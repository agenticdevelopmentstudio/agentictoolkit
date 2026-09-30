<!-- leaf: implement-status-web/api--edge-cases · source: status-web-api.md -->

# Status Web API

**Rules** (cite as `implement-status-web/api--edge-cases#<slug>`):

- `null-and-empty-input` MUST — toEndpoint MUST turn an absent environment, platform, deployProject, or expectBody into null, and an absent …
- `error-states` MUST — a non-ok HTTP response from any of these functions MUST surface as the crafted Error from …

## Edge Cases

- **Null and empty input**: `toEndpoint` MUST turn an absent `environment`,
  `platform`, `deployProject`, or `expectBody` into `null`, and an absent
  `ignoreProjectWarning` into `false` (endpoint-optional-field-defaults,
  endpoint-ignore-warning-default). `ignoreProjects` called with an empty
  array MUST resolve immediately via `Promise.all([])`, issuing no request.
  `listEndpoints`/`unignoreProject` perform no client-side check that
  `siteId`/`platform`/`projectName` is non-empty before URL-encoding it into
  the request; an empty string is sent to the backend as-is.
- **Boundary values**: none of `retentionDays`, `checkIntervalSeconds`, or
  `expectedStatus` is range-checked by this module before being sent;
  `environment` and `platform` are typed against the `ENVIRONMENTS`/
  `PLATFORMS` constants but, like `kind` (see `endpoint-kind-required`),
  nothing in `monitored-sites.ts` validates membership in either list
  before a request is sent.
- **Concurrent access**: this is single-threaded browser JavaScript; no two
  calls into these files ever interleave on the same value. Multiple
  concurrent calls to `json`/`fetch`/`eventSource` are independent — no
  shared mutable state exists outside each call's own closures (the
  `defaultClient` singleton is stateless: only `basePath` and a resolved
  `fetch` reference). `ignore-project-fanout`'s `Promise.all` deliberately
  issues its N requests concurrently; when one rejects, the already-issued
  sibling requests continue running to completion in the background, but
  neither their results nor their errors are surfaced.
- **Error states**: a non-ok HTTP response from any of these functions MUST
  surface as the crafted `Error` from `json-error-message`/`json-error-detail`.
  A network-level failure — `fetch()` itself rejecting because the request
  never reached a server (offline, DNS failure, CORS) — is caught nowhere in
  `client.ts`, `monitored-sites.ts`, or `peers.ts`; it propagates to the
  caller as whatever error `fetch()` produces, which is a different shape
  than the `${method} ${url} → ${status}` message a non-ok response
  produces.
- **Offline or disconnected state**: the same uncaught-`fetch()`-rejection
  behavior above covers a `json`/`fetch` call made while offline. For
  `eventSource(path)`, this file only constructs the native `EventSource`
  object; reconnection after the connection drops is entirely the browser's
  native `EventSource` behavior — none of these three files listens for or
  reacts to an SSE `error` event, or re-creates the `EventSource` itself.
