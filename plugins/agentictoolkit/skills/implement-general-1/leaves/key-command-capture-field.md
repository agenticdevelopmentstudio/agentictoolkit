<!-- leaf: implement-general-1/key-command-capture-field · source: key-command-capture-field.md -->

**Rules** (cite as `implement-general-1/key-command-capture-field#<slug>`):

- `main-actor-confinement` MUST
- `coder-initialization-rejection` MUST
- `click-focus` MUST
- `focus-recording-start` MUST
- `resign-recording-stop` MUST
- `redundant-recording-notification-suppression` MUST
- `recording-change-reporting` MUST
- `manual-recording-stop` MUST
- `idle-end-recording-noop` MUST
- `end-recording-resignation` MUST
- `end-recording-force-stop` MUST
- `recording-key-equivalent-interception` MUST
- `idle-key-equivalent-deferral` MUST
- `incidental-modifier-stripping` MUST
- `bare-escape-cancel` MUST
- `bare-return-commit` MUST
- `unmodified-tab-passthrough` MUST
- `modified-tab-capture` MUST
- `captured-chord-reporting` MUST
- `unconstructible-chord-ignore` MUST
- `uncaptured-key-down-passthrough` MUST
- `recording-placeholder-display` MUST
- `pending-shortcut-priority` MUST
- `prior-text-retention` MUST
- `idle-placeholder-display` MUST
- `pointing-hand-cursor` MUST
- `theme-change-repaint` MUST
- `recording-state-border-color` MUST
- `shortcut-presence-text-color` MUST

# KeyCommandCaptureField

## Overview

`KeyCommandCaptureField`
(`packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandCaptureField.swift`)
is the field a user clicks into and then presses the keys they want recorded
as a key command. It looks like a text field but is deliberately not one: per
the source's own doc comment, a field editor would eat the very chords being
recorded, and `NSTextField`'s own key handling turns Cmd-anything into an edit
command. So `KeyCommandCaptureField` is a plain focusable `NSView` that paints
its own bezel and reads key events directly, overriding both
`performKeyEquivalent(with:)` (so Cmd-chords, which AppKit offers down the
key-equivalent chain before `keyDown`, are not claimed by a menu item or the
window first) and `keyDown(with:)` (for everything else). It records and
reports captured chords, a bare-Escape cancel, and a bare-Return/Enter commit
through closures; it never persists anything itself. Committing a captured
chord is the hosting row's business (the source names `KeyCommandRowView` as
the intended caller) because a captured chord is *pending* until the user
says otherwise, and this component's own loss of focus must not silently
decide that either way.

## Behavioral Requirements

- **main-actor-confinement**: Component MUST be usable only on the main actor;
  the class is declared `@MainActor`.
- **coder-initialization-rejection**: Component MUST NOT support construction
  via `init(coder:)`; that initializer MUST trigger a fatal error.
- **click-focus**: Component MUST become the window's first responder in
  response to `mouseDown(with:)`, for any click location within its bounds (no
  sub-region hit-testing is performed).
- **focus-recording-start**: Component MUST set `isRecording` to `true`
  when `becomeFirstResponder()` is called and the superclass call succeeds.
- **resign-recording-stop**: Component MUST set `isRecording` to `false`
  when `resignFirstResponder()` is called and the superclass call succeeds.
- **redundant-recording-notification-suppression**: Component MUST NOT act on
  (re-render text, re-theme, or invoke `onRecordingChanged`) a write to
  `isRecording` that sets it to its current value.
- **recording-change-reporting**: Component MUST invoke `onRecordingChanged`
  with the new value exactly when `isRecording` actually changes.
- **manual-recording-stop**: Component MUST expose a public
  `endRecording()` method.
- **idle-end-recording-noop**: `endRecording()` MUST be a no-op when
  `isRecording` is already `false`.
- **end-recording-resignation**: When `endRecording()` runs
  while `isRecording` is `true` and this view is the window's current first
  responder, Component MUST call `window?.makeFirstResponder(nil)`.
- **end-recording-force-stop**: When `endRecording()` runs
  while `isRecording` is `true`, Component MUST set `isRecording` to `false`
  directly afterward, regardless of whether this view was the window's first
  responder and regardless of whether the resignation above succeeded — the
  source's own comment describes this as stopping recording "without going
  through the responder chain," which is what lets the hosting row end
  recording from code that itself committed or abandoned the edit.
- **recording-key-equivalent-interception**: While `isRecording` is
  `true`, Component MUST evaluate every event passed to
  `performKeyEquivalent(with:)` through its own chord-capture logic instead of
  deferring to `super.performKeyEquivalent(with:)`.
- **idle-key-equivalent-deferral**: While `isRecording` is `false`,
  Component MUST return `super.performKeyEquivalent(with: event)` unevaluated
  by its own capture logic.
- **incidental-modifier-stripping**: Before classifying a key event as
  Escape, Return/Enter, or Tab, Component MUST compute a modifier set from the
  event's modifier flags restricted to `.deviceIndependentFlagsMask` with
  `.function`, `.numericPad`, and `.capsLock` removed, so that an event
  carrying an incidental Fn or CapsLock bit is not misclassified as
  "modified."
- **bare-escape-cancel**: While recording, Component MUST invoke
  `onCancel` and consume the event when the pressed key is Escape and the
  stripped modifier set is empty.
- **bare-return-commit**: While recording, Component MUST invoke
  `onCommit` and consume the event when the pressed key is Return or the
  keypad Enter key and the stripped modifier set is empty.
- **unmodified-tab-passthrough**: While recording, Component MUST NOT
  capture Tab pressed with an empty stripped modifier set or with only Shift;
  it MUST return `false` from its capture logic (not consuming the event) so
  normal focus traversal continues.
- **modified-tab-capture**: While recording, Component MUST treat Tab
  combined with any modifier other than (or in addition to) Shift alone — for
  example Option-Tab or Control-Tab — as an ordinary capturable chord, not as
  a focus-navigation key.
- **captured-chord-reporting**: While recording, for any key event that is not
  the bare-Escape, bare-Return, or passthrough-Tab case, Component MUST
  attempt to construct a `KeyboardShortcuts.Shortcut` from the raw event and,
  when construction succeeds, MUST invoke `onCapture` with that shortcut and
  consume the event. This MUST happen for every distinct chord captured while
  recording, not only the first.
- **unconstructible-chord-ignore**: While recording, when
  `KeyboardShortcuts.Shortcut(event:)` returns `nil` for a key event that is
  not the bare-Escape, bare-Return, or passthrough-Tab case, Component MUST
  NOT invoke `onCapture`, `onCancel`, or `onCommit`, and MUST NOT consume the
  event (its capture logic returns `false`).
- **uncaptured-key-down-passthrough**: Component's `keyDown(with:)`
  MUST call `super.keyDown(with: event)` whenever `isRecording` is `false`,
  or whenever `isRecording` is `true` but its capture logic returns `false`
  for that event.
- **recording-placeholder-display**: Component MUST display the literal text
  "Press keys…" in place of a shortcut description whenever it is recording
  and neither `pendingShortcut` nor `displayedShortcut` is set.
- **pending-shortcut-priority**: Whenever `pendingShortcut` is
  non-nil, Component MUST render `pendingShortcut`'s `description` instead of
  `displayedShortcut`'s, regardless of recording state. This MUST take effect
  immediately when either property is set (both have a `didSet` that calls
  the same text-refresh routine).
- **prior-text-retention**: When recording starts while
  `displayedShortcut` is already non-nil and `pendingShortcut` is still nil,
  Component MUST continue displaying `displayedShortcut`'s description (MUST
  NOT switch to "Press keys…") until the caller sets `pendingShortcut` in
  response to a chord the component reported through `onCapture`.
- **idle-placeholder-display**: Component MUST display its
  `placeholder` string (default the literal "Click to record") when not
  recording and neither `pendingShortcut` nor `displayedShortcut` is set.
- **pointing-hand-cursor**: Component MUST register the pointing-hand
  cursor over its full bounds via `resetCursorRects()`.
- **theme-change-repaint**: Component MUST re-derive its background
  color, border color, label font, and label text color from the current
  `SemanticPalette` every time the active theme changes, and once
  synchronously during initialization.
- **recording-state-border-color**: Component MUST draw its 1pt layer
  border in the palette's `accentColor` while recording and in the palette's
  `borderColor` otherwise.
- **shortcut-presence-text-color**: Component MUST draw its label text in
  the palette's `primaryTextColor` whenever `pendingShortcut ?? displayedShortcut`
  is non-nil, and in the palette's `placeholderTextColor` otherwise (covering
  both the "Press keys…" and `placeholder` text cases).

## Appearance

- **Corner radius**: 5pt (`layer?.cornerRadius = 5`).
- **Padding**: The label is pinned 6pt in from the view's leading and
  trailing edges (`constant: 6`/`constant: -6`) and centered vertically
  (`centerYAnchor`); there is no separate top/bottom padding constant —
  vertical position is centering within the fixed 22pt height, not an inset.
- **Font**: `palette.font(.button)`, which resolves via
  `theme.typography.style(.button).nsFont(scaledSize:)` to a 13pt, medium
  weight, proportional system font by default (`FontStyle(size: 13, weight:
  .medium)` in `ThemeTypography.swift`); the size scales with the active
  theme's `sizeScale` and the label repaints on every theme change (see
  theme-change-repaint).
- **Background**: The layer's `backgroundColor` is set to
  `palette.controlBackgroundColor` (the theme's `controlBackground` role,
  resolved to a fixed sRGB `NSColor` per the active theme — not a
  system-dynamic color).
- **Foreground/Text**: See shortcut-presence-text-color — `primaryTextColor`
  when a shortcut is shown, `placeholderTextColor` otherwise.
- **Border**: 1pt width (`layer?.borderWidth = 1`, a fixed constant, not
  theme-scaled); color per recording-state-border-color.
- **Shadow**: Not applicable — no shadow property is set or drawn anywhere in
  `KeyCommandCaptureField.swift`.
- **Min/Max size**: Height is fixed at exactly 22pt
  (`heightAnchor.constraint(equalToConstant: 22)`). Width has a minimum of
  132pt (`widthAnchor.constraint(greaterThanOrEqualToConstant: 132)`) and no
  explicit maximum; how wide the view actually grows is left to whatever
  layout hosts it (the source names `KeyCommandRowView`'s row).

