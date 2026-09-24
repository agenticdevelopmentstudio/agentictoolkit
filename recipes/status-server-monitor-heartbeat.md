---
id: dddf0162-9d32-45a4-86a8-7e2d1b313d41
title: Status Server Monitor Heartbeat
domain: agentictoolkit://recipes/status-server-monitor-heartbeat
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Dead-man's-switch check-in: GETs an external monitor URL after every successful full sync, fail-soft and bounded, so a dead container is caught by an outside watcher."
platforms:
- typescript
- web
tags:
- monitor
- heartbeat
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/observability/logging
related:
- agentictoolkit://recipes/status-server-monitor-cycle-runner
- agentictoolkit://recipes/status-server-monitor-alerts
references:
- packages/web/packages/status-server/src/monitor/heartbeat.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/env.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/heartbeat.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a server-side dead-man's-switch check-in function, not a visual component.

## States

Not applicable — this is a server-side dead-man's-switch check-in function, not a visual component; its only runtime outcomes (no-op, successful ping, non-2xx ping, network failure) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side dead-man's-switch check-in function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-heartbeat-001 | noop-null-or-empty-url, always-resolves-undefined | `fetch` stubbed to `throw new Error('down')`; `await pingHeartbeat(null)` | No `fetch` call is made; the call resolves `undefined` — `heartbeat.int.test.ts` › "is a no-op without a url and fail-soft on network errors" (first assertion) |
| status-server-monitor-heartbeat-002 | noop-null-or-empty-url | `fetch` stubbed to `throw new Error('down')`; `await pingHeartbeat('')` | No `fetch` call is made — not directly asserted by `heartbeat.int.test.ts`, traced to the `if (!url) return;` guard treating an empty string identically to `null` |
| status-server-monitor-heartbeat-003 | single-get-request, user-agent-header | `fetch` stubbed to resolve `new Response('ok')` and record its arguments; `await pingHeartbeat('https://hc.example.com/ping/abc')` | `fetch` is called exactly once; the first argument, stringified, is `'https://hc.example.com/ping/abc'`; the second argument's `method` is `'GET'` and its `headers['User-Agent']` is `'AgenticDeveloperHubStatus/1.0'` — the URL and call-count assertions are from `heartbeat.int.test.ts` › "GETs the configured URL with a bounded signal"; the header value is traced directly to source, since that test asserts only `init?.signal` and the URL |
| status-server-monitor-heartbeat-004 | bounded-timeout-5000ms | `fetch` stubbed to inspect and record `init?.signal`; `await pingHeartbeat('https://hc.example.com/ping/abc')` | The recorded `init.signal` is truthy — `heartbeat.int.test.ts` › "GETs the configured URL with a bounded signal" (`expect(init?.signal).toBeTruthy()`) |
| status-server-monitor-heartbeat-005 | bounded-timeout-5000ms, network-failure-logged-not-thrown, always-resolves-undefined | `fetch` stubbed to never resolve or reject (hangs); `await pingHeartbeat(url)` under fake timers advanced past 5,000ms | The `fetch` call's own promise rejects once the 5,000ms `AbortSignal` fires; the rejection is caught and logged per network-failure-logged-not-thrown; `pingHeartbeat` resolves `undefined` within the timeout window rather than hanging indefinitely — not present in `heartbeat.int.test.ts`, traced to `HEARTBEAT_TIMEOUT_MS = 5_000` and the `AbortSignal.timeout(HEARTBEAT_TIMEOUT_MS)` call in source |
| status-server-monitor-heartbeat-006 | non-2xx-logged-not-thrown, always-resolves-undefined | `fetch` stubbed to resolve `new Response('not found', { status: 404 })`; `console.error` spied; `await pingHeartbeat(url)` | `console.error` is called with a message matching `/heartbeat/i` and containing `'404'`; the call resolves without throwing — `heartbeat.int.test.ts` › "logs a non-2xx check-in instead of treating it as a successful ping" |
| status-server-monitor-heartbeat-007 | network-failure-logged-not-thrown, always-resolves-undefined | `fetch` stubbed to `throw new Error('down')`; `await pingHeartbeat('https://hc.example.com/ping/abc')` | The call resolves `undefined`, does not throw — `heartbeat.int.test.ts` › "is a no-op without a url and fail-soft on network errors" (second assertion) |
| status-server-monitor-heartbeat-008 | caller-supplied-url-no-default-no-env-read | Static read of `heartbeat.ts`'s function signature and import list | `pingHeartbeat` declares exactly one parameter (`url: string \| null`); the file contains no import of, and no reference to, `process.env` or any environment-reading helper |
| status-server-monitor-heartbeat-009 | independent-per-call-no-shared-state | `fetch` stubbed to record each call's url and resolve `new Response('ok')` for one url while rejecting for another; `await Promise.all([pingHeartbeat(URL_A), pingHeartbeat(URL_B)])` | `fetch` is called exactly twice, once with `URL_A` and once with `URL_B`; `URL_B`'s rejection is caught and logged independently and does not prevent, delay, or alter the outcome recorded for `URL_A` — not present in `heartbeat.int.test.ts`, traced to the module holding no shared queue or cache (contrast with `alerts.ts`'s module-level queue) |
| status-server-monitor-heartbeat-010 | always-resolves-undefined, non-2xx-logged-not-thrown | `fetch` stubbed to resolve `new Response('ok', { status: 200 })`; `console.error` spied; `await pingHeartbeat(url)` | The call resolves `undefined`; `console.error` is not called — exercised incidentally by the "cycle-runner heartbeat wiring" suite's successful-ping cases in `heartbeat.int.test.ts`, not by a dedicated happy-path assertion on `pingHeartbeat` itself |

## Edge Cases

- **Null and empty input**: `url` of `null` or `''` MUST no-op with no network call (noop-null-or-empty-url); this is the type's own documented range (`string | null`) plus JavaScript's falsy-string coercion, not a validation gap. A non-empty but malformed `url` string (e.g. `'not a url'`) is not specially checked by this file — `fetch` itself throws synchronously constructing the request, and that throw occurs inside the same `try` block as the `await fetch(...)` call, so it is caught and logged exactly like any other network failure (network-failure-logged-not-thrown) — MUST.
- **Boundary values**: the 5,000ms `AbortSignal.timeout` deadline is a wall-clock boundary this file cannot make deterministic on its own; a response that settles at exactly 5,000ms is a race between the response and the abort, a property of `AbortSignal.timeout` itself rather than a guarantee this file makes — SHOULD be treated as "may or may not abort" rather than a precise cutoff.
- **Concurrent access**: `pingHeartbeat` holds no module-level mutable state (unlike `alerts.ts`'s queue), so two or more concurrent or overlapping calls simply run independent `fetch` calls with independent `AbortSignal` instances; neither the outcome nor the logging of one call can affect another (independent-per-call-no-shared-state) — MUST. Nothing in this file prevents a caller from invoking it concurrently with itself; the sole real caller, `cycle-runner.ts`, only ever calls it once per full sync and only after the rest of that sync's phase has completed, which is a fact about that caller, external to this file.
- **Error states**: a non-2xx response is logged and treated as a failed check-in without throwing (non-2xx-logged-not-thrown) — MUST. A rejected `fetch` — a DNS failure, a connection refused, a TLS error, or the 5,000ms abort firing — is caught and logged identically via the same `catch` block, with no distinction made between a genuine network failure and a self-inflicted timeout (network-failure-logged-not-thrown) — MUST.
- **Offline / disconnected state**: loss of connectivity to the check-in URL mid-request is indistinguishable from any other network failure this file handles — it folds into the same `catch` block, logged once, with no retry and no backoff of any kind. The only recovery path is the next full sync (per the module's own header comment, roughly every ~5 minutes) calling `pingHeartbeat` again from scratch; that cadence is decided entirely by the caller (`cycle-runner.ts`, `index.ts`/`scheduler.ts`), external to this file — MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` (parameter to `pingHeartbeat`) | `string \| null` | none — caller-supplied, required | The check-in URL to ping. `null` or an empty string disables the feature entirely for that call. This file never reads an environment variable itself. |
| `HEARTBEAT_URL` | environment variable, read by `config/env.ts`'s `heartbeatUrl` getter (external to this file) | unset → `null` | The environment variable the shipped `StatusConfig` implementation reads (via `optional(env.HEARTBEAT_URL)`) to produce the `url` value that `cycle-runner.ts`'s `runMonitorCycle` (external to this file) passes into `pingHeartbeat` as `config.heartbeatUrl`. |
| `HEARTBEAT_TIMEOUT_MS` (module constant) | `number` | `5_000` | Fixed per-request deadline via `AbortSignal.timeout`; not configurable per call and has no environment override in this file. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only sends an outbound GET to a caller-supplied `url`, which is a check-in destination this file is handed, not a deep-link target it defines.

## Localization

None of this file's user-facing strings route through a localization mechanism; both `console.error` messages are hardcoded English literals interpolated directly in `pingHeartbeat`. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse — and because these are operator-facing diagnostic lines (surfaced wherever the container's stderr is collected), they are genuinely user-facing, not internal-only.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `[heartbeat] check-in URL answered <status> — the dead-man ping is NOT registering; verify HEARTBEAT_URL` | `console.error` when the response's `ok` flag is `false` |
| n/a | `[heartbeat] ping failed: <message>` | `console.error` when the `fetch` call rejects (network failure or timeout) |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; the only on/off lever is the `url` argument passed to `pingHeartbeat` per call, already documented under Configuration and noop-null-or-empty-url, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only observable output besides the network call itself is the two `console.error` lines documented under Logging.

## Privacy

- **Data collected**: none of this file's own data. `url` is an opaque, potentially secret-bearing check-in endpoint (a healthchecks.io-style path) supplied by the caller; this file transmits no request body, no cookie, and no credential of any kind in the GET it issues — only the `User-Agent` header and whatever query/path segments are already baked into `url` itself.
- **Storage**: none. `pingHeartbeat` persists nothing to disk or a database; the module's only piece of state is the `HEARTBEAT_TIMEOUT_MS` constant.
- **Transmission**: exactly one outbound GET per call, to the caller-supplied `url`, with no body. Neither `console.error` message ever includes `url` itself — the non-2xx message names only the numeric status, and the failure message names only the caught error's text — so a check-in URL is never written to this file's own log output.
- **Retention**: not applicable — this file keeps no record of a ping after the call that made it resolves; there is no history or count of past pings anywhere in this module.

## Logging

This file uses plain `console.error` calls with a literal `[heartbeat]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Response resolved with a non-2xx status | error (`console.error`) | `[heartbeat] check-in URL answered <status> — the dead-man ping is NOT registering; verify HEARTBEAT_URL` |
| `fetch` rejected (network failure or the 5,000ms abort) | error (`console.error`) | `[heartbeat] ping failed: <message>` |

These are the only two log lines this file emits — a successful `2xx` ping, and the `null`/empty-`url` no-op, each produce no log output at all, at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern would model `pingHeartbeat` as a free `async` function (or an `actor` method if it needed to coordinate with other state, which it does not here) taking a `URL?` and returning `Void`, built on `URLSession.shared.data(for:)` with the request's `timeoutInterval` set to `5`; `URLSession`'s own timeout-to-`URLError` mapping plays the role `AbortSignal.timeout` plays here, and both the non-2xx `HTTPURLResponse.statusCode` check and the `catch` block's logging translate directly.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the function as a `suspend fun pingHeartbeat(url: String?)` over OkHttp or Ktor, wrapping the call in `withTimeout(5_000)` (or the client's own per-call timeout config) and a `try`/`catch` that logs exactly like the source rather than propagating; there is no shared/module state to port, since Kotlin has no equivalent of a per-`Worker` module instance the way this pattern's sibling (`alerts.ts`) needs to account for.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/heartbeat.ts` as a single exported function on the Node status backend — not client-side React, and no framework dependency of its own beyond global `fetch` and `AbortSignal.timeout`. Its one real caller, `cycle-runner.ts`'s `runMonitorCycle`, runs it inside the monitor's own `Worker` thread (see `worker.ts`), but because this file holds no module-level state, the per-`Worker`-instance module-duplication concern documented on its sibling `alerts.ts` does not apply here — every call is independent regardless of which thread makes it.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no framework-specific concern beyond what SwiftUI's bullet already covers — the check-in call itself is `URLSession`-level, not view-layer.
- **WinUI 3**: a .NET port models `pingHeartbeat` as `async Task PingHeartbeatAsync(string? url)`, returning immediately when `url` is `null` or empty (mirroring `if (!url) return;`), then issuing one `HttpClient.GetAsync(url, cts.Token)` call with a `CancellationTokenSource(TimeSpan.FromSeconds(5))` as the `AbortSignal.timeout` analogue and a `User-Agent` header set via `HttpRequestMessage.Headers.UserAgent` (or `DefaultRequestHeaders` on a shared `HttpClient`) to the same literal `AgenticDeveloperHubStatus/1.0` value. The whole call sits inside a `try`/`catch (Exception ex)` that logs via `ILogger.LogError` (the `explicit-error-handling`/fail-soft shape, not a `throw`), and a resolved-but-non-2xx `HttpResponseMessage.IsSuccessStatusCode == false` gets its own `LogError` branch mirroring `non-2xx-logged-not-thrown` — `HttpClient.GetAsync` does not throw on a non-2xx status by default, so that check needs to be written explicitly, exactly as the TypeScript source writes it. No `ObservableCollection`/`INotifyPropertyChanged` apply: this function has no UI-bound state of its own to expose.

## Design Decisions

- **Decision**: check the resolved `Response`'s `ok` flag explicitly and log a distinct message when it is `false`, rather than treating any resolved (non-rejected) `fetch` call as a successful check-in.
  **Rationale**: stated directly in the source comment on `pingHeartbeat` — `fetch()` only REJECTS on a network-level failure; a 404 from a typo'd or deleted check-in URL resolves happily. Without this check, every cycle would believe it checked in while the external dead-man service never saw a valid ping — silently defeating the entire purpose of the file.
  **Approved**: pending
- **Decision**: catch every rejection from the `fetch` call — both a genuine network failure and the 5,000ms `AbortSignal.timeout` firing — with one `catch` block that logs and resolves normally, rather than letting either propagate.
  **Rationale**: the function's own doc comment states the constraint directly — "a slow or failing heartbeat endpoint must never fail (or stall) the cycle that is trying to report its own success." The health-check mechanism itself must never become the reason the monitor cycle it is reporting on appears to fail.
  **Approved**: pending
- **Decision**: hardcode the 5,000ms timeout (`HEARTBEAT_TIMEOUT_MS`) and the literal `User-Agent` string as module constants, rather than exposing either as a parameter or an environment-configurable value.
  **Rationale**: not spelled out beyond the constant's own name; recorded here as an observed, deliberate fact rather than an invented rationale. The module's header comment notes full syncs run "every ~5min," so a fixed several-second budget for one outbound GET leaves ample margin without needing to be tunable per deployment, and a single hardcoded identifying `User-Agent` is enough for an operator to recognize the caller in the receiving service's logs.
  **Approved**: pending
- **Decision**: take no default for `url` and read no environment variable directly, leaving both "which endpoint" and "on vs. off" entirely to the caller.
  **Rationale**: stated directly in the function's own doc comment — "`url` is `config.heartbeatUrl` — this module takes no default and never reads env itself." This keeps `pingHeartbeat` a pure, side-effect-parameterized function that unit tests can call directly with any `url` value, with no need to stub `process.env`, matching how `heartbeat.int.test.ts` exercises it.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` is `partial`: `heartbeat.int.test.ts` exercises the `null`-url no-op, the GET call with a bounded signal, fail-soft resolution on a thrown `fetch` error, and the non-2xx logging path — but the exact `User-Agent` header value, the no-environment-read fact, and the independence of concurrent calls (vectors 003, 008, 009 above) are traceable to reading the source rather than to an existing assertion. `separation-of-concerns` passes: this file owns exactly one concern (the outbound check-in call); it reads no config itself, taking the URL as a plain parameter, and every decision about when to call it and what URL to pass lives entirely in its caller (`cycle-runner.ts`), external to this file. `explicit-error-handling` passes: both a rejected `fetch` and a resolved-but-non-2xx `Response` are checked and logged explicitly via `console.error`, never silently swallowed — a stricter result than its sibling `alerts.ts`, whose `flushAlerts` inspects only the rejection path and never checks `Response.ok` at all. `timeout-configuration` passes: the one GET call carries a 5,000ms deadline via `AbortSignal.timeout`. `retry-with-backoff` fails as written: a failed or non-2xx check-in is logged once with no retry, no backoff, and no re-attempt of any kind within the call — a deliberate tradeoff recorded as fact in Design Decisions above (the external monitor's missed-ping alert is the intended recovery signal, not an in-process retry), not a defended pass. `graceful-degradation` passes: a `null`/empty `url` is a full no-op (noop-null-or-empty-url) rather than an error, and every failure mode (non-2xx, network error, timeout) is caught and logged rather than propagated, so the monitor cycle that calls `pingHeartbeat` last is never itself put at risk by this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
