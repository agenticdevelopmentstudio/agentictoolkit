---
id: 969b7f76-3fff-4a13-9b85-a61df25c70ee
title: Key Command Capture Field
domain: agentictoolkit://cookbook/ui/controls/key-command-capture-field
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A bespoke component that records key-command chords and reports capture/cancel/commit
  without persisting.
platforms:
- swift
- macos
tags:
- keyboard-shortcut
- recorder
- focus
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/key-command-row-view
references:
- https://github.com/sindresorhus/KeyboardShortcuts
approved-by: ''
approved-date: ''
---

# Key Command Capture Field

## Overview

This is the field a user clicks into and then presses the keys they want
recorded as a key command. It looks like a text field but is deliberately
not one: a field editor would eat the very chords being recorded, and a
standard text field's own key handling turns a primary-modifier chord into
an edit command. So this component is a plain focusable view that paints
its own bezel and reads key events directly, intercepting them through the
platform's pre-dispatch key-handling path (so a primary-modifier chord,
which the platform offers to a menu item or the window before ordinary key
handling, is not claimed there first) as well as through its regular
key-handling path (for everything else). It records and reports captured
chords, a bare-Escape cancel, and a bare-Return/Enter commit through
callbacks; it never persists anything itself. Committing a captured chord
is the hosting row's business (a Key Command Row View is the intended
caller) because a captured chord is *pending* until the user says
otherwise, and this component's own loss of focus must not silently decide
that either way.

## Behavioral Requirements

- **main-actor-confinement**: See Platform Notes.
- **coder-initialization-rejection**: See Platform Notes.
- **click-focus**: Component MUST take focus in response to a click, for
  any click location within its bounds (no sub-region hit-testing is
  performed).
- **focus-recording-start**: Component MUST set `isRecording` to `true`
  when it gains focus and the underlying focus-gain succeeds.
- **resign-recording-stop**: Component MUST set `isRecording` to `false`
  when it loses focus and the underlying focus-loss succeeds.
- **redundant-recording-notification-suppression**: Component MUST NOT act
  on (re-render text, re-theme, or invoke `onRecordingChanged`) a write to
  `isRecording` that sets it to its current value.
- **recording-change-reporting**: Component MUST invoke `onRecordingChanged`
  with the new value exactly when `isRecording` actually changes.
- **manual-recording-stop**: Component MUST expose an operation that
  manually stops recording.
- **idle-end-recording-noop**: The manual recording-stop operation MUST be
  a no-op when `isRecording` is already `false`.
- **end-recording-resignation**: When the manual recording-stop operation
  runs while `isRecording` is `true` and this component currently holds
  focus, Component MUST clear the window's focus.
- **end-recording-force-stop**: When the manual recording-stop operation
  runs while `isRecording` is `true`, Component MUST set `isRecording` to
  `false` directly afterward, regardless of whether this component held
  focus and regardless of whether the focus-clearing above succeeded —
  this stops recording without depending on the focus-change notification
  path, which is what lets the hosting row end recording from code that
  itself committed or abandoned the edit.
- **recording-key-equivalent-interception**: While `isRecording` is
  `true`, Component MUST evaluate every event delivered through the
  platform's pre-dispatch key-handling path through its own chord-capture
  logic instead of deferring to the default pre-dispatch handling.
- **idle-key-equivalent-deferral**: While `isRecording` is `false`,
  Component MUST defer every event delivered through the pre-dispatch
  key-handling path to the default pre-dispatch handling, unevaluated by
  its own capture logic.
- **incidental-modifier-stripping**: Before classifying a key event as
  Escape, Return/Enter, or Tab, Component MUST compute a modifier set that
  excludes incidental state — Caps Lock, the Fn key, and numeric-keypad
  status — so that an event carrying one of those incidental bits is not
  misclassified as "modified."
- **bare-escape-cancel**: While recording, Component MUST invoke
  `onCancel` and consume the event when the pressed key is Escape and the
  stripped modifier set is empty.
- **bare-return-commit**: While recording, Component MUST invoke
  `onCommit` and consume the event when the pressed key is Return or the
  keypad Enter key and the stripped modifier set is empty.
- **unmodified-tab-passthrough**: While recording, Component MUST NOT
  capture Tab pressed with an empty stripped modifier set or with only
  Shift; it MUST decline to capture the event (not consuming it) so normal
  focus traversal continues.
- **modified-tab-capture**: While recording, Component MUST treat Tab
  combined with any modifier other than (or in addition to) Shift alone —
  for example Option-Tab or Control-Tab — as an ordinary capturable chord,
  not as a focus-navigation key.
- **captured-chord-reporting**: While recording, for any key event that is
  not the bare-Escape, bare-Return, or passthrough-Tab case, Component
  MUST attempt to construct a shortcut value from the raw event and, when
  construction succeeds, MUST invoke `onCapture` with that shortcut and
  consume the event. This MUST happen for every distinct chord captured
  while recording, not only the first.
- **unconstructible-chord-ignore**: While recording, when constructing a
  shortcut value from a key event that is not the bare-Escape, bare-Return,
  or passthrough-Tab case fails, Component MUST NOT invoke `onCapture`,
  `onCancel`, or `onCommit`, and MUST NOT consume the event (its capture
  logic declines to capture it).
- **uncaptured-key-down-passthrough**: Component MUST defer to the default
  key-handling behavior whenever `isRecording` is `false`, or whenever
  `isRecording` is `true` but its capture logic declines to capture that
  event.
- **recording-placeholder-display**: Component MUST display the literal text
  "Press keys…" in place of a shortcut description whenever it is recording
  and neither `pendingShortcut` nor `displayedShortcut` is set.
- **pending-shortcut-priority**: Whenever `pendingShortcut` is
  non-nil, Component MUST render `pendingShortcut`'s `description` instead of
  `displayedShortcut`'s, regardless of recording state. This MUST take effect
  immediately when either property is set.
- **prior-text-retention**: When recording starts while
  `displayedShortcut` is already non-nil and `pendingShortcut` is still nil,
  Component MUST continue displaying `displayedShortcut`'s description (MUST
  NOT switch to "Press keys…") until the caller sets `pendingShortcut` in
  response to a chord the component reported through `onCapture`.
- **idle-placeholder-display**: Component MUST display its
  `placeholder` string (default the literal "Click to record") when not
  recording and neither `pendingShortcut` nor `displayedShortcut` is set.
- **pointing-hand-cursor**: Component MUST register the pointing-hand
  cursor over its full bounds.
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

- **Corner radius**: 5pt.
- **Padding**: The label is pinned 6pt in from the view's leading and
  trailing edges and centered vertically; there is no separate top/bottom
  padding constant — vertical position is centering within the fixed 22pt
  height, not an inset.
- **Font**: `palette.font(.button)`, which defaults to a 13pt, medium
  weight, proportional system font; the size scales with the active
  theme's `sizeScale` and the label repaints on every theme change (see
  theme-change-repaint).
- **Background**: Set to `palette.controlBackgroundColor` (the theme's
  `controlBackground` role, resolved to a fixed color per the active
  theme — not a system-dynamic color).
- **Foreground/Text**: See shortcut-presence-text-color — `primaryTextColor`
  when a shortcut is shown, `placeholderTextColor` otherwise.
- **Border**: 1pt width (a fixed constant, not theme-scaled); color per
  recording-state-border-color.
- **Shadow**: Not applicable — no shadow property is set or drawn anywhere
  in this component's own source.
- **Min/Max size**: Height is fixed at exactly 22pt. Width has a minimum of
  132pt and no explicit maximum; how wide the view actually grows is left
  to whatever layout hosts it (a Key Command Row View).

## States

| State | Appearance change |
|-------|------------------|
| Default (idle, no shortcut) | Border color = `borderColor`; label shows `placeholder` ("Click to record" by default) in `placeholderTextColor`. |
| Idle with a shortcut | Border color = `borderColor`; label shows `displayedShortcut.description` in `primaryTextColor`. |
| Recording, nothing shown yet | Border color = `accentColor`; label shows "Press keys…" in `placeholderTextColor` (see recording-placeholder-display). |
| Recording, prior shortcut still showing | Border color = `accentColor`; label continues showing `displayedShortcut.description` in `primaryTextColor` until the first chord is captured (see prior-text-retention) — the border color is the only visual difference from the idle-with-a-shortcut state at this instant. |
| Recording, chord captured (pending) | Border color = `accentColor`; label shows `pendingShortcut.description` in `primaryTextColor`. |
| Pressed | Not applicable: the component draws no separate pressed visual; a click only reassigns focus, and any resulting border-color change is the Recording transition above, not a press state. |
| Disabled | Not implemented in source: no enabled/disabled property is ever read, set, or checked anywhere in this component's own source. |
| Focused | Not styled as a distinct state: gaining focus and entering the Recording state are the same event (the focus-gain hook sets `isRecording = true`); the accent-colored border **is** this component's only focus indicator. |
| Loading | Not applicable — the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not implemented in source. No accessibility role, label,
  or title-element link — unlike the Key Command Row View
  (`agentictoolkit://cookbook/ui/settings/rows/key-command-row-view`),
  whose sibling toggle control links to its label — appears anywhere in
  this component's own source; the view relies entirely on the platform's
  default accessibility exposure. The view is an interactive,
  focus-accepting control whose whole purpose is recording user input, and
  this file assigns it no accessibility role or label of its own; any such
  assignment is left entirely to the caller.
- **Label requirements**: Not implemented in source. This file
  sets no accessibility label of its own; a caller may assign one externally
  (accessibility identifiers, not labels, are assigned by the hosting row
  outside this file), but nothing in this component's own source guarantees
  a screen reader announces this control's purpose. This is the same gap
  as the Role/trait item above.
- **Announce state changes**: Not implemented in source. No accessibility
  change notification (or equivalent) accompanies the `isRecording`
  transition or a captured/committed/cancelled chord anywhere in source,
  so a screen reader user is not told the control entered or left
  recording mode.
- **Minimum tap target**: Not applicable to a touch-target threshold — this
  is a pointer/keyboard-driven control with no touch input path in source.
  Its actual click target is fixed at 22pt tall by a minimum of 132pt wide
  (see Min/Max size), matching this file's own layout constants, not a
  touch guideline.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Every color this component draws (`controlBackgroundColor`, `accentColor`/`borderColor`, `primaryTextColor`/`placeholderTextColor`) is resolved at runtime from whichever `SemanticPalette` the active theme supplies, and this component's own source performs no contrast check of its own, so whether text-on-background or border-on-background contrast meets a specific ratio (e.g. WCAG 4.5:1) cannot be determined from this source file alone — it would require auditing the contrast ratio of each theme's actual token values.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| kccf-003 | click-focus | Click anywhere within an on-screen, unfocused field's bounds | The field becomes the window's focused control |
| kccf-004 | focus-recording-start | Give focus to an unfocused field, in a window that accepts it | `isRecording == true` after the call; `onRecordingChanged` fires with `true` |
| kccf-005 | resign-recording-stop | Remove focus from a recording field, with the window accepting the change | `isRecording == false` after the call; `onRecordingChanged` fires with `false` |
| kccf-006 | redundant-recording-notification-suppression | With `isRecording == true`, trigger another focus-gain success (the field is already focused) | `onRecordingChanged` is not invoked a second time; no additional text/theme refresh is observed |
| kccf-007 | recording-change-reporting | Toggle focus onto then off of the field | `onRecordingChanged` fires exactly twice: once with `true`, once with `false` |
| kccf-008 | idle-end-recording-noop | Call the manual recording-stop operation on a field where `isRecording == false` | No change to focus, `isRecording`, or `onRecordingChanged` invocation |
| kccf-009 | end-recording-resignation | Field is recording and currently holds focus; call the manual recording-stop operation | The window's focus is cleared |
| kccf-010 | end-recording-force-stop | Field is recording but is not currently focused (e.g. focus already moved); call the manual recording-stop operation | `isRecording == false` after the call, and the window's focus is not touched (the focus-check guard is skipped) |
| kccf-011 | recording-key-equivalent-interception | Field is recording; send an event for the primary modifier plus K | The field's own capture logic evaluates the event (it is not deferred to the default pre-dispatch handling); `onCapture` fires with the corresponding shortcut |
| kccf-012 | idle-key-equivalent-deferral | Field is not recording; send an event for the primary modifier plus K | The default pre-dispatch handling's return value is what the capture logic returns; `onCapture` does not fire |
| kccf-013 | incidental-modifier-stripping | Field is recording; send an Escape key event with Caps Lock active (physically on) but no other modifier held | `onCancel` fires (the event is still classified as "unmodified Escape" after stripping the incidental Caps Lock state) |
| kccf-014 | incidental-modifier-stripping | Field is recording; send a Return key event with Caps Lock active (physically on) but no other modifier held | `onCommit` fires (the event is still classified as "unmodified Return" after stripping the incidental Caps Lock state) |
| kccf-015 | bare-escape-cancel | Field is recording; send Escape with no modifiers | `onCancel` fires; the event is consumed (capture logic returns `true`) |
| kccf-016 | bare-return-commit | Field is recording; send Return with no modifiers | `onCommit` fires; the event is consumed |
| kccf-017 | bare-return-commit | Field is recording; send the keypad Enter key with no modifiers | `onCommit` fires; the event is consumed |
| kccf-018 | unmodified-tab-passthrough | Field is recording; send Tab with no modifiers | Capture logic declines to capture; `onCapture`/`onCancel`/`onCommit` do not fire; focus is free to advance |
| kccf-019 | unmodified-tab-passthrough | Field is recording; send Shift-Tab | Capture logic declines to capture; the event is not consumed |
| kccf-020 | modified-tab-capture | Field is recording; send Option-Tab | A shortcut value is constructed and `onCapture` fires with it; the event is consumed |
| kccf-021 | captured-chord-reporting | Field is recording; send the primary modifier plus Shift plus K, then Option plus the primary modifier plus P | `onCapture` fires twice, once per chord, each with the corresponding shortcut value |
| kccf-022 | unconstructible-chord-ignore | Field is recording; send a bare modifier-key-down event (e.g. the primary modifier pressed alone, with no other key) for which constructing a shortcut value fails | `onCapture`/`onCancel`/`onCommit` do not fire; the event is not consumed |
| kccf-023 | uncaptured-key-down-passthrough | Field is not recording; send a key press for any key | The default key-handling behavior is invoked |
| kccf-024 | recording-placeholder-display | Field has no `pendingShortcut` and no `displayedShortcut`; give it focus | Label text becomes "Press keys…" |
| kccf-025 | pending-shortcut-priority | `displayedShortcut` is set to shortcut A; set `pendingShortcut` to shortcut B | Label text immediately shows B's `description`, not A's |
| kccf-026 | prior-text-retention | `displayedShortcut` is set to shortcut A, `pendingShortcut` is nil; give the field focus | Label text remains A's `description` (does NOT change to "Press keys…") until a chord is captured |
| kccf-027 | idle-placeholder-display | `pendingShortcut` and `displayedShortcut` are both nil, `isRecording == false`, default `placeholder` | Label text reads "Click to record" |
| kccf-028 | pointing-hand-cursor | Query cursor rects for the field's bounds | A pointing-hand cursor rect covers the full bounds |
| kccf-029 | theme-change-repaint | Field is on screen with theme T1; switch the active theme to T2 | Background/border color and label font/text color are re-read from T2's `SemanticPalette` without further user action |
| kccf-030 | recording-state-border-color | Compare a non-recording field to the same field once it starts recording | Border color changes from `borderColor` to `accentColor` |
| kccf-031 | shortcut-presence-text-color | Compare a field with `displayedShortcut` set to one with none | Text color is `primaryTextColor` when a shortcut is shown, `placeholderTextColor` when none is |

`main-actor-confinement` and `coder-initialization-rejection` have no test
vectors: see Platform Notes for how each is
verified.

## Edge Cases

- Null/empty input: `placeholder` is a non-optional string; an empty string
  assigned to it produces an empty label with no crash, and the component
  needs no additional nil-handling because none of its stored properties
  (`displayedShortcut`, `pendingShortcut` may be unset; `placeholder` is
  always set) admit an unhandled null case.
- Boundary values: Not applicable in the numeric-range sense — the two
  layout constants (22pt fixed height, 132pt minimum width) are fixed
  architectural constants, not user-adjustable inputs with a min/max to
  probe, and every key-code comparison in the component's capture logic is
  an exact equality check, not a range comparison that could be
  off-by-one.
- Concurrent access: Not applicable — this component is confined to a
  single thread of execution for its entire lifetime, so all construction,
  focus changes, and key handling are serialized to that thread. See Platform Notes for how that confinement is enforced.
- Error states: Not applicable in the thrown-error sense — no
  error-throwing call appears anywhere in this component's own source. The
  one call that can fail, constructing a shortcut value from an event, is
  a call that can return an absent result rather than throw, and its
  failure case is handled by unconstructible-chord-ignore rather than
  propagated or crashed on.
- Offline/disconnected: Not applicable — the component performs no
  networking of any kind.
- Uncaptured key falls to default key-handling behavior: when the
  component defers to the default key-handling behavior (idle, or
  recording with an unconstructible chord), the platform's own default
  handling applies, which for a plain, otherwise-unhandled view typically
  produces the system alert sound. This is standard, unmodified platform
  behavior triggered by this file's own fallback, not a custom sound the
  component plays.
- Re-clicking while already recording: a click unconditionally claims
  focus even if the field is already focused;
  redundant-recording-notification-suppression means this has no effect on
  `isRecording` or `onRecordingChanged`.
- The manual recording-stop operation called when the window has since
  been deallocated or has no focused control at all: the focus-check
  guard evaluates false, so the focus-clearing branch is skipped and only
  the unconditional `isRecording = false` runs (see
  end-recording-force-stop).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `onCapture` | Callback | none | Called for every chord captured while recording, with the captured shortcut value. |
| `onCancel` | Callback | none | Called when the user presses bare Escape while recording. |
| `onCommit` | Callback | none | Called when the user presses bare Return or keypad Enter while recording. |
| `onRecordingChanged` | Callback | none | Called when recording starts (click/focus) or stops (loses focus/the manual recording-stop operation). |
| `displayedShortcut` | Shortcut (optional) | none | The shortcut the bound command is already assigned to; shown when nothing is pending. |
| `pendingShortcut` | Shortcut (optional) | none | The chord captured but not yet saved; takes precedence over `displayedShortcut` when set. The component only reads this property to decide what to display — it never assigns or clears it itself. The caller sets it (typically from `onCapture`) and clears it once the edit is committed or abandoned. |
| `placeholder` | String | the literal `"Click to record"` | Shown when there is nothing pending, displayed, or being recorded. |

## Deep Linking

Not applicable: this component is a focus target embedded in a settings
row, not a navigable screen or destination; no URL scheme, route, or
deep-link handler appears anywhere in its own source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (unassigned) | `Click to record` | Default value of the `placeholder` property, shown when nothing is captured, displayed, or being recorded. |
| (unassigned) | `Press keys…` | Shown while recording with nothing pending or displayed. |

Both strings above are literal values set directly, which does not localize
on its own; this component's own source contains no localization-catalog
lookup or other localization mechanism for either literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, movement, or scaling; every appearance change is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this component directly: this component's own source reads no system contrast setting, and neither does the `SemanticPalette` color-resolution path it calls into; whether the resulting colors are contrasty enough is tracked once, under the open question on minimum-contrast-ratio in Accessibility above, not duplicated here. |
| Differentiate Without Color | During the "prior shortcut still showing" transition, the border color changing from `borderColor` to `accentColor` is the only indicator that recording has begun; no icon, text, or shape change accompanies it until a chord is captured, unlike every other state, where the text itself changes. The component does not respond to Differentiate Without Color. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component's own source; the field always behaves identically once
constructed.

## Analytics

Not applicable: this component's own source contains no analytics or
telemetry call. `onCapture`/`onCommit`/`onCancel`/`onRecordingChanged` are
behavioral callbacks for the hosting row, not telemetry events.

## Privacy

- **Data collected**: Not applicable — the component captures a keyboard
  chord configuration (a key plus modifiers), not personal data, and only
  for as long as it is held in `pendingShortcut`/`displayedShortcut`.
- **Storage**: Not applicable — this component's own source performs no
  read or write to disk or any other persistent store; the source's own
  doc comment is explicit that this component "records and reports; it
  never saves." Persistence, if any, is owned by whatever the hosting row
  commits the chord to, which is outside this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: `pendingShortcut` and `displayedShortcut` are retained only
  in memory for the view's own lifetime. Neither is cleared by the manual
  recording-stop operation or anywhere else in this file — that operation
  only stops recording (see end-recording-force-stop); assigning and
  clearing both properties is entirely the caller's responsibility. Either
  property is overwritten whenever the caller sets a new value, or
  released when the view is deallocated; this file writes nothing to
  persistent storage.

## Logging

Not applicable: this component's own source contains no logging call.

## Platform Notes

- **SwiftUI**: There is no built-in SwiftUI equivalent for raw key-equivalent
  interception. Wrap this exact AppKit type in an `NSViewRepresentable`
  rather than reimplementing it, because `onKeyPress`/`.focusable()`
  (macOS 14+) observe key events but do not intercept primary-modifier
  chords ahead of the menu/window the way `performKeyEquivalent` does —
  the same problem a standard text field's field editor has. Expose
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
  gaining/losing focus.
- **React/Web**: A `<div>` (or a read-only `<input>`, to get a native focus
  ring for free) with `tabIndex={0}` and an `onKeyDown` handler reading
  `event.key`/`event.code` plus the modifier booleans. Call
  `event.preventDefault()` for every combination the field decides to
  capture, since a Ctrl/Cmd-chord can otherwise trigger the browser's or
  OS's own shortcuts — the DOM analog of intercepting a key equivalent
  before the menu claims it — but deliberately skip `preventDefault()` for
  a bare Tab/Shift-Tab so native focus order is preserved, mirroring
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
  `AgenticToolkitCore`'s theming (`observeTheme`, `SemanticPalette`). The
  primary modifier on this platform is Command: the "primary modifier plus
  K"/"primary modifier plus Shift plus K"/"Option plus primary modifier
  plus P" test-vector inputs above correspond to ⌘K, ⌘⇧K, and ⌥⌘P
  respectively. `main-actor-confinement` is enforced by the class and its
  public API being declared `@MainActor`, so construction or mutation from
  off the main actor fails to compile — a static, compile-time check
  rather than a vector observed by running the program; a port on a
  platform without an equivalent compile-time enforcement should verify
  this as a build-verification note rather than a runtime test.
  `coder-initialization-rejection` is implemented as a fatal error on
  `init?(coder:)`, since this component provides no Interface
  Builder/`NSCoding` support. There is no UIKit code path in source and
  none is implied — iOS has no key-equivalent chain or hardware-shortcut
  recording concept comparable to this component's purpose. click-focus is
  implemented as a direct `window?.makeFirstResponder(self)` call from
  `mouseDown(with:)`; the pre-dispatch interception/deferral requirements
  are implemented by overriding `performKeyEquivalent(with:)` (deferring to
  `super.performKeyEquivalent(with:)` when idle), and the regular
  key-handling deferral is implemented by overriding `keyDown(with:)` to
  call `super.keyDown(with: event)`; `incidental-modifier-stripping`
  computes the modifier set from `event.modifierFlags` restricted to
  `.deviceIndependentFlagsMask` with `.function`, `.numericPad`, and
  `.capsLock` removed; `pointing-hand-cursor` is registered via
  `resetCursorRects()`; redundant-recording-notification-suppression is
  implemented as an early return in the `isRecording` property's `didSet`
  observer when the new value equals the old; theme-change-repaint is
  driven by `observeTheme`, whose initializer applies the current palette
  synchronously before the initializer's own first `refreshText()` call
  runs; `pending-shortcut-priority` and the placeholder-display
  requirements are implemented as `didSet` observers on `pendingShortcut`
  and `displayedShortcut` that both call the same `refreshText()` routine.
  The corner radius is `layer?.cornerRadius = 5`; the border width is
  `layer?.borderWidth = 1`; the label's leading/trailing insets are Auto
  Layout constraints of `constant: 6`/`constant: -6`, centered vertically
  via `centerYAnchor`; the fixed height and minimum width are
  `heightAnchor.constraint(equalToConstant: 22)` and
  `widthAnchor.constraint(greaterThanOrEqualToConstant: 132)`. The font is
  `palette.font(.button)`, which resolves via
  `theme.typography.style(.button).nsFont(scaledSize:)` to `FontStyle(size:
  13, weight: .medium)` in `ThemeTypography.swift`. No
  `setAccessibilityRole`, `setAccessibilityLabel`, or
  `setAccessibilityTitleUIElement` call, and no
  `NSAccessibility.post(element:notification:)` call, appears anywhere in
  source. The default key-handling fallback (when neither an override
  claims the event) is AppKit's own `NSResponder.keyDown` default, which
  for a plain `NSView` with no further responder-chain handler typically
  produces the system alert beep. The manual recording-stop operation's
  focus-check guard is `window?.firstResponder === self`, evaluated through
  optional chaining so a deallocated window or absent first responder
  evaluates `false` without crashing. Both localized-string literals are
  assigned directly to an AppKit `stringValue`, which — unlike a string
  literal passed to a SwiftUI `Text`/`Label` (a `LocalizedStringKey`) —
  does not localize on its own; source contains no `NSLocalizedString` or
  string-catalog key reference for either. Every appearance change
  (`refreshText()`, `applyTheme()`) is an instantaneous property
  assignment with no `CATransaction`/animator-proxy call. Neither this
  component's own source nor the `SemanticPalette` color-resolution path
  it calls into reads `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`.
  Persistence, were the hosting row to add any, would typically go through
  `UserDefaults` or an equivalent store — this component itself performs
  none.
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
  `LostFocus` (the WinUI analog of gaining/losing focus)
  with `IsTabStop="True"`, and leave `e.Handled =
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

**Decision**: Draw a bespoke view and read raw key events directly, instead
of using a standard text field.
**Rationale**: A field editor would eat the very chords being recorded, and
a standard text field's own key handling turns a primary-modifier chord
into an edit command. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Override the pre-dispatch key-handling hook
(`performKeyEquivalent(with:)`) in addition to the regular key-handling
hook (`keyDown(with:)`).
**Rationale**: A primary-modifier chord never reaches the regular
key-handling hook because the platform offers it down the key-equivalent
chain first (a menu item, the window), which would otherwise claim it;
this override is what makes the recorder work for primary-modifier
combinations at all. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Let bare Tab and Shift-Tab pass through uncaptured while
Option-Tab/Control-Tab remain capturable.
**Rationale**: A recorder that swallowed either bare form would trap
anyone who arrived at the field by tabbing through the panel, while a
modifier-carrying Tab combination is still a legitimate chord to record.
(Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: The manual recording-stop operation forces `isRecording` to
`false` unconditionally, not only through the focus-loss path losing focus
takes.
**Rationale**: This is what the hosting row calls once an edit is
committed or abandoned, to stop recording without depending on the
focus-change notification path — necessary because the row, not the
field, owns commit, and may need to end recording from code that does not
itself trigger a focus change. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: While recording, do not switch the label to "Press keys…" if
a shortcut is already being displayed or pending; only fall back to
"Press keys…" when neither is set.
**Rationale**: The text-refresh routine resolves text from a single
precedence chain (`pendingShortcut ?? displayedShortcut`, else "Press
keys…" or `placeholder`) with no separate "just started recording" branch.
This is called out because a reader could otherwise assume "Press keys…"
always appears the instant recording starts. (Applies to the AppKit
implementation.)
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/controls/. |
