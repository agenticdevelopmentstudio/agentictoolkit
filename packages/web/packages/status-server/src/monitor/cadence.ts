/**
 * When the expensive deploy phase (provider polls + peers + telemetry) is allowed to run.
 *
 * The boot tick must stay CHEAP. `start.py` probes `/health` every 60s and, after 3
 * consecutive misses, restarts the WHOLE container — frontend included. A boot cycle that
 * runs the heavy phase starves the loop right through that window, so the container dies,
 * boots, and runs the same heavy cycle again: a crash LOOP it can never escape (which is
 * exactly what it did — every restart re-entered the boot full sync). Holding the first
 * full sync back by {@link FIRST_FULL_SYNC_DELAY_MS} lets the process answer a few probes
 * before it takes on the expensive work. The fleet is still PROBED on the boot tick — only
 * the provider/telemetry phase waits — so the board is never blank, just deploy-less for
 * one interval.
 */
export const FIRST_FULL_SYNC_DELAY_MS = 60_000;

export interface DeployCadence {
  /** True when THIS tick should run the expensive deploy phase. A `manual` check-now
   *  always forces one (and re-anchors the interval from now). */
  shouldFullSync(manual: boolean): boolean;
}

export function createDeployCadence(opts: {
  deploySyncIntervalMs: number;
  /** Delay before the FIRST full sync after boot. Defaults to {@link FIRST_FULL_SYNC_DELAY_MS}. */
  firstDelayMs?: number;
  /** Injectable clock (tests). */
  now?: () => number;
}): DeployCadence {
  const now = opts.now ?? Date.now;
  const firstDelayMs = opts.firstDelayMs ?? FIRST_FULL_SYNC_DELAY_MS;
  let nextFullSyncAt = now() + firstDelayMs;

  return {
    shouldFullSync(manual: boolean): boolean {
      const t = now();
      if (!manual && t < nextFullSyncAt) return false;
      nextFullSyncAt = t + opts.deploySyncIntervalMs;
      return true;
    },
  };
}
