<!-- leaf: implement-status-server-monitor-2/time-ago--test-vectors · source: status-server-monitor-time-ago.md -->

# Status Server Monitor Time Ago

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-time-ago-001 | just-now-bucket | `timeAgo(iso, nowMs)` where `nowMs - new Date(iso).getTime() = 0` ms | Resolves `'just now'` — traced to `diffSecs < 60`; the given source tree has no dedicated test file for `timeAgo`, so every vector below is derived by reading `time-ago.ts` directly |
| status-server-monitor-time-ago-002 | just-now-bucket | `nowMs` set so `diffSecs = 59` | Resolves `'just now'` — the upper edge of the just-now bucket |
| status-server-monitor-time-ago-003 | minutes-bucket, bucket-evaluation-order | `nowMs` set so `diffSecs = 60` (`diffMins = 1`) | Resolves `'1m'` — the just-now/minutes boundary |
| status-server-monitor-time-ago-004 | minutes-bucket | `nowMs` set so `diffSecs = 3599` (`diffMins = 59`) | Resolves `'59m'` — the upper edge of the minutes bucket |
| status-server-monitor-time-ago-005 | hours-bucket, bucket-evaluation-order | `nowMs` set so `diffSecs = 3600` (`diffMins = 60`, `diffHours = 1`) | Resolves `'1h'` — the minutes/hours boundary |
| status-server-monitor-time-ago-006 | hours-bucket | `nowMs` set so `diffHours = 23` | Resolves `'23h'` — the upper edge of the hours bucket |
| status-server-monitor-time-ago-007 | days-bucket, bucket-evaluation-order | `nowMs` set so `diffHours = 24` | Resolves `'1d'` — the hours/days boundary |
| status-server-monitor-time-ago-008 | days-bucket | `nowMs` set so `diffHours = 240` (10 days) | Resolves `'10d'` — demonstrates the days bucket's lack of a week/month/year rollover |
| status-server-monitor-time-ago-009 | just-now-bucket | `iso` set 5 minutes after `nowMs` (`diffSecs = -300`) | Resolves `'just now'` — traced to the unconditional `diffSecs < 60` comparison, which is also true for every negative value |
| status-server-monitor-time-ago-010 | no-iso-validation | `timeAgo('not-a-date', Date.now())` | Resolves the literal string `'NaNd'` — traced to `new Date('not-a-date').getTime()` returning `NaN`, which propagates through every comparison as `false` until the final branch; per `no-iso-validation` |
| status-server-monitor-time-ago-011 | synchronous-purity, no-throw-on-well-formed-input | Call `timeAgo` for every input in vectors 001–010 with global `Date.now`, `console.*`, and `fetch` spied | Zero recorded calls on any spy across all eleven calls; none of the eleven calls throws |
