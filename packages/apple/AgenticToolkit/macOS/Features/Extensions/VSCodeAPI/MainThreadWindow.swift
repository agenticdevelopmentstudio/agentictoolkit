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

/// How urgently a `vscode.window.showInputBox` validation message wants to be
/// noticed — `InputBoxValidationSeverity` (`vscode.d.ts:2194-2207`, measured
/// against commit `3addbda6`): `Info = 1` (`:2198`), `Warning = 2` (`:2202`),
/// `Error = 3` (`:2206`).
///
/// `case information`, not `.info` — matching this file's own
/// `ExtensionMessageSeverity` spelling rather than the declaration's member
/// name, for the same reason that type already made: a Swift enum case name
/// is this codebase's word, not a transcription of upstream's.
///
/// **No `.ignore` case.** `Severity.Ignore` exists on upstream's internal
/// `$validateInput` bridge (`extHostQuickOpen.ts:187-189`) for a validation
/// result whose `severity` matched none of the three and whose `message` was
/// also empty — upstream's way of saying "nothing to show." This type has no
/// member for that because `inputValidation(from:)` below answers `nil` for
/// that same case instead: a severity is only ever attached to a message that
/// exists, so "nothing to show" is the absence of an `ExtensionInputValidation`
/// altogether, not a fourth severity.
public enum ExtensionInputValidationSeverity: Sendable, Equatable {
    case information, warning, error
}

/// One validation result from a `vscode.window.showInputBox` call's
/// `validateInput`, reduced to what a presenter needs to show a message and
/// decide whether to keep accepting the current value.
///
/// `InputBoxValidationMessage` (`vscode.d.ts:2212-2225`, measured against
/// commit `3addbda6`). **A presenter must not accept a value whose most
/// recent validation carried `.error`:** "When using
/// {@link InputBoxValidationSeverity.Error}, the user will not be able to
/// accept the input (e.g., by pressing Enter)" (`vscode.d.ts:2221-2223`).
/// Enforcing that belongs to whatever type builds an `NSTextField` around
/// this — task 5.5b-iv — not to this type or to `MainThreadWindow`, which
/// only carries the presenter's answer back to the extension.
public struct ExtensionInputValidation: Sendable, Equatable {
    public let message: String
    public let severity: ExtensionInputValidationSeverity

    /// Spelled out rather than synthesised, for `ExtensionQuickPickItem.init`'s
    /// reason: a `public` type's memberwise initialiser is `internal`, and
    /// this one's callers include a test module.
    public init(message: String, severity: ExtensionInputValidationSeverity) {
        self.message = message
        self.severity = severity
    }
}

/// One `vscode.window.showInputBox` call, reduced to what a presenter needs
/// to show a text field and report back the value the user accepted.
///
/// `InputBoxOptions` (`vscode.d.ts:2231-2282`, measured against commit
/// `3addbda6`).
public struct ExtensionInputBoxRequest: Sendable, Equatable {

    /// `InputBoxOptions.title` (`vscode.d.ts:2236`), or `nil`.
    public let title: String?

    /// `InputBoxOptions.prompt` (`vscode.d.ts:2254`) — "The text to display
    /// underneath the input box" — or `nil`.
    public let prompt: String?

    /// `InputBoxOptions.placeHolder` (`vscode.d.ts:2259`), or `nil`.
    public let placeHolder: String?

    /// `InputBoxOptions.value` (`vscode.d.ts:2241`): the value to pre-fill.
    /// **Non-optional, defaulting to `""`** — the declaration's own default
    /// for "the value to pre-fill" when the option is absent is an empty
    /// box, not the absence of a box, and every consumer of this field wants
    /// a `String` to seed a text field with, never an `Optional` to unwrap
    /// first.
    public let value: String

    /// `InputBoxOptions.valueSelection` (`vscode.d.ts:2249`): "Defined as
    /// tuple of two number where the first is the inclusive start index and
    /// the second the exclusive end index." `nil` means "the whole
    /// pre-filled value will be selected"; an empty range (`start == end`)
    /// means "only the cursor will be set" — both the declaration's own
    /// words, and both left to the presenter to act on, since carrying them
    /// as anything but this range would force this type to guess what
    /// `value.count` is going to be by the time a presenter reads it.
    ///
    /// A `Range<Int>`, not the declaration's tuple: parsing rejects a pair
    /// this type could not otherwise represent — reversed, negative, or past
    /// `value`'s end — rather than trapping when a presenter eventually tried
    /// to build a `Range` from a raw tuple. See `parseValueSelection(from:valueLength:)`.
    public let valueSelection: Range<Int>?

    /// `InputBoxOptions.password` (`vscode.d.ts:2264`): "Controls if a
    /// password input is shown."
    public let isPassword: Bool

    /// `InputBoxOptions.ignoreFocusOut` (`vscode.d.ts:2270`).
    public let ignoreFocusOut: Bool

    /// Whether this call carried a `validateInput` function at all.
    ///
    /// A separate stored field rather than something a presenter derives
    /// from the `validate` closure `ExtensionInputBoxPresenting` hands it
    /// alongside this request — the two are separate parameters precisely so
    /// a presenter can decide whether to call `validate` at all without
    /// having to invoke it once to find out, on the same terms upstream's
    /// own `typeof this._validateInput === 'function'`
    /// (`extHostQuickOpen.ts:156`) is computed once and threaded through
    /// rather than re-derived from the function reference each time.
    public let isValidating: Bool

    /// Spelled out for `ExtensionQuickPickItem.init`'s reason: a `public`
    /// type's synthesised memberwise initialiser is `internal`, and this
    /// one's callers include a test module.
    public init(
        title: String?,
        prompt: String?,
        placeHolder: String?,
        value: String,
        valueSelection: Range<Int>?,
        isPassword: Bool,
        ignoreFocusOut: Bool,
        isValidating: Bool
    ) {
        self.title = title
        self.prompt = prompt
        self.placeHolder = placeHolder
        self.value = value
        self.valueSelection = valueSelection
        self.isPassword = isPassword
        self.ignoreFocusOut = ignoreFocusOut
        self.isValidating = isValidating
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

/// Where a `vscode.window.showInputBox` call actually puts a text field on
/// screen (or, in a test, records what it was asked to show).
///
/// A third presenter rather than a member added to `ExtensionMessagePresenting`
/// or `ExtensionQuickPickPresenting` — see `ExtensionQuickPickPresenting`'s
/// own doc for the interface-segregation reasoning that already governs this
/// adaptor's other seam.
///
/// **No type in this module conforms to it.** `ExtensionQuickPickPresenting`'s
/// own doc already anticipates the panel that will: task 5.5b-iv builds one
/// conformer serving both this seam and that one.
///
/// `@MainActor`, matching every other type in this directory.
@MainActor
public protocol ExtensionInputBoxPresenting: AnyObject {

    /// Shows `request` and answers the value the user accepted.
    ///
    /// **`nil` means dismissed. An empty string does not** — the user can
    /// accept an empty value, and that is a different answer from never
    /// answering at all, on the same terms `ExtensionQuickPickPresenting`
    /// draws between a dismissal and an accepted empty selection.
    ///
    /// - Parameters:
    ///   - request: What to show.
    ///   - validate: Runs `request`'s `validateInput`, if it has one, against
    ///     a candidate value, and answers `nil` for "valid" — following
    ///     `InputBoxOptions.validateInput`'s own contract: "Return
    ///     `undefined`, `null`, or the empty string when 'value' is valid"
    ///     (`vscode.d.ts:2278`, measured against commit `3addbda6`). **A
    ///     conformer must not accept a value whose most recent call to
    ///     `validate` answered `.error` severity** —
    ///     `InputBoxValidationMessage`'s own doc: "the user will not be able
    ///     to accept the input (e.g., by pressing Enter)" for that severity
    ///     (`vscode.d.ts:2221-2223`). When `request.isValidating` is `false`,
    ///     `validate` always answers `nil`, and a conformer has no reason to
    ///     call it — but it is not made optional, so every conformer handles
    ///     one shape rather than two.
    /// - Returns: The accepted value, or `nil` if dismissed.
    func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String?
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
/// rather than in AppKit directly; `showQuickPick` (task 5.5b-ii), terminating
/// in an `ExtensionQuickPickPresenting` instead; and `showInputBox` (task
/// 5.5b-iii), terminating in an `ExtensionInputBoxPresenting` — a third seam,
/// for the reason `ExtensionQuickPickPresenting`'s own doc gives.
///
/// **One instance per extension**, mirroring `MainThreadCommands` and
/// `MainThreadWorkspace`. Nothing enforces it, but every ownership question
/// below — and `isDisposed`'s meaning — is answered as if it holds.
///
/// **`notImplementedLedger` and `extensionIdentifier` are stored and read by
/// no member on this type.** They mirror `MainThreadWorkspace.init`'s
/// shape and exist so `createStatusBarItem` (5.5c) — the next slice of this
/// same seam — has them already in hand rather than adding its own
/// constructor parameter later. Nothing here builds a `VSCodeAPI.subNamespace`
/// the way `MainThreadWorkspace.fs` does, so nothing here has a miss to
/// record yet. `showQuickPick`'s and `showInputBox`'s ignored cancellation
/// tokens are deliberately **not** recorded either: a `NotImplementedAccess`
/// is "One VS Code API member an
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

    /// Where a `showInputBox` call actually puts a text field on screen (or,
    /// in a test, records what it was asked to show). A third presenter
    /// rather than a member on either existing protocol — see
    /// `ExtensionInputBoxPresenting`'s own doc for why.
    private let inputBoxPresenter: ExtensionInputBoxPresenting

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
    ///   - inputBoxPresenter: Where a `showInputBox` call is actually
    ///     presented. Not defaulted, for `presenter:`'s own reason: a text
    ///     field that silently answered "dismissed" would tell every
    ///     extension the user refused something they were never shown. No
    ///     type in this module conforms to `ExtensionInputBoxPresenting` yet
    ///     either, so every conformer today is a test double.
    ///   - notImplementedLedger: Mirrors `MainThreadWorkspace.init`'s
    ///     parameter of the same name. See this type's own doc for why it is
    ///     unused today.
    ///   - extensionIdentifier: Mirrors `MainThreadWorkspace.init`'s parameter
    ///     of the same name; unused today for the same reason.
    public init(
        presenter: ExtensionMessagePresenting,
        quickPickPresenter: ExtensionQuickPickPresenting,
        inputBoxPresenter: ExtensionInputBoxPresenting,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String
    ) {
        self.presenter = presenter
        self.quickPickPresenter = quickPickPresenter
        self.inputBoxPresenter = inputBoxPresenter
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

    // MARK: - vscode.window.showInputBox

    /// This member's full path, used in its own rejection messages and in the
    /// torn-down message `VSCodeAPI.member` builds, matching
    /// `quickPickMemberPath`'s own reason for existing.
    private static let inputBoxMemberPath = "vscode.window.showInputBox"

    /// `implementation` for `vscode.window.showInputBox`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is.
    public private(set) lazy var showInputBox: Any = VSCodeAPI.member(
        MainThreadWindow.inputBoxMemberPath, of: self, whenTornDown: .rejectedPromise
    ) { $0.handleShowInputBox() }

    /// The `vscode.InputBoxValidationSeverity` enum, as the name→value table
    /// an installer hands to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`,
    /// matching `quickPickItemKindMembers`'s own reason for existing.
    ///
    /// **Keys are the declaration's own member spellings — `"Info"`, not
    /// `"information"`.** `ExtensionInputValidationSeverity.information`
    /// exists for this file's internal use, on `ExtensionMessageSeverity`'s
    /// own precedent; what an extension writes is
    /// `vscode.InputBoxValidationSeverity.Info` (`vscode.d.ts:2198`), and this
    /// table is what makes that expression resolve rather than reach for an
    /// undefined member. The case-name mismatch between the two is
    /// deliberate and does not need reconciling — nothing outside this file
    /// reads `ExtensionInputValidationSeverity` by its case names, and
    /// nothing outside `extension-runtime.js`'s namespace tables reads this
    /// one by its keys.
    ///
    /// **`"vscode"`, not `"vscode.window"`, is the namespace path an
    /// installer must use** — `InputBoxValidationSeverity` is a top-level
    /// `vscode` export exactly as `QuickPickItemKind` is, and
    /// `quickPickItemKindMembers`'s own doc already gives the measured
    /// citations for why that resolves.
    ///
    /// **Nothing installs it.** Same state as `quickPickItemKindMembers`: no
    /// type in this module constructs a `MainThreadWindow`'s installer, so no
    /// member on this adaptor is installed today.
    public static let inputBoxValidationSeverityMembers: [String: Int] = [
        "Info": 1, "Warning": 2, "Error": 3
    ]

    /// Rejects rather than raises on a torn-down adaptor, matching
    /// `handleShowQuickPick`.
    ///
    /// Argument shape, from `vscode.d.ts:11491` (measured against commit
    /// `3addbda6`): `showInputBox(options?: InputBoxOptions, token?:
    /// CancellationToken): Thenable<string | undefined>`.
    /// 1. **argument 0 — the options.** Optional. Absent, `undefined` or
    ///    `null` means every default; an object is read for the seven
    ///    `InputBoxOptions` fields this type carries plus `validateInput`;
    ///    anything else — a string, a number — is a caller error and
    ///    rejects, on `handleShowQuickPick`'s own terms for its argument 1.
    /// 2. **argument 1 — the cancellation token. Accepted and ignored**, for
    ///    `handleShowQuickPick`'s own stated reason: `CancellationToken`
    ///    appears in no file under `packages/apple/AgenticToolkit`, so
    ///    nothing here can act on one. Not recorded in `NotImplementedLedger`
    ///    for the same reason `showQuickPick`'s ignored token is not — a
    ///    degraded argument is not an absent member.
    private func handleShowInputBox() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        let path = MainThreadWindow.inputBoxMemberPath

        var options = InputBoxCallOptions()
        if let optionsArgument = arguments.first, !optionsArgument.isUndefined, !optionsArgument.isNull {
            guard optionsArgument.isObject else {
                return VSCodeAPI.rejectedPromise(
                    message: "\(path)'s argument 0 is neither an options object nor undefined.", in: context)
            }
            switch MainThreadWindow.inputBoxOptions(from: optionsArgument) {
            case .parsed(let parsedOptions):
                options = parsedOptions
            case .rejected(let message):
                return VSCodeAPI.rejectedPromise(message: message, in: context)
            }
        }

        return presentInputBoxPromise(options: options, in: context)
    }

    /// Argument 0 of a `showInputBox` call, already read — `InputBoxOptions`
    /// (`vscode.d.ts:2231`) plus the options object itself, bound as `this`
    /// when `validateInput` is invoked. See
    /// `makeValidateClosure(validateInput:optionsObject:in:)` for why that
    /// binding is this file's fourth divergence from upstream.
    private struct InputBoxCallOptions {
        var title: String?
        var prompt: String?
        var placeHolder: String?
        var value = ""
        var valueSelection: Range<Int>?
        var isPassword = false
        var ignoreFocusOut = false

        /// The options object itself. `nil` only when argument 0 was absent,
        /// `undefined` or `null` — `handleShowInputBox` never constructs an
        /// `InputBoxCallOptions` from a real object without setting this.
        var optionsObject: JSValue?

        /// `InputBoxOptions.validateInput` (`vscode.d.ts:2280`), when
        /// argument 0 carried one that `isObject` — the same test
        /// `quickPickOptions(from:)` uses for `onDidSelectItem`, and the
        /// Swift-side stand-in for upstream's own
        /// `typeof this._validateInput === 'function'`
        /// (`extHostQuickOpen.ts:156`).
        var validateInput: JSValue?
    }

    /// What `inputBoxOptions(from:)` found.
    private enum InputBoxOptionsParse {
        case parsed(InputBoxCallOptions)
        case rejected(message: String)
    }

    /// Reads `InputBoxOptions` (`vscode.d.ts:2231`) off argument 0.
    ///
    /// `title`, `prompt`, `placeHolder` and `value` go through
    /// `coercedOptionalString(_:)`, `quickPickOptions(from:)`'s own choice for
    /// decoration that is not worth rejecting a call over; `value` then
    /// defaults to `""` rather than staying `nil`, matching
    /// `ExtensionInputBoxRequest.value`'s own non-optional field. `password`
    /// and `ignoreFocusOut` go through `toBool()`, defaulting `false` exactly
    /// as `quickPickOptions(from:)`'s own booleans do.
    ///
    /// `valueSelection` is validated against the parsed `value`'s length,
    /// which is why it is read after `value` rather than alongside it — see
    /// `parseValueSelection(from:valueLength:)`.
    ///
    /// Every read here can run an extension's own getter on a `Proxy`, the
    /// same accepted, read-only risk `quickPickOptions(from:)`'s own doc
    /// names for its own reads, in turn citing `isOptionsArgument`'s
    /// (`Uri.swift:352-358`).
    private static func inputBoxOptions(from value: JSValue) -> InputBoxOptionsParse {
        var options = InputBoxCallOptions()
        options.optionsObject = value
        options.title = coercedOptionalString(value.forProperty("title"))
        options.prompt = coercedOptionalString(value.forProperty("prompt"))
        options.placeHolder = coercedOptionalString(value.forProperty("placeHolder"))
        options.value = coercedOptionalString(value.forProperty("value")) ?? ""
        options.isPassword = value.forProperty("password")?.toBool() ?? false
        options.ignoreFocusOut = value.forProperty("ignoreFocusOut")?.toBool() ?? false
        if let validate = value.forProperty("validateInput"), validate.isObject {
            options.validateInput = validate
        }
        switch parseValueSelection(from: value.forProperty("valueSelection"), valueLength: options.value.count) {
        case .parsed(let range):
            options.valueSelection = range
        case .rejected(let message):
            return .rejected(message: message)
        }
        return .parsed(options)
    }

    /// What `parseValueSelection(from:valueLength:)` found.
    private enum ValueSelectionParse {
        case parsed(Range<Int>?)
        case rejected(message: String)
    }

    /// Reads `InputBoxOptions.valueSelection` (`vscode.d.ts:2249`): "Defined
    /// as tuple of two number where the first is the inclusive start index
    /// and the second the exclusive end index."
    ///
    /// **Divergence from upstream, deliberate: a malformed pair rejects the
    /// call rather than being forwarded.** `mainThreadQuickOpen.ts:113`
    /// forwards `options.valueSelection` to the widget completely unexamined
    /// — `inputOptions.valueSelection = options.valueSelection;` — because
    /// the widget upstream hands it to can cope with whatever shape arrives.
    /// This type carries the field as `Range<Int>`, and constructing one from
    /// a reversed or out-of-bounds pair traps rather than misbehaving, so
    /// there is no "forward it unexamined" option here — the choice is
    /// between rejecting and silently discarding the field, and a silently
    /// discarded field is the same "worse than a rejected call" judgement
    /// `parseQuickPickItems(from:)` already makes about a malformed item.
    ///
    /// Every rejection names `valueSelection`, so a caller can tell which
    /// option was at fault.
    ///
    /// - Parameters:
    ///   - value: `argument.forProperty("valueSelection")` — absent,
    ///     `undefined` and `null` all parse to `nil`, matching the
    ///     declaration's own "When `undefined` the whole pre-filled value
    ///     will be selected."
    ///   - valueLength: The already-parsed `value` option's `count`, the
    ///     bound an `end` past it is rejected against.
    private static func parseValueSelection(from value: JSValue?, valueLength: Int) -> ValueSelectionParse {
        guard let value, !value.isUndefined, !value.isNull else {
            return .parsed(nil)
        }
        let base = "\(inputBoxMemberPath)'s options.valueSelection"
        guard value.isArray else {
            return .rejected(message: "\(base) is neither a two-element array nor undefined/null.")
        }
        let length = Int(value.forProperty("length")?.toInt32() ?? -1)
        guard length == 2 else {
            return .rejected(message: "\(base) must have exactly two elements, not \(length).")
        }
        guard let startValue = value.atIndex(0), startValue.isNumber,
              let endValue = value.atIndex(1), endValue.isNumber else {
            return .rejected(message: "\(base)'s two elements must both be numbers.")
        }
        let start = Int(startValue.toInt32())
        let end = Int(endValue.toInt32())
        guard start >= 0 else {
            return .rejected(message: "\(base)'s start (\(start)) must not be negative.")
        }
        guard end >= start else {
            return .rejected(message: "\(base)'s end (\(end)) must not be before its start (\(start)).")
        }
        guard end <= valueLength else {
            return .rejected(
                message: "\(base)'s end (\(end)) is past the end of value, which is \(valueLength) long.")
        }
        return .parsed(start..<end)
    }

    /// The `validate` closure `ExtensionInputBoxPresenting.presentInputBox`
    /// is handed for an `options` argument that carried no `validateInput` at
    /// all: always answers `nil`, following that parameter's own doc — a
    /// conformer has no reason to call it, but it is not made optional.
    private static func alwaysValidClosure(_: String) async -> ExtensionInputValidation? {
        nil
    }

    /// The `validate` closure to hand `ExtensionInputBoxPresenting.presentInputBox`.
    ///
    /// `alwaysValidClosure` when `options.validateInput` is `nil`; otherwise
    /// `makeValidateClosure(validateInput:optionsObject:in:)`, bound to this
    /// call's own `validateInput` and options object.
    private func inputValidateClosure(
        for options: InputBoxCallOptions,
        in context: JSContext
    ) -> (String) async -> ExtensionInputValidation? {
        guard let validateInput = options.validateInput else {
            return MainThreadWindow.alwaysValidClosure
        }
        return makeValidateClosure(validateInput: validateInput, optionsObject: options.optionsObject, in: context)
    }

    /// Builds the closure that runs one `validateInput` call against a
    /// candidate value and normalises whatever comes back, mirroring
    /// upstream's own bridge (`extHostQuickOpen.ts:166-196`, measured against
    /// commit `3addbda6`):
    /// ```
    /// async $validateInput(input: string): Promise<...> {
    ///     if (!this._validateInput) { return; }
    ///     const result = await this._validateInput(input);      // :171
    ///     if (!result || typeof result === 'string') { return result; }   // :172-174
    ///     switch (result.severity) { ... }                       // :176-190
    /// }
    /// ```
    ///
    /// Three steps, each a place this closure can honestly answer `nil`
    /// ("valid") rather than propagate a failure into the extension:
    /// 1. **Invoke.** `VSCodeAPI.call(_:thisArg:arguments:)` with a JS string
    ///    for `value`, built fresh in `context` — the promise's own context.
    ///    A `.threw` answers `nil`: this file's first stated divergence, "a
    ///    rejected validation promise answers 'valid' rather than
    ///    surfacing," extended to a synchronous throw on the same reasoning —
    ///    smaller harm than blocking every future keystroke on one bad call,
    ///    and reversible by the extension.
    /// 2. **Settle.** `validateInput` may itself answer a `Thenable`
    ///    (`vscode.d.ts:2280-2281`), so the returned value goes through
    ///    `VSCodeAPI.settlement(of:in:)`; `.rejected` and `.unavailable` both
    ///    answer `nil`, on the same divergence.
    /// 3. **Normalise.** `inputValidation(from:)` reduces the fulfilled value
    ///    to `ExtensionInputValidation?`.
    ///
    /// **`this` is bound to `optionsObject`, and that is this file's fourth
    /// divergence from upstream, not previously listed.** Measured against
    /// `extHostQuickOpen.ts:171`, upstream calls `this._validateInput(input)`
    /// — a plain call through the enclosing `ExtHostQuickOpen`-side class's
    /// own field, so `this` inside the extension's `validateInput` is that
    /// internal instance, never the `options` object the extension passed to
    /// `showInputBox`. This host binds `this` to `optionsObject` instead,
    /// following `highlightHandler(for:itemValues:)`'s own precedent for
    /// `onDidSelectItem` — which upstream **does** call as
    /// `options.onDidSelectItem(…)` (`extHostQuickOpen.ts:118`) — for
    /// consistency across this adaptor's two callback bindings rather than
    /// giving each its own rule. The cost is narrow: an extension whose
    /// `validateInput` reads its own `this` (rather than the near-universal
    /// arrow function or closure-based validator, which ignores it) sees a
    /// different object than upstream would hand it.
    ///
    /// Safe to invoke any number of times, including after `isDisposed`: a
    /// disposed adaptor answers `nil` before touching `validateInput` at all,
    /// so a validator call racing teardown neither crashes nor reaches a
    /// torn-down extension's callback.
    private func makeValidateClosure(
        validateInput: JSValue,
        optionsObject: JSValue?,
        in context: JSContext
    ) -> (String) async -> ExtensionInputValidation? {
        { [weak self] value in
            guard let self, !self.isDisposed else { return nil }
            let valueArgument = MainThreadWindow.stringValue(value, in: context)
            guard case .returned(let returned) = VSCodeAPI.call(
                validateInput, thisArg: optionsObject, arguments: [valueArgument]
            ), let returned else {
                return nil
            }
            guard case .fulfilled(let settled) = await VSCodeAPI.settlement(of: returned, in: context) else {
                return nil
            }
            return MainThreadWindow.inputValidation(from: settled)
        }
    }

    /// Normalises a settled `validateInput` result into
    /// `ExtensionInputValidation?`, mirroring `$validateInput`'s own
    /// normalisation (`extHostQuickOpen.ts:172-190`, measured against commit
    /// `3addbda6`) with one adjustment: upstream's `default:` arm answers
    /// `Severity.Ignore` when `result.message` is falsy and `Severity.Error`
    /// otherwise (`:187-189`); this type has no `.ignore` case (see
    /// `ExtensionInputValidationSeverity`'s own doc), so an object with no
    /// usable `message` answers `nil` here regardless of what `severity`
    /// says, and only an object that does carry a `message` can reach the
    /// `default: .error` arm below.
    ///
    /// - `undefined` or `null` → `nil`, "Return `undefined`, `null`, or the
    ///   empty string when 'value' is valid" (`vscode.d.ts:2278`).
    /// - an empty string → `nil`, the same sentence.
    /// - a non-empty string → `.error`, the declaration's own default:
    ///   "By setting a string, the InputBox will use a default
    ///   {@link InputBoxValidationSeverity} of Error" (`vscode.d.ts:13326`,
    ///   measured against commit `3addbda6`).
    /// - an array → `nil`. Arrays are objects in JavaScript, and this rule is
    ///   listed ahead of the object rule below rather than falling into it,
    ///   since an array has no `message` property of its own to read.
    /// - an object → its `message`, read the same way `stringOptionalField(_:)`
    ///   reads item decoration: `nil` for anything that is not a string,
    ///   which answers `nil` for the whole result, on the reasoning this
    ///   doc's opening paragraph gives. With a usable `message`, `severity`
    ///   is read as a number, one-based per `InputBoxValidationSeverity`
    ///   (`vscode.d.ts:2198-2206`): `1` → `.information`, `2` → `.warning`,
    ///   `3` → `.error`, anything else — absent, a string, out of range — →
    ///   `.error`, matching the declaration's own default for a bare string.
    /// - anything else (a number, a boolean) → `nil`.
    private static func inputValidation(from value: JSValue) -> ExtensionInputValidation? {
        if value.isUndefined || value.isNull {
            return nil
        }
        if value.isString {
            guard let message = value.toString(), !message.isEmpty else { return nil }
            return ExtensionInputValidation(message: message, severity: .error)
        }
        guard value.isObject, !value.isArray else {
            return nil
        }
        guard let messageValue = value.forProperty("message"), messageValue.isString,
              let message = messageValue.toString() else {
            return nil
        }
        let severity: ExtensionInputValidationSeverity
        if let severityValue = value.forProperty("severity"), severityValue.isNumber {
            switch severityValue.toInt32() {
            case 1:
                severity = .information
            case 2:
                severity = .warning
            case 3:
                severity = .error
            default:
                severity = .error
            }
        } else {
            severity = .error
        }
        return ExtensionInputValidation(message: message, severity: severity)
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

    /// `presentMessagePromise`'s counterpart for `showInputBox`.
    ///
    /// Checked twice for teardown, on `presentMessagePromise`'s own reasoning
    /// and exact spelling: once before `inputBoxPresenter.presentInputBox` is
    /// ever awaited, once after it returns.
    ///
    /// `validate` is `inputValidateClosure(for:in:)` — `alwaysValidClosure`
    /// when `options.validateInput` was absent, otherwise a closure bound to
    /// this call's own `validateInput` and options object. Either way, it
    /// closes over `context` and `options`, not over `self`, and — being
    /// `[weak self]` internally for the `validateInput` case — remains safe
    /// to invoke after this `Task` itself has moved past its own teardown
    /// checks; `makeValidateClosure`'s own doc gives the disposed-answers-nil
    /// behavior that keeps a late call from reaching a torn-down extension.
    ///
    /// A `nil` answer resolves `undefined`, matching `Thenable<string |
    /// undefined>` (`vscode.d.ts:11491`) — a dismissal. A string answer,
    /// **including the empty string**, resolves a JS string built fresh in
    /// the settled context via `stringValue(_:in:)`: an accepted empty value
    /// is a real answer, never conflated with dismissal, on this file's own
    /// stated rule for `ExtensionInputBoxPresenting.presentInputBox`.
    ///
    /// No identity to preserve here, unlike `presentMessagePromise` and
    /// `presentQuickPickPromise`: the contract returns a plain `string`, not
    /// a caller-supplied object, so there is no original `JSValue` to hand
    /// back.
    private func presentInputBoxPromise(options: InputBoxCallOptions, in context: JSContext) -> JSValue? {
        let path = MainThreadWindow.inputBoxMemberPath
        let request = ExtensionInputBoxRequest(
            title: options.title,
            prompt: options.prompt,
            placeHolder: options.placeHolder,
            value: options.value,
            valueSelection: options.valueSelection,
            isPassword: options.isPassword,
            ignoreFocusOut: options.ignoreFocusOut,
            isValidating: options.validateInput != nil)
        let validate = inputValidateClosure(for: options, in: context)
        return JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            // Both executor arguments are `_Null_unspecified`; see
            // `presentMessagePromise` for why a missing one leaves the
            // promise pending rather than inventing a settlement.
            guard let resolveValue, let rejectValue else { return }
            let settlement = SettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: path)
                    return
                }
                let answer = await self.inputBoxPresenter.presentInputBox(request, validate: validate)
                guard !self.isDisposed, let resultContext = settlement.resolve.context else {
                    MainThreadWindow.rejectTornDown(settlement.reject, path: path)
                    return
                }
                guard let answer else {
                    settlement.resolve.call(withArguments: [MainThreadWindow.undefinedValue(in: resultContext)])
                    return
                }
                settlement.resolve.call(withArguments: [MainThreadWindow.stringValue(answer, in: resultContext)])
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

    /// A JavaScript string holding `value`, built fresh in `context`.
    ///
    /// `NSNull()` when the bridge cannot build one, matching
    /// `arrayValue(of:in:)`'s own fallback and for the same reason: settling
    /// or calling with *something* keeps an extension's `await` from hanging
    /// forever on a failure it cannot see. Used both to resolve
    /// `presentInputBoxPromise`'s accepted answer — including the empty
    /// string — and to build `makeValidateClosure`'s own argument to
    /// `validateInput`.
    private static func stringValue(_ value: String, in context: JSContext) -> Any {
        if let value = JSValue(object: value, in: context) {
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
    /// each of them reports its own failure to the extension itself, by
    /// raising or by rejecting, and there is nothing here yet that fails in a
    /// way only a log line can report — kept for the same reason
    /// `notImplementedLedger` is: 5.5c extends this same class.
    public static nonisolated let logger = makeLogger()
}
