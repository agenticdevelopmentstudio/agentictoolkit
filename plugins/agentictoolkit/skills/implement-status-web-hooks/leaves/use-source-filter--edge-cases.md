<!-- leaf: implement-status-web-hooks/use-source-filter--edge-cases · source: status-web-hooks-use-source-filter.md -->

# useSourceFilter

**Rules** (cite as `implement-status-web-hooks/use-source-filter--edge-cases#<slug>`):

- `empty-selection` MUST — toggling off every source MUST give an empty Set. For ActivityPanel, this hides every row that has a known platform …
- `unknown-source-string` MUST — the IssueSource parameter type rules this out at compile time. A value forced in with a cast MUST be added to or …
- `source-added-to-issue-sources-later` MUST — new mounts MUST include it in the default. An instance that is already mounted does not pick it up until it remounts.
- `rapid-repeated-toggles` MUST — each call MUST flip membership once, based on the latest queued state (source-filter-007).
- `strict-mode-double-invoked-updater` MUST — the result MUST be the same as a single call, because the updater is pure.
- `reload-or-remount` MUST — the selection MUST reset to all-selected. The source persists nothing (see Design Decisions).
- `server-render` MUST — the hook MUST render the default all-selected Set on the server. It touches no browser-only API.

## Edge Cases

- **Empty selection**: toggling off every source MUST give an empty `Set`. For `ActivityPanel`, this hides every row that has a known `platform` whenever more than one source exists. Rows whose `platform` is null or missing still show, because the consumer lets them through.
- **Unknown source string**: the `IssueSource` parameter type rules this out at compile time. A value forced in with a cast MUST be added to or removed from the in-memory `Set` like any other value, because the hook does no runtime check. `sources.size` can then exceed 7.
- **Source added to `ISSUE_SOURCES` later**: new mounts MUST include it in the default. An instance that is already mounted does not pick it up until it remounts.
- **Rapid repeated toggles**: each call MUST flip membership once, based on the latest queued state (source-filter-007).
- **Strict Mode double-invoked updater**: the result MUST be the same as a single call, because the updater is pure.
- **Reload or remount**: the selection MUST reset to all-selected. The source persists nothing (see Design Decisions).
- **Server render**: the hook MUST render the default all-selected `Set` on the server. It touches no browser-only API.
- **Null or empty input, timeouts, cancellation, network loss, storage errors**: not applicable. The hook takes no arguments, and its only operation is a synchronous in-memory set update with no I/O.
