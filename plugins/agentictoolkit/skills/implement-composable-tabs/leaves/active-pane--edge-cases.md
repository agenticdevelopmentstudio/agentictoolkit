<!-- leaf: implement-composable-tabs/active-pane--edge-cases · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane

**Rules** (cite as `implement-composable-tabs/active-pane--edge-cases#<slug>`):

- `input-activenodeid-nil-return-nil-rather-than` MUST — Null/empty input: activeNodeID(in: nil) MUST return nil rather than trapping or treating a missing window as any …
- `nsevent-associated-window-ignored-record-traced-guard` MUST — Null/empty input: An NSEvent with no associated window MUST be ignored by record(_:) — traced to guard let window = …
- `whose-contentview-nil-treated-having-pane-under` MUST — Null/empty input: A window whose contentView is nil MUST be treated as having no pane under any point — traced to …
- `window-zero-panes-have-entry-active-id` MUST — Boundary values: A window with zero panes MUST have no entry in the active id map, and any view queried against that …
- `exactly-one-pane-have-pane-hold-active` MUST — Boundary values: A window with exactly one pane MUST have that pane hold the active id once it appears, per …
- `makefirstresponder-returning-false-handled-internally-takefocus-within` MUST — Error states: The only "failure" outcome in this file is a view refusing first-responder status (makeFirstResponder …

## Edge Cases

- Null/empty input: `activeNodeID(in: nil)` MUST return `nil` rather than
  trapping or treating a missing window as any particular window's state.
- Null/empty input: An `NSEvent` with no associated `window` MUST be ignored
  by `record(_:)` — traced to `guard let window = event.window else { return }`
  (see **an-event-with-no-window-is-ignored**).
- Null/empty input: A window whose `contentView` is `nil` MUST be treated as
  having no pane under any point — traced to `paneChain(under:in:)`'s
  `guard let contentView = window.contentView else { return nil }` (see
  **a-nil-content-view-means-no-pane**).
- Boundary values: A window with zero panes MUST have no entry in the active
  id map, and any view queried against that window (there being no pane to
  contain it) counts as active per **view-outside-any-pane-counts-as-active**.
- Boundary values: A window with exactly one pane MUST have that pane hold
  the active id once it appears, per **arrival-claims-active-in-an-unclaimed-window**,
  and MUST have no active pane left once it departs, per
  **departure-clears-active-id-when-no-pane-survives**.
- Concurrent access: The whole component is `@MainActor`; every mutation of
  its window/pane bookkeeping happens on the main actor, so concurrent access
  from multiple threads is not a case this file has to handle. Two sources
  that could otherwise race with in-flight AppKit event tracking —
  `NSWindow.willCloseNotification` and the `highlightActivePane` settings
  publisher — are explicitly re-dispatched onto `DispatchQueue.main` (not
  `RunLoop.main`) so a change made while AppKit tracks a mouse-down in
  `.eventTracking` run-loop mode is still applied, rather than being deferred
  until the tracking loop ends.
- Error states: The only "failure" outcome in this file is a view refusing
  first-responder status (`makeFirstResponder` returning `false`). This MUST
  be handled internally by `takeFocus(within:in:)`'s three-way
  `FocusOutcome` (`taken` / `nowhereToPut` / `refused`) as described above; it
  is never surfaced to a caller, logged, or shown to the user — there is no
  user-visible error state for a focus refusal beyond the outline and
  keyboard simply not moving.
- Offline/disconnected: Not applicable. The component makes no network call
  and has no server-backed state; it is a pure in-memory, single-process
  tracker of per-window UI state.
