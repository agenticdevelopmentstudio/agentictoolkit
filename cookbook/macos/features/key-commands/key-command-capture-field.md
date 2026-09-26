---
id: 969b7f76-3fff-4a13-9b85-a61df25c70ee
title: KeyCommandCaptureField
domain: agentictoolkit://cookbook/macos/features/key-commands/key-command-capture-field
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Bespoke macOS NSView that records key-command chords and reports capture/cancel/commit
  without persisting.
platforms:
- swift
- macos
tags:
- keyboard-shortcut
- recorder
- focus
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/key-commands/key-command-row-view
references:
- https://github.com/sindresorhus/KeyboardShortcuts
approved-by: ''
approved-date: ''
---

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

## Accessibility

- **Role/trait**: Not implemented in source. No
  `setAccessibilityRole`, `setAccessibilityLabel`, or accessibility
  title-element link — unlike `KeyCommandRowView`
  (`agentictoolkit://cookbook/macos/features/key-commands/key-command-row-view`), whose sibling toggle
  control links to its label via `setAccessibilityTitleUIElement` — appears
  anywhere in `KeyCommandCaptureField.swift`; the view relies entirely on
  `NSView`'s default accessibility exposure. The view is an interactive,
  first-responder-accepting control whose whole purpose is recording user
  input, and this file assigns it no accessibility role or label of its
  own; any such assignment is left entirely to the caller.
- **Label requirements**: Not implemented in source. This file
  sets no accessibility label of its own; a caller may assign one externally
  (accessibility identifiers, not labels, are assigned by the hosting row
  outside this file), but nothing in `KeyCommandCaptureField.swift` guarantees
  VoiceOver announces this control's purpose. This is the same gap as the
  Role/trait item above.
- **Announce state changes**: Not implemented in source. No
  `NSAccessibility.post(element:notification:)` call (or equivalent)
  accompanies the `isRecording` transition or a captured/committed/cancelled
  chord anywhere in source, so a VoiceOver user is not told the control
  entered or left recording mode.
- **Minimum tap target**: Not applicable to the 44×44pt touch threshold — this
  is a macOS, pointer/keyboard-driven `NSView`/`NSResponder`, with no touch
  input path in source. Its actual click target is fixed at 22pt tall by a
  minimum of 132pt wide (see Min/Max size), matching this file's own layout
  constants, not a touch guideline.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Every color this component draws (`controlBackgroundColor`, `accentColor`/`borderColor`, `primaryTextColor`/`placeholderTextColor`) is resolved at runtime from whichever `SemanticPalette` the active theme supplies, and `KeyCommandCaptureField.swift` performs no contrast check of its own, so whether text-on-background or border-on-background contrast meets a specific ratio (e.g. WCAG 4.5:1) cannot be determined from this source file alone — it would require auditing the contrast ratio of each theme's actual token values.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `onCapture` | `((KeyboardShortcuts.Shortcut) -> Void)?` | `nil` | Called for every chord captured while recording. |
| `onCancel` | `(() -> Void)?` | `nil` | Called when the user presses bare Escape while recording. |
| `onCommit` | `(() -> Void)?` | `nil` | Called when the user presses bare Return or keypad Enter while recording. |
| `onRecordingChanged` | `((Bool) -> Void)?` | `nil` | Called when recording starts (click/focus) or stops (resign focus/`endRecording()`). |
| `displayedShortcut` | `KeyboardShortcuts.Shortcut?` | `nil` | The shortcut the bound command is already assigned to; shown when nothing is pending. |
| `pendingShortcut` | `KeyboardShortcuts.Shortcut?` | `nil` | The chord captured but not yet saved; takes precedence over `displayedShortcut` when set. The component only reads this property to decide what to display — it never assigns or clears it itself. The caller sets it (typically from `onCapture`) and clears it once the edit is committed or abandoned. |
| `placeholder` | `String` | the literal `"Click to record"` | Shown when there is nothing pending, displayed, or being recorded. |

## Deep Linking

Not applicable: `KeyCommandCaptureField` is a focus target embedded in a
settings row, not a navigable screen or destination; no URL scheme, route, or
deep-link handler appears anywhere in `KeyCommandCaptureField.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (unassigned) | `Click to record` | Default value of the `placeholder` property, assigned directly to an AppKit `NSTextField.stringValue` when nothing is captured, displayed, or being recorded. |
| (unassigned) | `Press keys…` | Literal assigned directly to `label.stringValue` in `refreshText()` while recording with nothing pending or displayed. |

Both strings above are literal `String` values assigned to an AppKit
`stringValue`, which — unlike a string literal passed to a SwiftUI
`Text`/`Label` (a `LocalizedStringKey`) — does not localize on its own;
`KeyCommandCaptureField.swift` contains no `NSLocalizedString`,
string-catalog key reference, or other localization mechanism for either
literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, movement, scaling, or `CATransaction`/animator-proxy call; every appearance change (`refreshText()`, `applyTheme()`) is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this component directly: `KeyCommandCaptureField.swift` reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`), and neither does the `SemanticPalette` color-resolution path it calls into; whether the resulting colors are contrasty enough is tracked once, under the open question on minimum-contrast-ratio in Accessibility above, not duplicated here. |
| Differentiate Without Color | During the "prior shortcut still showing" transition, the border color changing from `borderColor` to `accentColor` is the only indicator that recording has begun; no icon, text, or shape change accompanies it until a chord is captured, unlike every other state, where the text itself changes. The component does not respond to Differentiate Without Color. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `KeyCommandCaptureField.swift`; the field always behaves identically once
constructed.

## Analytics

Not applicable: `KeyCommandCaptureField.swift` contains no analytics or
telemetry call. `onCapture`/`onCommit`/`onCancel`/`onRecordingChanged` are
behavioral callbacks for the hosting row, not telemetry events.

## Privacy

- **Data collected**: Not applicable — the component captures a keyboard
  chord configuration (a key plus modifiers), not personal data, and only
  for as long as it is held in `pendingShortcut`/`displayedShortcut`.
- **Storage**: Not applicable — `KeyCommandCaptureField.swift` performs no
  read or write to disk, `UserDefaults`, or any other store; the source's own
  doc comment is explicit that this component "records and reports; it never
  saves." Persistence, if any, is owned by whatever the hosting row commits
  the chord to, which is outside this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: `pendingShortcut` and `displayedShortcut` are retained only
  in memory for the view's own lifetime. Neither is cleared by `endRecording()`
  or anywhere else in this file — `endRecording()` only stops recording (see
  end-recording-force-stop); assigning and clearing both properties is
  entirely the caller's responsibility. Either property is overwritten
  whenever the caller sets a new value, or released when the view is
  deallocated; this file writes nothing to persistent storage.

## Logging

Not applicable: `KeyCommandCaptureField.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: There is no built-in SwiftUI equivalent for raw key-equivalent
  interception. Wrap this exact AppKit type in an `NSViewRepresentable`
  rather than reimplementing it, because `onKeyPress`/`.focusable()`
  (macOS 14+) observe key events but do not intercept Cmd-chords ahead of the
  menu/window the way `performKeyEquivalent` does — the same problem the
  source's own doc comment describes for `NSTextField`'s field editor. Expose
  `onCapture`/`onCancel`/`onCommit`/`onRecordingChanged` as `Binding`s or
  closures passed through the representable's coordinator.
- **Compose**: There is no window-level "key equivalent" concept in Compose;
  the closest analog is a focusable composable with
  `Modifier.onPreviewKeyEvent { ... }` on a `FocusRequester`-focused node,
  which sees key events before children (and, at the platform level, before
  most system shortcut handling) the way `performKeyEquivalent` runs before
  the menu/window. Mirror unmodified-tab-passthrough by returning `false`
  (unhandled) for a bare Tab/Shift-Tab `KeyEvent` and drive the
  recording boolean from `Modifier.onFocusChanged`, the Compose analog of
  `becomeFirstResponder`/`resignFirstResponder`.
- **React/Web**: A `<div>` (or a read-only `<input>`, to get a native focus
  ring for free) with `tabIndex={0}` and an `onKeyDown` handler reading
  `event.key`/`event.code` plus the modifier booleans. Call
  `event.preventDefault()` for every combination the field decides to
  capture, since Cmd/Ctrl-chords can otherwise trigger the browser's or OS's
  own shortcuts — the DOM analog of intercepting a key equivalent before the
  menu claims it — but deliberately skip `preventDefault()` for a bare
  Tab/Shift-Tab so native focus order is preserved, mirroring
  unmodified-tab-passthrough. Add `role="button"` (or `role="group"` if the
  recorder is treated as a composite control) plus an explicit `aria-label` to
  supply the accessible label the source itself never assigns (see
  Accessibility above), and an `aria-live="polite"` region announcing
  recording start/stop and the captured-chord description to supply the
  state announcement the source itself never makes (see Announce state
  changes above) — `role="textbox"` would incorrectly tell assistive tech to
  expect editable text, which this control is not.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandCaptureField.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, depending
  on the third-party `KeyboardShortcuts` package (github.com/sindresorhus/
  KeyboardShortcuts) for its `Shortcut` type and key constants, and on
  `AgenticToolkitCore`'s theming (`observeTheme`, `SemanticPalette`). There is
  no UIKit code path in source and none is implied — iOS has no
  key-equivalent chain or hardware-shortcut recording concept comparable to
  this component's purpose. click-focus is implemented as a direct
  `window?.makeFirstResponder(self)` call from `mouseDown(with:)`;
  redundant-recording-notification-suppression is implemented as an early
  return in the `isRecording` property's `didSet` observer when the new value
  equals the old; theme-change-repaint is driven by `observeTheme`, whose
  initializer applies the current palette synchronously before the
  initializer's own first `refreshText()` call runs.
- **WinUI 3**: Build a custom templated `Control` (or `UserControl`) styled to
  look like a `TextBox` — a rounded `Border` (`CornerRadius="5"`, matching this
  recipe's 5pt corner radius exactly, rather than Fluent's small-control
  default of 4) hosting a centered `TextBlock` — and NOT an actual `TextBox`,
  for the same reason the source avoids `NSTextField`: WinUI's
  `TextBox` consumes character input through its own composition/IME
  pipeline and would swallow the very keys being recorded. Override
  `OnPreviewKeyDown` — the WinUI analog of `performKeyEquivalent`, since it
  runs before a `KeyboardAccelerator` or menu can claim a Ctrl-chord — and
  set `e.Handled = true` for every combination the control decides to
  capture; read modifiers from `Windows.System.VirtualKeyModifiers` in place
  of `NSEvent.modifierFlags`. Drive the recording boolean from `GotFocus`/
  `LostFocus` (the WinUI analog of `becomeFirstResponder`/
  `resignFirstResponder`) with `IsTabStop="True"`, and leave `e.Handled =
  false` for a bare `VirtualKey.Tab` so normal `XYFocusKeyboardNavigation`
  still moves focus, mirroring unmodified-tab-passthrough. Represent a
  captured chord as a `VirtualKeyModifiers` + `VirtualKey` pair — WinUI has no
  ready-made equivalent to `KeyboardShortcuts.Shortcut` — and format it for
  display by joining modifier names with `+`, mirroring `Shortcut.description`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandCaptureField.swift` |

## Design Decisions

- **Decision**: Draw a bespoke `NSView` and read raw key events directly, instead
  of using an `NSTextField`.
  **Rationale**: Per the source's own doc comment, a field editor would eat the
  very chords being recorded, and `NSTextField`'s own key handling turns
  Cmd-anything into an edit command.
  **Approved**: pending
- **Decision**: Override `performKeyEquivalent(with:)` in addition to
  `keyDown(with:)`.
  **Rationale**: Per the source's own comment, Cmd-chords never reach `keyDown`
  because AppKit offers them down the key-equivalent chain first (a menu
  item, the window), which would otherwise claim them; this override is what
  makes the recorder work for Cmd-combinations at all.
  **Approved**: pending
- **Decision**: Let bare Tab and Shift-Tab pass through uncaptured while
  Option-Tab/Control-Tab remain capturable.
  **Rationale**: Per the source's own comment, a recorder that swallowed either
  bare form would trap anyone who arrived at the field by tabbing through the
  panel, while a modifier-carrying Tab combination is still a legitimate
  chord to record.
  **Approved**: pending
- **Decision**: `endRecording()` forces `isRecording` to `false` unconditionally,
  not only through the responder-chain path `resignFirstResponder()` takes.
  **Rationale**: Per the source's own comment, this is what the hosting row calls
  once an edit is committed or abandoned, to stop recording "without going
  through the responder chain" — necessary because the row, not the field,
  owns commit, and may need to end recording from code that does not itself
  trigger first-responder resignation.
  **Approved**: pending
- **Decision**: While recording, do not switch the label to "Press keys…" if a
  shortcut is already being displayed or pending; only fall back to "Press
  keys…" when neither is set.
  **Rationale**: `refreshText()` resolves text from a single precedence chain
  (`pendingShortcut ?? displayedShortcut`, else "Press keys…" or
  `placeholder`) with no separate "just started recording" branch. This is
  called out because a reader could otherwise assume "Press keys…" always
  appears the instant recording starts.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`native-controls-preference` is passed, not failed: the component
deliberately avoids the native `NSTextField` control for the reason recorded
in Design Decisions above (a field editor would eat the chords being
recorded), so the deviation is justified rather than an oversight.
`screen-reader-support` is failed because the source implements no
accessibility role, label, or state announcement at all (see Accessibility
above). `contrast-ratio` is partial per the open question on
minimum-contrast-ratio in Accessibility above: the actual colors are
theme-resolved at runtime and cannot be checked against a ratio from this
source file alone. No catalog check covers the one-color-only transition
described under Differentiate Without Color in
Accessibility Options above; it is not represented in this table.
`no-hardcoded-strings` is failed because of the two unlocalized literals
recorded under Localization above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: trimmed summary; renamed requirements to subject-noun kebab-case and updated every cross-reference; reformatted Design Decisions to bold Decision/Rationale/Approved; fixed the AppKit / UIKit platform-notes label; added the KeyboardShortcuts reference URL and the KeyCommandRowView related link; named KeyCommandRowView in the vague accessibility citation; corrected the pendingShortcut-ownership contradiction (the caller assigns and clears it, never the component); replaced the unrealistic Escape+.function test vector with Escape+Caps Lock, added a Return+Caps Lock vector, and renumbered all vectors sequentially; dropped MUST-level edge-case wording not backed by a named requirement; fixed the WinUI corner-radius mismatch and removed an editorializing aside; moved several implementation-coupled requirements (click-focus, redundant-recording-notification-suppression, theme-change-repaint) to observable phrasing with mechanism notes under AppKit / UIKit; replaced the React role="textbox" recommendation with role="button"/"group" plus aria-label and aria-live; and normalized Compliance statuses/category casing and cleaned up citations against the compliance catalog. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
