<!-- leaf: implement-status-server/openapi--edge-cases · source: status-server-openapi.md -->

# Status Server OpenAPI

**Rules** (cite as `implement-status-server/openapi--edge-cases#<slug>`):

- `null-and-empty-input` MUST — normHonoPath('') MUST return '/' — the empty string has no trailing slash to strip, so the collapse/strip steps no-op …
- `error-states` MUST — the only error path in these three files is zodJson's try/catch, handled per zod-json-fallback-on-throw; normHonoPath …

## Edge Cases

- **Null and empty input**: `normHonoPath('')` MUST return `'/'` — the empty string has no trailing slash to strip, so the collapse/strip steps no-op and the `|| '/'` fallback fires on the still-empty result. `errors()` called with zero codes MUST return `{}` (`Object.fromEntries([])`), documenting no error responses at all. `zodJson(schema)` for a `schema` that is `undefined`/`null` MUST fall through to the same catch-and-fallback path as zod-json-fallback-on-throw, since `z.toJSONSchema` throws synchronously on a non-`ZodType` argument.
- **Boundary values**: `normHonoPath` collapses a run of any length of two or more consecutive slashes to one, and its `:name` regex matches a parameter name of any length composed of letters, digits, and underscores; `errors(...codes)` accepts any numeric status codes, including non-standard ones, with no allowlist. `pathParam`/`queryParam` accept a `name` of any string, including the empty string, with no validation — per `build.ts`'s own eslint-disable comment ("No client input flows through here — every fragment is a static, trusted document piece"), every call site is a hardcoded literal inside a `paths/*.ts` module, not caller- or request-supplied input, so the absence of a validation check here is consistent with that documented trust boundary rather than a gap in it.
- **Concurrent access**: none of the three files holds mutable module-level state that a call writes to — `COMPONENT_SCHEMAS`, `BEARER`, `errorResponse`, and `okFlag` are read-only constants, and `MODULES` is a fixed array built once at module load. `buildOpenApiSpec` mutates only the `doc` object returned by that same call's own `app.getOpenAPI31Document(...)` invocation; in every observed call site (`tools/dump-openapi.ts`, and `test/openapi.test.ts`'s module-scope build and its later re-build inside one test) `buildOpenApiSpec` is called at most once per process run, never concurrently against a shared `app` instance, so there is no evidence in these sources of two calls racing to mutate the same returned document.
- **Error states**: the only error path in these three files is `zodJson`'s `try`/`catch`, handled per zod-json-fallback-on-throw; `normHonoPath` and every `shared.ts` builder besides `zodJson` MUST NOT throw for any string or object input, since none of them performs a fallible operation (no parsing, no I/O, no external call).
- **Offline / disconnected state**: not applicable — none of these three files makes a network call, reads a file, or queries a database; `buildOpenApiSpec`'s only inputs are the caller-supplied `app` object and `version` string, both already in memory.
