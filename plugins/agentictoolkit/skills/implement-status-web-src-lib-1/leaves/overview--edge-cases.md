<!-- leaf: implement-status-web-src-lib-1/overview--edge-cases · source: status-web-src-lib-overview.md -->

# Overview Projections

**Rules** (cite as `implement-status-web-src-lib-1/overview--edge-cases#<slug>`):

- `empty-problem-list` MUST — indicatorFromProblems([]) MUST return { state: "ok", count: 0 }. OverviewTab guards the case where "ok" would be a …
- `unknown-severity` MUST — A problem whose severity is none of the typed values counts toward count and MUST yield "warn" unless another problem …
- `empty-activity` MUST — deployCounts([], anySinceMs) MUST return all zeros.
- `unparseable-at` MUST — Date.parse returns NaN, NaN < sinceMs is false, so the row MUST be counted as inside the window. ActivityRow.at is …
- `sincems-of-nan` MUST — Every comparison is false, so every deploy row MUST be counted.
- `non-integer-or-huge-windows` MUST — activityWindowLabel rounds to the nearest hour (e.g. 23.6h to "24h"); a whole-day multiple of 48h or more MUST switch …
- `nan-bounds` MUST — If either bound is NaN (e.g. an unparseable generatedAt at the call site), Math.max(1, NaN) is NaN and the function …
- `negative-or-zero-window` MUST — activityWindowLabel MUST return "1h".
- `headlinefor-with-count-0-and-non-ok-state` MUST — MUST return "0 SERVICES NEED ATTENTION" or "0 PROBLEMS"; the function trusts the caller's pairing of state and count.
- `negative-or-fractional-count` MUST — headlineFor MUST interpolate it verbatim with the plural form (e.g. "-1 PROBLEMS").
- `vercel-environment-of-whitespace` MUST — isRealEnvDeployRow("vercel", " ") MUST return true; only null, undefined and "" count as a preview.

## Edge Cases

- **Empty problem list**: `indicatorFromProblems([])` MUST return `{ state: "ok", count: 0 }`. `OverviewTab` guards the case where "ok" would be a false "ALL SYSTEMS OPERATIONAL" claim; the module itself does not.
- **Unknown severity**: A problem whose `severity` is none of the typed values counts toward `count` and MUST yield `"warn"` unless another problem is `"critical"`.
- **Empty activity**: `deployCounts([], anySinceMs)` MUST return all zeros.
- **Unparseable `at`**: `Date.parse` returns `NaN`, `NaN < sinceMs` is `false`, so the row MUST be counted as inside the window. `ActivityRow.at` is documented as an ISO time supplied by the server, so this is a caller precondition, not validation the module performs.
- **`sinceMs` of `NaN`**: Every comparison is `false`, so every deploy row MUST be counted.
- **Non-integer or huge windows**: `activityWindowLabel` rounds to the nearest hour (e.g. 23.6h to `"24h"`); a whole-day multiple of 48h or more MUST switch to days, and 24h MUST stay `"24h"`.
- **`NaN` bounds**: If either bound is `NaN` (e.g. an unparseable `generatedAt` at the call site), `Math.max(1, NaN)` is `NaN` and the function MUST return `"NaNh"`; it performs no guard.
- **Negative or zero window**: `activityWindowLabel` MUST return `"1h"`.
- **`headlineFor` with count 0 and non-ok state**: MUST return `"0 SERVICES NEED ATTENTION"` or `"0 PROBLEMS"`; the function trusts the caller's pairing of state and count.
- **Negative or fractional count**: `headlineFor` MUST interpolate it verbatim with the plural form (e.g. `"-1 PROBLEMS"`).
- **Vercel environment of whitespace**: `isRealEnvDeployRow("vercel", " ")` MUST return `true`; only `null`, `undefined` and `""` count as a preview.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O; a missing or stale board is handled by its callers (`use-portfolio-indicator` maps it to `"unknown"` before `INDICATOR_STATE` is consulted).
