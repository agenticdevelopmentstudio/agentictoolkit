<!-- leaf: implement-composable-tabs/view-registry--edge-cases · source: composable-tabs-view-registry.md -->

# ComposableTabsViewRegistry

**Rules** (cite as `implement-composable-tabs/view-registry--edge-cases#<slug>`):

- `view-id-entry-return-unknown-rather-than` MUST — Null/empty input: descriptor(for:) for a view id with no entry MUST return .unknown rather than throwing or crashing — …
- `view-id-entry-return-placeholder-rather-than` MUST — Null/empty input: makeContentViewController(...) for a view id with no entry MUST return a placeholder rather than …
- `called-treeid-nil-fall-back-nodeid-per` MUST — Null/empty input: makeContentViewController(...) called with treeID: nil MUST fall back to nodeID per tree-id-default, …
- `theme-chartseriesnscolors-empty-leave-container-untinted-per` MUST — Null/empty input: PlaceholderPaneViewController loaded while the theme's chartSeriesNSColors is empty MUST leave the …
- `empty-one-empty-leave-container-previously-set` MUST — Boundary values: A theme switch from a chart-series list that is non-empty to one that is empty MUST leave the …
- `values-unregister-placeholder-always-refused-regardless-how` MUST — Boundary values: unregister(.placeholder) MUST always be refused, regardless of how many other view ids are registered …
- `boundary-values-panenumber-index-chartseriesnscolors-number-series` MUST — Boundary values: paneNumber == 1 MUST index chartSeriesNSColors[0] (the (number - 1) % series.count formula's lowest …

## Edge Cases

- Null/empty input: `descriptor(for:)` for a view id with no entry MUST
  return `.unknown` rather than throwing or crashing — traced to
  `entries[viewID]?.descriptor ?? .unknown`.
- Null/empty input: `makeContentViewController(...)` for a view id with no
  entry MUST return a placeholder rather than throwing — traced to the
  `guard let entry = entries[viewID] else { ... return PlaceholderPaneViewController(...) }`.
- Null/empty input: `makeContentViewController(...)` called with `treeID: nil`
  MUST fall back to `nodeID` per **tree-id-default**, rather than
  leaving `treeID` `nil` or generating a new identifier — traced to
  `treeID: treeID ?? nodeID`.
- Null/empty input: `PlaceholderPaneViewController` loaded while the theme's
  `chartSeriesNSColors` is empty MUST leave the container untinted per
  **empty-series-no-tint** — traced to
  `guard !series.isEmpty else { return }`.
- Boundary values: A theme switch from a chart-series list that is non-empty
  to one that is empty MUST leave the container's previously set tint in
  place, per **stale-tint-persistence** — traced to the same
  `guard !series.isEmpty else { return }` in the `observeTheme` closure, which
  makes no assignment on that path rather than clearing the layer's
  `backgroundColor`.
- Boundary values: `unregister(.placeholder)` MUST always be refused,
  regardless of how many other view ids are registered — the only view id the
  registry hard-codes as non-removable.
- Boundary values: `paneNumber == 1` MUST index `chartSeriesNSColors[0]` (the
  `(number - 1) % series.count` formula's lowest input), and any `paneNumber`
  larger than the series length MUST wrap via the modulo rather than index out
  of bounds.
- Concurrent access: The registry, `ComposableTabsViewContext`, and
  `PlaceholderPaneViewController` are all `@MainActor`; registration,
  unregistration, lookup, and content creation all happen on the main actor,
  so concurrent mutation from multiple threads is not a case this file has to
  handle.
- Error states: The only error path in this file is an unregistered view id,
  and it is not surfaced as a thrown error or shown to the user — it is
  handled by falling back to `PlaceholderPaneViewController` and logging at
  `.error` (**unregistered-fallback**,
  **placeholder-protection**). Nothing in this file communicates that
  fallback to the caller beyond the placeholder itself and the log line.
- Offline/disconnected: Not applicable. The registry makes no network call
  and holds no server-backed state; it is a pure in-memory, single-process
  map from view id to descriptor and factory.
