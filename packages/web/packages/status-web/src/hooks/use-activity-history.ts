"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ActivityCursor, ActivityPage, ActivityRow } from "../lib/board-types";

/**
 * How many pages the pane may fetch back-to-back without the reader scrolling again.
 * The auto-continue exists so an ACTIVE FILTER can page past a stretch of non-matching
 * rows; the budget exists so a filter matching NOTHING cannot quietly drag 90 days of
 * history across the wire.
 */
export const MAX_AUTOPAGE_FETCHES = 5;

/** Page size — the server clamps to the same value. */
const PAGE_SIZE = 300;

/**
 * How long one page may take before it is abandoned.
 *
 * Without it a request that never settles (a dropped connection, a proxy holding the
 * socket, a laptop suspended mid-flight) strands `inFlight`/`loading` true for the life of
 * the tab: `loadOlder`'s first guard then rejects every later call, the pane's auto-fill is
 * gated on `!loading` so it never retries either, and "loading older activity…" is the last
 * thing the reader ever sees. Abandoning it surfaces the ordinary error line instead, which
 * the next scroll retries.
 */
const PAGE_TIMEOUT_MS = 20_000;

export interface UseActivityHistoryResult {
  /** Every loaded history row, oldest-first. */
  rows: ActivityRow[];
  loadOlder: () => void;
  loading: boolean;
  /** The server reported no facts older than the last page. */
  exhausted: boolean;
  /**
   * The last page FAILED. Distinct from `exhausted`: nothing was learned about what lies
   * behind the window, so the pane must say "couldn't load", never "beginning of history".
   */
  error: boolean;
  autoBudgetSpent: boolean;
  resetAutoBudget: () => void;
}

/** The feed's total order: `at` first, id as the tie-break — the same comparator the
 *  server sorts with (`derive-activity.ts`) and the same pair the cursor is built from. */
function byAtThenId(a: ActivityRow, b: ActivityRow): number {
  return a.at === b.at ? (a.id === b.id ? 0 : a.id < b.id ? -1 : 1) : a.at < b.at ? -1 : 1;
}

/** True when `r` sorts strictly before `oldest` in that order. */
function sortsBefore(r: ActivityRow, oldest: ActivityRow): boolean {
  return byAtThenId(r, oldest) < 0;
}

function sameRow(a: ActivityRow, b: ActivityRow): boolean {
  const ka = Object.keys(a) as (keyof ActivityRow)[];
  return ka.length === Object.keys(b).length && ka.every((k) => a[k] === b[k]);
}

/**
 * Merge by id into one oldest-first order, the INCOMING copy winning on a conflict.
 *
 * Incoming is always the more recent read of the same fact — a shed row is the last thing
 * the live window said about it, a paged row is the server's answer just now — so where
 * the two disagree, what is held is the older account. Keeping it was safe only while row
 * ids moved: a corrected row then arrived under a NEW id and got in beside the stale one,
 * visibly duplicated. Ids are stable now (see `derive-activity.ts`'s `deployRowId`), so
 * "existing wins" would silently drop the correction and leave the stale copy as the only
 * account of that deployment, with no later page able to repair it — cursors only move
 * backward. A row that is byte-identical still returns `prev` untouched, which is all the
 * original churn argument actually needed.
 */
function mergeRows(prev: ActivityRow[], incoming: ActivityRow[]): ActivityRow[] {
  const held = new Map(prev.map((r) => [r.id, r]));
  let changed = false;
  for (const r of incoming) {
    const have = held.get(r.id);
    if (have && sameRow(have, r)) continue;
    held.set(r.id, r);
    changed = true;
  }
  if (!changed) return prev;
  return [...held.values()].sort(byAtThenId);
}

/**
 * The loaded HISTORY, held separately from `board.activity`.
 *
 * They cannot share an array. Every SSE frame refetches `/api/board` and React Query
 * replaces the activity array wholesale (`use-board.ts:85`), so history merged into it
 * would be destroyed on the next frame — the pane would silently rewind to the top
 * mid-scroll. The pane concatenates the two at render time instead.
 *
 * This hook holds NO localStorage. The reasoning in `use-board.ts` applies unchanged: a
 * durable client store of server-derived rows is what let a fixed problem survive in one
 * browser tab forever.
 *
 * The array is deliberately UNCAPPED, and `mergeRows` re-sorts the whole of it. Both are
 * the right shape here. Its size is bounded by what the reader can actually reach — a page
 * costs a scroll gesture plus a budget reset, and `exhausted` stops `loadOlder` outright
 * once the server runs out of facts inside the 90-day retention — so this is a few
 * thousand rows at the far end of a determined scroll, sorted in a few milliseconds on the
 * one frame a page lands. A cap would be worse than the cost it saves: every row here IS
 * on screen or scrollable to, cursors only ever move backward, and nothing refetches a
 * window already read — so evicting rows would punch exactly the hole in the middle of the
 * feed that the shed-absorption effect below exists to prevent.
 */
export function useActivityHistory(opts: {
  /** False whenever the age-out filter would hide every row this could fetch. */
  enabled: boolean;
  /** The LIVE page, oldest-first — `board.activity` verbatim. */
  live: ActivityRow[];
}): UseActivityHistoryResult {
  const { enabled, live } = opts;
  const oldest = live[0] ?? null;
  const [rows, setRows] = useState<ActivityRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [exhausted, setExhausted] = useState(false);
  const [error, setError] = useState(false);
  const [autoBudgetSpent, setAutoBudgetSpent] = useState(false);

  // `loadOlder`'s control state (the cursor, the fetch count, the re-entrancy latch, and
  // the caller's latest `enabled`/`oldest`) lives in refs, NOT `useState`. If it lived in
  // state, `loadOlder`'s `useCallback` would have to close over it and its identity would
  // change on every fetch — and the NEXT task's auto-continue effect depends on this
  // hook's returned object, so a churning `loadOlder` would re-arm that effect after
  // every page rather than only when the caller's own `enabled`/`oldest` change. Refs let
  // `loadOlder` close over nothing and keep one stable identity for the hook's lifetime;
  // `rows`/`loading`/`exhausted`/`autoBudgetSpent` still live in `useState` because those
  // are the only fields a render needs to react to.
  const enabledRef = useRef(enabled);
  const oldestRef = useRef(oldest);
  const cursorRef = useRef<ActivityCursor | null>(null);
  const fetchesRef = useRef(0);
  const exhaustedRef = useRef(false);
  const inFlight = useRef(false);
  // Has the reader started paging? Set the instant the FIRST request goes out, not when it
  // lands — see the shed-absorption effect, which has to keep rows the live window drops
  // while that first page is still on the wire. It is also the only honest test for "has
  // paged": a first page that legitimately comes back `{ rows: [], nextCursor: null }`
  // leaves both `rows` and `cursorRef` empty, and reading either as "never paged" would
  // silently disable shed-absorption for the life of the tab.
  const pagedRef = useRef(false);
  const abortRef = useRef<AbortController | null>(null);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      abortRef.current?.abort();
    };
  }, []);
  // Bumped every time history is discarded. A fetch that was already on the wire when the
  // reader switched age-out back on would otherwise land in `finally`/`setRows` AFTER the
  // reset and re-populate the history it just cleared — with `cursorRef` now null, so the
  // next page would continue from the live tail again and the pane, which concatenates
  // without re-sorting, would render those orphans out of order. A response from a
  // superseded epoch is dropped whole.
  const epoch = useRef(0);

  enabledRef.current = enabled;
  oldestRef.current = oldest;

  // Turning the age-out filter back on discards history rather than holding it: it is
  // invisible under any TTL, and keeping it would make the memory cost of a scroll
  // permanent for the session.
  useEffect(() => {
    if (!enabled) {
      setRows([]);
      setLoading(false);
      setExhausted(false);
      setError(false);
      setAutoBudgetSpent(false);
      cursorRef.current = null;
      fetchesRef.current = 0;
      exhaustedRef.current = false;
      inFlight.current = false;
      pagedRef.current = false;
      abortRef.current?.abort();
      abortRef.current = null;
      epoch.current += 1;
    }
  }, [enabled]);

  // ONCE THE READER HAS PAGED BACK, catch every row the live window SHEDS.
  //
  // `board.activity` is a WINDOW — capped at MAX_ACTIVITY_ROWS and floored 24h back — so
  // its oldest row keeps moving NEWER as deploys land and time passes. History was paged
  // from wherever that oldest row sat when the scroll began, so a row the window drops
  // afterwards falls out of BOTH lists: a hole in the middle of the feed that grows for as
  // long as the tab stays open, with nothing on screen marking it. Catching it costs no
  // request at all — it was present in a frame this client already received, so keeping it
  // is strictly cheaper than fetching it back.
  //
  // Only what LEFT the window is kept, never the window itself: history is the scroll-back
  // buffer, and copying live rows into it would just double them (the pane concatenates
  // both lists) and grow an idle tab's memory for a scroll nobody performed. Before the
  // reader has paged at all there is no history to hole, so shed rows are simply let go —
  // the next page then starts from wherever the window's oldest row has moved to.
  //
  // Not a durable store: in-memory, dropped the moment age-out comes back on, and holding
  // timestamped EVENTS rather than current state — the hazard `use-board.ts` warns about
  // (a fixed problem surviving in one tab forever) needs mutable state to bite.
  //
  // TWO GUARDS decide what counts as shed, because "an id left `board.activity`" is not
  // the same claim as "the window slid past this row", and only the second one is safe to
  // freeze. A row can leave the live window for reasons that have nothing to do with age:
  // a `deploying` deployment superseded by the next promotion is re-mapped to phase `none`
  // and its deploy row simply stops being derived (`vercelPhases`, `railwayPhases`,
  // and `reconcile-stuck-deploys`'s `collapseInFlightDeploySql("none")`); an operator
  // disabling or renaming an endpoint drops every row `ownedDeployTarget` no longer
  // claims; MAX_ACTIVITY_ROWS evicts the oldest under a burst; and a server change to the
  // id grammar retires every id at once. Each of those hands this effect a row that is
  // still mid-flight, and freezing it produces exactly the bug this file's history is
  // about — a permanent "building" for a deployment that finished, which no refetch can
  // reach because it no longer lives in `board.activity`.
  const prevLive = useRef<ActivityRow[]>(live);
  useEffect(() => {
    // An EMPTY live window is not a shed. `use-board.ts` returns a null board while a read
    // is stale (≥3min) or the monitor's data is frozen (≥10min), and OverviewTab passes
    // `board?.activity ?? []`, so an ordinary API blip arrives here as "all 300 rows left
    // at once". Returning BEFORE `prevLive` is updated is deliberate: the pre-blip window
    // survives, so whatever genuinely ages out during the outage is still caught when the
    // board comes back.
    const oldest = live[0];
    if (oldest == null) return;
    const stillLive = new Set(live.map((l) => l.id));
    const shed = prevLive.current.filter(
      (r) =>
        !stillLive.has(r.id) &&
        // GUARD 1 — it must have fallen off the OLD end. That is the only shed this
        // effect was built for (the window's oldest row keeps moving newer), and it is
        // what separates aging out from every other exit above, none of which leave a row
        // sorting behind what the window still holds.
        sortsBefore(r, oldest) &&
        // GUARD 2 — never freeze a row still asserting progress. The server's own
        // freshness contract terminalizes an unconfirmed in-flight phase at 6h
        // (`expireUnconfirmedDeploys`), far inside the 24h floor, so a `progress` row
        // reaching the floor is already anomalous — and a frozen one is a claim about a
        // live build that nothing will ever re-confirm.
        r.tone !== "progress",
    );
    prevLive.current = live;
    if (!enabled || shed.length === 0) return;
    if (!pagedRef.current) return;
    setRows((prev) => mergeRows(prev, shed));
  }, [enabled, live]);

  const loadOlder = useCallback(() => {
    if (
      !enabledRef.current ||
      inFlight.current ||
      exhaustedRef.current ||
      fetchesRef.current >= MAX_AUTOPAGE_FETCHES
    ) {
      return;
    }
    // The first page continues from the live tail's oldest row; later pages from the
    // server's own cursor. With NEITHER — a quiet fleet whose 24h window holds nothing at
    // all, which is precisely the case this feature was built for — the request goes out
    // with no cursor and the server serves the newest page it has. Returning here instead
    // left the pane empty and inert over a database holding 90 days of history.
    const liveOldest = oldestRef.current;
    const from: ActivityCursor | null =
      cursorRef.current ?? (liveOldest ? { atMs: Date.parse(liveOldest.at), id: liveOldest.id } : null);

    inFlight.current = true;
    pagedRef.current = true;
    setLoading(true);
    setError(false);
    fetchesRef.current += 1;
    if (fetchesRef.current >= MAX_AUTOPAGE_FETCHES) setAutoBudgetSpent(true);
    const q = new URLSearchParams({ limit: String(PAGE_SIZE) });
    if (from != null) {
      q.set("before", String(from.atMs));
      q.set("beforeId", from.id);
    }
    const myEpoch = epoch.current;
    const controller = new AbortController();
    abortRef.current = controller;
    const timer = setTimeout(() => controller.abort(), PAGE_TIMEOUT_MS);
    void (async () => {
      try {
        const res = await fetch(`/api/activity?${q}`, {
          headers: { accept: "application/json" },
          signal: controller.signal,
        });
        if (!res.ok) throw new Error(`activity fetch failed: ${res.status}`);
        const page: ActivityPage = await res.json();
        if (epoch.current !== myEpoch || !mounted.current) return;
        // `mergeRows` sorts rather than assuming the page is strictly older than what is
        // already loaded. It usually is — but the effect above puts SHED live rows into the
        // same array, and those are NEWER than everything paged, so "prepend and hope"
        // would render the feed out of order the first time the window dropped a row.
        setRows((prev) => mergeRows(prev, page.rows));
        cursorRef.current = page.nextCursor;
        exhaustedRef.current = page.nextCursor == null;
        setExhausted(exhaustedRef.current);
      } catch {
        // A failed page is not the end of history — leave the cursor alone so the next
        // scroll retries the same window rather than skipping it. The fetch count is NOT
        // rolled back, though: it was already spent above, so a filter that matches
        // nothing but errors on every page still stops after MAX_AUTOPAGE_FETCHES instead
        // of retrying the same failing window forever.
        //
        // It IS reported. Swallowed, a 500 was indistinguishable from "nothing older
        // exists" — the pane would sit blank with no line explaining it, and the auto-fill
        // rule would keep firing at a broken endpoint because nothing told it to stop.
        // An ABORT lands here too — the timeout above, or unmount. Both are honest errors
        // from the reader's side: nothing was learned about what lies behind the window.
        if (mounted.current && epoch.current === myEpoch) setError(true);
      } finally {
        clearTimeout(timer);
        if (abortRef.current === controller) abortRef.current = null;
        // Same epoch guard: the reset already cleared both, and clearing them again could
        // unlatch a fetch started after a re-enable.
        if (epoch.current === myEpoch) {
          inFlight.current = false;
          if (mounted.current) setLoading(false);
        }
      }
    })();
  }, []);

  const resetAutoBudget = useCallback(() => {
    fetchesRef.current = 0;
    setAutoBudgetSpent(false);
  }, []);

  return {
    rows,
    loadOlder,
    loading,
    exhausted,
    error,
    autoBudgetSpent,
    resetAutoBudget,
  };
}
