// Outbound alerting: the monitor DETECTED outages but told no one — an issue
// was only visible to someone already looking at the wallboard. Issue
// open/resolve transitions queue here and each cycle flushes the queue as ONE
// webhook POST to ALERT_WEBHOOK_URL.
//
// The payload works with the common webhook receivers without per-vendor
// adapters: `text` renders on Slack, `content` on Discord, and `alerts` is the
// structured list for anything custom (ntfy, a Worker, etc.). Fail-soft +
// bounded — alerting must never take the cycle down. Unset URL = feature off.

export interface IssueAlert {
  /** `retired` = the MONITOR was deleted because what it watched stopped existing (the
   *  cycle's automatic removal). Distinct from `resolved` on purpose: nothing recovered,
   *  so claiming it did would tell on-call an outage cleared when it never did — but the
   *  `opened` alert sent days earlier still needs a counterpart, or the last word anyone
   *  hears about that target is a red one that no future cycle can ever close. */
  kind: 'opened' | 'resolved' | 'retired';
  target: string;
  name: string;
  environment: string | null;
  state: string | null;
  detail: string | null;
}

const ALERT_TIMEOUT_MS = 5_000;
/** Queue bound — alerts only ever accumulate within one cycle (the cycle
 *  flushes), so hitting this means something is very wrong; drop oldest. */
const MAX_QUEUED = 100;

const queue: IssueAlert[] = [];

/** Queue an issue transition for the next flush. Cheap + sync — safe to call
 *  from the recorders' hot path, with no config in scope there. Whether alerting
 *  is actually ON is `flushAlerts`' call to make (it takes the URL); an unqueued
 *  alert while alerting is off would leave the `opened` alert sent before it
 *  turned off with no `resolved`/`retired` counterpart once it turns back on. */
export function notifyIssueAlert(alert: IssueAlert): void {
  queue.push(alert);
  if (queue.length > MAX_QUEUED) queue.shift();
}

function line(a: IssueAlert): string {
  const env = a.environment ? ` (${a.environment})` : '';
  const state = a.state ? ` ${a.state}` : '';
  const detail = a.detail ? ` — ${a.detail}` : '';
  if (a.kind === 'opened') return `🔴 opened${state}: ${a.name}${env}${detail}`;
  if (a.kind === 'retired') return `🗑 monitor removed: ${a.name}${env}${detail}`;
  return `✅ resolved: ${a.name}${env}`;
}

/** POST every queued alert as one webhook. Called at the end of each monitor
 *  cycle with `config.alertWebhookUrl`; fail-soft (a down webhook endpoint is
 *  logged and the batch dropped — the open issue itself is durable in the DB
 *  either way). A null url (alerting off) leaves the queue for a later flush —
 *  bounded by MAX_QUEUED, never read from env here. */
export async function flushAlerts(url: string | null): Promise<void> {
  if (!url || queue.length === 0) return;
  const alerts = queue.splice(0);
  const text = alerts.map(line).join('\n');
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text, content: text, alerts }),
      signal: AbortSignal.timeout(ALERT_TIMEOUT_MS),
    });
  } catch (err) {
    console.error(`[alerts] webhook delivery failed (${alerts.length} alerts): ${err instanceof Error ? err.message : String(err)}`);
  }
}

/** Test hook — drop queued alerts. */
export function _resetAlerts(): void {
  queue.length = 0;
}
