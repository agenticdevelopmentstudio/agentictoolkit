import { describe, it, expect, vi } from 'vitest';
import { cachedSingleFlight } from '@agentic-toolkit/deploy-platform/util';

// The one TTL+single-flight primitive. Three routes had grown three copies of
// this (telemetry inline, reads.ts, app.ts) — and the app.ts copy, guarding the
// UNAUTHENTICATED status summary, was the one that forgot the single-flight.

describe('cachedSingleFlight', () => {
  it('collapses concurrent misses into ONE build', async () => {
    let builds = 0;
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const get = cachedSingleFlight(30_000, async () => {
      builds++;
      await gate;
      return { n: builds };
    });

    const all = Promise.all([get(), get(), get()]);
    release();
    const results = await all;

    expect(builds).toBe(1);
    expect(results.map((r) => r.n)).toEqual([1, 1, 1]); // every caller gets the same value
  });

  it('serves from cache inside the TTL and rebuilds after it', async () => {
    vi.useFakeTimers();
    try {
      let builds = 0;
      const get = cachedSingleFlight(30_000, async () => ({ n: ++builds }));
      expect((await get()).n).toBe(1);
      expect((await get()).n).toBe(1); // cached
      vi.advanceTimersByTime(31_000);
      expect((await get()).n).toBe(2); // TTL lapsed
    } finally {
      vi.useRealTimers();
    }
  });

  it('`fresh` bypasses the TTL but still JOINS an in-flight build', async () => {
    let builds = 0;
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const get = cachedSingleFlight(30_000, async () => {
      builds++;
      await gate;
      return { n: builds };
    });

    const inflight = get();
    const fresh = get(true); // a build started moments ago IS fresh — don't start a second
    release();
    await Promise.all([inflight, fresh]);
    expect(builds).toBe(1);
  });

  it('does not cache a FAILED build, and lets the next caller retry', async () => {
    let attempts = 0;
    const get = cachedSingleFlight(30_000, async () => {
      attempts++;
      if (attempts === 1) throw new Error('boom');
      return { ok: true };
    });

    await expect(get()).rejects.toThrow('boom');
    await expect(get()).resolves.toEqual({ ok: true }); // retried, not poisoned
    expect(attempts).toBe(2);
  });
});
