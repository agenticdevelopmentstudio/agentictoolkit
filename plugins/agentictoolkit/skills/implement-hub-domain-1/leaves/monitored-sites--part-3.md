<!-- leaf: implement-hub-domain-1/monitored-sites--part-3 · source: hub-domain-monitored-sites.md -->

# Hub Domain Monitored Sites — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/monitored-sites--part-3#<slug>`):

- `swiftui` SHOULD — model SiteGroupView/SiteView/EndpointView (and the create/update body shapes) as Codable, Hashable, Sendable structs, …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.workspace` (every function) | `string` (caller parameter, optional) | omitted → caller's own owner scope | Percent-encoded and appended as `?workspace=<slug>` (or `&workspace=<slug>` on `listEndpoints`); pins the operation to a workspace's owning principal instead of the caller's own scope. |
| `body` (`createGroup`) | `CreateGroupBody` (`{ name, slug, retentionDays? }`) | none — required except `retentionDays` | Sent through `compact()` as the `POST` body. |
| `body` (`updateGroup`) | `UpdateGroupBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` as the `PUT` body. |
| `body` (`createSite`) | `CreateSiteBody` (`{ name, slug, groupId }`, all required) | none — required | Sent verbatim (renamed to `siteGroupId`) as the `POST` body; not passed through `compact()`. |
| `body` (`updateSite`) | `UpdateSiteBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` (renamed to `siteGroupId`) as the `PUT` body. |
| `siteId` (`listEndpoints`, `createEndpoint`) | `string` (caller parameter, required) | none | Identifies the parent site; sent as a query parameter on `listEndpoints` and as a body field on `createEndpoint`. |
| `body` (`createEndpoint`) | `CreateEndpointBody` (`{ url, kind, expectedStatus?, checkIntervalSeconds?, isActive? }`) | none — `url`/`kind` required, rest optional | Sent through `compact()` as the `POST` body, with `siteId` added from the function's own parameter. |
| `body` (`updateEndpoint`) | `UpdateEndpointBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` as the `PUT` body; carries no `siteId` field. |
| `ENDPOINT_KINDS` | module constant, `readonly ["http","tcp","icmp"]` | fixed | The declared set of valid `kind` values; not consulted by `createEndpoint`/`updateEndpoint` (`endpoint-kind-validation`). |
| `GROUPS`/`SITES`/`ENDPOINTS` | module constants, fixed path strings | fixed | `/api/monitoring/site-groups`, `/api/monitoring/sites`, `/api/monitoring/endpoints`; not injectable or configurable. |

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes monitoring
  configuration records — group/site names and slugs, retention windows, and endpoint URLs, kinds, and
  check intervals. These are infrastructure-monitoring configuration records, not end-user PII.
- **Storage**: none. Every function is a stateless per-call request builder (`no-client-side-cache`,
  `module-holds-no-mutable-state`); nothing is held in memory or on disk beyond the lifetime of a single
  call.
- **Transmission**: yes. Every call carries a bearer credential attached by `@agentic-toolkit/auth/client`
  (`auth-delegated-to-shared-client`), not by this module; whatever transport security the deployment
  provides is outside the scope of these two files.
- **Retention**: none. Nothing this module handles is retained after the response it produced is returned
  to the caller.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/monitored-sites/monitored-sites.ts`
  and `wire.ts` hold the client, re-exported by `index.ts` as `@agentic-toolkit/data/monitored-sites`;
  every function is built on `authedJson`/`authedRequest` (from `../http`, re-exporting
  `@agentic-toolkit/auth/client`) and `compact`/`enc`/`sortByText`/`workspaceQuery` (from
  `../client-helpers`). The Dashboards feature (`packages/web/packages/features/dashboards/src/*`) is the
  one current consumer.
- **SwiftUI**: model `SiteGroupView`/`SiteView`/`EndpointView` (and the create/update body shapes) as
  `Codable, Hashable, Sendable` structs, mirroring the sibling Hub domain recipes' models pattern, and the
  twelve functions as `async throws` calls on an `actor` or `@MainActor final class`, with a dedicated
  error type carrying the HTTP status and optional machine code in place of `AuthHttpError`. `ENDPOINT_KINDS`
  becomes a `CaseIterable` `enum` — and, unlike the TypeScript source, a Swift port SHOULD use that enum as
  the `kind` parameter's type rather than a bare `String`, which would close the `endpoint-kind-validation`
  gap at compile time rather than reproducing it.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Dashboards feature would
  consume the ported client through an injected data-source protocol, the same pattern other Hub domain
  recipes' data sources already use, rather than calling `URLSession` from the view layer.
- **Compose**: model the three wire rows and the six body shapes as Kotlin `data class`es annotated
  `@Serializable`, and the twelve functions as `suspend fun`s on a class built on Ktor or OkHttp, with a
  sealed error type carrying the HTTP status and optional code; model `ENDPOINT_KINDS` as a Kotlin `enum
  class`.
- **WinUI 3**: a .NET port would model `GroupRow`/`SiteRow`/`EndpointRow` and the six body shapes as
  `record`s attributed for `System.Text.Json`, and the twelve functions as `Task<T>`-returning methods on a
  class built on `HttpClient`, attaching `Authorization: Bearer <token>` the way this module's
  `authedFetch` does and refreshing on a `401` the same one-retry way, defining a `MonitoredSitesApiException`
  (status, code) parallel to `AuthHttpError`. Represent `ENDPOINT_KINDS` as a C# `enum EndpointKind { Http,
  Tcp, Icmp }` with a `[JsonConverter]` for the lowercase wire strings, and prefer exposing the endpoint
  list to a bound UI (e.g. a `DataGrid`/`ItemsRepeater`) through an `ObservableCollection<EndpointView>`
  populated after each `Task` completes, rather than a raw array, since WinUI 3's data-binding idiom
  expects change notification a plain `List<T>` does not provide — this is the platform with the least
  existing prior art in this repo for the refresh-and-retry contract, so the WinUI 3 port would need to
  build the equivalent of `authedFetch` itself, not only the twelve request builders.

## Design Decisions

**Decision**: `createSite` builds its body as a plain object literal (`{ name, slug, siteGroupId:
body.groupId }`) rather than passing it through `compact()`, even though `createGroup` and
`createEndpoint` both do.
**Rationale**: `CreateSiteBody`'s three fields are all required (unlike `CreateGroupBody.retentionDays`
or `CreateEndpointBody`'s optional fields), so `compact()` would be a no-op here; the source omits the
call rather than applying it unconditionally for consistency.
**Approved**: pending

**Decision**: the module's own top-of-file comment states "the client-side narrowing in
`listSites()`/`listEndpoints()` stays as defense-in-depth," but `listSites`'s current implementation
performs no owner/workspace filter — only a `sortByText` by name.
**Rationale**: `listSites`'s own inline comment explains the server now owner-scopes `sites` identically
to `site_groups`, and the earlier client-side intersection (against the groups list) was removed
specifically because it round-tripped an extra request and hid rows past the 500-row cap; the top-of-file
comment appears to predate that refactor and was not updated to drop the `listSites()` half of its claim.
This recipe records the code as it actually behaves — no client-side owner narrowing in `listSites` — per
the source-fidelity guideline's requirement to describe the code as it is rather than as a stale comment
describes it.
**Approved**: pending

**Decision**: `listEndpoints` builds its query string with `URLSearchParams`/`qs.set` instead of the
shared `workspaceQuery` helper every other function in this file uses.
**Rationale**: `listEndpoints` already needs `URLSearchParams` to carry the required `siteId` parameter,
so appending `workspace` to that same object avoids constructing a second query-string fragment and
concatenating it; the resulting request is equivalent to what `workspaceQuery` would have produced, but
the code path is not shared.
**Approved**: pending
