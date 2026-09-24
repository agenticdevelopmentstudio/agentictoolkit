---
id: 1094926a-e89e-416d-aa62-8bfd42afa1b4
title: Status Server Monitor Probe
domain: agentictoolkit://recipes/status-server-monitor-probe
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The live DNS-then-HTTP probe for one configured endpoint — bounded-concurrency,
  capped-body, whole-leg-timeout — that health sync and the no-DB status fallback both use.
platforms:
- typescript
- web
tags:
- monitor
- probe
- dns
- http
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
related:
- agentictoolkit://recipes/status-server-monitor-health
- agentictoolkit://recipes/status-server-monitor-endpoint-kinds
references:
- packages/web/packages/status-server/src/monitor/probe.ts (agentictoolkit)
- packages/web/packages/status-server/test/probe.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/endpoint-kinds.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/util/map-limit.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a server-side DNS/HTTP probe function, not a visual component.

## States

Not applicable — this is a server-side DNS/HTTP probe function, not a visual component; the three verdicts a probe can settle into (`healthy`, `degraded`, `down`) are a return-value enumeration owned by `classify` (`health.ts`) and are specified above under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side DNS/HTTP probe function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-probe-001 | dns-check-toggles-default-true, classification-delegated-to-health-module | `probe(base)` where `base.url = 'https://example.com'`, `resolve4` mocked to `['93.184.216.34']`, `fetch` mocked to resolve `200 'ok'` | `status: 'healthy'`, `statusCode: 200`, `dnsOk: true`, `error: null`, `slug: 'svc'` — `probe.test.ts` › "classifies a healthy endpoint" |
| status-server-monitor-probe-002 | down-error-message-selection, classification-delegated-to-health-module | Same setup, `fetch` mocked to resolve `500 'err'` | `status: 'down'`, `statusCode: 500`, `dnsOk: true`, `error` containing `'500'` — `probe.test.ts` › "marks an endpoint down on a 500" |
| status-server-monitor-probe-003 | dns-check-record-order, dns-check-toggles-default-true | `resolve4`/`resolve6` mocked `[]`, `resolveCname` mocked `['cname.vercel-dns.com']`, every `dnsCheck*` left `undefined` (default all-on) | `dnsOk: true`, `status: 'healthy'` — `probe.test.ts` › "treats a CNAME-only host as resolvable when all record checks are on (default)" |
| status-server-monitor-probe-004 | dns-check-record-order, dns-no-match-is-down, dns-failure-short-circuits-http | `resolve4` mocked `[]`, `resolveCname` mocked `['cname.vercel-dns.com']`, `probe({ ...base, dnsCheckA: true, dnsCheckAaaa: false, dnsCheckCname: false })` | `status: 'down'`, `dnsOk: false`, `error` containing `'DNS'`; `resolveCname` and `resolve6` are never called — `probe.test.ts` › "fails DNS when only the enabled record types do not resolve" |
| status-server-monitor-probe-005 | dns-all-disabled-skips-check | `probe({ ...base, dnsCheckA: false, dnsCheckAaaa: false, dnsCheckCname: false })`, `fetch` mocked `200` | `resolve4`/`resolve6`/`resolveCname` never called; `dnsOk: true`, `status: 'healthy'` — `probe.test.ts` › "skips DNS resolution entirely when every record check is off" |
| status-server-monitor-probe-006 | hostname-parse-failure-skips-dns, fetch-failure-timeout-classification | `probe({ ...base, url: 'not a url' })`, DNS mocks unset (should not be called), `fetch` left to reject on the malformed URL | `resolve4`/`resolve6`/`resolveCname` never called (hostname parsed as `""`); `status: 'down'`, `dnsOk: true`, `error` equal to the thrown `TypeError`'s message — traced directly to the `try { hostname = new URL(svc.url).hostname } catch { hostname = "" }` guard |
| status-server-monitor-probe-007 | whole-leg-timeout, fetch-failure-timeout-classification, timeout-handle-always-cleared | `probe(base, { timeoutMs: 50 })`, `fetch` mocked to a promise that never settles on its own | After ~50ms: `status: 'down'`, `statusCode: null`, `responseTimeMs: 50`, `error: 'Timeout after 50ms'`, `dnsOk: true` — traced directly to `controller.signal.aborted` being `true` in the `catch` block |
| status-server-monitor-probe-008 | body-read-conditional, down-error-message-selection, classification-delegated-to-health-module | `probe({ ...base, kind: 'http', expectBody: 'OK-MARKER', expectedStatus: 200 })`, `fetch` mocked `200` with a short body `'nope'` (well under the cap) | `status: 'down'` (marker missing forces down via `classify`'s `bodyMarkerMissing` check); `error: 'expected content "OK-MARKER" not found in response'` (no truncation clause, since the read completed) — traced directly to the `markerError` ternary's non-truncated branch |
| status-server-monitor-probe-009 | body-truncation-annotates-marker-error, capped-read-stops-at-limit | Same setup as 008, but `fetch`'s body is a stream longer than `PROBE_BODY_MAX_BYTES` (`262144` bytes) that never contains `'OK-MARKER'` | `status: 'down'`; `error` containing `'body truncated'`, `'marker may lie beyond the cap'`, and `'256KB'` (`Math.round(262144 / 1024)`) — traced directly to the `markerError` ternary's truncated branch |
| status-server-monitor-probe-010 | body-read-conditional | `probe({ ...base, kind: 'http', expectBody: null })`, `fetch` mocked `200` with a `Response` whose `body` is a real (unread) stream | `res.body.cancel()` is called; `classify` is invoked with `bodyText: undefined` and `bodyMarkerMissing: false` — traced directly to the `isHealthKind \|\| expectBody` guard being false, taking the `else` branch |
| status-server-monitor-probe-011 | bounded-concurrency-probing, result-order-preserved, per-probe-independence | `probeEndpoints` called with 30 distinct `ConfiguredEndpoint` values (unique `slug`s), `fetch` mocked to track concurrently-in-flight call count and resolve `200` after a short delay | The tracked concurrent-in-flight count never exceeds `24`; the returned `Probe[]` has length `30` in the same order as the input array — traced directly to `mapLimit(endpoints, HEALTH_PROBE_CONCURRENCY, probe)` |

## Edge Cases

- **Null and empty input**: `svc.expectBody` of `undefined` or `null` MUST both be treated as "no marker configured" — the `expectBody` guard (`svc.expectBody ?? null`) and the later `expectBody != null` check both treat either value identically, so `body-read-conditional`'s marker branch is skipped for either — MUST. `svc.environment`, `svc.platform`, and `svc.deployProject` being `null` (all three are declared nullable on `ConfiguredEndpoint`) have no effect on `probe`'s behavior at all — none of the three is read anywhere in this file — MUST. An empty `endpoints` array passed to `probeEndpoints` MUST resolve `mapLimit`'s `Promise.all(Array.from({ length: Math.min(24, 0) }, worker))` (i.e., zero workers) immediately to `[]`, without ever calling `probe` — MUST.
- **Boundary values**: a response body that is exactly `PROBE_BODY_MAX_BYTES` bytes long, with nothing more waiting in the stream, MUST still be reported `truncated: true` — `readBodyCapped` sets `truncated = total >= maxBytes` unconditionally once the loop exits on the byte-count condition, with no separate check for whether `done` would have been `true` on the next read; this is a known over-report at the exact boundary, not a bug the recipe author is speculating about, and a port MUST reproduce it rather than "fixing" it to check for genuine truncation — MUST. `HEALTH_PROBE_CONCURRENCY` at `24` bounds `mapLimit`'s worker count via `Math.min(limit, items.length)`, so an `endpoints` array shorter than `24` MUST spawn exactly `endpoints.length` workers, never `24` idle ones — MUST.
- **Concurrent access**: Node's single-threaded event loop means no two `probe` calls ever execute JavaScript concurrently in the literal sense; `mapLimit`'s bounded worker loop is cooperative interleaving of `await`s, and each `probe` call owns its own `AbortController`, its own `setTimeout` handle, and its own local variables, with no module-level mutable state shared between calls — MUST NOT interleave in a way that lets one call's timer, controller, or result leak into another's. Two concurrent `probe` calls against the *same* `svc` (e.g. a scheduled tick overlapping a manual "check now") are not deduplicated or locked against each other anywhere in this file; each runs to its own independent `Probe` result, and the caller (`sync.ts`, external) is responsible for not issuing duplicate calls for the same endpoint within one cycle — MUST NOT be read as this file providing endpoint-level mutual exclusion.
- **Error states**: a DNS failure short-circuits to a `"down"` result before any HTTP attempt (`dns-failure-short-circuits-http`) — MUST. An HTTP status that is neither 2xx nor `expectedStatus` classifies `"down"` via `classify`, with `error` set from `res.status` (`down-error-message-selection`) — MUST. A `fetch` rejection (network error, TLS failure, or the whole-leg timeout) is caught and converted into a `"down"` `Probe` with a message distinguishing "Timeout after Nms" from the underlying error's own message (`fetch-failure-timeout-classification`) — MUST. A body-read failure that is not the timeout/abort itself is logged via `console.error` and does NOT itself force `"down"` — it degrades to a status-code-only classification (`body-read-error-not-fatal`) — MUST. No error path in this file allows an exception to propagate out of `probe` uncaught; the only `throw` inside `readBodyCapped` (the abort-signal rethrow) is itself caught by `probe`'s own outer `try`/`catch` — MUST.
- **Offline / disconnected state**: connectivity loss before the DNS query settles is bounded by `dns-timeout-fails-fast`'s `Promise.race` against `dnsTimeoutMs`, so a black-holed resolver fails that probe rather than holding its concurrency slot hostage (per the source's own comment on `DNS_TIMEOUT_MS`) — MUST. Connectivity loss before HTTP headers arrive, or mid-body, is bounded by the single `whole-leg-timeout` `AbortController`, which the source's own comment says was widened from a headers-only deadline specifically because a server that answers instantly and then trickles its body forever "hang[s] the probe past every cycle budget" — MUST. A resolver or server that answers but the connection drops mid-body-read (neither a clean end-of-stream nor the abort firing) is the `body-read-error-not-fatal` path: reported via `console.error`, classified by status code alone — MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.timeoutMs` | `number` | `HEALTH_CHECK_TIMEOUT_MS` (`10_000`, from `health.ts`) | Deadline, in milliseconds, for the whole HTTP leg of one `probe` call — headers and any body read. |
| `opts.dnsTimeoutMs` | `number` | `DNS_TIMEOUT_MS` (`5_000`, private to this file — not exported) | Deadline, in milliseconds, for the DNS-resolution step of one `probe` call. |
| `svc.url` | `string` | none — required | The endpoint URL `probe` issues its `GET` request against, and the source `new URL(...)` parses for the DNS-resolution hostname. |
| `svc.kind` | `string` | none — required | When exactly `"health"`, gates the JSON-body status check inside `classify` and forces a capped body read even without `expectBody` set. |
| `svc.expectedStatus` | `number` | none — required | The status code `classify` treats as acceptable even when it is not itself a 2xx response. |
| `svc.expectBody` | `string \| null \| undefined` | `null`/`undefined` (no marker check) | An optional content marker; when set, `probe` reads and searches the capped body for this substring. |
| `svc.dnsCheckA` / `svc.dnsCheckAaaa` / `svc.dnsCheckCname` | `boolean \| undefined` | `true` (via `??`) for each | Per-endpoint toggles for which DNS record types `resolveDns` queries; all three `false` skips the DNS step entirely. |
| `HEALTH_PROBE_CONCURRENCY` (exported module constant) | `number` | `24` | The concurrency limit `probeEndpoints` passes to `mapLimit`; not overridable by a caller of `probeEndpoints`. |
| `PROBE_BODY_MAX_BYTES` (exported module constant) | `number` | `262144` (`256 * 1024`) | The byte cap `probe` passes to every capped body read it performs; not overridable by a caller of `probe`. |

## Deep Linking

Not applicable: this file defines no application route or URL pattern of its own — `svc.url` is an operator-configured probe target it fetches, not a deep-link target this file defines or resolves.

## Localization

This file's `error` strings are hardcoded English and are the exact text surfaced to operators through the health sync and the `/api/status` no-DB fallback (per the Overview); none of them route through a localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `DNS: <reason>` | `error` when `resolveDns` reports `ok: false` (`dns-failure-short-circuits-http`); `<reason>` is `"does not resolve"` or `"resolution timed out"` |
| n/a | `Unexpected status <code>` | `error` when `classify` returns `"down"` and the marker-missing branch does not apply (`down-error-message-selection`) |
| n/a | `expected content "<marker>" not found in response` | `error` when the configured `expectBody` marker is missing and the body was read to completion |
| n/a | `expected content "<marker>" not found in the first <N>KB (body truncated — marker may lie beyond the cap)` | `error` when the marker is missing and the capped read was truncated (`body-truncation-annotates-marker-error`) |
| n/a | `Timeout after <ms>ms` | `error` when the fetch attempt is classified as the whole-leg timeout (`fetch-failure-timeout-classification`) |
| n/a | `Unknown error` | `error` fallback when a caught fetch rejection is not an `Error` instance |
| n/a | `[probe] body read failed after headers: <message>` | `console.error` line for a non-abort mid-stream body-read failure (`body-read-error-not-fatal`) |

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; the per-endpoint `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname` toggles documented under Configuration are stored, per-endpoint operator settings, not a global feature flag lookup.

## Analytics

Not applicable: this file emits no analytics or usage-telemetry event of its own describing its execution; its `Probe` results are consumed by callers (health sync persistence, the status wallboard fallback) that are external to this file.

## Privacy

- **Data collected**: this file's only externally-supplied input is `svc: ConfiguredEndpoint` (an operator-configured probe target — URL, expected status, optional body marker, DNS-check toggles) and the two optional `ProbeOptions` deadlines; it collects nothing about the requester or any end user.
- **Storage**: none. `probe` and `probeEndpoints` hold no state between calls and write nothing themselves; persisting a `Probe` result is the caller's concern (`sync.ts`, external to this file).
- **Transmission**: `probe` sends one outbound `GET` request, carrying the fixed `User-Agent: AgenticDeveloperHubStatus/1.0` header, to whatever `svc.url` the operator configured, and issues DNS queries against the process's configured resolver for `svc.url`'s hostname. No credential, token, or end-user data is attached to either.
- **Retention**: not applicable — this file holds no data across calls to retain; retention of persisted probe history is `sync.ts`'s concern, external to this file.

## Logging

This file uses one plain `console.error` call with a literal `[probe]` message prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A capped body read fails mid-stream for a reason other than the timeout/abort signal firing | error (`console.error`) | `[probe] body read failed after headers: <message>` |

This is the only log line this file emits directly; every other outcome (DNS failure, HTTP error status, timeout, marker mismatch) is communicated purely through the returned `Probe` value, with no log call of its own.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `Probe` as a `Sendable struct` mirroring the six fields, `ProbeOptions` as a `Sendable struct` with two `Optional<Double>`-or-`Int` fields, and `probe`/`probeEndpoints` as non-isolated `async` functions; the DNS step becomes `resolveDns`-equivalent logic layered over `Network.framework`'s `NWEndpoint`/`NWParameters` DNS resolution or a raw `getaddrinfo` call for A/AAAA, with CNAME resolution requiring a lower-level DNS query (Apple's high-level APIs do not expose CNAME chains directly) — a genuine platform capability gap relative to Node's `dns.promises.resolveCname`, worth flagging during the port rather than silently dropping the CNAME check.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `probe`/`probeEndpoints` as `suspend fun`s, `Probe`/`ProbeOptions` as `data class`es, uses `withTimeoutOrNull`/`withTimeout` in place of the source's `AbortController`+`setTimeout` pair for the whole-leg deadline, and a bounded `Semaphore(24)` (or a fixed-size coroutine dispatcher) in place of `mapLimit` for `HEALTH_PROBE_CONCURRENCY`; DNS resolution goes through `java.net.InetAddress` for A/AAAA, with CNAME again requiring a dedicated DNS-record library since the JDK's built-in resolver does not expose it.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/probe.ts` as a plain ESM module on the Node status backend, importing `node:dns`'s `promises` API for DNS, the global `fetch`/`AbortController`/`Response` for HTTP, and `mapLimit` from the sibling `deploy-platform` package for bounded concurrency; it is imported by `sync.ts` (persisted health sync) and, per its own header comment, by the `/api/status` route's no-DB fallback, and is unit-tested directly by `probe.test.ts` with `node:dns` mocked via `vi.mock`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern applies. A macOS agent embedding this pattern (e.g. a background monitoring daemon) would use `URLSession` with a per-request `timeoutInterval` for the whole-leg deadline and `URLSession`'s own `dataTask` cancellation in place of `AbortController`, plus the same `Network.framework`/`getaddrinfo` DNS caveat noted under SwiftUI.
- **WinUI 3**: a .NET port models `Probe` as a `readonly record struct` with the six fields (`string`, a `HealthStatus` enum, `int?`, `int?`, `string?`, `bool`) and `ProbeOptions` as a `record` with two `int?` fields, with `ProbeAsync`/`ProbeEndpointsAsync` as `static async Task<T>` methods. `HttpClient` with a `CancellationTokenSource(timeoutMs)` replaces `fetch`+`AbortController` for the whole-leg deadline, covering both the header wait and a capped `Stream.CopyToAsync`-based body read (mirroring `readBodyCapped`'s byte-count cap and its "cancel the rest of the stream either way" contract) in place of the source's `ReadableStreamDefaultReader`. DNS resolution uses `System.Net.Dns.GetHostAddressesAsync` filtered by `AddressFamily.InterNetwork`/`InterNetworkV6` for the A/AAAA checks; .NET's `Dns` class exposes no CNAME lookup, so the CNAME check requires a third-party DNS library (e.g. one built on `System.Net.DnsClient` conventions) or a raw UDP query — the same platform gap noted under SwiftUI and Compose. Bounded concurrency for `ProbeEndpointsAsync` uses a `SemaphoreSlim(24, 24)` guarding a `Task.WhenAll` over per-endpoint `Task`s, writing into a pre-sized `Probe[]` by index (not `ConcurrentBag`) to reproduce `mapLimit`'s order-preserving guarantee. `System.Text.Json` is not needed by this file itself — the JSON body check lives in the `classify` port (`health.ts`, external to this recipe's given source), not in `probe.ts`. `ObservableCollection`/`INotifyPropertyChanged` do not apply: this file has no UI-bound state to expose; those types belong to a WinUI 3 dashboard view model consuming `Probe` results, not to the probe itself.

## Design Decisions

- **Decision**: bound `probeEndpoints`'s fan-out to `HEALTH_PROBE_CONCURRENCY = 24` rather than probing every endpoint at once.
  **Rationale**: stated directly in the source's own comment — an unbounded fan-out "saturates Node's getaddrinfo threadpool (4 threads) and socket pool," which inflated every site's measured response time into a uniform ~2s band and tripped the degraded threshold for sites that actually answer in under 300ms. `24` is chosen against two limits at once: low enough that DNS queue depth (~24/4 = 6) stays well under the saturation point, yet high enough that a wide outage (many endpoints hanging to the full `HEALTH_CHECK_TIMEOUT_MS`) still finishes inside the calling route's `maxDuration` (60s): the comment computes "~134 endpoints × 10s / 24 ≈ 56s," versus ~67s (and a platform kill) at the previous value of `20`.
  **Approved**: pending
- **Decision**: cap every body read at `PROBE_BODY_MAX_BYTES` (`256 * 1024` bytes) and always cancel the remainder of the stream, whether the cap was hit or not.
  **Rationale**: stated directly in the source's own comment — "the health JSON and expectBody markers live in the first bytes... [w]ithout a cap, classifying 'read the whole body' lets one endless/huge response drain forever inside the cycle." Always cancelling (`capped-read-stops-at-limit`) returns the socket to the pool instead of leaving it idling half-open.
  **Approved**: pending
- **Decision**: make the whole-leg timeout cover both headers and the body read, rather than clearing the deadline once headers arrive.
  **Rationale**: stated directly in the source's own comment — clearing the deadline at headers "once let a server that answers instantly and then trickles its body forever hang the probe past every cycle budget: the worker got terminated every tick, `/health` went stale, and the supervisor restart-looped the container — one bad endpoint taking down the monitor."
  **Approved**: pending
- **Decision**: measure `responseTimeMs` only across the HTTP leg (`fetchStart` to header arrival), excluding the preceding DNS-resolution step.
  **Rationale**: stated directly in the source's own comment — "'response time' should mean how long the *site* took to answer, not how long our checker spent resolving the name."
  **Approved**: pending
- **Decision**: report a mid-stream body-read failure via `console.error` and a status-code-only fallback classification, rather than treating it as a `"down"` outage.
  **Rationale**: stated directly in the source's own comment — "the server already answered with headers, so a broken body is not evidence the site is down — and since HTTP issues carry no debounce, letting it hard-fail would open an issue (and page on-call) off one connection blip."
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |

`unit-test-coverage` is `partial`: `probe.test.ts` gives `probe` five assertions covering a healthy 2xx, a 5xx, a CNAME-only default-on resolution, a narrowed DNS-check-type failure, and every DNS check disabled — but it exercises none of the HTTP-body path (`expectBody`, the truncation-annotated marker error, the `isHealthKind` JSON-body branch reached through `classify`), none of the whole-leg timeout or fetch-rejection branch, none of the malformed-`svc.url` hostname-parse-failure path, and no test targets `probeEndpoints`'s bounded concurrency or order-preservation at all. `separation-of-concerns` passes: this file's only responsibility is producing one `Probe` result per endpoint; it delegates the verdict computation to `classify` (`health.ts`, external) and performs no persistence of its own, per the header comment's explicit design goal of staying "free of any DB import." `explicit-error-handling` passes: every failure path this file can take — DNS failure, non-2xx status, fetch rejection, timeout, body-read failure — is caught explicitly and converted into a documented field on the returned `Probe`, with no unhandled promise rejection or silently dropped error anywhere in the file. `timeout-handling` passes: both the DNS step and the HTTP step are bounded by explicit, configurable deadlines (`dnsTimeoutMs`, `timeoutMs`), each defaulting to a named constant, with the fetch-timeout handle explicitly cleared in a `finally` block. `fault-tolerance` passes: a malformed `svc.url`, an unreachable host, a black-holed DNS resolver, a huge or endless response body, and a body that fails mid-read are all absorbed into a `"down"` (or degraded/healthy, as appropriate) `Probe` result rather than crashing the caller or leaving a promise unsettled. `timeout-configuration` (Access Patterns) passes: every network request this file issues — the DNS lookup and the HTTP fetch — has an explicit, caller-overridable timeout; none can wait indefinitely. `retry-with-backoff` (Access Patterns) is `failed`, stated plainly rather than smoothed over: this file makes exactly one DNS attempt and one HTTP attempt per `probe` call, with no retry, no backoff, and no jitter of any kind on either leg; a single transient DNS hiccup or connection reset is reported as `"down"` for that cycle with no attempt to retry within the same call — the next scheduled monitor cycle (external to this file, in `sync.ts`/the scheduler) is the only retry this design provides.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
