import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { eq } from 'drizzle-orm';

// `runCycle` resolves every monitored host, and the `.example.test` names below are not
// real. Left unmocked these tests make live DNS queries — slow, offline-hostile, and
// (because a name that fails to resolve is now an input to a DELETION rule) they would be
// leaning on the "no host resolves at all" guard to stay green instead of on the behavior
// under test. Every host resolves here; DNS retirement has its own file.
vi.mock('node:dns', () => ({
  promises: {
    resolve4: async () => ['203.0.113.7'],
    resolve6: async () => [],
    resolveCname: async () => [],
  },
}));

import { createApp } from '../src/app';
import { deployProjectMeta, monitoredEndpoints } from '../src/libsql/schema';
import { statusAdapter } from '../src/routes/auto-configure';
import { runAutoConfigure } from '@agentic-toolkit/deploy-platform/engine';
import { listSites, listEndpoints } from '../src/storage/config-store';
import { runCycle } from '../src/monitor/sync';
import { sessionHeaders } from './helpers/auth';
import { freshDb, type Db } from './helpers/db';
import { stubVercelAccount, type FakeVercelAccount } from './helpers/vercel-account';
import { testConfig } from './helpers/config';

// The server-side Auto Configure engine, run against a FAKE VERCEL ACCOUNT (a seeded
// integration row + a stubbed projects API — see helpers/vercel-account). Auto Configure
// re-verifies the Vercel project table against the account before it suggests anything, so
// "this project exists" now means "the account returns it", not "a row sits in
// deploy_project_meta": registering it with the account is what makes it enumerable, and
// the run's own refresh is what writes the table. Railway/Cloudflare stay unconfigured, so
// they contribute nothing.
describe('server-side auto-configure', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let adminAuth: { Cookie: string };
  let vercel: FakeVercelAccount;

  beforeEach(async () => {
    db = await freshDb();
    adminAuth = await sessionHeaders(db, 'admin');
    vercel = await stubVercelAccount(db);
    app = createApp({ db, config: testConfig() });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  const postJson = (path: string, body: unknown, headers: { Cookie: string }) =>
    app.request(path, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

  const makeGroup = async (slug: string) =>
    (await (await postJson('/config/site-groups', { name: slug.toUpperCase(), slug }, adminAuth)).json()) as { id: string };
  const makeSite = async (groupId: string, slug: string) =>
    (await (await postJson('/config/sites', { name: slug.toUpperCase(), slug, siteGroupId: groupId }, adminAuth)).json()) as { id: string };
  const makeEndpoint = async (siteId: string, host: string, kind = 'frontend') =>
    (await (await postJson('/config/endpoints', { siteId, url: `https://${host}`, kind }, adminAuth)).json()) as { id: string };

  // A Vercel project that EXISTS in the account — the refresh records it, and the
  // enumeration then surfaces it with [domain] as its domain list.
  const seedProject = (projectName: string, domain: string) => vercel.add(projectName, domain);

  const metaNames = async () => (await db.select().from(deployProjectMeta)).map((r) => r.projectName);

  it('wires an existing endpoint whose host matches a project domain', async () => {
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    const ep = await makeEndpoint(site.id, 'app.example.test');
    seedProject('adh-app', 'app.example.test');

    const res = await postJson('/auto-configure', {}, adminAuth);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ added: 1, created: 0 });

    // The pre-existing endpoint is now wired to the project (platform + deployProject set).
    const [row] = await db.select().from(monitoredEndpoints).where(eq(monitoredEndpoints.id, ep.id));
    expect(row!.platform).toBe('vercel');
    expect(row!.deployProject).toBe('adh-app');
  });

  it('creates a new site + endpoint for a project no site monitors (opt-in create)', async () => {
    const group = await makeGroup('g');
    seedProject('new-app', 'new.example.test');

    const res = await postJson('/auto-configure', { create: { groupId: group.id } }, adminAuth);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ added: 0, created: 1 });

    // A fresh endpoint monitoring the project's domain now exists, wired + filed under the group.
    const sites = await listSites(db);
    expect(sites).toHaveLength(1);
    const endpoints = await listEndpoints(db);
    expect(endpoints).toHaveLength(1);
    expect(endpoints[0]).toMatchObject({
      url: 'https://new.example.test',
      platform: 'vercel',
      deployProject: 'new-app',
      siteId: sites[0]!.id,
    });
  });

  it('adds a per-env project to the site whose production endpoint is `www.` — no second site', async () => {
    // THE SHAPE AUTO CONFIGURE KEPT FAILING ON, end to end. Production is monitored at
    // `www.<apex>`; the staging project's host is `staging.<apex>`. Unless `www.` is folded
    // into the apex the two look unrelated, so the staging project falls through to "create
    // a site" — named for the same project base the production site ALREADY holds, which
    // 409s on UNIQUE(site_group_id, slug) and leaves the project pending on every run.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 'stenographer');
    await makeEndpoint(site.id, 'www.stenographer.example.test');
    seedProject('stenographer-staging', 'staging.stenographer.example.test');

    const res = await postJson('/auto-configure', { create: { groupId: group.id } }, adminAuth);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ added: 0, created: 1, skipped: 0 });

    // The staging monitor joined the EXISTING site — no duplicate site was created.
    expect((await listSites(db)).map((s) => s.id)).toEqual([site.id]);
    const endpoints = await listEndpoints(db);
    expect(endpoints.map((e) => e.url).sort()).toEqual([
      'https://staging.stenographer.example.test',
      'https://www.stenographer.example.test',
    ]);
    expect(endpoints.find((e) => e.url.includes('staging'))).toMatchObject({
      siteId: site.id,
      environment: 'staging',
      platform: 'vercel',
      deployProject: 'stenographer-staging',
    });
  });

  it('creates the site under a DISAMBIGUATED slug when the derived one is taken', async () => {
    // A project's slug is derived from its base NAME, which two unrelated products can
    // share. `(site_group_id, slug)` is UNIQUE, so without disambiguation createSite 409s —
    // and because nothing about the project changes between runs, it 409s forever. The
    // squatting site holds the slug but monitors nothing, so no match rule can absorb the
    // project: creation is the only path, and it has to succeed.
    const group = await makeGroup('g');
    const squatter = await makeSite(group.id, 'lonely');
    seedProject('lonely-production', 'lonely.example.test');

    const res = await postJson('/auto-configure', { create: { groupId: group.id } }, adminAuth);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ added: 0, created: 1, skipped: 0 });

    // A second site exists, under a slug the constraint accepts, and it carries the monitor.
    const sites = await listSites(db);
    expect(sites).toHaveLength(2);
    const created = sites.find((s) => s.id !== squatter.id)!;
    expect(created.slug).toBe('lonely-example-test');
    expect(await listEndpoints(db)).toMatchObject([
      { url: 'https://lonely.example.test', platform: 'vercel', deployProject: 'lonely-production', siteId: created.id },
    ]);
  });

  it('reports WHY each leftover was left, per project, in the response body', async () => {
    // A bare `skipped: 2` is what hid the stuck project for good: it reads exactly like
    // "nothing to do here" whether the run is idle or failing identically every time. The
    // reasons have to survive all the way into the JSON the dialog renders.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    // Already wired to SOMEONE ELSE — the conflict rule refuses to clobber it. `incumbent`
    // is seeded as a LIVE project (serving its own domain): a name the account no longer
    // has is treated as this deployment's old name and repaired, so an incumbent that never
    // existed would make this a takeover instead of the refusal the test is about.
    await postJson(
      '/config/endpoints',
      { siteId: site.id, url: 'https://taken.example.test', kind: 'frontend', platform: 'vercel', deployProject: 'incumbent' },
      adminAuth,
    );
    seedProject('incumbent', 'incumbent.example.test');
    seedProject('claimant', 'taken.example.test');
    seedProject('homeless', 'homeless.example.test');

    // No `create` → match-only, so `homeless` has nowhere to go and says so.
    const res = await postJson('/auto-configure', {}, adminAuth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { skipped: number; skippedDetail: { project: string; reason: string }[] };
    expect(body.skipped).toBe(2);
    expect(body.skippedDetail).toHaveLength(2);
    const byProject = Object.fromEntries(body.skippedDetail.map((d) => [d.project, d.reason]));
    expect(byProject.claimant).toContain('incumbent'); // names the project holding the domain
    expect(byProject.homeless).toContain('no site monitors this domain');
  });

  it('REPORTS filing a new site with its domain family\'s group instead of the chosen one', async () => {
    // The engine deliberately overrides the selected group so a product's sites stay
    // together — but an override nobody is told about reads as "it went where you said",
    // and the operator can only move a site they know moved.
    const adh = await makeGroup('adh');
    const other = await makeGroup('other');
    const hub = await makeSite(adh.id, 'hub');
    await makeEndpoint(hub.id, 'hub.family.test');
    seedProject('lewis', 'lewis.family.test');

    const res = await postJson('/auto-configure', { create: { groupId: other.id } }, adminAuth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { created: number; notes: { project: string; note: string }[] };
    expect(body.created).toBe(1);

    // It landed with the family, NOT in the group the operator picked…
    const created = (await listSites(db)).find((s) => s.id !== hub.id)!;
    expect(created.siteGroupId).toBe(adh.id);
    // …and the response says so, naming the family that decided it.
    expect(body.notes).toHaveLength(1);
    expect(body.notes[0]!.project).toBe('lewis');
    expect(body.notes[0]!.note).toContain('family.test');
  });

  it('honors forceGroup — the chosen group wins over the domain family, with nothing to report', async () => {
    // For a board whose groups are not per-product: filing by domain family would put a
    // production site in the Testing group, and there was no way to say no.
    const adh = await makeGroup('adh');
    const other = await makeGroup('other');
    const hub = await makeSite(adh.id, 'hub');
    await makeEndpoint(hub.id, 'hub.family.test');
    seedProject('lewis', 'lewis.family.test');

    const res = await postJson('/auto-configure', { create: { groupId: other.id, forceGroup: true } }, adminAuth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { created: number; notes: unknown[] };
    expect(body.created).toBe(1);

    const created = (await listSites(db)).find((s) => s.id !== hub.id)!;
    expect(created.siteGroupId).toBe(other.id);
    expect(body.notes).toEqual([]); // nothing was overridden, so there is nothing to report
  });

  it('refuses to add a SECOND monitor for an environment a sibling site already has', async () => {
    // `x` and `x-production` share the base `x` and both read as production, but their hosts
    // share no apex — so the sibling rule would attach the second to the first's site,
    // leaving one site with two `production` monitors wired to different deploy projects.
    // Neither is then trustworthy, and no display can untangle them.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 'x');
    await postJson(
      '/config/endpoints',
      { siteId: site.id, url: 'https://x-a.alpha.test', kind: 'frontend', platform: 'vercel', deployProject: 'x', environment: 'production' },
      adminAuth,
    );
    seedProject('x-production', 'x-b.beta.test');

    const res = await postJson('/auto-configure', { create: { groupId: group.id } }, adminAuth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { created: number; skipped: number; skippedDetail: { project: string; reason: string }[] };

    expect(body.created).toBe(0);
    expect(body.skipped).toBe(1);
    // Named, not silently dropped — the operator decides which project is the real one.
    expect(body.skippedDetail[0]!.project).toBe('x-production');
    expect(body.skippedDetail[0]!.reason).toContain('production');
    expect(body.skippedDetail[0]!.reason).toContain('already wired to x');
    // Still exactly one monitor on that site.
    expect(await listEndpoints(db)).toHaveLength(1);
  });

  it('rolls back the just-created site when its endpoint fails to create (no orphan)', async () => {
    const group = await makeGroup('g');
    // monitored_endpoints has no unique/NOT-NULL an Add can trip, so a createEndpoint
    // failure can't be provoked through a DB constraint — inject it to exercise the
    // rollback wire (real createSite runs, real purging deleteSite must undo it).
    const api = { ...statusAdapter(db), createEndpoint: () => Promise.reject(new Error('boom')) };
    const project = { platform: 'vercel', projectName: 'lonely', domain: 'lonely.example.test', environment: null };

    const res = await runAutoConfigure([project], { api, create: { groupId: group.id } });
    expect(res.created).toHaveLength(0);
    expect(res.skipped).toHaveLength(1);

    // The site the engine created was rolled back — nothing orphaned.
    expect(await listSites(db)).toHaveLength(0);
    expect(await listEndpoints(db)).toHaveLength(0);
  });

  it('GET /deploy-projects/unconfigured returns an unmatched project as addable; viewer POST is 403', async () => {
    seedProject('unmatched', 'unmatched.example.test');

    // `?fresh=1` — what the review modal sends: re-verify the account, THEN partition.
    const res = await app.request('/deploy-projects/unconfigured?fresh=1', { headers: adminAuth });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      pending: { projectName: string }[];
      addable: { projectName: string; domain: string | null }[];
      noDomain: unknown[];
      unconfiguredSites: unknown[];
    };
    expect(body.addable.map((p) => p.projectName)).toContain('unmatched');
    expect(body.pending.map((p) => p.projectName)).toContain('unmatched');

    // The write endpoint is admin-only: a viewer session is rejected.
    const viewerAuth = await sessionHeaders(db, 'viewer');
    const forbidden = await postJson('/auto-configure', {}, viewerAuth);
    expect(forbidden.status).toBe(403);
  });

  it('stops offering a project once it is deleted at Vercel', async () => {
    // THE BUG THIS BRANCH EXISTS FOR: the project table was upsert-only, so a project
    // deleted upstream kept being enumerated — Auto Configure went on offering it, and
    // accepting it re-created the very site the operator had just deleted.
    seedProject('doomed', 'doomed.example.test');
    await app.request('/deploy-projects/unconfigured?fresh=1', { headers: adminAuth });
    expect(await metaNames()).toEqual(['doomed']);

    vercel.remove('doomed');

    const res = await app.request('/deploy-projects/unconfigured?fresh=1', { headers: adminAuth });
    const body = (await res.json()) as { pending: { projectName: string }[]; addable: { projectName: string }[] };
    expect(body.pending).toEqual([]);
    expect(body.addable).toEqual([]);
    // …because the refresh evicted it, so nothing downstream can resurrect it.
    expect(await metaNames()).toEqual([]);
  });

  it('REMOVES a monitor whose project was deleted at Vercel, and the site it emptied', async () => {
    const group = await makeGroup('g');
    const doomedSite = await makeSite(group.id, 'docs');
    await makeEndpoint(doomedSite.id, 'docs.example.test');
    const keptSite = await makeSite(group.id, 'web');
    await makeEndpoint(keptSite.id, 'web.example.test');
    seedProject('docs-old', 'docs.example.test');
    seedProject('web-prod', 'web.example.test'); // a survivor, so the read isn't an empty one

    // Wire both monitors to their projects the honest way, then delete one upstream — which
    // takes its domain down with it, as a real deletion does.
    expect(await (await postJson('/auto-configure', {}, adminAuth)).json()).toMatchObject({ added: 2 });
    vercel.remove('docs-old');
    vercel.failHost('docs.example.test');

    await runCycle(db, testConfig());

    // The dead monitor is GONE — and so is the site it was the last monitor of, so nothing
    // is left on the board describing a project that no longer exists. Nothing surfaces it
    // for review first; there is nothing to decide.
    expect((await listEndpoints(db)).map((e) => e.url)).toEqual(['https://web.example.test']);
    expect((await listSites(db)).map((s) => s.id)).toEqual([keptSite.id]);
  });

  it('removes NOTHING when the Vercel account cannot be read (a broken poll is not a deletion)', async () => {
    // The blast radius if the guard were dropped: an unreadable account names every
    // monitored project as vanished, and the cycle would delete the entire board.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 'docs');
    await makeEndpoint(site.id, 'docs.example.test');
    seedProject('docs-old', 'docs.example.test');
    expect(await (await postJson('/auto-configure', {}, adminAuth)).json()).toMatchObject({ added: 1 });

    vercel.setBroken(true);
    vercel.failHost('docs.example.test'); // down as well as unreadable — still not deletable
    await runCycle(db, testConfig());

    expect(await listEndpoints(db)).toHaveLength(1);
    expect(await listSites(db)).toHaveLength(1);
  });

  it('removes NOTHING when the account reads back EMPTY — zero projects is not zero deletions', async () => {
    // Distinct from the broken-account case above, and NOT covered by it: this read
    // SUCCEEDS. `ok:true`, no error, just an empty project list — which is what a token
    // rescoped to the wrong team, or one whose scope silently narrowed, returns. Nothing
    // failed, so the fail-closed path never runs; only the size-0 guard stands between an
    // empty answer and deleting every monitor on the board.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 'docs');
    await makeEndpoint(site.id, 'docs.example.test');
    seedProject('docs-old', 'docs.example.test');
    expect(await (await postJson('/auto-configure', {}, adminAuth)).json()).toMatchObject({ added: 1 });

    // The account still answers — it just has nothing in it now. The domain goes dark too,
    // so the still-serving veto is not what keeps the monitor: only the guard is.
    vercel.remove('docs-old');
    vercel.failHost('docs.example.test');

    await runCycle(db, testConfig());

    expect(await listEndpoints(db)).toHaveLength(1);
    expect(await listSites(db)).toHaveLength(1);
  });

  it('removes NOTHING when EVERY wired project is missing from a non-empty read', async () => {
    // The other shape of the same lie, and the one the size-0 guard does NOT catch: the
    // account answers with projects, just none of OURS. That is a token pointed at a
    // different team, not an operator who deleted their entire fleet in one sitting — so
    // the guard is all-or-nothing on purpose. One survivor and the rule acts again.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 'docs');
    await makeEndpoint(site.id, 'docs.example.test');
    seedProject('docs-old', 'docs.example.test');
    expect(await (await postJson('/auto-configure', {}, adminAuth)).json()).toMatchObject({ added: 1 });

    vercel.remove('docs-old');
    vercel.failHost('docs.example.test'); // dark, so only the guard can be what saves it
    seedProject('someone-elses', 'elsewhere.example.test'); // a full, healthy read of the WRONG scope

    await runCycle(db, testConfig());

    expect(await listEndpoints(db)).toHaveLength(1);
    expect(await listSites(db)).toHaveLength(1);
  });

  it('REPAIRS a monitor still wired to a project RENAMED at Vercel, and reports the takeover', async () => {
    // THE UNCLEARABLE ALERT: a rename leaves the endpoint carrying the OLD project name, so
    // the NEW name reads unmonitored and is counted by the "N projects not monitored" banner,
    // while its domain is already wired — which the conflict rule refused on EVERY run. The
    // operator saw the same warning and the same "already wired to <dead name>" leftover
    // forever, with no action that cleared it.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    await postJson(
      '/config/endpoints',
      { siteId: site.id, url: 'https://renamed.example.test', kind: 'frontend', platform: 'vercel', deployProject: 'old-name' },
      adminAuth,
    );
    // The account holds ONLY the new name — `old-name` is gone from it, which is what makes
    // the existing wiring stale rather than a rival claim on the domain.
    seedProject('new-name', 'renamed.example.test');

    const res = await postJson('/auto-configure', {}, adminAuth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { added: number; created: number; skipped: number; notes: { project: string; note: string }[] };
    expect(body).toMatchObject({ added: 1, created: 0, skipped: 0 });
    // Re-pointed IN PLACE — no second site, no second monitor for the same deployment.
    const eps = await listEndpoints(db);
    expect(eps).toHaveLength(1);
    expect(eps[0]!.deployProject).toBe('new-name');
    expect(await listSites(db)).toHaveLength(1);
    // …and the run SAYS it rewrote existing wiring, naming what it took over from.
    expect(body.notes).toHaveLength(1);
    expect(body.notes[0]!.project).toBe('new-name');
    expect(body.notes[0]!.note).toContain('old-name');
  });

  it('does NOT clobber wiring when the incumbent project still EXISTS at Vercel', async () => {
    // The repair keys off the live enumeration, so "the incumbent is gone" is the only thing
    // that licenses a takeover. Two projects that both really exist is a genuine conflict and
    // stays one — the operator picks, not the planner.
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    await postJson(
      '/config/endpoints',
      { siteId: site.id, url: 'https://contested.example.test', kind: 'frontend', platform: 'vercel', deployProject: 'incumbent' },
      adminAuth,
    );
    seedProject('incumbent', 'incumbent.example.test'); // alive, just serving elsewhere now
    seedProject('claimant', 'contested.example.test');

    const res = await postJson('/auto-configure', {}, adminAuth);
    const body = (await res.json()) as { added: number; notes: unknown[]; skippedDetail: { project: string; reason: string }[] };
    expect(body.notes).toEqual([]);
    expect((await listEndpoints(db))[0]!.deployProject).toBe('incumbent'); // untouched
    expect(body.skippedDetail.find((d) => d.project === 'claimant')!.reason).toContain('incumbent');
  });

  it('does NOT repair against a platform that was NOT enumerated this run', async () => {
    // The incumbent sits on RAILWAY, which has no integration here — so nothing listed it,
    // and `legacy` may well still exist. Absence from a list we never made is silence, not
    // evidence, and rewriting on it would clobber live wiring. (Vercel IS verified this
    // run, which is exactly the trap: a rule that treated "verified something" as
    // "verified everything" would take this monitor over.)
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    await postJson(
      '/config/endpoints',
      { siteId: site.id, url: 'https://moved.example.test', kind: 'frontend', platform: 'railway', deployProject: 'legacy' },
      adminAuth,
    );
    seedProject('claimant', 'moved.example.test');

    const res = await postJson('/auto-configure', {}, adminAuth);
    const body = (await res.json()) as { added: number; notes: unknown[]; skippedDetail: { project: string; reason: string }[] };
    expect(body.added).toBe(0);
    expect(body.notes).toEqual([]);
    expect((await listEndpoints(db))[0]!.deployProject).toBe('legacy'); // untouched
    expect(body.skippedDetail.find((d) => d.project === 'claimant')!.reason).toContain('legacy');
  });

  it('offers NO Vercel project — and says so — when the account cannot be verified', async () => {
    const group = await makeGroup('g');
    seedProject('new-app', 'new.example.test');
    // A previous run recorded the project…
    await app.request('/deploy-projects/unconfigured?fresh=1', { headers: adminAuth });
    expect(await metaNames()).toEqual(['new-app']);
    // …and now Vercel's API is failing, so the table can't be vouched for.
    vercel.setBroken(true);

    const res = await postJson('/auto-configure', { create: { groupId: group.id } }, adminAuth);
    expect(res.status).toBe(200);
    // Fail CLOSED: suggest nothing rather than act on a table we couldn't re-verify —
    // and tell the caller, so "nothing to configure" and "we didn't look" don't read alike.
    // `vercelSkipped` is HOW MANY went unexamined: without a count the banner can only say
    // "some", which reads the same whether one project or the whole fleet was skipped.
    expect(await res.json()).toMatchObject({ added: 0, created: 0, vercelUnverified: true, vercelSkipped: 1 });
    expect(await listSites(db)).toHaveLength(0);
    // The row SURVIVES: a failed read is not evidence of deletion, it's just not usable.
    expect(await metaNames()).toEqual(['new-app']);
  });
});

describe('auto-configure with NO Vercel integration', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let adminAuth: { Cookie: string };

  beforeEach(async () => {
    db = await freshDb();
    adminAuth = await sessionHeaders(db, 'admin');
    // No integration row, no token — and a fetch that fails loudly, so an unconfigured
    // platform provably costs zero provider calls.
    vi.stubGlobal('fetch', vi.fn(async (url: string | URL) => { throw new Error(`unexpected fetch ${String(url)}`); }));
    app = createApp({ db, config: testConfig() });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('does NOT warn "unverified" — an unconfigured platform is not a failed read', async () => {
    const res = await app.request('/auto-configure', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: '{}',
    });

    expect(res.status).toBe(200);
    // The warning is for "we tried and couldn't verify". An operator who never connected
    // Vercel would otherwise be told, every single run, that something was wrong.
    expect(await res.json()).toMatchObject({ added: 0, created: 0, vercelUnverified: false, vercelSkipped: 0 });
  });
});

// ---------------------------------------------------------------------------
// A site MIGRATED between platforms — the shape behind the real "adh-status: that domain
// is already wired to adh-status-monitoring-site" toast. The old Vercel project is gone,
// a Railway project serves the same host, and the monitor still names the dead one. BOTH
// platforms enumerate live here, which is what makes the old name's absence evidence.
// ---------------------------------------------------------------------------
describe('auto-configure across a platform migration', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let adminAuth: { Cookie: string };
  let accounts: FakeVercelAccount;

  beforeEach(async () => {
    db = await freshDb();
    adminAuth = await sessionHeaders(db, 'admin');
    accounts = await stubVercelAccount(db, { railway: true });
    app = createApp({ db, config: testConfig() });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  const postJson = (path: string, body: unknown) =>
    app.request(path, { method: 'POST', headers: { ...adminAuth, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

  it('REPAIRS a monitor naming a project the OTHER platform no longer has', async () => {
    const group = (await (await postJson('/config/site-groups', { name: 'G', slug: 'g' })).json()) as { id: string };
    const site = (await (await postJson('/config/sites', { name: 'S', slug: 's', siteGroupId: group.id })).json()) as { id: string };
    await postJson('/config/endpoints', {
      siteId: site.id,
      url: 'https://lewis.example.test',
      kind: 'frontend',
      platform: 'vercel',
      deployProject: 'adh-status-monitoring-site',
    });
    // Vercel is verified AND empty of the old name; Railway is verified and serves the host.
    accounts.addRailway('adh-status', 'lewis.example.test');

    const res = await postJson('/auto-configure', {});
    expect(res.status).toBe(200);
    const body = (await res.json()) as { added: number; created: number; skipped: number; notes: { project: string; note: string }[] };
    expect(body).toMatchObject({ added: 1, created: 0, skipped: 0 });

    // Re-pointed IN PLACE, onto the new PLATFORM as well as the new name — the monitor
    // now polls the deployment that actually serves the host.
    const eps = await listEndpoints(db);
    expect(eps).toHaveLength(1);
    expect(eps[0]!.platform).toBe('railway');
    expect(eps[0]!.deployProject).toBe('adh-status');
    expect(await listSites(db)).toHaveLength(1);
    expect(body.notes[0]!.note).toContain('adh-status-monitoring-site');
  });

  it('does NOT repair when the OTHER platform\'s read FAILED — an unverifiable list proves no absence', async () => {
    // Same migration shape, minus the one fact that licensed it: Vercel's API is down, so
    // "the old project isn't in the Vercel list" is a read we couldn't complete, not a
    // deletion. Repairing here would clobber a live monitor on the strength of an outage.
    const group = (await (await postJson('/config/site-groups', { name: 'G', slug: 'g' })).json()) as { id: string };
    const site = (await (await postJson('/config/sites', { name: 'S', slug: 's', siteGroupId: group.id })).json()) as { id: string };
    await postJson('/config/endpoints', {
      siteId: site.id,
      url: 'https://lewis.example.test',
      kind: 'frontend',
      platform: 'vercel',
      deployProject: 'adh-status-monitoring-site',
    });
    accounts.addRailway('adh-status', 'lewis.example.test');
    accounts.setBroken(true);

    const res = await postJson('/auto-configure', {});
    const body = (await res.json()) as { added: number; notes: unknown[]; skippedDetail: { project: string; reason: string }[] };
    expect(body.added).toBe(0);
    expect(body.notes).toEqual([]);
    const eps = await listEndpoints(db);
    expect(eps[0]!.platform).toBe('vercel');
    expect(eps[0]!.deployProject).toBe('adh-status-monitoring-site'); // untouched
    expect(body.skippedDetail.find((d) => d.project === 'adh-status')!.reason).toContain('adh-status-monitoring-site');
  });
});
