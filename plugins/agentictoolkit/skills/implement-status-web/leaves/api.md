<!-- leaf: implement-status-web/api · source: status-web-api.md -->

**Rules** (cite as `implement-status-web/api#<slug>`):

- `default-base-path` MUST
- `url-join` MUST
- `late-fetch-resolution` MUST
- `json-content-type` MUST
- `json-ok-body` MUST
- `json-204-empty` MUST
- `json-error-message` MUST
- `json-error-detail` MUST
- `event-source-target` MUST
- `provider-client-selection` MUST
- `provider-memoization` MUST
- `hook-fallback` MUST
- `endpoint-optional-field-defaults` MUST
- `endpoint-ignore-warning-default` MUST
- `endpoint-dns-defaults` MUST
- `site-group-rename` MUST
- `group-crud` MUST
- `site-crud` MUST
- `endpoint-list-scope` MUST
- `endpoint-write-field-list` MUST
- `integration-crud` MUST
- `ignored-projects-list` MUST
- `ignore-project-fanout` MUST
- `unignore-project-id` MUST
- `peer-token-write-semantics` MUST
- `peer-view-redaction` MUST
- `peer-write-passthrough` MUST
- `peer-crud-routes` MUST

# Status Web API

## Overview

`status-web`'s one port onto its backend, and the two configuration-CRUD clients
built on it. `client.ts` defines `StatusApiClient` — `url`, `fetch`, `json`, and
`eventSource`, all resolved relative to a `basePath` — plus `createStatusApiClient`,
a `defaultClient` singleton, a React context, `StatusApiProvider`, and the
`useStatusApi` hook every panel and hook call instead of naming a base path
themselves. `monitored-sites.ts` is the monitoring-configuration client: groups,
sites, endpoints, integrations, and ignored deploy projects, each with a
backend-`Row` type mapped to a frontend `View` type. `peers.ts` is the
fleet-membership client: list/create/update/delete for the peer monitors this
one polls, including the shared-secret `token` field's write-only semantics.
All three files talk to the status backend through the caller-supplied
`StatusApiClient`, never naming `/api` themselves except in `client.ts`'s one
`DEFAULT_API_BASE` constant.

## Behavioral Requirements

### client.ts

- **default-base-path**: `createStatusApiClient` MUST default `basePath` to
  `DEFAULT_API_BASE` (the fixed string `"/api"`) when the caller supplies no
  `basePath` option.
- **url-join**: `url(path)` MUST return `${basePath}${path}` — a plain string
  concatenation with no encoding, normalization, or leading-slash correction.
- **late-fetch-resolution**: `fetch(path, init)` MUST resolve which `fetch`
  implementation to call — `fetchImpl` if the client was constructed with one,
  otherwise `globalThis.fetch` — at the time of each call, not once when
  `createStatusApiClient` runs.
- **json-content-type**: `json<T>(path, init)` MUST send a
  `"Content-Type": "application/json"` header on every request, and MUST let
  any `Content-Type` present in `init.headers` take precedence over that
  default (the headers object is built as
  `{"Content-Type": "application/json", ...(init?.headers ?? {})}`).
- **json-ok-body**: `json<T>` MUST return the parsed `await res.json()` body
  for any successful (`res.ok`) response whose status is not `204`.
- **json-204-empty**: `json<T>` MUST return `undefined` for a successful
  response with status `204`, without calling `res.json()`.
- **json-error-message**: `json<T>` MUST throw an `Error` when `res.ok` is
  `false`, with a message of exactly `${method} ${url} → ${status}`, where
  `method` is `init?.method` if given, else `"GET"`, and `url` is
  `this.url(path)`.
- **json-error-detail**: the thrown error message MUST be suffixed with
  ` — ${text}` when the failed response's body parses as JSON and yields a
  usable detail string, checked in this order: a string `error` field, then
  `error.message`, then a top-level `message` field; the message MUST carry
  no such suffix when the body does not parse as JSON or none of those
  fields is present.
- **event-source-target**: `eventSource(path)` MUST return
  `new EventSource(this.url(path))`.
- **provider-client-selection**: `StatusApiProvider` MUST use the `client`
  prop when one is given, and otherwise MUST construct a `StatusApiClient`
  via `createStatusApiClient({basePath})`.
- **provider-memoization**: the client `StatusApiProvider` supplies to its
  subtree MUST be memoized (`useMemo`) on `[client, basePath]`, so a
  re-render of the provider with the same `client`/`basePath` identity MUST
  NOT construct a new client instance.
- **hook-fallback**: `useStatusApi()` MUST return the nearest ancestor
  `StatusApiProvider`'s client when one is mounted, and MUST otherwise
  return the module-level `defaultClient` singleton, built once at module
  load via `createStatusApiClient()` with no arguments.

### monitored-sites.ts

- **endpoint-optional-field-defaults**: `toEndpoint` MUST default each of
  `environment`, `platform`, `deployProject`, and `expectBody` to `null` when
  the corresponding `EndpointRow` field is `undefined`, and MUST preserve an
  explicit non-`undefined` value (including an explicit `null`) unchanged.
- **endpoint-ignore-warning-default**: `toEndpoint` MUST default
  `ignoreProjectWarning` to `false` when `EndpointRow.ignoreProjectWarning` is
  `undefined`.
- **endpoint-dns-defaults**: `toEndpoint` MUST default each of `dnsCheckA`,
  `dnsCheckAaaa`, and `dnsCheckCname` to `true` when the corresponding
  `EndpointRow` field is `undefined`, and MUST preserve an explicit `false`
  value rather than overwriting it.
- **site-group-rename**: `toSite` MUST map `SiteRow.siteGroupId` to
  `SiteView.groupId`; the resulting `SiteView` MUST NOT carry a
  `siteGroupId` field.
- **group-crud**: `listGroups`, `createGroup`, `updateGroup`, and
  `deleteGroup` MUST call `GET`, `POST`, `PATCH`, and `DELETE` respectively
  against `/config/site-groups` (a specific group by appending `/{id}` for
  update and delete), and each of `listGroups`/`createGroup`/`updateGroup`
  MUST return its result mapped through `toGroup`.
- **site-crud**: `listSites`, `createSite`, and `updateSite` MUST call `GET`,
  `POST`, and `PATCH` against `/config/sites` (a specific site by appending
  `/{id}` for update), each returning its result mapped through `toSite`;
  `createSite`'s request body MUST rename the caller's `groupId` to
  `siteGroupId`.
- **endpoint-list-scope**: `listEndpoints(api, siteId)` MUST request
  `/config/endpoints?siteId={siteId}` (URL-encoded) and MUST map every
  returned row through `toEndpoint`; `listAllEndpoints` MUST request the bare
  `/config/endpoints` path with no `siteId` query parameter.
- **endpoint-kind-required**: `createEndpoint`'s parameter type (`Partial<Omit<EndpointView, "id" | "siteId">> & { url: string }`) leaves `kind` optional, and the client passes `body.kind` through unchecked — `monitored-sites.ts` only re-exports `ENDPOINT_KINDS` from `@/lib/endpoint-kinds` and never validates against it. A caller that omits `kind` sends no `kind` field; the status-server's create-endpoint schema accepts it as an optional string and the `kind` column defaults to `"http"`, so the endpoint is stored as an HTTP monitor.
- **endpoint-write-field-list**: `createEndpoint` and `updateEndpoint` MUST
  send exactly the fields named on `EndpointWriteFields` (every `EndpointView`
  field except `id` and `siteId`, plus `siteId`/`url` on create); a field the
  caller omits from `body` MUST be sent as `undefined`, and an `undefined`
  field MUST NOT appear in the serialized JSON body at all.
- **integration-crud**: `listIntegrations`, `createIntegration`,
  `updateIntegration`, and `deleteIntegration` MUST call `GET`, `POST`,
  `PATCH`, and `DELETE` against `/config/integrations` (a specific
  integration by `/{id}`), passing the caller's `body` object to
  `JSON.stringify` unmodified — no field allow-list is applied, unlike the
  group/site/endpoint functions.
- **ignored-projects-list**: `listIgnoredProjects` MUST return the result of
  `GET /config/ignored-projects` unmodified (no per-row mapping).
- **ignore-project-fanout**: `ignoreProjects` MUST issue one
  `POST /config/ignored-projects` request per project in its input array, in
  parallel via `Promise.all`, and MUST reject as soon as any one of those
  requests rejects; the outcome of every other request already in flight at
  that point MUST NOT be awaited or reported.
- **unignore-project-id**: `unignoreProject` MUST build its request path as
  `DELETE /config/ignored-projects/{id}`, where `{id}` is
  `encodeURIComponent` applied to the string `${platform}|${projectName}`.

### peers.ts

- **peer-token-write-semantics**: a caller's `Partial<PeerWrite>` update MUST
  be interpreted as: a `string` value for `token` sets or replaces the stored
  token; `null` clears it; omitting the `token` key from the update object
  MUST leave the stored token unchanged, since a redacted token cannot be
  echoed back to distinguish "no change" from "clear."
- **peer-view-redaction**: `PeerView` MUST NOT carry the raw token value; it
  MUST carry only `hasToken`, a boolean indicating whether a token is set.
- **peer-write-passthrough**: `createPeer` and `updatePeer` MUST serialize
  the caller's `body`/`Partial<PeerWrite>` object directly via
  `JSON.stringify`, with no field allow-list step — unlike
  `monitored-sites.ts`'s group/site/endpoint functions, which rebuild an
  explicit `fields` object before stringifying.
- **peer-crud-routes**: `listPeers`, `createPeer`, `updatePeer`, and
  `deletePeer` MUST call `GET`, `POST`, `PATCH`, and `DELETE` respectively
  against `/config/peers` (a specific peer by `/{id}` for update and
  delete).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `basePath` | `string` | `DEFAULT_API_BASE` (`"/api"`) | `createStatusApiClient`/`StatusApiProvider` option; every relative `path` is joined onto this prefix by `url()`. |
| `fetch` | `typeof fetch` | `globalThis.fetch` | `createStatusApiClient` option; injected to install a test double or a `fetch` polyfill, resolved fresh on every call (late-fetch-resolution). |
| `client` | `StatusApiClient` | none — the provider builds its own | `StatusApiProvider` prop; when given, `useStatusApi()` returns it verbatim instead of a provider-constructed client. |
| `body.environment` | one of `ENVIRONMENTS` (`"production" \| "staging" \| "testing"`) | none — caller-supplied | endpoint create/update field; not validated against `ENVIRONMENTS` by this module. |
| `body.platform` | one of `PLATFORMS` (`"vercel" \| "railway" \| "cloudflare" \| "crunchy"`) | none — caller-supplied | endpoint create/update field; not validated against `PLATFORMS` by this module. |
| `body.kind` | one of `ENDPOINT_KINDS` (`"http" \| "frontend" \| "admin" \| "health" \| "custom" \| "dns"`) | none — caller-supplied, optional in the type | omitted → server default `"http"`, per `endpoint-kind-required`. |
| `body.token` (peers) | `string \| null` | omitted key = leave unchanged | see `peer-token-write-semantics`. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `${method} ${url} → ${status}` (plus an optional ` — ${text}` detail suffix) | `client.ts`'s `json<T>` throws this as a plain `Error` message on every non-ok response (json-error-message, json-error-detail); it is English-only and never sourced from a localization resource. |

