//
//  NSAlertMessagePresenter.swift
//  AgenticToolkit
//
//  Split out of MainThreadWindow.swift, which had grown past 2,800 lines.
//

import AppKit
import Foundation
import OSLog
import AgenticToolkitCore

/// Presents a `vscode.window.show*Message` request with `NSAlert`.
///
/// **Presentation rule, decided here: always a sheet, never app-modal.**
/// `beginSheetModal(for:completionHandler:)` on the window `window()`
/// answers; failing that, on whatever ordinary window of this app is
/// currently visible; and failing *that*, the message is not shown at all and
/// the call resolves as a dismissal. This is a menu-bar app — having no
/// project window is the ordinary case, not the edge — so the window this
/// presenter attaches to is read from a `() -> NSWindow?` this type is
/// initialised with, rather than guessed at from `NSApplication.shared` or
/// some other ambient source, and each fallback is written out in
/// `presentedResponse(for:)` rather than left to whatever `NSAlert` happens
/// to do when handed no window at all.
///
/// **Why `runModal()` is not the no-window fallback.** It was, and it was
/// wrong twice over. `NSAlert.runModal()` runs an application-modal session:
/// it orders its own window front and makes it key, which for an
/// `LSUIElement` app that is not active *activates the app* — the one thing
/// this project forbids outright, because a window that comes forward
/// mid-sentence swallows the next keystrokes from whoever is typing
/// (`.claude/CLAUDE.md`, "never take the screen"). And it blocks the main
/// thread until someone responds, so an extension calling
/// `showInformationMessage` with no window available could wedge the whole
/// app's UI. A sheet does neither: it attaches to an already-visible window
/// without activating the app, and it returns through a completion handler.
///
/// **The last fallback drops the message, deliberately.** With no visible
/// window anywhere in the app there is no surface a sheet can attach to that
/// does not seize the screen, so the request is logged and resolved `nil` —
/// indistinguishable, to the extension, from a user who dismissed the alert
/// without choosing an item, which is a state `vscode.d.ts` already requires
/// every caller to handle. Losing one extension's message is the smaller
/// harm; the alternative is taking the screen from someone who is typing.
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
    /// resolves `undefined` — exactly what this implementation does.
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
        // A `nil` response is a message that was never shown; it resolves the
        // same as a dismissal, which is what an unmatched button index below
        // resolves to as well.
        guard let response = await presentedResponse(for: alert) else { return nil }
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
    /// `beginSheetModal(for:completionHandler:)`.
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
    /// itself — including the detail that the close-affordance
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

    /// A sheet on `window()`, else on any visible ordinary window of this
    /// app, else nothing at all — `nil`, meaning the message was never shown.
    /// See this type's own doc for why there is no app-modal branch.
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
    /// The window a sheet would attach to right now — the one `window()`
    /// answers with, else any visible window, else `nil`, which is the
    /// message being dropped.
    ///
    /// **`internal`, not `private`, and split out of `presentedResponse(for:)`
    /// deliberately**, on the same grounds as `buttonPlan(for:)` above: it is
    /// the only part of the presentation decision a test can exercise without
    /// running `beginSheetModal(for:completionHandler:)`, and running that in
    /// a test would put a sheet on someone's screen — the one thing this
    /// type's own doc says it exists to avoid. Going through `presentMessage`
    /// instead is not a substitute: it reaches this point only by showing the
    /// alert.
    ///
    /// Calling this is what makes the `() -> NSWindow?` seam observable, and
    /// the call happens per presentation rather than once at construction —
    /// see the `window` property's own doc.
    func sheetWindow() -> NSWindow? {
        window() ?? NSAlertMessagePresenter.anyVisibleWindow()
    }

    private func presentedResponse(for alert: NSAlert) async -> NSApplication.ModalResponse? {
        guard let window = sheetWindow() else {
            NSAlertMessagePresenter.logger.error(
                "Dropped a show*Message; no window for its sheet: \(alert.messageText, privacy: .public)")
            return nil
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    /// Any window of this app a sheet can sit on: visible, and able to become
    /// main, which is what excludes the status-item window and the
    /// non-activating panels a menu-bar app keeps around. Deliberately
    /// ambient — unlike `window()`, which the caller chooses — because this is
    /// the last thing tried before dropping the message, and at that point
    /// *some* window is better than none.
    private static func anyVisibleWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }
}

extension NSAlertMessagePresenter: Loggable {

    /// Used by exactly one line: the dropped-message report in
    /// `presentedResponse(for:)`. That drop is the one failure here that the
    /// extension cannot be told about — it is reported back as an ordinary
    /// dismissal — so a log line is the only place it can surface at all.
    public static nonisolated let logger = makeLogger()
}
