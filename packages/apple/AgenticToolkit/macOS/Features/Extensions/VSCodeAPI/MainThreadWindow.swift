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

    /// Every index into `itemTitles` whose item carried a truthy
    /// `isCloseAffordance`, in item order — empty when none did. VS Code's
    /// rule for which item, if any, *is* the dismissal rather than one more
    /// button next to an implicit Cancel.
    ///
    /// A list rather than one index, because upstream keeps the flag on
    /// **every** item that set it. `extHostMessageService.ts` logs
    /// `Only one message item can have 'isCloseAffordance'` for the second
    /// and later ones but still pushes `isCloseAffordance: !!isCloseAffordance`
    /// for each, and `mainThreadMessageService.ts` then routes every flagged
    /// command to `cancelButton = button` — so each one is kept out of the
    /// ordinary button list and the **last** overwrites the cancel slot.
    /// Modelling only the first made a second flagged item render as an
    /// ordinary button, which upstream never does. See
    /// `NSAlertMessagePresenter.presentMessage(_:)` for what a presenter does
    /// with this.
    public let closeAffordanceIndices: [Int]
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

/// One item of a `vscode.window.showQuickPick` call, reduced to what a
/// presenter needs to render a row and report which rows the user chose.
///
/// **`iconPath`, `resourceUri` and `buttons` are deliberately not carried,**
/// and that is a decision rather than an omission. `buttons` because the
/// declaration says they are not rendered by this API at all — "Buttons are
/// only rendered when using a quick pick created by the
/// {@link window.createQuickPick createQuickPick} API. Buttons are not
/// rendered when using the {@link window.showQuickPick showQuickPick} API"
/// (`vscode.d.ts:1979-1981`). `iconPath` and `resourceUri` because nothing in
/// this repo resolves an extension-supplied icon path to an image, and a
/// field that is always dropped is worse than an absent one: it reads to the
/// next person as a capability that exists.
public struct ExtensionQuickPickItem: Sendable, Equatable {

    /// The row's text. The only property `QuickPickItem` declares
    /// non-optional (`vscode.d.ts:1907`), and the only one that applies to a
    /// separator.
    public let label: String

    /// Rendered less prominently on the same line (`vscode.d.ts:1929`), or
    /// `nil` when the item carried none — or carried one that was not a
    /// string, which is omitted rather than rejected, on the same terms
    /// `handleShowMessage` omits an unusable `detail`.
    public let description: String?

    /// Rendered less prominently on a separate line (`vscode.d.ts:1939`), or
    /// `nil` on the same terms as `description`.
    public let detail: String?

    /// The item's `kind` was `QuickPickItemKind.Separator` — the number `-1`
    /// (`vscode.d.ts:1886`) — so it is a visual grouping rather than a
    /// selectable row.
    ///
    /// Every other property of a separator is left at its default here,
    /// because the declaration says so: "The only property that applies is
    /// {@link QuickPickItem.label label}. All other properties on
    /// {@link QuickPickItem} will be ignored and have no effect"
    /// (`vscode.d.ts:1881-1884`).
    public let isSeparator: Bool

    /// The item carried a truthy `picked` (`vscode.d.ts:1966`): it should
    /// start out selected.
    ///
    /// **Carried truthfully whatever `canPickMany` says.** The declaration's
    /// rule — "This is only honored when the picker allows multiple
    /// selections" (`vscode.d.ts:1959`) — is the presenter's to apply, not
    /// the parser's. A parser that zeroed this out would leave the presenter
    /// unable to tell "the extension did not ask for this row" from "the
    /// extension asked and something upstream discarded it".
    public let isPicked: Bool

    /// The item carried a truthy `alwaysShow` (`vscode.d.ts:1974`): keep the
    /// row visible even when the user's filter text would exclude it.
    ///
    /// Nothing in this task reads it. `MainThreadWindow` puts it on the
    /// request and stops there, and this task builds no conformer of
    /// `ExtensionQuickPickPresenting` at all; task 5.5b-iv is the task that
    /// builds one, and filtering is that panel's job.
    public let alwaysShow: Bool

    /// Spelled out rather than synthesised: this type is `public`, so the
    /// memberwise initialiser would be `internal` and a test in another
    /// module could not call it.
    public init(
        label: String,
        description: String?,
        detail: String?,
        isSeparator: Bool,
        isPicked: Bool,
        alwaysShow: Bool
    ) {
        self.label = label
        self.description = description
        self.detail = detail
        self.isSeparator = isSeparator
        self.isPicked = isPicked
        self.alwaysShow = alwaysShow
    }
}

/// One `vscode.window.showQuickPick` call, reduced to what a presenter needs
/// to show a picker and report back which rows — if any — the user chose.
public struct ExtensionQuickPickRequest: Sendable, Equatable {

    /// `QuickPickOptions.title` (`vscode.d.ts:1997`), or `nil`.
    public let title: String?

    /// `QuickPickOptions.placeHolder` (`vscode.d.ts:2012`) — placeholder text
    /// for the filter field — or `nil`.
    public let placeHolder: String?

    /// `QuickPickOptions.prompt` (`vscode.d.ts:2019`), or `nil`.
    ///
    /// **Carried, and read by nothing this task builds.** The declaration
    /// says it is "displayed below the input box and above the list of items"
    /// (`vscode.d.ts:2017`) and upstream forwards it to the renderer as one
    /// more field of the `$show` payload (`extHostQuickOpen.ts:72`); what a
    /// renderer does with it is the renderer's business, and this host has no
    /// renderer for it. The field records what the extension asked for.
    public let prompt: String?

    /// The items, in the order the extension supplied them — separators
    /// included, at their own positions. Indices into this array are the
    /// whole vocabulary `ExtensionQuickPickPresenting` answers in.
    public let items: [ExtensionQuickPickItem]

    /// `QuickPickOptions.canPickMany` (`vscode.d.ts:2030`): the user may
    /// accept more than one row, and "the result is an array of picks".
    public let canPickMany: Bool

    /// `QuickPickOptions.matchOnDescription` (`vscode.d.ts:2002`): include
    /// each item's `description` when filtering. Documented default `false`.
    public let matchOnDescription: Bool

    /// `QuickPickOptions.matchOnDetail` (`vscode.d.ts:2007`): include each
    /// item's `detail` when filtering. Documented default `false`.
    public let matchOnDetail: Bool

    /// `QuickPickOptions.ignoreFocusOut` (`vscode.d.ts:2025`): keep the
    /// picker open when focus moves elsewhere.
    public let ignoreFocusOut: Bool

    /// Spelled out for `ExtensionQuickPickItem.init`'s reason: a `public`
    /// type's synthesised memberwise initialiser is `internal`, and this
    /// one's callers include a test module.
    public init(
        title: String?,
        placeHolder: String?,
        prompt: String?,
        items: [ExtensionQuickPickItem],
        canPickMany: Bool,
        matchOnDescription: Bool,
        matchOnDetail: Bool,
        ignoreFocusOut: Bool
    ) {
        self.title = title
        self.placeHolder = placeHolder
        self.prompt = prompt
        self.items = items
        self.canPickMany = canPickMany
        self.matchOnDescription = matchOnDescription
        self.matchOnDetail = matchOnDetail
        self.ignoreFocusOut = ignoreFocusOut
    }
}

/// Where a `vscode.window.showQuickPick` call actually puts a picker on
/// screen (or, in a test, records what it was asked to show).
///
/// **A separate protocol from `ExtensionMessagePresenting`, deliberately.**
/// `NSAlertMessagePresenter` below is the right conformer for a message and
/// the wrong one for a picker; one protocol carrying both members would force
/// it to implement a presentation it has no business showing. Interface
/// segregation, and the cost is that `MainThreadWindow.init` takes two
/// presenters rather than one.
///
/// Declared in this file rather than a new one, and beside its one consumer
/// rather than in a lower tier — the placement `ExtensionMessagePresenting`
/// above already uses, and `ExtensionWorkspaceRoots`
/// (`MainThreadWorkspace.swift:28`) before it: no tier split before a second
/// consumer exists.
///
/// **No type in this module conforms to it.** That is this task's deliberate,
/// temporary state: task 5.5b-iv builds one panel serving both this seam and
/// `showInputBox`'s, and a panel written now against one of the two is how it
/// ends up unable to serve the other.
///
/// `@MainActor`, matching every other type in this directory.
@MainActor
public protocol ExtensionQuickPickPresenting: AnyObject {

    /// Shows `request` and answers **indices into `request.items`**.
    ///
    /// Indices, never labels. VS Code resolves `showQuickPick` with the
    /// original value the caller passed — `items[handle]` for single select,
    /// `handle.map(h => items[h])` for multi (`extHostQuickOpen.ts:125-131`)
    /// — so two items sharing a label have to stay distinguishable, and only
    /// a position distinguishes them.
    ///
    /// **`nil` means dismissed. An empty array does not.** With
    /// `request.canPickMany` a user can accept a selection of nothing, and
    /// upstream's `handle.map(…)` of an empty handle array resolves `[]`
    /// rather than `undefined` (`extHostQuickOpen.ts:128-129`). A conformer
    /// that answers `[]` for a dismissal tells the extension the user
    /// accepted an empty selection, which is a different answer.
    ///
    /// Single select answers a **one-element array**, not a bare `Int`: one
    /// return type for both modes, because `canPickMany` is a field of the
    /// request every conformer already reads, and two overloads would make
    /// each conformer spell the dismissal rule twice.
    ///
    /// - Parameters:
    ///   - request: What to show.
    ///   - onHighlight: Called with an index into `request.items` each time
    ///     the highlighted row changes. This is what VS Code's
    ///     `QuickPickOptions.onDidSelectItem` (`vscode.d.ts:2035`) is built
    ///     on, and upstream fires it from the widget's `onDidFocus`
    ///     (`mainThreadQuickOpen.ts:63-67`) rather than on acceptance. It may
    ///     be called any number of times, including zero, and must not be
    ///     called after `presentQuickPick` has returned.
    /// - Returns: The chosen indices, in the order the selection should be
    ///   reported to the extension, or `nil` if the picker was dismissed.
    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]?
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

    /// The position→item mapping `addButtons(for:to:)` renders, split out as a
    /// pure function of the request so it can be pinned without an `NSAlert`:
    /// one entry per button, in add order, holding the item index that button
    /// resolves to, and `nil` for the synthesized `"Cancel"`.
    ///
    /// **`internal`, not `private`, deliberately.** `MainThreadWindowTests`
    /// calls this directly through `@testable import AgenticToolkitMacOS`;
    /// tightening it to `private` compiles here and breaks that suite.
    ///
    /// Going through `presentMessage` instead is not a substitute for that
    /// direct call: it indexes the plan and returns a single item index
    /// rather than the plan itself, and it reaches that point only after
    /// awaiting `presentedResponse(for:)`, which runs
    /// `beginSheetModal(for:completionHandler:)` or `runModal()`.
    ///
    /// Entries come out in item order, **skipping every index in**
    /// `request.closeAffordanceIndices`, then one more for the "cancel slot":
    /// the **last** flagged item's index when there is a close affordance,
    /// otherwise `nil`. Last wins because upstream's loop assigns
    /// `cancelButton = button` for each flagged command in turn
    /// (`mainThreadMessageService.ts:120-124`), so an earlier one is
    /// overwritten and never rendered at all.
    ///
    /// This matches **`_showModalMessage`**'s button construction exactly
    /// (`mainThreadMessageService.ts:110-148`), measured against upstream
    /// during this fix round — including the detail that the close-affordance
    /// item is pulled **out of** the ordinary button list and put in the
    /// cancel slot; it does not render in its own item position, so button
    /// order and item order diverge whenever a close affordance is present.
    /// Naming the function matters because the same file builds buttons a
    /// second way in `_showMessage` (lines 54-108, the non-modal path), where
    /// every command — flagged or not — becomes a primary action
    /// (`commands.map(command => toAction(…))`, line 58) and there is no
    /// cancel button at all. Read against *that* function the claim is false,
    /// so a later non-modal presenter must not cite this as its precedent.
    static func buttonPlan(for request: ExtensionMessageRequest) -> [Int?] {
        var plan: [Int?] = []
        let closeAffordanceIndices = Set(request.closeAffordanceIndices)
        for index in request.itemTitles.indices where !closeAffordanceIndices.contains(index) {
            plan.append(index)
        }
        // The cancel slot: the last flagged item's index, or `nil` for the
        // synthesized `"Cancel"` when no item carries a close affordance.
        plan.append(request.closeAffordanceIndices.last)
        return plan
    }

    /// The position in a `buttonPlan(for:)` result that should be given
    /// Escape explicitly — the cancel slot, `plan.count - 1` — or `nil` when
    /// no button should be given it, which is a plan of one entry or none.
    ///
    /// **`internal`, not `private`, deliberately,** for the same reason as
    /// `buttonPlan(for:)`: `MainThreadWindowTests` calls this directly
    /// through `@testable import AgenticToolkitMacOS`, and tightening it to
    /// `private` compiles here and breaks that suite.
    ///
    /// **Why one entry is the exception.** The cancel slot is always the
    /// plan's last entry, so with two or more entries it is never the *first*
    /// button and Escape costs nothing. With exactly one entry that slot is
    /// also the first button, and two header facts collide: `NSAlert.h:96`,
    /// the doc on `-addButtonWithTitle:`, gives the first button a key
    /// equivalent of Return by default, while `NSButton.h:164` says
    /// `keyEquivalent` is a single `NSString` — "Setting the key equivalent to
    /// the Return character causes it to act as the default button for its
    /// window." Assigning Escape therefore *replaces* Return, and the
    /// default-button status with it. Nothing is bought by the trade: a
    /// one-entry plan means no item survived the skip, so — `presentMessage`
    /// having already short-circuited on empty `itemTitles` — every item is
    /// flagged and the only button *is* the close affordance. Return on it
    /// already produces the outcome Escape would.
    static func escapeKeyEquivalentPosition(in plan: [Int?]) -> Int? {
        plan.count > 1 ? plan.count - 1 : nil
    }

    /// Adds one button per `buttonPlan(for:)` entry, in plan order — the
    /// item's own title for an entry naming an item, `"Cancel"` for the `nil`
    /// entry — and returns that plan unchanged. `presentMessage` reads the
    /// chosen item back by button position, rather than with
    /// `response - .alertFirstButtonReturn` arithmetic read straight into
    /// `itemTitles`, which no longer holds once a button has been skipped.
    ///
    /// **The final button — always the cancel slot — is given Escape
    /// explicitly, but only when there is more than one button:**
    /// `escapeKeyEquivalentPosition(in:)` decides, because on a one-button
    /// alert that slot is also the first button and the assignment would take
    /// away the Return it has by default (see that function's doc).
    /// `NSAlert.h:96`, the doc on `-addButtonWithTitle:`, gives
    /// Escape only to a button whose *title* is "Cancel", so the
    /// close-affordance path, where the slot carries the flagged item's own
    /// title, would otherwise have no Escape at all — and that is the path
    /// this whole seam exists for. Upstream puts the flagged command in the
    /// dialog's `cancelButton` argument rather than in `buttons`
    /// (`mainThreadMessageService.ts:146`). Setting it on the synthesized
    /// `"Cancel"` too changes no behaviour — AppKit gives that one Escape by
    /// title anyway — but stating the intent in code is what stops the next
    /// person renaming the string and silently losing Escape. The button to
    /// set it on is the one `addButtonWithTitle:` returns (same header,
    /// `- Returns: The button that was added to the alert.`).
    private static func addButtons(for request: ExtensionMessageRequest, to alert: NSAlert) -> [Int?] {
        let plan = buttonPlan(for: request)
        let escapePosition = escapeKeyEquivalentPosition(in: plan)
        for (position, itemIndex) in plan.enumerated() {
            let title = itemIndex.map { request.itemTitles[$0] } ?? "Cancel"
            let button = alert.addButton(withTitle: title)
            if position == escapePosition {
                button.keyEquivalent = "\u{1b}"
            }
        }
        return plan
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

/// The `vscode.window` adaptor: `showInformationMessage`,
/// `showWarningMessage` and `showErrorMessage` (task 5.5a), each terminating
/// in whatever `ExtensionMessagePresenting` this adaptor was built with
/// rather than in AppKit directly, and `showQuickPick` (task 5.5b-ii),
/// terminating in an `ExtensionQuickPickPresenting` instead — a second seam,
/// for the reason that protocol's own doc gives.
///
/// **One instance per extension**, mirroring `MainThreadCommands` and
/// `MainThreadWorkspace`. Nothing enforces it, but every ownership question
/// below — and `isDisposed`'s meaning — is answered as if it holds.
///
/// **`notImplementedLedger` and `extensionIdentifier` are stored and read by
/// no member on this type.** They mirror `MainThreadWorkspace.init`'s
/// shape and exist so `showInputBox` (5.5b-iii) and
/// `createStatusBarItem` (5.5c) — the next slices of this same seam —
/// have them already in hand rather than each adding its own constructor
/// parameter later. Nothing here builds a `VSCodeAPI.subNamespace` the way
/// `MainThreadWorkspace.fs` does, so nothing here has a miss to record yet.
/// `showQuickPick`'s ignored cancellation token is deliberately **not**
/// recorded either: a `NotImplementedAccess` is "One VS Code API member an
/// extension reached for that this host does not implement yet"
/// (`NotImplementedLedger.swift:8-9`) whose `memberPath` is "Exactly the
/// string the thrown JavaScript error names" (`:25-26`), and nothing is
/// thrown here — recording `vscode.window.showQuickPick` would make task
/// 5.8's report tell a user that a member which works does not exist. A
/// degraded *argument* is not an absent *member*.
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

    /// Where a `showQuickPick` call actually puts a picker on screen (or, in
    /// a test, records what it was asked to show). A second presenter rather
    /// than two members on one protocol — see `ExtensionQuickPickPresenting`'s
    /// own doc for why.
    private let quickPickPresenter: ExtensionQuickPickPresenting

    /// Where a reach for an undefined `window` member is recorded. Stored for
    /// the reason this type's own doc gives — not read by any member on this
    /// type.
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
    ///   - quickPickPresenter: Where a `showQuickPick` call is actually
    ///     presented. Not defaulted, for `presenter:`'s own reason: a picker
    ///     that silently answered "dismissed" would tell every extension the
    ///     user refused something they were never shown, so there is no "do
    ///     nothing" presenter to default to here either. No type in this
    ///     module conforms to `ExtensionQuickPickPresenting` yet, so every
    ///     conformer today is a test double.
    ///   - notImplementedLedger: Mirrors `MainThreadWorkspace.init`'s
    ///     parameter of the same name. See this type's own doc for why it is
    ///     unused today.
    ///   - extensionIdentifier: Mirrors `MainThreadWorkspace.init`'s parameter
    ///     of the same name; unused today for the same reason.
    public init(
        presenter: ExtensionMessagePresenting,
        quickPickPresenter: ExtensionQuickPickPresenting,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String
    ) {
        self.presenter = presenter
        self.quickPickPresenter = quickPickPresenter
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
        var closeAffordanceIndices: [Int] = []
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
                // its own context. Every truthy one is recorded, not just the
                // first: upstream warns about the second and later ones but
                // keeps the flag on each, and its cancel slot is then
                // overwritten by the last. This loop has no logger to warn
                // through, so it records them all and lets the presenter
                // apply that same last-wins rule.
                if let closeAffordanceValue = item.forProperty("isCloseAffordance"),
                   closeAffordanceValue.toBool() {
                    closeAffordanceIndices.append(itemTitles.count - 1)
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
            closeAffordanceIndices: closeAffordanceIndices)
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

    // MARK: - vscode.window.showQuickPick

    /// This member's full path, used in its own rejection messages and in the
    /// torn-down message `VSCodeAPI.member` builds. A constant rather than
    /// `handleShowMessage`'s `memberPath` parameter: there are three
    /// `show*Message` members sharing one handler and exactly one
    /// `showQuickPick`.
    private static let quickPickMemberPath = "vscode.window.showQuickPick"

    /// `implementation` for `vscode.window.showQuickPick`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is.
    public private(set) lazy var showQuickPick: Any = VSCodeAPI.member(
        MainThreadWindow.quickPickMemberPath, of: self, whenTornDown: .rejectedPromise
    ) { $0.handleShowQuickPick() }

    /// The `vscode.QuickPickItemKind` enum, as the name→value table an
    /// installer hands to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`.
    /// An extension that wants a separator writes
    /// `kind: vscode.QuickPickItemKind.Separator`, and without this that
    /// expression is a reach for a member the shim does not have.
    ///
    /// The two values are the declaration's own: `Separator = -1`
    /// (`vscode.d.ts:1886`) and `Default = 0` (`vscode.d.ts:1890`).
    ///
    /// **The namespace path an installer must use is `"vscode"`, not
    /// `"vscode.window"`.** `QuickPickItemKind` is a top-level `vscode`
    /// export, and it is not one of the namespaces the shim creates —
    /// `extension-runtime.js:595` lists those, and they are `commands`,
    /// `workspace`, `window`, `languages` and `lm`. It does not need to be
    /// one: `extension-runtime.js:602-604` keeps the top-level member table
    /// under `namespaceTables.vscode`, and that is exactly the key
    /// `defineMember` looks up before writing into it
    /// (`extension-runtime.js:622`, `:629`), so a definition on `"vscode"`
    /// lands on the object `require('vscode')` returns without editing that
    /// file.
    ///
    /// **Nothing installs it.** No type in this module constructs a
    /// `MainThreadWindow` at all, so no member on this adaptor is installed
    /// today; this is the value the installer needs, and the installer does
    /// not exist.
    public static let quickPickItemKindMembers: [String: Int] = ["Separator": -1, "Default": 0]

    /// Rejects rather than raises on a torn-down adaptor, matching the three
    /// `show*Message` members above: this one returns a `Thenable` too, in
    /// all four of its overloads.
    ///
    /// Argument shape, from `vscode.d.ts:11421-11451`. All four overloads put
    /// items in argument 0 and options in argument 1, which is why there is
    /// no "options or first item" ambiguity to resolve here of the kind
    /// `handleShowMessage` has:
    /// 1. **argument 0 — the items.** Required; a missing argument 0 rejects.
    ///    Its declared type is `readonly T[] | Thenable<readonly T[]>`, and
    ///    which of the two it is cannot be decided synchronously — so it is
    ///    not decided here at all. It goes to
    ///    `VSCodeAPI.settlement(of:in:)`, whose doc states that a
    ///    non-thenable answers `.fulfilled` with itself, so the array case
    ///    and the promise case share one path; the `isArray` check then
    ///    happens on whatever that settled with, in
    ///    `parseQuickPickItems(from:)`.
    /// 2. **argument 1 — the options.** Optional. Absent, `undefined` or
    ///    `null` means every default; an object is read for the seven
    ///    `QuickPickOptions` fields plus `onDidSelectItem`; anything else — a
    ///    string, a number — is a caller error and rejects.
    /// 3. **argument 2 — the cancellation token. Accepted and ignored.**
    ///    `CancellationToken` appears in no file under
    ///    `packages/apple/AgenticToolkit` (measured with `grep -r` while
    ///    writing this), so there is nothing here for a token to cancel
    ///    through. The cost is concrete and worth stating: an extension that
    ///    passes one expecting to close the picker programmatically will find
    ///    that it does not. It is not recorded in `NotImplementedLedger` —
    ///    see this type's own doc for why.
    private func handleShowQuickPick() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        let path = MainThreadWindow.quickPickMemberPath

        guard let itemsArgument = arguments.first else {
            return VSCodeAPI.rejectedPromise(message: "\(path) requires an items argument.", in: context)
        }

        var options = QuickPickCallOptions()
        if arguments.count > 1, !arguments[1].isUndefined, !arguments[1].isNull {
            guard arguments[1].isObject else {
                return VSCodeAPI.rejectedPromise(
                    message: "\(path)'s argument 1 is neither an options object nor undefined.", in: context)
            }
            options = MainThreadWindow.quickPickOptions(from: arguments[1])
        }

        return presentQuickPickPromise(itemsArgument: itemsArgument, options: options, in: context)
    }

    /// Argument 1 of a `showQuickPick` call, already read — `QuickPickOptions`
    /// (`vscode.d.ts:1992`) plus the two `JSValue`s the highlight callback
    /// needs. Every default here is `nil` or `false`, which is what an absent
    /// argument 1 means and what the declaration documents for
    /// `matchOnDescription` (`vscode.d.ts:2000`) and `matchOnDetail`
    /// (`vscode.d.ts:2005`).
    private struct QuickPickCallOptions {
        var title: String?
        var placeHolder: String?
        var prompt: String?
        var canPickMany = false
        var matchOnDescription = false
        var matchOnDetail = false
        var ignoreFocusOut = false

        /// The options object itself, bound as `this` when `onDidSelectItem`
        /// is invoked: upstream calls it as `options.onDidSelectItem(…)`
        /// (`extHostQuickOpen.ts:118`), so `this` is that object.
        var optionsObject: JSValue?

        /// `QuickPickOptions.onDidSelectItem` (`vscode.d.ts:2035`), when
        /// argument 1 carried one that `isObject`.
        var onDidSelectItem: JSValue?
    }

    /// Reads `QuickPickOptions` (`vscode.d.ts:1992`) off argument 1.
    ///
    /// Strings go through `coercedString(from:)`, and a field whose coercion
    /// failed is simply left `nil` — the same judgement `handleShowMessage`
    /// makes about its own `detail` option, for the same reason: optional
    /// decoration is not worth rejecting a call over. Booleans go through
    /// `toBool()`, JavaScript's own truthiness, and an absent field is
    /// `false`.
    ///
    /// Every read here can run an extension's own getter on a `Proxy`, which
    /// is the accepted, read-only risk `isOptionsArgument` above names for
    /// its own `title` read.
    private static func quickPickOptions(from value: JSValue) -> QuickPickCallOptions {
        var options = QuickPickCallOptions()
        options.optionsObject = value
        options.title = coercedOptionalString(value.forProperty("title"))
        options.placeHolder = coercedOptionalString(value.forProperty("placeHolder"))
        options.prompt = coercedOptionalString(value.forProperty("prompt"))
        options.canPickMany = value.forProperty("canPickMany")?.toBool() ?? false
        options.matchOnDescription = value.forProperty("matchOnDescription")?.toBool() ?? false
        options.matchOnDetail = value.forProperty("matchOnDetail")?.toBool() ?? false
        options.ignoreFocusOut = value.forProperty("ignoreFocusOut")?.toBool() ?? false
        if let callback = value.forProperty("onDidSelectItem"), callback.isObject {
            options.onDidSelectItem = callback
        }
        return options
    }

    /// `coercedString(from:)` for an optional property read: `nil` for a
    /// field that is absent, `undefined`, `null`, or whose coercion failed.
    private static func coercedOptionalString(_ value: JSValue?) -> String? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        return coercedString(from: value)
    }

    /// A `String` only for a property that is genuinely a JavaScript string —
    /// `nil` for absent, and `nil` for a number or an object rather than a
    /// coercion of it. Used for an item's `description` and `detail`, which
    /// are decoration: a non-string one is omitted rather than rejecting the
    /// call, exactly as `handleShowMessage` omits an unusable `detail`.
    private static func stringOptionalField(_ value: JSValue?) -> String? {
        guard let value, value.isString else { return nil }
        return value.toString()
    }

    /// What `parseQuickPickItems(from:)` found.
    private enum QuickPickItemsParse {

        /// The array parsed: the presenter-facing items, and the original
        /// `JSValue` for each, at matching indices.
        case parsed(items: [ExtensionQuickPickItem], values: [JSValue])

        /// Argument 0 settled with something this member cannot read, and
        /// this is the message to reject the call with.
        case rejected(message: String)
    }

    /// Reads a settled argument 0 into `ExtensionQuickPickItem`s, mirroring
    /// the item loop in `extHostQuickOpen.ts:91-115`.
    ///
    /// - A string element is its own `label`, every other field defaulted
    ///   (`extHostQuickOpen.ts:92-93`).
    /// - An element whose `kind` is the number `-1` — `Separator`,
    ///   `vscode.d.ts:1886` — is a separator, and only its `label` is
    ///   carried; see `ExtensionQuickPickItem.isSeparator`.
    /// - Any other element must be an object with a **string** `label`. That
    ///   is the same bar `handleShowMessage` holds its own items to for
    ///   `title`, and `label` is deliberately not put through
    ///   `coercedString(from:)` so the two cannot disagree about what an item
    ///   is.
    /// - Anything else rejects, naming the element's index within the array.
    ///   A silently dropped row is worse than a rejected call — the same rule
    ///   `handleShowMessage` applies to its own item arguments.
    ///
    /// The `isArray` check lives here rather than in `handleShowQuickPick`
    /// because it can only be made after argument 0 has settled. Every
    /// property read below can run an extension's own getter on a `Proxy`,
    /// which is the accepted, read-only risk `isOptionsArgument` above names.
    private static func parseQuickPickItems(from value: JSValue) -> QuickPickItemsParse {
        guard value.isArray else {
            return .rejected(
                message: "\(quickPickMemberPath)'s argument 0 is neither an array nor a promise of one.")
        }
        let count = Int(value.forProperty("length")?.toInt32() ?? 0)
        var items: [ExtensionQuickPickItem] = []
        var values: [JSValue] = []
        for index in 0..<max(count, 0) {
            guard let element = value.atIndex(index) else {
                return .rejected(message: unreadableItemMessage(at: index))
            }
            if element.isString, let label = element.toString() {
                items.append(ExtensionQuickPickItem(
                    label: label, description: nil, detail: nil,
                    isSeparator: false, isPicked: false, alwaysShow: false))
                values.append(element)
                continue
            }
            guard element.isObject,
                  let labelValue = element.forProperty("label"), labelValue.isString,
                  let label = labelValue.toString() else {
                return .rejected(message: unreadableItemMessage(at: index))
            }
            if isSeparatorItem(element) {
                items.append(ExtensionQuickPickItem(
                    label: label, description: nil, detail: nil,
                    isSeparator: true, isPicked: false, alwaysShow: false))
            } else {
                items.append(ExtensionQuickPickItem(
                    label: label,
                    description: stringOptionalField(element.forProperty("description")),
                    detail: stringOptionalField(element.forProperty("detail")),
                    isSeparator: false,
                    isPicked: element.forProperty("picked")?.toBool() ?? false,
                    alwaysShow: element.forProperty("alwaysShow")?.toBool() ?? false))
            }
            values.append(element)
        }
        return .parsed(items: items, values: values)
    }

    /// The rejection for an element that is neither of the two shapes
    /// `showQuickPick` accepts, naming its index within the array the
    /// extension supplied.
    private static func unreadableItemMessage(at index: Int) -> String {
        "\(quickPickMemberPath)'s items[\(index)] is neither a string nor an object with a string 'label'."
    }

    /// Whether `item`'s `kind` is `QuickPickItemKind.Separator`, which is the
    /// number `-1` (`vscode.d.ts:1886`).
    ///
    /// Compared only when the property `isNumber`. `kind` is optional and
    /// "When not specified, the default is {@link QuickPickItemKind.Default}"
    /// (`vscode.d.ts:1912`), and a `kind` that is not a number is not the
    /// `Separator` member either.
    ///
    /// The `-1` is spelled here rather than read out of
    /// `quickPickItemKindMembers`: that table is what an installer hands to
    /// JavaScript, and making this test depend on it would mean one edit to
    /// the table silently changed how items parse as well.
    private static func isSeparatorItem(_ item: JSValue) -> Bool {
        guard let kindValue = item.forProperty("kind"), kindValue.isNumber else { return false }
        return kindValue.toInt32() == -1
    }

    /// The `onHighlight` closure `presentQuickPick` is handed.
    ///
    /// When argument 1 carried an `onDidSelectItem`, each call invokes it
    /// with **the original item `JSValue`** at that index: upstream passes
    /// `items[handle]`, the extension's own value, rather than a label or a
    /// handle (`extHostQuickOpen.ts:116-120`). Through
    /// `VSCodeAPI.call(_:thisArg:arguments:)` rather than `invokeMethod`, for
    /// the reason that method's own doc gives — a throw from an extension's
    /// callback must not escape into `ExtensionHost.pendingException`.
    /// `thisArg` is the options object, because upstream invokes it as
    /// `options.onDidSelectItem(…)` (`extHostQuickOpen.ts:118`).
    ///
    /// **A callback that throws is ignored, and that is a decision.** The
    /// `CallOutcome` is discarded — both a returned value, which
    /// `onDidSelectItem` declares as `any` (`vscode.d.ts:2035`), and a
    /// `.threw`. Tearing down a picker the user is still looking at because a
    /// highlight callback threw would turn the extension's bug into the
    /// user's lost selection.
    ///
    /// An index that `itemValues` does not contain invokes nothing: the
    /// presenter is a protocol anyone may conform to, so an out-of-range
    /// index is bad input rather than a programmer error this adaptor can
    /// assert away — the same judgement `presentMessagePromise` makes about a
    /// chosen index.
    ///
    /// With no `onDidSelectItem` the closure does nothing. `onHighlight` is
    /// not optional on the protocol: an optional closure buys one saved
    /// allocation and costs every conformer an `if let`.
    private static func highlightHandler(
        for options: QuickPickCallOptions,
        itemValues: [JSValue]
    ) -> (Int) -> Void {
        guard let callback = options.onDidSelectItem else { return { _ in } }
        let thisArg = options.optionsObject
        return { index in
            guard itemValues.indices.contains(index) else { return }
            _ = VSCodeAPI.call(callback, thisArg: thisArg, arguments: [itemValues[index]])
        }
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

    /// `presentMessagePromise`'s counterpart for `showQuickPick`, with one
    /// structural difference: argument 0 may be a `Thenable`, so this awaits
    /// **twice** — once for the items, once for the presenter — and therefore
    /// checks teardown three times rather than twice.
    ///
    /// **Divergence from upstream, deliberate: the picker is not shown before
    /// the items arrive.** Upstream races the widget against the items
    /// promise (`Promise.race([widgetClosedPromise, itemsPromise])`,
    /// `extHostQuickOpen.ts:81-83`) so the user sees an empty picker
    /// immediately and can dismiss it while the items are still loading. Here
    /// the presenter is called once, with the finished request. The cost is
    /// real: an extension whose items promise is slow shows nothing at all in
    /// that interval. Making `ExtensionQuickPickPresenting` able to express
    /// "show now, fill later" is a different protocol, and designing it for a
    /// conformer that does not exist yet is how it ends up the wrong shape —
    /// task 5.5b-iv builds the first conformer.
    ///
    /// **The parse happens after the items settle, not before**, for the
    /// reason `handleShowQuickPick`'s own doc gives: whether argument 0 is an
    /// array cannot be decided synchronously when it may be a promise of one.
    /// So `.rejected` and `.unavailable` and a bad array all reject *this*
    /// promise rather than the synchronously-returned one.
    ///
    /// **Resolution carries the original `JSValue`s**, `itemValues[index]`,
    /// for the identity reason `presentMessagePromise`'s doc spells out and
    /// that `extHostQuickOpen.ts:125-131` depends on: upstream hands back
    /// `items[handle]`, the extension's own object.
    ///
    /// The two shapes of a resolved value are the declaration's
    /// (`vscode.d.ts:11421-11451`): `canPickMany` resolves with an **array**
    /// of the picked items, and every other overload with a **single** item.
    /// An `ExtensionQuickPickPresenting` that answers `nil` — dismissed —
    /// resolves `undefined` in both shapes, which is what
    /// `Thenable<T | undefined>` means; an empty `[]` from a `canPickMany`
    /// picker is a real answer and resolves an empty array, never `undefined`,
    /// per that protocol's own doc.
    ///
    /// An index the presenter answers with that `itemValues` does not contain
    /// is treated as a dismissal rather than trapped, the same judgement
    /// `presentMessagePromise` makes: the presenter is a protocol anyone may
    /// conform to, so its answer is input.
    private func presentQuickPickPromise(
        itemsArgument: JSValue,
        options: QuickPickCallOptions,
        in context: JSContext
    ) -> JSValue? {
        let path = MainThreadWindow.quickPickMemberPath
        return JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            // Both executor arguments are `_Null_unspecified`; see
            // `presentMessagePromise` for why a missing one leaves the promise
            // pending rather than inventing a settlement.
            guard let resolveValue, let rejectValue else { return }
            let settlement = SettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: path)
                    return
                }
                let itemsSettlement = await VSCodeAPI.settlement(of: itemsArgument, in: context)
                guard !self.isDisposed else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: path)
                    return
                }
                let itemsValue: JSValue
                switch itemsSettlement {
                case .fulfilled(let value):
                    itemsValue = value
                case .rejected(let reason):
                    // The extension's own rejection reason, passed through
                    // rather than rewritten: an extension that rejected its
                    // items promise with a typed error should see that error.
                    //
                    // **Divergence from upstream, deliberate: a rejected
                    // items promise always rejects the call.** Upstream tests
                    // `isCancellationError(err)` first and answers `undefined`
                    // for that one case (`extHostQuickOpen.ts:134-137`). This
                    // host has no cancellation vocabulary at all —
                    // `CancellationToken` appears in no file under
                    // `packages/apple/AgenticToolkit` — so there is no error
                    // it could recognise as a cancellation, and a
                    // name-matching test would be a guess about what an
                    // extension's error object looks like.
                    settlement.reject.call(withArguments: [reason])
                    return
                case .unavailable:
                    MainThreadWindow.rejectWithError(
                        settlement.reject, message: VSCodeAPI.dispatchUnavailableMessage(for: context))
                    return
                }
                let items: [ExtensionQuickPickItem]
                let itemValues: [JSValue]
                switch MainThreadWindow.parseQuickPickItems(from: itemsValue) {
                case .parsed(let parsedItems, let parsedValues):
                    items = parsedItems
                    itemValues = parsedValues
                case .rejected(let message):
                    MainThreadWindow.rejectWithError(settlement.reject, message: message)
                    return
                }
                let request = ExtensionQuickPickRequest(
                    title: options.title,
                    placeHolder: options.placeHolder,
                    prompt: options.prompt,
                    items: items,
                    canPickMany: options.canPickMany,
                    matchOnDescription: options.matchOnDescription,
                    matchOnDetail: options.matchOnDetail,
                    ignoreFocusOut: options.ignoreFocusOut)
                let chosenIndices = await self.quickPickPresenter.presentQuickPick(
                    request,
                    onHighlight: MainThreadWindow.highlightHandler(for: options, itemValues: itemValues))
                guard !self.isDisposed, let resultContext = settlement.resolve.context else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: path)
                    return
                }
                guard let chosenIndices,
                      chosenIndices.allSatisfy({ itemValues.indices.contains($0) }) else {
                    settlement.resolve.call(withArguments: [MainThreadWindow.undefinedValue(in: resultContext)])
                    return
                }
                let chosenValues = chosenIndices.map { itemValues[$0] }
                if options.canPickMany {
                    settlement.resolve.call(
                        withArguments: [MainThreadWindow.arrayValue(of: chosenValues, in: resultContext)])
                    return
                }
                guard let first = chosenValues.first else {
                    settlement.resolve.call(withArguments: [MainThreadWindow.undefinedValue(in: resultContext)])
                    return
                }
                settlement.resolve.call(withArguments: [first])
            }
        }
    }

    /// A JavaScript array holding `values`, for a `canPickMany` resolution.
    ///
    /// `NSNull()` when the bridge cannot build one, matching
    /// `undefinedValue(in:)`'s own fallback: settling with *something* keeps
    /// an extension's `await` from hanging forever on a failure it cannot see.
    private static func arrayValue(of values: [JSValue], in context: JSContext) -> Any {
        if let value = JSValue(object: values, in: context) {
            return value
        }
        return NSNull()
    }

    /// Rejects `reject` with the same wording `VSCodeAPI.member`'s own
    /// teardown path uses, matching `MainThreadWorkspace.rejectTornDown`.
    private static func rejectTornDown(_ reject: JSValue, path: String) {
        rejectWithError(reject, message: "\(path) is unavailable: this extension's host has been torn down.")
    }

    /// Rejects `reject` with a JavaScript `Error` carrying `message`.
    ///
    /// An `Error` and not a bare string, so an extension's `catch` sees
    /// `error.message` and a stack — which is what
    /// `VSCodeAPI.rejectedPromise(message:in:)` builds for the synchronous
    /// refusals, and the asynchronous ones should not be a different shape.
    /// Silent when the context is gone: there is then nothing left to reject
    /// into.
    private static func rejectWithError(_ reject: JSValue, message: String) {
        guard let context = reject.context,
              let errorValue = JSValue(newErrorFromMessage: message, in: context) else {
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
    /// `MainThreadWorkspace`. Unused by every member on this type so far —
    /// the four of them report each failure to the extension itself, by
    /// raising or by rejecting, and there is nothing here yet that fails in a
    /// way only a log line can report — kept for the same reason
    /// `notImplementedLedger` is: 5.5b-iii/5.5c extend this same class.
    public static nonisolated let logger = makeLogger()
}
