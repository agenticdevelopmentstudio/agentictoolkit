---
id: 0679e232-f536-4d02-b3f0-592d52d44582
title: Status Server OpenAPI
domain: agentictoolkit://cookbook/status-server/openapi
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Three files that assemble the status backend's OpenAPI 3.1 document — merging
  fourteen hand-written route modules with the natively-generated auto-document, and
  the shared fragment builders both depend on.
platforms:
- typescript
- web
tags:
- openapi
- documentation
- pure-function
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/api-design
related:
- agentictoolkit://cookbook/status-server/auth
- agentictoolkit://cookbook/status-server/telemetry/fetchers
references:
- packages/web/packages/status-server/src/openapi/build.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/route-key.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/shared.ts (agentictoolkit)
- packages/web/packages/status-server/test/openapi.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/openapi-exclusions.ts (agentictoolkit)
- packages/web/packages/status-server/tools/dump-openapi.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server OpenAPI

## Overview

Three files under `src/openapi/` assemble the status backend's OpenAPI 3.1 document. `build.ts`'s `buildOpenApiSpec` takes the app's own natively-generated document (from `getOpenAPI31Document`, covering the handful of routes registered with Hono's `.openapi()`) and merges in fourteen hand-written `{paths, schemas?}` modules — one per plain-Hono route file — plus a fixed `Error` component schema and a forced `bearerAuth` security scheme. `shared.ts` is the small library of fragment builders (`jsonBody`, `ref`, `errorResponse`, `errors`, `okJson`, `okFlag`, `pathParam`, `queryParam`, `zodJson`, `BEARER`) every one of those fourteen hand-written modules composes its path-item objects from, so a documented request/response body is generated from the same zod schema the route handler validates against rather than hand-transcribed. `route-key.ts`'s `normHonoPath` normalizes a raw Hono route pattern (`:id` → `{id}`, collapsing double slashes, stripping a trailing slash) into the same key shape the hand-written modules already write by hand; none of this recipe's three files calls it internally — its one cited consumer is `test/openapi.test.ts`'s drift guard, which recomputes each registered route's key this way so it can be compared against `spec.paths`' keys without the two ever disagreeing on what a route's key is.

## Behavioral Requirements

### Spec Assembly (build.ts)

- **base-document-from-hono**: `buildOpenApiSpec(app, version)` MUST obtain the base document by calling `app.getOpenAPI31Document({ openapi: '3.1.0', info: { title: 'status-backend', version } })`, so the document's `openapi` field is always the literal `'3.1.0'` and `info.title` is always the literal `'status-backend'`.
- **module-list-is-documented-surface**: `MODULES` MUST list exactly one `{ paths, schemas? }` entry per plain-Hono route file that is not registered via `.openapi()`; per the source comment this list IS the documented surface for every such route, and its fourteen current entries are `readsPaths`, `boardPaths`, `activityPaths`, `configPaths`, `telemetryPaths`, `fleetPaths`, `usersPaths`, `authPaths`, `tokensPaths`, `devicePaths`, `streamPaths`, `badgePaths`, `autoConfigurePaths`, and `hooksPaths`.
- **native-routes-excluded-from-modules**: the five routes registered on `app` via Hono's `.openapi()` — `GET /health`, `GET /version`, `GET /public/status-summary`, `POST /cron/refresh`, and `POST /cron/maintenance`, per the source comment — MUST NOT appear as an entry in any `MODULES` module's `paths`.
- **hand-written-paths-merge**: `buildOpenApiSpec` MUST merge every `MODULES` entry's `paths` into one `HAND_WRITTEN_PATHS` map via `Object.assign({}, ...MODULES.map((m) => m.paths))`, so a path key present in more than one module keeps only the last-registered module's path-item object for that key.
- **hand-written-schemas-merge**: `buildOpenApiSpec` MUST merge every `MODULES` entry's `schemas` (defaulting to `{}` when a module supplies none, via `m.schemas ?? {}`) into one `HAND_WRITTEN_SCHEMAS` map the same way, with the same last-write-wins behavior on a colliding component-schema name.
- **auto-generated-paths-win-collision**: `buildOpenApiSpec` MUST assign `doc.paths` as `{ ...HAND_WRITTEN_PATHS, ...doc.paths }`, so an auto-generated (`.openapi()`-registered) path entry always overrides a hand-written entry sharing the same path key.
- **components-defaulted-when-absent**: `buildOpenApiSpec` MUST default `doc.components` to `{}` via `doc.components ?? doc.components`, before assigning `schemas` and `securitySchemes` onto it, so the assignment never throws when `getOpenAPI31Document` returns a document with no `components` key.
- **components-schemas-precedence**: `buildOpenApiSpec` MUST assign `doc.components.schemas` as `{ ...COMPONENT_SCHEMAS, ...HAND_WRITTEN_SCHEMAS, ...doc.components.schemas }`, so an auto-generated schema name overrides a hand-written schema of the same name, and a hand-written schema name overrides an entry from `COMPONENT_SCHEMAS`; names that do not collide across the three sources are all kept.
- **error-component-schema**: `COMPONENT_SCHEMAS` MUST define a component schema named `Error` whose shape is `{ type: 'object', properties: { error: { type: 'object', properties: { message: { type: 'string' }, code: { type: 'string' } } } } }`, with neither `message` nor `code` listed in a `required` array, unless a hand-written or auto-generated schema of the same name overrides it per components-schemas-precedence.
- **bearer-scheme-fixed**: `buildOpenApiSpec` MUST assign `doc.components.securitySchemes` as `{ ...doc.components.securitySchemes, bearerAuth: { type: 'http', scheme: 'bearer' } }`, so `bearerAuth` is always exactly this literal value regardless of what `getOpenAPI31Document` produced for that key, while every other key already present in the auto-generated `securitySchemes` is preserved.
- **build-return-type-unknown**: `buildOpenApiSpec` MUST declare its return type as `unknown`; a caller that needs to read the document's fields (as `test/openapi.test.ts` does) MUST cast the result itself before accessing them.
- **build-deterministic**: `buildOpenApiSpec(app, version)` MUST produce the same JSON document for the same registered routes and the same `version` argument on every call, with no internally-varying value (no timestamp, no random id); this is what lets `test/openapi.test.ts`'s "the committed openapi.json matches a fresh build" assertion compare a freshly-built document against the repo's checked-in `openapi.json` after normalizing only the caller-supplied `info.version`.

### Route-Key Normalization (route-key.ts)

- **param-token-conversion**: `normHonoPath` MUST replace every occurrence of a Hono path-parameter token of the form `:name` (`name` matching one or more letters, digits, or underscores) with the OpenAPI form `{name}`.
- **duplicate-slash-collapse**: `normHonoPath` MUST collapse any run of one or more consecutive slash characters, anywhere in the path, to a single slash.
- **trailing-slash-stripped**: `normHonoPath` MUST remove exactly one trailing slash from the input, except that when doing so leaves the empty string, `normHonoPath` MUST return the literal root path `/` instead (the `|| '/'` fallback).
- **route-key-pure**: `normHonoPath` MUST be a pure function of its `path` argument alone: the same input string always yields the same output string, with no side effect and no dependency on any prior call.

### Shared Fragment Builders (shared.ts)

- **bearer-security-requirement**: `BEARER` MUST be the fixed value `[{ bearerAuth: [] }]`, the OpenAPI security-requirement array a hand-written operation spreads into its own `security` field to require the `bearerAuth` scheme with no scopes.
- **json-body-wrapper**: `jsonBody(s)` MUST return `{ content: { 'application/json': { schema: s } } }` for any schema `s`, wrapping it as a JSON request or response body with no other content type offered.
- **schema-ref**: `ref(name)` MUST return `{ $ref: '#/components/schemas/' + name }` for the given component-schema name.
- **error-response-shape**: `errorResponse` MUST be the single fixed value `{ description: 'Error', ...jsonBody(ref('Error')) }` — a plain object literal, not a factory function — so every call site that spreads it into a `responses` map references the identical object.
- **errors-map-shares-error-response**: `errors(...codes)` MUST return a map from every supplied numeric status code to that same `errorResponse` object reference, via `Object.fromEntries(codes.map((c) => [c, errorResponse]))`, never a per-code copy.
- **ok-json-wrapper**: `okJson(description, schema)` MUST return `{ description, ...jsonBody(schema) }`.
- **ok-flag-shape**: `okFlag` MUST be the fixed value `okJson('Success', { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } } })`.
- **path-param-always-required-string**: `pathParam(name)` MUST return `{ name, in: 'path', required: true, schema: { type: 'string' } }` for any `name`; it MUST always set `required: true` and always type the schema as `'string'`, with no argument to vary either.
- **query-param-default-optional-string**: `queryParam(name, required)` MUST return `{ name, in: 'query', required, schema: { type: 'string' } }`, where `required` MUST default to `false` when the caller omits it, and the schema type MUST always be `'string'`.
- **zod-json-conversion**: `zodJson(schema)` MUST return `z.toJSONSchema(schema, { target: 'draft-2020-12' })` when that conversion succeeds, so the documented request or response body is generated from the same zod schema the route handler validates against rather than hand-transcribed separately.
- **zod-json-fallback-on-throw**: `zodJson(schema)` MUST catch any exception `z.toJSONSchema` throws for that `schema` and return `{ type: 'object', additionalProperties: true }` instead, making no logging call and re-throwing nothing; per the function's own doc comment this branch exists only for a zod type JSON Schema cannot represent (its own cited example is a raw `z.date()`), and every actual route body schema in this codebase is a plain JSON shape that does not exercise it, so the branch is documented as defensive only.

### Drift Coverage

- **path-collision-caught-by-drift-guard**: When two `MODULES` entries' `paths` collide on the same top-level path key, `Object.assign`'s last-write-wins behavior MUST silently drop every method the earlier module documented for that path from `HAND_WRITTEN_PATHS`; because `test/openapi.test.ts`'s "every registered route is documented or permanently excluded" assertion checks every method `createApp()` actually registers against `spec.paths`, such a drop MUST reliably fail that test the moment the app registers a route on the dropped method, so a real collision between two of the fourteen current modules cannot ship silently even though nothing in `build.ts` itself detects it at merge time.
- **schema-name-collision-unguarded**: `HAND_WRITTEN_SCHEMAS` merges the fourteen `MODULES` entries' `schemas` with `Object.assign`, so if two `paths/*.ts` modules ever export the same component-schema name, the later module's definition silently wins. No test in `test/openapi.test.ts` or elsewhere under `test/` compares component-schema names across modules the way the drift guard compares paths against `app.routes`; unique names are kept by convention alone. None of the fourteen modules' schema exports collide today.

## Appearance

Not applicable — this is a build-time OpenAPI document assembler and two supporting pure-function libraries, not a visual component.

## States

Not applicable — this is a build-time OpenAPI document assembler, not a visual component; it has no runtime state machine, only the one-shot, side-effect-free transformation `buildOpenApiSpec` performs on each call, captured under Behavioral Requirements.

## Accessibility

Not applicable — this is a build-time OpenAPI document assembler, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-openapi-001 | base-document-from-hono | `buildOpenApiSpec(app, '1.2.3')` where `app = createApp({ storage, scheduler, config, auth })` | `spec.openapi === '3.1.0'`; `spec.info` deep-equals `{ title: 'status-backend', version: '1.2.3' }` — `openapi.test.ts` › "is OpenAPI 3.1 with bearer security" (first assertion) |
| status-server-openapi-002 | bearer-scheme-fixed | Same `spec` as vector 001 | `spec.components.securitySchemes.bearerAuth` deep-equals `{ type: 'http', scheme: 'bearer' }` — same test, second assertion |
| status-server-openapi-003 | native-routes-excluded-from-modules, module-list-is-documented-surface | `buildOpenApiSpec(createApp({ storage, scheduler, config, auth }), version)` with a truthy `scheduler` stub, so `/cron/*` is mounted | `spec.paths` has entries for `/health`, `/version`, `/public/status-summary`, `/cron/refresh`, and `/cron/maintenance`, none of which is contributed by any of the fourteen `MODULES` entries — `openapi.test.ts`'s drift guard computes zero `phantom` and zero `undocumented` entries including these five |
| status-server-openapi-004 | hand-written-paths-merge | Every plain `app.get`/`post`/`patch`/`delete` route `createApp()` registers, e.g. `GET /tokens`, `POST /tokens`, `DELETE /tokens/{id}` | `spec.paths['/tokens'].get`, `.post`, and `spec.paths['/tokens/{id}'].delete` all exist, sourced from `tokensPaths` — `openapi.test.ts` › "every registered route is documented or permanently excluded" passes with an empty `undocumented` array |
| status-server-openapi-005 | auto-generated-paths-win-collision | `buildOpenApiSpec(stubApp, version)` where `stubApp.getOpenAPI31Document()` returns a document whose `paths` already contains `'/tokens': { get: { summary: 'AUTO' } }` (a fabricated collision with `tokensPaths`' hand-written `/tokens` `GET`) | `spec.paths['/tokens']` deep-equals exactly `{ get: { summary: 'AUTO' } }` — the auto-generated path-item object replaces the hand-written one wholesale for that key, including silently dropping the hand-written `POST /tokens` operation that the auto-generated path-item never defined |
| status-server-openapi-006 | components-defaulted-when-absent | `buildOpenApiSpec(stubApp, version)` where `stubApp.getOpenAPI31Document()` returns a document with no `components` key at all | Does not throw; the returned `spec.components` is an object containing `schemas` and `securitySchemes`, built from `COMPONENT_SCHEMAS`/`HAND_WRITTEN_SCHEMAS` and the forced `bearerAuth` entry |
| status-server-openapi-007 | components-schemas-precedence, hand-written-schemas-merge | `buildOpenApiSpec(createApp({ storage, scheduler, config, auth }), version).components.schemas` | Contains both `'ApiTokenMeta'` (from `tokensSchemas`, a `HAND_WRITTEN_SCHEMAS` entry) and `'Error'` (from `COMPONENT_SCHEMAS`, since no `MODULES` entry defines a schema named `'Error'`) — confirming the three-tier spread unions non-colliding names rather than only ever keeping one tier |
| status-server-openapi-008 | error-component-schema | Same `spec` as vector 007, `.components.schemas.Error` | Deep-equals `{ type: 'object', properties: { error: { type: 'object', properties: { message: { type: 'string' }, code: { type: 'string' } } } } }`; neither `message` nor `code` is listed in a `required` array |
| status-server-openapi-009 | build-return-type-unknown | `buildOpenApiSpec(app, version)` | The call's static return type is `unknown`; `test/openapi.test.ts` casts the result with `as { openapi: string; components: ...; paths: ... }` before reading any field, because the signature grants no field access without a cast |
| status-server-openapi-010 | build-deterministic | `buildOpenApiSpec(createApp({ storage, config, auth }), config.appVersion)` built once at module scope, and again inside a later test against a freshly constructed but equivalently-configured app | Both results, with `info.version` normalized to `'0.0.0'` in each, deep-equal the repo's committed `openapi.json` (also normalized) — `openapi.test.ts` › "the committed openapi.json matches a fresh build" |
| status-server-openapi-011 | param-token-conversion | `normHonoPath('/tokens/:id')` | Returns `'/tokens/{id}'` |
| status-server-openapi-012 | param-token-conversion | `normHonoPath('/deployments/:id/log')` | Returns `'/deployments/{id}/log'` — a param that is not the final path segment converts identically |
| status-server-openapi-013 | duplicate-slash-collapse | `normHonoPath('/tokens//id///log')` | Returns `'/tokens/id/log'` — every run of two or more slashes anywhere in the path collapses to one, regardless of run length or position |
| status-server-openapi-014 | trailing-slash-stripped | `normHonoPath('/tokens/')` | Returns `'/tokens'` |
| status-server-openapi-015 | trailing-slash-stripped | `normHonoPath('/')` | Returns `'/'` — stripping the sole trailing slash first yields the empty string, and the fallback restores the root path rather than returning an empty string |
| status-server-openapi-016 | route-key-pure | `normHonoPath('/health')` called, then `normHonoPath('/version')`, then `normHonoPath('/health')` again | Both calls on `'/health'` return the identical string `'/health'`; the intervening call on an unrelated path has no effect on either result |
| status-server-openapi-017 | bearer-security-requirement | `BEARER` | Deep-equals `[{ bearerAuth: [] }]` |
| status-server-openapi-018 | json-body-wrapper, schema-ref | `jsonBody(ref('Error'))` | Deep-equals `{ content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } }` |
| status-server-openapi-019 | error-response-shape | `errorResponse` | Deep-equals `{ description: 'Error', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } }` |
| status-server-openapi-020 | errors-map-shares-error-response | `errors(401, 404)` | Deep-equals `{ 401: errorResponse, 404: errorResponse }`; `errors(401, 404)[401]` and `errors(401, 404)[404]` are each the exact same object reference as the module's `errorResponse` export, not independent copies |
| status-server-openapi-021 | ok-json-wrapper, ok-flag-shape | `okFlag` | Deep-equals `{ description: 'Success', content: { 'application/json': { schema: { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } } } } } }` |
| status-server-openapi-022 | path-param-always-required-string | `pathParam('id')` | Deep-equals `{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }` |
| status-server-openapi-023 | query-param-default-optional-string | `queryParam('q')` and `queryParam('q', true)` | First deep-equals `{ name: 'q', in: 'query', required: false, schema: { type: 'string' } }`; second deep-equals the same object with `required: true` |
| status-server-openapi-024 | zod-json-conversion | `zodJson(z.object({ id: z.string() }))` | Returns the draft-2020-12 JSON Schema `z.toJSONSchema` produces for that shape (an object schema whose `properties.id` is `{ type: 'string' }`), not a hand-transcribed equivalent |
| status-server-openapi-025 | zod-json-fallback-on-throw | `zodJson(schema)` for a zod value `z.toJSONSchema` throws on for the `draft-2020-12` target — the function's own comment cites a raw `z.date()` as the example | Returns `{ type: 'object', additionalProperties: true }`; the call does not throw and makes no logging call |
| status-server-openapi-026 | path-collision-caught-by-drift-guard | The stub-collision scenario from vector 005, but where `createApp()` also registers a real route on a method (e.g. `POST /tokens`) that the surviving auto-generated path-item never defines | `openapi.test.ts`'s "every registered route is documented or permanently excluded" assertion's `undocumented` array now contains `POST /tokens`, failing the test — demonstrating the guard that keeps a real collision from shipping silently |
| status-server-openapi-027 | schema-name-collision-unguarded | Two `MODULES` entries hypothetically both exported a `Schemas` entry under the same component-schema name with different shapes | No test in `test/openapi.test.ts` or elsewhere under `test/` fails; this row records the unguarded case described in `schema-name-collision-unguarded` rather than a demonstrable current-repo failure, since none of the fourteen given `MODULES` entries currently collides |

## Edge Cases

- **Null and empty input**: `normHonoPath('')` MUST return `'/'` — the empty string has no trailing slash to strip, so the collapse/strip steps no-op and the `|| '/'` fallback fires on the still-empty result. `errors()` called with zero codes MUST return `{}` (`Object.fromEntries([])`), documenting no error responses at all. `zodJson(schema)` for a `schema` that is `undefined`/`null` MUST fall through to the same catch-and-fallback path as zod-json-fallback-on-throw, since `z.toJSONSchema` throws synchronously on a non-`ZodType` argument.
- **Boundary values**: `normHonoPath` collapses a run of any length of two or more consecutive slashes to one, and its `:name` regex matches a parameter name of any length composed of letters, digits, and underscores; `errors(...codes)` accepts any numeric status codes, including non-standard ones, with no allowlist. `pathParam`/`queryParam` accept a `name` of any string, including the empty string, with no validation — per `build.ts`'s own eslint-disable comment ("No client input flows through here — every fragment is a static, trusted document piece"), every call site is a hardcoded literal inside a `paths/*.ts` module, not caller- or request-supplied input, so the absence of a validation check here is consistent with that documented trust boundary rather than a gap in it.
- **Concurrent access**: none of the three files holds mutable module-level state that a call writes to — `COMPONENT_SCHEMAS`, `BEARER`, `errorResponse`, and `okFlag` are read-only constants, and `MODULES` is a fixed array built once at module load. `buildOpenApiSpec` mutates only the `doc` object returned by that same call's own `app.getOpenAPI31Document(...)` invocation; in every observed call site (`tools/dump-openapi.ts`, and `test/openapi.test.ts`'s module-scope build and its later re-build inside one test) `buildOpenApiSpec` is called at most once per process run, never concurrently against a shared `app` instance, so there is no evidence in these sources of two calls racing to mutate the same returned document.
- **Error states**: the only error path in these three files is `zodJson`'s `try`/`catch`, handled per zod-json-fallback-on-throw; `normHonoPath` and every `shared.ts` builder besides `zodJson` MUST NOT throw for any string or object input, since none of them performs a fallible operation (no parsing, no I/O, no external call).
- **Offline / disconnected state**: not applicable — none of these three files makes a network call, reads a file, or queries a database; `buildOpenApiSpec`'s only inputs are the caller-supplied `app` object and `version` string, both already in memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app` | `OpenAPIHono<any>` | required | The Hono app instance whose `.openapi()`-registered routes seed the base document via `getOpenAPI31Document`; passed by the caller (`tools/dump-openapi.ts`, `test/openapi.test.ts`). |
| `version` | `string` | required | Embedded verbatim as `doc.info.version`; both current callers pass `config.appVersion`. |
| `MODULES` | internal constant (`build.ts`) | fixed, fourteen entries | Not a caller-supplied option — the list of hand-written `{ paths, schemas? }` modules is hardcoded in `build.ts` and changes only by editing the source file. |

## Deep Linking

Not applicable: none of these three files defines an application URL scheme; the assembled document is a static JSON artifact served by the app's own `GET /doc` route (external to these three files), not a deep-link target.

## Localization

Not applicable: none of `build.ts`, `route-key.ts`, or `shared.ts` calls a localization or i18n mechanism, and the English strings they do embed — `info.title: 'status-backend'`, and `shared.ts`'s fixed `description` values `'Error'`/`'Success'` — are OpenAPI documentation metadata read by developers and API tooling from the generated document itself, not runtime messages returned to an end user or API caller (the actual runtime error body's `message`/`code` values are supplied elsewhere, by whatever code throws the error).

## Accessibility Options

Not applicable: these three files have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of these three files consults a feature-flag system; `MODULES` and the fourteen path modules it lists are compiled into every build with no flag gating any of them.

## Analytics

Not applicable: none of these three files emits an analytics or telemetry event of any kind.

## Privacy

- **Data collected**: None. Per `build.ts`'s own eslint-disable comment, "No client input flows through here" — none of these three files reads, stores, or transmits any caller-, request-, or user-scoped data; every fragment they assemble is a static, trusted document piece derived from the route modules' own zod schemas at build/test time.
- **Storage**: Not applicable — these three files write to nothing; `tools/dump-openapi.ts` (external to these three files) is what writes the assembled document to `openapi.json`.
- **Transmission**: Not applicable within these three files — the assembled document is served over HTTP by the app's `GET /doc` route, which lives outside these three files.
- **Retention**: Not applicable — no data is held by these three files between calls.

## Logging

Not applicable: none of `build.ts`, `route-key.ts`, or `shared.ts` contains a logging call at any level, including on `zodJson`'s caught-exception path (zod-json-fallback-on-throw), which returns its fallback silently.

## Platform Notes

- **React/Web** (source platform): the three files live under `packages/web/packages/status-server/src/openapi/`, layered on `@hono/zod-openapi`'s `OpenAPIHono.getOpenAPI31Document` for the natively-generated portion and Zod's `z.toJSONSchema` (`shared.ts`'s `zodJson`) to convert each hand-written route's own request/response Zod schema into the matching JSON Schema fragment, so the documented body and the handler's actual runtime validation are generated from one schema, never hand-transcribed twice. The fourteen `paths/*.ts` modules that supply `HAND_WRITTEN_PATHS`/`HAND_WRITTEN_SCHEMAS` are outside this recipe's three given files.
- **SwiftUI**: no SwiftUI equivalent of this assembler exists, since it is a server-side build artifact; a SwiftUI app is only a consumer of the resulting document, most usefully by feeding it to `swift-openapi-generator` to produce typed Swift request/response models and a generated client, rather than hand-writing `URLSession` calls against the routes the document describes.
- **Compose**: same consumer relationship as SwiftUI — an Android/Compose client calls the documented routes with OkHttp/Retrofit, optionally generating a client from this document via the OpenAPI Generator Kotlin target; there is no Compose-side equivalent of assembling the document itself.
- **AppKit / UIKit**: the same consumer relationship as SwiftUI, without the codegen story — an AppKit/UIKit client calls the documented routes directly with `URLSession`/`URLRequest`, treating the OpenAPI document as human-readable reference for path, parameter, and response shapes rather than as a code-generation input.
- **WinUI 3**: a WinUI 3 desktop client is likewise a consumer of the same document (`HttpClient` calls against the documented routes, optionally with an NSwag- or `Microsoft.OpenApi`-generated typed client). If the status backend itself were ported to a .NET server (ASP.NET Core Minimal APIs), this recipe's pattern maps directly: `Microsoft.OpenApi.Models.OpenApiDocument` replaces the hand-assembled JSON object; `Microsoft.AspNetCore.OpenApi`'s native minimal-API document generation replaces `getOpenAPI31Document` for the natively-documented routes; a `Dictionary<string, OpenApiPathItem>` merge (mirroring `HAND_WRITTEN_PATHS`'s `Object.assign`) documents any endpoint mapped outside that native generator; .NET 9's `System.Text.Json.Schema.JsonSchemaExporter` is the `zodJson` analogue for turning a C# request/response record's shape into the same JSON Schema the model binder validates against; and `normHonoPath`'s `:param`-to-brace rewrite has no equivalent step needed at all, because ASP.NET's own route-template syntax already uses `{param}`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/openapi/build.ts` |
| web | `packages/web/packages/status-server/src/openapi/route-key.ts` |
| web | `packages/web/packages/status-server/src/openapi/shared.ts` |

## Design Decisions

- **Decision**: let an auto-generated (`.openapi()`-registered) path or component-schema entry win over a hand-written one of the same key, rather than the reverse.
  **Rationale**: traced directly to `build.ts`'s own doc comment — "The auto-generated entries WIN on any path/schema key collision (they are the source of truth for the routes they cover)"; a native `.openapi()` route already carries its own zod-validated request/response types, which are authoritative for that route, so letting a hand-written module's static fragment for the same key shadow it would document the less accurate of the two.
  **Approved**: pending
- **Decision**: force `bearerAuth`'s security scheme to the literal `{ type: 'http', scheme: 'bearer' }` unconditionally, after spreading whatever `getOpenAPI31Document` produced for `securitySchemes`.
  **Rationale**: not stated in source as prose; this is a plain observation of the assignment order in `build.ts` (spread `doc.components.securitySchemes` first, then reassign `bearerAuth` on top), recorded as a fact about the code's actual behavior — every documented operation using `BEARER` security is guaranteed to resolve to this one bearer scheme shape, with no auto-generated `bearerAuth` entry able to diverge from it.
  **Approved**: pending
- **Decision**: reuse one identical `errorResponse` object (and `BEARER`, `okFlag`) as a shared constant across every call site, instead of a per-call factory that would produce an independent copy each time.
  **Rationale**: traced to `shared.ts`'s own comment on `errors` — "One place to define what a documented error entry is, instead of repeating `: errorResponse`"; every documented 4xx/5xx entry across all fourteen path modules intentionally shares the identical reference, trading per-call-site independence for a single edit point if the error envelope's documented shape ever changes.
  **Approved**: pending
- **Decision**: swallow a `zodJson` conversion failure into a generic `{ type: 'object', additionalProperties: true }` fallback, with no logging and no re-throw.
  **Rationale**: traced to `zodJson`'s own doc comment — the fallback exists only for a zod type JSON Schema cannot represent (its cited example is a raw `z.date()`), and every actual route schema in this codebase is a plain JSON shape, so the fallback path is documented as "defensive only," not an expected runtime occurrence needing a signal.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [api-design-conventions](agenticdevelopercookbook://compliance/access-patterns#api-design-conventions) | passed | Access Patterns |

`separation-of-concerns` passes: `build.ts` assembles the document, `route-key.ts` normalizes a route key, and `shared.ts` provides fragment builders — three single-purpose files with no duplicated logic between them, and the fourteen `paths/*.ts` modules each own their own route family's documentation, external to all three. `unit-test-coverage` is `partial`: `buildOpenApiSpec`'s overall document shape and its parity against `app.routes` is exercised thoroughly by `test/openapi.test.ts` (the 3.1/bearer-shape assertion, the phantom-route and undocumented-route drift-guard assertions, and the committed-`openapi.json` snapshot assertion), but none of `route-key.ts`'s `normHonoPath` edge cases (duplicate-slash collapse, the root-path fallback) or any of `shared.ts`'s nine individual helper functions (`jsonBody`, `ref`, `errorResponse`, `errors`, `okJson`, `okFlag`, `pathParam`, `queryParam`, `zodJson` including its catch branch) has a dedicated unit test — each is exercised only indirectly, as a value baked into the fourteen `paths/*.ts` modules that the drift-guard and snapshot tests check as a whole; this also leaves the collision case in `schema-name-collision-unguarded` without any regression test that would catch it. `explicit-error-handling` is `partial`: the one error path across these three files, `zodJson`'s `try`/`catch`, is a deliberate, documented fallback rather than an oversight, but it is nonetheless silently swallowed — a successful conversion and a caught exception that happens to produce the same permissive `{ type: 'object', additionalProperties: true }` shape are indistinguishable from outside the function, with no log or return value marking which branch ran. `api-design-conventions` passes: the OpenAPI paths these files assemble consistently use plural resource nouns, brace-style path parameters (via `pathParam` and, for the drift guard's own recomputation, `normHonoPath`'s `:name`-to-`{name}` rewrite), and one shared bearer/error/success-envelope vocabulary (`BEARER`, `errorResponse`, `okFlag`) reused by construction across all fourteen hand-written modules, rather than left to per-module hand-checking.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
