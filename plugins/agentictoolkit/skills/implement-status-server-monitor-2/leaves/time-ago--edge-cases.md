<!-- leaf: implement-status-server-monitor-2/time-ago--edge-cases · source: status-server-monitor-time-ago.md -->

# Status Server Monitor Time Ago

**Rules** (cite as `implement-status-server-monitor-2/time-ago--edge-cases#<slug>`):

- `null-and-empty-input` MUST — iso and nowMs are both declared as required, non-optional parameters (string and number); the source performs no …
- `boundary-values` MUST — at diffSecs = 59 the result is 'just now'; at diffSecs = 60 it is '1m' — MUST. At diffMins = 59 the result is '59m'; at …
- `concurrent-access` MUST — not a synchronization concern by construction — timeAgo is a pure, synchronous function that reads only its own two …
- `error-states` MUST — timeAgo has no dependency (network, database, file system) that can fail, and it never throws for any input reachable …

## Edge Cases

- **Null and empty input**: `iso` and `nowMs` are both declared as required, non-optional
  parameters (`string` and `number`); the source performs no runtime check for `null`,
  `undefined`, or an empty string on either. Passing `iso: ''` produces
  `new Date('').getTime()`, which is `NaN`, taking the same `NaN`-propagation path
  described under `no-iso-validation` — the function falls through to the days bucket and
  returns `'NaNd'` — MUST (see `no-iso-validation`).
- **Boundary values**: at `diffSecs = 59` the result is `'just now'`; at `diffSecs = 60` it
  is `'1m'` — MUST. At `diffMins = 59` the result is `'59m'`; at `diffMins = 60` it is
  `'1h'` — MUST. At `diffHours = 23` the result is `'23h'`; at `diffHours = 24` it is
  `'1d'` — MUST. There is no upper boundary on the days bucket: an elapsed time of, for
  example, 3650 days returns `'3650d'` unchanged, with no rollover to a larger unit — MUST.
- **Concurrent access**: not a synchronization concern by construction — `timeAgo` is a
  pure, synchronous function that reads only its own two arguments and holds no
  module-level or shared mutable state, so any number of concurrent callers may call it in
  any order or in parallel with no possibility of interleaved corruption — MUST.
- **Error states**: `timeAgo` has no dependency (network, database, file system) that can
  fail, and it never throws for any input reachable through its declared parameter types.
  A malformed `iso` does not raise an error; instead it silently produces the incorrect
  string `'NaNd'`, per `no-iso-validation` — MUST.
  Validating `iso` is the caller's job.
- **Offline / disconnected state**: not applicable — this file issues no network call and
  has no connectivity of its own to lose. Both call sites (`integrations.ts`,
  `fetch-vercel-projects.ts`) already hold their own timestamp — from local storage or an
  already-fetched deploy record — before calling `timeAgo`, so a caller's own network
  reachability is entirely external to this file.
