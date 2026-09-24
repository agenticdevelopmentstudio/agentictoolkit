---
id: 7add8e4b-922e-4518-aa45-79bf56cdf8bc
title: ApiToolkit
domain: agentictoolkit://recipes/api-toolkit
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Same-origin BFF request building, generated-endpoint lookup, JSON-Schema derived examples and field descriptions, and generic-CRUD headless hooks shared by @agentic-toolkit/api-explorer and @agentic-toolkit/crud."
platforms:
- typescript
- web
tags:
- crud
- api
- metadata
- headless
depends-on: []
related:
- agentictoolkit://recipes/crud-table
- agentictoolkit://recipes/crud-record-form
references: []
---

# ApiToolkit

## Overview

`ApiToolkit` is the headless, non-UI logic shared by two sibling packages:
`@agentic-toolkit/api-explorer` (`packages/web/packages/api-explorer/src/`) and
`@agentic-toolkit/crud` (`packages/web/packages/crud/src/`). Neither package
exports a component named `ApiToolkit`; this recipe is the umbrella
specification for their pure `lib/` functions and headless hooks — the parts
with no JSX and no DOM access — so that the request-building, endpoint-lookup,
schema-derivation, slugging, snippet-generation, and generic-CRUD contracts
are documented once instead of being re-derived by every UI recipe that
consumes them (`CrudTable`, `CrudRecordForm`, and any `ApiBrowser`/
`ApiEndpointReference` consumer).

`api-explorer`'s logic builds and executes same-origin `/api` BFF requests
from generated OpenAPI endpoint metadata (`buildRequest.ts`, `getEndpoint.ts`),
derives cycle-safe JSON-Schema examples and field descriptions
(`schema.ts`), highlights code with a dual-theme, lazily-cached shiki
instance (`highlight.ts`), projects endpoints to crawlable, collision-checked
URL slugs (`slug.ts`), generates cURL/JavaScript request snippets with a
deliberate non-live token placeholder (`snippets.ts`), and maps HTTP
method/status to a fixed presentation "tone" (`tone.ts`). `server.ts` is a
server-only entry (no `'use client'`) that re-exports the non-interactive
pieces; `index.ts` is the client barrel and deliberately excludes the large
generated endpoint metadata so importing a button component never pulls it
into the initial bundle.

`crud`'s logic derives per-column editability from a fixed precedence
(`editability.ts`), tracks staged, dirty, mergeable row edits
(`edits.ts`), gates table visibility by a presentation-only authorization
tier (`exposure.ts`), exposes the generated CRUD schema allowlist
(`schemas.ts`), defines the shared CRUD metadata shapes (`types.ts`), runs
list/create/update/remove against the same `/api` BFF through a headless hook
with an out-of-order-response guard (`useCrudResource.ts`), bridges an
imperative unsaved-changes guard into a stable proxy object
(`useExitGuardChannel.ts`), and exposes the current viewer's admin capability
and readiness (`viewer.ts`).

## Behavioral Requirements

### buildRequest.ts

- **request-base**: `API_BASE` MUST be the fixed string `/api`; every built
  request MUST be same-origin relative to this base, never an absolute
  cross-origin URL.
- **path-substitution**: `substitutePath` MUST replace each `{name}` path
  segment with the URL-encoded value from `pathValues` when present, and MUST
  leave a `{name}` segment visible, unencoded, in the resulting path when no
  matching value is supplied.
- **body-allowed**: `bodyAllowed` MUST return `true` only when the endpoint's
  method is one that accepts a body per its metadata; it MUST return `false`
  otherwise so `buildRequest` never attaches a body to a body-less method.
- **request-headers**: `buildRequest` MUST set `Content-Type: application/json`
  only when a body is actually attached, and MUST set
  `Authorization: Bearer <token>` only when a `token` argument is supplied;
  neither header MUST be present when its precondition is absent.
- **mutating-methods**: `isMutating` MUST return `true` for every HTTP method
  except `GET`, `HEAD`, and `OPTIONS`, and MUST return `false` for those three.
- **response-normalization**: `executeRequest` MUST resolve to an `ApiResult`
  for every HTTP status code, `2xx` through `5xx` inclusive, and MUST record
  the elapsed wall-clock duration (via `performance.now()`) on that result;
  it MUST NOT throw for a non-2xx HTTP response.
- **network-failure-propagation**: `executeRequest` MUST let a transport-level
  failure from `fetch` (offline, DNS failure, a CORS block) reject its promise
  rather than resolve to an `ApiResult`; its "never throws" contract covers
  only non-2xx statuses. `ApiEndpointDetail` catches the rejection and shows
  its message through `setError` (falling back to `'Request failed'`).
- **request-timeout**: neither `buildRequest` nor `executeRequest` attaches a
  timeout or an `AbortController` to the underlying `fetch`; a request that
  never resolves stays in flight until the browser gives up.

### getEndpoint.ts

- **endpoint-key**: `endpointKey` MUST derive a unique key from an endpoint's
  method and path such that `getEndpoint` can look up the same endpoint by
  that key.
- **tag-index-caching**: `index()` MUST build the tag-to-endpoints index
  (`_byTag`/`_tags`) lazily, on first use, and MUST reuse the cached result on
  every subsequent call rather than rebuilding it.
- **tag-ordering**: `allTags()` MUST return tags in sorted order.
- **endpoints-for-tag-ordering**: `endpointsForTag(tag)` MUST return that
  tag's endpoints sorted first by path, then by the fixed `METHOD_ORDER`
  ranking for endpoints sharing a path.

### highlight.ts

- **highlighter-singleton**: `highlighterPromise` MUST be created at most once
  per process (module-level cache) and MUST be reused by every subsequent call
  to `highlightToHtml` rather than re-importing/re-initializing shiki.
- **highlighter-dual-theme**: the cached highlighter MUST support both the
  `github-light` and `github-dark` themes and the `json`, `bash`, and
  `javascript` languages.
- **highlighter-failure-recovery**: if highlighter initialization rejects,
  the module MUST reset `highlighterPromise` back to `null` so a subsequent
  call retries initialization rather than being permanently disabled by one
  transient failure.
- **pretty-json-fallback**: `prettyJson` MUST return the original input text
  unchanged when `JSON.parse` fails, and MUST return an empty string for
  blank input; it MUST NOT throw.

### schema.ts

- **ref-resolution-scope**: `refName` MUST resolve only local
  `#/components/schemas/` references; a `$ref` outside that local scope MUST
  NOT be treated as resolved.
- **example-cycle-safety**: `schemaToExample` MUST thread a `seen` set through
  every recursive call so that a cyclic schema (a schema that refs itself,
  directly or transitively) terminates rather than recursing indefinitely.
- **example-precedence**: `schemaToExample` MUST resolve an example value by
  trying, in order: `$ref` resolution, `anyOf`/`oneOf` variant selection,
  `allOf` merge, an explicit `example`, an explicit `default`, the first
  `enum` value, then a type-driven default — stopping at the first
  applicable step.
- **type-label-truncation**: `typeLabel` MUST append a `?` suffix for a
  nullable type, MUST render a union of variants, and MUST truncate an enum
  preview beyond its fourth value with `…` rather than listing every value.
- **field-description-depth**: `describeFields` MUST describe fields exactly
  one level deep (name, type, required, description) after
  `unwrapToObject` has dereferenced/unwrapped `$ref`, array `items`, a
  null-union, and merged `allOf`.

### slug.ts

- **slug-projection**: `endpointSlug(meta)` MUST strip `{param}` braces from
  every path segment and MUST append the method, lower-cased, as the final
  slug segment.
- **slug-collision-detection**: the lazily-built `_slugToKey` index MUST throw
  when two distinct endpoints project to the same slug, rather than silently
  letting the second endpoint alias or shadow the first.
- **slug-lookup-miss**: `endpointForSlug(slug)` MUST return `undefined`, not
  throw, when no endpoint maps to the given slug.

### snippets.ts

- **snippet-token-placeholder**: every generated snippet MUST embed
  `TOKEN_PLACEHOLDER` (the literal string `YOUR_TOKEN`) in place of any real
  bearer token; a generated snippet MUST NOT embed a live, caller-supplied
  token.
- **snippet-body-inclusion**: `bodyText` MUST include a request body in the
  generated snippet only when `meta.requestBody` is non-null and the supplied
  body, once trimmed, is non-empty.
- **curl-snippet-escaping**: `curlSnippet` MUST single-quote an embedded JSON
  body and MUST shell-escape any single quote that occurs inside that body.

### tone.ts

- **method-tone-mapping**: `methodBadgeClass`/`methodDotClass` MUST map each
  of `GET`, `POST`, `PUT`, `PATCH`, `DELETE` to that method's fixed badge/dot
  classes, and MUST fall back to the neutral class for any other method.
- **method-text-class-consistency**: `methodTextClass(method)` MUST always
  equal the first space-delimited token of `methodBadgeClass(method)` for
  every method, so the badge and the text-only rendering can never drift onto
  different palettes.
- **status-tone-mapping**: `statusTone` MUST map `200`–`299` to the green
  tone, `400`–`499` to the orange tone, `500` and above to the red tone, and
  any other status to the muted tone.

### server.ts / index.ts (barrel split)

- **server-entry-no-client-directive**: `server.ts` MUST NOT carry a
  `'use client'` directive, so it can be imported from server-only code
  without pulling client component bundling requirements with it.
- **client-barrel-excludes-metadata**: `index.ts` (the client barrel) MUST
  NOT re-export `getEndpoint`/`API_ENDPOINTS`; a component imported from the
  client barrel MUST NOT bundle the generated endpoint metadata as a
  transitive dependency.
- **shared-cache-via-package-path**: `server.ts` MUST import `allTags`,
  `endpointsForTag`, `getEndpoint`, and `endpointKey` via the package path
  (`@agentic-toolkit/api-explorer/lib/getEndpoint`), not a relative path, so
  that the server entry and the client barrel — two separate build chunk
  graphs — observe the same module-level cache instance rather than each
  forking its own copy.

### editability.ts

- **server-managed-lock**: a column with `serverManaged: true` MUST NOT be
  editable in any mode, regardless of any override.
- **override-precedence**: `EDITABLE_OVERRIDES` MUST take effect only for a
  non-relational, non-server-managed column; an override MUST NOT make a
  relational (primary-key or foreign-key-shaped) column, nor a
  server-managed column, editable.
- **relational-create-only**: a relational column (a `pkParams` member, an
  exact `ID_REF_NAMES` match, or a match against the `ID_REF_SUFFIX` pattern
  `/(Id|_id|Rdid|_rdid)$/`) MUST be editable only when the mode is `create`,
  never in `edit` mode.
- **create-only-lock-on-edit**: a column marked `createOnly` MUST NOT be
  editable once the mode is `edit`.
- **default-editable**: a column that is not server-managed, not relational,
  and not locked by `createOnly` in edit mode MUST be editable by default.
- **hidden-columns**: `isColumnHidden` MUST return `true` only for a
  server-managed column.

### edits.ts

- **dirty-detection**: `isRowDirty(baseline, edits)` MUST return `true` if
  and only if at least one key present in `edits` has a value that is
  strictly (`!==`) different from the same key's value in `baseline`; because
  `edits` MUST carry only the columns that were actually changed, iterating
  its keys MUST be sufficient — `isRowDirty` MUST NOT need to inspect any key
  absent from `edits`.
- **draft-merge-immutability**: `mergeDraft(baseline, edits)` MUST return a
  new object overlaying `edits` onto `baseline`, and MUST NOT mutate either
  `baseline` or `edits`.

### exposure.ts

- **presentation-only-gate**: `canReadTable`/`canWriteTable` MUST be
  documented and treated as presentation-only; they MUST NOT be relied upon
  as the authorization boundary — the server MUST independently re-check
  every request regardless of what the client renders.
- **read-allowlist**: `canReadTable` MUST return `true` for `owner` and
  `catalog` exposure for any viewer, and MUST return `true` for `admin`
  exposure only when `isAdminViewer` is `true`.
- **write-allowlist**: `canWriteTable` MUST return `true` for `owner`
  exposure for any viewer, and MUST return `true` for `catalog` or `admin`
  exposure only when `isAdminViewer` is `true`.
- **fail-closed-on-unknown-tier**: a table whose exposure tier is missing or
  unrecognized MUST be denied both read and write for a non-admin viewer;
  `readableTables` MUST exclude such a table from its filtered result for a
  non-admin viewer.
- **order-preserving-filter**: `readableTables(tables, isAdminViewer)` MUST
  preserve the input order of the tables it retains.

### schemas.ts

- **schema-allowlist-single-source**: `CRUD_SCHEMAS` MUST be computed exactly
  once, at module load, from the generated `CRUD_TABLES`, and MUST serve as
  the single source of truth consulted by both halves of the
  allowlist-to-feature lockstep check.

### useCrudResource.ts

- **item-url-substitution**: `itemUrl(meta, row)` MUST substitute each
  `pkParams` value, URL-encoded, into `itemPath` to build the per-item URL.
- **row-key-derivation**: `rowKey(meta, row)` MUST join the row's escaped
  primary-key values, and MUST return the empty string when a single-pk row
  has no value for that key.
- **loading-vs-fetching**: `loading` MUST mean "nothing to show for the
  current list yet" and `fetching` MUST mean "a list call is currently open";
  the two MUST be able to diverge (e.g. a background re-list on an
  already-populated list has `fetching: true` but `loading: false`).
- **out-of-order-response-guard**: the hook MUST track a `listSeq` sequence
  number per list call and MUST discard the result of any list response
  whose sequence number is not the latest issued, so a slow, stale response
  MUST NOT overwrite state written by a newer, faster response.
- **loaded-for-tracking**: `loadedFor` MUST track which list identity's rows
  are currently on screen, and `loading` MUST be derived as
  `fetching && loadedFor.current !== listId` so switching to a not-yet-loaded
  list shows `loading`, while re-fetching an already-loaded list does not.
- **query-composition-order**: the `listQuery` string MUST place the
  `scopeEcosystemId`-derived `scopeQuery` before the `filterQuery` when both
  are present.
- **mutation-relist**: `create`, `update`, and `remove` MUST re-issue the list
  call after their underlying mutation succeeds; `createRow`, `updateRow`, and
  `removeRow` (the raw mutators they call) MUST NOT re-list on their own.
- **delete-uses-authed-request**: `removeRow` MUST call `authedRequest`
  (which discards the response body), not `authedJson`, because the DELETE
  endpoint answers `204 No Content` and `authedJson` throws on a `204`.
- **mutation-error-not-hook-state**: a failure from `createRow`, `updateRow`,
  or `removeRow` MUST propagate to the caller as a rejected promise, and MUST
  NOT be written into the hook's own `error` state.

### useExitGuardChannel.ts

- **stable-proxy-identity**: the `PaneExitGuard` proxy returned while a guard
  is registered MUST be the same object identity across re-registrations
  (built once via `useMemo` with an empty dependency array).
- **presence-is-the-dirty-signal**: the hook MUST expose the proxy (non-null)
  only while `present` is `true`, and MUST expose `null` once withdrawn;
  callers MUST treat the presence of a non-null guard, not merely a call to
  it, as part of the dirty signal.
- **proxy-reads-latest-guard**: the stable proxy's `isDirty()` MUST read
  through `guardRef` to the most recently registered guard rather than
  closing over a stale one.

### viewer.ts

- **standalone-default**: `useViewer()` MUST return the settled value
  `{ isAdmin: false, ready: true }` when no `AuthProvider` is mounted
  (`useOptionalAuth()` returns `null`), so the browser is usable standalone
  without ever reporting an unsettled/loading state.
- **admin-derivation**: when an `AuthProvider` is mounted, `isAdmin` MUST be
  derived from `isAdmin(auth.user)` and `ready` MUST be derived from
  `!auth.isLoading` — `ready` MUST distinguish "settled" from "still
  loading," never conflating the two.

## Appearance

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component.

## States

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component. (Runtime
state machines — `loading`/`fetching` in `useCrudResource`, `present` in
`useExitGuardChannel`, `ready`/`isAdmin` in `useViewer` — are specified above
under Behavioral Requirements.)

## Accessibility

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component.

## Conformance Test Vectors

| # | Input | Expected output/effect | Source |
|---|---|---|---|
| 1 | `methodTextClass('GET')` | Equals `methodBadgeClass('GET').split(' ')[0]` for every method (GET/POST/PUT/PATCH/DELETE/TRACE) | `tone.ts`; asserted by `tone.test.ts` |
| 2 | `methodDotClass('TRACE')` (an unrecognized method) | Falls back to the neutral dot class rather than throwing or returning `undefined` | `tone.ts`; asserted by `tone.test.ts` |
| 3 | `canReadTable({ exposure: 'admin' }, false)` | `false` (admin-only table denied to a non-admin viewer) | `exposure.ts`; asserted by `exposure.test.ts` |
| 4 | `canWriteTable({ exposure: 'catalog' }, false)` | `false` (catalog is readable but not writable by a non-admin) | `exposure.ts`; asserted by `exposure.test.ts` |
| 5 | `isColumnEditable(relationalColumn, { [relationalColumn.name]: true }, 'edit')` | `false` — an override cannot force a relational column editable outside `create` | `editability.ts`; asserted by `editability.test.ts` |
| 6 | `isRowDirty(baseline, {})` then `isRowDirty(baseline, { name: baseline.name })` | `false` in both cases — no edits, and an edit typed back to the baseline value | `edits.ts`; asserted by `edits.test.ts` |
| 7 | `removeRow(meta, row)` against an endpoint that answers `204 No Content` | Resolves via `authedRequest` (body discarded); calling `authedJson` on the same response would throw | `useCrudResource.ts`; corroborated by `authedJson`'s documented 204 behavior in `auth/client.ts` |
| 8 | Two list calls issued in quick succession where the first (older `listSeq`) resolves after the second (newer `listSeq`) | Only the newer response's rows are written to state; the stale, later-arriving response is discarded | `useCrudResource.ts`; asserted by `useCrudResource.test.tsx` |
| 9 | `endpointSlug({ path: '/users/{id}', method: 'GET' })` | `'users-id-get'` — braces stripped, method lower-cased and appended | `slug.ts` (no dedicated test file found) |
| 10 | `buildRequest(meta, values)` with no `token` argument, versus the same call with a `token` | No `Authorization` header in the first case; `Authorization: Bearer <token>` present in the second | `buildRequest.ts` (no dedicated test file found) |

## Edge Cases

- **Unfilled path parameter**: `substitutePath` leaves an unmatched `{name}`
  segment visible, unencoded, in the built path rather than erroring or
  omitting the segment — a deliberate, documented rendering choice, not a
  gap.
- **Cyclic schema**: `schemaToExample`'s `seen`-set threading guarantees
  termination on a schema that refs itself directly or transitively.
- **Slug collision**: two endpoints that would project to the same slug
  cause `slug.ts`'s lazily-built index to throw at build time rather than
  silently aliasing one endpoint's reference page onto another's.
- **External (non-local) `$ref`**: `refName` only resolves local
  `#/components/schemas/` references; a schema containing a `$ref` outside
  that scope is not resolved by `refName` and falls through
  `schemaToExample`'s remaining precedence steps (this API's generated
  OpenAPI schemas are self-contained, so this scope limitation is a design
  decision — see Design Decisions — not a runtime failure mode).
- **Out-of-order network responses**: `useCrudResource`'s `listSeq` guard is
  the specified defense against a slow list response overwriting a newer
  one; a mutation (`createRow`/`updateRow`/`removeRow`) has no equivalent
  sequence guard because those calls are not re-issued concurrently against
  the same resource by the hook itself.
- **Concurrent access to `EDITABLE_OVERRIDES`**: this module-level object is
  empty (`{}`) by default and is intended as static, hand-populated
  configuration; production code never mutates it at runtime. Only test code
  mutates and restores it. Because JavaScript execution is single-threaded,
  this is not a concurrency hazard in practice — it is a fact about the
  module's intended use, not an unresolved gap.
- **Network-level failure of a built request**: an offline/DNS/CORS failure
  rejects `executeRequest`'s promise instead of producing an `ApiResult` (see
  `network-failure-propagation`); the caller turns it into an error message.
- **Hung request**: no timeout or `AbortController` bounds the request built by
  `buildRequest`/`executeRequest` (see `request-timeout`); a connection that
  never resolves keeps the request in flight.

## Configuration

- **`API_BASE`** (`buildRequest.ts`, `useCrudResource.ts`) — fixed constant
  `/api`; not caller- or environment-configurable in the given source.
- **`token`** (`buildRequest(meta, values, token?)`) — optional, caller-
  supplied bearer token forwarded as `Authorization: Bearer <token>`.
- **`PUBLIC_API_ORIGIN`** (`snippets.ts`) — fixed constant
  `https://api.agenticdeveloperhub.com` used only for generated snippet URLs,
  never for the same-origin requests `buildRequest` itself issues.
- **`EDITABLE_OVERRIDES`** (`editability.ts`) — a module-level object callers
  may hand-populate (outside test code) to force a non-relational,
  non-server-managed column's editability; empty by default.
- **`meta` / `filter` / `scopeEcosystemId`** (`useCrudResource(meta, filter?,
  scopeEcosystemId?)`) — `meta` (the table's `CrudTableMeta`) is required;
  `filter` is an optional caller-supplied query object serialized into
  `listQuery`; `scopeEcosystemId` is an optional caller-supplied scope value
  that precedes `filter` in the query string and rides every verb, not just
  the list call.
- **`isAdminViewer`** (`exposure.ts`'s `canReadTable`/`canWriteTable`/
  `readableTables`) — caller-supplied boolean, typically sourced from
  `useViewer()`'s `isAdmin`.

## Deep Linking

`slug.ts` exists specifically to make each API endpoint reachable by a
crawlable, collision-checked URL slug: `endpointSlug(meta)` projects an
endpoint to a slug (path segments with `{param}` braces stripped, plus the
lower-cased method appended), and `endpointForSlug(slug)` reverses that
projection for routing, returning `undefined` on a miss rather than throwing.
This is the deep-linking contract for the whole recipe; no other given source
file participates in deep linking.

## Localization

None of the given sources externalize strings into a localization resource
system; the following are hardcoded, English-only strings that are facts
about the current implementation, not gaps:

- `snippets.ts`'s `TOKEN_PLACEHOLDER` (`'YOUR_TOKEN'`) is embedded verbatim,
  in English, in every generated cURL/JavaScript snippet.
- `slug.ts`'s collision message (`api-explorer: endpoint slug collision on
  "${slug}"...`) is a hardcoded English developer-facing error string.
- `useCrudResource`'s reliance on the auth package's hardcoded English error
  message for an unexpected `204` response (see Platform Notes) is inherited,
  not produced, by this recipe's own sources.

## Accessibility Options

Not applicable: none of the given sources render a visual or interactive
surface, so there is no contrast, motion, font-size, or other
accessibility-preference surface for this recipe to define.

## Feature Flags

Not applicable: no feature-flag check (e.g. an LaunchDarkly/config-service
call, or a hand-rolled flag lookup) appears in any of the given sources.
`EDITABLE_OVERRIDES` is column-editability configuration, not a feature flag.

## Analytics

Not applicable: none of the given sources emit an analytics/telemetry event
or call an analytics client.

## Privacy

- `buildRequest`'s `token` parameter is forwarded as an `Authorization`
  header and is never persisted, cached, or logged by any given source; the
  caller owns the token's lifecycle.
- `snippets.ts` deliberately substitutes `TOKEN_PLACEHOLDER` for any real
  token so that copying a generated snippet to the clipboard can never leak a
  live credential — a privacy-motivated design decision (see Design
  Decisions).
- `exposure.ts`'s tier gate (`canReadTable`/`canWriteTable`) is presentation
  data-minimization only: it narrows which tables the UI *offers* to a
  non-admin viewer, but it is explicitly documented as not a security or
  privacy boundary — the server independently decides what data is actually
  returned.
- None of the given sources persist personally identifiable information to
  local storage, a database, or any other durable store.

## Logging

Not applicable: none of the given sources call `console.*`, a logger, or
otherwise emit diagnostic output.

## Platform Notes

- **Web (source platform)**: `fetch`, `AbortController`, `URLSearchParams`,
  and `Promise` are the native browser primitives this recipe's TypeScript
  is written against; `shiki` (via dynamic `import()`) is the only
  third-party runtime dependency among the given sources.
- **Apple (Swift, not in source)**: `URLSession` (with `URLRequest`) is the
  equivalent of `buildRequest`/`executeRequest`; `Codable` is the equivalent
  of the JSON-Schema-driven `schemaToExample`/`describeFields` derivation
  (though Codable is compile-time-typed, so a dynamic JSON-Schema-to-example
  projection has no direct one-to-one match); `Task`/`async`/`await` replace
  the Promise-based flow; a stable `AnyObject` proxy under `@MainActor`
  would replace `useExitGuardChannel`'s `useMemo`-stabilized proxy.
- **Android (Kotlin, not in source)**: `OkHttp` or `Retrofit` plus
  `kotlinx.serialization` (or Moshi) replace `buildRequest`/`executeRequest`
  and the schema-derived example/field logic respectively; Kotlin
  `Flow`/`StateFlow` replace the `loading`/`fetching` state pair exposed by
  `useCrudResource`; a `Mutex`-guarded sequence counter would replace the
  `listSeq` out-of-order-response guard.
- **WinUI 3 (Windows, not in source)**: `HttpClient` replaces `buildRequest`/
  `executeRequest`; `System.Text.Json` replaces the JSON-Schema example/field
  derivation in `schema.ts` (again, statically-typed deserialization has no
  exact analogue to the dynamic example synthesis in `schemaToExample`);
  `Windows.Storage` has no counterpart here since no given source persists
  data locally; `Task`/`async`/`await` replace the Promise-based flow;
  `ObservableCollection<T>` plus `INotifyPropertyChanged` replace the
  `rows`/`loading`/`fetching` state that `useCrudResource` exposes to a React
  render; a WinUI 3 port would need its own out-of-order-response guard
  (e.g. a monotonically increasing request-token field checked before
  applying a completed request's result) since `HttpClient` provides no
  built-in equivalent to `listSeq`.
- **Python (not in source)**: `httpx` (or `requests`) replaces
  `buildRequest`/`executeRequest`; `dataclasses` or `pydantic` models replace
  the JSON-Schema example/field derivation; there is no direct Python
  analogue to the React-hook state machine in `useCrudResource` since Python
  is not paired with a UI render loop in this codebase — a port would need to
  re-derive the `loading`/`fetching` distinction against whatever calling
  convention it adopts (a callback, an async generator, or similar).

## Design Decisions

### Client-side exposure gate is presentation-only

**Decision**: `canReadTable`/`canWriteTable`/`readableTables` in `exposure.ts`
are documented and implemented as presentation-only filters; they are never
treated as the authorization boundary.

**Rationale**: The server independently re-checks every request regardless
of what the client renders, so duplicating that enforcement client-side would
create a second source of truth that could drift from the real one.

**Approved**: pending

### Deliberate duplication of the shiki singleton

**Decision**: `highlight.ts` maintains its own module-level `highlighterPromise`
cache rather than sharing `@agenticdevelopertoolkit/markdown`'s existing shiki
singleton.

**Rationale**: The source's own doc comment states this is a deliberate,
acknowledged non-DRY choice rather than an oversight, avoiding a cross-package
coupling between `api-explorer` and the markdown package's internal caching
lifecycle.

**Approved**: pending

### Server-only vs client-only barrel split

**Decision**: `server.ts` (no `'use client'`) and `index.ts` (`'use client'`)
are kept as two separate entry points, with `index.ts` deliberately excluding
`getEndpoint`/`API_ENDPOINTS`.

**Rationale**: This prevents the large generated endpoint metadata map from
being pulled into the initial client bundle of any consumer that only needs a
button component, while still letting server-rendered pages reach the full
metadata.

**Approved**: pending

### Package-path imports to share module-level cache state

**Decision**: `server.ts` imports `allTags`, `endpointsForTag`, `getEndpoint`,
and `endpointKey` via the package path
(`@agentic-toolkit/api-explorer/lib/getEndpoint`) rather than a relative
import.

**Rationale**: The server entry and the client barrel are two separate build
chunk graphs; importing via the package path ensures both resolve to the same
module instance and therefore the same cached `_byTag`/`_tags` state, instead
of each accidentally forking its own copy of the cache.

**Approved**: pending

### Non-live token placeholder in generated snippets

**Decision**: `snippets.ts` always substitutes `TOKEN_PLACEHOLDER`
(`'YOUR_TOKEN'`) for any real bearer token in a generated cURL/JavaScript
snippet.

**Rationale**: A generated snippet is commonly copied to the clipboard or
pasted into a shared document; embedding a live token there would be a
credential leak vector, so the source trades away snippet convenience
(the caller must substitute a real token before running it) for that safety.

**Approved**: pending

## Compliance

| Check | Status | Notes |
|---|---|---|
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | `exposure.ts`'s gate is documented and implemented as presentation-only; the source's own doc comment states the server independently re-checks every request. |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | partial | `buildRequest` issues only same-origin `/api` requests and never constructs an absolute URL, so transport (TLS) is inherited from the hosting page rather than configured or enforced by this source. |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | Not applicable: not implemented here | Token issuance, refresh, and rotation are owned by `@agentic-toolkit/auth`'s `authedFetch`; the given sources only consume an already-valid token (`buildRequest`'s optional `token` parameter, or `authedRequest`/`authedJson` inside `useCrudResource`). |
| [secure-data-storage](agenticdevelopercookbook://compliance/privacy-and-data#secure-data-storage) | Not applicable: not implemented here | None of the given sources persist a token, credential, or PII to any local or remote store. |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | `executeRequest` has no recovery path for a network-level (as opposed to HTTP-status) failure; it rejects and the caller only reports the message — see `network-failure-propagation`. |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | Neither `buildRequest` nor `executeRequest` configures a timeout or `AbortController` — see `request-timeout`. |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | No retry logic exists anywhere in `buildRequest.ts`/`executeRequest`; the one retry-on-401 that exists in this codebase lives in the auth package's `authedFetch`, outside this recipe's given sources. |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | `executeRequest` normalizes every HTTP status into a uniform `ApiResult`; `tone.ts` gives a documented, tested status/method-to-tone mapping; `useCrudResource` propagates a mutation failure to its caller rather than swallowing it. |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | `useCrudResource`'s `listSeq` guard rejects a stale, out-of-order list response; `slug.ts` throws loudly on a genuine slug collision rather than silently aliasing two endpoints. |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | `tone.ts`, `exposure.ts`, `editability.ts`, `edits.ts`, `useCrudResource.ts`, and `useExitGuardChannel.ts` each have a sibling `__tests__` file with meaningful assertions; `buildRequest.ts`, `getEndpoint.ts`, `highlight.ts`, `schema.ts`, `slug.ts`, `snippets.ts`, and `types.ts` have no test file found in the repository. |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Most paths handle errors explicitly (`executeRequest`'s status normalization, `useCrudResource`'s `error` state, `exposure.ts`'s fail-closed default); `executeRequest`'s unguarded `fetch()` call is the one path where a network failure is not handled at all. |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | All seventeen given files are pure logic or headless hooks with no JSX and no DOM access; the `server.ts`/`index.ts` split further separates server-only from client-only concerns. |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | `snippets.ts`'s `TOKEN_PLACEHOLDER` and `slug.ts`'s collision message are hardcoded, English-only strings never externalized to a localization resource — see Localization. |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, documenting the shared headless logic of `@agentic-toolkit/api-explorer` and `@agentic-toolkit/crud`; records `executeRequest`'s network-failure propagation and absent request timeout. |
