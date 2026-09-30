<!-- leaf: implement-status-server/openapi--part-2 · source: status-server-openapi.md -->

# Status Server OpenAPI — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app` | `OpenAPIHono<any>` | required | The Hono app instance whose `.openapi()`-registered routes seed the base document via `getOpenAPI31Document`; passed by the caller (`tools/dump-openapi.ts`, `test/openapi.test.ts`). |
| `version` | `string` | required | Embedded verbatim as `doc.info.version`; both current callers pass `config.appVersion`. |
| `MODULES` | internal constant (`build.ts`) | fixed, fourteen entries | Not a caller-supplied option — the list of hand-written `{ paths, schemas? }` modules is hardcoded in `build.ts` and changes only by editing the source file. |

## Privacy

- **Data collected**: None. Per `build.ts`'s own eslint-disable comment, "No client input flows through here" — none of these three files reads, stores, or transmits any caller-, request-, or user-scoped data; every fragment they assemble is a static, trusted document piece derived from the route modules' own zod schemas at build/test time.
- **Storage**: Not applicable — these three files write to nothing; `tools/dump-openapi.ts` (external to these three files) is what writes the assembled document to `openapi.json`.
- **Transmission**: Not applicable within these three files — the assembled document is served over HTTP by the app's `GET /doc` route, which lives outside these three files.
- **Retention**: Not applicable — no data is held by these three files between calls.

## Platform Notes

- **React/Web** (source platform): the three files live under `packages/web/packages/status-server/src/openapi/`, layered on `@hono/zod-openapi`'s `OpenAPIHono.getOpenAPI31Document` for the natively-generated portion and Zod's `z.toJSONSchema` (`shared.ts`'s `zodJson`) to convert each hand-written route's own request/response Zod schema into the matching JSON Schema fragment, so the documented body and the handler's actual runtime validation are generated from one schema, never hand-transcribed twice. The fourteen `paths/*.ts` modules that supply `HAND_WRITTEN_PATHS`/`HAND_WRITTEN_SCHEMAS` are outside this recipe's three given files.
- **SwiftUI**: no SwiftUI equivalent of this assembler exists, since it is a server-side build artifact; a SwiftUI app is only a consumer of the resulting document, most usefully by feeding it to `swift-openapi-generator` to produce typed Swift request/response models and a generated client, rather than hand-writing `URLSession` calls against the routes the document describes.
- **Compose**: same consumer relationship as SwiftUI — an Android/Compose client calls the documented routes with OkHttp/Retrofit, optionally generating a client from this document via the OpenAPI Generator Kotlin target; there is no Compose-side equivalent of assembling the document itself.
- **AppKit / UIKit**: the same consumer relationship as SwiftUI, without the codegen story — an AppKit/UIKit client calls the documented routes directly with `URLSession`/`URLRequest`, treating the OpenAPI document as human-readable reference for path, parameter, and response shapes rather than as a code-generation input.
- **WinUI 3**: a WinUI 3 desktop client is likewise a consumer of the same document (`HttpClient` calls against the documented routes, optionally with an NSwag- or `Microsoft.OpenApi`-generated typed client). If the status backend itself were ported to a .NET server (ASP.NET Core Minimal APIs), this recipe's pattern maps directly: `Microsoft.OpenApi.Models.OpenApiDocument` replaces the hand-assembled JSON object; `Microsoft.AspNetCore.OpenApi`'s native minimal-API document generation replaces `getOpenAPI31Document` for the natively-documented routes; a `Dictionary<string, OpenApiPathItem>` merge (mirroring `HAND_WRITTEN_PATHS`'s `Object.assign`) documents any endpoint mapped outside that native generator; .NET 9's `System.Text.Json.Schema.JsonSchemaExporter` is the `zodJson` analogue for turning a C# request/response record's shape into the same JSON Schema the model binder validates against; and `normHonoPath`'s `:param`-to-brace rewrite has no equivalent step needed at all, because ASP.NET's own route-template syntax already uses `{param}`.

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
