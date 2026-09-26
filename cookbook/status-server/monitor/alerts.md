---
id: 1d3c4f89-f2d5-4cf1-b5c2-879ec0e594a9
title: Status Server Monitor Alerts
domain: agentictoolkit://cookbook/status-server/monitor/alerts
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Queues monitor issue open, resolve, and retire transitions and batches them
  into one fail-soft webhook POST per flush; a no-op when the URL is unset.
platforms:
- typescript
- web
tags:
- monitor
- alerting
- webhook
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
related: []
references:
- packages/web/packages/status-server/src/monitor/alerts.ts (agentictoolkit)
- packages/web/packages/status-server/test/alerts.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Alerts

## Overview

`alerts.ts` (`packages/web/packages/status-server/src/monitor/alerts.ts`) is the status backend's outbound alerting module. Its own header comment states the problem it exists to fix: outbound alerting — the monitor DETECTED outages but told no one, because an issue was only visible to someone already looking at the wallboard. Issue open/resolve/retire transitions, decided elsewhere by the ledger (`issues.ts`) and the monitor's sync sweep (`sync.ts`), are queued here and flushed as ONE webhook POST per cycle to `ALERT_WEBHOOK_URL`. The payload shape is deliberately generic — `text` renders on Slack, `content` on Discord, and `alerts` is the structured list for anything custom (ntfy, a Worker, etc.) — so no per-vendor adapter is needed. The module is fail-soft and bounded by design, per its own header comment: alerting must never take the monitor cycle down, and an unset URL turns the feature off entirely. It exports `IssueAlert` (the queued shape), `notifyIssueAlert` (synchronous enqueue), `flushAlerts` (async drain-and-POST), and the test-only `_resetAlerts`.

## Behavioral Requirements

### Data Shape

- **issue-alert-shape**: An `IssueAlert` value MUST carry exactly six fields: `kind: 'opened' | 'resolved' | 'retired'`, `target: string`, `name: string`, `environment: string | null`, `state: string | null`, and `detail: string | null`; a literal missing any of these six fields or using another `kind` value MUST fail to type-check.
- **retired-kind-distinct-from-resolved**: The `kind` value `retired` MUST be distinct from `resolved`. Per the type's own doc comment, `retired` records that the MONITOR was deleted because what it watched stopped existing — the cycle's automatic removal — which is distinct on purpose from `resolved`: nothing recovered, so claiming it did would tell on-call an outage cleared when it never did, yet the `opened` alert sent days earlier still needs a counterpart, or the last word anyone hears about that target is a red one no future cycle can ever close.

### Queueing (`notifyIssueAlert`)

- **enqueue-synchronous**: `notifyIssueAlert` MUST append the given `IssueAlert` to the module-level queue synchronously and return `void`, performing no `await` and no I/O.
- **enqueue-independent-of-flush-config**: `notifyIssueAlert` MUST accept and queue an alert regardless of whether alert delivery is currently enabled. Per the source comment, whether alerting is actually ON is `flushAlerts`'s call to make (it takes the URL); an unqueued alert while alerting is off would leave the `opened` alert sent before it turned off with no `resolved`/`retired` counterpart once it turns back on.
- **queue-bounded-drop-oldest**: When appending a new entry would grow the queue past `MAX_QUEUED` (100) entries, `notifyIssueAlert` MUST drop the single oldest queued entry (`queue.shift()`) immediately after the append, so the queue never holds more than 100 entries.

### Delivery (`flushAlerts`)

- **flush-noop-null-url**: `flushAlerts` MUST return, without dequeuing or sending anything, when its `url` argument is `null`; every currently-queued alert MUST remain queued for a later flush.
- **flush-noop-empty-queue**: `flushAlerts` MUST return without making any network call when the queue is empty, regardless of `url`.
- **flush-drains-before-sending**: When `url` is non-null and the queue is non-empty, `flushAlerts` MUST remove every currently-queued alert from the queue (`queue.splice(0)`) before attempting delivery, not after a successful response.
- **flush-single-batched-post**: `flushAlerts` MUST deliver every alert drained in one call as exactly one HTTP POST to `url`, never one request per alert.
- **flush-request-shape**: The POST MUST set header `Content-Type: application/json` and a JSON body with exactly three top-level keys: `text` (the drained alerts' rendered lines, joined; see Rendering), `content` (the identical string as `text`), and `alerts` (the drained `IssueAlert[]`, unmodified).
- **flush-timeout-5000ms**: The POST MUST carry a deadline of 5,000 milliseconds (`ALERT_TIMEOUT_MS`), enforced via `AbortSignal.timeout(5_000)`.
- **flush-fail-soft**: When the POST call rejects (a network failure or the 5,000ms abort), `flushAlerts` MUST catch the rejection, log it via `console.error` with the message `[alerts] webhook delivery failed (<n> alerts): <error message>` (`<n>` the count of alerts in that batch), and resolve normally; it MUST NOT re-queue the already-drained alerts and MUST NOT throw or reject.
- **webhook-non-2xx-response**: NEEDS REVIEW: Not implemented in source. `flushAlerts` never inspects the `Response` object `fetch` resolves — no `.ok` or status-code check of any kind — so a webhook receiver that answers with a 4xx or 5xx status is treated identically to a successful delivery: no log line is written, nothing is retried, and the batch was already drained from the queue before the request was even sent, so this failure mode leaves no signal anywhere for an operator to notice a broken or rejecting `ALERT_WEBHOOK_URL`. Settled by confirming whether checking `response.ok` and logging a non-2xx the same way the catch block logs a thrown error is the intended fix, or whether webhook receivers are trusted to never reject a well-formed payload.

### Rendering (`line`)

- **render-opened**: Rendering an `opened` alert MUST produce the string `🔴 opened<state>: <name><environment><detail>`, where `<state>` is a leading space plus `state` when `state` is a non-empty string (else omitted entirely), `<environment>` is ` (` + `environment` + `)` when `environment` is a non-empty string (else omitted), and `<detail>` is ` — ` + `detail` when `detail` is a non-empty string (else omitted).
- **render-retired**: Rendering a `retired` alert MUST produce `🗑 monitor removed: <name><environment><detail>`, applying the same `<environment>`/`<detail>` composition rules as render-opened, and MUST NOT include the alert's `state` field anywhere in the rendered line even when it is non-null.
- **render-resolved**: Rendering a `resolved` alert MUST produce `✅ resolved: <name><environment>`, applying the same `<environment>` composition rule as render-opened, and MUST NOT include the alert's `state` or `detail` fields anywhere in the rendered line even when they are non-null.
- **render-lines-joined**: `flushAlerts` MUST join the drained alerts' rendered lines with a single `\n` between each, in the same order the alerts were drained (oldest queued first, after any `MAX_QUEUED` drops), to build the `text`/`content` string.

### Test Hook

- **reset-clears-queue**: `_resetAlerts` MUST synchronously empty the queue (`queue.length = 0`) and MUST NOT perform any network call.

### Ordering and Concurrency

- **queue-is-module-singleton**: The queue MUST be a single module-level array shared by every call to `notifyIssueAlert` and `flushAlerts` that runs against the same loaded module instance; the module exposes no way to construct an independent queue. Because JavaScript is single-threaded within one module instance and neither `notifyIssueAlert` nor the synchronous prefix of `flushAlerts` awaits before mutating the queue, two calls into this module from the same thread MUST NOT interleave their queue mutations — this ordering is a fact of the runtime, not a race requiring a lock.
- **queue-is-per-thread-instance**: Because a Node `Worker` thread loads its own copy of a module, an alert queued by a call to `notifyIssueAlert` inside one thread's module instance MUST NOT become visible to, or be delivered by, a call to `flushAlerts` made from a different thread's module instance; whichever thread calls `notifyIssueAlert` for a given alert MUST also be the thread that calls `flushAlerts` for that alert to ever be delivered. This is not directly observable inside `alerts.ts` itself but is a structural consequence of module state being per-thread, and it is why this file has three independent flush call sites external to it: `cycle-runner.ts` flushes from the monitor's own `Worker` thread, while `board/reconcile.ts` and `routes/hooks.ts` each flush from the API thread specifically because an alert queued by an API-thread-triggered ledger write would otherwise sit in that thread's queue forever — the monitor thread's next `flushAlerts` call can never see it, because it is a different module instance's array.

## Appearance

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component.

## States

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component; its only runtime states (queued vs. drained, alerting on vs. off) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-alerts-001 | enqueue-synchronous, flush-single-batched-post, flush-request-shape, render-lines-joined, flush-noop-empty-queue, queue-is-module-singleton | `notifyIssueAlert({kind:'opened', target:'a', name:'Site A', environment:'production', state:'down', detail:'HTTP 503'})`; `notifyIssueAlert({kind:'opened', target:'b', name:'Site B', environment:null, state:'failed', detail:null})`; `await flushAlerts(ALERT_URL)`; then `await flushAlerts(ALERT_URL)` again with nothing newly queued | Exactly one `fetch` call total; its body's `text` contains both `'Site A'` and `'Site B'` in that order; `body.alerts.length === 2`; the second `flushAlerts` call makes no additional `fetch` call — `alerts.int.test.ts` › "batches queued alerts into ONE webhook POST on flush" |
| status-server-monitor-alerts-002 | flush-noop-null-url, enqueue-independent-of-flush-config | `notifyIssueAlert({kind:'opened', target:'a', name:'A', environment:null, state:'down', detail:null})`; `await flushAlerts(null)` | No `fetch` call is made — `alerts.int.test.ts` › "is a no-op with a null url and fail-soft on delivery errors" |
| status-server-monitor-alerts-003 | flush-fail-soft | `fetch` stubbed to `throw new Error('webhook down')`; `notifyIssueAlert({...})`; `await flushAlerts(ALERT_URL)` | The call resolves `undefined` and does not throw — `alerts.int.test.ts`, same test, second half |
| status-server-monitor-alerts-004 | flush-drains-before-sending, flush-fail-soft | `fetch` stubbed to throw on its first call and succeed on its second; `notifyIssueAlert(A)`; `await flushAlerts(URL)` (throws internally, caught); `notifyIssueAlert(B)`; `await flushAlerts(URL)` (succeeds) | The second POST's `body.alerts` contains only `B`, never `A` — `A` was already removed from the queue by the failed attempt and is never retried or re-queued |
| status-server-monitor-alerts-005 | render-opened | `notifyIssueAlert({kind:'opened', target:'x', name:'App', environment:'production', state:'down', detail:'HTTP 503'})`; flush | Rendered line is exactly `🔴 opened down: App (production) — HTTP 503` |
| status-server-monitor-alerts-006 | render-opened | `notifyIssueAlert({kind:'opened', target:'x', name:'App', environment:null, state:null, detail:null})`; flush | Rendered line is exactly `🔴 opened: App` — no state suffix, no parenthetical, no dash-detail |
| status-server-monitor-alerts-007 | render-resolved | `notifyIssueAlert({kind:'resolved', target:'x', name:'App', environment:'production', state:'down', detail:'HTTP 503'})`; flush | Rendered line is exactly `✅ resolved: App (production)` — `state` and `detail` never appear even though both are present on the alert |
| status-server-monitor-alerts-008 | render-retired | `notifyIssueAlert({kind:'retired', target:'x', name:'App', environment:null, state:'down', detail:'no endpoint matches this monitor any more'})`; flush | Rendered line is exactly `🗑 monitor removed: App — no endpoint matches this monitor any more` — `state` never appears |
| status-server-monitor-alerts-009 | queue-bounded-drop-oldest | Call `notifyIssueAlert` 101 times with `name` values `'N0'`…`'N100'`, each otherwise identical; flush | `body.alerts.length === 100`; `body.alerts[0].name === 'N1'` (`'N0'` was dropped as the oldest entry when the 101st push exceeded `MAX_QUEUED`) |
| status-server-monitor-alerts-010 | reset-clears-queue | `notifyIssueAlert({...})`; `_resetAlerts()`; `await flushAlerts(ALERT_URL)` | No `fetch` call is made — consistent with `_resetAlerts()` being called in `alerts.int.test.ts`'s `beforeEach` to isolate every test in that file from the last |
| status-server-monitor-alerts-011 | flush-timeout-5000ms | `fetch` stubbed to never resolve or reject (hangs); `await flushAlerts(ALERT_URL)` under fake timers advanced past 5,000ms | The call's `fetch` invocation received a `signal` that aborts at 5,000ms, causing the `fetch` promise to reject with an abort error, which `flushAlerts` catches per flush-fail-soft — the call resolves `undefined` within the timeout window, not indefinitely |
| status-server-monitor-alerts-012 | issue-alert-shape | `const bad: IssueAlert = { kind: 'opened', target: 'a', name: 'A', environment: null, state: null }` (missing `detail`) | TypeScript compilation fails: property `detail` is missing from type `IssueAlert` |
| status-server-monitor-alerts-013 | queue-is-per-thread-instance | In a Node `Worker` thread, call `notifyIssueAlert({...})`; from the main (parent) thread's own loaded copy of `alerts.ts`, call `await flushAlerts(ALERT_URL)` | The main thread's `flushAlerts` makes no `fetch` call, because the alert was appended to the worker thread's independent module-level `queue`, not the main thread's — delivering it requires calling `flushAlerts` from inside that same worker |
| status-server-monitor-alerts-014 | retired-kind-distinct-from-resolved, render-retired | `notifyIssueAlert({kind:'retired', target:'ep-1', name:'App', environment:'production', state:null, detail:'endpoint deleted — no endpoint matches this monitor'})`; flush | Rendered line begins `🗑 monitor removed:`, never `✅ resolved:`, matching how `sync.ts`'s `retireMonitors` constructs this alert on an automatic monitor deletion (external to this file, cited for context) |
| status-server-monitor-alerts-015 | flush-noop-empty-queue, flush-single-batched-post | Real recorder path: `applyBoardToLedger` opens an issue for a down endpoint, then `flushAlerts` (1 POST, text matches `/opened/i`); the same board is applied again with the endpoint still down, then `flushAlerts` (no new POST — still 1 total); the board then reports the endpoint healthy, then `flushAlerts` (a 2nd POST, text matches `/resolved/i`) | Exactly 2 POSTs total across three cycles — silent on the unchanged middle cycle because nothing new was queued — `alerts.int.test.ts` › "emits opened on a new outage and resolved on recovery — silent in between" |

## Edge Cases

- **Null and empty input**: `environment`, `state`, and `detail` are each checked for truthiness, not for `null` specifically, so an empty string behaves identically to `null` in every render function — MUST. `name` and `target` carry no such guard: `name` is interpolated into every rendered line unconditionally, so an empty-string `name` produces a line like `🔴 opened: ` with nothing after the colon rather than a validation error — MUST (this file never validates that `name` or `target` is non-empty). `target` never appears in the rendered `text`/`content` string at all in any `kind`; it is carried only in the structured `alerts` array of the payload — MUST.
- **Boundary values**: the 100th queued entry is kept and the 101st push causes the 1st to be dropped (status-server-monitor-alerts-009) — MUST. The 5,000ms abort deadline is a wall-clock boundary this file cannot make deterministic on its own; a request that settles at exactly 5,000ms is a race between the response and the abort that this file does not control — SHOULD be treated as "may or may not abort" rather than a guaranteed cutoff, per `AbortSignal.timeout`'s own semantics.
- **Concurrent access**: within one thread, `notifyIssueAlert` and the synchronous prefix of `flushAlerts` (the `splice`) cannot interleave, because neither awaits before mutating the queue — ordering inside one thread is a fact of the JavaScript runtime, not a race (queue-is-module-singleton) — MUST. Across threads, the queue is NOT shared: a Node `Worker` loads its own module instance, so an alert queued on one thread is invisible to, and undeliverable by, `flushAlerts` called from another thread (queue-is-per-thread-instance) — MUST. This file provides no cross-thread synchronization of its own; every caller external to this file that queues an alert on one thread MUST also flush from that same thread, which is exactly the shape observed at this file's three real call sites (`cycle-runner.ts`'s monitor worker; `board/reconcile.ts` and `routes/hooks.ts` on the API thread).
- **Error states**: a network failure or the 5,000ms abort during the POST is caught, logged via `console.error`, and the batch is dropped without retry — MUST (flush-fail-soft). A webhook receiver that responds with a non-2xx status is NOT distinguished from success by this file at all — see the `webhook-non-2xx-response` marker above; this is the one genuine gap in this file's error handling, not a case this recipe can state a defined MUST for.
- **Offline / disconnected state**: this file has no inbound connectivity of its own to lose; its analogue is the webhook receiver being unreachable or slow mid-POST, which is exactly the Error states case above — handled by the fixed 5,000ms timeout and fail-soft catch, with no retry and no backoff of any kind (see `webhook-non-2xx-response` and the `retry-with-backoff` compliance result below). A `flushAlerts` call made while the process has no queued alerts and the URL is unreachable is indistinguishable from one made while everything is healthy, because `flush-noop-empty-queue` returns before any network attempt either way.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` (parameter to `flushAlerts`) | `string \| null` | none — caller-supplied per call | The webhook target for that flush. `null` disables delivery for that call while leaving the queue intact for a later flush with a non-null url. This file never reads an environment variable itself. |
| `ALERT_WEBHOOK_URL` | environment variable, read by `config/env.ts`'s `alertWebhookUrl` getter (external to this file) | unset → `null` | The environment variable the shipped `StatusConfig` implementation reads to produce the `url` value this file's callers (`cycle-runner.ts`, `board/reconcile.ts`, `routes/hooks.ts`, all external) pass into `flushAlerts`. |
| `ALERT_TIMEOUT_MS` (module constant) | `number` | `5_000` | Fixed per-POST deadline via `AbortSignal.timeout`; not configurable per call and has no environment override in this file. |
| `MAX_QUEUED` (module constant) | `number` | `100` | Fixed queue bound; not configurable per call. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only sends an outbound webhook POST to a caller-supplied `url`, which is a payload destination this file is handed, not a deep-link target it defines.

## Localization

None of this file's user-facing strings route through a localization mechanism; every rendered alert-line fragment and the one `console.error` message are hardcoded English literals interpolated by `line()` and `flushAlerts`'s catch block. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse — and because these rendered lines are the text an on-call engineer reads in Slack or Discord, they are genuinely user-facing, not internal-only.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `🔴 opened` | Line prefix for an `opened` alert (`line()`) |
| n/a | `🗑 monitor removed:` | Line prefix for a `retired` alert (`line()`) |
| n/a | `✅ resolved:` | Line prefix for a `resolved` alert (`line()`) |
| n/a | `[alerts] webhook delivery failed (<n> alerts): <message>` | `console.error` on a caught delivery failure (`flushAlerts`) |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; the only on/off lever is the `url` argument passed to `flushAlerts` per call, already documented under Configuration and flush-noop-null-url, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: the alert's `target`, `name`, `environment`, `state`, and `detail` strings — infrastructure identifiers and status text describing a monitored site or deploy, sourced by callers external to this file (`issues.ts`, `sync.ts`) from roster and deploy metadata, never from an end user directly. This file constructs and transmits no credential, token, or personal end-user data.
- **Storage**: none. The queue is in-memory only (`const queue: IssueAlert[] = []`); this file never writes an alert to disk or a database. An alert not yet delivered when the process exits is lost — there is no persistence to survive a restart.
- **Transmission**: every queued alert's fields, plus the derived `text`/`content` strings, are sent verbatim in the JSON body of one outbound POST per flush to the caller-supplied `url` — an operator-controlled webhook receiver (Slack, Discord, ntfy, or a custom endpoint). This file does not validate or restrict the destination's scheme or host beyond whatever `fetch` itself enforces; whether that connection is encrypted is a property of `url`, not something this file chooses.
- **Retention**: not applicable to this file directly — once drained, an alert exists only inside the in-flight HTTP request; this file keeps no record of what it has previously sent.

## Logging

This file uses a plain `console.error` call with a literal `[alerts]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Webhook delivery failure (network error or 5,000ms abort) | error (`console.error`) | `[alerts] webhook delivery failed (<n> alerts): <error message>` |

This is the only log line this file emits — a successful flush produces no log output at all, at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this alerting pattern would model `IssueAlert` as a `Sendable` `struct`, the queue as an `actor`'s private array (an `actor` gives thread-isolation for free, in place of relying on JavaScript's single-thread-per-module guarantee), and `flushAlerts` as an `actor` method built on `URLSession`'s `data(for:)` with the request's `timeoutInterval` set to `5`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the queue as a `MutableList` guarded by a `Mutex` (Kotlin coroutines have no equivalent to one JS module instance being implicitly single-threaded), `MAX_QUEUED` as an explicit size check plus `removeAt(0)` after each add, and `flushAlerts` as a `suspend fun` over OkHttp or Ktor with `withTimeout(5_000)`, called from a background dispatcher so it never blocks the caller that raised the alert.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/alerts.ts` as a plain module-scope singleton on the Node status backend — not client-side React, and no framework dependency of its own beyond global `fetch` and `AbortSignal.timeout`. It is imported by three independent call sites external to this file (`cycle-runner.ts`'s monitor `Worker`, `board/reconcile.ts`, and `routes/hooks.ts`'s API routes), which exist precisely because this module's queue is per-thread.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no `Worker`-per-thread module-duplication concern the way Node does, unless it explicitly hands work to a separate process; the queue-is-per-thread-instance gotcha this file has is specific to Node's per-`Worker` module loading and does not recur with a Swift `actor`, which is a single instance regardless of which thread calls into it.
- **WinUI 3**: a .NET port models `IssueAlert` as a `readonly record struct` with the same six fields (the `kind` field as an `enum` with three cases), the queue as a `ConcurrentQueue<IssueAlert>` guarded by an explicit bound check-and-dequeue after every `Enqueue` (since `ConcurrentQueue<T>` has no built-in cap, unlike this file's `queue.shift()` on overflow), and `flushAlerts` as `Task FlushAlertsAsync(string? url)` using `HttpClient.PostAsync` with `System.Text.Json` for the body and a `CancellationTokenSource(TimeSpan.FromSeconds(5))` passed to the request as the `AbortSignal.timeout` analogue. The drain-before-send ordering (`flush-drains-before-sending`) needs the same deliberate shape in C#: dequeue every pending item into a local `List<IssueAlert>` before `await`-ing the POST, so a failed request does not leave stale items mixed with newly-enqueued ones, and a failed send simply drops that local list rather than requeuing it, matching flush-fail-soft.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/alerts.ts` |

## Design Decisions

- **Decision**: drain the queue (`queue.splice(0)`) before attempting the webhook POST, rather than after a successful response.
  **Rationale**: stated directly in the source comment on `flushAlerts` — delivery is "fail-soft (a down webhook endpoint is logged and the batch dropped — the open issue itself is durable in the DB either way)." Draining first means a slow or repeatedly-invoked flush never accumulates an ever-growing in-flight batch, at the deliberate cost that a failed POST permanently loses that specific batch instead of retrying it later; the tradeoff is acceptable because the underlying issue state lives durably in the database regardless of whether the notification about it was ever delivered.
  **Approved**: pending
- **Decision**: bound the queue at 100 entries and drop the OLDEST entry on overflow (`queue.shift()`), rather than dropping the newest or refusing to enqueue.
  **Rationale**: the source comment on `MAX_QUEUED` states the queue "only ever accumulates within one cycle (the cycle flushes), so hitting this means something is very wrong." Once something has already gone wrong enough to hit the bound, keeping the most recently queued (and therefore most current) transitions is more actionable to on-call than preserving the oldest history.
  **Approved**: pending
- **Decision**: give `resolved` and `retired` alerts narrower render templates than `opened` — `resolved` drops `state` and `detail` entirely; `retired` drops `state` but keeps `detail`.
  **Rationale**: not spelled out in a comment beyond the `kind` field's own distinction; recorded here as an observed, deliberate fact of `line()`'s three branches rather than an invented rationale — a recovery message needs no further explanation (the outage is simply over), while a retirement needs the removal reason (`detail`) to tell on-call why the monitor disappeared, but has no live `state` left to report since nothing is being monitored any more.
  **Approved**: pending
- **Decision**: keep `notifyIssueAlert` synchronous and side-effect-free beyond the in-memory push, deferring all I/O and the alerting on/off decision to the separately-invoked `flushAlerts`.
  **Rationale**: stated directly in the source comment on `notifyIssueAlert` — enqueuing is "cheap + sync — safe to call from the recorders' hot path, with no config in scope there," and gating on the URL is deliberately `flushAlerts`'s job so an unqueued alert while alerting is off would leave an earlier `opened` alert with no matching `resolved`/`retired` counterpart once alerting turns back on.
  **Approved**: pending
- **Decision**: provide `_resetAlerts` as a test-only escape hatch with no production equivalent.
  **Rationale**: the function's own doc comment calls it a "Test hook — drop queued alerts." Production code has no path that clears the queue other than a successful `flushAlerts` drain, which is consistent with the queue being expected to fully empty via `flushAlerts` every cycle rather than ever needing an out-of-band reset.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `test/alerts.int.test.ts` exercises queue batching into one POST, the null-url no-op, fail-soft delivery on a thrown fetch error, and the real `openIssue`/`resolveIssue` recorder path across an opened-then-silent-then-resolved cycle, including the case where a config-driven close must stay silent. `separation-of-concerns` passes: this file owns exactly one concern (queueing and delivering alerts) behind two functions and a type; it reads no config itself, taking the webhook URL as a plain parameter, and the ledger/business-logic decision of WHEN to alert lives entirely in its callers (`issues.ts`, `sync.ts`), external to this file. `explicit-error-handling` is `partial`: a thrown/rejected `fetch` is caught and logged explicitly via `console.error`, never silently swallowed — but a non-2xx `Response` is not inspected at all (see the `webhook-non-2xx-response` marker above), so that specific failure mode produces no signal whatsoever, which is the one respect in which this check is not fully met. `timeout-configuration` passes: every POST carries a 5,000ms deadline via `AbortSignal.timeout`. `retry-with-backoff` fails as written: a failed delivery is logged once and the batch is permanently dropped (`flush-drains-before-sending` removes it from the queue before the attempt); there is no retry, no backoff, and no re-queue of any kind — a deliberate tradeoff recorded as fact in Design Decisions above, not a defended pass. `graceful-degradation` passes: an unset webhook URL is a full no-op (`flush-noop-null-url`) rather than an error, and a delivery failure is caught and logged rather than propagated — the monitor cycle and the underlying issue ledger are both fully independent of whether alert delivery is configured or currently working.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
