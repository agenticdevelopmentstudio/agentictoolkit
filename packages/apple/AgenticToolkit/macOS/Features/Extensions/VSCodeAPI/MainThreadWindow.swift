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
public enum ExtensionMessageSeverity: Sendable, Equatable {
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

    /// The index into `itemTitles` of the item whose `isCloseAffordance` was
    /// truthy, or `nil` when none was — VS Code's rule for which item, if
    /// any, *is* the dismissal rather than one more button next to an
    /// implicit Cancel. See `NSAlertMessagePresenter.presentMessage(_:)` for
    /// what a presenter does with this.
    public let closeAffordanceIndex: Int?
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

    /// **The empty-items case (a single "OK" that resolves `nil`) is measured
    /// against upstream, not merely assumed:** with no items at all, VS
    /// Code's own `mainThreadMessageService.ts` shows a single **OK** that
    /// resolves `undefined` — exactly what this branch already did before
    /// this fix round, and is unchanged by it.
    public func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        let alert = NSAlert()
        alert.messageText = request.message
        if let detail = request.detail {
            alert.informativeText = detail
        }
        alert.alertStyle = NSAlertMessagePresenter.alertStyle(for: request.severity)

        guard !request.itemTitles.isEmpty else {
            alert.addButton(withTitle: "OK")
            _ = await presentedResponse(for: alert)
            return nil
        }

        let buttonItemIndices = NSAlertMessagePresenter.addButtons(for: request, to: alert)
        let response = await presentedResponse(for: alert)
        let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard buttonItemIndices.indices.contains(buttonIndex) else { return nil }
        return buttonItemIndices[buttonIndex]
    }

    /// Adds one button per item, **in order, skipping**
    /// `request.closeAffordanceIndex`, then one more button in the "cancel
    /// slot": that item's own title when there is a close affordance
    /// (answering its own index), otherwise `"Cancel"` (answering `nil`).
    ///
    /// This matches `mainThreadMessageService.ts`'s button construction
    /// exactly, measured against upstream during this fix round — including
    /// the detail that the close-affordance item is pulled **out of** the
    /// ordinary button list and put in the cancel slot; it does not render
    /// in its own item position, so button order and item order diverge
    /// whenever a close affordance is present. Returns, for each button
    /// added in order, the item index that button should resolve to (`nil`
    /// for the synthesized `"Cancel"`) — read back by position after
    /// `NSAlert` answers, rather than recovered with
    /// `response - .alertFirstButtonReturn` arithmetic read straight into
    /// `itemTitles`, which no longer holds once a button has been skipped.
    private static func addButtons(for request: ExtensionMessageRequest, to alert: NSAlert) -> [Int?] {
        var buttonItemIndices: [Int?] = []
        for (index, title) in request.itemTitles.enumerated() where index != request.closeAffordanceIndex {
            alert.addButton(withTitle: title)
            buttonItemIndices.append(index)
        }
        if let closeAffordanceIndex = request.closeAffordanceIndex {
            alert.addButton(withTitle: request.itemTitles[closeAffordanceIndex])
            buttonItemIndices.append(closeAffordanceIndex)
        } else {
            alert.addButton(withTitle: "Cancel")
            buttonItemIndices.append(nil)
        }
        return buttonItemIndices
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
    ///
    /// **No other `beginSheetModal` site under `macOS/` is bridged into a
    /// continuation** — measured by searching this tier: every other
    /// `beginSheetModal` call (`ComposableTabsPaneViewController`,
    /// `AISettingsViewPanelController`, `ExtensionsSettingsPanelViewController`,
    /// `NotesFolderListViewController`, `NotesSplitViewController`) drives its
    /// completion handler directly rather than bridging it into `async`.
    /// (`withCheckedContinuation`/`withCheckedThrowingContinuation` is not
    /// itself unprecedented in this tier — `ExtensionHost.swift` uses one for
    /// bridging a JS activation callback — so the narrower, accurate claim is
    /// about `beginSheetModal`/`NSAlert` sites specifically, not continuations
    /// in general.) The continuation is kept here anyway — it is what makes
    /// `presentMessage` itself `async`, matching `ExtensionMessagePresenting`
    /// — but nothing about it should be read as matching how this tier's
    /// other `NSAlert` call sites are written, because it does not.
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
    /// Argument shape, matching `extHostMessageService.ts` (confirmed against
    /// upstream during this fix round, not merely this task's original brief):
    /// 1. **argument 0 — the message.** Required; a missing argument 0
    ///    rejects. Present but not a string, it is coerced through
    ///    `coercedString(from:)`: a well-behaved `toString` is honoured, a
    ///    throwing or missing one rejects the call rather than presenting a
    ///    blank alert.
    /// 2. **argument 1 — options or the first item, by VS Code's actual rule
    ///    (`isMessageItem`): a string, or an object with a truthy `title`, is
    ///    an item; anything else — including an array, whose own `title` is
    ///    `undefined` — is read as options
    ///    (`{ modal?: boolean, detail?: string }`). See `isOptionsArgument`.
    /// 3. **the rest — items.** A string is its own title. An object with a
    ///    string `title` (VS Code's `MessageItem`) uses that title, and its
    ///    `isCloseAffordance` is recorded if truthy. Anything else rejects,
    ///    naming the offending argument's index — a silently dropped button
    ///    is worse than a rejected call.
    private func handleShowMessage(severity: ExtensionMessageSeverity, memberPath: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        guard let messageArgument = arguments.first else {
            return VSCodeAPI.rejectedPromise(
                message: "\(memberPath) requires a message argument.", in: context)
        }
        guard let message = MainThreadWindow.coercedString(from: messageArgument) else {
            return VSCodeAPI.rejectedPromise(
                message: "\(memberPath)'s argument 0 could not be converted to a string.", in: context)
        }

        var detail: String?
        var isModal = false
        var itemsStartIndex = 1
        if arguments.count > 1, MainThreadWindow.isOptionsArgument(arguments[1]) {
            let options = arguments[1]
            isModal = options.forProperty("modal")?.toBool() ?? false
            // A `nil` here — a missing `detail`, or one whose coercion
            // failed — is simply omitted: `detail` is optional decoration,
            // and rejecting the whole call over an unusable subtitle would
            // be worse than showing the message without one.
            if let detailValue = options.forProperty("detail"), !detailValue.isUndefined, !detailValue.isNull {
                detail = MainThreadWindow.coercedString(from: detailValue)
            }
            itemsStartIndex = 2
        }

        var itemTitles: [String] = []
        var itemValues: [JSValue] = []
        var closeAffordanceIndex: Int?
        for index in itemsStartIndex..<arguments.count {
            let item = arguments[index]
            if item.isString, let title = item.toString() {
                // A string item is never a close affordance — matching
                // `extHostMessageService.ts`'s own item loop, which
                // hard-codes `isCloseAffordance: false` for this branch.
                itemTitles.append(title)
                itemValues.append(item)
                continue
            }
            if item.isObject, let titleValue = item.forProperty("title"), titleValue.isString,
               let title = titleValue.toString() {
                itemTitles.append(title)
                itemValues.append(item)
                // Reading `isCloseAffordance` here can run an extension's own
                // getter — the same accepted, read-only risk named below for
                // `title` in `isOptionsArgument`, and the same precedent
                // `Uri.url(from:in:)`'s own doc names for its
                // `forProperty("toString")` read (`Uri.swift:352-358`),
                // bounded to the extension that wrote the getter acting on
                // its own context. First truthy one wins, matching upstream,
                // which warns and ignores a second one — this loop has no
                // logger to warn through, so it simply never overwrites an
                // index already recorded.
                if closeAffordanceIndex == nil,
                   let closeAffordanceValue = item.forProperty("isCloseAffordance"), closeAffordanceValue.toBool() {
                    closeAffordanceIndex = itemTitles.count - 1
                }
                continue
            }
            return VSCodeAPI.rejectedPromise(
                message: "\(memberPath)'s argument \(index) is neither a string nor an object " +
                    "with a string 'title'.",
                in: context)
        }

        let request = ExtensionMessageRequest(
            severity: severity, message: message, detail: detail, isModal: isModal, itemTitles: itemTitles,
            closeAffordanceIndex: closeAffordanceIndex)
        return presentMessagePromise(memberPath: memberPath, request: request, itemValues: itemValues, in: context)
    }

    /// Whether `value` — argument 1 of a `show*Message` call — is options
    /// rather than the first item, per VS Code's actual rule in
    /// `extHostMessageService.ts`'s `isMessageItem` (confirmed verbatim
    /// against upstream during this fix round): an item is a string, or an
    /// object with a **truthy** `title`; anything else in this position is
    /// options.
    ///
    /// Truthiness, not shape — and deliberately not the same bar as the
    /// item-collection loop below. `{ title: 42 }` classifies as an item
    /// here (`42` is truthy), then is correctly rejected by that loop's own,
    /// stricter, string-`title` requirement — which is strictly better than
    /// silently swallowing it as options, and is why that loop's string
    /// check must not change to match this one.
    ///
    /// **An array in this position has no `Array.isArray` carve-out** — VS
    /// Code's real code has none either. An array's own `title` is
    /// `undefined` (falsy), so it already falls out as options with no
    /// special-casing: this is deliberate parity with upstream, not an
    /// oversight, and nothing here should reintroduce an array check.
    private static func isOptionsArgument(_ value: JSValue) -> Bool {
        if value.isString { return false }
        guard value.isObject else { return true }
        // Reading `title` here can run an extension's own getter — the same
        // accepted, read-only risk `Uri.url(from:in:)`'s own doc names for
        // its `forProperty("toString")` read (`Uri.swift:352-358`), bounded
        // to the extension that wrote the getter acting on its own context.
        guard let titleValue = value.forProperty("title") else { return true }
        return !titleValue.toBool()
    }

    /// Coerces `value` to a `String`, used for both the message and `detail`
    /// arguments of a `show*Message` call.
    ///
    /// **What this replaces, and why:** this task's original round called
    /// `value.toString()` — JavaScriptCore's own, unguarded conversion —
    /// directly on any non-string argument, with its doc comment claiming
    /// that matched how `Uri.url(from:in:)` treats a `Uri | string` argument.
    /// That claim was false: `Uri.url(from:in:)` (`Uri.swift:359-375`) calls
    /// `.toString()` unguarded **only inside `if value.isString`** — it never
    /// runs arbitrary extension code that way — and routes the real
    /// `toString` *invocation* for a non-string value through the guarded
    /// `VSCodeAPI.call` trampoline. This helper now does exactly that, for
    /// both branches:
    /// - `value.isString` → `value.toString()`, matching `Uri.url(from:in:)`'s
    ///   own string branch precisely.
    /// - otherwise → `toString` is read via `forProperty` (an accepted,
    ///   read-only risk — the same one named in `isOptionsArgument` above)
    ///   and, only if it is itself an object, invoked through
    ///   `VSCodeAPI.call(_:thisArg:arguments:)`. Only `case .returned(let
    ///   result)` with `result.isString` counts as success.
    ///
    /// **Why the guard matters:** measured in this fix round (via `pyobjc`
    /// driving `JavaScriptCore.framework` directly): for an object whose
    /// `toString` throws, `JSValue.toString()` returns `nil` **and leaves
    /// `context.exception` set**. Unguarded, `?? ""` would swallow the
    /// failure — an alert with a blank `messageText` still reaches the
    /// screen — while the pending exception is separately routed by
    /// `ExtensionHost.makeContext()`'s `context.exceptionHandler`
    /// (`ExtensionHost.swift:896`) into `pendingException`, which
    /// `callActivate` reads: an extension calling this during `activate()`
    /// could fail its own activation naming an unrelated cause.
    /// `VSCodeAPI.call` exists precisely to keep a thrown exception from
    /// escaping into that path (`VSCodeAPI.swift:300-320`), which is why the
    /// non-string branch goes through it rather than calling `toString()`
    /// directly.
    ///
    /// `nil` covers a throw, a non-string return, and a missing or
    /// non-callable `toString` alike — callers decide what `nil` means for
    /// their own argument (the message rejects the call; `detail` is simply
    /// omitted).
    private static func coercedString(from value: JSValue) -> String? {
        if value.isString {
            return value.toString()
        }
        guard let toStringFunction = value.forProperty("toString"), toStringFunction.isObject else {
            return nil
        }
        guard case .returned(let result) = VSCodeAPI.call(toStringFunction, thisArg: value, arguments: []),
              let result, result.isString else {
            return nil
        }
        return result.toString()
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
            // `valueWithNewPromiseInContext:fromExecutor:` declares both
            // executor arguments `_Null_unspecified`, so Swift types them
            // `JSValue?` here. JavaScriptCore always supplies both; with
            // either missing there is nothing to settle the promise through,
            // so the only honest answer is to leave it pending.
            guard let resolveValue, let rejectValue else { return }
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
