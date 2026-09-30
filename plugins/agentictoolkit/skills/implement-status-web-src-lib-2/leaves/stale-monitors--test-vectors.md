<!-- leaf: implement-status-web-src-lib-2/stale-monitors--test-vectors · source: status-web-src-lib-stale-monitors.md -->

# Stale Monitors

## Conformance Test Vectors

All vectors use `NOW = Date.parse("2026-06-26T00:00:00.000Z")` and a base service with `slug "ep1"`, `name "Site"`, `url "https://site.example.com"`, `environment "production"`, `status "down"`, `statusCode null`, `error "HTTP 500"`, `dnsOk true` and `downSince` 30 days before `NOW`, with the named fields overridden. Vectors 001 to 010 are traced to the assertions in `stale-monitors.test.ts`; 011 to 017 are traced to the function body.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stale-monitors-001 | select-down-only, row-slug, row-dns-ok, row-detail-error, row-age | Base service | One row: `slug "ep1"`, `dnsOk true`, `detail "HTTP 500"`, `ageMs` = 2 592 000 000 |
| stale-monitors-002 | select-dns-neutral, select-sort-order | `gone` (down 90 days, error "DNS: does not resolve"), `also-gone` (down 9 days), `alive` (healthy, `downSince null`); run once with `dnsOk false` and once with `dnsOk true` | Both runs return slugs `["gone", "also-gone"]` |
| stale-monitors-003 | row-dns-ok | Base service with `dnsOk false` | One row with `dnsOk false` |
| stale-monitors-004 | select-inclusive-threshold | Base service down 2 days | `[]` |
| stale-monitors-005 | select-down-only, select-requires-down-since | `h` healthy with `downSince null`; `d` degraded down 40 days; `x` down with `downSince null` | `[]` |
| stale-monitors-006 | select-non-finite-age | Base service with `downSince "not-a-date"` | `[]` |
| stale-monitors-007 | row-detail-status-code | Base service with `error null`, `statusCode 503` | One row with `detail "HTTP 503"` |
| stale-monitors-008 | select-sort-order | `newer` down 8 days, then `older` down 90 days | Slugs `["older", "newer"]` |
| stale-monitors-009 | stale-threshold-default | Read `STALE_MONITOR_MS` | 604 800 000 |
| stale-monitors-010 | select-inclusive-threshold, select-default-threshold | Base service down exactly 7 days; separately, down 6 days | One row; `[]` |
| stale-monitors-011 | row-detail-fallback | Base service with `error null`, `statusCode null` | One row with `detail "down"` |
| stale-monitors-012 | row-environment | Base service with `environment ""` | One row with `environment null` |
| stale-monitors-013 | select-empty-input | `selectStaleMonitors([], NOW)` | `[]` |
| stale-monitors-014 | select-requires-down-since | Base service with `downSince ""` | `[]` |
| stale-monitors-015 | select-signature, select-inclusive-threshold | Base service down 2 days, `thresholdMs` = 86 400 000 | One row with `ageMs` = 172 800 000 |
| stale-monitors-016 | row-projection, row-down-since, row-name-url | Base service | Row keys are exactly `slug, name, url, environment, detail, dnsOk, downSince, ageMs`; `downSince` equals the input string |
| stale-monitors-017 | select-no-mutation | Freeze the input array and each service, then call | No exception; input unchanged |
