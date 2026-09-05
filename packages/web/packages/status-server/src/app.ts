import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import { HTTPException } from 'hono/http-exception';
import type { Db } from './libsql/client';
import type { StatusConfig } from './config/port';
import { buildOpenApiSpec } from './openapi/build';
import { requireAuth, type AuthVars } from './middleware/auth';
import { cachedSingleFlight } from '@agentic-toolkit/deploy-platform/util';
import { authRoutes } from './routes/auth';
import { usersRoutes } from './routes/users';
import { readsRoutes, buildSnapshot } from './routes/reads';
import { deployLogRoutes } from './routes/deploy-logs';
import { boardRoutes } from './routes/board';
import { activityRoutes } from './routes/activity';
import { autoConfigureRoutes } from './routes/auto-configure';
import { badgeRoutes } from './routes/badge';
import { configRoutes } from './routes/config';
import type { SeedRoster } from './config/seed';
import { cronRoutes } from './routes/cron';
import { streamRoutes } from './routes/stream';
import { hooksRoutes } from './routes/hooks';
import { fleetRoutes } from './routes/fleet';
import { telemetryRoutes } from './routes/telemetry';
import { tokensRoutes } from './routes/tokens';
import { devicePublicRoutes, deviceApprovalRoutes } from './routes/device';
import { mountMcp } from './mcp/route';
import type { Scheduler } from './scheduler';

function isAllowedOrigin(origin: string, allowed: readonly string[]): boolean {
  if (!origin) return false;
  if (allowed.includes(origin)) return true;
  try {
    return allowed.includes(new URL(origin).host);
  } catch {
    return false;
  }
}

// The CORS-open public READ surface: open, unauthenticated data readable from any
// origin. Deliberately NARROWER than the set of pre-auth-seam routes — /auth/* and
// /hooks/* also run before requireAuth but carry credentials, so they stay
// origin-gated and are intentionally NOT listed here.
function isPublicPath(path: string): boolean {
  return path === '/health' || path === '/version' || path.startsWith('/public/');
}

/** TTL for the public status-summary cache. The route is unauthenticated, so its
 *  DB cost must not scale with request rate — a status headline that lags reality
 *  by up to this window is the intended trade. */
const STATUS_SUMMARY_CACHE_MS = 30_000;

/** App-wide request-body cap. Nothing here legitimately posts more than small
 *  JSON; the cap exists for the PRE-AUTH surface (/hooks/* must buffer the raw
 *  body for its HMAC check), where an anonymous oversized body would otherwise
 *  be read wholesale into memory before any check could reject it. */
export const MAX_BODY_BYTES = 1_048_576; // 1MB

/** The public headline payload, built from one snapshot. Extracted so the cached
 *  build and the route's declared response schema share one shape (the cache used
 *  to hold `unknown` and cast it back with `any`, which put the cache-hit path
 *  outside the type check the fresh path still passed). */
async function buildStatusSummary(db: Db, config: StatusConfig): Promise<{
  operational: boolean;
  status: 'healthy' | 'degraded' | 'down' | 'unknown';
  generatedAt: string;
  counts: { total: number; healthy: number; degraded: number; down: number; unknown: number };
  downSites: { name: string; status: 'down' | 'degraded'; since?: string }[];
}> {
  const snap = await buildSnapshot(db, config);

  // One pass over services; every status is one of these four buckets, so
  // total === healthy + degraded + down + unknown by construction.
  const counts = { total: snap.services.length, healthy: 0, degraded: 0, down: 0, unknown: 0 };
  for (const s of snap.services) counts[s.status] += 1;

  const endpointDown = snap.services
    .filter((s) => s.status === 'down' || s.status === 'degraded')
    .map((s) => {
      const env = s.environment ? ` (${s.environment})` : '';
      const name = `${s.group} · ${s.name}${env}`;
      // At most one OPEN issue per target (partial unique `uniq_open_issue_per_target`),
      // so this lookup is unambiguous and `openedAt` is the outage start.
      const since = snap.openIssues.find((i) => i.target === s.slug)?.openedAt;
      const base = { name, status: s.status as 'down' | 'degraded' };
      return since ? { ...base, since } : base;
    });

  // Deploy/build failures behind a still-serving site: the URL returns 200,
  // so they're NOT endpoint health failures (never an `endpointDown` above) —
  // yet they DO drop the headline off green (publicOverall folds any open
  // non-endpoint issue into `degraded`). List them too, so the public
  // "experiencing issues" NAMES the affected sites instead of showing an
  // unexplained, empty warning. status:'degraded' — the site itself is up.
  const serviceSlugs = new Set(snap.services.map((s) => s.slug));
  const nonEndpointDown = snap.openIssues
    .filter((i) => !serviceSlugs.has(i.target))
    .map((i) => {
      const env = i.environment && !i.name.includes(i.environment) ? ` (${i.environment})` : '';
      return { name: `${i.name}${env}`, status: 'degraded' as const, since: i.openedAt };
    });

  // A status page must never claim green when it can't tell: when every
  // monitored service is `unknown` (e.g. before the first probe cycle) the
  // 3-state rollup collapses to `healthy` — override it to `unknown` so the
  // public headline never shows green on zero signal.
  const allUnknown = counts.total > 0 && counts.unknown === counts.total;
  return {
    operational: !allUnknown && snap.overall === 'healthy',
    status: allUnknown ? ('unknown' as const) : snap.overall,
    generatedAt: snap.generatedAt,
    counts,
    downSites: [...endpointDown, ...nonEndpointDown],
  };
}

/** Everything `createApp` needs from its host — the ONE seam `StatusConfig` crosses
 *  into the HTTP surface. Every route factory below receives `opts.config` (or the
 *  one field it needs) rather than reading a module-level singleton. */
export interface AppDeps {
  db: Db;
  scheduler?: Scheduler;
  config: StatusConfig;
  /** The host's seed roster — what `POST /config/seed` creates in an empty configuration
   *  (./config/seed.ts). Omitted or empty: seed creates only the provider connections. */
  seed?: SeedRoster;
}

export function createApp(opts: AppDeps): OpenAPIHono<{ Variables: AuthVars }> {
  const app = new OpenAPIHono<{ Variables: AuthVars }>();
  const allowed = opts.config.corsAllowedHosts;
  const cachedSummary = cachedSingleFlight(STATUS_SUMMARY_CACHE_MS, () => buildStatusSummary(opts.db, opts.config));

  app.use(
    '*',
    cors({
      origin: (origin, c) => {
        // Public READ paths are readable from any origin (open status data). Gate
        // the open grant to safe methods so a future `/public/*` write route is
        // never auto-opened to cross-origin writes.
        if (isPublicPath(c.req.path) && (c.req.method === 'GET' || c.req.method === 'HEAD')) {
          return origin || '*';
        }
        return isAllowedOrigin(origin, allowed) ? origin : undefined;
      },
      credentials: true,
      allowMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowHeaders: ['Authorization', 'Content-Type'],
    }),
  );

  // After CORS (a 413 should still carry CORS headers), before every route.
  app.use(
    '*',
    bodyLimit({
      maxSize: MAX_BODY_BYTES,
      onError: (c) => c.json({ error: { message: 'request body too large' } }, 413),
    }),
  );

  app.onError((err, c) => {
    const isHttp = err instanceof HTTPException;
    if (!isHttp) console.error(err);
    const status = isHttp ? err.status : 500;
    return c.json({ error: { message: isHttp ? err.message : 'Internal Server Error' } }, status);
  });

  // Public allowlist — the ONLY routes outside the requireAuth seam.
  app.openapi(
    createRoute({
      method: 'get',
      path: '/health',
      tags: ['site'],
      summary: 'Liveness + cycle-freshness probe',
      responses: {
        200: {
          description: 'up — the monitoring loop has completed a cycle within the freshness window',
          content: {
            'application/json': {
              schema: z.object({ status: z.enum(['ok', 'stale']), lastCycleAt: z.string().nullable() }),
            },
          },
        },
        503: {
          description: 'process is up but the monitoring loop has not completed a cycle recently (wedged or failing) — the data it serves is stale',
          content: {
            'application/json': {
              schema: z.object({ status: z.enum(['ok', 'stale']), lastCycleAt: z.string().nullable() }),
            },
          },
        },
      },
    }),
    // A process that answers HTTP but whose loop has stopped cycling is NOT healthy —
    // it serves ever-staler data as green. Report `stale` + 503 so a healthcheck (point
    // Railway's healthcheckPath here) or an external probe can SEE it and restart, rather
    // than the outage hiding behind a 200 the way it did for ~32h.
    (c) => {
      const lastCycleAt = opts.scheduler?.lastCycleAt()?.toISOString() ?? null;
      const stale = opts.scheduler?.cycleStale() ?? false;
      return c.json({ status: stale ? ('stale' as const) : ('ok' as const), lastCycleAt }, stale ? 503 : 200);
    },
  );

  app.openapi(
    createRoute({
      method: 'get',
      path: '/version',
      tags: ['site'],
      summary: 'Version info',
      responses: {
        200: {
          description: 'version',
          content: {
            'application/json': { schema: z.object({ name: z.string(), version: z.string() }) },
          },
        },
      },
    }),
    (c) => c.json({ name: 'status-backend', version: opts.config.appVersion }),
  );

  // The landing page's headline status. PUBLIC by design (the `/` route is never
  // gated), so it sits before the auth seam alongside /health + /version. A status
  // page must never claim green when it can't tell, so the shape is deliberately
  // minimal: `operational` is true ONLY when the overall rollup is healthy, and
  // `downSites` names every site the headline is unhappy about — the services
  // failing their HEALTH check AND the deploy/build failures behind a still-up
  // site (both with the open issue's openedAt as `since`). The frontend renders "status unavailable" if this
  // 404s/errors, so keeping it here (no auth, no extra config) is what turns the
  // landing from "unavailable" to a live signal.
  app.openapi(
    createRoute({
      method: 'get',
      path: '/public/status-summary',
      tags: ['site'],
      summary: 'Headline portfolio status for the public landing page',
      responses: {
        200: {
          description: 'headline status',
          content: {
            'application/json': {
              schema: z.object({
                operational: z.boolean(),
                status: z.enum(['healthy', 'degraded', 'down', 'unknown']),
                generatedAt: z.string(),
                counts: z.object({
                  total: z.number(),
                  healthy: z.number(),
                  degraded: z.number(),
                  down: z.number(),
                  unknown: z.number(),
                }),
                downSites: z.array(
                  z.object({
                    name: z.string(),
                    status: z.enum(['down', 'degraded']),
                    since: z.string().optional(),
                  }),
                ),
              }),
            },
          },
        },
      },
    }),
    // Cached + SINGLE-FLIGHT: this is the one route anonymous traffic can reach, so
    // its DB cost must scale with the clock, not with the request rate — and a burst
    // landing on an expired cache must share ONE build, not start one each.
    async (c) => c.json(await cachedSummary()),
  );

  // Public auth routes mint the very session the seam below checks, so they sit
  // before it. Webhooks authenticate via provider signature — also pre-seam.
  app.route('/', authRoutes(opts.db, opts.config));
  app.route('/', hooksRoutes(opts.db, opts.config));
  // The device-flow REQUEST + POLL are reached by an unauthenticated CLI, so they
  // sit pre-seam beside the auth routes (both per-IP rate-limited inside). The
  // APPROVAL trio is a signed-in action and lives POST-seam below.
  app.route('/', devicePublicRoutes(opts.db));

  // Everything below requires auth; /health + /version + /public/* + /auth/* + /hooks/* above are public.
  app.use('*', requireAuth(opts.db, opts.config));
  // MCP transport (GET/POST/DELETE /mcp) — the tier the seam resolved selects the tool
  // set (view → read-only, admin → all). Mounted FIRST post-seam, well before usersRoutes'
  // blanket `use('*', requireAdmin)`, so a view-tier caller reaches its read-only tools.
  mountMcp(app, opts.db, opts.config);
  app.route('/', readsRoutes(opts.db, opts.config));
  // GET /deployments/:id/log — view tier, beside the reads it completes. Kept in its
  // own module because, unlike every route in reads.ts, it calls the provider.
  app.route('/', deployLogRoutes(opts.db));
  app.route('/', boardRoutes(opts.db, opts.config));
  app.route('/', activityRoutes(opts.db, opts.config));
  // Server-side Auto Configure (POST /auto-configure) — admin-gated inside the sub-app,
  // sits beside the reads it complements (GET /deploy-projects/unconfigured lives in reads).
  app.route('/', autoConfigureRoutes(opts.db));
  // Live push (SSE) + manual check — view tier; the SSE route needs the scheduler
  // for the cadence frame, /live/check to trigger a cycle.
  app.route('/', streamRoutes(opts.db, opts.scheduler, opts.config));
  app.route('/', badgeRoutes(opts.db, opts.config));
  app.route('/config', configRoutes(opts.db, opts.config, opts.seed ?? []));
  if (opts.scheduler) app.route('/', cronRoutes(opts.db, opts.scheduler));
  app.route('/', fleetRoutes(opts.db, opts.config));
  app.route('/', telemetryRoutes(opts.db, opts.config));
  // API bearer tokens (mint/list/revoke) — admin-gated, EXCEPT a token may revoke
  // itself (view tier). It MUST mount before usersRoutes: usersRoutes does
  // `use('*', requireAdmin)` at '/', which in Hono leaks onto every route
  // registered after it — mounting tokens after users would block the view-tier
  // self-revoke DELETE before it reaches this router.
  app.route('/', tokensRoutes(opts.db));
  // Device-approval trio (GET /auth/device/pending, POST /auth/device/approve,
  // /auth/device/deny) — any signed-in viewer/admin, NOT admin-only. Like
  // tokensRoutes it MUST mount before usersRoutes, whose `use('*', requireAdmin)`
  // at '/' leaks onto every route registered after it and would 403 a viewer
  // approving a device.
  app.route('/', deviceApprovalRoutes(opts.db));
  app.route('/', usersRoutes(opts.db));

  app.get('/doc', (c) => c.json(buildOpenApiSpec(app, opts.config.appVersion)));
  return app;
}
