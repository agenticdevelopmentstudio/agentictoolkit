import type { ProviderDeploy } from "./provider-deploy";

/**
 * In-memory ring buffer of webhook-received deploy events, merged into /api/live
 * responses so a webhook shows up without waiting for the next provider poll.
 *
 * Module-scope by design: on a long-running server (local dev, Railway) this is
 * exact; on Vercel serverless it's BEST-EFFORT (each warm instance has its own
 * buffer, and an event may land on an instance /api/live never reads). That's
 * accepted — the 60s poll re-reads providers directly, so the buffer only ever
 * shortens latency, never carries truth the poll can't recover.
 */

export interface BufferedDeploy {
  deploy: ProviderDeploy;
  receivedAt: number; // ms — when the webhook arrived (server clock)
}

const CAP = 200;

const buffer: BufferedDeploy[] = [];

export function pushDeployEvent(deploy: ProviderDeploy): void {
  buffer.push({ deploy, receivedAt: Date.now() });
  if (buffer.length > CAP) buffer.splice(0, buffer.length - CAP);
}

/** Events received at/after `sinceMs` — newest info wins an id-merge downstream. */
export function deployEventsSince(sinceMs: number): BufferedDeploy[] {
  return buffer.filter((b) => b.receivedAt >= sinceMs);
}

/** Test hook — empty the buffer (module state persists across vitest cases). */
export function clearDeployEvents(): void {
  buffer.length = 0;
}
