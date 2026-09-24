---
id: 1d2f69b6-1156-4dfa-a390-a240925ba1bd
title: KeyCommandRowView
domain: agentictoolkit://recipes/key-command-row-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row for one key command — a capture field, a pending
  confirm/cancel pair, and an enable switch, backed by KeyCommandRegistry.
platforms:
- swift
- macos
tags:
- settings
- macos
- appkit
- keyboard-shortcuts
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# KeyCommandRowView

## Overview

`KeyCommandRowView`
(`packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandRowView.swift`)
is the settings row for one bindable command in the Key Commands panel:
`[title] … [click-to-record field] [confirm | cancel] [on/off]`, with a status
readout appearing underneath while an edit is pending or a refusal is being
shown. It composes four child controls — a `ThemedLabel` title, a
`KeyCommandCaptureField` that records a chord, a `ConfirmCancelControl`
confirm/cancel pair, and an `NSSwitch` — around a single `KeyCommandDescriptor`
and the shared `KeyCommandRegistry` that owns every command's binding and
answers whether a chord is free.

The row, not the capture field, owns the pending-edit state. Per the source's
own doc comment, a captured chord is pending until the user commits it, and
focus can leave the field in the middle of that (the user clicks the
confirm/cancel pair, which is a separate view), so the state that decides
whether the confirm/cancel pair and the status readout are on screen cannot
live in the view that loses focus — it lives in the row.

## Behavioral Requirements

- **appends-colon-to-title**: Component MUST set the title label's text to
  `"<command.title>:"` — `command.title` with a trailing colon appended.
- **arranges-main-row**: Component MUST arrange the title label, the capture
  field, the confirm/cancel pair, and the toggle left-to-right in a single
  horizontal row built via `NSView.makeRow`.
- **stacks-main-and-readout-rows**: Component MUST stack the main row above
  the readout row in a vertical `NSStackView` with 4pt spacing, and MUST pin
  that stack to the component's own edges.
- **hides-confirm-cancel-when-not-editing**: Component MUST hide the
  confirm/cancel pair whenever it is not mid-edit, and MUST show it whenever
  it becomes mid-edit.
- **hides-readout-row-when-idle**: Component MUST hide the readout row
  whenever it is neither mid-edit nor showing a refusal message, and MUST
  show the readout row otherwise.
- **links-toggle-accessibility-title**: Component MUST set the toggle's
  accessibility title UI element to the title label.
- **sets-capture-field-accessibility-identifier**: Component MUST set the
  capture field's accessibility identifier to
  `"settings.key-commands.<command.id>.recorder"`.
- **sets-toggle-accessibility-identifier**: Component MUST set the toggle's
  accessibility identifier to `"settings.key-commands.<command.id>.enabled"`.
- **begins-editing-on-capture**: Component MUST record a captured chord as
  the pending shortcut, mirror it onto the capture field's own pending
  shortcut, enter the mid-edit state, and refresh availability whenever the
  capture field reports a captured chord.
- **begins-editing-on-recording-start**: Component MUST enter the mid-edit
  state and refresh availability whenever the capture field starts
  recording.
- **forwards-recording-state-to-registry**: Component MUST set the
  registry's recording flag to the capture field's current recording state
  whenever that state changes.
- **ends-editing-when-recording-stops-with-nothing-pending**: Component MUST
  leave the mid-edit state when the capture field stops recording while no
  chord is pending.
- **keeps-editing-open-when-recording-stops-with-a-pending-chord**:
  Component MUST remain in the mid-edit state when the capture field stops
  recording while a chord is still pending (for example, because focus left
  the field when the user clicked the confirm/cancel pair).
- **refuses-commit-without-a-pending-chord**: Component MUST NOT write a
  binding or end the edit when a commit is attempted with no pending chord
  set.
- **refuses-commit-of-an-unavailable-chord**: Component MUST refresh
  availability and leave the edit open, without writing a binding or ending
  the edit, when the pending chord is no longer available at commit time.
- **enables-command-on-first-or-unbound-commit**: Component MUST set the
  committed binding's enabled flag to `true` when the command has never had
  an authored binding, or its current binding has no shortcut.
- **preserves-enabled-state-on-rebind**: Component MUST preserve the
  command's current enabled flag in the committed binding when the command
  already has an authored binding whose shortcut is non-nil.
- **commits-pending-chord-to-registry**: Component MUST write the pending
  chord and the computed enabled flag to the registry, keyed by the
  command's id, when a commit succeeds.
- **clears-edit-state-after-commit-or-cancel**: Component MUST clear the
  pending shortcut on both itself and the capture field, stop the capture
  field's recording, and leave the mid-edit state after a successful commit
  and after a cancel.
- **refreshes-after-commit-or-cancel**: Component MUST re-read the current
  binding and update its subviews immediately after a successful commit and
  after a cancel.
- **cancels-without-writing-a-binding**: Component MUST NOT write a binding
  to the registry when a cancel is performed.
- **refuses-toggle-on-when-the-current-chord-is-taken**: Component MUST,
  when the toggle is switched on while the command's current shortcut is
  unavailable, reset the toggle to off, set a refusal message of the form
  `"can't switch on — <reason>"`, and refresh availability, without writing
  a binding.
- **clears-refusal-on-an-accepted-toggle-change**: Component MUST clear any
  pending refusal message whenever a toggle change is accepted.
- **commits-accepted-toggle-state**: Component MUST write the command's
  existing shortcut together with the toggle's new enabled state to the
  registry, then refresh its subviews, whenever a toggle change is
  accepted.
- **refreshes-on-external-bindings-change**: Component MUST re-read the
  current binding and update its subviews whenever the registry posts its
  bindings-changed notification.
- **reflects-bound-shortcut-on-refresh**: Component MUST set the capture
  field's displayed shortcut to the command's current binding shortcut
  whenever it refreshes.
- **shows-placeholder-when-unbound**: Component MUST set the capture
  field's placeholder to `"Click to record"` when the current binding has
  no shortcut, and to an empty string otherwise.
- **reflects-enabled-state-on-refresh**: Component MUST set the toggle's
  state to on when the current binding's enabled flag is `true` and to off
  otherwise, whenever it refreshes.
- **disables-toggle-without-a-bound-shortcut**: Component MUST set the
  toggle's enabled flag to `false` when the current binding has no
  shortcut, and to `true` otherwise.
- **shows-refusal-in-status-label**: Component MUST show the refusal
  message, styled with the danger role, in the status label whenever a
  refusal is pending and the component is not currently mid-edit.
- **shows-unavailable-reason-while-pending**: Component MUST append
  `" — <reason>"` to the availability label in the status label whenever a
  pending chord is unavailable.
- **prompts-for-a-chord-while-pending-is-empty**: Component MUST show
  `"press a key combination"` in the status label whenever no chord is
  pending and no refusal is masking it.
- **shows-availability-label-for-an-available-pending-chord**: Component
  MUST show the plain availability label (`"available"`) in the status
  label when a pending chord is available.
- **colors-status-label-by-availability**: Component MUST style the status
  label with the secondary-text role when no chord is pending, the success
  role when a pending chord is available, and the danger role when a
  pending chord is unavailable.
- **gates-confirm-by-availability**: Component MUST set the confirm/cancel
  pair's confirm-enabled flag to the pending chord's availability whenever
  availability is refreshed.
- **requires-a-command-and-a-registry-to-construct**: Component MUST
  require both a `KeyCommandDescriptor` and a `KeyCommandRegistry` at
  construction; no initializer produces a usable row without both.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init?(coder:)`; that initializer MUST trigger a fatal error.
- **removes-its-notification-observer-on-deinit**: Component MUST remove
  its bindings-changed observer when deinitialized.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor.

## Appearance

- **Corner radius**: Not applicable to `KeyCommandRowView` itself — the row
  sets no `wantsLayer`/`cornerRadius` of its own; it only arranges four
  subviews in stack views. The capture field and the confirm/cancel pair
  each draw their own 5pt-corner-radius chrome, but that is those
  components' own appearance, not this file's.
- **Padding**: The main row's `NSStackView` (built by `NSView.makeRow`) uses
  `SettingsLayout.default[.rowSpacing]` = 8pt between the title label and
  the flexible spacer `makeRow` inserts after it, with the spacer-to-field
  gap zeroed (`setCustomSpacing(0, after: spacer)`), so the spacer's own
  width is the only room between the label and the capture field; the
  capture field, confirm/cancel pair, and toggle then sit with the same 8pt
  `rowSpacing` between each of them. The readout row is built the same way,
  from a blank value label and the status label, so its own leading gap is
  likewise the spacer's width. The outer vertical stack (main row over
  readout row) uses a spacing of 4pt, set directly in
  `KeyCommandRowView.swift`. `pinToEdges` pins that outer stack to the
  component's top/leading/trailing/bottom with no additional constant, so
  the component contributes 0pt of outer padding beyond its internal 8pt /
  4pt spacing.
- **Font**: The title label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to 13pt, medium weight. The status label and the blank
  spacer label (`ComposableSettings.makeValueLabel`, `textRole: .caption`)
  resolve to 11pt, regular weight. Neither the capture field's internal
  label nor the confirm/cancel pair's buttons are styled by this file; they
  are those components' own appearance.
- **Background**: None (transparent) on `KeyCommandRowView` itself — no
  `wantsLayer` or background color is set anywhere in
  `KeyCommandRowView.swift`. The capture field and confirm/cancel pair each
  paint their own themed background layer, but that is their own chrome.
- **Foreground/Text**: The title label uses the primary-text role. The
  status label's role switches between secondary-text, success, and danger
  depending on pending-chord availability (see States and
  **colors-status-label-by-availability**); the blank spacer label in the
  readout row keeps its default secondary-text role, unused for display.
- **Border**: Not applicable to `KeyCommandRowView` itself — no border is
  drawn or configured anywhere in `KeyCommandRowView.swift`. The capture
  field draws its own 1pt border (accent-colored while recording, otherwise
  the theme's border color) and the confirm/cancel pair draws its own 1pt
  border; both are those components' own appearance.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `KeyCommandRowView.swift`.
- **Min/Max size**: `KeyCommandRowView` sets no explicit min/max width or
  height constraint of its own; its size is the sum of its subviews'
  intrinsic sizes plus the row/stack spacing described under Padding. Of
  its children, the capture field fixes its own height to 22pt and its own
  minimum width to 132pt, and the confirm/cancel pair fixes its own height
  to 20pt with two 24pt-wide buttons — both are those components' own
  constraints, reflected here only because they set the row's effective
  minimum width and height.

## States

| State | Appearance change |
|-------|------------------|
| Default | The row shows the command's current binding at rest: the capture field displays the bound shortcut (or the "Click to record" placeholder when unbound), the toggle reflects the binding's enabled flag, the confirm/cancel pair is hidden, and the readout row is hidden. |
| Pressed | Not applicable to `KeyCommandRowView` itself: the row draws no pressable control of its own. The toggle's native press feedback, the capture field's click-to-focus, and the confirm/cancel pair's button-press feedback all belong to those subcomponents, not to this file. |
| Disabled | Implemented as **disables-toggle-without-a-bound-shortcut**: the toggle's enabled flag is set to `false` whenever the current binding has no shortcut, and `NSSwitch`'s native disabled dimming applies; `KeyCommandRowView` itself has no separate `isEnabled` of its own. |
| Focused | The capture field becoming first responder (recording) is surfaced at the row level: the row enters the mid-edit state, the confirm/cancel pair and readout row become visible, and the status label prompts `"press a key combination"` until a chord is captured (see **begins-editing-on-recording-start**). The capture field's own border color change while recording is that component's own appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own; every state transition in source is a synchronous property assignment. |

## Accessibility

- **Role/trait**: `KeyCommandRowView` sets no accessibility role on itself.
  The toggle keeps `NSSwitch`'s native switch role via
  **links-toggle-accessibility-title**. The capture field's own role belongs
  to its component; see `agentictoolkit://recipes/key-command-capture-field`,
  which records the open question.
- **Label requirements**: The toggle's accessible name comes from the title
  label via **links-toggle-accessibility-title**. NEEDS REVIEW: the capture
  field is given only an accessibility *identifier*
  (`"settings.key-commands.<id>.recorder"`, a UI-test hook) and no
  accessibility *label* or title-element link to the title label; whether a
  screen reader announces it meaningfully depends on AppKit's default
  exposure of its internal, unlabeled text field, which neither this file
  nor `KeyCommandCaptureField.swift` configures explicitly. Resolving this
  needs a decision on what the capture field should announce (e.g. "Move
  Selection Up, shortcut recorder") and where that string should live.
- **Announce state changes (e.g., loading, disabled)**: NEEDS REVIEW: a
  refusal or an availability change updates the status label's `stringValue`
  and `role` (color) synchronously, but no call in
  `KeyCommandRowView.swift` posts an accessibility announcement (for
  example, `NSAccessibility.post(element:notification:)`). A sighted user
  sees the refusal appear immediately next to the switch; whether a
  VoiceOver user is notified of it at all is undefined by source and would
  need confirmation from an accessibility audit of the built panel.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView` composition with no touch input path in source;
  the 44×44pt minimum is iOS/touch guidance. `KeyCommandRowView` sets no
  `controlSize` on the toggle, so it keeps `NSSwitch`'s regular system
  click-target metrics.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| key-command-row-view-001 | appends-colon-to-title | Construct with `command.title == "Move Selection Up"` | Title label's `stringValue == "Move Selection Up:"` |
| key-command-row-view-002 | arranges-main-row | Construct any row | Title label, capture field, confirm/cancel pair, and toggle are all subviews of one horizontal row, in that left-to-right order |
| key-command-row-view-003 | stacks-main-and-readout-rows | Construct any row | The main row and the readout row are the only two arranged views of a vertical `NSStackView` pinned to the component's own edges, with 4pt spacing between them |
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
| key-command-row-view-031 | shows-unavailable-reason-while-pending | Capture a chord already bound to another command | Status label's text is `"unavailable — taken by "<other command's title>""` |
| key-command-row-view-032 | prompts-for-a-chord-while-pending-is-empty | Enter the mid-edit state before any chord is captured | Status label's text is `"press a key combination"` |
| key-command-row-view-033 | shows-availability-label-for-an-available-pending-chord | Capture a free chord | Status label's text is `"available"` |
| key-command-row-view-034 | colors-status-label-by-availability | Capture a free chord, then capture one already taken | Status label's role is success for the free chord and danger for the taken chord |
| key-command-row-view-035 | gates-confirm-by-availability | Capture a chord already bound to another command | Confirm/cancel pair's confirm-enabled flag is `false` |
| key-command-row-view-036 | requires-a-command-and-a-registry-to-construct | Inspect `KeyCommandRowView`'s public initializers | Only `init(command:registry:)` is available; both parameters are non-optional |
| key-command-row-view-037 | rejects-coder-initialization | Attempt `KeyCommandRowView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| key-command-row-view-038 | removes-its-notification-observer-on-deinit | Construct a row, capture its notification observer, then release the row | The observer is removed from `NotificationCenter.default`; no further calls into the deallocated row occur when the notification is posted again |
| key-command-row-view-039 | confines-to-main-actor | Attempt to construct or mutate a `KeyCommandRowView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `command` (`KeyCommandDescriptor`) and `registry`
  (`KeyCommandRegistry`) are non-optional, typed constructor parameters;
  Swift's type system rules out `nil` for either. `command.title` as an
  empty string produces a title label reading `":"` with no crash. This is
  a MUST: the component provides, and needs, no nil-handling path for its
  two initializer parameters.
- Boundary values: Not this file's own boundary — `KeyCommandRowView`
  imposes no minimum-modifier or chord-shape check itself; it defers
  entirely to `registry.availability(of:for:)`, which is the component that
  requires at least one of ⌘/⌃/⌥ before a chord is considered available.
- Concurrent access: Not applicable — `KeyCommandRowView` and
  `KeyCommandRegistry` are both declared `@MainActor`, so all construction,
  mutation, and notification handling is serialized to the main actor by
  the compiler (see **confines-to-main-actor**).
- Error states: Not applicable in the throw/catch sense — no throwing API
  is called anywhere in `KeyCommandRowView.swift`. The one failure domain
  the component has — a chord that cannot be assigned — is modeled as data
  (`KeyCommandAvailability.unavailable(reason)`) and surfaced through the
  refusal/status-label requirements above (see
  **refuses-commit-of-an-unavailable-chord**,
  **refuses-toggle-on-when-the-current-chord-is-taken**), a MUST-level
  behavior rather than an omission.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to the in-process
  `KeyCommandRegistry`.
- Click in, then click out with nothing captured: if the user focuses the
  capture field and it resigns first responder before any chord is
  captured, `onRecordingChanged(false)` fires with `pendingShortcut == nil`,
  so the row leaves the mid-edit state and the confirm/cancel pair and
  readout row hide again — this is a MUST, per
  **ends-editing-when-recording-stops-with-nothing-pending**, and is called
  out in source's own comment: "Clicked in and straight back out without
  pressing anything: there is nothing to confirm, so the pair should not
  linger."
- Re-recording a shipped-off, never-touched command versus one the user
  explicitly turned off: both have `binding.isEnabled == false` at the
  moment of recording, but the committed result differs — a shipped-off
  command with no authored binding turns on (**enables-command-on-first-or-
  unbound-commit**), while a command the user themselves switched off stays
  off (**preserves-enabled-state-on-rebind**) — because the row
  distinguishes "never authored" from "authored and off" via
  `registry.hasAuthoredBinding(for:)`, not merely by reading the current
  enabled flag. This is a MUST-level, source-traceable distinction; see
  Design Decisions.
- A binding change caused by a different row while this row is mid-edit:
  `KeyCommandRegistry.bindingsDidChangeNotification` fires for every
  binding write, including ones made by sibling rows sharing the same
  registry. `refresh()` only reassigns the capture field's displayed
  shortcut/placeholder and the toggle's state/enabled flag from the current
  binding — it never touches `pendingShortcut` or the mid-edit state — so
  an edit already in progress on this row survives a binding change made
  elsewhere (MUST, traced to `refresh()`'s body).
- A refusal shown after a toggle refusal, with no active recording: the
  refusal path (`toggleChanged`) sets `refusal` without ever setting
  `isEditing`; `updateReadoutVisibility()` still reveals the readout row
  because it reacts to `refusal != nil` independently of `isEditing`. The
  refusal message is cleared only when the next edit begins (`isEditing`'s
  `didSet` clears `refusal` when it becomes `true`), so it otherwise
  persists on screen until the user starts recording again — traced
  directly to the class's own doc comment: "shown in the readout until the
  next edit."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `command` | `KeyCommandDescriptor` | — (required) | The one command this row edits: supplies the title, id, and default binding used throughout. |
| `registry` | `KeyCommandRegistry` | — (required) | The shared registry the row reads bindings from and writes committed bindings and toggle changes to; also the object the row observes for external binding changes. |

## Deep Linking

Not applicable: `KeyCommandRowView` is a row inside a settings panel, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `KeyCommandRowView.swift`.

## Localization

NEEDS REVIEW: none of the user-facing strings this file introduces route
through a localization mechanism (no `NSLocalizedString`, no String Catalog
key) — each is a Swift string literal or string interpolation written
directly in `KeyCommandRowView.swift`. `command.title` itself is a
caller-supplied value (populated by whatever feature declares the
`KeyCommandDescriptor`) and is out of this file's scope, matching how
sibling settings-row recipes treat a caller-supplied title. The table below
lists this file's own literals as they appear in source.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `key_command_row.title_format` | `"<title>:"` (trailing colon appended to `command.title`) | Title label text |
| `key_command_row.placeholder.click_to_record` | `Click to record` | Capture field placeholder when unbound |
| `key_command_row.status.press_a_key_combination` | `press a key combination` | Status label when a pending chord has not yet been captured |
| `key_command_row.status.refusal_prefix` | `can't switch on — ` | Prefix before the availability reason when a toggle-on attempt is refused |
| `key_command_row.status.reason_separator` | ` — ` | Separator concatenated between the availability label and its reason |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `KeyCommandRowView.swift` performs no animation, transition, or `NSAnimationContext` call anywhere — every visibility and state change (`isHidden`, `stringValue`, `role`, toggle `state`) is an instantaneous property assignment, not even an opacity fade. |
| Increase Contrast | Not implemented in source: this file sets no independent high-contrast styling of its own. The title and status labels' colors are `ThemeRole` tokens (`.primaryText`, `.secondaryText`, `.success`, `.danger`) resolved by the active `SemanticPalette`; whatever Increase Contrast adjustment that palette makes is inherited automatically and is that theming system's concern, not this file's. `NSSwitch`'s on/off rendering is AppKit's own, which tracks Increase Contrast natively. |
| Differentiate Without Color | Satisfied without a color-only signal: the status label's *text* changes with availability (`"available"`, `"unavailable — <reason>"`, `"press a key combination"`, or the refusal sentence) in addition to its color role, so availability is never communicated by color alone. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `KeyCommandRowView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `KeyCommandRowView.swift` contains no analytics or
telemetry call.

## Privacy

- **Data collected**: The row surfaces the one piece of user-authored data
  it edits — the chord and enabled flag for `command.id` — but does not
  collect anything beyond what the user types into the capture field or
  toggles on the switch.
- **Storage**: `KeyCommandRowView` performs no storage of its own; it
  delegates persistence entirely to `registry.setBinding(_:for:)`, which
  writes into `UserSettings.keyCommandBindings`
  (`UserSettings+KeyCommands.swift`) — a component not covered by this
  file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `KeyCommandRowView.swift`.
- **Retention**: Not applicable to this file — the row retains only its own
  subviews, its `command`, its `registry` reference, and its own transient
  edit state (`pendingShortcut`, `isEditing`, `refusal`) for its own
  lifetime; how long the committed binding itself is retained is the
  registry/`UserSettings` layer's concern, not this file's.

## Logging

Not applicable: `KeyCommandRowView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose a `VStack` of an `HStack` (title `Text`, a custom
  chord-recorder view, a confirm/cancel `HStack` shown conditionally, and a
  `Toggle("", isOn: $isEnabled).labelsHidden()`) over a conditionally
  visible status `Text`. Drive `isEditing`/`pendingShortcut`/`refusal` as
  `@State` on the row's own view rather than on the recorder subview, for
  the same reason the source keeps this state on the row: the recorder can
  lose focus mid-edit. Give the toggle
  `.accessibilityLabel(command.title)` as the SwiftUI analog of
  `setAccessibilityTitleUIElement`, and drive the recorder's own
  accessibility label and role explicitly rather than leaving them
  implicit — see the Accessibility gaps this recipe flags.
- **Compose**: Use a `Column` of a `Row` (title `Text`, a custom
  chord-recorder composable, a confirm/cancel `Row` shown conditionally,
  and a trailing `Switch(checked = isEnabled, onCheckedChange = { ... })`)
  over a conditionally visible status `Text`. Hold the pending-chord and
  refusal state in the row's own `remember`/view-model scope, not the
  recorder's, mirroring the row-owns-the-edit design decision. Give the
  `Switch` a `Modifier.semantics { contentDescription = command.title }`.
- **React/Web**: A flex column containing a flex row (`<label>` for the
  title, a `<button>`- or `<div role="textbox">`-based chord recorder that
  listens for `keydown` while focused, a conditionally rendered
  confirm/cancel button pair, and a styled checkbox/switch input with
  `aria-labelledby` pointing at the title) above a conditionally rendered
  status `<div>` with `aria-live="polite"` — an explicit stand-in for the
  announcement path this recipe flags as unresolved in the AppKit source.
  Keep `isEditing`/`pendingShortcut`/`refusal` in the row component's own
  state, not the recorder's.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandRowView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, composing
  a `ThemedLabel`, a `KeyCommandCaptureField`, a `ConfirmCancelControl`, and
  an `NSSwitch` into a two-row vertical `NSStackView` via
  `ComposableSettings`'s `makeRow`/`pinToEdges` helpers, and observing
  `KeyCommandRegistry.bindingsDidChangeNotification` to stay in sync with
  bindings committed elsewhere. There is no UIKit code path in source; a
  UIKit port would replace `NSSwitch` with `UISwitch`, replace the
  target/action wiring with `.addTarget(_:action:for: .valueChanged)`, and
  would need its own chord-recording input surface since `UIKit` has no
  `performKeyEquivalent`-based hardware-keyboard capture equivalent to
  `KeyCommandCaptureField`'s.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with columns `Auto,*,Auto,Auto,Auto`: a `TextBlock` for the title in
  column 0; a custom `KeyboardAccelerator`-capturing control (a `Border`
  wrapping a `TextBlock`, focusable via `IsTabStop="True"`, overriding
  `OnKeyDown`/`OnPreviewKeyDown` to capture the chord the same way
  `performKeyEquivalent`/`keyDown` do here) in column 1; a two-button
  confirm/cancel `StackPanel` (two `Button`s with `FontIcon` glyphs,
  `Visibility` bound to an `IsEditing` property) in column 2; and a
  `ToggleSwitch` (restyled with empty `OnContent`/`OffContent` to match
  `NSSwitch`'s minimal chrome) bound `IsOn="{x:Bind IsEnabled, Mode=TwoWay}"`
  in column 3. Add a `TextBlock` for the status readout in a second `Grid`
  row, its `Visibility` bound to `IsEditing OR HasRefusal`. Hold
  `IsEditing`, `PendingShortcut`, and `Refusal` as properties on the row's
  own code-behind or view model — not on the recorder control — mirroring
  the row-owns-the-edit decision below, since a WinUI `UserControl` can
  just as easily lose logical focus mid-edit as an AppKit view can lose
  first responder. Set `AutomationProperties.LabeledBy` on the `ToggleSwitch`
  to the `TextBlock`, the WinUI analog of `setAccessibilityTitleUIElement`,
  and set `AutomationProperties.Name` explicitly on the chord-recorder
  `Border` — WinUI's analog of the accessibility label this recipe flags as
  missing on the AppKit capture field. Raise a
  `Windows.UI.Xaml.Automation.Peers.AutomationPeer` `NotifyLiveRegionChanged`
  (or bind the status `TextBlock` to a `LiveSetting="Polite"`
  `AutomationProperties`) when the refusal or availability text changes —
  the WinUI analog of the announcement gap this recipe flags in the AppKit
  source.

## Design Decisions

- Decision: The row, not `KeyCommandCaptureField`, owns the pending-edit
  state (`isEditing`, `pendingShortcut`) and the confirm/cancel pair's
  visibility.
  Rationale: Per the source's own doc comment, "a captured chord is
  pending until the user commits it, and focus can leave in the middle of
  that (they click the checkmark, after all), so the state that decides
  whether ✓ and ✗ are on screen cannot live in the thing that loses focus."
  Approved: pending
- Decision: `commitEdit()` sets the committed binding's enabled flag to
  `true` whenever the command has no authored binding or its current
  shortcut is `nil`, but preserves the existing enabled flag when
  re-recording an already-authored, already-bound command.
  Rationale: Per the source's own comment, "recording a chord is
  unambiguous intent to use it, so the command comes on — unless the user
  themselves switched it off, in which case the switch stays where they
  put it. A shipped 'off' is not the user's choice: the suggested global
  chords ship off, and recording over one must not save a chord that
  silently never fires."
  Approved: pending
- Decision: `toggleChanged()` snaps the switch back to off and shows a
  refusal message, rather than silently ignoring the attempt, when turning
  a command on would collide with another command's chord.
  Rationale: Per the source's own comments, "switching on puts the chord
  back in play, so it has to be free: a chord two commands hold fires
  both," and "the switch snapping back by itself would otherwise read as a
  control that is broken rather than one that said no."
  Approved: pending
- Decision: The readout row's visibility is driven by `isEditing ||
  refusal != nil`, not by `isEditing` alone.
  Rationale: `toggleChanged()`'s refusal path never sets `isEditing`, so
  without this the toggle's refusal message would have nowhere visible to
  appear; the refusal persists on screen until the next edit begins,
  because `isEditing`'s `didSet` is what clears `refusal`.
  Approved: pending
- Decision: `onRecordingChanged(false)` clears the mid-edit state only when
  no chord is pending; when a chord is pending, the mid-edit state is left
  untouched.
  Rationale: Per the source's own comment, "clicked in and straight back
  out without pressing anything: there is nothing to confirm, so the pair
  should not linger" — but when a chord *is* pending, the mid-edit state
  must survive the field resigning first responder, since clicking the
  confirm/cancel pair itself moves focus off the capture field before the
  commit or cancel runs.
  Approved: pending
- Decision: This recipe carries substantially more behavioral requirements
  (39) than the structurally simpler settings-row siblings in this family
  (e.g. `CheckboxView` at 12, `CaptionedSliderView`'s comparable count).
  Rationale: `KeyCommandRowView` is genuinely more complex by the
  cross-recipe-consistency measure of distinct behaviors and states: it
  composes four subviews instead of two, owns a multi-step pending-edit
  state machine, and mediates conflict-checking through the shared
  registry — none of which the simpler bound-value rows in this family do.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |
| [meaningful-labels](agenticdevelopercookbook://compliance/accessibility#meaningful-labels) | needs-review | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | needs-review | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | needs-review | internationalization |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [accessibility-identifiers](agenticdevelopercookbook://compliance/ui#accessibility-identifiers) | passed | ui |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
