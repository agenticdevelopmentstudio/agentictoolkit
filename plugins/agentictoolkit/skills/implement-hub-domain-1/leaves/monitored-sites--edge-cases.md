<!-- leaf: implement-hub-domain-1/monitored-sites--edge-cases · source: hub-domain-monitored-sites.md -->

# Hub Domain Monitored Sites

**Rules** (cite as `implement-hub-domain-1/monitored-sites--edge-cases#<slug>`):

- `null-and-empty-input-workspace` MUST — not checked client-side in any of the twelve functions. opts.workspace is a typed string | undefined; an empty string …
- `null-and-empty-input-required-create-fields` MUST — createGroup, createSite, and createEndpoint perform no client-side check that name/slug/url are non-empty; an empty …
- `boundary-values-retentiondays-expectedstatus-checkintervalseconds` MUST — none of these numeric fields has a client-side minimum, maximum, or integer check; whatever number the caller supplies …

## Edge Cases

- **Null and empty input — `workspace`**: not checked client-side in any of the twelve functions. `opts.workspace`
  is a typed `string | undefined`; an empty string is sent unchanged as `workspace=` (or, for
  `listEndpoints`, silently omitted, since `qs.set` is only called when `opts?.workspace` is truthy and an
  empty string is falsy). This is a MUST per the observed source; no validation exists.
- **Null and empty input — required create fields**: `createGroup`, `createSite`, and `createEndpoint`
  perform no client-side check that `name`/`slug`/`url` are non-empty; an empty string is sent to the
  backend unchanged, per `compact()`'s own scope (it drops only `undefined`, never filters an empty
  string). MUST behave this way per source.
- **Boundary values — `retentionDays`/`expectedStatus`/`checkIntervalSeconds`**: none of these numeric
  fields has a client-side minimum, maximum, or integer check; whatever number the caller supplies
  (including negative, zero, or non-integer) is sent to the backend unchanged via `compact()`. MUST
  behave this way per source — no declared closed set constrains these fields, unlike `kind`.
- **Boundary values — list size past the generic-CRUD 500-row cap**: per the module's own comment on
  `listSites`, "generic-CRUD lists cap at 500." `listGroups`, `listSites`, and `listEndpoints` accept no
  pagination, cursor, or limit parameter, and none of the three inspects the returned row count or signals
  truncation to the caller; a workspace with more than 500 groups, sites, or endpoints receives a silently
  incomplete list from any of the three. This is a fact traced directly to the source's own comment, not a
  gap invented by this recipe — see the `pagination-support` compliance finding below.
- **Concurrent access — module state**: this module holds no shared mutable state between calls (only the
  read-only `GROUPS`/`SITES`/`ENDPOINTS`/`ENDPOINT_KINDS` constants), so there is nothing for two
  concurrent calls to race on within the module itself.
- **Concurrent access — competing writes**: two concurrent `updateSite`/`updateGroup`/`updateEndpoint`
  calls for the same `id` follow ordinary `PUT` semantics — last response received wins, with no
  client-side sequencing, optimistic-lock check, or `updatedAt`-based conflict detection in this file.
- **Concurrent access — reparent then list**: calling `updateSite` to move a site to a new group and then
  immediately calling `listSites`/`listEndpoints` issues two independent requests with no client-side
  cache to invalidate; the second request's freshness depends entirely on the backend having committed
  the first, which this module does not wait on beyond the first request's own response.
- **Error states — non-2xx response**: every non-`401` failure and every unresolved `401` throws
  `AuthHttpError` carrying the HTTP status and optional code (`errors-carry-status-and-code`); nothing in
  this file catches or swallows that error.
- **Error states — `204` on a declared-void write**: `deleteGroup`, `deleteSite`, and `deleteEndpoint` call
  `authedRequest` (which discards the body and does not special-case `204`), so a `204` response resolves
  normally; this differs from `authedJson`, which throws on `204` — none of `monitored-sites.ts`'s create
  or update functions can receive a bodiless `204`, since `authedJson` treats that as an error regardless
  of caller intent.
- **Offline or disconnected state**: none of the twelve functions catches a network-level `fetch`
  rejection; a connectivity loss mid-call propagates as an unhandled promise rejection out of this module
  to the caller, with no retry, queuing, or offline-specific handling anywhere in this file.
- **No timeout**: no function sets a deadline or `AbortSignal`; a reachable-but-unresponsive backend leaves
  the call pending until the underlying `fetch` implementation's own limit, if any.
- **No cancellation**: no function accepts an `AbortSignal` parameter, so a caller cannot cancel an
  in-flight request through this module.
- **No retry beyond the `401` waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in this file retries a network failure or a non-`401`
  error status.
- **Stale module doc comment**: the module's own top-of-file comment states "the client-side narrowing in
  `listSites()`/`listEndpoints()` stays as defense-in-depth," but `listSites`'s implementation performs no
  such filter — it maps and sorts the response with no owner/workspace narrowing of its own; only
  `listEndpoints` retains a client-side filter (on `siteId`, per `endpoint-list-double-filtered`). This is
  recorded as an observed discrepancy between the source's comment and its code in Design Decisions, not
  smoothed over.
