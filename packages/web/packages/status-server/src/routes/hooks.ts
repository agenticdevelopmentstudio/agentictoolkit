import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import { verifyVercelSignature, verifySharedSecret } from '../monitor/webhook-verify';
import { mapVercelDeployEvent, mapRailwayDeployEvent } from '../monitor/webhook-events';
import { pushDeployEvent } from '../monitor/live-buffer';
import { upsertDeployments } from '../monitor/sync';
import { emitLiveUpdate } from '../live/live-events';
import {
  ownsDeployProject, readRoster, reconcileBoardLedger, rosterDeployProjects, type DeployIdentity,
} from '../board';
import { flushAlerts } from '../monitor/alerts';

/**
 * A deploy event only matters if a live site OWNS its project (some endpoint is wired to
 * it). An update for a project no site monitors is dropped at the door — it never enters
 * the DB, so it can never become a phantom deploy/Problem.
 *
 * Resolved through the BOARD's ownership rule (`src/board/ownership.ts`), not a private
 * name-keyed copy of it. The copy this replaces matched on `projectName` alone, so the
 * first webhook after an upstream RENAME was discarded at the door while the board — which
 * resolves the same project by its provider id — was showing a Problem for it: no instant
 * alert and no row, for the one signal that arrives seconds after a deploy fails. It also
 * ignored `monitorDeploys`, so a switch the operator turned off still admitted writes
 * (Requirement A).
 *
 * Fails CLOSED. It used to pass the event through on a config-read error, reasoning that
 * the per-cycle reconcile is the real gate. It is not: an admitted row for a project
 * nobody monitors is a permanent row (nothing prunes `deployments` for 90 days) that the
 * fold will keep reading. Refusing costs one webhook, which the poller re-fetches within
 * the cycle; admitting one can strand a phantom only a human can clear.
 *
 * THREE answers, not two, because a config-read failure is not a verdict. `not-owned` is
 * a decision about the world and is final — 2xx, nothing to retry. `unknown` means the
 * roster could not be read at all, and answering 2xx there told the provider the event was
 * accepted and discarded it: a DB blip during a deploy burst silently lost the fastest
 * failure signal the monitor gets, for every event in the burst. Providers retry a 5xx,
 * so `unknown` says 503 and lets them.
 */
type Ownership = 'owned' | 'not-owned' | 'unknown';

async function ownedBySite(db: Db, row: DeployIdentity): Promise<Ownership> {
  try {
    return ownsDeployProject(row, rosterDeployProjects(await readRoster(db))) ? 'owned' : 'not-owned';
  } catch (err) {
    console.error('[hooks] ownership check failed — asking the provider to retry:', err);
    return 'unknown';
  }
}

/**
 * Derive deploy issues from the just-persisted webhook row and DELIVER any alert
 * it raised, right here on the ingest request.
 *
 * A webhook is the fastest signal the monitor ever gets — the provider telling us
 * a deploy failed seconds after it did. Persisting it and pushing it to the board
 * while leaving the ISSUE (and therefore the page to on-call) to the next full
 * sync meant the one path that could alert immediately was the one path that
 * didn't: the dashboard showed the failure minutes before anyone was told.
 *
 * Calls the cycle's OWN verb, so a webhook-derived issue is identical to a
 * poll-derived one (and idempotent against it — the partial unique index makes the
 * double-derive a no-op). The alert queue is flushed here because `openIssue` /
 * `resolveIssue` queue on whatever thread they run on, and this one is the API
 * thread, not the monitor worker.
 *
 * `skipOnEmptyRoster` because a webhook only OBSERVES: it did not cause an empty
 * roster, so an empty read here is a blip, not "every site was deleted". Narrowing a
 * project deleted at Vercel is `deriveBoard`'s job now — it reads the same
 * `deploy_project_meta` mirror the cycle keeps — so a hook still cannot REOPEN, and
 * page for, a Problem the cycle just resolved as "unmonitored".
 *
 * Fail-soft: a derivation failure must never 500 a webhook (the provider would
 * just retry-storm) — the next cycle re-derives it from the row we already wrote.
 */
async function runReconcile(db: Db, config: StatusConfig): Promise<void> {
  try {
    await reconcileBoardLedger(db, config, { skipOnEmptyRoster: true });
    await flushAlerts(config.alertWebhookUrl);
  } catch (err) {
    console.error('[hooks] issue derivation failed — the next cycle will re-derive it:', err);
  }
}

/**
 * Single-flight {@link runReconcile}: at most one reconcile in flight, and any number of
 * arrivals during it coalesce into exactly ONE follow-up pass.
 *
 * A reconcile is a WHOLE-BOARD fold plus a ledger write-back — it reads every roster
 * entry, deploy, probe and platform sample, and it is not cheap. One per webhook event was
 * fine one event at a time and pathological in the case webhooks actually arrive in: a
 * fleet-wide push fans out to ~48 Vercel projects, each firing several lifecycle events, so
 * a hundred concurrent full folds pile onto the API thread — the same per-tick cost blowup
 * that drove the container past its CPU quota once already. They also raced each other:
 * every one reads `issues` and writes it back, and the last writer home wins.
 *
 * The follow-up pass is what makes coalescing SAFE rather than merely cheap. An arrival
 * during a run may have written its deploy row after that run read its facts, so its
 * failure would be invisible to the in-flight fold; the queued pass re-derives after it,
 * and one pass covers every arrival in the burst because they all share the flag. Callers
 * await the whole drain, so a webhook still does not answer before the board has seen it.
 *
 * State lives per `hooksRoutes` call rather than at module scope, so it is scoped to the
 * same `db` the routes close over.
 */
function reconcileGate(db: Db, config: StatusConfig): () => Promise<void> {
  let running: Promise<void> | null = null;
  let queued = false;

  return function deriveIssuesAndAlert(): Promise<void> {
    if (running !== null) {
      queued = true;
      return running;
    }
    running = (async () => {
      try {
        do {
          // Cleared BEFORE the pass, so an arrival during it always wins another one.
          queued = false;
          await runReconcile(db, config);
        } while (queued);
      } finally {
        running = null;
      }
    })();
    return running;
  };
}

/**
 * Provider webhook ingest routes. These authenticate via provider signature /
 * shared secret rather than the app-wide view/admin token, so they MUST be
 * mounted before the requireAuth seam.
 */
export function hooksRoutes(db: Db, config: StatusConfig): Hono {
  const app = new Hono();
  const deriveIssuesAndAlert = reconcileGate(db, config);

  // POST /hooks/vercel — HMAC-SHA1 signature in x-vercel-signature header.
  // Must read the RAW body text before parsing so the digest covers the exact bytes.
  app.post('/hooks/vercel', async (c) => {
    const secret = config.webhooks.vercel;
    // Throw (not c.json) so app.onError shapes it as the documented { error: { message } }
    // envelope every other route uses — webhook senders only read the status code.
    if (!secret) throw new HTTPException(503, { message: 'webhook not configured' });

    const raw = await c.req.text(); // RAW body — required for the HMAC check
    const sig = c.req.header('x-vercel-signature');
    if (!verifyVercelSignature(raw, sig, secret)) {
      throw new HTTPException(401, { message: 'invalid signature' });
    }

    let event: unknown;
    try {
      event = JSON.parse(raw);
    } catch {
      return c.json({ ok: true, ignored: 'unparseable' }); // 2xx → no retry-storm
    }

    const row = mapVercelDeployEvent(event);
    if (!row) return c.json({ ok: true, ignored: true }); // not a deploy event we map
    // Drop any update for a project no live site owns — never enters the DB. A roster we
    // could not READ is not that verdict: 503 so the provider redelivers.
    const owned = await ownedBySite(db, row);
    if (owned === 'unknown') throw new HTTPException(503, { message: 'ownership check unavailable' });
    if (owned === 'not-owned') return c.json({ ok: true, ignored: 'not owned by a site' });
    // PERSIST the pushed state (not just the live buffer): a webhook is often the
    // only witness of a deploy that finished after leaving the recent-deploys
    // poll window — without this write it would stay "building" in the DB
    // forever. Fail-soft: the buffer + poll still cover a failed write.
    try {
      await upsertDeployments(db, [row], { source: 'webhook' });
    } catch (err) {
      console.error('[hooks] vercel deploy upsert failed:', err);
    }
    pushDeployEvent(row);
    // Derive the issue (and page on-call) NOW, not on the next cycle.
    await deriveIssuesAndAlert();
    emitLiveUpdate(db, config); // a webhook merges into /live — push it to open streams now
    return c.json({ ok: true, id: row.id });
  });

  // POST /hooks/railway — shared secret via ?token= query param OR x-webhook-secret
  // header (Railway only lets you configure the URL, so ?token= is the primary path).
  app.post('/hooks/railway', async (c) => {
    const secret = config.webhooks.railway;
    // Throw (not c.json) so app.onError shapes it as the documented { error: { message } }
    // envelope every other route uses — webhook senders only read the status code.
    if (!secret) throw new HTTPException(503, { message: 'webhook not configured' });

    const provided =
      c.req.query('token') ?? c.req.header('x-webhook-secret') ?? null;
    if (!verifySharedSecret(provided, secret)) {
      throw new HTTPException(401, { message: 'invalid secret' });
    }

    let event: unknown;
    try {
      event = await c.req.json();
    } catch {
      return c.json({ ok: true, ignored: 'unparseable' });
    }

    const row = mapRailwayDeployEvent(event);
    if (!row) return c.json({ ok: true, ignored: true });
    // Drop any update for a project no live site owns — never enters the DB. A roster we
    // could not READ is not that verdict: 503 so the provider redelivers.
    const owned = await ownedBySite(db, row);
    if (owned === 'unknown') throw new HTTPException(503, { message: 'ownership check unavailable' });
    if (owned === 'not-owned') return c.json({ ok: true, ignored: 'not owned by a site' });
    // Persist like the Vercel hook: webhook truth must survive the poll window.
    try {
      await upsertDeployments(db, [row], { source: 'webhook' });
    } catch (err) {
      console.error('[hooks] railway deploy upsert failed:', err);
    }
    pushDeployEvent(row);
    // Derive the issue (and page on-call) NOW, not on the next cycle.
    await deriveIssuesAndAlert();
    emitLiveUpdate(db, config); // a webhook merges into /live — push it to open streams now
    return c.json({ ok: true, id: row.id });
  });

  // No /hooks/cloudflare: Cloudflare offers no per-deploy webhook analogous to
  // Vercel/Railway (only account-level Notifications with a generic envelope and a
  // cf-webhook-auth secret, requiring dashboard setup and mapping only loosely to a
  // deploy). Cloudflare is intentionally polling-only — fetchCloudflareDeployments()
  // covers it on the 60s cycle, which closes any gap a webhook would.
  // adh-ui-allow: defer — Cloudflare has no per-deploy webhook; polling covers it; approved by mike 2026-06-26

  return app;
}
