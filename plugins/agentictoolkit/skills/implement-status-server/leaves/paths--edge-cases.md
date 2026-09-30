<!-- leaf: implement-status-server/paths--edge-cases · source: status-server-paths.md -->

# Status Server Paths

**Rules** (cite as `implement-status-server/paths--edge-cases#<slug>`):

- `null-and-empty-input` MUST — zodJson(schema) receiving a zod schema z.toJSONSchema cannot convert MUST NOT throw; the fallback { type: 'object', …
- `boundary-values` MUST — errors() called with zero codes MUST return {} (Object.fromEntries of an empty array), documenting no failure code at …

## Edge Cases

- **Null and empty input**: `zodJson(schema)` receiving a zod schema `z.toJSONSchema` cannot convert MUST NOT throw; the fallback `{ type: 'object', additionalProperties: true }` MUST be returned in its place. None of the 14 modules' own imported zod schemas currently exercises this branch — every route zod body documented here is a plain JSON shape — so it is defensive-only, per `shared.ts`'s own comment, not a path any current operation reaches.
- **Boundary values**: `errors()` called with zero codes MUST return `{}` (`Object.fromEntries` of an empty array), documenting no failure code at all; no module in this set calls it with zero arguments. A route whose normalized key (`normHonoPath`) differs from a `PERMANENTLY_UNDOCUMENTED` entry by even a trailing slash or a case difference MUST be treated by the drift guard as a genuinely undocumented route, not a match, since the comparison is an exact string match.
- **Concurrent access**: Not applicable — every `*Paths`/`*Schemas` export is a `const` object literal fully built once, synchronously, at module-import time by a single-threaded JS module loader; there is no mutable shared state and no request-scoped code path anywhere in the 14 modules for two callers to race over.
- **Error states — module left out of the registry**: a module accidentally omitted from the `MODULES` array in `build.ts` documents nothing at build time and raises no error; the omission is caught only the next time `test/openapi.test.ts` runs its undocumented-route assertion.
- **ref-integrity**: `ref(name)` builds its `$ref` string from its argument without checking it against `components.schemas`, and neither `buildOpenApiSpec` nor `test/openapi.test.ts` checks that every `$ref` resolves. A misspelled `ref()` argument produces a dangling reference in the published spec, and no test catches it.
- **Offline / disconnected state**: Not applicable — none of the 14 modules or `shared.ts`'s helpers makes a network call, a storage call, or any I/O; the entire component is pure, synchronous document construction from data already available at import time, so there is no connectivity state for it to lose.
