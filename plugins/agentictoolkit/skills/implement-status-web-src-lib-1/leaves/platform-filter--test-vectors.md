<!-- leaf: implement-status-web-src-lib-1/platform-filter--test-vectors · source: status-web-src-lib-platform-filter.md -->

# Platform Filter Options

## Conformance Test Vectors

Vectors pf-001 to pf-006 are derived from the assertions in `src/lib/platform-filter.test.ts`. The rest trace to `platformFilterOptions` and `allPlatformKeys` directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pf-001 | known-platforms-always, known-platforms-order | `platformFilterOptions([{platform:"vercel"},{platform:"vercel"},{platform:"cloudflare"}])` | keys `["vercel","railway","cloudflare","crunchy"]` (railway present with zero endpoints) |
| pf-002 | known-platforms-always | `platformFilterOptions([])` | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-003 | none-row-conditional | `platformFilterOptions([{platform:"vercel"}])` | no row has key `"__none__"` |
| pf-004 | none-row-conditional, none-row-last, null-maps-to-sentinel | `platformFilterOptions([{platform:"vercel"},{platform:null}])` | last row equals `{ key: "__none__", label: "no platform" }` |
| pf-005 | unknown-platforms-appended, none-row-last | `platformFilterOptions([{platform:"fly"},{platform:null}])` | keys `["vercel","railway","cloudflare","crunchy","fly","__none__"]` |
| pf-006 | known-platform-no-duplicate | `platformFilterOptions([{platform:"railway"},{platform:"railway"}])` | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-007 | all-keys-contents, all-keys-ignores-data | `allPlatformKeys()` | set equal to `{"vercel","railway","cloudflare","crunchy","__none__"}` |
| pf-008 | known-platform-label | `platformFilterOptions([])[1]` | `{ key: "railway", label: "railway" }` |
| pf-009 | unknown-platforms-order, unknown-platforms-deduplicated | `platformFilterOptions([{platform:"render"},{platform:"fly"},{platform:"render"}])` | keys `["vercel","railway","cloudflare","crunchy","render","fly"]` |
| pf-010 | known-match-exact | `platformFilterOptions([{platform:"Vercel"}])` | keys `["vercel","railway","cloudflare","crunchy","Vercel"]` |
| pf-011 | all-keys-fresh-set | `const a = allPlatformKeys(); a.clear(); allPlatformKeys().size` | `5` |
| pf-012 | none-sentinel | read `PLATFORM_NONE` | `"__none__"` |
| pf-013 | options-synchronous | call `platformFilterOptions(input)` with a frozen input array | returns rows without throwing; input unchanged |
| pf-014 | selection-contract | selection `allPlatformKeys()`; endpoints with platform `"railway"`, `null`, `"fly"` | `railway` and `null` endpoints pass; `fly` endpoint does not |
| pf-015 | no-errors, single-threaded | call both functions with valid input | return a value synchronously (not a promise); nothing thrown |
