<!-- leaf: implement-status-server-monitor-1/probe · source: status-server-monitor-probe.md -->

**Rules** (cite as `implement-status-server-monitor-1/probe#<slug>`):

- `health-probe-concurrency-constant` MUST
- `probe-body-max-bytes-constant` MUST
- `probe-options-shape` MUST
- `probe-result-shape` MUST
- `probe-never-rejects` MUST
- `dns-check-toggles-default-true` MUST
- `dns-check-record-order` MUST
- `dns-all-disabled-skips-check` MUST
- `dns-no-match-is-down` MUST
- `dns-timeout-fails-fast` MUST
- `dns-failure-short-circuits-http` MUST
- `hostname-parse-failure-skips-dns` MUST
- `http-request-shape` MUST
- `response-time-excludes-dns` MUST
- `whole-leg-timeout` MUST
- `body-read-conditional` MUST
- `capped-read-stops-at-limit` MUST
- `body-read-error-not-fatal` MUST
- `body-abort-error-rethrown` MUST
- `body-truncation-annotates-marker-error` MUST
- `classification-delegated-to-health-module` MUST
- `down-error-message-selection` MUST
- `non-down-error-is-null` MUST
- `fetch-failure-timeout-classification` MUST
- `timeout-handle-always-cleared` MUST
- `bounded-concurrency-probing` MUST
- `result-order-preserved` MUST
- `per-probe-independence` MUST

# Status Server Monitor Probe

## Overview

`probe.ts` (`packages/web/packages/status-server/src/monitor/probe.ts`) is, per its own header comment, "the live HTTP/DNS probe — the single source of truth for 'is this endpoint up right now'." It exports `HEALTH_PROBE_CONCURRENCY` (`24`), `PROBE_BODY_MAX_BYTES` (`256 * 1024`), the `ProbeOptions` and `Probe` interfaces, and the two functions `probe` and `probeEndpoints`. For one `ConfiguredEndpoint` (`storage/ports.ts`, imported type-only so this file pulls in no database code), `probe` first resolves the endpoint's hostname over DNS, then issues one `GET` request under a single whole-leg deadline, optionally reads a capped slice of the body, and hands the outcome to `classify` (`health.ts`) for the `healthy` / `degraded` / `down` verdict. `probeEndpoints` fans this out across many endpoints through `mapLimit` (`@agentic-toolkit/deploy-platform/util`) at a bounded concurrency. The header comment states why the type-only import matters: this file stays "free of any DB import so the status route can fall back to a live probe without pulling in the writer graph" — used both by the health sync (which persists results, in `sync.ts`, external to this file) and by the `/api/status` route's no-DB fallback (which returns probe results straight to the wallboard when the database is unreadable).

## Behavioral Requirements

### Exported Constants

- **health-probe-concurrency-constant**: `HEALTH_PROBE_CONCURRENCY` MUST be exported with the value `24`, and `probeEndpoints` MUST use this constant, not a separately hard-coded literal, as the concurrency limit passed to `mapLimit`.
- **probe-body-max-bytes-constant**: `PROBE_BODY_MAX_BYTES` MUST be exported with the value `256 * 1024` (`262144` bytes), and `probe` MUST pass this constant, not a separately hard-coded literal, as the cap to every capped body read it performs.

### Data Shapes

- **probe-options-shape**: `ProbeOptions` MUST accept the two optional fields `timeoutMs?: number` (the deadline for the whole HTTP leg — headers and body) and `dnsTimeoutMs?: number` (the deadline for DNS resolution).
- **probe-result-shape**: `Probe` MUST carry exactly the six fields `slug: string`, `status: HealthStatus`, `responseTimeMs: number | null`, `statusCode: number | null`, `error: string | null`, and `dnsOk: boolean`.
- **probe-never-rejects**: `probe(svc, opts)` MUST always resolve to a `Probe` value and MUST NOT reject its returned promise for a DNS failure, an HTTP error status, a fetch rejection, a timeout, or a body-read failure against the probed endpoint; the returned `status` and `error` fields communicate the outcome instead.

### DNS Resolution Step

- **dns-check-toggles-default-true**: `dnsChecksOf(svc)` MUST resolve each of `svc.dnsCheckA`, `svc.dnsCheckAaaa`, and `svc.dnsCheckCname` to `true` whenever the corresponding field is `undefined`, so an endpoint configured before the toggles existed keeps every record type enabled.
- **dns-check-record-order**: When at least one record-type check is enabled, `resolveDns` MUST query in this order — A (if enabled) via `dns.promises.resolve4`, then AAAA (if enabled) via `dns.promises.resolve6`, then CNAME (if enabled) via `dns.promises.resolveCname` — and MUST return `{ ok: true, error: null }` on the first query whose resolved array has at least one entry, without issuing any subsequent enabled query.
- **dns-all-disabled-skips-check**: When `dnsCheckA`, `dnsCheckAaaa`, and `dnsCheckCname` all resolve to `false`, `resolveDns` MUST return `{ ok: true, error: null }` immediately and MUST call none of `dns.promises.resolve4`, `dns.promises.resolve6`, or `dns.promises.resolveCname`.
- **dns-no-match-is-down**: When every enabled record-type query settles to an empty array (a rejected query is itself caught and treated as an empty array), `resolveDns` MUST return `{ ok: false, error: "does not resolve" }`.
- **dns-timeout-fails-fast**: `resolveDns` MUST race its lookups against a deadline of `dnsTimeoutMs` (default `DNS_TIMEOUT_MS`, `5_000`) milliseconds via `Promise.race`, and MUST resolve `{ ok: false, error: "resolution timed out" }` when that deadline elapses first, regardless of whether the underlying `dns.promises` calls ever settle on their own.
- **dns-failure-short-circuits-http**: `probe` MUST run the DNS check before attempting the HTTP fetch and, when `resolveDns` reports `ok: false`, MUST return immediately with `status: "down"`, `dnsOk: false`, `statusCode: null`, and `error` set to the literal string `"DNS: "` concatenated with the DNS failure's `error` message, without attempting the HTTP fetch at all.
- **hostname-parse-failure-skips-dns**: When `new URL(svc.url).hostname` throws (a malformed `svc.url`), `probe` MUST treat `hostname` as the empty string and MUST skip the DNS-resolution step entirely (the `if (hostname)` guard is false), proceeding directly to the HTTP fetch attempt against the unparsed `svc.url`.

### HTTP Probe Step

- **http-request-shape**: Once DNS has passed or was skipped, `probe` MUST issue exactly one `GET` request to `svc.url` carrying the header `User-Agent: AgenticDeveloperHubStatus/1.0` and the option `redirect: "follow"`.
- **response-time-excludes-dns**: The `responseTimeMs` reported for a completed HTTP attempt MUST be measured from immediately before the `fetch` call (`fetchStart`) to immediately after the response headers are available, excluding whatever time the preceding DNS-resolution step took.
- **whole-leg-timeout**: `probe` MUST abort the fetch — via an `AbortController` whose `signal` is passed to `fetch` — when `timeoutMs` (default `HEALTH_CHECK_TIMEOUT_MS` from `health.ts`, `10_000`) milliseconds elapse from the start of the HTTP attempt, and this single deadline MUST cover both the header wait and any body read performed against that same response.
- **body-read-conditional**: `probe` MUST read the response body, capped at `PROBE_BODY_MAX_BYTES` bytes, only when `svc.kind === "health"` or `svc.expectBody` is a non-`null` value; for every other request `probe` MUST instead cancel the response body stream (`res.body?.cancel()`) without reading it.
- **capped-read-stops-at-limit**: `readBodyCapped` MUST stop pulling chunks from the response body's reader once the accumulated byte total reaches `maxBytes`, and MUST always cancel the reader afterward (`reader.cancel()`), whether the cap was hit or the stream ended on its own, so the underlying socket returns to the pool either way.
- **body-read-error-not-fatal**: When the capped read fails mid-stream for a reason other than the abort signal firing, `probe` MUST treat the body as unreadable (`failed: true`), log the failure via `console.error` with the message prefix `[probe] body read failed after headers:`, and fall back to classifying the response by `statusCode` and `responseTimeMs` alone, rather than treating the read failure itself as a `"down"` outage.
- **body-abort-error-rethrown**: When the capped read's underlying `signal` (the same `AbortController` as `whole-leg-timeout`) is already aborted at the moment the read throws, `readBodyCapped` MUST rethrow that error rather than reporting it as a non-fatal read failure, so a body that never finishes arriving is classified as the same timeout outage as unresponsive headers.
- **body-truncation-annotates-marker-error**: When `svc.expectBody` is configured, the configured marker is not found in the body text, AND the capped read reached `PROBE_BODY_MAX_BYTES` before the stream ended (`truncated: true`), `probe`'s `error` field for that outcome MUST state that the body was truncated at the byte cap (expressed in KB, `Math.round(PROBE_BODY_MAX_BYTES / 1024)`) and that the marker may lie beyond it, rather than the plain "not found" message used when the body was read to completion.
- **classification-delegated-to-health-module**: `probe` MUST compute `status` by calling `classify` (`health.ts`) with `statusCode: res.status`, `responseTimeMs`, `expectedStatus: svc.expectedStatus`, `isHealthKind: svc.kind === "health"`, `bodyText` (only when the body was read and readable), and `bodyMarkerMissing`, and MUST use `classify`'s return value unchanged as `Probe.status`.
- **down-error-message-selection**: When `classify` returns `"down"`, `probe`'s `error` field MUST be the body-marker message (per body-truncation-annotates-marker-error, when applicable) if `bodyMarkerMissing` is `true` AND (`res.status < 300` OR `res.status === svc.expectedStatus`); otherwise `error` MUST be the literal string `"Unexpected status "` concatenated with `res.status`.
- **non-down-error-is-null**: When `classify` returns `"healthy"` or `"degraded"`, `probe`'s `error` field MUST be `null`.
- **fetch-failure-timeout-classification**: When the `fetch` call (including any body read performed under its signal) rejects, `probe` MUST return `status: "down"`, `statusCode: null`, and `dnsOk: true`; when the rejection is attributable to the timeout — `controller.signal.aborted` is `true`, OR the caught error's message contains `"abort"`, OR the elapsed time from `fetchStart` is greater than or equal to `timeoutMs` — `probe` MUST set `responseTimeMs` to `timeoutMs` and `error` to the string `` `Timeout after ${timeoutMs}ms` ``; otherwise it MUST set `responseTimeMs` to the actual elapsed time and `error` to the caught value's `message` when it is an `Error`, or the literal string `"Unknown error"` otherwise.
- **timeout-handle-always-cleared**: `probe` MUST clear the fetch-abort `setTimeout` handle in a `finally` block that runs whether the fetch attempt resolves or rejects, so no timer outlives the single `probe` call that created it.

### Concurrency and Ordering

- **bounded-concurrency-probing**: `probeEndpoints(endpoints)` MUST probe all `endpoints` through `mapLimit` at a concurrency limit of `HEALTH_PROBE_CONCURRENCY` (`24`), never running more than that many `probe` calls in flight at once regardless of how many `endpoints` are supplied.
- **result-order-preserved**: `probeEndpoints` MUST return its `Probe[]` result in the same order as the input `endpoints` array, regardless of the order in which the individual bounded `probe` calls settle.
- **per-probe-independence**: Each `probe` call MUST run independently of every other — one endpoint's DNS failure, HTTP error, timeout, or body-read failure MUST NOT alter the `status`, `error`, or timing recorded for any other endpoint's result.

