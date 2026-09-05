import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { LiveSnapshot } from '../monitor/live-types';
import { buildLiveSnapshot } from '../routes/reads';

/**
 * In-process fan-out of "the live snapshot changed" to every open SSE stream.
 *
 * Module-scope by design (same rationale as live-buffer): on the single
 * long-running container this is exact. On a hypothetical multi-instance deploy
 * it's best-effort per instance — a client connected to instance A won't get an
 * event raised on instance B — but the client's polling fallback re-reads the DB,
 * so a missed push only adds latency, never loses truth.
 *
 * The producer (a finished cycle, or a webhook) calls `emitLiveUpdate(db, config)`; we
 * build ONE snapshot and hand the SAME object to every subscriber, so N open
 * streams cost one DB read, not N. Bursts coalesce into a single trailing build.
 *
 * The client never relies on WHICH source raised an event: every snapshot carries
 * a `cycleAt` (the cycle clock), and the reducer advances its count-based provider
 * streaks only when `cycleAt` strictly increases — so a snapshot delivered twice
 * (poll + push), out of order, or from a webhook is folded correctly without any
 * per-event "kind" tagging.
 */

type Subscriber = (snap: LiveSnapshot) => void;

const subscribers = new Set<Subscriber>();

/** The most recently published snapshot — lets a freshly connecting stream reuse
 *  it instead of every connection independently re-running buildLiveSnapshot (a
 *  reconnect storm after a redeploy would otherwise stampede the DB). */
let lastPublished: { snap: LiveSnapshot; at: number } | null = null;

/** Subscribe an SSE stream; returns the unsubscribe to call on disconnect. */
export function subscribeLive(cb: Subscriber): () => void {
  subscribers.add(cb);
  return () => {
    subscribers.delete(cb);
  };
}

/** Hand a freshly-built snapshot to every open stream. Pure + synchronous so the
 *  pub/sub is trivially testable without a DB. */
export function publishSnapshot(snap: LiveSnapshot): void {
  lastPublished = { snap, at: Date.now() };
  for (const cb of subscribers) {
    try {
      cb(snap);
    } catch (err) {
      // One wedged stream must never block the fan-out to the others.
      console.error('[live-events] subscriber threw:', err);
    }
  }
}

/** The last published snapshot if it's newer than `maxAgeMs` — else null. */
export function recentSnapshot(maxAgeMs: number): LiveSnapshot | null {
  return lastPublished && Date.now() - lastPublished.at <= maxAgeMs ? lastPublished.snap : null;
}

/** Current open-stream count — exported for the health/observability surface. */
export function liveSubscriberCount(): number {
  return subscribers.size;
}

const COALESCE_MS = 150;
let pending: ReturnType<typeof setTimeout> | null = null;

/** Build the latest snapshot and push it to every open stream. Debounced: a burst
 *  of calls within COALESCE_MS folds into one build+fan-out. Fail-soft — a failed
 *  build is logged and dropped (the next cycle/poll recovers), never thrown into
 *  the cycle/webhook that called us. */
export function emitLiveUpdate(db: Db, config: StatusConfig): void {
  if (subscribers.size === 0) return; // nobody listening — skip the DB read entirely
  if (pending) return; // a build is already scheduled; this call folds into it
  pending = setTimeout(() => {
    pending = null;
    buildLiveSnapshot(db, config)
      .then(publishSnapshot)
      .catch((err) => console.error('[live-events] emit build failed:', err));
  }, COALESCE_MS);
}

/** Test hook — drop all subscribers + cached snapshot + cancel any pending build. */
export function resetLiveEvents(): void {
  subscribers.clear();
  lastPublished = null;
  if (pending) {
    clearTimeout(pending);
    pending = null;
  }
}
