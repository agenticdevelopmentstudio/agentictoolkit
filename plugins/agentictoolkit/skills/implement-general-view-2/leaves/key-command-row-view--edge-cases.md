<!-- leaf: implement-general-view-2/key-command-row-view--edge-cases · source: key-command-row-view.md -->

# KeyCommandRowView

**Rules** (cite as `implement-general-view-2/key-command-row-view--edge-cases#<slug>`):

- `current-chord-taken-level-behavior-rather-than` MUST — Error states: Not applicable in the throw/catch sense — no throwing API is called anywhere in KeyCommandRowView.swift. …
- `current-enabled-flag-level-source-traceable-distinction` MUST — Re-recording a shipped-off, never-touched command versus one the user explicitly turned off: both have …

## Edge Cases

- Null/empty input: `command` (`KeyCommandDescriptor`) and `registry`
  (`KeyCommandRegistry`) are non-optional, typed constructor parameters;
  Swift's type system rules out `nil` for either (see
  **requires-a-command-and-a-registry-to-construct**). `command.title` as
  an empty string produces a title label reading `":"` with no crash.
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
  readout row hide again — per
  **ends-editing-when-recording-stops-with-nothing-pending**, and called
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
  elsewhere (see **preserves-pending-edit-on-external-change**, traced to
  `refresh()`'s body).
- A refusal shown after a toggle refusal, with no active recording: the
  refusal path (`toggleChanged`) sets `refusal` without ever setting
  `isEditing`; `updateReadoutVisibility()` still reveals the readout row
  because it reacts to `refusal != nil` independently of `isEditing`. The
  refusal message clears along either of two paths: the next edit
  beginning (`isEditing`'s `didSet` clears `refusal` when it becomes
  `true`), or an accepted toggle change, which sets `refusal = nil` directly
  in `toggleChanged()` before writing the binding (see
  **clears-refusal-on-an-accepted-toggle-change**). Absent either, the
  refusal persists on screen — traced directly to the class's own doc
  comment: "shown in the readout until the next edit."
