---
id: ab36ce5f-4624-4097-bb66-a339dfecc4c9
title: Status Server Paths
domain: agentictoolkit://recipes/status-server-paths
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Fourteen hand-written OpenAPI path/schema modules documenting the status backend's REST surface, assembled and drift-checked against the live routes.
platforms:
- typescript
- web
tags:
- server
- openapi
- api
- docs
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/api-design
- agenticdevelopercookbook://guidelines/implementing/networking/error-responses
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related:
- agentictoolkit://recipes/status-server-auth
- agentictoolkit://recipes/status-server-board
- agentictoolkit://recipes/status-server-config
- agentictoolkit://recipes/status-server-middleware
- agentictoolkit://recipes/status-server-monitor-types
- agentictoolkit://recipes/status-server-monitor-live-types
- agentictoolkit://recipes/status-server-monitor-uptime
- agentictoolkit://recipes/status-server-fetchers
references:
- packages/web/packages/status-server/src/openapi/shared.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/build.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/route-key.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/activity.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/auth.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/autoConfigure.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/badge.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/board.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/config.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/device.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/fleet.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/hooks.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/stream.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/telemetry.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/tokens.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/users.ts (agentictoolkit)
- packages/web/packages/status-server/test/openapi.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/openapi-exclusions.ts (agentictoolkit)
- packages/web/packages/status-server/tools/dump-openapi.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Paths

## Overview

This is the status backend's OpenAPI documentation layer: fourteen modules under
`src/openapi/paths/` (`activity`, `auth`, `autoConfigure`, `badge`, `board`,
`config`, `device`, `fleet`, `hooks`, `reads`, `stream`, `telemetry`, `tokens`,
`users`), each documenting one plain-Hono route file's operations as OpenAPI 3.1
path items and, where it introduces a reusable shape, named component schemas.
`shared.ts` supplies the vocabulary every module builds with (`BEARER`, `jsonBody`,
`ref`, `errors`, `okJson`, `okFlag`, `pathParam`, `queryParam`, `zodJson`), and
`route-key.ts`'s `normHonoPath` normalizes a Hono route pattern into the same path
key form these modules use. `build.ts`'s `buildOpenApiSpec` merges the fourteen
modules' `Paths`/`Schemas` exports with the app's five natively `.openapi()`-
registered routes (`/health`, `/version`, `/public/status-summary`, the merged
`/cron/*` pair) into the document served at `GET /doc`. `test/openapi.test.ts` is
this component's drift guard: it fails the build the moment a route `createApp()`
registers goes undocumented (unless listed in `test/openapi-exclusions.ts`'s
`PERMANENTLY_UNDOCUMENTED`), the moment a documented path stops matching a real
route, or the moment the committed `openapi.json` (written by `pnpm openapi:dump` /
`tools/dump-openapi.ts`) drifts from a fresh build. This recipe treats the fourteen
modules, `shared.ts`, and `route-key.ts` as one component: the contract that keeps
the status backend's served API documentation honest about its actual routes.

## Behavioral Requirements

- **paths-export**: Each of the 14 modules MUST export a `<name>Paths: Paths` object (`Record<string, unknown>`, from `shared.ts`) keyed by OpenAPI path-template strings, as its route file's documented operations.
- **schemas-export-when-introduced**: A module that introduces a response or request shape reused via `ref(name)` MUST also export a `<name>Schemas: Schemas` object; `activity.ts`, `autoConfigure.ts`, `badge.ts`, `device.ts`, `hooks.ts`, `stream.ts`, and `users.ts` introduce no schema of their own and export no `Schemas` object.
- **path-key-template-form**: Every key of a `Paths` object MUST be the path-template form of its Hono route (`/config/sites/{id}`, not `/config/sites/:id`), matching the form `normHonoPath` produces from the route actually registered by `createApp()`.
- **operation-required-fields**: Every HTTP-method entry inside a path item MUST include `tags`, `summary`, and `responses`.
- **bearer-scheme-post-seam**: An operation whose route is mounted after the app-wide `requireAuth` seam MUST declare `security: BEARER`.
- **bearer-scheme-pre-seam-omitted**: An operation whose route is mounted before the `requireAuth` seam (`/auth/signup`, `/auth/login`, `/auth/logout`, `/auth/github/start`, `/auth/github/callback`, `/auth/device`, `/auth/device/token`, `/hooks/vercel`, `/hooks/railway`) MUST NOT declare `security`.
- **provider-webhook-security-comment**: `hooks.ts`'s two operations MUST omit `security` because the caller they authenticate is the deploy PROVIDER (a Vercel request signature, or Railway's shared secret via `?token=`/`x-webhook-secret`), not an app session or bearer token — a fact the module states in its header comment rather than in the OpenAPI `security` field, since neither scheme is a bearer token.
- **admin-gated-403**: An operation gated by `requireAdmin` (every operation in `config.ts` and `users.ts`; `/board/reconcile`; `/auto-configure`; `POST /tokens`; `/auth/device/approve`; `/auth/device/deny`) MUST declare `403` in its `errors(...)` list alongside `401`.
- **request-body-from-route-zod**: A documented request body for an operation whose route validates input with a zod schema (`signupBody`, `loginBody`, `autoConfigureBody`, `siteGroupInsert`/`Patch`, `monitoredSiteInsert`/`Patch`, `monitoredEndpointInsert`/`Patch`, `deployIntegrationInsert`/`Patch`, `ignoredProjectInsert`, `peerInsert`/`Patch`, `createSchema`, `roleBody`, `requestSchema`, `tokenSchema`, `userCodeSchema`) MUST convert that same imported schema through `zodJson()` rather than a hand-written JSON Schema literal.
- **success-envelope-helpers**: A documented JSON success response MUST be constructed with `okJson`, `okFlag`, or `jsonBody`, so its shape is always `{ description, content: { 'application/json': { schema } } }`.
- **error-envelope-helper**: A documented failure code MUST be added through `errors(...codes)`, resolving to the shared `errorResponse` (`{ description: 'Error', content: { 'application/json': { schema: ref('Error') } } }`), with the sole exception of `/live/check`'s `503` (see no-scheduler-response-shape and Design Decisions).
- **schema-single-owner**: A named component schema referenced elsewhere via `ref(name)` MUST be declared in exactly one module's `Schemas` export; `ActivityRow` is declared once in `board.ts`'s `boardSchemas` and reused by `activity.ts`'s `rows` field through `ref('ActivityRow')`, never redeclared.
- **module-registration**: Every `<name>Paths`/`<name>Schemas` pair MUST appear exactly once in the `MODULES` array in `build.ts`; a module omitted from `MODULES` contributes nothing to the assembled document regardless of what it exports.
- **hand-written-yields-to-generated**: `buildOpenApiSpec` MUST let the app's native `.openapi()`-generated `paths` and `components.schemas` win over every hand-written module's entries on a key collision, by spreading the generated document's `doc.paths`/`doc.components.schemas` after `HAND_WRITTEN_PATHS`/`HAND_WRITTEN_SCHEMAS`.
- **security-scheme-fixed**: `buildOpenApiSpec` MUST set `components.securitySchemes.bearerAuth` to `{ type: 'http', scheme: 'bearer' }` unconditionally, spread after whatever `doc.components.securitySchemes` the generated document already supplies, so a bearer scheme always exists and is never displaced.
- **zod-json-fallback**: `zodJson` MUST catch any exception `z.toJSONSchema` throws and return `{ type: 'object', additionalProperties: true }` in its place, rather than letting the exception propagate.
- **query-params-string-typed**: `queryParam` MUST document every query parameter's `schema` as `{ type: 'string' }`, regardless of the parameter's actual runtime type at the handler (`hours`, `days`, `buckets`, and `limit` are numeric; `fresh` is boolean-like) — every one of `reads.ts`'s numeric or boolean query parameters is documented as `type: string`.
- **peer-token-redaction**: `config.ts`'s `PeerRow` schema MUST be built from `peerInsert.omit({ token: true })`, never the raw `peerInsert`, and MUST add a `hasToken: boolean` field in its place; the response schema for `/config/peers` and `/config/peers/{id}` MUST NOT declare a `token` property.
- **token-value-once**: `POST /tokens`'s `201` response MUST be the only tokens-module response whose schema includes the raw secret (`allOf: [ApiTokenMeta, { token: string }]`); `GET /tokens`'s `200` response MUST document `ApiTokenMeta[]`, which has no `token` property.
- **activity-cursor-pair-documented**: `GET /activity`'s parameters MUST list `before` and `beforeId` as two independent, non-required query parameters, and its `description` MUST state the pair contract in prose (both required together, a lone half is a `400`, an empty `beforeId` alongside a present `before` is the server's own pagination-stall cursor), since an OpenAPI parameter object cannot express a two-field co-requirement.
- **reconcile-side-effect-documented**: `POST /board/reconcile`'s `description` MUST state that the call can page on-call (opening or resolving a ledger row queues an alert this endpoint flushes), not just that it mutates the ledger.
- **content-type-svg-badge**: `GET /status/badge.svg`'s `200` response MUST declare `content: { 'image/svg+xml': { schema: { type: 'string' } } }`, not a JSON envelope.
- **content-type-sse-stream**: `GET /live/stream`'s `200` response MUST declare `content: { 'text/event-stream': { schema: { type: 'string' } } }`, not a JSON envelope.
- **no-scheduler-response-shape**: `/live/check`'s documented `503` response MUST use the literal schema `{ ok: false, ran: false, reason: 'no scheduler' }`, not the shared `Error` schema that every other documented failure code in this component uses (see Design Decisions).
- **module-purity**: Every `*Paths`/`*Schemas` export MUST be a side-effect-free object literal fully constructed at module-evaluation time; none of the 14 modules performs I/O, reads a request, or depends on any value not available at import time.
- **drift-guard-exhaustive**: Every route `createApp()` registers (`app.routes`, excluding the `ALL`-method middleware entries) MUST resolve to a documented path+method in the assembled `spec.paths`, or MUST be listed in `test/openapi-exclusions.ts`'s `PERMANENTLY_UNDOCUMENTED` set; `test/openapi.test.ts` fails the moment a route satisfies neither, with no backlog exemption.
- **no-phantom-documented-routes**: Every path+method documented in the assembled `spec.paths` MUST correspond to a route `createApp()` actually registers; `test/openapi.test.ts` fails on a documented path with no matching registered route.
- **committed-spec-pinned**: The repository's committed `openapi.json` MUST equal a fresh `buildOpenApiSpec(createApp({ storage, config, auth }), config.appVersion)` call (built with no scheduler, `info.version` normalized to `'0.0.0'` for the comparison); `test/openapi.test.ts`'s third assertion enforces this, and the file is regenerated by `pnpm openapi:dump` (`tools/dump-openapi.ts`).
- **no-persistence**: This component MUST NOT read or write storage, a database, or a file itself; it returns static object literals describing routes whose actual handlers, storage access, and auth enforcement live in `src/routes/*`, `src/storage/*`, and `src/middleware/*`.

## Appearance

Not applicable — this is a server-side OpenAPI document builder, not a visual component.

## States

Not applicable — this is a server-side OpenAPI document builder, not a visual component; its module-loading and assembly steps are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side OpenAPI document builder, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-paths-001 | drift-guard-exhaustive | Fresh `spec = buildOpenApiSpec(app, version)` built from `createApp()` with every route mounted | Every entry of `registered` (built from `app.routes`) is present in `documented` or in `PERMANENTLY_UNDOCUMENTED` — `openapi.test.ts` › "every registered route is documented or permanently excluded (no backlog)" |
| status-server-paths-002 | no-phantom-documented-routes | Same `spec` | Every entry of `documented` (built from `spec.paths`) is present in `registered` — same file › "documents no phantom routes" |
| status-server-paths-003 | security-scheme-fixed | `spec.components.securitySchemes.bearerAuth` and `spec.openapi` | `scheme === 'bearer'` and `openapi === '3.1.0'` — same file › "is OpenAPI 3.1 with bearer security" |
| status-server-paths-004 | committed-spec-pinned | `buildOpenApiSpec(createApp({ storage, config, auth }), config.appVersion)` built with no scheduler, versus the committed `openapi.json`, both with `info.version` normalized to `'0.0.0'` | Deep-equal — same file › "the committed openapi.json matches a fresh build" |
| status-server-paths-005 | activity-cursor-pair-documented, bearer-scheme-post-seam | `activityPaths['/activity'].get` | `parameters` includes `before`, `beforeId` (both non-required), and `limit`; `security` is `BEARER`; `responses` has `200` (`rows`, `nextCursor`) and the codes from `errors(400, 401)` |
| status-server-paths-006 | provider-webhook-security-comment, success-envelope-helpers | `hooksPaths['/hooks/vercel'].post` and `hooksPaths['/hooks/railway'].post` | Neither declares a `security` key; both `responses[200]` equal `okIgnored` (`{ ok, id?, ignored? }`) and both declare `errors(401, 503)` |
| status-server-paths-007 | peer-token-redaction | `configSchemas.PeerRow` | Its `allOf` properties include `hasToken: { type: 'boolean' }` and contain no `token` property anywhere in the merged shape |
| status-server-paths-008 | token-value-once | `tokensPaths['/tokens'].post.responses[201]` versus `tokensPaths['/tokens'].get.responses[200]` | The `201` schema's `allOf` includes `{ token: { type: 'string' } }`; the `200` schema is `{ type: 'array', items: ref('ApiTokenMeta') }`, which has no `token` property |
| status-server-paths-009 | content-type-svg-badge | `badgePaths['/status/badge.svg'].get.responses[200]` | `content` key is exactly `image/svg+xml` with `schema: { type: 'string' }` |
| status-server-paths-010 | no-scheduler-response-shape | `streamPaths['/live/check'].post.responses[503]` | Schema requires `['ok', 'ran', 'reason']` with `ok` enum `[false]`, `ran` enum `[false]`, `reason` enum `['no scheduler']` — not `ref('Error')` |
| status-server-paths-011 | admin-gated-403 | `boardPaths['/board/reconcile'].post.responses` | Includes both `401` and `403` (from `errors(401, 403)`) |
| status-server-paths-012 | schema-single-owner | `activityPaths['/activity'].get.responses[200]`'s `rows` field | `{ type: 'array', items: ref('ActivityRow') }`; `ActivityRow` is declared only in `boardSchemas` — `activity.ts` exports no `Schemas` of its own |

## Edge Cases

- **Null and empty input**: `zodJson(schema)` receiving a zod schema `z.toJSONSchema` cannot convert MUST NOT throw; the fallback `{ type: 'object', additionalProperties: true }` MUST be returned in its place. None of the 14 modules' own imported zod schemas currently exercises this branch — every route zod body documented here is a plain JSON shape — so it is defensive-only, per `shared.ts`'s own comment, not a path any current operation reaches.
- **Boundary values**: `errors()` called with zero codes MUST return `{}` (`Object.fromEntries` of an empty array), documenting no failure code at all; no module in this set calls it with zero arguments. A route whose normalized key (`normHonoPath`) differs from a `PERMANENTLY_UNDOCUMENTED` entry by even a trailing slash or a case difference MUST be treated by the drift guard as a genuinely undocumented route, not a match, since the comparison is an exact string match.
- **Concurrent access**: Not applicable — every `*Paths`/`*Schemas` export is a `const` object literal fully built once, synchronously, at module-import time by a single-threaded JS module loader; there is no mutable shared state and no request-scoped code path anywhere in the 14 modules for two callers to race over.
- **Error states — module left out of the registry**: a module accidentally omitted from the `MODULES` array in `build.ts` documents nothing at build time and raises no error; the omission is caught only the next time `test/openapi.test.ts` runs its undocumented-route assertion.
- **ref-integrity**: `ref(name)` builds its `$ref` string from its argument without checking it against `components.schemas`, and neither `buildOpenApiSpec` nor `test/openapi.test.ts` checks that every `$ref` resolves. A misspelled `ref()` argument produces a dangling reference in the published spec, and no test catches it.
- **Offline / disconnected state**: Not applicable — none of the 14 modules or `shared.ts`'s helpers makes a network call, a storage call, or any I/O; the entire component is pure, synchronous document construction from data already available at import time, so there is no connectivity state for it to lose.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app` | `OpenAPIHono<any>` (Hono) | Required, caller-supplied | The fully-mounted app instance `buildOpenApiSpec` reads `app.getOpenAPI31Document()` from, and (in `test/openapi.test.ts`) `app.routes` from; every route must already be registered before this call, since nothing here re-checks later. |
| `version` | `string` | Required, caller-supplied | Written into the assembled document's `info.version`; the tracked `openapi.json` normalizes this to `'0.0.0'` before comparison so a version bump alone never fails the drift guard's snapshot check. |
| `PERMANENTLY_UNDOCUMENTED` | `Set<string>` (`test/openapi-exclusions.ts`) | `GET /`, `GET /doc`, `GET /mcp`, `POST /mcp`, `DELETE /mcp` | The only allowed exceptions to "every registered route is documented"; adding an entry here is the one way to leave a route out of the OpenAPI surface without failing the test. |

## Deep Linking

Not applicable: none of these 14 modules defines an application URL scheme or a mobile/web deep-link target; they document HTTP API paths on the status backend's own origin, consumed by API clients and Swagger-style tooling, not by a deep-link handler.

## Localization

Every `summary`/`description` string across the 14 modules (for example `authPaths['/auth/signup'].post.summary`, or `activityPaths['/activity'].get.description`) is a hardcoded English literal aimed at a developer reading the generated API documentation; none of these modules reads a string catalog, an i18n bundle, or an `Accept-Language` header, and the assembled document carries no locale dimension at all. Per this recipe's authoring rules, a hardcoded developer-facing string is a fact worth recording, not a gap to excuse with a blanket "Not applicable":

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — doc summary | `Create a status account (starts pending until an admin promotes it)` | `authPaths['/auth/signup'].post.summary` |
| n/a — doc description | `The cursor is the (before, beforeId) PAIR because a deployment's build and deploy rows share a timestamp...` | `activityPaths['/activity'].get.description` |
| n/a — doc summary | `Requirement B: write the board into the ledger — opens, updates and resolves rows (can alert)` | `boardPaths['/board/reconcile'].post.summary` |

## Accessibility Options

Not applicable: these 14 modules have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color; they emit a JSON document, not a rendered surface.

## Feature Flags

Not applicable: none of the 14 modules or `shared.ts`'s helpers consults a feature-flag system; every operation and schema is a fixed literal.

## Analytics

Not applicable: none of the 14 modules emits an analytics or telemetry event of its own; `telemetry.ts` documents endpoints that READ pre-aggregated `ErrorDTO`/`AnalyticsMetricDTO` rows computed elsewhere (`src/telemetry/*`) — it does not produce analytics data itself.

## Privacy

- **Data collected**: this component collects nothing itself; it documents the shapes of data other modules collect and expose, most notably `peerInsert`'s raw fleet-peer `token`, the API-token secret minted by `POST /tokens`, and the GitHub OAuth `code`/`state` query parameters on `/auth/github/callback`.
- **Storage**: this component performs no storage of its own; it only declares which persisted-row schemas (`PeerRow`, `ApiTokenMeta`) are safe to return, by construction excluding the raw secret from every response schema except the one-time `POST /tokens` `201` body.
- **Transmission**: the documented request schemas accept the raw `peerInsert.token` and the OAuth `code` on write; the documented response schemas never echo a raw secret back except that single `201` create response — every other read of a peer or a token is redacted (`hasToken: boolean`, or `ApiTokenMeta` with no `token` field at all).
- **Retention**: this component documents the fields that carry a secret's lifecycle (`ApiTokenMeta.expiresAt`, `ApiTokenMeta.revokedAt`, and `DELETE /tokens/{id}`'s revoke operation) without implementing any of that retention itself — actual storage and expiry enforcement live in the routes and storage modules this recipe's `related` field points at.

## Logging

Subsystem: n/a (status backend) | Category: n/a

| Event | Level | Message |
|-------|-------|---------|
| — | — | No logging calls exist anywhere in these 14 modules or in `shared.ts`; the entire component is declarative object construction with no observability surface of its own. |

## Platform Notes

- **React/Web** (source platform): the 14 modules live under `packages/web/packages/status-server/src/openapi/paths/`, built on `@hono/zod-openapi`'s `OpenAPIHono` (for the native `.openapi()` routes merged in by `build.ts`) plus zod's own `z.toJSONSchema` (`shared.ts`'s `zodJson`) — no separate OpenAPI-authoring library is used; every path/schema fragment is a plain TypeScript object literal typed against the local `Paths`/`Schemas` aliases.
- **SwiftUI**: an Apple client consumes this documented surface through a generated or hand-written `URLSession`-based API client — it is not a re-implementation of the doc builder. A Swift port of the DOCUMENT-GENERATION pattern itself, for a Vapor backend, would model each `<name>Paths`/`<name>Schemas` module as an `OpenAPIKit` `OpenAPI.PathItem`/`JSONSchema` map, merged the same way `build.ts` does with `merging(_:uniquingKeysWith:)`.
- **Compose**: an Android client is likewise a consumer, calling with Retrofit/OkHttp against the generated spec. A Kotlin backend re-implementation of this pattern, on Ktor, would model each module as a `Paths`/`Components.Schemas` fragment assembled through Ktor's `install(OpenApi) { ... }` DSL or a hand-rolled map merge mirroring `MODULES`.
- **AppKit / UIKit**: the same client relationship as SwiftUI applies — there is no server-side doc builder to port; an app-side client generated from `openapi.json` (for example via `swift-openapi-generator`) is the natural consumer of exactly the document this component assembles.
- **WinUI 3**: a WinUI 3 client is a consumer too — a generated C# client (NSwag, or a `Microsoft.OpenApi`-based codegen) reads the same `openapi.json`, calls with `HttpClient`, and binds results through `ObservableCollection<T>`/`INotifyPropertyChanged`. If a future product needed to reimplement this exact DOCUMENT-BUILDING pattern on a .NET backend (ASP.NET Core Minimal API), each `<name>Paths` module maps to a set of `OpenApiPathItem` entries built with `Microsoft.OpenApi.Models` and merged into `OpenApiDocument.Paths` the same way `Object.assign` merges `HAND_WRITTEN_PATHS` here; a `<name>Schemas` module maps to entries added to `OpenApiDocument.Components.Schemas`, with `System.Text.Json`'s `JsonSchemaExporter` (or NJsonSchema) taking the place of `zodJson`'s zod-to-JSON-Schema conversion, and ASP.NET's own `AddEndpointsApiExplorer`/`AddSwaggerGen` taking the place of `getOpenAPI31Document()` for the natively-registered routes this component's hand-written modules deliberately never re-describe.

## Design Decisions

- **Decision**: let the app's native `.openapi()`-generated paths and schemas win over every hand-written module's entries on any path or schema-name collision.
  **Rationale**: `build.ts`'s own comment states this directly — the auto-generated entries win on any path/schema key collision because they are the source of truth for the routes they cover; the five natively-registered routes are already correctly documented by the framework from the route's own zod schemas, so a hand-written module documenting the same key would only be a manually-maintained duplicate that could drift.
  **Approved**: pending
- **Decision**: document `/live/check`'s `503` with a literal success-shaped schema (`{ ok: false, ran: false, reason: 'no scheduler' }`) instead of routing it through the shared `errors()` helper and the `Error` schema every other failure code in this component uses.
  **Rationale**: not stated in a source comment beyond the route's own summary ("503 without a scheduler"); the response body this route actually returns on that path is the same `{ ok, ran, reason }` shape as its `200`, just with fixed `false`/`no scheduler` values, so describing it with the generic `Error` schema would document a body the handler never sends — recorded here as the one deliberate divergence from this component's own `errors()` convention, not an oversight.
  **Approved**: pending
- **Decision**: document `DELETE /tokens/{id}` with a bare `204` (`description: 'Revoked'`, no body) while every other row-deleting mutation in this surface (`config.ts`'s five `DELETE` operations, `users.ts`'s `DELETE /users/{id}`) documents `200` with the shared `okFlag` (`{ ok: boolean }`) body.
  **Rationale**: not explained in a source comment; the two shapes are not interchangeable for a generated client — one has a body to parse, the other must not — so a port MUST preserve each operation's documented status code and body shape exactly rather than assuming one uniform delete convention across this surface.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [api-design-conventions](agenticdevelopercookbook://compliance/access-patterns#api-design-conventions) | passed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

`separation-of-concerns` passes: all 14 modules and `shared.ts` build a static
document; no module handles a real request, touches storage, or enforces auth —
those live one layer up in `src/routes/*`, `src/storage/*`, and `src/middleware/*`,
documented in the sibling recipes this one's `related` field points at.
`unit-test-coverage` is partial: `test/openapi.test.ts` exercises the ASSEMBLED
behavior with meaningful, specific assertions (the drift guard's two set
differences, the security-scheme shape, and the committed-`openapi.json`
snapshot), but no test targets `shared.ts`'s individual helpers directly —
`errors()` called with zero arguments, `zodJson`'s catch-fallback branch, and
`pathParam`/`queryParam`'s fixed shapes have no dedicated unit test of their own,
only indirect coverage through whichever operations happen to call them.
`explicit-error-handling` passes: the one place this component could swallow an
error, `zodJson`'s `try`/`catch`, converts the exception into an explicit,
documented fallback value instead of ignoring it or leaving it `undefined`.
`api-design-conventions` passes: `config.ts`'s `listCreate`/`patchDelete` helpers
give every resource collection the same GET-list/POST-create/PATCH-update/DELETE-
remove shape, `queryParam`/`pathParam`/`errors` keep parameter and error
documentation uniform across all 14 modules, and every path key is resource-
oriented and grouped by `tags`. `error-response-handling` is partial: every
failure code in this component resolves to one distinguishable, documented status
built through the shared `errors()` helper, with the acknowledged exceptions of
`/live/check`'s `503` and `DELETE /tokens/{id}`'s bare `204` diverging from the
`200`-plus-`okFlag` convention used elsewhere — real, traceable divergences
recorded in Design Decisions, not a uniform contract. `data-minimization` passes:
`PeerRow` and the `POST /tokens` response are the two places a secret could leak
into this documented surface, and both are constructed to minimize it — `PeerRow`
substitutes `hasToken: boolean` for the raw `peerInsert.token`, and only the
one-time `201` create response for a minted token includes the raw value at all.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
