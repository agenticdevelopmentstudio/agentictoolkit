<!-- leaf: implement-extension-host-vs-2/code-api-ns-alert-message-presenter--part-2 · source: extension-host-vs-code-api-ns-alert-message-presenter.md -->

# NSAlertMessagePresenter — continued (part 2)

## Platform Notes

- **SwiftUI**: reproduce `buttonPlan(for:)` as a plain Swift function and feed its entries into `.alert(_:isPresented:actions:)` (or `.confirmationDialog` for a longer button list, since SwiftUI's alert API is best suited to a small, fixed count), giving the cancel-slot entry's `Button` a `role: .cancel` so SwiftUI supplies its own default/Escape handling rather than a manually assigned key equivalent the way `addButtons(for:to:)` does.
- **Compose**: `AlertDialog`'s `confirmButton`/`dismissButton` slots cover at most two buttons; for the general case, matching this presenter's unbounded `itemTitles` list, render a `Column` of `TextButton`s inside `AlertDialog`'s `text` slot, driven by the same `buttonPlan`-equivalent skip-and-collapse function. Compose has no sheet-versus-application-modal distinction to preserve, so the source's "never activate the app" constraint has no direct analogue to violate.
- **React/Web**: build a modal (a native `dialog` element, or a design-system modal) rather than `window.confirm`/`window.alert`, since neither supports more than one fixed OK/Cancel pair; reproduce `buttonPlan(for:)` as a pure function over `itemTitles`/`closeAffordanceIndices` driving the rendered button list, and model the "nothing to attach to" fallback as resolving the returned `Promise` with `null`, logged rather than thrown, when no container element is mounted.
- **AppKit / UIKit**: this is the source. `NSAlertMessagePresenter.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`) belongs to the `AgenticToolkitMacOS` framework target and uses `NSAlert`, `NSAlert.Style`, `NSApplication.ModalResponse`, and `beginSheetModal(for:completionHandler:)` bridged into `async` with `withCheckedContinuation`. A UIKit iOS port would use `UIAlertController` with `UIAlertAction`s and `present(_:animated:completion:)`; because an iOS app is always in the foreground, the "no window anywhere, drop the message" fallback this file implements has a much narrower analogue there — a root view controller that has not yet attached to a window.
- **WinUI 3**: present with `ContentDialog`, whose `PrimaryButtonText`/`SecondaryButtonText`/`CloseButtonText` give exactly three button slots — fewer than `NSAlert`'s unbounded button list — so a request needing more than three effective buttons, after the same last-wins cancel-slot collapse **button-plan-cancel-slot** requires, needs either a custom `ContentDialog` body with its own `StackPanel` of `Button` controls wired to close the dialog with a result, or `Windows.UI.Popups.MessageDialog` with its own capped `UICommand` list — either way the port must reimplement `buttonPlan(for:)`'s skip-and-collapse logic itself. Call `ContentDialog.ShowAsync`, which is already the WinUI analogue of a sheet attached to the current window rather than an application-modal call that activates a different one, and marshal onto the `DispatcherQueue` a `@MainActor` maps to via `DispatcherQueue.TryEnqueue` when invoked off that queue. Model "no window to attach to" as "no `XamlRoot` is available," logged and resolved as `ContentDialogResult.None` rather than shown, mirroring this file's own drop-and-log fallback; `Task`/`async`/`await` plays the role of Swift's `async`, and there is no `CancellationToken` wired up here, matching the Edge Cases entry on cancellation.

## Design Decisions

**Decision**: presentation is always a sheet, never an application-modal alert.
**Rationale**: stated in the type's own doc comment — this is an `LSUIElement` menu-bar app for which `NSAlert.runModal()` would activate the app and make its window key, seizing the screen from whoever is typing, and would additionally block the main thread until dismissed, risking a UI wedge if no window happens to be available.
**Approved**: pending

**Decision**: with no window anywhere in the app, the message is dropped (logged, resolved `nil`) rather than shown by any other means.
**Rationale**: stated in the type's own doc comment — there is no surface a sheet can attach to that does not seize the screen, so the message is logged and resolved the same as a user dismissal, a state `vscode.d.ts` already requires every caller to handle; losing one extension's message is judged the smaller harm.
**Approved**: pending

**Decision**: `window` is an injected closure with no default value.
**Rationale**: stated in `init(window:)`'s own doc comment — the no-window fallback must be an explicit choice a caller made, not an incidental default the initializer picked, and not guessed at from `NSApplication.shared` or another ambient source.
**Approved**: pending

**Decision**: `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)` are `internal`, not `private`.
**Rationale**: stated in both functions' own doc comments — `MainThreadWindowTests` calls each directly through `@testable import AgenticToolkitMacOS`, and tightening either to `private` compiles here but breaks that suite.
**Approved**: pending

**Decision**: Escape is assigned to the cancel-slot button only when the plan has more than one entry.
**Rationale**: stated in `escapeKeyEquivalentPosition(in:)`'s own doc comment — on a one-entry plan, the cancel slot is also the sole button, which `NSAlert` already gives Return by default; assigning Escape there would replace Return (and its default-button status) for no behavioral gain, since a one-entry plan only arises when every item was flagged and the sole button already is the close affordance.
**Approved**: pending

**Decision**: `closeAffordanceIndices`'s last-wins tie-break in the cancel slot is applied here, not re-derived here.
**Rationale**: the rule itself — the *last* flagged item's index wins the single cancel slot — is documented in full, with its upstream justification, in ExtensionMessagePresenting's Design Decisions; **button-plan-cancel-slot** in this recipe applies that same rule to this conformer's concrete AppKit button layout rather than restating the rationale.
**Approved**: pending

**Decision**: `presentedResponse(for:)` bridges `beginSheetModal(for:completionHandler:)` into `async` with `withCheckedContinuation`, unlike every other `beginSheetModal` site in this tier.
**Rationale**: stated in the source's own doc comment as a claim measured against the rest of the `macOS/` tier — every other `beginSheetModal` site (`ComposableTabsPaneViewController`, `AISettingsViewPanelController`, `ExtensionsSettingsPanelViewController`, `NotesFolderListViewController`, `NotesSplitViewController`) drives its completion handler directly, while this presenter must be `async` to satisfy `ExtensionMessagePresenting`; `withCheckedContinuation` itself is not unprecedented in the tier (`ExtensionHost.swift` uses one for a JS activation callback), only its pairing with `NSAlert`/`beginSheetModal` is.
**Approved**: pending

**Decision**: this recipe traces `presentMessage(_:)`, `sheetWindow()`, `presentedResponse(for:)`, `alertStyle(for:)`, and `anyVisibleWindow()` to the source only, with no given test exercising any of them directly.
**Rationale**: every case in `MainThreadWindowTests.swift` that exercises message presentation substitutes a `RecordingMessagePresenter` or `SuspendingMessagePresenter` test double for `NSAlertMessagePresenter` precisely to avoid putting a real sheet on screen during a test run; `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)` were split out as `internal`, side-effect-free functions specifically so something about the button layout could still be pinned without running `beginSheetModal(for:completionHandler:)`.
**Approved**: pending
