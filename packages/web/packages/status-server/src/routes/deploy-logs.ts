import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Tier } from '../middleware/auth';
import type { StatusConfig } from '../config/port';
import type { Storage } from '../storage/ports';
import { type ProviderConn } from '@agentic-toolkit/deploy-platform/conn';
import { providerConn } from '../monitor/provider-conn';
import { fetchVercelBuildLog } from '../monitor/fetch-vercel';
import { fetchRailwayBuildLog } from '../monitor/fetch-railway';

// ---------------------------------------------------------------------------
// GET /deployments/:id/log — the WHOLE build log for one deployment.
//
// Every other read here is a cheap replay of the last monitoring cycle. This one
// deliberately is not: build logs are big, most are never asked for, and the DB
// already carries the one-line summary (`error_text`, written once per failed
// deploy by enrich-deploy-errors). Storing full logs for every failure would
// grow the table for output almost nobody reads, so the log is fetched from the
// provider ON DEMAND — one authenticated human asking about one deployment.
//
// Why it exists at all: `error_text` is the provider's final sentence ("Command
// … exited with 1"), which says a build failed but never why. Without the log,
// diagnosing a failure means opening the Vercel/Railway dashboard — so the CLI
// (`adh-status issues show`) could report a problem it could not explain.
// ---------------------------------------------------------------------------

/** The full provider log for one deployment row, dispatched by platform. Null for
 *  a platform with no build-log concept (Cloudflare Workers, Crunchy) or with no
 *  configured token — indistinguishable to the caller from "no log", which is the
 *  honest answer either way: we have nothing to show. */
async function fetchLogFor(
  row: { id: string; platform: string },
  conn: ProviderConn,
  signal: AbortSignal,
): Promise<string | null> {
  if (row.platform === 'vercel' && conn.vercel.token) {
    return fetchVercelBuildLog(
      row.id.replace(/^vc_/, ''),
      { VERCEL_API_TOKEN: conn.vercel.token, VERCEL_TEAM_ID: conn.vercel.teamId },
      signal,
    );
  }
  if (row.platform === 'railway' && conn.railway.token) {
    return fetchRailwayBuildLog(row.id.replace(/^ry_/, ''), conn.railway.token, signal);
  }
  return null;
}

/** Wall-clock cap on the provider call. Generous compared with the 8s polls — a
 *  human is waiting on this one request, and a long build's log is a big
 *  response — but still bounded, so a hung provider can't pin the handler. */
const LOG_TIMEOUT_MS = 25_000;

export function deployLogRoutes(storage: Storage, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  app.get('/deployments/:id/log', async (c) => {
    const id = c.req.param('id');
    const row = await storage.deploy.findById(id);
    // A 404 here means "no such deployment in the monitored feed" — a real client
    // error worth distinguishing from a deployment that exists but has no log.
    if (!row) throw new HTTPException(404, { message: `Unknown deployment: ${id}` });

    const conn = await providerConn(storage, config);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), LOG_TIMEOUT_MS);
    let log: string | null;
    try {
      log = await fetchLogFor(row, conn, controller.signal);
    } finally {
      clearTimeout(timer);
    }

    // `errorText` travels with the log so one request answers the whole question:
    // the summary is always available (it is persisted), the log is best-effort.
    return c.json({ ...row, log });
  });

  return app;
}
