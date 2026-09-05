"use client";
import { useCallback, useEffect, useSyncExternalStore } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { LiveSnapshot } from "../lib/live-types";

export const POLL_INTERVAL_MS = 60_000;
/** Clear a manual-check spinner after this long even if no snapshot arrives — the
 *  backstop for a check that ran but whose push never landed (stream wedged).
 *
 *  Sized to OUTLAST a real cycle: POST /live/check returns the moment the cycle
 *  STARTS (the backend runs it detached, since a manual full sync polls every
 *  provider and can take minutes), so this timer runs concurrently with the whole
 *  sync — not, as it once did, with the tail end of an already-finished one. At
 *  the old 12s it fired on essentially every manual check, clearing the spinner
 *  while the providers were still being polled and telling the user the check had
 *  finished when it had barely begun. The backend's own cycle budget is
 *  max(3× the probe interval, 2min), so give it that plus margin. */
const CHECK_SAFETY_MS = 200_000;
/** Backoff before recreating an EventSource that PERMANENTLY closed (a non-200 on
 *  connect — auth expiry, 5xx — which the browser does NOT auto-retry). */
const STREAM_REOPEN_MS = 3_000;

// ---------------------------------------------------------------------------
// ONE module-scope store. The hook is mounted by the header pill AND OverviewTab
// (sections) — a per-component useState would fork the store. All shared state
// lives here.
//
// This is the TRANSPORT half only: one ref-counted EventSource (/api/live/stream)
// as the PRIMARY feed — the backend pushes a snapshot on every cycle and on each
// webhook — with the React Query poll as the FALLBACK, gated off while the stream
// is connected. It answers "what did the last probe cycle see" (services,
// deployments, lastCycleAt, probeIntervalMs, monitorVersion, configDegraded).
//
// It does NOT fold frames into a durable model any more — that was the defect
// (see use-board.ts / board-types.ts, which answer "what is wrong and what
// happened" from the server-derived board instead). `subscribeLiveFrames` lets
// that hook piggyback on this same feed without opening a second connection.
// ---------------------------------------------------------------------------

interface StoreView {
  snapshot: LiveSnapshot | null;
  /** Whether the SSE stream is currently open. While true the poll stands down. */
  streamConnected: boolean;
  /** Backend-reported time of the next scheduled cycle (ms) — the TRUE cadence
   *  the countdown should show. Null until the stream reports a schedule frame. */
  nextCheckAt: number | null;
  /** A manual check is in flight (from the click until the user's own result lands). */
  awaitingCheck: boolean;
  /** The last /api/live read FAILED and nothing has succeeded since — the message, or
   *  null while the read path is healthy. Owned here rather than read off React Query's
   *  `isError`, which is not a usable outage signal on a COLD board: with no cached data
   *  the query resets to `status:'pending'` at the start of every refetch, so `isError`
   *  is only true for the sliver between exhausting its retries and the next attempt.
   *  A page opened while the backend redeploys — exactly what the reconnect overlay is
   *  for — therefore never held the flag long enough for the overlay's 1.2s show delay,
   *  and the board sat on "Loading…" forever instead. This flag flips on a failed read
   *  and clears only on a successful one, so it stays asserted across the whole outage. */
  liveError: string | null;
}

/** The pre-anything view. One factory, because `__resetStoreForTests` has to produce
 *  EXACTLY this — a reset that drifts from the initializer leaves tests running against
 *  a shape the app never has. */
const freshView = (): StoreView => ({
  snapshot: null, streamConnected: false, nextCheckAt: null, awaitingCheck: false, liveError: null,
});

let view: StoreView = freshView();
const SERVER_VIEW: StoreView = view; // stable ref for SSR — first client paint matches
let lastIngested: LiveSnapshot | null = null;
/** When the user's in-flight manual check was requested (ms). The spinner clears
 *  only once a snapshot BUILT AFTER this lands — an unrelated earlier push doesn't
 *  count as "their check finished". Null when no check is pending. */
let awaitingCheckSince: number | null = null;
let checkSafetyTimer: ReturnType<typeof setTimeout> | null = null;
const listeners = new Set<() => void>();

function notify(): void {
  for (const l of listeners) l();
}

/** Replace `view` with a patched copy and notify — but only if something actually
 *  changed, so a no-op patch (e.g. repeated stream-error events) doesn't re-render. */
function patch(next: Partial<StoreView>): void {
  let changed = false;
  for (const k of Object.keys(next) as (keyof StoreView)[]) {
    if (view[k] !== next[k]) {
      changed = true;
      break;
    }
  }
  if (!changed) return;
  view = { ...view, ...next };
  notify();
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  acquireStream(); // open the SSE stream while at least one component is mounted
  return () => {
    listeners.delete(cb);
    releaseStream();
  };
}

function getView(): StoreView {
  return view;
}

function getServerView(): StoreView {
  return SERVER_VIEW;
}

/** Two snapshots are the SAME delivery iff identical object OR identical build
 *  clock — a cheap skip for a re-delivered frame. */
export function isSameSnapshot(a: LiveSnapshot | null, b: LiveSnapshot): boolean {
  return a !== null && (a === b || a.generatedAt === b.generatedAt);
}

const frameSubscribers = new Set<() => void>();

/**
 * Every ingested live frame, from either feed. `useBoard` refetches on these rather than
 * opening a SECOND EventSource: the board and the snapshot answer different questions but
 * they change at the same moments, and one connection per tab is the existing contract.
 *
 * Deliberately NOT the `listeners` set above — that fires on every connection-state change.
 */
export function subscribeLiveFrames(cb: () => void): () => void {
  frameSubscribers.add(cb);
  return () => frameSubscribers.delete(cb);
}

/** Fold a snapshot exactly once and notify. Module-level so N mounted hooks (and
 *  StrictMode double-effects) can't double-ingest. */
function ingestOnce(snap: LiveSnapshot): void {
  if (isSameSnapshot(lastIngested, snap)) return;
  lastIngested = snap;
  // Clear the spinner only for a snapshot built AT/AFTER the user's own check
  // request — not for an unrelated push that happened to be in flight.
  const resolvesCheck = awaitingCheckSince != null && Date.parse(snap.generatedAt) >= awaitingCheckSince;
  if (resolvesCheck) {
    awaitingCheckSince = null;
    clearCheckSafety();
  }
  patch(resolvesCheck ? { snapshot: snap, awaitingCheck: false } : { snapshot: snap });
  for (const cb of frameSubscribers) cb();
}

function clearCheckSafety(): void {
  if (checkSafetyTimer != null) {
    clearTimeout(checkSafetyTimer);
    checkSafetyTimer = null;
  }
}

// --- SSE stream singleton ----------------------------------------------------
// One EventSource per tab, ref-counted by the N mounted hooks (header pill +
// OverviewTab). The browser auto-reconnects on a NETWORK drop; a non-200 response
// (auth expiry, 5xx) permanently CLOSES it, so we detect readyState=CLOSED and
// recreate after a backoff — otherwise the tab is stuck on the poll forever.

let es: EventSource | null = null;
let streamRefs = 0;
let reopenTimer: ReturnType<typeof setTimeout> | null = null;

function openStream(): void {
  if (es || typeof window === "undefined" || typeof EventSource === "undefined") return;
  const source = new EventSource("/api/live/stream");
  es = source;
  source.addEventListener("open", () => patch({ streamConnected: true }));
  source.addEventListener("snapshot", (e) => onSnapshotFrame((e as MessageEvent).data));
  source.addEventListener("schedule", (e) => onScheduleFrame((e as MessageEvent).data));
  source.addEventListener("error", () => {
    // CONNECTING → the browser is auto-retrying a transient drop; just reflect the
    // gap. CLOSED → a permanent failure the browser won't retry; recreate ourselves.
    if (source.readyState === EventSource.CLOSED) {
      if (es === source) es = null;
      source.close();
      patch({ streamConnected: false, nextCheckAt: null });
      scheduleReopen();
    } else {
      patch({ streamConnected: false });
    }
  });
}

function scheduleReopen(): void {
  if (reopenTimer != null || streamRefs <= 0) return;
  reopenTimer = setTimeout(() => {
    reopenTimer = null;
    if (streamRefs > 0) openStream();
  }, STREAM_REOPEN_MS);
}

function onSnapshotFrame(data: string): void {
  try {
    ingestOnce(JSON.parse(data) as LiveSnapshot);
  } catch {
    // a malformed frame is dropped; the next frame (or the poll fallback) recovers
  }
}

function onScheduleFrame(data: string): void {
  try {
    const { nextCheckAt } = JSON.parse(data) as { nextCheckAt: string | null };
    patch({ nextCheckAt: nextCheckAt ? Date.parse(nextCheckAt) : null });
  } catch {
    // ignore — the countdown falls back to the client estimate
  }
}

function acquireStream(): void {
  streamRefs += 1;
  openStream();
}

/** Test hook — reset the module singleton between cases (it persists across renders
 *  by design, so tests must clear it to stay isolated). Deliberately leaves
 *  `frameSubscribers` alone — clearing it would silently unsubscribe a mounted
 *  `useBoard` out from under a test's store reset. */
export function __resetStoreForTests(): void {
  view = freshView();
  lastIngested = null;
  awaitingCheckSince = null;
  clearCheckSafety();
  listeners.clear();
  if (reopenTimer != null) {
    clearTimeout(reopenTimer);
    reopenTimer = null;
  }
  es?.close();
  es = null;
  streamRefs = 0;
}

function releaseStream(): void {
  streamRefs -= 1;
  if (streamRefs <= 0) {
    streamRefs = 0;
    if (reopenTimer != null) {
      clearTimeout(reopenTimer);
      reopenTimer = null;
    }
    es?.close();
    es = null;
    patch({ streamConnected: false, nextCheckAt: null });
  }
}

async function fetchLive(): Promise<LiveSnapshot> {
  // The poll is a plain re-read of the latest DB snapshot (the check runs on the
  // backend; ?fresh had no effect on /live, so it's gone — see /live/check).
  // Every outcome is recorded in `liveError` — this is the single place the read
  // happens, so it is the honest place to say whether the backend is answering.
  try {
    const r = await fetch("/api/live");
    if (!r.ok) throw new Error(`live ${r.status}`);
    const snapshot = (await r.json()) as LiveSnapshot;
    patch({ liveError: null });
    return snapshot;
  } catch (e) {
    patch({ liveError: e instanceof Error ? e.message : String(e) });
    throw e;
  }
}

export interface LiveSnapshotStore {
  /** The latest raw snapshot (services list etc.) — null before the first poll. */
  snapshot: LiveSnapshot | null;
  /** The live feed is failing: the poll errored, the stream is not connected, and
   *  no re-read is in flight — the status site can't see anything; show the stop sign. */
  offline: boolean;
  /** Like `offline` but STABLE across an in-flight re-read: the poll last errored and
   *  the stream is down, regardless of whether a probe is currently running. `offline`
   *  flaps false during every poll/retry (its `!isFetching` term); the reconnect
   *  overlay needs a signal that stays asserted through those probes so it doesn't
   *  strobe and its outage clock keeps accumulating. */
  disconnected: boolean;
  /** The last snapshot monitored NOTHING (no endpoints) — the monitor is just
   *  as blind as offline; consumers must never read green from it. */
  blind: boolean;
  /** The live-feed error text while disconnected (stable across probes) — for the
   *  reconnect overlay's detail line. Null when the feed is healthy. */
  offlineDetail: string | null;
  polling: boolean;
  /** When the next check fires — drives the countdown. Backend cadence while the
   *  stream is connected; a client estimate off the last poll otherwise. */
  nextPollAt: number | null;
  /** Ask the backend to run a full check NOW (POST /api/live/check); the fresh result
   *  arrives via the stream (or, in fallback, a follow-up poll). The heavyweight
   *  provider fan-out — for the explicit Overview refresh button, NOT auto-retry. */
  refresh: () => void;
  /** Cheap reachability re-read (GET /api/live) — the reconnect overlay's retry. Does
   *  NOT kick a provider fan-out, so an auto-retry loop can't hammer a down backend. */
  reconnect: () => void;
}

export function useLiveSnapshot(): LiveSnapshotStore {
  const queryClient = useQueryClient();
  const { snapshot, streamConnected, nextCheckAt, awaitingCheck, liveError } = useSyncExternalStore(
    subscribe,
    getView,
    getServerView,
  );

  // The poll is the FALLBACK: every auto-refetch trigger stands down while the
  // stream is connected (an idempotent fold makes a stray poll harmless, but there's
  // no reason to do the redundant work / provider fan-out).
  const query = useQuery<LiveSnapshot>({
    queryKey: ["live"],
    queryFn: fetchLive,
    refetchInterval: streamConnected ? false : POLL_INTERVAL_MS,
    refetchOnWindowFocus: !streamConnected,
    refetchOnMount: !streamConnected,
    refetchOnReconnect: !streamConnected,
    retry: 1,
  });

  const { data, dataUpdatedAt } = query;
  useEffect(() => {
    // External-store sync (the sanctioned exception): hand each poll result to the
    // singleton. ingestOnce is idempotent, so this is safe even if it races a
    // stream push of the same cycle.
    if (data) ingestOnce(data);
  }, [data]);

  useEffect(() => {
    // On losing the stream, re-read immediately so `offline` and the data reflect
    // CURRENT backend health rather than a stale, possibly hours-old, poll error.
    if (!streamConnected) void queryClient.refetchQueries({ queryKey: ["live"] });
  }, [streamConnected, queryClient]);

  const refresh = useCallback(() => {
    clearCheckSafety();
    awaitingCheckSince = Date.now();
    patch({ awaitingCheck: true });
    void (async () => {
      let ran = false;
      try {
        const r = await fetch("/api/live/check", { method: "POST" });
        if (r.ok) {
          const body = (await r.json().catch(() => null)) as { ran?: boolean } | null;
          ran = body?.ran !== false; // explicit ran:false = debounced/coalesced
        }
      } catch {
        // network error — treated as "no fresh cycle coming"
      }
      if (!ran) {
        // Debounced, coalesced, or failed: NO new cycle is coming, so the freshest
        // truth is whatever already landed in the DB — re-read it now (the stream
        // isn't going to push anything for this click).
        if (!view.streamConnected) void queryClient.refetchQueries({ queryKey: ["live"] });
        awaitingCheckSince = null;
        patch({ awaitingCheck: false });
        return;
      }
      // A cycle STARTED. The backend answers immediately (detached), so re-reading
      // /live right now would just fetch the PRE-cycle snapshot — stale by
      // construction, and unable to resolve the check. The result arrives when the
      // cycle finishes: pushed over the stream, or picked up by the fallback poll
      // (which keeps running on its own cadence while the stream is down).
      checkSafetyTimer = setTimeout(() => {
        checkSafetyTimer = null;
        awaitingCheckSince = null;
        patch({ awaitingCheck: false });
        // Last-ditch re-read: if we never saw the cycle's snapshot within the
        // budget, pull whatever the backend has rather than sitting on stale data.
        void queryClient.refetchQueries({ queryKey: ["live"] });
      }, CHECK_SAFETY_MS);
    })();
  }, [queryClient]);

  // A cheap reachability re-read for the reconnect overlay's retry: just re-fetch the
  // ["live"] snapshot (GET /api/live). Unlike `refresh` this does NOT POST /live/check,
  // so an auto-retry loop over a down/redeploying backend stays a light GET, never a
  // repeated full provider fan-out.
  const reconnect = useCallback(() => {
    void queryClient.refetchQueries({ queryKey: ["live"] });
  }, [queryClient]);

  // Offline only when every feed is dark AND we're not mid re-read: the last read
  // failed, the stream isn't connected, and no fetch is in flight to refute it.
  const offline = liveError !== null && !streamConnected && !query.isFetching;
  // `disconnected` is the same outage WITHOUT the `!isFetching` term, so it stays
  // asserted through each in-flight probe. The overlay rides this so it doesn't
  // strobe and its outage clock accumulates toward the "deploying → unreachable"
  // escalation. Both read `liveError`, not `query.isError` — see its doc comment:
  // on a cold board the query's error status is too short-lived to build on.
  const disconnected = liveError !== null && !streamConnected;
  const clientNextEstimate = dataUpdatedAt > 0 ? dataUpdatedAt + POLL_INTERVAL_MS : null;

  return {
    snapshot,
    offline,
    disconnected,
    blind: snapshot !== null && snapshot.services.length === 0,
    // `liveError` IS the detail, and it is already exactly as sticky as `disconnected`
    // (same source), so the overlay's detail line stays put across probes instead of
    // blinking to null during each re-read.
    offlineDetail: disconnected ? liveError : null,
    polling: query.isFetching || awaitingCheck,
    // Prefer the backend cadence while streaming, but fall back to the client
    // estimate in the window after 'open' but before the first schedule frame.
    nextPollAt: streamConnected ? nextCheckAt ?? clientNextEstimate : clientNextEstimate,
    refresh,
    reconnect,
  };
}
