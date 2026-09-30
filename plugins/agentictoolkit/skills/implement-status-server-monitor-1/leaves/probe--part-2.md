<!-- leaf: implement-status-server-monitor-1/probe--part-2 · source: status-server-monitor-probe.md -->

# Status Server Monitor Probe — continued (part 2)

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

## Privacy

- **Data collected**: this file's only externally-supplied input is `svc: ConfiguredEndpoint` (an operator-configured probe target — URL, expected status, optional body marker, DNS-check toggles) and the two optional `ProbeOptions` deadlines; it collects nothing about the requester or any end user.
- **Storage**: none. `probe` and `probeEndpoints` hold no state between calls and write nothing themselves; persisting a `Probe` result is the caller's concern (`sync.ts`, external to this file).
- **Transmission**: `probe` sends one outbound `GET` request, carrying the fixed `User-Agent: AgenticDeveloperHubStatus/1.0` header, to whatever `svc.url` the operator configured, and issues DNS queries against the process's configured resolver for `svc.url`'s hostname. No credential, token, or end-user data is attached to either.
- **Retention**: not applicable — this file holds no data across calls to retain; retention of persisted probe history is `sync.ts`'s concern, external to this file.

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
