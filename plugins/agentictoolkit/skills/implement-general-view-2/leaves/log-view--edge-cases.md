<!-- leaf: implement-general-view-2/log-view--edge-cases · source: log-view.md -->

# Log View

**Rules** (cite as `implement-general-view-2/log-view--edge-cases#<slug>`):

- `null-empty-input` MUST — provider.lines empty at construction or after a clear MUST render zero rows (see States: Empty). A line with no value …
- `boundary-values` MUST — A click exactly on the last valid row and last valid column index MUST dispatch normally; a click one index past the …

## Edge Cases

- **Null/empty input**: `provider.lines` empty at construction or after a
  clear MUST render zero rows (see States: Empty). A line with no value for
  a given column MUST render that cell as an empty string
  (`missing-cell-value-renders-empty`). A column with `onClick`/
  `onDoubleClick` both `nil` MUST allow a click to resolve without effect
  (the hook call is a no-op optional invocation).
- **Boundary values**: A click exactly on the last valid row and last valid
  column index MUST dispatch normally; a click one index past the last row
  (`row == provider.lines.count`) MUST be inert
  (`click-outside-valid-cell-is-inert`). An unbounded log (`maxLines ==
  Int.max`) or a log capped by `maxLines` are both handled identically by
  this component, since row-count capping is a `LogProvider` concern —
  `LogView` only ever displays however many lines `provider.lines` reports
  at the time it is asked.
- **Concurrent access**: The component, `LogProvider`, and
  `LogProviderDelegate` are all `@MainActor`-isolated, so every provider
  mutation and every view update this component performs is serialized onto
  the main actor; Swift's actor isolation is the entirety of the concurrency
  handling, with no additional locking or queuing.
- **Error states**: `LogView` performs no I/O, network, or asynchronous
  operation of its own, so it has no failure mode to report. It has no
  validation of the `LogLine`/`LogColumn` values it is handed beyond the
  guards already covered above (`missing-cell-value-renders-empty`,
  `click-outside-valid-cell-is-inert`); malformed input from a
  misbehaving provider is not specially detected or reported.
- **Offline/disconnected state**: Not applicable. The component makes no
  network calls; connectivity handling, if any, belongs to whatever
  `LogProvider` implementation feeds it (for example, an SSE subscription),
  which is a separate component.
