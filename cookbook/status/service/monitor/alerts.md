---
id: 1d3c4f89-f2d5-4cf1-b5c2-879ec0e594a9
title: Monitor Alerts
domain: agentictoolkit://cookbook/status/service/monitor/alerts
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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

# Monitor Alerts

## Overview

This module is the status backend's outbound alerting queue and webhook dispatcher. It exists to fix a specific problem: the monitor detects outages but tells no one, because an issue is only visible to someone already watching the dashboard. Issue open/resolve/retire transitions, decided elsewhere by the issue ledger and the monitor's sync sweep, are queued here and flushed as one webhook POST per cycle to a configured destination URL. The payload shape is deliberately generic — a `text` field renders on Slack, a `content` field on Discord, and a structured `alerts` list serves anything custom (ntfy, a custom receiver, etc.) — so no per-vendor adapter is needed. The module is fail-soft and bounded by design: alerting must never take the monitor cycle down, and an unset URL turns the feature off entirely. It exposes: a queued-alert shape, a synchronous enqueue operation, an asynchronous drain-and-POST flush operation, and a test-only queue reset.

## Behavioral Requirements

### Data Shape

- **issue-alert-shape**: An alert value MUST carry exactly six fields: a `kind` of `opened`, `resolved` or `retired`, `target`, `name`, `environment` (string or absent), `state` (string or absent), and `detail` (string or absent); the module MUST provide no way to construct a value missing any of these six fields or carrying an unrecognized `kind`.
- **retired-kind-distinct-from-resolved**: The `kind` value `retired` MUST be distinct from `resolved`: `retired` records that the monitor was deleted because what it watched stopped existing — an automatic removal — which is distinct on purpose from `resolved`: nothing recovered, so claiming it did would tell on-call an outage cleared when it never did, yet the `opened` alert sent earlier still needs a counterpart, or the last word anyone hears about that target is a red one no future cycle can ever close.

### Queueing

- **enqueue-synchronous**: The enqueue operation MUST append the given alert to the shared queue synchronously and return nothing, performing no wait and no I/O.
- **enqueue-independent-of-flush-config**: The enqueue operation MUST accept and queue an alert regardless of whether alert delivery is currently enabled. Whether delivery is actually turned on is the flush operation's call to make (it takes the destination); an alert dropped at enqueue time while delivery is off would leave an `opened` alert sent earlier with no `resolved`/`retired` counterpart once delivery turns back on.
- **queue-bounded-drop-oldest**: When appending a new entry would grow the queue past `MAX_QUEUED` (100) entries, the enqueue operation MUST drop the single oldest queued entry immediately after the append, so the queue never holds more than 100 entries.

### Delivery

- **flush-noop-null-url**: The flush operation MUST return, without dequeuing or sending anything, when its destination argument is `null`; every currently-queued alert MUST remain queued for a later flush.
- **flush-noop-empty-queue**: The flush operation MUST return without making any network call when the queue is empty, regardless of the destination.
- **flush-drains-before-sending**: When the destination is non-null and the queue is non-empty, the flush operation MUST remove every currently-queued alert from the queue before attempting delivery, not after a successful response.
- **flush-single-batched-post**: The flush operation MUST deliver every alert drained in one call as exactly one HTTP POST to the destination, never one request per alert.
- **flush-request-shape**: The POST MUST set header `Content-Type: application/json` and a JSON body with exactly three top-level keys: `text` (the drained alerts' rendered lines, joined; see Rendering), `content` (the identical string as `text`), and `alerts` (the drained alert list, unmodified).
- **flush-timeout-5000ms**: The POST MUST carry a deadline of 5,000 milliseconds (`ALERT_TIMEOUT_MS`), enforced by aborting the request if no response arrives in time.
- **flush-fail-soft**: When the POST call fails (a network failure or the 5,000ms abort), the flush operation MUST catch the failure, log it with the message `[alerts] webhook delivery failed (<n> alerts): <error message>` (`<n>` the count of alerts in that batch), and resolve normally; it MUST NOT re-queue the already-drained alerts and MUST NOT throw or reject.
- **webhook-non-2xx-response**: NEEDS REVIEW: Not implemented in source. The flush operation never inspects the response status of the POST — no success/failure check of any kind — so a webhook receiver that answers with a 4xx or 5xx status is treated identically to a successful delivery: no log line is written, nothing is retried, and the batch was already drained from the queue before the request was even sent, so this failure mode leaves no signal anywhere for an operator to notice a broken or rejecting destination URL. Settled by confirming whether checking the response status and logging a non-2xx the same way the catch path logs a thrown error is the intended fix, or whether webhook receivers are trusted to never reject a well-formed payload.

### Rendering

- **render-opened**: Rendering an `opened` alert MUST produce the string `🔴 opened<state>: <name><environment><detail>`, where `<state>` is a leading space plus `state` when `state` is a non-empty string (else omitted entirely), `<environment>` is ` (` + `environment` + `)` when `environment` is a non-empty string (else omitted), and `<detail>` is ` — ` + `detail` when `detail` is a non-empty string (else omitted).
- **render-retired**: Rendering a `retired` alert MUST produce `🗑 monitor removed: <name><environment><detail>`, applying the same `<environment>`/`<detail>` composition rules as render-opened, and MUST NOT include the alert's `state` field anywhere in the rendered line even when it is non-null.
- **render-resolved**: Rendering a `resolved` alert MUST produce `✅ resolved: <name><environment>`, applying the same `<environment>` composition rule as render-opened, and MUST NOT include the alert's `state` or `detail` fields anywhere in the rendered line even when they are non-null.
- **render-lines-joined**: The flush operation MUST join the drained alerts' rendered lines with a single `\n` between each, in the same order the alerts were drained (oldest queued first, after any `MAX_QUEUED` drops), to build the `text`/`content` string.

### Test Hook

- **reset-clears-queue**: The reset operation MUST synchronously empty the queue and MUST NOT perform any network call.

### Ordering and Concurrency

- **queue-is-module-singleton**: The queue MUST be a single instance shared by every call to the enqueue and flush operations that runs against the same loaded instance of this module; the module exposes no way to construct an independent queue. Within one such instance, two calls into this module MUST NOT interleave their queue mutations — this ordering is a fact of the runtime, not a race requiring a lock.
- **queue-is-per-thread-instance**: Because this module may be loaded independently by more than one isolated execution context (for example, a background worker and the process that also imports it), an alert queued in one context's instance of this module MUST NOT become visible to, or be delivered by, a call to the flush operation made from a different context's instance; whichever execution context calls the enqueue operation for a given alert MUST also be the context that calls the flush operation for that alert to ever be delivered. This is not directly observable from a single context's own use of this module, but is a structural consequence of the module's state being scoped per loaded instance — which is why this module has three independent flush call sites external to it: one flushes from the monitor's own background execution context, while the other two flush from the API-serving context specifically because an alert queued by an API-triggered ledger write would otherwise sit in that context's queue forever — the monitor context's next flush call can never see it, because it is a different instance's queue.

## Appearance

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component.

## States

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component; its only runtime states (queued vs. drained, alerting on vs. off) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side alert queue and webhook dispatcher, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-alerts-001 | enqueue-synchronous, flush-single-batched-post, flush-request-shape, render-lines-joined, flush-noop-empty-queue, queue-is-module-singleton | Enqueue an opened alert for `Site A` (production, down, HTTP 503), then an opened alert for `Site B` (no environment, failed, no detail); flush to a webhook URL; flush again with nothing newly queued | Exactly one POST total; its body's `text` contains both `Site A` and `Site B` in that order; the body's alert list has 2 entries; the second flush makes no additional POST |
| status-server-monitor-alerts-002 | flush-noop-null-url, enqueue-independent-of-flush-config | Enqueue an opened alert for `A`; flush with a `null` destination | No POST is made |
| status-server-monitor-alerts-003 | flush-fail-soft | The POST is stubbed to fail with `webhook down`; enqueue an alert; flush to a webhook URL | The call resolves without throwing |
| status-server-monitor-alerts-004 | flush-drains-before-sending, flush-fail-soft | The POST is stubbed to fail on its first call and succeed on its second; enqueue alert A; flush (fails, caught); enqueue alert B; flush (succeeds) | The second POST's alert list contains only B, never A — A was already removed from the queue by the failed attempt and is never retried or re-queued |
| status-server-monitor-alerts-005 | render-opened | Enqueue an opened alert for `App` (production, down, HTTP 503); flush | Rendered line is exactly `🔴 opened down: App (production) — HTTP 503` |
| status-server-monitor-alerts-006 | render-opened | Enqueue an opened alert for `App` with no environment, state or detail; flush | Rendered line is exactly `🔴 opened: App` — no state suffix, no parenthetical, no dash-detail |
| status-server-monitor-alerts-007 | render-resolved | Enqueue a resolved alert for `App` (production, down, HTTP 503); flush | Rendered line is exactly `✅ resolved: App (production)` — `state` and `detail` never appear even though both are present on the alert |
| status-server-monitor-alerts-008 | render-retired | Enqueue a retired alert for `App` with no environment, state `down`, detail `no endpoint matches this monitor any more`; flush | Rendered line is exactly `🗑 monitor removed: App — no endpoint matches this monitor any more` — `state` never appears |
| status-server-monitor-alerts-009 | queue-bounded-drop-oldest | Enqueue 101 alerts with names `N0`…`N100`, otherwise identical; flush | The body's alert list has 100 entries; the first entry's name is `N1` (`N0` was dropped as the oldest entry when the 101st push exceeded `MAX_QUEUED`) |
| status-server-monitor-alerts-010 | reset-clears-queue | Enqueue an alert; reset the queue; flush to a webhook URL | No POST is made |
| status-server-monitor-alerts-011 | flush-timeout-5000ms | The POST is stubbed to never resolve or reject (hangs); flush to a webhook URL, with the clock advanced past 5,000ms | The request aborts at 5,000ms and the resulting failure is caught per flush-fail-soft — the call resolves within the timeout window, not indefinitely |
| status-server-monitor-alerts-012 | issue-alert-shape | Attempt to construct an alert value with `kind: 'opened'`, `target: 'a'`, `name: 'A'`, no `environment`, no `state`, and no `detail` field at all | Construction is rejected: the `detail` field is missing from the required shape |
| status-server-monitor-alerts-013 | queue-is-per-thread-instance | In one execution context (for example a background worker), enqueue an alert; from a different context's own loaded instance of this module, flush to a webhook URL | The second context's flush makes no POST, because the alert was appended to the first context's independent queue, not the second's — delivering it requires flushing from within that same context |
| status-server-monitor-alerts-014 | retired-kind-distinct-from-resolved, render-retired | Enqueue a retired alert for endpoint `ep-1` (`App`, production, no state, detail `endpoint deleted — no endpoint matches this monitor`); flush | Rendered line begins `🗑 monitor removed:`, never `✅ resolved:`, matching how the monitor's automatic-removal path constructs this alert on an automatic monitor deletion |
| status-server-monitor-alerts-015 | flush-noop-empty-queue, flush-single-batched-post | Apply a board that opens an issue for a down endpoint, then flush (1 POST, text matches an opened pattern); apply the same board again with the endpoint still down, then flush (no new POST — still 1 total); apply a board reporting the endpoint healthy, then flush (a 2nd POST, text matches a resolved pattern) | Exactly 2 POSTs total across three cycles — silent on the unchanged middle cycle because nothing new was queued |

## Edge Cases

- **Null and empty input**: `environment`, `state`, and `detail` are each checked for truthiness, not for absence specifically, so an empty string behaves identically to absent in every render path — MUST. `name` and `target` carry no such guard: `name` is interpolated into every rendered line unconditionally, so an empty-string `name` produces a line like `🔴 opened: ` with nothing after the colon rather than a validation error — MUST (this module never validates that `name` or `target` is non-empty). `target` never appears in the rendered `text`/`content` string at all in any `kind`; it is carried only in the structured `alerts` array of the payload — MUST.
- **Boundary values**: the 100th queued entry is kept and the 101st push causes the 1st to be dropped (status-server-monitor-alerts-009) — MUST. The 5,000ms abort deadline is a wall-clock boundary this module cannot make deterministic on its own; a request that settles at exactly 5,000ms is a race between the response and the abort that this module does not control — SHOULD be treated as "may or may not abort" rather than a guaranteed cutoff.
- **Concurrent access**: within one execution context, the enqueue operation and the drain step of the flush operation cannot interleave, because neither yields before mutating the queue — ordering inside one context is a fact of the runtime, not a race (queue-is-module-singleton) — MUST. Across execution contexts, the queue is NOT shared: each context loads its own instance of this module, so an alert queued in one context is invisible to, and undeliverable by, a flush called from another context (queue-is-per-thread-instance) — MUST. This module provides no cross-context synchronization of its own; every caller external to this module that queues an alert in one context MUST also flush from that same context, which is exactly the shape observed at this module's three real call sites (the monitor's own background worker; the two other sites on the API-serving context).
- **Error states**: a network failure or the 5,000ms abort during the POST is caught, logged, and the batch is dropped without retry — MUST (flush-fail-soft). A webhook receiver that responds with a non-2xx status is NOT distinguished from success by this module at all — see the `webhook-non-2xx-response` marker above; this is the one genuine gap in this module's error handling, not a case this recipe can state a defined MUST for.
- **Offline / disconnected state**: this module has no inbound connectivity of its own to lose; its analogue is the webhook receiver being unreachable or slow mid-POST, which is exactly the Error states case above — handled by the fixed 5,000ms timeout and fail-soft catch, with no retry and no backoff of any kind (see `webhook-non-2xx-response` and the `retry-with-backoff` compliance result below). A flush call made while there are no queued alerts and the destination is unreachable is indistinguishable from one made while everything is healthy, because `flush-noop-empty-queue` returns before any network attempt either way.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Destination (parameter to the flush operation) | string or null | none — caller-supplied per call | The webhook target for that flush. `null` disables delivery for that call while leaving the queue intact for a later flush with a non-null destination. This module never reads configuration itself. |
| `ALERT_WEBHOOK_URL` | environment variable, read by configuration external to this module | unset → `null` | The environment variable the shipped configuration reads to produce the destination value this module's external callers pass into the flush operation. |
| `ALERT_TIMEOUT_MS` (module constant) | number | `5_000` | Fixed per-POST deadline; not configurable per call and has no environment override in this module. |
| `MAX_QUEUED` (module constant) | number | `100` | Fixed queue bound; not configurable per call. |

## Deep Linking

Not applicable: this module defines no application URL scheme or route of its own — it only sends an outbound webhook POST to a caller-supplied destination, which is a payload destination this module is handed, not a deep-link target it defines.

## Localization

None of this module's user-facing strings route through a localization mechanism; every rendered alert-line fragment and the one error-log message are hardcoded English literals interpolated by the rendering step and the flush operation's failure-handling path. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse — and because these rendered lines are the text an on-call engineer reads in Slack or Discord, they are genuinely user-facing, not internal-only.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `🔴 opened` | Line prefix for an `opened` alert |
| n/a | `🗑 monitor removed:` | Line prefix for a `retired` alert |
| n/a | `✅ resolved:` | Line prefix for a `resolved` alert |
| n/a | `[alerts] webhook delivery failed (<n> alerts): <message>` | Logged on a caught delivery failure |

## Accessibility Options

Not applicable: this module has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system; the only on/off lever is the destination argument passed to the flush operation per call, already documented under Configuration and flush-noop-null-url, not a flag-service lookup.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: the alert's `target`, `name`, `environment`, `state`, and `detail` strings — infrastructure identifiers and status text describing a monitored site or deploy, sourced by callers external to this module (the issue ledger and monitor sync sweep) from roster and deploy metadata, never from an end user directly. This module constructs and transmits no credential, token, or personal end-user data.
- **Storage**: none. The queue is in-memory only; this module never writes an alert to disk or a database. An alert not yet delivered when the process exits is lost — there is no persistence to survive a restart.
- **Transmission**: every queued alert's fields, plus the derived `text`/`content` strings, are sent verbatim in the JSON body of one outbound POST per flush to the caller-supplied destination — an operator-controlled webhook receiver (Slack, Discord, ntfy, or a custom endpoint). This module does not validate or restrict the destination's scheme or host beyond whatever the underlying HTTP client itself enforces; whether that connection is encrypted is a property of the destination, not something this module chooses.
- **Retention**: not applicable to this module directly — once drained, an alert exists only inside the in-flight HTTP request; this module keeps no record of what it has previously sent.

## Logging

This module emits a single error-level log line with a literal `[alerts]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Webhook delivery failure (network error or 5,000ms abort) | error | `[alerts] webhook delivery failed (<n> alerts): <error message>` |

This is the only log line this module emits — a successful flush produces no log output at all, at any level.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
