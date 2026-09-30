<!-- leaf: implement-general-1/key-command-capture-field--states · source: key-command-capture-field.md -->

# KeyCommandCaptureField

## States

| State | Appearance change |
|-------|------------------|
| Default (idle, no shortcut) | Border color = `borderColor`; label shows `placeholder` ("Click to record" by default) in `placeholderTextColor`. |
| Idle with a shortcut | Border color = `borderColor`; label shows `displayedShortcut.description` in `primaryTextColor`. |
| Recording, nothing shown yet | Border color = `accentColor`; label shows "Press keys…" in `placeholderTextColor` (see recording-placeholder-display). |
| Recording, prior shortcut still showing | Border color = `accentColor`; label continues showing `displayedShortcut.description` in `primaryTextColor` until the first chord is captured (see prior-text-retention) — the border color is the only visual difference from the idle-with-a-shortcut state at this instant. |
| Recording, chord captured (pending) | Border color = `accentColor`; label shows `pendingShortcut.description` in `primaryTextColor`. |
| Pressed | Not applicable: the component draws no separate pressed/mouse-down visual; `mouseDown(with:)` only reassigns first responder, and any resulting border-color change is the Recording transition above, not a press state. |
| Disabled | Not implemented in source: `isEnabled`/`enabled` is never read, set, or checked anywhere in `KeyCommandCaptureField.swift`. |
| Focused | Not styled as a distinct state: gaining focus and entering the Recording state are the same event (`becomeFirstResponder()` sets `isRecording = true`); the accent-colored border **is** this component's only focus indicator. |
| Loading | Not applicable — the component has no asynchronous operation and no loading indicator in source. |
