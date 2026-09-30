<!-- leaf: implement-status-web-src-lib-2/time-ago--test-vectors · source: status-web-src-lib-time-ago.md -->

# Status Web Time Ago

## Conformance Test Vectors

`BASE` is `new Date("2024-06-01T12:00:00Z").getTime()`, as in `time-ago.test.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-time-ago-001 | just-now-bucket | `iso` = `BASE - 30000` as ISO, `nowMs` = `BASE` | `just now` (test "returns just now for less than 60 seconds") |
| status-web-time-ago-002 | just-now-bucket | `iso` = `BASE` as ISO, `nowMs` = `BASE` | `just now` (test "exactly 0 seconds") |
| status-web-time-ago-003 | minutes-bucket, bucket-evaluation-order | `iso` = `BASE - 60000`, `nowMs` = `BASE` | `1m` (test "boundary: exactly 60s") |
| status-web-time-ago-004 | minutes-bucket | `iso` = `BASE - 12 * 60000`, `nowMs` = `BASE` | `12m` (test "less than 1 hour") |
| status-web-time-ago-005 | hours-bucket, bucket-evaluation-order | `iso` = `BASE - 60 * 60000`, `nowMs` = `BASE` | `1h` (test "boundary: exactly 60 minutes") |
| status-web-time-ago-006 | hours-bucket | `iso` = `BASE - 3 * 3600000`, `nowMs` = `BASE` | `3h` (test "less than 1 day") |
| status-web-time-ago-007 | days-bucket, bucket-evaluation-order | `iso` = `BASE - 24 * 3600000`, `nowMs` = `BASE` | `1d` (test "boundary: exactly 24 hours") |
| status-web-time-ago-008 | days-bucket | `iso` = `BASE - 2 * 86400000`, `nowMs` = `BASE` | `2d` (test "1 day or more") |
| status-web-time-ago-009 | just-now-bucket | `iso` = `BASE - 59999`, `nowMs` = `BASE` | `just now` (upper edge; derived from `diffSecs < 60`) |
| status-web-time-ago-010 | minutes-bucket | `iso` = `BASE - 3599000`, `nowMs` = `BASE` | `59m` (derived from source) |
| status-web-time-ago-011 | hours-bucket | `iso` = `BASE - 86399000`, `nowMs` = `BASE` | `23h` (derived from source) |
| status-web-time-ago-012 | days-unbounded | `iso` = `BASE - 365 * 86400000`, `nowMs` = `BASE` | `365d`, no larger unit (derived from source) |
| status-web-time-ago-013 | just-now-bucket | `iso` = `BASE + 300000` (5 minutes in the future), `nowMs` = `BASE` | `just now` (negative `diffSecs`; derived from source) |
| status-web-time-ago-014 | iso-precondition, no-throw | `iso` = `not-a-date`, `nowMs` = `BASE` | `NaNd`, no exception (derived from source) |
| status-web-time-ago-015 | iso-precondition, no-throw | `iso` = empty string, `nowMs` = `BASE` | `NaNd`, no exception (`new Date("")` is invalid) |
| status-web-time-ago-016 | caller-supplied-clock, synchronous-purity, no-suffix-composition | Call vectors 001-008 with `Date.now` and `console` spied | Zero spy calls; every result matches exactly, with no trailing `ago` or space |
