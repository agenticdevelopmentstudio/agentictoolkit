import { and, desc, gt, inArray, lt, notInArray, eq, sql } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { deployments } from "../libsql/schema";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import {
  vercelPhases,
  railwayPhases,
  inFlightSql,
  collapseInFlightBuildSql,
  collapseInFlightDeploySql,
  type Phases,
} from "./deploy-status";
import { pollableByIdPlatforms, type ProviderConn } from "@agentic-toolkit/deploy-platform/conn";
import { gqlPost } from "@agentic-toolkit/deploy-platform/providers";
import { rateLimitedUntil, noteIfRateLimited } from "@agentic-toolkit/deploy-platform/cooldown";

/** The provider answered definitively that this deployment no longer exists —
 *  distinct from `null` (transient: network, auth, rate limit → retry later). */
type Gone = "gone";

// The recent-deploys poll reads only the provider's newest ~100 deployments, so a
// deployment that leaves that window while still in flight would otherwise freeze
// at `building` forever (a deploy burst — many projects building at once — pushes
// unfinished ids out before they complete, exactly what a mono-repo restructure
// does). That prediction came true: a 45-project rebuild left rows reading
// "building" ~15 minutes after every build was green, because this ran only on the
// 5-minute poll tick and only past a 10-minute threshold. It now also runs on the
// fast tick, under a threshold shorter than the poll — see RECONCILE_STALE_MS.
// Bounds mirror enrichDeployErrors: recent window, per-cycle cap, bounded
// concurrency, per-call timeout, fail-soft — a backlog drains over cycles.
const RECONCILE_WINDOW_DAYS = 14;
const RECONCILE_MAX_PER_CYCLE = 10;
const RECONCILE_CONCURRENCY = 4;
const RECONCILE_CALL_TIMEOUT_MS = 8_000;
/** How long an in-flight row may go UNCONFIRMED before it is re-fetched by id.
 *  Doubles as the retry backoff: every check bumps `fetched_at`, so a genuinely
 *  still-building row is re-checked at this cadence rather than every tick.
 *
 *  Deliberately SHORTER than the deploy poll's interval (5 min default — see
 *  config.deploySyncIntervalMs). The poll is not a freshness guarantee: it emits
 *  only what the provider's recent-deploys window still shows. Gating this at
 *  LONGER than the poll therefore made the poll the only thing that could
 *  terminalize a finished build, and any row it missed read "building" for the
 *  poll gap PLUS this threshold — ~15 minutes, observed on the board after a
 *  45-project rebuild whose builds were all green within 4. Shorter than the poll
 *  means the fast tick re-confirms in-flight rows BETWEEN polls instead of
 *  trusting a phase nothing has checked. */
export const RECONCILE_STALE_MS = 2 * 60_000;

// Per-row retry backoff after a FAILED by-id fetch. A success bumps `fetched_at`, so
// only failures need separate pacing: a row whose fetch fails PERMANENTLY (a 403 from
// token scope, an unmapped payload) must not be re-fetched every tick forever.
// EXPONENTIAL, not flat: a flat delay forces one bad tradeoff — short enough to retry a
// transient blip promptly means a permanent failure keeps burning provider quota at that
// same cadence; long enough to rate-limit a permanent failure means a row that had ONE
// network blip waits the full delay before its next real check. Escalating from a short
// base means a transient failure retries soon while a persistently-failing row backs off
// toward the cap.
export const RECONCILE_BACKOFF_BASE_MS = 60_000;
export const RECONCILE_BACKOFF_MAX_MS = 5 * 60_000;
/** How long a lapsed backoff's escalation count is REMEMBERED past its expiry, so a row
 *  that fails again shortly after being retried resumes escalating instead of resetting
 *  to the base delay. Past this the entry is pruned and the next failure starts fresh. */
export const RECONCILE_BACKOFF_MEMORY_MS = 10 * 60_000;

interface Backoff {
  /** epoch-ms before which this row is not retried. */
  until: number;
  /** consecutive failures — the exponent for the next delay. */
  fails: number;
}

/** id → its current backoff. Worker-thread local and intentionally unpersisted (a
 *  restart just retries sooner); pruned on every pass, and bounded by the number of
 *  in-flight rows a cycle can even see. */
const retryAfterFailure = new Map<string, Backoff>();

/** Register a failed by-id fetch for `id` and set its next-retry time, escalating the
 *  delay if the row is still within its previous backoff's memory window. */
function parkFailure(id: string, now: number): void {
  const prev = retryAfterFailure.get(id);
  const fails = prev && prev.until + RECONCILE_BACKOFF_MEMORY_MS > now ? prev.fails + 1 : 1;
  const delay = Math.min(RECONCILE_BACKOFF_BASE_MS * 2 ** (fails - 1), RECONCILE_BACKOFF_MAX_MS);
  retryAfterFailure.set(id, { until: now + delay, fails });
}

/** Test hook — clear the per-row failure backoff (module state persists across tests). */
export function _resetReconcileBackoff(): void {
  retryAfterFailure.clear();
}

/** How long an in-flight phase may stay unconfirmable before the monitor STOPS
 *  ASSERTING it. Past this, the row terminalizes as `unknown` — the honest "we
 *  could not find out" — instead of reading "building" forever. Well past any
 *  legitimate build AND many reconcile/poll attempts (both retry on minute
 *  cadences), so it only fires when confirmation has failed persistently — e.g.
 *  a revoked token, a provider that no longer answers for the row, or a row so
 *  old it left the reconcile window. `unknown` is overwritable per-lifecycle (see
 *  deploy-status.columnOverwritableSql), so any fresh provider truth — a poll, a by-id
 *  re-fetch, OR a late webhook — replaces the expired lifecycle; a false expiry (the row
 *  was still legitimately building) heals the moment truth arrives, while a true expiry
 *  (the provider genuinely stopped answering) stays terminal, which is the point. */
export const EXPIRE_UNCONFIRMED_MS = 6 * 60 * 60_000;

interface VercelDeploymentState {
  readyState?: string;
  readySubstate?: string | null;
  target?: string | null;
}

async function fetchVercelPhasesById(
  uid: string,
  conn: ProviderConn,
  signal: AbortSignal,
): Promise<Phases | Gone | null> {
  const url = new URL(`https://api.vercel.com/v13/deployments/${encodeURIComponent(uid)}`);
  if (conn.vercel.teamId) url.searchParams.set("teamId", conn.vercel.teamId);
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${conn.vercel.token}` },
    signal,
  });
  // 404 = the deployment was DELETED at the provider. A permanent answer, not a
  // failure — returning null here would leave the row in flight and (newest-first)
  // let dead rows monopolize the per-cycle cap forever.
  if (res.status === 404) return "gone";
  // Register the throttle in the SHARED cooldown so this loop (and every other
  // caller) leaves Vercel alone until it lapses, instead of extending it each tick.
  if (noteIfRateLimited("vercel", res)) return null;
  if (!res.ok) {
    console.error(`[reconcile] Vercel deployment ${uid} detail ${res.status}`);
    return null;
  }
  const d = (await res.json()) as VercelDeploymentState;
  if (!d.readyState) return null;
  return vercelPhases(d.readyState, d.readySubstate, d.target);
}

async function fetchRailwayPhasesById(
  id: string,
  token: string,
  signal: AbortSignal,
): Promise<Phases | Gone | null> {
  // Route through the shared Railway choke point: it passes the id as a GraphQL
  // VARIABLE (never string-interpolated) and notes any 429 in the shared cooldown,
  // so this by-id call can't drift from the poller's throttle handling.
  const res = await gqlPost(token, "query($id: String!) { deployment(id: $id) { status } }", signal, { id });
  if (res.status === 429) return null; // gqlPost already noted the throttle; just bail this tick
  if (!res.ok) {
    console.error(`[reconcile] Railway deployment ${id} detail ${res.status}`);
    return null;
  }
  const body = (await res.json()) as { data?: { deployment?: { status?: string } | null } };
  // The query succeeded and the provider said "no such deployment" — deleted.
  // (Errors/auth failures leave `data` unset and fall through to null → retry.)
  if (body.data && body.data.deployment === null) return "gone";
  const status = body.data?.deployment?.status;
  return status ? railwayPhases(status) : null;
}

async function fetchPhasesFor(
  row: { id: string; platform: string },
  conn: ProviderConn,
  signal: AbortSignal,
): Promise<Phases | Gone | null> {
  if (row.platform === "vercel" && conn.vercel.token) {
    return fetchVercelPhasesById(row.id.replace(/^vc_/, ""), conn, signal);
  }
  if (row.platform === "railway" && conn.railway.token) {
    return fetchRailwayPhasesById(row.id.replace(/^ry_/, ""), conn.railway.token, signal);
  }
  return null;
}

/**
 * Re-fetch (by id) recent Vercel/Railway deploys that are still IN FLIGHT in the DB
 * but whose phase nothing has confirmed for RECONCILE_STALE_MS, and persist their
 * real phases — so a build terminalizes on the board promptly instead of reading
 * "building" long after the provider called it.
 *
 * This covers BOTH ways the poll leaves a row stale: one that fell out of the
 * provider's ~100-deployment window while unfinished (and so is never emitted
 * again), and one the poll simply hasn't revisited yet at its 5-minute cadence.
 * The board must not assert an in-flight phase nothing has checked — that is the
 * whole job of this module.
 *
 * Runs after upsertDeployments on a full cycle, and standalone on the fast
 * probe-only ticks (see runCycle). Best-effort and fail-soft, exactly like
 * enrichDeployErrors: one failed fetch just leaves the row for a later cycle.
 * Rows that are GENUINELY still building get their `fetched_at` bumped, which
 * defers their next re-check by RECONCILE_STALE_MS.
 */
export async function reconcileVanishedDeploys(db: Db, conn: ProviderConn): Promise<void> {
  // Honor the shared cooldown: a throttled provider is left alone entirely — by-id
  // fetches burn the same quota the poll does, and hammering 10 of them every fast
  // tick is exactly how a throttle never lapses (the rows stay stale the whole time).
  // pollableByIdPlatforms returns typed ProviderName values, so no `as` cast can slip a
  // non-slot name into the cooldown's Atomics index.
  const polled = pollableByIdPlatforms(conn).filter((p) => !rateLimitedUntil(p));
  if (polled.length === 0) return;

  const now = Date.now();
  // Prune backoff entries past their escalation-memory window — keeps the map bounded by
  // the rows recently failing, not by everything that ever failed.
  for (const [id, b] of retryAfterFailure) {
    if (b.until + RECONCILE_BACKOFF_MEMORY_MS <= now) retryAfterFailure.delete(id);
  }
  // Rows still inside their backoff window are EXCLUDED IN SQL, not selected then
  // filtered in JS: a JS filter after a newest-first LIMIT let a cluster of permanently-
  // failing rows fill the batch and starve older stale rows, needing an overselect
  // fudge factor that still broke down past ~cap×factor parked rows. Excluding them in
  // the WHERE means the LIMIT always returns that many RETRYABLE rows, however many are
  // parked.
  const parkedIds = [...retryAfterFailure].filter(([, b]) => b.until > now).map(([id]) => id);

  let candidates: { id: string; platform: string }[];
  try {
    candidates = await db
      .select({ id: deployments.id, platform: deployments.platform })
      .from(deployments)
      .where(
        and(
          inArray(deployments.platform, polled),
          // Literal in-flight predicate (shared vocabulary) — matches idx_deploy_inflight's
          // partial WHERE textually, so this per-tick query seeks the index, not a full scan.
          sql.raw(inFlightSql("")),
          gt(deployments.createdAt, new Date(now - RECONCILE_WINDOW_DAYS * 86_400_000)),
          lt(deployments.fetchedAt, new Date(now - RECONCILE_STALE_MS)),
          parkedIds.length > 0 ? notInArray(deployments.id, parkedIds) : undefined,
        ),
      )
      .orderBy(desc(deployments.createdAt))
      .limit(RECONCILE_MAX_PER_CYCLE);
  } catch (err) {
    console.error("[reconcile] vanished-deploy query failed:", err);
    return;
  }
  if (candidates.length === 0) return;

  await mapLimit(candidates, RECONCILE_CONCURRENCY, async (row) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), RECONCILE_CALL_TIMEOUT_MS);
    try {
      const phases = await fetchPhasesFor(row, conn, controller.signal);
      if (!phases) {
        // no token / fetch failed / unmapped — park THIS row so a permanent per-row
        // failure can't hog the newest-first cap every tick; retry after the backoff.
        parkFailure(row.id, Date.now());
        return;
      }
      if (phases === "gone") {
        // Provider says the deployment no longer exists → terminalize the IN-FLIGHT
        // lifecycle(s) only (build→canceled, deploy→none), the same mapping as Vercel
        // DELETED / Railway REMOVED. A per-lifecycle CASE over the row's CURRENT state
        // (not a blanket overwrite) preserves a settled verdict the other lifecycle
        // already reached — a built+deploying row that vanishes keeps its `built` — and
        // is race-safe against a concurrent write between the select and this update.
        console.log(`[reconcile] ${row.id} gone at provider → canceling in-flight lifecycle(s)`);
        await db
          .update(deployments)
          .set({
            buildPhase: sql.raw(collapseInFlightBuildSql("canceled")),
            deployPhase: sql.raw(collapseInFlightDeploySql("none")),
            fetchedAt: new Date(),
          })
          .where(eq(deployments.id, row.id));
      } else {
        // Fresh by-id provider truth — authoritative, so it overwrites both phases.
        await db
          .update(deployments)
          .set({
            buildPhase: phases.buildPhase,
            deployPhase: phases.deployPhase,
            fetchedAt: new Date(),
          })
          .where(eq(deployments.id, row.id));
      }
      retryAfterFailure.delete(row.id);
    } catch (err) {
      parkFailure(row.id, Date.now());
      console.error(`[reconcile] ${row.id} phase fetch/store failed:`, err);
    } finally {
      clearTimeout(timer);
    }
  });
}

/**
 * Terminal backstop for the rows NOTHING can confirm: any deployment still in
 * flight whose phase has gone unconfirmed for {@link EXPIRE_UNCONFIRMED_MS}
 * collapses to `unknown`. The reconcile above is best-effort — a revoked token, a
 * provider that stopped answering for a row, or a row that aged past
 * RECONCILE_WINDOW_DAYS all leave it asserting "building" forever, and an
 * in-flight row also wedges issue derivation (building is neither bad nor
 * resolving). Expiry converts "we stopped knowing" into a terminal state the
 * board and the recorders can handle like a canceled skip.
 *
 * Deliberately NOT windowed by createdAt: rows older than the reconcile window
 * are exactly the zombies this exists to clear. `fetched_at` is NOT bumped —
 * expiry is a statement about our knowledge, not provider truth, so the row's
 * "last confirmed" time stays honest. One indexed UPDATE per full sync; each
 * lifecycle collapses only if IT was the in-flight one (a finished build with a
 * wedged deploy keeps its `built`).
 */
export async function expireUnconfirmedDeploys(db: Db): Promise<void> {
  try {
    const res = await db
      .update(deployments)
      // Same per-lifecycle collapse the gone-branch uses, to `unknown` — a settled
      // lifecycle keeps its verdict; only the in-flight one(s) expire.
      .set({
        buildPhase: sql.raw(collapseInFlightBuildSql("unknown")),
        deployPhase: sql.raw(collapseInFlightDeploySql("unknown")),
      })
      .where(
        and(
          // Same shared in-flight predicate the reconcile uses → also seeks idx_deploy_inflight.
          sql.raw(inFlightSql("")),
          lt(deployments.fetchedAt, new Date(Date.now() - EXPIRE_UNCONFIRMED_MS)),
        ),
      );
    const n = Number(res.rowsAffected ?? 0);
    if (n > 0) console.log(`[reconcile] ${n} in-flight deploy row(s) unconfirmable for 6h+ → unknown`);
  } catch (err) {
    // Fail-soft like the reconcile: a failed sweep just waits for the next cycle.
    console.error("[reconcile] expiry sweep failed:", err);
  }
}
