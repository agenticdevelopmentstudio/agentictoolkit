import { describe, it, expect } from 'vitest';
import { createDeployCadence } from '../src/monitor/cadence';

/** A cadence driven by a clock we advance by hand. */
function at(start = 1_000_000): { cadence: ReturnType<typeof createDeployCadence>; advance: (ms: number) => void } {
  let t = start;
  const cadence = createDeployCadence({ deploySyncIntervalMs: 300_000, firstDelayMs: 60_000, now: () => t });
  return { cadence, advance: (ms) => void (t += ms) };
}

describe('deploy cadence', () => {
  it('does NOT run the deploy phase on the boot tick', () => {
    // The whole crash-loop: a heavy boot cycle starves the loop, the supervisor misses 3
    // /health probes and restarts the container, which boots into the same heavy cycle.
    const { cadence } = at();
    expect(cadence.shouldFullSync(false)).toBe(false);
  });

  it('holds the deploy phase back until the first-sync delay has passed', () => {
    const { cadence, advance } = at();
    expect(cadence.shouldFullSync(false)).toBe(false); // boot
    advance(59_000);
    expect(cadence.shouldFullSync(false)).toBe(false); // still inside the grace window
    advance(1_000);
    expect(cadence.shouldFullSync(false)).toBe(true); // first full sync
  });

  it('then runs on the deploy interval, not every tick', () => {
    const { cadence, advance } = at();
    advance(60_000);
    expect(cadence.shouldFullSync(false)).toBe(true); // first
    advance(60_000);
    expect(cadence.shouldFullSync(false)).toBe(false); // a probe tick — stays cheap
    advance(240_000);
    expect(cadence.shouldFullSync(false)).toBe(true); // 300s after the last full sync
  });

  it('a manual check-now forces a full sync and re-anchors the interval', () => {
    const { cadence, advance } = at();
    expect(cadence.shouldFullSync(true)).toBe(true); // manual, even during boot grace
    advance(299_000);
    expect(cadence.shouldFullSync(false)).toBe(false); // re-anchored from the manual run
    advance(1_000);
    expect(cadence.shouldFullSync(false)).toBe(true);
  });
});
