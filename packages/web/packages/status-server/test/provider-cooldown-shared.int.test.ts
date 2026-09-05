import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import {
  noteRateLimited,
  rateLimitedUntil,
  cooldownState,
  _resetProviderCooldowns,
} from '@agentic-toolkit/deploy-platform/cooldown';

// The monitor cycle runs on a WORKER thread; the dashboard's /deploy-projects and
// /integrations enumerations call the same fetchers on the MAIN thread — against
// the same provider token. A 429 seen by one must back the other off, or the
// thread that didn't see it keeps hammering an already-throttled account and
// extends the throttle: the very "re-hit at cadence, never de-escalate" failure
// the cooldown exists to prevent, reincarnated at the thread boundary.

const workerPath = fileURLToPath(new URL('./helpers/cooldown-worker.mjs', import.meta.url));

let worker: Worker;

/** One request/response round trip to the worker. */
function ask(msg: Record<string, unknown>): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const onMessage = (reply: Record<string, unknown>): void => {
      worker.off('message', onMessage);
      resolve(reply);
    };
    worker.on('message', onMessage);
    worker.once('error', reject);
    worker.postMessage(msg);
  });
}

beforeEach(() => {
  _resetProviderCooldowns();
  // Spawn the worker with the SAME shared state the main thread holds — exactly
  // how worker-client.ts hands it to the monitor worker.
  worker = new Worker(workerPath, { workerData: { cooldowns: cooldownState() } });
});

afterEach(async () => {
  await worker.terminate();
});

describe('provider cooldown is shared across threads', () => {
  it('a 429 recorded on the MAIN thread stops the WORKER polling that provider', async () => {
    noteRateLimited('vercel', '120');

    const reply = await ask({ op: 'read', provider: 'vercel' });
    expect(reply.until).not.toBeNull();
    expect(Number(reply.until)).toBeGreaterThan(Date.now());
  }, 20_000);

  it('a 429 recorded on the WORKER stops the MAIN thread polling that provider', async () => {
    expect(rateLimitedUntil('railway')).toBeNull();

    await ask({ op: 'note', provider: 'railway', retryAfter: '90' });

    const until = rateLimitedUntil('railway');
    expect(until).not.toBeNull();
    expect(until!).toBeGreaterThan(Date.now());
  }, 20_000);

  it('leaves the OTHER providers pollable (per-provider, not a global stop)', async () => {
    noteRateLimited('cloudflare', '60');
    const cooled = await ask({ op: 'read', provider: 'cloudflare' });
    const other = await ask({ op: 'read', provider: 'crunchy' });
    expect(cooled.until).not.toBeNull();
    expect(other.until).toBeNull();
  }, 20_000);
});
