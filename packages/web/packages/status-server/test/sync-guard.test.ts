import { describe, it, expect, vi } from 'vitest';
import { guard } from '../src/monitor/sync';

// The provider-poll guard is what stops ONE slow/hung platform from wedging the
// whole monitor cycle (an unbounded poll made the cycle blow the scheduler budget,
// which made the supervisor restart the container). These lock in: a hung poll is
// capped to the fallback, a throwing poll degrades to the fallback, and a fast poll
// passes through untouched.
describe('sync guard — provider poll cap', () => {
  it('caps a hung poll and resolves the fallback instead of hanging forever', async () => {
    vi.useFakeTimers();
    try {
      const fallback = { ok: false as const, deploys: [] as unknown[] };
      const p = guard('test', null, fallback, () => new Promise<typeof fallback>(() => {})); // never resolves
      await vi.advanceTimersByTimeAsync(20_000); // reach the cap
      await expect(p).resolves.toBe(fallback);
    } finally {
      vi.useRealTimers();
    }
  });

  it('degrades a throwing poll to the fallback', async () => {
    const fallback = { ok: false as const, deploys: [] as unknown[] };
    await expect(
      guard('test', null, fallback, async () => {
        throw new Error('boom');
      }),
    ).resolves.toBe(fallback);
  });

  it('passes a fast successful poll through unchanged', async () => {
    // Widen T explicitly so the fallback (ok:false) and the passed-through result
    // (ok:true) unify — the test only cares that the SAME object comes back.
    type Result = { ok: boolean; deploys: unknown[] };
    const fallback: Result = { ok: false, deploys: [] };
    const good: Result = { ok: true, deploys: [{ id: 'x' }] };
    await expect(guard('test', null, fallback, async () => good)).resolves.toBe(good);
  });
});
