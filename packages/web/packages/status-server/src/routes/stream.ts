import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { AuthVars } from '../middleware/auth';
import type { Scheduler } from '../scheduler';
import type { LiveSnapshot } from '../monitor/live-types';
import { buildLiveSnapshot } from './reads';
import { subscribeLive, recentSnapshot } from '../live/live-events';

// ---------------------------------------------------------------------------
// Live push (SSE) + manual "check now".
//
//   GET  /live/stream   text/event-stream — the current snapshot on connect (a
//                       `snapshot` event), then one per backend update (cycle
//                       finished, webhook landed). A `schedule` event carries the
//                       real backend next-cycle time so the client countdown is true.
//   POST /live/check    trigger a cycle NOW (scheduler.runNow). View-tier: any
//                       signed-in viewer can ask for a fresh check. Single-flight
//                       (the scheduler coalesces overlaps) + a min-interval guard so
//                       a click-storm can't hammer the provider APIs. `ran` reports
//                       whether a fresh cycle actually started.
//
// Both sit behind the app-wide requireAuth seam (view tier suffices).
// ---------------------------------------------------------------------------

const HEARTBEAT_MS = 25_000; // keep proxies/load-balancers from idling the connection
const MANUAL_MIN_MS = 3_000; // floor between manual checks — single-flight + this debounce
const OPENING_CACHE_MS = 1_500; // reuse a very-recent published snapshot for the opening frame
// Auth is validated once, at connect. Recycle the connection so a revoked/expired
// session can't keep streaming forever — the EventSource's clean-close reconnect
// re-runs requireAuth (and 401s a session that's no longer valid).
const STREAM_MAX_MS = 10 * 60_000;

// Per-CALLER throttle: one viewer's click-storm is debounced without penalizing a
// different viewer's first click (the scheduler's single-flight already coalesces
// the actual provider sweeps). Keyed by user id; `anon` covers AUTH_DISABLED/peer.
const lastManualCheckAt = new Map<string, number>();

/** Test hook — clear the manual-check throttle between cases (it's process-global). */
export function resetCheckThrottle(): void {
  lastManualCheckAt.clear();
}

function snapshotFrame(json: string): string {
  return `event: snapshot\ndata: ${json}\n\n`;
}
function scheduleFrame(scheduler: Scheduler | undefined): string {
  const next = scheduler?.nextCycleAt()?.toISOString() ?? null;
  return `event: schedule\ndata: ${JSON.stringify({ nextCheckAt: next })}\n\n`;
}

export function streamRoutes(db: Db, scheduler: Scheduler | undefined, config: StatusConfig): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  app.get('/live/stream', async (c) => {
    const encoder = new TextEncoder();
    // Reuse a very-recent published snapshot if one exists (avoids a buildLiveSnapshot
    // stampede when a redeploy reconnects every tab at once); otherwise build one.
    // A transient build failure yields a null opening frame rather than a 500 — a 500
    // makes EventSource give up permanently. The client's initial poll still paints.
    let initial: LiveSnapshot | null = recentSnapshot(OPENING_CACHE_MS);
    if (!initial) {
      try {
        initial = await buildLiveSnapshot(db, config);
      } catch (err) {
        console.error('[live/stream] opening snapshot failed:', err);
        initial = null;
      }
    }

    let unsubscribe: (() => void) | null = null;
    let heartbeat: ReturnType<typeof setInterval> | null = null;
    let lifetime: ReturnType<typeof setTimeout> | null = null;
    let closed = false;
    const cleanup = (): void => {
      if (closed) return;
      closed = true;
      unsubscribe?.();
      if (heartbeat) clearInterval(heartbeat);
      if (lifetime) clearTimeout(lifetime);
    };

    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        const send = (text: string): void => {
          try {
            controller.enqueue(encoder.encode(text));
          } catch {
            // enqueue throws once the client is gone (and no clean cancel/abort
            // fired, e.g. a black-holed connection) — tear down so we don't leak the
            // subscription + heartbeat.
            cleanup();
          }
        };

        // Subscribe BEFORE sending the opening frame so a push raised during the
        // opening build can't slip through the gap unseen.
        unsubscribe = subscribeLive((snap) => {
          send(snapshotFrame(JSON.stringify(snap)));
          send(scheduleFrame(scheduler)); // cadence shifts after each cycle
        });
        if (initial) send(snapshotFrame(JSON.stringify(initial)));
        send(scheduleFrame(scheduler));
        heartbeat = setInterval(() => send(`: ping\n\n`), HEARTBEAT_MS);
        // Cleanly end the stream after the lifetime cap; the client reconnects and
        // re-authenticates. close() may throw if already torn down — ignore.
        lifetime = setTimeout(() => {
          cleanup();
          try {
            controller.close();
          } catch {
            // already closed
          }
        }, STREAM_MAX_MS);
      },
      cancel() {
        // Fires when the client disconnects (the node server aborts the stream).
        cleanup();
      },
    });

    // Belt-and-suspenders: also tear down on the request's abort signal, in case
    // the runtime aborts the request without cancelling the stream.
    c.req.raw.signal.addEventListener('abort', cleanup);

    return new Response(stream, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'X-Accel-Buffering': 'no', // tell any nginx/proxy layer not to buffer the stream
      },
    });
  });

  app.post('/live/check', async (c) => {
    if (!scheduler) return c.json({ ok: false, ran: false, reason: 'no scheduler' }, 503);
    const who = c.get('user')?.id ?? 'anon';
    const now = Date.now();
    // Coalesce one caller's click-storm: inside the floor we no-op rather than queue
    // another full provider sweep. The scheduler's own single-flight handles overlap
    // with the periodic tick; this guards the idle-between-ticks gap.
    if (now - (lastManualCheckAt.get(who) ?? 0) < MANUAL_MIN_MS) {
      return c.json({ ok: true, ran: false, reason: 'debounced' });
    }
    lastManualCheckAt.set(who, now);
    // DETACHED start: a manual full sync can run minutes, and the fresh snapshot
    // reaches every open tab via the SSE stream — holding this response open for
    // the whole cycle tied up the proxy and the client for nothing. `ran` is false
    // when a cycle was already in flight (coalesced) — the client then knows no
    // NEW cycle started and just re-reads the latest state.
    const ran = scheduler.runNowDetached();
    return c.json({ ok: true, ran });
  });

  return app;
}
