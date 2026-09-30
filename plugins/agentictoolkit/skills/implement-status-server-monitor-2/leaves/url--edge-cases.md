<!-- leaf: implement-status-server-monitor-2/url--edge-cases · source: status-server-monitor-url.md -->

# Status Server Monitor URL

**Rules** (cite as `implement-status-server-monitor-2/url--edge-cases#<slug>`):

- `null-and-empty-input` MUST — hostOf's parameter is declared string, not nullable — a caller passing null/undefined violates that typed contract, a …
- `boundary-values` MUST — for projectPageUrl, exactly 3 pathname segments after filter(Boolean) is the minimum that triggers the Vercel collapse …
- `concurrent-access` MUST — not a synchronization concern by construction — both functions are pure, take no shared mutable state as an argument, …
- `error-states` MUST — the only failure mode either function can encounter is the URL constructor throwing on a malformed or relative URL …

## Edge Cases

- **Null and empty input**: `hostOf`'s parameter is declared `string`, not nullable — a
  caller passing `null`/`undefined` violates that typed contract, a fact stated by the
  signature rather than unvalidated input the function itself must guard against. At
  runtime, an empty string `''` passed to `hostOf` throws inside `new URL('')` and is caught,
  returning `''` unchanged — MUST. `projectPageUrl` explicitly accepts `null`, `undefined`,
  and `''` and returns `null` for all three via one truthiness check — MUST.
- **Boundary values**: for `projectPageUrl`, exactly 3 pathname segments after
  `filter(Boolean)` is the minimum that triggers the Vercel collapse
  (`parts.length >= 3`); exactly 2 segments does not, and the original `url` passes through
  unchanged rather than being reconstructed — MUST. A pathname with a leading, trailing, or
  doubled slash is unaffected because `filter(Boolean)` drops the empty strings such
  separators produce — MUST.
- **Concurrent access**: not a synchronization concern by construction — both functions are
  pure, take no shared mutable state as an argument, and hold none at module scope, so any
  number of concurrent callers, on one request or many, may invoke either function in any
  order or in parallel with no possibility of interleaved corruption — MUST.
- **Error states**: the only failure mode either function can encounter is the `URL`
  constructor throwing on a malformed or relative URL string; both functions catch that error
  explicitly and fall back to returning the original `url` argument unchanged. The thrown
  error object itself is discarded — the `catch` block binds no variable and inspects nothing
  about the failure — so a caller cannot distinguish "parsed and passed through" from "failed
  to parse and passed through": both produce the identical output. This is a documented,
  deliberate passthrough (per `projectPageUrl`'s doc comment: "Other platforms / unrecognised
  URLs pass through unchanged"), not a swallowed error requiring escalation — MUST.
- **Offline / disconnected state**: not applicable — neither function makes a network call
  or holds any connection state of its own; a caller's own network reachability (for example
  whether `sync.ts` can reach a monitored endpoint) is entirely external to this file.
