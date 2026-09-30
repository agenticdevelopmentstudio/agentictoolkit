<!-- leaf: implement-status-server-monitor-1/alerts · source: status-server-monitor-alerts.md -->

**Rules** (cite as `implement-status-server-monitor-1/alerts#<slug>`):

- `issue-alert-shape` MUST
- `retired-kind-distinct-from-resolved` MUST
- `enqueue-synchronous` MUST
- `enqueue-independent-of-flush-config` MUST
- `queue-bounded-drop-oldest` MUST
- `flush-noop-null-url` MUST
- `flush-noop-empty-queue` MUST
- `flush-drains-before-sending` MUST
- `flush-single-batched-post` MUST
- `flush-request-shape` MUST
- `flush-timeout-5000ms` MUST
- `flush-fail-soft` MUST
- `render-opened` MUST
- `render-retired` MUST
- `render-resolved` MUST
- `render-lines-joined` MUST
- `reset-clears-queue` MUST
- `queue-is-module-singleton` MUST
- `queue-is-per-thread-instance` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` (parameter to `flushAlerts`) | `string \| null` | none — caller-supplied per call | The webhook target for that flush. `null` disables delivery for that call while leaving the queue intact for a later flush with a non-null url. This file never reads an environment variable itself. |
| `ALERT_WEBHOOK_URL` | environment variable, read by `config/env.ts`'s `alertWebhookUrl` getter (external to this file) | unset → `null` | The environment variable the shipped `StatusConfig` implementation reads to produce the `url` value this file's callers (`cycle-runner.ts`, `board/reconcile.ts`, `routes/hooks.ts`, all external) pass into `flushAlerts`. |
| `ALERT_TIMEOUT_MS` (module constant) | `number` | `5_000` | Fixed per-POST deadline via `AbortSignal.timeout`; not configurable per call and has no environment override in this file. |
| `MAX_QUEUED` (module constant) | `number` | `100` | Fixed queue bound; not configurable per call. |

## Localization

None of this file's user-facing strings route through a localization mechanism; every rendered alert-line fragment and the one `console.error` message are hardcoded English literals interpolated by `line()` and `flushAlerts`'s catch block. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse — and because these rendered lines are the text an on-call engineer reads in Slack or Discord, they are genuinely user-facing, not internal-only.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `🔴 opened` | Line prefix for an `opened` alert (`line()`) |
| n/a | `🗑 monitor removed:` | Line prefix for a `retired` alert (`line()`) |
| n/a | `✅ resolved:` | Line prefix for a `resolved` alert (`line()`) |
| n/a | `[alerts] webhook delivery failed (<n> alerts): <message>` | `console.error` on a caught delivery failure (`flushAlerts`) |

