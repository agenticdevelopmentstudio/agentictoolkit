<!-- leaf: implement-status-server/paths--part-2 · source: status-server-paths.md -->

# Status Server Paths — continued (part 2)

**Rules** (cite as `implement-status-server/paths--part-2#<slug>`):

- `decision` MUST — document DELETE /tokens/{id} with a bare 204 (description: 'Revoked', no body) while every other row-deleting mutation …

## Localization

Every `summary`/`description` string across the 14 modules (for example `authPaths['/auth/signup'].post.summary`, or `activityPaths['/activity'].get.description`) is a hardcoded English literal aimed at a developer reading the generated API documentation; none of these modules reads a string catalog, an i18n bundle, or an `Accept-Language` header, and the assembled document carries no locale dimension at all. Per this recipe's authoring rules, a hardcoded developer-facing string is a fact worth recording, not a gap to excuse with a blanket "Not applicable":

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — doc summary | `Create a status account (starts pending until an admin promotes it)` | `authPaths['/auth/signup'].post.summary` |
| n/a — doc description | `The cursor is the (before, beforeId) PAIR because a deployment's build and deploy rows share a timestamp...` | `activityPaths['/activity'].get.description` |
| n/a — doc summary | `Requirement B: write the board into the ledger — opens, updates and resolves rows (can alert)` | `boardPaths['/board/reconcile'].post.summary` |

## Privacy

- **Data collected**: this component collects nothing itself; it documents the shapes of data other modules collect and expose, most notably `peerInsert`'s raw fleet-peer `token`, the API-token secret minted by `POST /tokens`, and the GitHub OAuth `code`/`state` query parameters on `/auth/github/callback`.
- **Storage**: this component performs no storage of its own; it only declares which persisted-row schemas (`PeerRow`, `ApiTokenMeta`) are safe to return, by construction excluding the raw secret from every response schema except the one-time `POST /tokens` `201` body.
- **Transmission**: the documented request schemas accept the raw `peerInsert.token` and the OAuth `code` on write; the documented response schemas never echo a raw secret back except that single `201` create response — every other read of a peer or a token is redacted (`hasToken: boolean`, or `ApiTokenMeta` with no `token` field at all).
- **Retention**: this component documents the fields that carry a secret's lifecycle (`ApiTokenMeta.expiresAt`, `ApiTokenMeta.revokedAt`, and `DELETE /tokens/{id}`'s revoke operation) without implementing any of that retention itself — actual storage and expiry enforcement live in the routes and storage modules this recipe's `related` field points at.

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
