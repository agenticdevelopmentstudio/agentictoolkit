import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Board } from "../lib/board-types";
import { subscribeLiveFrames } from "./use-live-snapshot";
import { useNow } from "./use-now";
import { BOARD_POLL_INTERVAL_MS, isBoardStale, boardDataFreshness } from "../lib/board-staleness";

export { BOARD_POLL_INTERVAL_MS };

async function fetchBoard(): Promise<Board> {
  const res = await fetch("/api/board", { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`board fetch failed: ${res.status}`);
  return res.json();
}

/**
 * Why {@link UseBoardResult.board} is null; always null itself when `board` isn't.
 *
 * `stale`, `frozen` and `no-data` are three different failures and are deliberately not
 * one word: `stale` means the READ stopped arriving (the board's own `generatedAt` went
 * old), `frozen` means the read keeps arriving on time over FACTS that stopped moving (a
 * wedged monitor), and `no-data` means the board rests on no observation at all. They
 * fold to the same null board — none of them can back a claim — but a human staring at
 * the wallboard needs to know whether to look at the API, at the monitor process, or at
 * the config.
 *
 * `no-data` is split out for Fix Round 2 item C3: it is the NORMAL state of a roster with
 * nothing configured to observe, and reporting it as a wedged monitor sent a fresh
 * install to debug a monitor that was working perfectly. Still null, still never green —
 * only worded, and ordered against `blind`, by the consumer that can tell which it is.
 */
export type BoardUnavailableReason = "loading" | "unavailable" | "stale" | "frozen" | "no-data";

export interface UseBoardResult {
  /**
   * Null whenever the board CANNOT BACK A CURRENT CLAIM — {@link BoardUnavailableReason}
   * is the list of ways that happens, and is the only place it is spelled out (Fix
   * Round 2 item C4: every comment that re-listed the causes went stale the round a
   * cause was added). Never merely "arrived once, however long ago", and never merely
   * "arrived".
   * Fix Round 3 item 1: this is folded in HERE, the ONE place, rather than left for
   * every consumer to re-derive by also calling `isBoardStale` itself. Three
   * separate rounds produced three separate instances of exactly one bug — a
   * consumer that checked `board === null` but not whether a present board had gone
   * stale, and rendered a confident verdict off a frozen read — because `board`
   * used to mean only "hasn't arrived", leaving the second question optional. It no
   * longer is: every consumer gets the right answer by construction, not by
   * remembering to ask.
   */
  board: Board | null;
  /** Why `board` is null right now, for a caller that wants to word its own message
   *  differently per cause; always null when `board` itself is non-null. This is the
   *  ONLY loading/unavailability signal on this hook — a separate `isLoading` would be
   *  a second way to ask one question, which is the shape that caused the three-round
   *  bug above. A caller wanting the spinner tests `reason === "loading"`. */
  reason: BoardUnavailableReason | null;
  error: Error | null;
  refetch: () => void;
}

/**
 * The client's ONE source for the board. It fetches and renders; it does not derive,
 * accumulate, or persist. There is deliberately no localStorage here: the durable
 * client store is what let a fixed problem survive on one browser tab forever, because
 * a server-side fix had no way to reach into a tab's saved state and clear it.
 *
 * A problem that stops being derived server-side is simply absent from the next read.
 */
export function useBoard(): UseBoardResult {
  const q = useQuery<Board>({
    queryKey: ["board"],
    queryFn: fetchBoard,
    refetchInterval: BOARD_POLL_INTERVAL_MS,
    // Fix Round 2 item 5: matches useLiveSnapshot's own `retry: 1` (use-live-snapshot.ts),
    // the sibling feed that gates the SAME OverviewTab loading screen. Board and live
    // already poll every BOARD_POLL_INTERVAL_MS/POLL_INTERVAL_MS regardless, so React
    // Query's default (3 retries with growing backoff) only delays surfacing a genuinely
    // down backend behind a longer spinner — it doesn't make the eventual read any more
    // likely to succeed, and it is the auto-retry-loop-over-a-down-backend the sibling
    // hook's own comment explicitly avoids. One retry still absorbs a single transient
    // blip without the multi-second wait.
    retry: 1,
  });
  // The stream is the fast path; the poll above is the floor if it's down.
  useEffect(() => subscribeLiveFrames(() => void q.refetch()), [q.refetch]);

  // Fix Round 3 item 1: the ONE call site for `isBoardStale` on this feed —
  // `board-staleness.ts` still owns the rule and the threshold, this just applies
  // it before anything downstream ever sees `data`. React Query keeps the last
  // successful `data` on screen forever once `refetchInterval` starts failing (a
  // permanently-500ing `/api/board` never clears it on its own), so without this a
  // frozen board would keep reading as a current "operational" verdict forever.
  //
  // Fix Round 4 group 6 adds the second half of that sentence: a board can also keep
  // arriving perfectly on time and be just as unable to back a claim, because the
  // MONITOR wedged rather than the API. `generatedAt` is the derivation clock and is
  // re-stamped on every read, so `isBoardStale` is structurally blind to it; the
  // board's data clock is what catches it. Both fold into `board === null` here, in the
  // one place, for exactly the reason the first one does — a consumer that has to
  // remember to ask a second question is a consumer that will eventually forget.
  //
  // The data-clock window is cadence-scaled, so it needs the backend's probe interval —
  // taken off THE BOARD BEING JUDGED. It used to come off the live-snapshot singleton
  // instead, which meant the cadence and the clock it scales arrived on two different
  // feeds: null for every consumer that never opens the SSE stream (the header pill,
  // `usePortfolioIndicator`) and null again for every consumer that opens one but is asked
  // before the first frame lands, silently widening the window in exactly the cases where
  // it mattered. One board, one answer.
  const nowMs = useNow();
  const data = q.data ?? null;
  const dataFreshness =
    data == null ? null : boardDataFreshness(data.dataAsOfMs, data.generatedAt, data.probeIntervalMs);
  const reason: BoardUnavailableReason | null =
    data == null ? (q.isLoading ? "loading" : "unavailable")
    : isBoardStale(data.generatedAt, nowMs) ? "stale"
    : dataFreshness === "current" ? null
    : dataFreshness === "no-data" ? "no-data"
    : "frozen";

  return {
    board: reason == null ? data : null,
    reason,
    error: (q.error as Error | null) ?? null,
    refetch: () => void q.refetch(),
  };
}
