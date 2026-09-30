<!-- leaf: implement-general-1/key-command-capture-field--test-vectors · source: key-command-capture-field.md -->

# KeyCommandCaptureField

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| kccf-001 | main-actor-confinement | Attempt to construct or mutate a `KeyCommandCaptureField` from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
| kccf-002 | coder-initialization-rejection | Attempt `KeyCommandCaptureField(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| kccf-003 | click-focus | Send `mouseDown(with:)` to an on-screen, unfocused field at any point within its bounds | `window.makeFirstResponder` is invoked with the field as its argument |
| kccf-004 | focus-recording-start | Call `becomeFirstResponder()` on an unfocused field whose window accepts it | `isRecording == true` after the call; `onRecordingChanged` fires with `true` |
| kccf-005 | resign-recording-stop | Call `resignFirstResponder()` on a recording field whose window accepts the resignation | `isRecording == false` after the call; `onRecordingChanged` fires with `false` |
| kccf-006 | redundant-recording-notification-suppression | With `isRecording == true`, trigger another `becomeFirstResponder()` success (already first responder) | `onRecordingChanged` is not invoked a second time; no additional text/theme refresh is observed |
| kccf-007 | recording-change-reporting | Toggle focus onto then off of the field | `onRecordingChanged` fires exactly twice: once with `true`, once with `false` |
| kccf-008 | idle-end-recording-noop | Call `endRecording()` on a field where `isRecording == false` | No change to first responder, `isRecording`, or `onRecordingChanged` invocation |
| kccf-009 | end-recording-resignation | Field is recording and is the window's first responder; call `endRecording()` | `window.makeFirstResponder(nil)` is invoked |
| kccf-010 | end-recording-force-stop | Field is recording but is not currently the window's first responder (e.g. focus already moved); call `endRecording()` | `isRecording == false` after the call, and `window.makeFirstResponder(nil)` is NOT invoked (the `if window?.firstResponder === self` guard is skipped) |
| kccf-011 | recording-key-equivalent-interception | Field is recording; send `performKeyEquivalent(with:)` for ⌘K | The field's own capture logic evaluates the event (⌘K is not passed to `super.performKeyEquivalent`); `onCapture` fires with the ⌘K shortcut |
| kccf-012 | idle-key-equivalent-deferral | Field is not recording; send `performKeyEquivalent(with:)` for ⌘K | `super.performKeyEquivalent(with:)`'s return value is what the method returns; `onCapture` does not fire |
| kccf-013 | incidental-modifier-stripping | Field is recording; send an Escape key event whose raw `modifierFlags` includes `.capsLock` (Caps Lock is physically on) but no Shift/Control/Option/Command | `onCancel` fires (the event is still classified as "unmodified Escape" after stripping `.capsLock`) |
| kccf-014 | incidental-modifier-stripping | Field is recording; send a Return key event whose raw `modifierFlags` includes `.capsLock` (Caps Lock is physically on) but no Shift/Control/Option/Command | `onCommit` fires (the event is still classified as "unmodified Return" after stripping `.capsLock`) |
| kccf-015 | bare-escape-cancel | Field is recording; send Escape with no modifiers | `onCancel` fires; the event is consumed (capture logic returns `true`) |
| kccf-016 | bare-return-commit | Field is recording; send Return with no modifiers | `onCommit` fires; the event is consumed |
| kccf-017 | bare-return-commit | Field is recording; send the keypad Enter key with no modifiers | `onCommit` fires; the event is consumed |
| kccf-018 | unmodified-tab-passthrough | Field is recording; send Tab with no modifiers | Capture logic returns `false`; `onCapture`/`onCancel`/`onCommit` do not fire; focus is free to advance |
| kccf-019 | unmodified-tab-passthrough | Field is recording; send Shift-Tab | Capture logic returns `false`; the event is not consumed |
| kccf-020 | modified-tab-capture | Field is recording; send Option-Tab | `KeyboardShortcuts.Shortcut(event:)` is constructed and `onCapture` fires with it; the event is consumed |
| kccf-021 | captured-chord-reporting | Field is recording; send ⌘⇧K, then ⌥⌘P | `onCapture` fires twice, once per chord, each with the corresponding `Shortcut` |
| kccf-022 | unconstructible-chord-ignore | Field is recording; send a bare modifier-key-down event (e.g. Command pressed alone, no other key) that `KeyboardShortcuts.Shortcut(event:)` returns `nil` for | `onCapture`/`onCancel`/`onCommit` do not fire; the event is not consumed |
| kccf-023 | uncaptured-key-down-passthrough | Field is not recording; send `keyDown(with:)` for any key | `super.keyDown(with: event)` is invoked |
| kccf-024 | recording-placeholder-display | Field has no `pendingShortcut` and no `displayedShortcut`; call `becomeFirstResponder()` | Label text becomes "Press keys…" |
| kccf-025 | pending-shortcut-priority | `displayedShortcut` is set to shortcut A; set `pendingShortcut` to shortcut B | Label text immediately shows B's `description`, not A's |
| kccf-026 | prior-text-retention | `displayedShortcut` is set to shortcut A, `pendingShortcut` is nil; call `becomeFirstResponder()` | Label text remains A's `description` (does NOT change to "Press keys…") until a chord is captured |
| kccf-027 | idle-placeholder-display | `pendingShortcut` and `displayedShortcut` are both nil, `isRecording == false`, default `placeholder` | Label text reads "Click to record" |
| kccf-028 | pointing-hand-cursor | Query cursor rects for the field's bounds | A pointing-hand cursor rect covers the full bounds |
| kccf-029 | theme-change-repaint | Field is on screen with theme T1; switch the active theme to T2 | Layer background/border color and label font/text color are re-read from T2's `SemanticPalette` without further user action |
| kccf-030 | recording-state-border-color | Compare a non-recording field to the same field once it starts recording | Border color changes from `borderColor` to `accentColor` |
| kccf-031 | shortcut-presence-text-color | Compare a field with `displayedShortcut` set to one with none | Text color is `primaryTextColor` when a shortcut is shown, `placeholderTextColor` when none is |
