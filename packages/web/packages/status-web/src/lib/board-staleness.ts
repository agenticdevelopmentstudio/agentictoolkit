/**
 * How stale the BOARD ITSELF is — mirrors `snapshot-staleness.ts`'s pattern (one
 * clock, one threshold, one shared rule) so board freshness does not invent a second
 * staleness vocabulary. `generatedAt` IS the board read's own timestamp, and the
 * read can simply STOP arriving while React Query keeps the last successful `data`
 * on screen forever (`use-board.ts`).
 *
 * This is judged against the CLIENT clock (`useNow()`), NOT `store.snapshot`'s own
 * `generatedAt` — a second server timestamp the sole call site (`useBoard`) can reach
 * for, so it isn't that one is unavailable. (Fix Round 3 item 1 made `useBoard` that
 * sole call site; `usePortfolioIndicator` used to apply this rule a second time and
 * no longer does — `board === null` already covers it. This comment kept naming both
 * long after the second one was gone.) The real reason: board-to-snapshot goes blind
 * exactly when the two feeds
 * freeze TOGETHER — the same backend outage that stops `/api/board` responding
 * usually stops `/api/live` moments later too — which is the common failure this
 * module exists to catch, not a rare edge case. The client clock is the one
 * timestamp that keeps moving no matter which server-side feed has died, the same
 * one the rest of the view already uses for "time ago" labels.
 *
 * Accepted skew exposure, deliberately left uncorrected: a client clock running more
 * than `BOARD_STALE_MS` FAST false-trips a genuinely healthy board to "unknown" —
 * safe, if an annoyance. One running more than `BOARD_STALE_MS` SLOW masks a truly
 * frozen board past the point it should have gone stale — unsafe, but a multi-minute
 * clock skew on the viewer's own machine is a separate, much rarer failure than a
 * dead backend, and not one this module attempts to detect or correct for.
 *
 * Fix Round 2 item 3: `use-board.ts`'s `q.data ?? null` lets a permanently-500ing
 * `/api/board` leave the LAST GOOD board on screen forever, with the pill still
 * green — nobody read `Board.generatedAt` before this. A frozen board making a
 * current-looking claim is the same false claim C1 was about, just slower.
 */

import { snapshotStaleMs } from "./snapshot-staleness";

/** The board's own poll cadence (`use-board.ts`'s `refetchInterval`). Lives here, not
 *  in the hook, so this module — the one place the staleness threshold is derived —
 *  doesn't reach INTO a hook file for it. */
export const BOARD_POLL_INTERVAL_MS = 60_000;

/** A board is stale once it hasn't refreshed for 3 poll cycles — long enough that one
 *  missed poll (a slow request, a momentary blip) can't false-trip it, but short
 *  enough that a permanently-failing `/api/board` is caught well within a wallboard
 *  viewer's attention span. */
export const BOARD_STALE_MS = 3 * BOARD_POLL_INTERVAL_MS;

/**
 * Whether the board's own `generatedAt` is old enough that it can no longer back a
 * current claim. An unparseable `generatedAt` fails CLOSED — reads as STALE, not
 * fresh. This mirrors `row-model.ts`'s `deployDtoUnconfirmed`, not `snapshotFreshness`'s
 * choice for a missing clock: `snapshotFreshness`'s null `lastCycleAt` means "no
 * probe has run yet", a legitimately fresh state, but a GARBAGE `generatedAt` here
 * means "we cannot tell" — and this branch's rule is that an absence of a judgeable
 * claim must never render as health, the same reasoning `deployDtoUnconfirmed` already
 * applies to an unparseable confirmation clock. `board === null` (no board at all)
 * is the separate, stronger signal callers must still check first; this function
 * only judges a board that HAS arrived at least once — but having arrived with an
 * unparseable clock is no better than never having arrived.
 */
export function isBoardStale(generatedAt: string, nowMs: number): boolean {
  const age = nowMs - Date.parse(generatedAt);
  return !Number.isFinite(age) || age > BOARD_STALE_MS;
}

/**
 * How many write cadences of the board's SLOWEST heartbeat fact may pass before its data
 * clock can no longer back a current claim.
 *
 * Must be ≥ 2 — a window equal to the write cadence is crossed at the tail of EVERY
 * cycle by construction: the fact is written at the end of a cycle, so its age climbs to
 * one whole cadence (plus however long the next cycle takes) just before it is rewritten.
 * One cadence of headroom means one entirely missed cycle is absorbed and the second one
 * is not, which is the same "a single blip must not false-trip it, two must" rule
 * `BOARD_STALE_MS` applies to the read clock.
 */
export const BOARD_DATA_STALE_CYCLES = 2;

/**
 * How far the board's DATA clock may lag its DERIVATION clock before the board can no
 * longer back a current claim, for a backend probing at `probeIntervalMs`.
 *
 * Fix Round 2 item C2: this used to be the bare `SNAPSHOT_STALE_FLOOR_MS` constant — a
 * fixed 5 minutes — under a comment claiming it tracked the backend scheduler's
 * `staleAfterMs`. It did not: that rule is CADENCE-SCALED (`snapshotStaleMs` here,
 * `max(intervalMs * 5, 300_000)` at `src/scheduler.ts`), so the copy was wrong for every
 * non-default probe interval and broke the board twice over:
 *
 *   - `PROBE_INTERVAL_SECONDS=3600` (the value `playwright.auth.config.ts` and the
 *     verify-status-backend skill both use): five minutes after boot every fact is older
 *     than the fixed window, so `board === null` and the whole board is replaced by
 *     `UnknownBoardPanel` permanently.
 *   - A fleet with no HTTP endpoints, at the default 60s: the heartbeat fact is then the
 *     platform sample, rewritten on the full-sync cadence `max(300_000, probeIntervalMs
 *     * 5)` (`src/config.ts`) — EXACTLY the old fixed window, so the lag crossed it at
 *     the tail of every cycle and the board flapped to unknown once per cycle.
 *
 * So the window is derived, not restated: `snapshotStaleMs` is the one producer of "how
 * old is too old" (the same question `snapshotFreshness` asks of `/live`), and the
 * cycle multiplier above supplies the headroom the second failure needs. `snapshotStaleMs`
 * and the full-sync cadence are the same expression, which is why multiplying it is
 * enough to clear the cadence rather than merely equal it.
 *
 * A missing `probeIntervalMs` (an older backend, or the live snapshot not landed yet)
 * falls back to `snapshotStaleMs`'s own floor — the widest safe answer, never a narrower
 * one, so an unknown cadence can only delay the verdict, never false-trip it.
 */
export function boardDataStaleMs(probeIntervalMs?: number | null): number {
  return snapshotStaleMs(probeIntervalMs) * BOARD_DATA_STALE_CYCLES;
}

/**
 * What the board's data clock says about the board — three states, because two of them
 * are NOT the same failure and rendering them identically is how a healthy fresh install
 * got diagnosed as a broken monitor (Fix Round 2 item C3).
 *
 * - `current`   — the newest observation is recent enough to back what the board claims.
 * - `frozen`    — observations EXIST but have stopped arriving: a wedged monitor. Also
 *                 the verdict for an unparseable `generatedAt`, which fails CLOSED for
 *                 the same reason it does in `isBoardStale`.
 * - `no-data`   — the board rests on NO observation at all. Not health ("nothing has
 *                 been looked at" is never green), but not evidence of a fault either:
 *                 it is the correct, expected state of a roster with nothing configured
 *                 to observe and of a monitor that has not completed its first cycle.
 *                 The caller decides which of those it is — `OverviewTab` pairs it with
 *                 the live snapshot's `blind` to reach the actionable "no endpoints
 *                 configured" panel instead of "check the monitor process".
 */
export type BoardDataFreshness = "current" | "frozen" | "no-data";

/**
 * Fix Round 4 group 6: whether the board's facts have frozen underneath a monitor that
 * is still cycling. `isBoardStale` above cannot see this — it judges `generatedAt`,
 * which a wedged monitor keeps re-stamping fresh on every read while the endpoints and
 * platform samples it derives from stay exactly where they were. The board then serves
 * `indicator: "operational"` and an empty `problems` list forever, off last-known-healthy
 * data, and every one of those words is false.
 *
 * Judged SERVER-clock against SERVER-clock (`generatedAt` minus `dataAsOfMs`), the way
 * `snapshotFreshness` judges `/live` and deliberately NOT the way `isBoardStale` judges
 * the read itself: both ends come from the same machine, so this verdict is immune to
 * client clock skew and to a sleeping tab's throttled timers. The two rules compose —
 * `isBoardStale` catches a read that stopped ARRIVING, this catches a read that keeps
 * arriving over frozen FACTS — and neither can substitute for the other.
 */
export function boardDataFreshness(
  dataAsOfMs: number | null,
  generatedAt: string,
  probeIntervalMs?: number | null,
): BoardDataFreshness {
  if (dataAsOfMs === null) return "no-data";
  const lag = Date.parse(generatedAt) - dataAsOfMs;
  if (!Number.isFinite(lag)) return "frozen";
  return lag > boardDataStaleMs(probeIntervalMs) ? "frozen" : "current";
}
