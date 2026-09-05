import { describe, it, expect, vi } from 'vitest';
import { createScheduler } from '../src/scheduler';

describe('scheduler overlap guard', () => {
  it('does not start a second cycle while one is running', async () => {
    let running = 0;
    let maxConcurrent = 0;
    const cycle = vi.fn(async () => {
      running++;
      maxConcurrent = Math.max(maxConcurrent, running);
      await new Promise((r) => setTimeout(r, 20));
      running--;
    });
    const sched = createScheduler({ cycle, intervalMs: 1 });
    sched.start();
    await new Promise((r) => setTimeout(r, 60));
    sched.stop();
    expect(maxConcurrent).toBe(1);
    expect(sched.lastCycleAt()).not.toBeNull();
  });

  it('nextCycleAt tracks the interval GRID anchor (not lastCycleAt), re-anchoring on runNow', async () => {
    vi.useFakeTimers();
    try {
      const sched = createScheduler({ cycle: async () => {}, intervalMs: 60_000 });
      expect(sched.nextCycleAt()).toBeNull(); // not started yet

      const t0 = Date.now();
      sched.start(); // anchors the grid at t0 → next firing at t0 + interval
      await Promise.resolve(); // let the immediate boot cycle settle (clears inFlight)
      expect(sched.nextCycleAt()!.getTime()).toBe(t0 + 60_000);

      // A manual run partway through the interval does NOT shift the prediction…
      vi.advanceTimersByTime(20_000);
      expect(sched.nextCycleAt()!.getTime()).toBe(t0 + 60_000);

      // …until runNow re-anchors the grid to now (t0 + 20s) → next at +60s from there.
      const ran = await sched.runNow();
      expect(ran).toBe(true);
      expect(sched.nextCycleAt()!.getTime()).toBe(t0 + 20_000 + 60_000);

      sched.stop();
      expect(sched.nextCycleAt()).toBeNull(); // stopped → no scheduled tick
    } finally {
      vi.useRealTimers();
    }
  });

  it('passes manual:false to periodic/boot ticks and manual:true to runNow', async () => {
    // The cadence-decoupled cycle keys off this: a user-triggered "check now" forces a
    // full deploy sync, while the cheap timer ticks skip the expensive provider polls.
    const seen: boolean[] = [];
    const cycle = vi.fn(async ({ manual }: { manual: boolean }) => {
      seen.push(manual);
    });
    const sched = createScheduler({ cycle, intervalMs: 60_000 });
    sched.start(); // boot tick
    await Promise.resolve(); // let the immediate boot cycle settle
    expect(seen).toEqual([false]); // boot is not manual (index.ts fulls it via the time gate)

    const ran = await sched.runNow();
    expect(ran).toBe(true);
    expect(seen).toEqual([false, true]); // runNow → manual
    sched.stop();
  });

  it('runNow returns false when a cycle is already in flight (coalesced)', async () => {
    let release: (() => void) | null = null;
    const cycle = vi.fn(() => new Promise<void>((r) => (release = r)));
    const sched = createScheduler({ cycle, intervalMs: 60_000 });
    const first = sched.runNow(); // starts the cycle, holds it open
    const second = await sched.runNow(); // in-flight → coalesces
    expect(second).toBe(false);
    release!();
    expect(await first).toBe(true);
    expect(cycle).toHaveBeenCalledTimes(1);
  });

  it('self-heals when a cycle hangs — the cycle timeout abandons it so the loop resumes', async () => {
    vi.useFakeTimers();
    try {
      let started = 0;
      const cycle = vi.fn(() => {
        started += 1;
        // The first cycle hangs forever (an un-timed-out await inside runCycle);
        // every later cycle completes normally.
        return started === 1 ? new Promise<void>(() => {}) : Promise.resolve();
      });
      const sched = createScheduler({ cycle, intervalMs: 1_000, cycleTimeoutMs: 5_000 });
      sched.start(); // boot tick → cycle #1 hangs, holding the single-flight lock

      // While #1 is "in flight" the single-flight guard skips every interval tick —
      // this is the wedge that kept the deployed monitor frozen for ~32h.
      await vi.advanceTimersByTimeAsync(4_000);
      expect(cycle).toHaveBeenCalledTimes(1);
      expect(sched.lastCycleAt()).toBeNull();

      // Once the cycle timeout elapses the hung cycle is abandoned (inFlight cleared),
      // so a subsequent interval tick starts a fresh cycle that completes.
      await vi.advanceTimersByTimeAsync(4_000);
      sched.stop();
      expect(cycle.mock.calls.length).toBeGreaterThanOrEqual(2);
      expect(sched.lastCycleAt()).not.toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it('cycleStale trips when the loop has not completed a cycle within the window', async () => {
    vi.useFakeTimers();
    try {
      const sched = createScheduler({
        cycle: () => new Promise<void>(() => {}), // hangs → no cycle ever completes
        intervalMs: 1_000,
        cycleTimeoutMs: 60_000,
        staleAfterMs: 5_000,
      });
      expect(sched.cycleStale()).toBe(false); // not started → nothing to judge
      sched.start();
      expect(sched.cycleStale()).toBe(false); // inside the boot window
      await vi.advanceTimersByTimeAsync(6_000);
      expect(sched.cycleStale()).toBe(true); // no completed cycle past the window
      sched.stop();
      expect(sched.cycleStale()).toBe(false); // stopped → not judged
    } finally {
      vi.useRealTimers();
    }
  });

  it('cycleStale stays false while cycles keep completing', async () => {
    vi.useFakeTimers();
    try {
      const sched = createScheduler({ cycle: async () => {}, intervalMs: 1_000, staleAfterMs: 5_000 });
      sched.start();
      await vi.advanceTimersByTimeAsync(10_000); // many completed cycles across the window
      expect(sched.cycleStale()).toBe(false);
      sched.stop();
    } finally {
      vi.useRealTimers();
    }
  });
});
