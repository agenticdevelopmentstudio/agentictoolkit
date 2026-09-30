<!-- leaf: implement-general-1/key-command-capture-field--edge-cases · source: key-command-capture-field.md -->

# KeyCommandCaptureField

## Edge Cases

- Null/empty input: `placeholder` is a non-optional `String`; an empty string
  assigned to it produces an empty label with no crash, and the component
  needs no additional nil-handling because none of its stored properties
  (`displayedShortcut`, `pendingShortcut` are `Optional` by type; `placeholder`
  is non-optional) admit an unhandled null case.
- Boundary values: Not applicable in the numeric-range sense — the two
  layout constants (22pt fixed height, 132pt minimum width) are fixed
  architectural constants, not user-adjustable inputs with a min/max to
  probe, and every key-code comparison in `capture(_:)` is an exact `==`
  equality check on a `UInt16`, not a range comparison that could be
  off-by-one.
- Concurrent access: Not applicable — the class is `@MainActor`-confined
  (see main-actor-confinement), so all construction, focus changes, and key
  handling are serialized to the main actor by the compiler.
- Error states: Not applicable in the thrown-error sense — no `try`,
  `Result`, or throwing call appears anywhere in
  `KeyCommandCaptureField.swift`. The one call that can fail,
  `KeyboardShortcuts.Shortcut(event:)`, is a failable initializer (returns
  `Optional`, not a thrown error) and its `nil` case is handled by
  unconstructible-chord-ignore rather than propagated or crashed on.
- Offline/disconnected: Not applicable — the component performs no
  networking of any kind.
- Uncaptured key falls to default `NSResponder` behavior: when `keyDown(with:)`
  calls `super.keyDown(with: event)` (idle, or recording with an
  unconstructible chord), AppKit's own default `NSResponder.keyDown`
  implementation applies, which for a plain `NSView` with no further
  responder-chain handler typically produces the system alert beep. This is
  standard, unmodified AppKit behavior triggered by this file's own fallback,
  not a custom sound the component plays.
- Re-clicking while already recording: `mouseDown(with:)` unconditionally
  claims first responder even if the field is already first responder;
  redundant-recording-notification-suppression means this has no effect on
  `isRecording` or `onRecordingChanged`.
- `endRecording()` called when the window has since been deallocated or has
  no first responder at all: `window?.firstResponder === self` evaluates
  `false` through the optional chain, so the resignation branch is skipped
  and only the unconditional `isRecording = false` runs (see
  end-recording-force-stop).
