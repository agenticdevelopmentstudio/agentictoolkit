<!-- leaf: implement-status-server-monitor-1/heartbeat · source: status-server-monitor-heartbeat.md -->

**Rules** (cite as `implement-status-server-monitor-1/heartbeat#<slug>`):

- `noop-null-or-empty-url` MUST
- `single-get-request` MUST
- `user-agent-header` MUST
- `bounded-timeout-5000ms` MUST
- `non-2xx-logged-not-thrown` MUST
- `network-failure-logged-not-thrown` MUST
- `always-resolves-undefined` MUST
- `caller-supplied-url-no-default-no-env-read` MUST
- `independent-per-call-no-shared-state` MUST

# Status Server Monitor Heartbeat

## Overview

`heartbeat.ts` (`packages/web/packages/status-server/src/monitor/heartbeat.ts`) exports one function, `pingHeartbeat`, the status backend's dead-man's-switch check-in. Its own header comment states the problem it exists to fix: every layer of the self-healing chain — the cycle watchdog, worker terminate/respawn, supervisor health-watch, Railway's restart policy — lives INSIDE the container, so when the container itself dies (a volume failure, a platform outage, Railway's `restartPolicyMaxRetries` exhausted) nothing tells anyone; the monitor that watches everything has no watcher of its own. The fix is push-based rather than pull-based: after every successful FULL sync, `pingHeartbeat` issues one bounded GET to a caller-supplied `url` (a healthchecks.io-style check-in endpoint). The external service alerts on a MISSED ping, which is the one failure mode no in-container code could ever report on its own behalf. Its sole caller, `cycle-runner.ts`'s `runMonitorCycle`, invokes it as the last step of the full-sync phase, passing `config.heartbeatUrl`; `pingHeartbeat` itself takes no default for that value and reads no environment variable directly.

## Behavioral Requirements

### Dead-Man Check-In (`pingHeartbeat`)

- **noop-null-or-empty-url**: `pingHeartbeat` MUST return immediately, performing no network call, when `url` is `null` or an empty string — any value the `if (!url) return;` guard treats as falsy.
- **single-get-request**: When `url` is a non-empty string, `pingHeartbeat` MUST issue exactly one HTTP GET request to `url`, never more than one request and never a different HTTP method.
- **user-agent-header**: The GET request MUST set the header `User-Agent` to the literal value `AgenticDeveloperHubStatus/1.0`.
- **bounded-timeout-5000ms**: The GET request MUST carry a deadline of 5,000 milliseconds (`HEARTBEAT_TIMEOUT_MS`), enforced by passing `AbortSignal.timeout(HEARTBEAT_TIMEOUT_MS)` as the request's `signal`.
- **non-2xx-logged-not-thrown**: MUST log via `console.error` when the resolved `Response`'s `ok` flag is `false`, with the message `[heartbeat] check-in URL answered <status> — the dead-man ping is NOT registering; verify HEARTBEAT_URL` where `<status>` is the numeric `res.status`; MUST NOT throw, reject, or retry for this condition.
- **network-failure-logged-not-thrown**: MUST catch a rejected `fetch` call — a network-level failure or the 5,000ms `AbortSignal.timeout` deadline firing — and log via `console.error` with the message `[heartbeat] ping failed: <message>`, where `<message>` is the caught value's `message` property when it is an `Error` instance, else the caught value coerced with `String(err)`; MUST NOT rethrow or leave the returned promise rejected.
- **always-resolves-undefined**: `pingHeartbeat` MUST resolve to `undefined` and MUST NOT reject, under every input and outcome this file can produce: a `null`/empty `url`, a successful `2xx` response, a non-2xx response, or a network failure or timeout.
- **caller-supplied-url-no-default-no-env-read**: `pingHeartbeat` MUST take `url` as its only parameter and MUST apply no default value of its own when a caller has one to supply; per the function's own doc comment, `url` is `config.heartbeatUrl`, and the module MUST NOT read `HEARTBEAT_URL` or any other environment variable directly — enabling or disabling the feature, and choosing the endpoint, are entirely the caller's decision.
- **independent-per-call-no-shared-state**: Each call to `pingHeartbeat` MUST perform its own independent fetch with no queue, cache, debounce, or de-duplication shared with any other call; the module holds no mutable state beyond the `HEARTBEAT_TIMEOUT_MS` constant, so concurrent or repeated calls MUST NOT interact with, block, or influence one another's outcome or logging.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` (parameter to `pingHeartbeat`) | `string \| null` | none — caller-supplied, required | The check-in URL to ping. `null` or an empty string disables the feature entirely for that call. This file never reads an environment variable itself. |
| `HEARTBEAT_URL` | environment variable, read by `config/env.ts`'s `heartbeatUrl` getter (external to this file) | unset → `null` | The environment variable the shipped `StatusConfig` implementation reads (via `optional(env.HEARTBEAT_URL)`) to produce the `url` value that `cycle-runner.ts`'s `runMonitorCycle` (external to this file) passes into `pingHeartbeat` as `config.heartbeatUrl`. |
| `HEARTBEAT_TIMEOUT_MS` (module constant) | `number` | `5_000` | Fixed per-request deadline via `AbortSignal.timeout`; not configurable per call and has no environment override in this file. |

## Localization

None of this file's user-facing strings route through a localization mechanism; both `console.error` messages are hardcoded English literals interpolated directly in `pingHeartbeat`. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse — and because these are operator-facing diagnostic lines (surfaced wherever the container's stderr is collected), they are genuinely user-facing, not internal-only.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `[heartbeat] check-in URL answered <status> — the dead-man ping is NOT registering; verify HEARTBEAT_URL` | `console.error` when the response's `ok` flag is `false` |
| n/a | `[heartbeat] ping failed: <message>` | `console.error` when the `fetch` call rejects (network failure or timeout) |

## Privacy

- **Data collected**: none of this file's own data. `url` is an opaque, potentially secret-bearing check-in endpoint (a healthchecks.io-style path) supplied by the caller; this file transmits no request body, no cookie, and no credential of any kind in the GET it issues — only the `User-Agent` header and whatever query/path segments are already baked into `url` itself.
- **Storage**: none. `pingHeartbeat` persists nothing to disk or a database; the module's only piece of state is the `HEARTBEAT_TIMEOUT_MS` constant.
- **Transmission**: exactly one outbound GET per call, to the caller-supplied `url`, with no body. Neither `console.error` message ever includes `url` itself — the non-2xx message names only the numeric status, and the failure message names only the caught error's text — so a check-in URL is never written to this file's own log output.
- **Retention**: not applicable — this file keeps no record of a ping after the call that made it resolves; there is no history or count of past pings anywhere in this module.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern would model `pingHeartbeat` as a free `async` function (or an `actor` method if it needed to coordinate with other state, which it does not here) taking a `URL?` and returning `Void`, built on `URLSession.shared.data(for:)` with the request's `timeoutInterval` set to `5`; `URLSession`'s own timeout-to-`URLError` mapping plays the role `AbortSignal.timeout` plays here, and both the non-2xx `HTTPURLResponse.statusCode` check and the `catch` block's logging translate directly.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the function as a `suspend fun pingHeartbeat(url: String?)` over OkHttp or Ktor, wrapping the call in `withTimeout(5_000)` (or the client's own per-call timeout config) and a `try`/`catch` that logs exactly like the source rather than propagating; there is no shared/module state to port, since Kotlin has no equivalent of a per-`Worker` module instance the way this pattern's sibling (`alerts.ts`) needs to account for.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/heartbeat.ts` as a single exported function on the Node status backend — not client-side React, and no framework dependency of its own beyond global `fetch` and `AbortSignal.timeout`. Its one real caller, `cycle-runner.ts`'s `runMonitorCycle`, runs it inside the monitor's own `Worker` thread (see `worker.ts`), but because this file holds no module-level state, the per-`Worker`-instance module-duplication concern documented on its sibling `alerts.ts` does not apply here — every call is independent regardless of which thread makes it.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no framework-specific concern beyond what SwiftUI's bullet already covers — the check-in call itself is `URLSession`-level, not view-layer.
- **WinUI 3**: a .NET port models `pingHeartbeat` as `async Task PingHeartbeatAsync(string? url)`, returning immediately when `url` is `null` or empty (mirroring `if (!url) return;`), then issuing one `HttpClient.GetAsync(url, cts.Token)` call with a `CancellationTokenSource(TimeSpan.FromSeconds(5))` as the `AbortSignal.timeout` analogue and a `User-Agent` header set via `HttpRequestMessage.Headers.UserAgent` (or `DefaultRequestHeaders` on a shared `HttpClient`) to the same literal `AgenticDeveloperHubStatus/1.0` value. The whole call sits inside a `try`/`catch (Exception ex)` that logs via `ILogger.LogError` (the `explicit-error-handling`/fail-soft shape, not a `throw`), and a resolved-but-non-2xx `HttpResponseMessage.IsSuccessStatusCode == false` gets its own `LogError` branch mirroring `non-2xx-logged-not-thrown` — `HttpClient.GetAsync` does not throw on a non-2xx status by default, so that check needs to be written explicitly, exactly as the TypeScript source writes it. No `ObservableCollection`/`INotifyPropertyChanged` apply: this function has no UI-bound state of its own to expose.

