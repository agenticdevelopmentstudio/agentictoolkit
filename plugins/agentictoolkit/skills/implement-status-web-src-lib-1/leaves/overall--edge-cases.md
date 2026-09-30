<!-- leaf: implement-status-web-src-lib-1/overall--edge-cases · source: status-web-src-lib-overall.md -->

# Overall Status Rollup

**Rules** (cite as `implement-status-web-src-lib-1/overall--edge-cases#<slug>`):

- `empty-input` MUST — statuses of length 0 MUST yield "unknown"; "no data" is kept distinct from both healthy and outage.
- `single-element` MUST — ["down"] MUST yield "major_outage", ["degraded"] MUST yield "degraded", and ["healthy"] MUST yield "operational".
- `all-down-boundary` MUST — the all-down check MUST run before the any-down check, so an all-"down" array never yields "degraded".
- `mixed-down-and-healthy` MUST — an array with at least one "down" and at least one non-"down" element MUST yield "degraded", not "major_outage", …
- `out-of-type-elements` MUST — values such as "unknown", null or other strings are excluded by the type; at runtime they MUST count as neither down …
- `very-large-arrays` MUST — the function MUST scan in linear time with no size limit; both every and some stop at the first deciding element.
- `divergence-from-the-server` MUST — this client copy has no publicOverall; a verdict computed here from endpoint statuses alone can read "operational" …

## Edge Cases

- **Empty input**: `statuses` of length 0 MUST yield `"unknown"`; "no data" is kept distinct from both healthy and outage.
- **Single element**: `["down"]` MUST yield `"major_outage"`, `["degraded"]` MUST yield `"degraded"`, and `["healthy"]` MUST yield `"operational"`.
- **All-down boundary**: the all-down check MUST run before the any-down check, so an all-`"down"` array never yields `"degraded"`.
- **Mixed down and healthy**: an array with at least one `"down"` and at least one non-`"down"` element MUST yield `"degraded"`, not `"major_outage"`, however many services are down.
- **Null or missing argument**: `null` or `undefined` for `statuses` is excluded by the type signature (a typed caller precondition); if one arrives through an unchecked cast, reading `.length` throws a `TypeError` that propagates to the caller unchanged.
- **Out-of-type elements**: values such as `"unknown"`, `null` or other strings are excluded by the type; at runtime they MUST count as neither down nor degraded (see unrecognized-element-fallback), so an all-`"unknown"` array yields `"operational"`, not `"unknown"`.
- **Very large arrays**: the function MUST scan in linear time with no size limit; both `every` and `some` stop at the first deciding element.
- **Concurrent access**: not applicable; the function is synchronous, pure and runs on the single JavaScript thread, so calls cannot interleave.
- **Error states and offline state**: not applicable; the function does no I/O, so it has no dependency that can fail or disconnect.
- **Divergence from the server**: this client copy has no `publicOverall`; a verdict computed here from endpoint statuses alone can read `"operational"` while the server's public verdict reads `"degraded"` because of a non-endpoint problem. The client MUST display the server-supplied `StatusResponse.overall` rather than recompute it.
