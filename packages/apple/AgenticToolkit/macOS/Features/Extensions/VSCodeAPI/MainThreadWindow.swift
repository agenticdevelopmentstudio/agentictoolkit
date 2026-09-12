//
//  MainThreadWindow.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - The presentation seam

/// How urgently a `vscode.window.show*Message` call wants to be noticed.
public enum ExtensionMessageSeverity: Sendable {
    case information, warning, error
}

/// One `vscode.window.show*Message` call, reduced to what a presenter needs
/// to show something and report back which button — if any — the user chose.
public struct ExtensionMessageRequest: Sendable {
    public let severity: ExtensionMessageSeverity
    public let message: String
    public let detail: String?
    public let isModal: Bool
    public let itemTitles: [String]
}

/// What `MainThreadWindow` depends on instead of AppKit directly, so the
/// adaptor's argument parsing and promise settlement are testable with no UI
/// — the same move `FileSystemServicing` made for `MainThreadWorkspace`'s
/// `fs`, and the same placement `ExtensionWorkspaceRoots` uses: declared
/// beside the one consumer that needs it, in the same file, rather than
/// anticipating a tier split before a second conformer exists.
///
/// `@MainActor`, matching every other type in this directory: nothing here is
/// ever read off the main actor.
@MainActor
public protocol ExtensionMessagePresenting: AnyObject {

    /// The index into `request.itemTitles` of the button the user chose, or
    /// `nil` if they dismissed it. Always `nil` when `itemTitles` is empty.
    func presentMessage(_ request: ExtensionMessageRequest) async -> Int?
}

// MARK: - The AppKit conformer

/// Presents a `vscode.window.show*Message` request with `NSAlert`.
///
/// **Presentation rule, decided here:** a sheet
/// (`beginSheetModal(for:completionHandler:)`) when `window()` answers a real
/// window, and an app-modal `runModal()` when it answers `nil`. This is a
/// menu-bar app — having no window is the ordinary case, not the edge — so
/// the window this presenter attaches to is read from a `() -> NSWindow?`
/// this type is initialised with, rather than guessed at from
/// `NSApplication.shared` or some other ambient source, and the no-window
/// fallback is written out below rather than left to whatever `NSAlert`
/// happens to do when handed no window at all.
///
/// **Hazard, stated rather than designed away:** the app-modal branch
/// (`runModal()`) blocks the main thread until the user responds. An
/// extension that calls `showInformationMessage` while no window is
/// available — the ordinary case for this app — can wedge the whole app's UI
/// until someone dismisses the alert. That is a genuine cost of giving
/// extensions `showInformationMessage` at all, not an oversight in this
/// conformer, and the next person changing this file needs to find it
/// stated rather than rediscover it.
///
/// **`request.isModal == false` is presented modally anyway.** Real VS Code
/// shows a non-modal message as a notification toast; this repo has no toast
/// primitive today, and inventing one is outside this task. `isModal` is
/// carried on `ExtensionMessageRequest` truthfully, so a later, non-modal
/// presenter can honour it — this conformer does not, and does not pretend
/// to.
@MainActor
public final class NSAlertMessagePresenter: ExtensionMessagePresenting {

    /// Where to attach a sheet, or `nil` to fall back to an app-modal alert.
    /// Called fresh at presentation time rather than cached, so this answers
    /// with whatever window is frontmost when the extension actually asks,
    /// not whatever was frontmost when this presenter was constructed.
    private let window: () -> NSWindow?

    /// - Parameter window: Not defaulted, deliberately: see this type's own
    ///   doc for why the no-window fallback must be an explicit choice a
    ///   caller made, rather than an incidental default this initialiser
    ///   picked for it.
    public init(window: @escaping () -> NSWindow?) {
        self.window = window
    }

    public func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        let alert = NSAlert()
        alert.messageText = request.message
        if let detail = request.detail {
            alert.informativeText = detail
        }
        alert.alertStyle = NSAlertMessagePresenter.alertStyle(for: request.severity)
        if request.itemTitles.isEmpty {
            alert.addButton(withTitle: "OK")
        } else {
            for title in request.itemTitles {
                alert.addButton(withTitle: title)
            }
        }

        let response = await presentedResponse(for: alert)
        guard !request.itemTitles.isEmpty else { return nil }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return request.itemTitles.indices.contains(index) ? index : nil
    }

    /// `.information → .informational`, `.warning → .warning`,
    /// `.error → .critical` — the mapping this task's brief specifies.
    private static func alertStyle(for severity: ExtensionMessageSeverity) -> NSAlert.Style {
        switch severity {
        case .information: return .informational
        case .warning: return .warning
        case .error: return .critical
        }
    }

    /// A sheet when `window()` answers one, an app-modal alert otherwise —
    /// see this type's own doc for the reasoning and for the hazard the
    /// app-modal branch carries.
    private func presentedResponse(for alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window = window() else {
            return alert.runModal()
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}

// MARK: - The adaptor

/// The `vscode.window` adaptor's first slice: `showInformationMessage`,
/// `showWarningMessage` and `showErrorMessage`, each terminating in whatever
/// `ExtensionMessagePresenting` this adaptor was built with rather than in
/// AppKit directly.
///
/// **One instance per extension**, mirroring `MainThreadCommands` and
/// `MainThreadWorkspace`. Nothing enforces it, but every ownership question
/// below — and `isDisposed`'s meaning — is answered as if it holds.
///
/// **`notImplementedLedger` and `extensionIdentifier` are stored but unused
/// by this task's three members.** They mirror `MainThreadWorkspace.init`'s
/// shape and exist so `showQuickPick`/`showInputBox` (5.5b) and
/// `createStatusBarItem` (5.5c) — the next two slices of this same seam —
/// have them already in hand rather than each adding its own constructor
/// parameter later. Nothing here builds a `VSCodeAPI.subNamespace` the way
/// `MainThreadWorkspace.fs` does, so nothing here has a miss to record yet.
///
/// **Whoever owns this adaptor must call `dispose()` when it tears the
/// extension host down.** A presentation started before that point keeps
/// running — there is no way to cancel an alert already on screen, and no
/// reason to: the user's answer is harmless to finish computing — but
/// `dispose()` means that answer is never delivered to a torn-down extension.
///
/// `@MainActor` for the reason every adaptor in this directory is: `JSValue`
/// is not `Sendable`, and every block below runs on the thread that made the
/// call, which for this host is always the main actor.
@MainActor
public final class MainThreadWindow {

    /// Where a `show*Message` call actually puts something on screen (or, in
    /// a test, records what it was asked to show).
    private let presenter: ExtensionMessagePresenting

    /// Where a reach for an undefined `window` member is recorded. Stored for
    /// the reason this type's own doc gives — not read by this task's three
    /// members.
    private let notImplementedLedger: NotImplementedLedger

    /// The extension this adaptor belongs to. Stored for the same reason as
    /// `notImplementedLedger`.
    private let extensionIdentifier: String

    /// Set by `dispose()`. Checked before a presentation begins and again
    /// after the presenter's `await` returns, so a presentation that outlives
    /// its host answers with a rejection instead of delivering a result — or
    /// crashing — into a torn-down extension.
    private var isDisposed = false

    /// Carries a promise's `resolve`/`reject` `JSValue`s into a `Task`, on the
    /// same terms as `MainThreadWorkspace`'s own `SettlementBox`: nothing here
    /// actually crosses an isolation domain — the `Task` below reads both
    /// values back on the same main actor that created them — but a bare
    /// `JSValue` is not `Sendable` and is not a type this module can extend
    /// with a conformance, so this box states the guarantee explicitly rather
    /// than reaching for a broader escape hatch.
    private struct SettlementBox: @unchecked Sendable {
        let resolve: JSValue
        let reject: JSValue
    }

    /// - Parameters:
    ///   - presenter: Where a `show*Message` call is actually presented. Not
    ///     defaulted: a caller that forgot to pass a real presenter would
    ///     otherwise get no default AppKit behaviour to fall back on — there
    ///     is no "do nothing" presenter that would be safe to default to.
    ///   - notImplementedLedger: Mirrors `MainThreadWorkspace.init`'s
    ///     parameter of the same name. See this type's own doc for why it is
    ///     unused today.
    ///   - extensionIdentifier: Mirrors `MainThreadWorkspace.init`'s parameter
    ///     of the same name; unused today for the same reason.
    public init(
        presenter: ExtensionMessagePresenting,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String
    ) {
        self.presenter = presenter
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
    }

    // MARK: - vscode.window.showInformationMessage / showWarningMessage / showErrorMessage

    /// `implementation` for `vscode.window.showInformationMessage`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is.
    public private(set) lazy var showInformationMessage: Any = VSCodeAPI.member(
        "vscode.window.showInformationMessage", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleShowMessage(severity: .information, memberPath: "vscode.window.showInformationMessage") }

    /// `implementation` for `vscode.window.showWarningMessage`.
    public private(set) lazy var showWarningMessage: Any = VSCodeAPI.member(
        "vscode.window.showWarningMessage", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleShowMessage(severity: .warning, memberPath: "vscode.window.showWarningMessage") }

    /// `implementation` for `vscode.window.showErrorMessage`.
    public private(set) lazy var showErrorMessage: Any = VSCodeAPI.member(
        "vscode.window.showErrorMessage", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleShowMessage(severity: .error, memberPath: "vscode.window.showErrorMessage") }

    /// Rejects rather than raises on a torn-down adaptor: all three members
    /// return a `Thenable`, matching `MainThreadWorkspace`'s `fs` operations
    /// and `MainThreadCommands.executeCommand`.
    ///
    /// Argument shape, per this task's brief:
    /// 1. **argument 0 — the message.** Required; a missing argument 0
    ///    rejects. Present but not a string, it is coerced through its own
    ///    JavaScript string conversion (`JSValue.toString()`), the same
    ///    treatment `Uri.url(from:in:)` gives a `Uri | string` argument that
    ///    turns out to be a plain string.
    /// 2. **argument 1 — options**, read as `{ modal?: boolean, detail?:
    ///    string }` only when it is an object that is neither a string nor an
    ///    array. Anything else in that position is the first item.
    /// 3. **the rest — items.** A string is its own title. An object with a
    ///    string `title` (VS Code's `MessageItem`) uses that title. Anything
    ///    else rejects, naming the offending argument's index — a silently
    ///    dropped button is worse than a rejected call.
    private func handleShowMessage(severity: ExtensionMessageSeverity, memberPath: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        guard let messageArgument = arguments.first else {
            return VSCodeAPI.rejectedPromise(
                message: "\(memberPath) requires a message argument.", in: context)
        }
        let message = messageArgument.toString() ?? ""

        var detail: String?
        var isModal = false
        var itemsStartIndex = 1
        if arguments.count > 1, MainThreadWindow.isOptionsArgument(arguments[1], in: context) {
            let options = arguments[1]
            isModal = options.forProperty("modal")?.toBool() ?? false
            if let detailValue = options.forProperty("detail"), detailValue.isString {
                detail = detailValue.toString()
            }
            itemsStartIndex = 2
        }

        var itemTitles: [String] = []
        var itemValues: [JSValue] = []
        for index in itemsStartIndex..<arguments.count {
            let item = arguments[index]
            if item.isString, let title = item.toString() {
                itemTitles.append(title)
                itemValues.append(item)
                continue
            }
            if item.isObject, let titleValue = item.forProperty("title"), titleValue.isString,
               let title = titleValue.toString() {
                itemTitles.append(title)
                itemValues.append(item)
                continue
            }
            return VSCodeAPI.rejectedPromise(
                message: "\(memberPath)'s argument \(index) is neither a string nor an object " +
                    "with a string 'title'.",
                in: context)
        }

        let request = ExtensionMessageRequest(
            severity: severity, message: message, detail: detail, isModal: isModal, itemTitles: itemTitles)
        return presentMessagePromise(memberPath: memberPath, request: request, itemValues: itemValues, in: context)
    }

    /// Whether `value` — argument 1 of a `show*Message` call — is options
    /// rather than the first item: an object that is neither a string nor an
    /// array, matching this task's brief exactly.
    private static func isOptionsArgument(_ value: JSValue, in context: JSContext) -> Bool {
        value.isObject && !value.isString && !isArrayArgument(value, in: context)
    }

    /// `value instanceof Array`, checked the same way `MainThreadCommands`
    /// checks `callback instanceof Function`: there is only ever one realm in
    /// a context this host builds, so the cross-realm gap that check's own
    /// comment names does not apply here either.
    private static func isArrayArgument(_ value: JSValue, in context: JSContext) -> Bool {
        guard let arrayConstructor = context.objectForKeyedSubscript("Array") else { return false }
        return value.isInstance(of: arrayConstructor)
    }

    // MARK: - The promise bridge

    /// Builds a genuinely-pending `Thenable`, presents `request` in a `Task`,
    /// and settles the promise on the main actor once the presenter answers.
    ///
    /// **The return is an index, not a title, and that is load-bearing.** VS
    /// Code resolves `showInformationMessage` with *the same value the caller
    /// passed in* — so an extension passing `{ title: 'Undo' }` gets that
    /// object back and can compare it by identity. `itemValues[chosenIndex]`
    /// is what lets this hand back the original `JSValue`, including for two
    /// items that happen to share a title; resolving with a re-matched title
    /// instead would collapse that case onto the wrong item, or an arbitrary
    /// one of the two.
    ///
    /// Checked twice for teardown, mirroring `MainThreadWorkspace`'s
    /// `runFileSystemOperation`: once before `presenter.presentMessage` is
    /// ever awaited (the adaptor may already be disposed by the time this
    /// `Task` gets its first turn), and once after it returns (disposed while
    /// the presentation was on screen). The second check is spelled as
    /// `guard !self.isDisposed, …` — reading the property directly off the
    /// `self` the first `guard let self` already bound, not re-binding it —
    /// because `self` is a non-optional `let` by that point and a second
    /// `guard let self` there does not compile; this is the exact shape a
    /// 5.4c fix round had to correct.
    private func presentMessagePromise(
        memberPath: String,
        request: ExtensionMessageRequest,
        itemValues: [JSValue],
        in context: JSContext
    ) -> JSValue? {
        JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            let settlement = SettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: memberPath)
                    return
                }
                let chosenIndex = await self.presenter.presentMessage(request)
                guard !self.isDisposed, let resultContext = settlement.resolve.context else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: memberPath)
                    return
                }
                guard let chosenIndex, itemValues.indices.contains(chosenIndex) else {
                    settlement.resolve.call(withArguments: [MainThreadWindow.undefinedValue(in: resultContext)])
                    return
                }
                settlement.resolve.call(withArguments: [itemValues[chosenIndex]])
            }
        }
    }

    /// Rejects `reject` with the same wording `VSCodeAPI.member`'s own
    /// teardown path uses, matching `MainThreadWorkspace.rejectTornDown`.
    private static func rejectTornDown(_ reject: JSValue, path: String) {
        guard let context = reject.context,
              let errorValue = JSValue(
                newErrorFromMessage: "\(path) is unavailable: this extension's host has been torn down.",
                in: context) else {
            return
        }
        reject.call(withArguments: [errorValue])
    }

    /// A genuine JavaScript `undefined`, matching
    /// `MainThreadWorkspace.undefinedValue(in:)`.
    private static func undefinedValue(in context: JSContext) -> Any {
        if let value = JSValue(undefinedIn: context) {
            return value
        }
        return NSNull()
    }

    // MARK: - Teardown

    /// Marks this adaptor torn down. A presentation already in flight rejects
    /// rather than delivering a result; see this type's own doc.
    public func dispose() {
        isDisposed = true
    }
}

extension MainThreadWindow: Loggable {

    /// This adaptor's own log destination, matching `MainThreadCommands` and
    /// `MainThreadWorkspace`. Unused by this task's three members — there is
    /// nothing here yet that fails in a way only a log line can report — kept
    /// for the same reason `notImplementedLedger` is: 5.5b/5.5c extend this
    /// same class.
    public static nonisolated let logger = makeLogger()
}
