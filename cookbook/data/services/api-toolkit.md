---
id: 7add8e4b-922e-4518-aa45-79bf56cdf8bc
title: API Toolkit
domain: agentictoolkit://cookbook/data/services/api-toolkit
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Same-origin request building, generated-endpoint lookup, schema-derived examples and field descriptions, and generic-CRUD headless logic for API browsing and data-table editing."
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
- agentictoolkit://cookbook/ui/crud/crud-table
- agentictoolkit://cookbook/ui/crud/crud-record-form
references: []
---

# API Toolkit

## Overview

This recipe is the headless, non-visual logic shared by two sibling features: an
API-exploration browser and a generic data-table (CRUD) editor. Neither feature
exports a single component named after this recipe; this is the umbrella
specification for their pure logic and headless state units — the parts with no
visual rendering — so that the request-building, endpoint-lookup,
schema-derivation, slugging, snippet-generation, and generic-CRUD contracts are
documented once instead of being re-derived by every UI recipe that consumes
them (the CRUD table, the CRUD record form, and any API browser or
endpoint-reference consumer).

The API-exploration logic builds and executes same-origin backend-for-frontend
(BFF) requests from generated endpoint metadata, derives cycle-safe
schema-driven examples and field descriptions, highlights code with a
dual-theme, lazily-cached syntax highlighter, projects endpoints to crawlable,
collision-checked URL slugs, generates request snippets (a command-line form
and a scripting form) with a deliberate non-live token placeholder, and maps
HTTP method/status to a fixed presentation "tone." A server-usable entry point
re-exports the non-interactive pieces; a separate client-facing entry point
deliberately excludes the large generated endpoint metadata so importing a
button component never pulls it into the initial bundle.

The CRUD logic derives per-column editability from a fixed precedence, tracks
staged, dirty, mergeable row edits, gates table visibility by a
presentation-only authorization tier, exposes the generated CRUD schema
allowlist, defines the shared CRUD metadata shapes, runs list/create/
update/remove against the same BFF layer through a headless state unit with an
out-of-order-response guard, bridges an imperative unsaved-changes guard into a
stable proxy object, and exposes the current viewer's admin capability and
readiness.

## Behavioral Requirements

### Request Building and Execution

- **request-base**: the fixed API base MUST be the fixed string `/api`; every
  built request MUST be same-origin relative to this base, never an absolute
  cross-origin URL.
- **path-substitution**: path substitution MUST replace each `{name}` path
  segment with the URL-encoded value from the supplied path values when
  present, and MUST leave a `{name}` segment visible, unencoded, in the
  resulting path when no matching value is supplied.
- **body-allowed**: the body-allowed check MUST return true only when the
  endpoint's method is one that accepts a body per its metadata; it MUST
  return false otherwise so the request builder never attaches a body to a
  body-less method.
- **request-headers**: the request builder MUST set `Content-Type:
  application/json` only when a body is actually attached, and MUST set
  `Authorization: Bearer <token>` only when a token argument is supplied;
  neither header MUST be present when its precondition is absent.
- **mutating-methods**: the mutating-method check MUST return true for every
  HTTP method except `GET`, `HEAD`, and `OPTIONS`, and MUST return false for
  those three.
- **response-normalization**: the request executor MUST resolve to a uniform
  result for every HTTP status code, `2xx` through `5xx` inclusive, and MUST
  record the elapsed wall-clock duration on that result; it MUST NOT throw for
  a non-2xx HTTP response.
- **network-failure-propagation**: the request executor MUST let a
  transport-level failure (offline, DNS failure, a cross-origin block) reject
  its promise rather than resolve to a normalized result; its "never throws"
  contract covers only non-2xx statuses. The endpoint detail view catches the
  rejection and shows its message (falling back to `'Request failed'`).
- **request-timeout**: neither the request builder nor the request executor
  attaches a timeout or a cancellation controller to the underlying request; a
  request that never resolves stays in flight until the browser gives up.

### Endpoint Lookup

- **endpoint-key**: the endpoint key MUST be derived from an endpoint's method
  and path such that endpoint lookup can find the same endpoint by that key.
- **tag-index-caching**: the tag-to-endpoints index MUST be built lazily, on
  first use, and MUST be reused on every subsequent call rather than being
  rebuilt.
- **tag-ordering**: the full tag list MUST be returned in sorted order.
- **endpoints-for-tag-ordering**: the endpoints-for-a-tag lookup MUST return
  that tag's endpoints sorted first by path, then by a fixed method ranking
  for endpoints sharing a path.

### Code Highlighting

- **highlighter-singleton**: the cached highlighter MUST be created at most
  once per process and MUST be reused by every subsequent highlight call
  rather than being re-initialized.
- **highlighter-dual-theme**: the cached highlighter MUST support both a
  light and a dark theme and the JSON, shell, and JavaScript languages.
- **highlighter-failure-recovery**: if highlighter initialization rejects, the
  cache MUST reset back to empty so a subsequent call retries initialization
  rather than being permanently disabled by one transient failure.
- **pretty-json-fallback**: the pretty-JSON fallback MUST return the original
  input text unchanged when parsing fails, and MUST return an empty string
  for blank input; it MUST NOT throw.

### Schema-Derived Examples and Field Descriptions

- **ref-resolution-scope**: reference resolution MUST resolve only local
  schema-component references; a reference outside that local scope MUST NOT
  be treated as resolved.
- **example-cycle-safety**: example derivation MUST thread a "seen" set
  through every recursive step so that a cyclic schema (a schema that refs
  itself, directly or transitively) terminates rather than recursing
  indefinitely.
- **example-precedence**: example derivation MUST resolve an example value by
  trying, in order: reference resolution, `anyOf`/`oneOf` variant selection,
  `allOf` merge, an explicit example, an explicit default, the first `enum`
  value, then a type-driven default — stopping at the first applicable step.
- **type-label-truncation**: the type label MUST append a `?` suffix for a
  nullable type, MUST render a union of variants, and MUST truncate an enum
  preview beyond its fourth value with `…` rather than listing every value.
- **field-description-depth**: field description MUST describe fields exactly
  one level deep (name, type, required, description) after type unwrapping
  has dereferenced a reference, array items, a null-union, and a merged
  `allOf`.

### Endpoint Slugging

- **slug-projection**: slug projection MUST strip `{param}` braces from every
  path segment and MUST append the method, lower-cased, as the final slug
  segment.
- **slug-collision-detection**: the lazily-built slug index MUST throw when
  two distinct endpoints project to the same slug, rather than silently
  letting the second endpoint alias or shadow the first.
- **slug-lookup-miss**: slug lookup MUST return nothing, not throw, when no
  endpoint maps to the given slug.

### Snippet Generation

- **snippet-token-placeholder**: every generated snippet MUST embed a fixed
  token placeholder (the literal string `YOUR_TOKEN`) in place of any real
  bearer token; a generated snippet MUST NOT embed a live, caller-supplied
  token.
- **snippet-body-inclusion**: the generated snippet's body text MUST include a
  request body only when the endpoint's metadata declares a request body and
  the supplied body, once trimmed, is non-empty.
- **curl-snippet-escaping**: the command-line snippet MUST single-quote an
  embedded JSON body and MUST shell-escape any single quote that occurs
  inside that body.

### Method and Status Tone Mapping

- **method-tone-mapping**: the method badge/dot class mapping MUST map each of
  `GET`, `POST`, `PUT`, `PATCH`, `DELETE` to that method's fixed badge/dot
  classes, and MUST fall back to the neutral class for any other method.
- **method-text-class-consistency**: the method text class MUST always equal
  the first space-delimited token of the method's badge class for every
  method, so the badge and the text-only rendering can never drift onto
  different palettes.
- **status-tone-mapping**: the status tone mapping MUST map `200`–`299` to
  the green tone, `400`–`499` to the orange tone, `500` and above to the red
  tone, and any other status to the muted tone.

### Server and Client Entry Points

- **server-entry-safe-for-server-use**: the server-usable entry point MUST
  NOT carry a marker that forces client-side rendering machinery, so it can
  be imported from server-only code without pulling client-bundling
  requirements with it.
- **client-barrel-excludes-metadata**: the client-facing entry point MUST NOT
  re-export endpoint lookup or the generated endpoint list; a component
  imported from the client-facing entry point MUST NOT bundle the generated
  endpoint metadata as a transitive dependency.
- **shared-cache-via-package-path**: the server-usable entry point MUST reach
  the tag index, endpoint-for-tag lookup, endpoint lookup, and endpoint key
  functions through a path that resolves to the same module instance as the
  client-facing entry point uses, so that the server entry and the client
  entry — two separate build chunk graphs — observe the same module-level
  cache instance rather than each forking its own copy.

### Column Editability

- **server-managed-lock**: a column marked server-managed MUST NOT be
  editable in any mode, regardless of any override.
- **override-precedence**: an editability override MUST take effect only for
  a non-relational, non-server-managed column; an override MUST NOT make a
  relational (primary-key or foreign-key-shaped) column, nor a
  server-managed column, editable.
- **relational-create-only**: a relational column (a primary-key member, an
  exact match against a known set of identifier field names, or a match
  against a fixed identifier-suffix pattern) MUST be editable only when the
  mode is create, never in edit mode.
- **create-only-lock-on-edit**: a column marked create-only MUST NOT be
  editable once the mode is edit.
- **default-editable**: a column that is not server-managed, not relational,
  and not locked by the create-only flag in edit mode MUST be editable by
  default.
- **hidden-columns**: the hidden-column check MUST return true only for a
  server-managed column.

### Row Edit Tracking

- **dirty-detection**: dirty detection MUST return true if and only if at
  least one key present in the edit set has a value that is strictly
  different from the same key's value in the baseline; because the edit set
  MUST carry only the columns that were actually changed, iterating its keys
  MUST be sufficient — dirty detection MUST NOT need to inspect any key absent
  from the edit set.
- **draft-merge-immutability**: draft merging MUST return a new object
  overlaying the edit set onto the baseline, and MUST NOT mutate either the
  baseline or the edit set.

### Table Visibility Gate

- **presentation-only-gate**: the read/write allowlist checks MUST be
  documented and treated as presentation-only; they MUST NOT be relied upon
  as the authorization boundary — the server MUST independently re-check
  every request regardless of what the client renders.
- **read-allowlist**: the read-allowlist check MUST return true for
  owner and catalog exposure for any viewer, and MUST return true for admin
  exposure only when the viewer is an admin.
- **write-allowlist**: the write-allowlist check MUST return true for owner
  exposure for any viewer, and MUST return true for catalog or admin exposure
  only when the viewer is an admin.
- **fail-closed-on-unknown-tier**: a table whose exposure tier is missing or
  unrecognized MUST be denied both read and write for a non-admin viewer; the
  readable-tables filter MUST exclude such a table from its filtered result
  for a non-admin viewer.
- **order-preserving-filter**: the readable-tables filter MUST preserve the
  input order of the tables it retains.

### Schema Allowlist

- **schema-allowlist-single-source**: the schema allowlist MUST be computed
  exactly once, at load time, from the generated table list, and MUST serve
  as the single source of truth consulted by both halves of the
  allowlist-to-feature lockstep check.

### CRUD Resource State

- **item-url-substitution**: the item URL builder MUST substitute each
  primary-key value, URL-encoded, into the item path to build the per-item
  URL.
- **row-key-derivation**: the row key MUST join the row's escaped
  primary-key values, and MUST return the empty string when a single-key row
  has no value for that key.
- **loading-vs-fetching**: "loading" MUST mean "nothing to show for the
  current list yet" and "fetching" MUST mean "a list call is currently open";
  the two MUST be able to diverge (e.g. a background re-list on an
  already-populated list has fetching true but loading false).
- **out-of-order-response-guard**: the state MUST track a sequence number per
  list call and MUST discard the result of any list response whose sequence
  number is not the latest issued, so a slow, stale response MUST NOT
  overwrite state written by a newer, faster response.
- **loaded-for-tracking**: the state MUST track which list identity's rows
  are currently on screen, and "loading" MUST be derived as "fetching is true
  and the currently-loaded list differs from the requested one" so switching
  to a not-yet-loaded list shows loading, while re-fetching an
  already-loaded list does not.
- **query-composition-order**: the list query string MUST place the
  scope-derived query segment before the filter query segment when both are
  present.
- **mutation-relist**: create, update, and remove MUST re-issue the list call
  after their underlying mutation succeeds; the raw create/update/remove
  mutators they call MUST NOT re-list on their own.
- **delete-uses-authed-request**: row removal MUST call the
  response-body-discarding authenticated request helper, not the
  JSON-parsing authenticated request helper, because the delete endpoint
  answers `204 No Content` and the JSON-parsing helper throws on a `204`.
- **mutation-error-not-hook-state**: a failure from create, update, or remove
  MUST propagate to the caller as a rejected promise, and MUST NOT be written
  into the state's own error field.

### Exit Guard Channel

- **stable-proxy-identity**: the exit-guard proxy returned while a guard is
  registered MUST be the same object identity across re-registrations (built
  once, with no dependency that would cause it to be rebuilt).
- **presence-is-the-dirty-signal**: the channel MUST expose the proxy
  (non-null) only while a guard is present, and MUST expose nothing once
  withdrawn; callers MUST treat the presence of a non-null guard, not merely
  a call to it, as part of the dirty signal.
- **proxy-reads-latest-guard**: the stable proxy's dirty check MUST read
  through to the most recently registered guard rather than closing over a
  stale one.

### Viewer State

- **standalone-default**: the viewer state MUST return the settled value
  "not an admin, ready" when no authentication provider is present, so the
  browser is usable standalone without ever reporting an unsettled/loading
  state.
- **admin-derivation**: when an authentication provider is present, the
  admin flag MUST be derived from an admin check against the current user
  and readiness MUST be derived from the negation of the provider's loading
  state — readiness MUST distinguish "settled" from "still loading," never
  conflating the two.

## Appearance

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component.

## States

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component. (Runtime
state machines — loading/fetching in the CRUD resource state, guard presence
in the exit guard channel, ready/isAdmin in the viewer state — are specified
above under Behavioral Requirements.)

## Accessibility

Not applicable — this is headless request-building, endpoint-lookup,
schema-derivation, and generic-CRUD logic, not a visual component.

## Conformance Test Vectors

| # | Input | Expected output/effect | Source |
|---|---|---|---|
| 1 | The method text class computed for each of GET/POST/PUT/PATCH/DELETE/TRACE | Equals the first token of that method's badge class for every method | Method and status tone mapping's test coverage |
| 2 | The method dot class computed for an unrecognized method (TRACE) | Falls back to the neutral dot class rather than throwing or returning nothing | Method and status tone mapping's test coverage |
| 3 | The read-allowlist check applied to an admin-exposure table for a non-admin viewer | False (admin-only table denied to a non-admin viewer) | Table visibility gate's test coverage |
| 4 | The write-allowlist check applied to a catalog-exposure table for a non-admin viewer | False (catalog is readable but not writable by a non-admin) | Table visibility gate's test coverage |
| 5 | The column editability check applied to a relational column with an override set for that column's name, in edit mode | False — an override cannot force a relational column editable outside create mode | Column editability's test coverage |
| 6 | Dirty detection applied with no edits, then applied with an edit typed back to the baseline value | False in both cases — no edits, and an edit typed back to the baseline value | Row edit tracking's test coverage |
| 7 | Row removal against an endpoint that answers `204 No Content` | Resolves via the response-body-discarding request helper; using the JSON-parsing helper on the same response would throw | CRUD resource state's test coverage, corroborated by the JSON helper's documented 204 behavior in the auth client recipe |
| 8 | Two list calls issued in quick succession where the first (older sequence number) resolves after the second (newer sequence number) | Only the newer response's rows are written to state; the stale, later-arriving response is discarded | CRUD resource state's test coverage |
| 9 | Slug projection applied to the endpoint `GET /users/{id}` | `'users-id-get'` — braces stripped, method lower-cased and appended | Endpoint slugging (no dedicated test coverage found) |
| 10 | The request builder invoked with no bearer token, versus the same call with a token supplied | No authorization header in the first case; an authorization header carrying the token is present in the second | Request building and execution (no dedicated test coverage found) |

## Edge Cases

- **Unfilled path parameter**: path substitution leaves an unmatched `{name}`
  segment visible, unencoded, in the built path rather than erroring or
  omitting the segment — a deliberate, documented rendering choice, not a
  gap.
- **Cyclic schema**: example derivation's "seen"-set threading guarantees
  termination on a schema that refs itself directly or transitively.
- **Slug collision**: two endpoints that would project to the same slug cause
  the lazily-built slug index to throw at build time rather than silently
  aliasing one endpoint's reference page onto another's.
- **External (non-local) reference**: reference resolution only resolves
  local schema-component references; a schema containing a reference outside
  that scope is not resolved and falls through example derivation's
  remaining precedence steps (this API's generated schemas are self-contained,
  so this scope limitation is a design decision — see Design Decisions — not
  a runtime failure mode).
- **Out-of-order network responses**: the CRUD resource state's sequence-number
  guard is the specified defense against a slow list response overwriting a
  newer one; a mutation (create/update/remove) has no equivalent sequence
  guard because those calls are not re-issued concurrently against the same
  resource by the state itself.
- **Concurrent access to the editability overrides**: this overrides object is
  empty by default and is intended as static, hand-populated configuration;
  production code never mutates it at runtime. Only test code mutates and
  restores it. Because the runtime is single-threaded, this is not a
  concurrency hazard in practice — it is a fact about the module's intended
  use, not an unresolved gap.
- **Network-level failure of a built request**: an offline/DNS/cross-origin
  failure rejects the request executor's promise instead of producing a
  normalized result (see network-failure-propagation); the caller turns it
  into an error message.
- **Hung request**: no timeout or cancellation bounds the request built by the
  request builder/executor (see request-timeout); a connection that never
  resolves keeps the request in flight.

## Configuration

- **The API base** (used by request building/execution and by the CRUD
  resource state) — fixed constant `/api`; not caller- or
  environment-configurable in the given source.
- **`token`** (an optional argument to the request builder) — optional,
  caller-supplied bearer token forwarded as `Authorization: Bearer <token>`.
- **The public API origin** (used by snippet generation) — fixed constant
  `https://api.agenticdeveloperhub.com` used only for generated snippet URLs,
  never for the same-origin requests the request builder itself issues.
- **The editability overrides** (used by column editability) — a
  module-level object callers may hand-populate (outside test code) to force
  a non-relational, non-server-managed column's editability; empty by
  default.
- **`meta` / `filter` / `scopeEcosystemId`** (arguments to the CRUD resource
  state) — `meta` (the table's metadata) is required; `filter` is an optional
  caller-supplied query object serialized into the list query; `scopeEcosystemId`
  is an optional caller-supplied scope value that precedes `filter` in the
  query string and rides every verb, not just the list call.
- **`isAdminViewer`** (an argument to the table visibility gate's checks) —
  caller-supplied boolean, typically sourced from the viewer state's admin
  flag.

## Deep Linking

Endpoint slugging exists specifically to make each API endpoint reachable by
a crawlable, collision-checked URL slug: slug projection projects an endpoint
to a slug (path segments with `{param}` braces stripped, plus the lower-cased
method appended), and slug lookup reverses that projection for routing,
returning nothing on a miss rather than throwing. This is the deep-linking
contract for the whole recipe; no other given source participates in deep
linking.

## Localization

None of the given sources externalize strings into a localization resource
system; the following are hardcoded, English-only strings that are facts
about the current implementation, not gaps:

- The fixed token placeholder (`'YOUR_TOKEN'`) is embedded verbatim, in
  English, in every generated command-line/scripting snippet.
- The slug index's collision message (`endpoint slug collision on
  "${slug}"...`) is a hardcoded English developer-facing error string.
- The CRUD resource state's reliance on an inherited hardcoded English error
  message for an unexpected `204` response (see Platform Notes) is inherited,
  not produced, by this recipe's own logic.

## Accessibility Options

Not applicable: none of the given sources render a visual or interactive
surface, so there is no contrast, motion, font-size, or other
accessibility-preference surface for this recipe to define.

## Feature Flags

Not applicable: no feature-flag check (a config-service call, or a
hand-rolled flag lookup) appears in any of the given sources. The
editability overrides are column-editability configuration, not a feature
flag.

## Analytics

Not applicable: none of the given sources emit an analytics/telemetry event
or call an analytics client.

## Privacy

- The request builder's token parameter is forwarded as an `Authorization`
  header and is never persisted, cached, or logged by any given source; the
  caller owns the token's lifecycle.
- Snippet generation deliberately substitutes the fixed token placeholder for
  any real token so that copying a generated snippet to the clipboard can
  never leak a live credential — a privacy-motivated design decision (see
  Design Decisions).
- The table visibility gate's tier check (read-allowlist/write-allowlist) is
  presentation data-minimization only: it narrows which tables the UI
  *offers* to a non-admin viewer, but it is explicitly documented as not a
  security or privacy boundary — the server independently decides what data
  is actually returned.
- None of the given sources persist personally identifiable information to
  local storage, a database, or any other durable store.

## Logging

Not applicable: none of the given sources call a logger or otherwise emit
diagnostic output.

## Platform Notes

- **Web (source platform)**: a fetch/promise-based HTTP call, a cancellation
  controller, and a query-string builder are the native browser primitives
  this recipe's source is written against; a syntax-highlighting library
  (loaded dynamically at first use) is the only third-party runtime
  dependency among the given sources, and its cached highlighter supports the
  `github-light`/`github-dark` themes and the `json`/`bash`/`javascript`
  languages. The server-usable entry point in source is a file with no
  client-rendering directive, so it can be imported from server-only code
  without pulling client-component bundling requirements with it; the
  client-facing entry point deliberately omits the endpoint-lookup functions
  and the generated endpoint metadata constant, and reaches the shared lookup
  functions via their package path rather than a relative path so both entry
  points observe the same module-level cache instance instead of each
  forking its own copy. The exit-guard proxy is built once via a
  memoization primitive with an empty dependency array so its object
  identity is stable across re-registrations. The viewer state's dependence
  on an optional context-based authentication provider (absent, it settles
  to signed-out defaults instead of an unsettled loading state), and the CRUD
  resource state's use of a response-body-discarding request helper and a
  JSON-parsing request helper from the auth client recipe for the actual
  network calls, are specific to this source's implementation in
  `@agentic-toolkit/api-explorer` and `@agentic-toolkit/crud`.
- **Apple (Swift, not in source)**: `URLSession` (with `URLRequest`) is the
  equivalent of the request builder/executor; `Codable` is the equivalent of
  the schema-driven example/field-description derivation (though Codable is
  compile-time-typed, so a dynamic schema-to-example projection has no direct
  one-to-one match); `Task`/`async`/`await` replace the promise-based flow; a
  stable `AnyObject` proxy under `@MainActor` would replace the exit guard
  channel's memoized proxy.
- **Android (Kotlin, not in source)**: `OkHttp` or `Retrofit` plus
  `kotlinx.serialization` (or Moshi) replace the request builder/executor and
  the schema-derived example/field logic respectively; Kotlin
  `Flow`/`StateFlow` replace the loading/fetching state pair exposed by the
  CRUD resource state; a `Mutex`-guarded sequence counter would replace the
  out-of-order-response guard.
- **WinUI 3 (Windows, not in source)**: `HttpClient` replaces the request
  builder/executor; `System.Text.Json` replaces the schema example/field
  derivation (again, statically-typed deserialization has no exact analogue
  to the dynamic example synthesis); `Windows.Storage` has no counterpart
  here since no given source persists data locally; `Task`/`async`/`await`
  replace the promise-based flow; `ObservableCollection<T>` plus
  `INotifyPropertyChanged` replace the rows/loading/fetching state that the
  CRUD resource state exposes to a render; a WinUI 3 port would need its own
  out-of-order-response guard (e.g. a monotonically increasing request-token
  field checked before applying a completed request's result) since
  `HttpClient` provides no built-in equivalent to the sequence guard.
- **Python (not in source)**: `httpx` (or `requests`) replaces the request
  builder/executor; `dataclasses` or `pydantic` models replace the
  schema-driven example/field derivation; there is no direct Python analogue
  to the state machine in the CRUD resource state since Python is not paired
  with a UI render loop in this codebase — a port would need to re-derive the
  loading/fetching distinction against whatever calling convention it adopts
  (a callback, an async generator, or similar).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/api-explorer/src/lib/buildRequest.ts` |
| web | `packages/web/packages/api-explorer/src/lib/getEndpoint.ts` |
| web | `packages/web/packages/api-explorer/src/lib/highlight.ts` |
| web | `packages/web/packages/api-explorer/src/lib/schema.ts` |
| web | `packages/web/packages/api-explorer/src/lib/slug.ts` |
| web | `packages/web/packages/api-explorer/src/lib/snippets.ts` |
| web | `packages/web/packages/api-explorer/src/lib/tone.ts` |
| web | `packages/web/packages/api-explorer/src/server.ts` |
| web | `packages/web/packages/api-explorer/src/types.ts` |
| web | `packages/web/packages/crud/src/editability.ts` |
| web | `packages/web/packages/crud/src/edits.ts` |
| web | `packages/web/packages/crud/src/exposure.ts` |
| web | `packages/web/packages/crud/src/schemas.ts` |
| web | `packages/web/packages/crud/src/types.ts` |
| web | `packages/web/packages/crud/src/useCrudResource.ts` |
| web | `packages/web/packages/crud/src/useExitGuardChannel.ts` |
| web | `packages/web/packages/crud/src/viewer.ts` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/services/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, documenting the shared headless logic of `@agentic-toolkit/api-explorer` and `@agentic-toolkit/crud`; records `executeRequest`'s network-failure propagation and absent request timeout. |
