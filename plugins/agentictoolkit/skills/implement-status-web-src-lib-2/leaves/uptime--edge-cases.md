<!-- leaf: implement-status-web-src-lib-2/uptime--edge-cases · source: status-web-src-lib-uptime.md -->

# Uptime Math

**Rules** (cite as `implement-status-web-src-lib-2/uptime--edge-cases#<slug>`):

- `empty-input-no-checks` MUST — uptimePercent with total 0 MUST return null; dayStatus with all counts 0 MUST return "healthy". The two functions …
- `empty-input-no-services` MUST — overallUptimePercent([]) MUST return null, as MUST an array whose every entry is null.
- `missing-field` MUST — an entry whose uptimePercent is undefined (outside the type, but possible from untyped JSON) MUST be dropped like null, …
- `boundary-exactly-half-down` MUST — down / total equal to 0.5 MUST yield "degraded", not "down"; the comparison is strictly greater than.
- `boundary-negative-total` MUST — uptimePercent MUST return null for any total below 0.
- `boundary-zero-total-with-down-checks` MUST — dayStatus MUST return "down", because a positive number divided by 0 is positive infinity.
- `malformed-input-inconsistent-counts` MUST — when the bucket counts do not sum to total, uptimePercent MUST still divide by total and MAY return values above 100 or …
- `floating-point-rounding` MUST — rounding goes through binary floating point, so a value whose exact decimal half lies just below the representable …

## Edge Cases

- **Empty input — no checks**: `uptimePercent` with `total` 0 MUST return `null`; `dayStatus` with all counts 0 MUST return `"healthy"`. The two functions therefore disagree on a no-data day: one says "no data", the other says "healthy". Callers that need a "no data" day state MUST check `total` themselves.
- **Empty input — no services**: `overallUptimePercent([])` MUST return `null`, as MUST an array whose every entry is `null`.
- **Missing field**: an entry whose `uptimePercent` is `undefined` (outside the type, but possible from untyped JSON) MUST be dropped like `null`, because the filter uses loose `!= null`.
- **Boundary — exactly half down**: `down / total` equal to 0.5 MUST yield `"degraded"`, not `"down"`; the comparison is strictly greater than.
- **Boundary — negative total**: `uptimePercent` MUST return `null` for any `total` below 0.
- **Boundary — zero total with down checks**: `dayStatus` MUST return `"down"`, because a positive number divided by 0 is positive infinity.
- **Malformed input — inconsistent counts**: when the bucket counts do not sum to `total`, `uptimePercent` MUST still divide by `total` and MAY return values above 100 or below 0; no validation or clamping occurs (see counts-not-validated). The counts are produced by the status server, which owns their consistency.
- **Malformed input — NaN**: a `NaN` count makes `uptimePercent` return `NaN` (unless `total` itself is `NaN`, which fails the `total <= 0` test and also yields `NaN`); a `NaN` `uptimePercent` in the service list makes `overallUptimePercent` return `NaN`.
- **Floating-point rounding**: rounding goes through binary floating point, so a value whose exact decimal half lies just below the representable boundary MAY round down; ports MUST use IEEE 754 double arithmetic and the same multiply-round-divide sequence to match the reference output digit for digit.
- **Concurrent access**: not applicable — the functions are pure and hold no state, so any number of calls may run in any order with identical results.
- **Error states and offline**: not applicable — the module performs no I/O and has no dependency that can fail or disconnect.
- **Cancellation and timeouts**: not applicable — every call completes synchronously in constant time for `uptimePercent` and `dayStatus`, and linear time in the array length for `overallUptimePercent`.
