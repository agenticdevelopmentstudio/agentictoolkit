/**
 * How stale the displayed status data is — the ONE staleness rule, shared by the
 * board-wide {@link SnapshotStaleBanner} and {@link usePortfolioIndicator} so the
 * banner and the header/home status sign can never disagree.
 *
 * The lag is measured SERVER-side: the snapshot's own `generatedAt` (stamped at read
 * time, server clock) minus its newest persisted probe `lastCycleAt` (also server
 * clock). Both ends are the server clock, so the verdict is immune to client clock
 * skew and to `setInterval`-based client timers being throttled while a tab sleeps —
 * comparing against the client's `Date.now()` would false-trip on either. Because the
 * client re-pulls `/live` on its own interval, each fresh snapshot re-stamps
 * `generatedAt` while a wedged poller's `lastCycleAt` stays frozen, so the lag still
 * grows and the banner still appears.
 *
 * The stale window scales with the probe interval (5× it, floored at 5min) to MIRROR
 * the backend scheduler's own `staleAfterMs` (src/scheduler.ts: `max(interval×5,
 * 5min)`), so raising `PROBE_INTERVAL_SECONDS` doesn't make a single skipped cycle
 * false-trip the banner. `very-stale` escalates the tone (amber → red) at 3× the
 * stale window.
 *
 * NB this is "how fresh is the data on screen" (newest persisted probe), which is a
 * DIFFERENT concern from the scheduler's cycle-COMPLETION health at `/health` — a
 * downstream cycle stage can hang after the probes were written, which `/health`
 * catches (and the container self-heals) while the on-screen data is still current.
 */
export type SnapshotFreshness = "fresh" | "stale" | "very-stale";

/** Stale-window floor — also the window used when the backend reports no interval
 *  (an older backend that predates the `probeIntervalMs` field). Matches the
 *  scheduler's 5min `staleAfterMs` floor. */
export const SNAPSHOT_STALE_FLOOR_MS = 5 * 60_000;

/** The stale window for a given probe interval: 5× the interval, floored. */
export function snapshotStaleMs(probeIntervalMs?: number | null): number {
  return Math.max((probeIntervalMs ?? 0) * 5, SNAPSHOT_STALE_FLOOR_MS);
}

export function snapshotFreshness(
  lastCycleAt: string | null | undefined,
  generatedAt: string | null | undefined,
  probeIntervalMs?: number | null,
): SnapshotFreshness {
  // No probe yet (zero-endpoint monitor) or no read clock → nothing to judge; no alarm.
  if (!lastCycleAt || !generatedAt) return "fresh";
  const ageMs = Date.parse(generatedAt) - Date.parse(lastCycleAt);
  const staleMs = snapshotStaleMs(probeIntervalMs);
  // `!(ageMs > staleMs)` (not `ageMs <= staleMs`) so an unparseable date → NaN → NaN
  // comparisons are false → we fall through to "fresh" rather than showing a banner.
  if (!(ageMs > staleMs)) return "fresh";
  return ageMs > staleMs * 3 ? "very-stale" : "stale";
}
