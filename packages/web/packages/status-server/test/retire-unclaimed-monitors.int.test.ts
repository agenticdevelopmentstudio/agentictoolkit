import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { isNull, eq, and } from 'drizzle-orm';

// node:dns is mocked so DNS decides NOTHING here: every host resolves, in every test,
// including the ones whose monitors get deleted. What is removed is decided from the
// platform inventory alone — an unresolvable name is only ever how a DOWN endpoint is
// explained. Hoisted so the mock factory can see the spies.
const { resolve4, resolve6, resolveCname } = vi.hoisted(() => ({
  resolve4: vi.fn<(h: string) => Promise<string[]>>(),
  resolve6: vi.fn<(h: string) => Promise<string[]>>(),
  resolveCname: vi.fn<(h: string) => Promise<string[]>>(),
}));
vi.mock('node:dns', () => ({ promises: { resolve4, resolve6, resolveCname } }));

import {
  issues,
  monitoredEndpoints,
  monitoredSites,
  siteGroups,
  healthChecks,
  metricsHourly,
  deployIntegrations,
} from '../src/libsql/schema';
import { runCycle } from '../src/monitor/sync';
import { listEndpoints, listSites } from '../src/storage/config-store';
import { flushAlerts, _resetAlerts, type IssueAlert } from '../src/monitor/alerts';
import { freshDb, type Db } from './helpers/db';
import { testConfig } from './helpers/config';

// ---------------------------------------------------------------------------
// The ONE automatic removal rule, driven end-to-end through `runCycle`.
//
// Two lists decide it and both are read in the same cycle: the PLATFORM INVENTORY
// (which projects exist, and the domains each serves) and the board's own config. A
// monitor wired to a project the inventory no longer lists — or an unwired monitor whose
// host no project serves — describes something that stopped existing, so the cycle
// deletes it: the endpoint, its checks, its metrics, its open issue, and the site it was
// the last monitor of. There is no clock and no banner; the first cycle that can SEE the
// absence acts on it.
//
// Everything else here is the same rule REFUSING to judge. Each safety condition is a
// property of the reads that just happened — a partial domain fan-out, an un-listable
// second platform, an inventory that overlaps the board nowhere, a whole platform's
// wired monitors vanishing at once — and every one of them withholds the verdict instead
// of deleting live config. The unit tests in the toolkit
// (`deploy-platform/src/engine/claimed-by-nothing.test.ts`) pin the rule itself; these
// pin that the CYCLE supplies it honest evidence and acts on the answer.
// ---------------------------------------------------------------------------

const ALERT_URL = 'https://hooks.example.com/alert';

/** One pass of the fleet, as a test declares it. */
interface Fleet {
  /** The Vercel projects the account returns, each mapped to the custom domains it
   *  serves. This is the whole inventory: `deploy_project_meta` is a MIRROR of it (the
   *  cycle reconciles the table from this read), so a project absent here is deleted. */
  projects: Record<string, string[]>;
  /** Projects whose `/domains` read 403s — one blind spot in the domain fan-out, which
   *  is the failure that returns an EMPTY list indistinguishable from "serves nothing". */
  domainsForbidden?: string[];
  /** Hosts whose probe answers 200. Everything else answers 503, because a monitor for
   *  something deleted is normally down — and a HEALTHY probe vetoes removal outright. */
  serving?: string[];
}

let db: Db;
let alerts: IssueAlert[];
let logs: string[];

/** A JSON provider response. */
const json = (body: unknown): Response =>
  new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });

/** A project whose production deployment is READY and promoted: nothing stale, nothing
 *  failed. So the only thing this fleet asserts is WHICH PROJECTS EXIST — the fact the
 *  removal rule reads — with no deploy Problems muddying the assertions. */
function vercelProject(name: string, hosts: string[]): unknown {
  const deployment = {
    id: `dpl_${name}`,
    createdAt: Date.now(),
    readyState: 'READY',
    readySubstate: 'PROMOTED',
    target: 'production',
    url: `${name}.vercel.app`,
    alias: hosts,
    meta: {},
  };
  return {
    name,
    targets: { production: deployment },
    latestDeployments: [deployment],
    link: { org: 'acme', repo: name, productionBranch: 'main' },
  };
}

function vercelApi(fleet: Fleet, url: URL): Response {
  const perProject = /^\/v9\/projects\/([^/]+)\/domains$/.exec(url.pathname);
  if (perProject) {
    const project = decodeURIComponent(perProject[1]!);
    if (fleet.domainsForbidden?.includes(project)) return new Response('forbidden', { status: 403 });
    return json({ domains: (fleet.projects[project] ?? []).map((name) => ({ name, verified: true })) });
  }
  if (url.pathname === '/v9/projects') {
    return json({
      projects: Object.entries(fleet.projects).map(([name, hosts]) => vercelProject(name, hosts)),
      pagination: { next: null },
    });
  }
  if (url.pathname === '/v6/deployments') return json({ deployments: [] });
  // Team-slug lookups: cosmetic (they label a link), and "unknown" is a fine answer.
  return json({});
}

/** Route every network call this cycle makes: the Vercel API, the endpoint probes, and
 *  the alert webhook. Anything else is a provider the test deliberately left unreadable
 *  (Railway, below) and fails — which is the blind spot such a test is asserting on. */
function serve(fleet: Fleet): void {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const raw = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (raw === ALERT_URL) {
        alerts.push(...(JSON.parse(String(init?.body)) as { alerts: IssueAlert[] }).alerts);
        return new Response('ok');
      }
      const url = new URL(raw);
      if (url.hostname === 'api.vercel.com') return vercelApi(fleet, url);
      if (url.hostname.endsWith('.example.test')) {
        return new Response('body', { status: fleet.serving?.includes(url.hostname) ? 200 : 503 });
      }
      return new Response('unreadable', { status: 500 });
    }),
  );
}

/** One monitored endpoint, as a test declares it. Each gets its OWN site, so a deletion
 *  that empties a site is visible in `listSites`. */
interface Monitor {
  host: string;
  /** The Vercel project this monitor is WIRED to (the authority for its own removal).
   *  Omitted = unwired, and then the domain lists are the authority instead. */
  project?: string;
  kind?: string;
  /** The operator's per-endpoint "Ignore" — the one opt-out of the whole rule. */
  ignore?: boolean;
  path?: string;
}

/** Seed one group, one site per monitor, one endpoint per site. Returns host → endpoint
 *  id (which is also the probe slug and the issue target). */
async function seed(monitors: Monitor[]): Promise<Record<string, string>> {
  const g = (await db.insert(siteGroups).values({ slug: 'g', name: 'G' }).returning())[0]!;
  const ids: Record<string, string> = {};
  for (const m of monitors) {
    const slug = m.host.split('.')[0]!;
    const site = (await db.insert(monitoredSites).values({ siteGroupId: g.id, slug, name: slug }).returning())[0]!;
    const ep = (
      await db
        .insert(monitoredEndpoints)
        .values({
          siteId: site.id,
          url: `https://${m.host}${m.path ?? ''}`,
          kind: m.kind ?? 'http',
          platform: m.project ? 'vercel' : null,
          deployProject: m.project ?? null,
          ignoreProjectWarning: m.ignore ?? false,
        })
        .returning()
    )[0]!;
    ids[m.host] = ep.id;
  }
  return ids;
}

/** Hold credentials for a platform. The token itself comes from env by name, so a
 *  platform is "configured" exactly when its row's env var is set. */
const configure = (platform: string, tokenEnvVar: string, config: Record<string, unknown> = {}) =>
  db.insert(deployIntegrations).values({ platform, label: 'test', config, tokenEnvVar });

const configureVercel = () => configure('vercel', 'TEST_VERCEL_TOKEN', { teamId: 'team_test' });

const urls = async () => (await listEndpoints(db)).map((e) => e.url).sort();
const siteSlugs = async () => (await listSites(db)).map((s) => s.slug).sort();
const openIssues = () => db.select().from(issues).where(isNull(issues.resolvedAt));
const withheld = () => logs.filter((l) => l.includes('not removing monitors'));

/** Backdate an endpoint's open issue: downtime is not, and must never become, the clock
 *  this deletion runs on. */
const ageIssue = (target: string, ageMs: number) =>
  db.update(issues).set({ openedAt: new Date(Date.now() - ageMs) }).where(eq(issues.target, target));

beforeEach(async () => {
  db = await freshDb();
  alerts = [];
  logs = [];
  _resetAlerts();
  vi.stubEnv('ALERT_WEBHOOK_URL', ALERT_URL);
  vi.stubEnv('TEST_VERCEL_TOKEN', 'vercel-token');
  resolve4.mockImplementation(async () => ['203.0.113.7']);
  resolve6.mockImplementation(async () => []);
  resolveCname.mockImplementation(async () => []);
  vi.spyOn(console, 'log').mockImplementation((...args: unknown[]) => void logs.push(args.join(' ')));
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

// Every test uses its OWN project names on purpose: `fetchProjectDomains` memoizes each
// project's domain list for an hour at module scope, so a name reused across tests would
// inherit the previous test's answer — and the 403 tests would silently pass on a cached
// success.
describe('runCycle removes monitors the platform inventory no longer accounts for', () => {
  it('deletes a monitor whose wired project is gone — row, checks, metrics, site, issue and an alert', async () => {
    await configureVercel();
    serve({ projects: { 'wired-live': ['live.example.test'] } });
    const ids = await seed([
      { host: 'live.example.test', project: 'wired-live' },
      { host: 'gone.example.test', project: 'wired-gone' },
    ]);

    // ONE cycle. There is no clock to age and nothing to click: the first pass that can
    // see the absence acts on it.
    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://live.example.test']);
    // …and it left nothing behind for anyone to tidy up.
    expect(await siteSlugs()).toEqual(['live']);
    const gone = ids['gone.example.test']!;
    expect(await db.select().from(healthChecks).where(eq(healthChecks.serviceSlug, gone))).toEqual([]);
    expect(await db.select().from(metricsHourly).where(eq(metricsHourly.serviceSlug, gone))).toEqual([]);
    expect(await db.select().from(issues).where(and(eq(issues.target, gone), isNull(issues.resolvedAt)))).toEqual([]);
    // The surviving monitor keeps its own Problem: it is down, and that is still true.
    expect((await openIssues()).map((i) => i.target)).toEqual([ids['live.example.test']]);

    // The removal ALERTS. Deleting the monitor deletes the only thing that could ever
    // have closed the `opened` alert sent for it, and `retired` says so without
    // pretending anything recovered.
    await flushAlerts(ALERT_URL);
    const retired = alerts.filter((a) => a.kind === 'retired');
    expect(retired).toHaveLength(1);
    expect(retired[0]!.target).toBe(gone);
    expect(retired[0]!.detail).toBe('its vercel project "wired-gone" no longer exists');
  });

  it('deletes an unwired monitor no project serves, and keeps one an ALIAS domain claims', async () => {
    await configureVercel();
    // `alias.example.test` is not the project's canonical domain — it is in its domain
    // LIST, which is exactly what the unwired half judges on.
    serve({ projects: { 'unwired-served': ['canonical.example.test', 'alias.example.test'] } });
    await seed([{ host: 'alias.example.test' }, { host: 'orphan.example.test' }]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://alias.example.test']);
    expect(await siteSlugs()).toEqual(['alias']);
  });

  it('keeps a monitor that probed HEALTHY even though nothing claims it, and deletes its dead sibling', async () => {
    await configureVercel();
    // Both unclaimed monitors are condemned by the inventory; only the veto separates
    // them. A project is keyed by NAME, so a rename or a team transfer reads exactly like
    // a deletion — and a URL that is answering is a site worth watching regardless.
    serve({ projects: { 'veto-live': ['vl.example.test'] }, serving: ['serving.example.test'] });
    await seed([{ host: 'vl.example.test' }, { host: 'serving.example.test' }, { host: 'dead.example.test' }]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://serving.example.test', 'https://vl.example.test']);
  });
});

describe('runCycle refuses to remove anything on a degraded or ambiguous pass', () => {
  it('keeps a monitor whose project still exists, however long it has been down', async () => {
    // The apidocs case, and the distinction the whole rule turns on: the project is
    // READY and claims the host; the site just answers 404 on the path being monitored.
    // A site serving errors for a year still EXISTS — its monitor is the alarm saying so,
    // and deleting the alarm is not cleanup.
    await configureVercel();
    serve({ projects: { 'api-production': ['api.example.test'] } });
    const ids = await seed([{ host: 'api.example.test', project: 'api-production', path: '/docs' }]);

    await runCycle(db, testConfig());
    await ageIssue(ids['api.example.test']!, 365 * 24 * 60 * 60 * 1000);
    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://api.example.test/docs']);
    expect((await openIssues()).map((i) => i.target)).toEqual([ids['api.example.test']]);
    await flushAlerts(ALERT_URL);
    expect(alerts.filter((a) => a.kind === 'retired')).toEqual([]);
  });

  it('withholds the unwired verdict when ONE project domain read 403s', async () => {
    await configureVercel();
    // One project's domain read fails. Its domains are missing from the claim index and
    // nothing can know which host that cost — so no absence from those lists is evidence.
    serve({
      projects: { 'domains-ok': ['a.example.test'], 'domains-403': ['b.example.test'] },
      domainsForbidden: ['domains-403'],
    });
    await seed([{ host: 'a.example.test' }, { host: 'orphan.example.test' }]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://a.example.test', 'https://orphan.example.test']);
    expect(withheld().join('\n')).toContain('domain lists not complete for vercel');
  });

  it('withholds the unwired verdict when a SECOND configured platform is unreadable, while still judging the wired half', async () => {
    // Any platform could be the one serving an unwired monitor's host, so that half needs
    // EVERY configured platform's domain lists. A wired monitor needs only its own
    // platform's project list — so one blind provider must not stall the verdict the
    // other provider can already deliver.
    await configureVercel();
    await configure('railway', 'TEST_RAILWAY_TOKEN');
    vi.stubEnv('TEST_RAILWAY_TOKEN', 'railway-token');
    serve({ projects: { 'railway-blind-live': ['rl.example.test'] } });
    await seed([
      { host: 'rl.example.test', project: 'railway-blind-live' },
      { host: 'rg.example.test', project: 'railway-blind-gone' },
      { host: 'ru.example.test' },
    ]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://rl.example.test', 'https://ru.example.test']);
    expect(withheld().join('\n')).toContain('domain lists not complete for railway');
  });

  it('deletes nothing when the enumerated projects claim NONE of the monitored hosts', async () => {
    // A re-scoped or swapped token returns a perfectly successful list of somebody
    // else's projects. Two lists that overlap nowhere are not the same fleet.
    await configureVercel();
    serve({ projects: { 'somebody-elses': ['other.example.test'] } });
    await seed([{ host: 'mine.example.test' }, { host: 'mine2.example.test' }]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://mine.example.test', 'https://mine2.example.test']);
    expect(withheld().join('\n')).toContain('claim none of the 2 monitored hosts');
  });

  it('deletes nothing when ALL of a platform\'s wired monitors read vanished at once', async () => {
    // Mass deletion is what a credential change looks like; a real deletion is one row.
    await configureVercel();
    serve({ projects: { 'mass-live': ['ml.example.test'] } });
    await seed([
      { host: 'ml.example.test' },
      { host: 'mga.example.test', project: 'mass-gone-a' },
      { host: 'mgb.example.test', project: 'mass-gone-b' },
    ]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://mga.example.test', 'https://mgb.example.test', 'https://ml.example.test']);
    expect(withheld().join('\n')).toContain('ALL 2 wired monitors');
  });

  it('deletes nothing when no deploy platform is configured', async () => {
    // An empty inventory is not an empty fleet: with no credentials at all, nothing can
    // speak for any host.
    serve({ projects: {} });
    await seed([{ host: 'na.example.test' }, { host: 'nb.example.test' }]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual(['https://na.example.test', 'https://nb.example.test']);
    expect(withheld().join('\n')).toContain('no deploy platform is configured');
  });

  it('never judges a monitor that was never platform-backed — an infra kind or an operator opt-out', async () => {
    await configureVercel();
    serve({ projects: { 'infra-live': ['il.example.test'] } });
    // No project claims either host, and both are DOWN. Neither is a candidate: the
    // platform list cannot speak about a `health` probe, and "Ignore" is the operator
    // saying this monitor legitimately has no deploy project.
    await seed([
      { host: 'il.example.test' },
      { host: 'probe.example.test', kind: 'health' },
      { host: 'ignored.example.test', ignore: true },
    ]);

    await runCycle(db, testConfig());

    expect(await urls()).toEqual([
      'https://ignored.example.test',
      'https://il.example.test',
      'https://probe.example.test',
    ]);
  });
});
