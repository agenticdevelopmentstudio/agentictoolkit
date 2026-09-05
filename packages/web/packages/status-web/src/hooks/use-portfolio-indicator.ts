import { useLiveSnapshot } from "./use-live-snapshot";
import { useBoard } from "./use-board";
import { snapshotFreshness } from "../lib/snapshot-staleness";
import { INDICATOR_STATE, type IndicatorState } from "../lib/overview";

export interface PortfolioIndicator {
  /** The status glyph key; "unknown" when the monitor can't claim any status. */
  pillKey: IndicatorState | "unknown";
  /** Problem count backing the sign. */
  count: number;
}

/**
 * The whole-portfolio status indicator, shared by the header pill
 * (StatusHeader) and the /home landing sign (BoardShell). Both derive from the
 * board (for what's wrong) and the live transport (for whether the data backing
 * that claim is fresh); sharing the derivation keeps the "when is status
 * unknown" rule in ONE place so the two signs can never disagree. Callers format
 * their own headline text from `pillKey`/`count`.
 */
export function usePortfolioIndicator(): PortfolioIndicator {
  const store = useLiveSnapshot();
  const { board } = useBoard();
  // Stale snapshot data can't back a confident status claim — surface "unknown" so
  // this pill and the /home sign AGREE with the board-wide SnapshotStaleBanner (one
  // staleness rule, shared via snapshotFreshness) instead of showing a green
  // "operational" over a red "monitoring paused". null lastCycleAt (no probe yet) is
  // fresh, so a healthy monitor is unaffected. This is a DIFFERENT fact from the
  // board's own staleness below: the live transport and the board poll fail
  // independently, and either one alone going stale is real information the other
  // can't stand in for.
  const stale =
    store.snapshot != null &&
    snapshotFreshness(store.snapshot.lastCycleAt, store.snapshot.generatedAt, store.snapshot.probeIntervalMs) !==
      "fresh";
  // `board === null`, not a `polling` test and not a deletion: this means "nothing
  // has come back yet, do not claim a colour" — and the thing that must now have
  // come back is the board. Without it the pill would render a false green
  // "operational" off nothing before the first read lands.
  //
  // Fix Round 3 item 1: `useBoard` itself now folds a STALE board (one that arrived
  // but hasn't refreshed in `BOARD_STALE_MS`) into this same `null`, so this hook no
  // longer computes its own `isBoardStale` term — `board === null` already covers
  // both "never arrived" and "gone stale" by construction, the same way every other
  // consumer of `useBoard` now does. See use-board.ts.
  const pillKey: IndicatorState | "unknown" =
    store.offline || store.blind || board === null || stale ? "unknown" : INDICATOR_STATE[board.indicator];
  return { pillKey, count: board?.problems.length ?? 0 };
}
