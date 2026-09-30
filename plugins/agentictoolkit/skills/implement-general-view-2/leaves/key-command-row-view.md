<!-- leaf: implement-general-view-2/key-command-row-view · source: key-command-row-view.md -->

**Rules** (cite as `implement-general-view-2/key-command-row-view#<slug>`):

- `appends-colon-to-title` MUST
- `arranges-main-row` MUST
- `stacks-main-and-readout-rows` MUST
- `hides-confirm-cancel-when-not-editing` MUST
- `hides-readout-row-when-idle` MUST
- `links-toggle-accessibility-title` MUST
- `sets-capture-field-accessibility-identifier` MUST
- `sets-toggle-accessibility-identifier` MUST
- `begins-editing-on-capture` MUST
- `begins-editing-on-recording-start` MUST
- `forwards-recording-state-to-registry` MUST
- `ends-editing-when-recording-stops-with-nothing-pending` MUST
- `keeps-editing-open-when-recording-stops-with-a-pending-chord` MUST
- `refuses-commit-without-a-pending-chord` MUST
- `refuses-commit-of-an-unavailable-chord` MUST
- `enables-command-on-first-or-unbound-commit` MUST
- `preserves-enabled-state-on-rebind` MUST
- `commits-pending-chord-to-registry` MUST
- `clears-edit-state-after-commit-or-cancel` MUST
- `refreshes-after-commit-or-cancel` MUST
- `cancels-without-writing-a-binding` MUST
- `refuses-toggle-on-when-the-current-chord-is-taken` MUST
- `clears-refusal-on-an-accepted-toggle-change` MUST
- `commits-accepted-toggle-state` MUST
- `refreshes-on-external-bindings-change` MUST
- `preserves-pending-edit-on-external-change` MUST
- `reflects-bound-shortcut-on-refresh` MUST
- `shows-placeholder-when-unbound` MUST
- `reflects-enabled-state-on-refresh` MUST
- `disables-toggle-without-a-bound-shortcut` MUST
- `shows-refusal-in-status-label` MUST
- `shows-unavailable-reason-while-pending` MUST
- `prompts-for-a-chord-while-pending-is-empty` MUST
- `shows-availability-label-for-an-available-pending-chord` MUST
- `colors-status-label-by-availability` MUST
- `gates-confirm-by-availability` MUST
- `requires-a-command-and-a-registry-to-construct` MUST
- `rejects-coder-initialization` MUST
- `removes-its-notification-observer-on-deinit` MUST
- `confines-to-main-actor` MUST

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
  horizontal row, in that order.
- **stacks-main-and-readout-rows**: Component MUST stack the main row above
  the readout row in a vertical stack with 4pt spacing between them, and
  MUST pin that stack to the component's own edges.
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
- **preserves-pending-edit-on-external-change**: Component MUST NOT clear
  the pending shortcut or leave the mid-edit state when it refreshes in
  response to a bindings-changed notification triggered by a change made
  elsewhere (for example, by a sibling row).
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

