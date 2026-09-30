<!-- leaf: implement-status-server/paths--test-vectors · source: status-server-paths.md -->

# Status Server Paths

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
