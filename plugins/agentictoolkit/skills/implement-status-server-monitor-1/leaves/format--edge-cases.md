<!-- leaf: implement-status-server-monitor-1/format--edge-cases · source: status-server-monitor-format.md -->

# Status Server Monitor Format

**Rules** (cite as `implement-status-server-monitor-1/format--edge-cases#<slug>`):

- `null-and-empty-input` MUST — shortSha, commitFirstLine, and commitFullMessage each treat null, undefined, and the empty string '' identically, …
- `boundary-values` MUST — for both commitFirstLine and commitFullMessage, a string whose length is exactly max is returned unchanged, and only a …
- `concurrent-access` MUST — not a synchronization concern by construction — all three functions are pure, take no shared mutable state as an …

## Edge Cases

- **Null and empty input**: `shortSha`, `commitFirstLine`, and `commitFullMessage` each
  treat `null`, `undefined`, and the empty string `''` identically, returning `null` for
  all three, because each function's guard is a single truthiness check
  (`if (!hash)` / `if (!message)`) rather than an explicit `null`/`undefined` comparison —
  MUST. `commitFullMessage` additionally treats a message that is present but consists
  entirely of whitespace (for example `'   \n  '`) as empty, because trailing-whitespace
  stripping leaves nothing for the string to contain — MUST.
- **Boundary values**: for both `commitFirstLine` and `commitFullMessage`, a string whose
  length is exactly `max` is returned unchanged, and only a string strictly longer than
  `max` is truncated, because the cap is a strict `length > max` comparison before slicing
  — MUST. A `max` of `0` truncates any non-empty extracted string to the empty string
  (`slice(0, 0)`), not to `null` — the empty-result guard is on `hash`/`message` only, and
  is checked before truncation runs, so a truncated-to-empty result is never re-checked
  against it — MUST.
- **Concurrent access**: not a synchronization concern by construction — all three
  functions are pure, take no shared mutable state as an argument, and hold none at module
  scope, so any number of concurrent callers, on one request or many, may call them in any
  order or in parallel with no possibility of interleaved corruption — MUST.
- **Error states**: not applicable — none of the three functions has a dependency
  (network, database, file system) that can fail; each computes its result synchronously
  from the arguments it was given, and none can throw for any input within its declared
  parameter type.
- **Offline / disconnected state**: not applicable — this module issues no network call and
  has no connectivity of its own to lose. What happens when a caller (a fetcher such as
  `fetch-vercel.ts`) cannot reach its own upstream is that caller's concern, external to
  this file.
