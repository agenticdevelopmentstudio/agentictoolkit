<!-- leaf: implement-general-view-2/key-command-row-view--test-vectors · source: key-command-row-view.md -->

# KeyCommandRowView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| key-command-row-view-001 | appends-colon-to-title | Construct with `command.title == "Move Selection Up"` | Title label's `stringValue == "Move Selection Up:"` |
| key-command-row-view-002 | arranges-main-row | Construct any row | Title label, capture field, confirm/cancel pair, and toggle are all subviews of one horizontal row, in that left-to-right order |
| key-command-row-view-003 | stacks-main-and-readout-rows | Construct any row | The main row and the readout row are the only two arranged views of a vertical stack pinned to the component's own edges, with 4pt spacing between them |
| key-command-row-view-004 | hides-confirm-cancel-when-not-editing | Construct any row (not mid-edit) | Confirm/cancel pair's `isHidden == true`; after entering the mid-edit state, `isHidden == false` |
| key-command-row-view-005 | hides-readout-row-when-idle | Construct any row (not mid-edit, no refusal) | Readout row's `isHidden == true`; after entering the mid-edit state, `isHidden == false` |
| key-command-row-view-006 | links-toggle-accessibility-title | Construct any row | Toggle's accessibility title UI element is the title label |
| key-command-row-view-007 | sets-capture-field-accessibility-identifier | Construct with `command.id == "widgets.undo"` | Capture field's accessibility identifier is `"settings.key-commands.widgets.undo.recorder"` |
| key-command-row-view-008 | sets-toggle-accessibility-identifier | Construct with `command.id == "widgets.undo"` | Toggle's accessibility identifier is `"settings.key-commands.widgets.undo.enabled"` |
| key-command-row-view-009 | begins-editing-on-capture | Trigger the capture field's captured-chord callback with a chord | Row's pending shortcut and the capture field's pending shortcut both equal the captured chord; row enters the mid-edit state |
| key-command-row-view-010 | begins-editing-on-recording-start | Trigger the capture field's recording-changed callback with `true` | Row enters the mid-edit state |
| key-command-row-view-011 | forwards-recording-state-to-registry | Trigger the capture field's recording-changed callback with `true`, then `false` | `registry.isRecordingChord` is `true` then `false`, matching each call |
| key-command-row-view-012 | ends-editing-when-recording-stops-with-nothing-pending | With no chord captured, trigger the recording-changed callback with `false` | Row leaves the mid-edit state |
| key-command-row-view-013 | keeps-editing-open-when-recording-stops-with-a-pending-chord | Capture a chord, then trigger the recording-changed callback with `false` | Row remains in the mid-edit state |
| key-command-row-view-014 | refuses-commit-without-a-pending-chord | With no chord pending, invoke the capture field's commit callback | No binding is written to the registry; the row remains in its prior edit state |
| key-command-row-view-015 | refuses-commit-of-an-unavailable-chord | Capture a chord already bound to another command, then invoke commit | No binding is written for this command; the edit remains open; the status label reflects the "taken by" reason |
| key-command-row-view-016 | enables-command-on-first-or-unbound-commit | `KeyCommandBehaviourTests.testRecordingOverAShippedOffCommandSwitchesItOn`: command ships with `isEnabledByDefault == false` and no authored binding; capture a free chord and commit | Committed binding's `isEnabled == true` |
| key-command-row-view-017 | preserves-enabled-state-on-rebind | Command has an authored binding with `isEnabled == false` and a non-nil shortcut; capture a different free chord and commit | Committed binding's `isEnabled == false` (preserved) |
| key-command-row-view-018 | commits-pending-chord-to-registry | Capture a free chord and commit | `registry.binding(for: command.id).shortcut` equals the captured chord |
| key-command-row-view-019 | clears-edit-state-after-commit-or-cancel | Capture a chord, commit | Row's pending shortcut is `nil`, capture field's pending shortcut is `nil`, capture field is no longer recording, row leaves the mid-edit state |
| key-command-row-view-020 | refreshes-after-commit-or-cancel | Capture a free chord and commit | Capture field's displayed shortcut updates to the newly committed chord immediately after commit |
| key-command-row-view-021 | cancels-without-writing-a-binding | Capture a chord, then invoke cancel | `registry.binding(for: command.id)` is unchanged from before the capture |
| key-command-row-view-022 | refuses-toggle-on-when-the-current-chord-is-taken | `KeyCommandBehaviourTests.testTheSwitchRefusesToPutATakenChordBackInPlay`: command's own (disabled) shortcut is now held by another command; switch the toggle on | Toggle snaps back to off; `registry.binding(for: command.id).isEnabled` remains `false` |
| key-command-row-view-023 | clears-refusal-on-an-accepted-toggle-change | After a refused toggle-on attempt (status label shows a refusal), switch the toggle off | Refusal message is cleared; status label no longer shows the refusal text |
| key-command-row-view-024 | commits-accepted-toggle-state | Command has a free, bound shortcut; switch the toggle off | `registry.binding(for: command.id).isEnabled == false`; shortcut unchanged |
| key-command-row-view-025 | refreshes-on-external-bindings-change | Post `KeyCommandRegistry.bindingsDidChangeNotification` for the observed registry after another row changes a binding | Row's subviews (capture field, toggle, status label) re-read and reflect the current registry state |
| key-command-row-view-026 | reflects-bound-shortcut-on-refresh | Set a binding with a shortcut directly on the registry, then trigger refresh | Capture field's displayed shortcut equals the binding's shortcut |
| key-command-row-view-027 | shows-placeholder-when-unbound | Command has no bound shortcut; trigger refresh | Capture field's placeholder is `"Click to record"` |
| key-command-row-view-028 | reflects-enabled-state-on-refresh | Set a binding with `isEnabled == true`, then trigger refresh | Toggle's state is on |
| key-command-row-view-029 | disables-toggle-without-a-bound-shortcut | Command has no bound shortcut; trigger refresh | Toggle's enabled flag is `false` |
| key-command-row-view-030 | shows-refusal-in-status-label | Trigger a refused toggle-on attempt | Status label's text is `"can't switch on — <reason>"`; status label's role is danger |
| key-command-row-view-031 | shows-unavailable-reason-while-pending | Capture a chord already bound to another command | Status label's text is `"unavailable — taken by <other command's title>"` |
| key-command-row-view-032 | prompts-for-a-chord-while-pending-is-empty | Enter the mid-edit state before any chord is captured | Status label's text is `"press a key combination"` |
| key-command-row-view-033 | shows-availability-label-for-an-available-pending-chord | Capture a free chord | Status label's text is `"available"` |
| key-command-row-view-034 | colors-status-label-by-availability | Capture a free chord, then capture one already taken | Status label's role is success for the free chord and danger for the taken chord |
| key-command-row-view-035 | gates-confirm-by-availability | Capture a chord already bound to another command | Confirm/cancel pair's confirm-enabled flag is `false` |
| key-command-row-view-036 | requires-a-command-and-a-registry-to-construct | Inspect `KeyCommandRowView`'s public initializers | Only `init(command:registry:)` is available; both parameters are non-optional |
| key-command-row-view-037 | rejects-coder-initialization | Attempt `KeyCommandRowView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| key-command-row-view-038 | removes-its-notification-observer-on-deinit | Construct a row, capture its notification observer, then release the row | The observer is removed from `NotificationCenter.default`; no further calls into the deallocated row occur when the notification is posted again |
| key-command-row-view-039 | confines-to-main-actor | Attempt to construct or mutate a `KeyCommandRowView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| key-command-row-view-040 | preserves-pending-edit-on-external-change | Capture a chord (mid-edit, chord pending), then post `KeyCommandRegistry.bindingsDidChangeNotification` for a change made by a sibling row | Row's pending shortcut is unchanged and the row remains in the mid-edit state; the capture field's displayed shortcut and the toggle still reflect the refreshed binding |
| key-command-row-view-041 | clears-edit-state-after-commit-or-cancel | Capture a chord, then invoke cancel | Row's pending shortcut is `nil`, capture field's pending shortcut is `nil`, capture field is no longer recording, row leaves the mid-edit state |
| key-command-row-view-042 | refreshes-after-commit-or-cancel | Capture a chord, then invoke cancel | Capture field's displayed shortcut and the toggle's state are re-read from the registry immediately after cancel |
