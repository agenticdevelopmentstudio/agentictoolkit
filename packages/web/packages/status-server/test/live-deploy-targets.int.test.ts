import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as schema from '../src/libsql/schema';
import { buildLiveSnapshot } from '../src/routes/reads';
import { clearDeployEvents, pushDeployEvent } from '../src/monitor/live-buffer';
import { freshDb, type Db } from './helpers/db';
import { testConfig } from './helpers/config';

// ---------------------------------------------------------------------------
// The board's Problems are now derived SERVER-side (see src/board/), not folded from
// `/live`.deployments on the client. `/live` itself, though, still serves `deployments`
// to the Deployments tab — and `deployments` rows are history that outlives both the
// site that monitored them and the project that produced them, with nothing pruning
// them (purgeEndpointHistory can't — a deploy target isn't keyed by an endpoint).
// Un-narrowed, a deleted site's / deleted Vercel project's last FAILED build would be
// re-served on every poll forever. This suite pins that narrowing.
//
// `deployTargets` — the roster the client's now-deleted localStorage problem store
// used to sweep orphaned problems against — is gone from the wire; `Board.monitoredTargets`
// (server-side) replaced it. The cases below that used to also assert `deployTargets`
// now assert `deployments`/`projectsOf` only.
// ---------------------------------------------------------------------------

/** An endpoint wired to (platform, project), under its own site. */
async function seedWiredEndpoint(
  db: Db,
  opts: { slug: string; platform: string | null; deployProject: string | null; ignoreProjectWarning?: boolean },
): Promise<void> {
  const g = (await db.insert(schema.siteGroups).values({ slug: `g-${opts.slug}`, name: 'G' }).returning())[0]!;
  const s = (
    await db
      .insert(schema.monitoredSites)
      .values({ siteGroupId: g.id, slug: opts.slug, name: opts.slug })
      .returning()
  )[0]!;
  await db.insert(schema.monitoredEndpoints).values({
    siteId: s.id,
    url: `https://${opts.slug}.example.com`,
    platform: opts.platform,
    deployProject: opts.deployProject,
    ignoreProjectWarning: opts.ignoreProjectWarning ?? false,
  });
}

/** A persisted FAILED build row — the shape that becomes a Problem on the board. */
async function seedFailedDeploy(db: Db, platform: string, projectName: string, id = `d_${platform}_${projectName}`) {
  await db.insert(schema.deployments).values({
    id,
    platform,
    projectName,
    buildPhase: 'failed',
    deployPhase: 'none',
    environment: 'production',
    createdAt: new Date(),
  });
}

/** The Vercel projects the account mirror says still exist. */
async function seedLiveVercelProjects(db: Db, ...names: string[]) {
  if (names.length === 0) return;
  await db.insert(schema.deployProjectMeta).values(names.map((projectName) => ({ platform: 'vercel', projectName })));
}

const projectsOf = (snap: { deployments: { projectName: string }[] }) =>
  snap.deployments.map((d) => d.projectName).sort();

describe('buildLiveSnapshot deploy-target narrowing', () => {
  let db: Db;

  beforeEach(async () => {
    db = await freshDb();
    clearDeployEvents();
  });

  afterEach(() => {
    clearDeployEvents();
  });

  it('serves a live site-owned target’s build', async () => {
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedLiveVercelProjects(db, 'docs-production');
    await seedFailedDeploy(db, 'vercel', 'docs-production');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['docs-production']);
  });

  it('DROPS a build whose Vercel project was evicted from the account mirror', async () => {
    // The site is still wired to `studio-production`, but the project was deleted at
    // Vercel — so deploy_project_meta no longer lists it. Its last failed build can
    // never be superseded by a success, which is exactly why serving it pinned an
    // unclearable Problem on the board.
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedWiredEndpoint(db, { slug: 'studio', platform: 'vercel', deployProject: 'studio-production' });
    await seedLiveVercelProjects(db, 'docs-production');
    await seedFailedDeploy(db, 'vercel', 'docs-production');
    await seedFailedDeploy(db, 'vercel', 'studio-production');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['docs-production']);
  });

  it('DROPS a build for a project no live site owns (the deleted-site case)', async () => {
    // Deleting a monitored site removes its endpoints — but purgeEndpointHistory never
    // touches `deployments`, so the dead project's rows sit in the table until the
    // 90-day prune. Ownership, not the row's existence, decides what the board sees.
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedLiveVercelProjects(db, 'docs-production', 'deleted-site');
    await seedFailedDeploy(db, 'vercel', 'docs-production');
    await seedFailedDeploy(db, 'vercel', 'deleted-site');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['docs-production']);
  });

  it('drops a build for an endpoint that opted OUT of deploy-project matching', async () => {
    await seedWiredEndpoint(db, {
      slug: 'infra',
      platform: 'vercel',
      deployProject: 'infra-production',
      ignoreProjectWarning: true,
    });
    await seedLiveVercelProjects(db, 'infra-production');
    await seedFailedDeploy(db, 'vercel', 'infra-production');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(snap.deployments).toEqual([]);
  });

  it('an EMPTY account mirror narrows NOTHING — an owned project’s builds survive', async () => {
    // "Every Vercel project is gone" and "the token was rescoped / the read came back
    // empty" are indistinguishable, and the failure modes aren't symmetric: silently
    // un-monitoring the whole fleet is far worse than leaving Problems on screen.
    // Same guard as dropVanishedVercelProjects.
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedFailedDeploy(db, 'vercel', 'docs-production');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['docs-production']);
  });

  it('gates the WEBHOOK OVERLAY too, so a provider retry cannot re-add a dead project', async () => {
    // The buffer is a second, independent way a build enters the snapshot. Gating only
    // the persisted rows would let the next webhook put the Problem straight back.
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedLiveVercelProjects(db, 'docs-production');
    const base = {
      buildPhase: 'failed' as const,
      deployPhase: 'none' as const,
      environment: 'production',
      commitHash: null,
      commitMessage: null,
      branch: null,
      commitRepo: null,
      url: null,
      createdAt: new Date(),
    };
    pushDeployEvent({ ...base, id: 'vc_live', platform: 'vercel', projectName: 'docs-production' });
    pushDeployEvent({ ...base, id: 'vc_dead', platform: 'vercel', projectName: 'studio-production' });

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['docs-production']);
  });

  it('keys railway + cloudflare targets canonically, and serves their builds', async () => {
    // Deploy rows carry `cloudflare-pages`; every owned-target set is keyed by the
    // CANONICAL platform, so the roster the client sweeps against must be canonical too.
    await seedWiredEndpoint(db, { slug: 'api', platform: 'railway', deployProject: 'api-svc' });
    await seedWiredEndpoint(db, { slug: 'edge', platform: 'cloudflare-pages', deployProject: 'edge-worker' });
    await seedFailedDeploy(db, 'railway', 'api-svc');
    await seedFailedDeploy(db, 'cloudflare-pages', 'edge-worker');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['api-svc', 'edge-worker']);
  });

  it('always serves crunchy builds — its targets are not site-bound', async () => {
    await seedFailedDeploy(db, 'crunchy', 'primary-cluster');

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(projectsOf(snap)).toEqual(['primary-cluster']);
  });

  it('spends the MAX_DEPLOYS window on OWNED rows — unowned history cannot starve it', async () => {
    // `sync` upserts a row for every project the tokens can see (145+ Vercel projects in
    // production, nearly all monitored by no site), so the newest 250 rows are dominated
    // by projects the board will never show. Filtering AFTER the limit left a handful of
    // owned rows — and could strand the newest SUCCESS outside the window, which is the
    // ONLY thing that mitigates an open build Problem on the client. So the ownership
    // predicate has to be in the query, not in a post-filter.
    await seedWiredEndpoint(db, { slug: 'docs', platform: 'vercel', deployProject: 'docs-production' });
    await seedLiveVercelProjects(db, 'docs-production');

    // The owned target's history, OLDEST in the table: a failure, then the success that
    // clears it. Both must survive the window.
    const base = Date.now() - 400 * 60_000;
    await db.insert(schema.deployments).values({
      id: 'd_owned_fail',
      platform: 'vercel',
      projectName: 'docs-production',
      buildPhase: 'failed',
      deployPhase: 'none',
      environment: 'production',
      createdAt: new Date(base),
    });
    await db.insert(schema.deployments).values({
      id: 'd_owned_ok',
      platform: 'vercel',
      projectName: 'docs-production',
      buildPhase: 'built',
      deployPhase: 'deployed',
      environment: 'production',
      createdAt: new Date(base + 60_000),
    });
    // 300 NEWER rows for projects no site owns — more than MAX_DEPLOYS on their own.
    await db.insert(schema.deployments).values(
      Array.from({ length: 300 }, (_, i) => ({
        id: `d_noise_${i}`,
        platform: 'vercel',
        projectName: `unowned-${i}`,
        buildPhase: 'failed',
        deployPhase: 'none',
        environment: 'production',
        createdAt: new Date(base + 120_000 + i * 1_000),
      })),
    );

    const snap = await buildLiveSnapshot(db, testConfig());

    expect(snap.deployments.map((d) => d.id).sort()).toEqual(['d_owned_fail', 'd_owned_ok']);
  });
});
