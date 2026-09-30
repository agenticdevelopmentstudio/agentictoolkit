<!-- leaf: implement-status-web-src-lib-1/platform-filter--edge-cases · source: status-web-src-lib-platform-filter.md -->

# Platform Filter Options

**Rules** (cite as `implement-status-web-src-lib-1/platform-filter--edge-cases#<slug>`):

- `empty-endpoint-list` MUST — platformFilterOptions([]) MUST return exactly the four known-platform rows, with no no-platform row (pf-002).
- `all-endpoints-unwired` MUST — Input where every platform is null MUST return the four known-platform rows followed by the no-platform row.
- `empty-string-platform` MUST — A platform of "" is not null and not in PLATFORMS, so it MUST produce an unknown-platform row with key: "" and label: …
- `value-equal-to-the-sentinel` MUST — An endpoint whose platform is the literal string "__none__" MUST be treated as unwired: it produces the no-platform row …
- `case-variants` MUST — "Vercel" or "RAILWAY" MUST produce separate unknown-platform rows, since matching is case-sensitive (pf-010).
- `unknown-platform-under-the-default-selection` MUST — An endpoint with an unknown platform gets a filter row but its key is not in allPlatformKeys(). With the default or …

## Edge Cases

- **Empty endpoint list**: `platformFilterOptions([])` MUST return exactly the four known-platform rows, with no no-platform row (pf-002).
- **All endpoints unwired**: Input where every `platform` is `null` MUST return the four known-platform rows followed by the no-platform row.
- **Empty-string platform**: A `platform` of `""` is not `null` and not in `PLATFORMS`, so it MUST produce an unknown-platform row with `key: ""` and `label: ""`. The source does not reject or relabel it; `EndpointsSection` sets `platform` from the `PLATFORMS` select, which bounds how such a value could arise.
- **Value equal to the sentinel**: An endpoint whose `platform` is the literal string `"__none__"` MUST be treated as unwired: it produces the no-platform row and no unknown-platform row, because the sentinel check does not distinguish it from `null`.
- **Case variants**: `"Vercel"` or `"RAILWAY"` MUST produce separate unknown-platform rows, since matching is case-sensitive (pf-010).
- **Unknown platform under the default selection**: An endpoint with an unknown platform gets a filter row but its key is not in `allPlatformKeys()`. With the default or "all" selection, a caller filtering by set membership MUST hide it until the operator selects that row (pf-014).
- **Missing `platform` field**: A `platform` of `undefined` is excluded by the type signature; at runtime the `??` operator maps it to `PLATFORM_NONE` the same as `null`.
- **Large input**: Work is linear in the number of endpoints plus a scan of `PLATFORMS` per distinct value; there is no size limit and no truncation.
- **Concurrent access**: Not applicable. Both functions are synchronous and stateless, and JavaScript runs them on one thread.
- **Error states and offline**: Not applicable. The module performs no I/O, so there is no dependency to fail and no connectivity to lose.
