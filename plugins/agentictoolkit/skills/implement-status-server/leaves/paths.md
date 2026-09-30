<!-- leaf: implement-status-server/paths · source: status-server-paths.md -->

**Rules** (cite as `implement-status-server/paths#<slug>`):

- `paths-export` MUST
- `schemas-export-when-introduced` MUST
- `path-key-template-form` MUST
- `operation-required-fields` MUST
- `bearer-scheme-post-seam` MUST
- `bearer-scheme-pre-seam-omitted` MUST
- `provider-webhook-security-comment` MUST
- `admin-gated-403` MUST
- `request-body-from-route-zod` MUST
- `success-envelope-helpers` MUST
- `error-envelope-helper` MUST
- `schema-single-owner` MUST
- `module-registration` MUST
- `hand-written-yields-to-generated` MUST
- `security-scheme-fixed` MUST
- `zod-json-fallback` MUST
- `query-params-string-typed` MUST
- `peer-token-redaction` MUST
- `token-value-once` MUST
- `activity-cursor-pair-documented` MUST
- `reconcile-side-effect-documented` MUST
- `content-type-svg-badge` MUST
- `content-type-sse-stream` MUST
- `no-scheduler-response-shape` MUST
- `module-purity` MUST
- `drift-guard-exhaustive` MUST
- `no-phantom-documented-routes` MUST
- `committed-spec-pinned` MUST
- `no-persistence` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app` | `OpenAPIHono<any>` (Hono) | Required, caller-supplied | The fully-mounted app instance `buildOpenApiSpec` reads `app.getOpenAPI31Document()` from, and (in `test/openapi.test.ts`) `app.routes` from; every route must already be registered before this call, since nothing here re-checks later. |
| `version` | `string` | Required, caller-supplied | Written into the assembled document's `info.version`; the tracked `openapi.json` normalizes this to `'0.0.0'` before comparison so a version bump alone never fails the drift guard's snapshot check. |
| `PERMANENTLY_UNDOCUMENTED` | `Set<string>` (`test/openapi-exclusions.ts`) | `GET /`, `GET /doc`, `GET /mcp`, `POST /mcp`, `DELETE /mcp` | The only allowed exceptions to "every registered route is documented"; adding an entry here is the one way to leave a route out of the OpenAPI surface without failing the test. |

