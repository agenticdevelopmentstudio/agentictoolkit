<!-- leaf: implement-status-server/openapi · source: status-server-openapi.md -->

**Rules** (cite as `implement-status-server/openapi#<slug>`):

- `base-document-from-hono` MUST
- `module-list-is-documented-surface` MUST
- `native-routes-excluded-from-modules` MUST
- `hand-written-paths-merge` MUST
- `hand-written-schemas-merge` MUST
- `auto-generated-paths-win-collision` MUST
- `components-defaulted-when-absent` MUST
- `components-schemas-precedence` MUST
- `error-component-schema` MUST
- `bearer-scheme-fixed` MUST
- `build-return-type-unknown` MUST
- `build-deterministic` MUST
- `param-token-conversion` MUST
- `duplicate-slash-collapse` MUST
- `trailing-slash-stripped` MUST
- `route-key-pure` MUST
- `bearer-security-requirement` MUST
- `json-body-wrapper` MUST
- `schema-ref` MUST
- `error-response-shape` MUST
- `errors-map-shares-error-response` MUST
- `ok-json-wrapper` MUST
- `ok-flag-shape` MUST
- `path-param-always-required-string` MUST
- `query-param-default-optional-string` MUST
- `zod-json-conversion` MUST
- `zod-json-fallback-on-throw` MUST
- `path-collision-caught-by-drift-guard` MUST

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

