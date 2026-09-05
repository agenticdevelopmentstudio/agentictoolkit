import { describe, it, expect, vi, afterEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import { isNull, eq, sql } from 'drizzle-orm';
import * as schema from '../src/libsql/schema';
import { runCycle, runMaintenance, upsertDeployments } from '../src/monitor/sync';
import type { ProviderDeploy } from '../src/monitor/provider-deploy';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

afterEach(() => vi.unstubAllGlobals());

async function bootDb() {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

/** One active group → site → endpoint. Returns the endpoint id (the probe slug). */
async function seedOneEndpoint(
  db: Awaited<ReturnType<typeof bootDb>>,
  url: string,
): Promise<string> {
  const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0];
  const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g!.id, slug: 's', name: 'S' }).returning())[0];
  const ep = (await db.insert(schema.monitoredEndpoints).values({ siteId: s!.id, url }).returning())[0];
  return ep!.id;
}

describe('runCycle', () => {
  it('records a health check for an active endpoint and does not throw without provider tokens', async () => {
    const db = await bootDb();
    await seedOneEndpoint(db, 'https://example.com');

    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
    await runCycle(db, testConfig()); // must not throw even though no VERCEL/RAILWAY/CLOUDFLARE tokens are set

    const checks = await db.select().from(schema.healthChecks);
    expect(checks.length).toBeGreaterThanOrEqual(1);
    expect(checks[0]!.status).toBe('healthy');
  });

  it('skipDeploys runs the probe (steps 0-5) but skips the provider poll + prune', async () => {
    // The scheduler passes skipDeploys on the fast probe-only ticks so the expensive
    // provider polls run on a slower cadence. Prove the gate end-to-end: with a configured
    // (ok:true) Railway integration, a FULL cycle reaches step 7's prune and deletes an
    // aged deploy row; a skipDeploys cycle never reaches it, so the row survives — while
    // the probe (steps 0-5) still records a health check either way. (A skipDeploys tick
    // does run the bounded in-flight reconcile, but this row is terminal and long outside
    // its 14-day window, so it is not a candidate and nothing re-fetches it.)
    const db = await bootDb();
    await seedOneEndpoint(db, 'https://example.com');
    await db
      .insert(schema.deployIntegrations)
      .values({ platform: 'railway', label: 'rw', tokenEnvVar: 'TEST_RAILWAY_TOKEN' });
    process.env.TEST_RAILWAY_TOKEN = 'tok';
    // An aged deploy the prune (createdAt < now - 90d) would delete.
    await db.insert(schema.deployments).values({
      id: 'old',
      platform: 'railway',
      projectName: 'p',
      createdAt: new Date(Date.now() - 200 * 86_400 * 1000),
    });

    // 200 for the health probe; Railway GraphQL enumerates zero projects (authorized
    // empty → the fetcher returns ok:true), so the FULL cycle is entitled to prune.
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) =>
        String(url).includes('backboard.railway.app')
          ? Response.json({ data: { projects: { edges: [] } } })
          : new Response('ok', { status: 200 }),
      ),
    );

    try {
      // skipDeploys → poll + prune never run → aged row survives, probe still recorded.
      await runCycle(db, testConfig(), { skipDeploys: true });
      expect((await db.select().from(schema.deployments)).map((d) => d.id)).toContain('old');
      expect((await db.select().from(schema.healthChecks)).length).toBeGreaterThanOrEqual(1);

      // Full cycle → Railway ok:true → step 7 prune deletes the aged row.
      await runCycle(db, testConfig());
      expect((await db.select().from(schema.deployments)).map((d) => d.id)).not.toContain('old');
    } finally {
      delete process.env.TEST_RAILWAY_TOKEN;
    }
  });

  it('rolls up metrics_hourly and is idempotent across reruns (one row per service/hour)', async () => {
    const db = await bootDb();
    const slug = await seedOneEndpoint(db, 'https://example.com');

    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
    await runCycle(db, testConfig());
    await runCycle(db, testConfig());

    const metrics = await db.select().from(schema.metricsHourly);
    expect(metrics).toHaveLength(1); // two cycles, same hour → upserted, not duplicated
    expect(metrics[0]!.serviceSlug).toBe(slug);
    expect(metrics[0]!.totalChecks).toBe(2); // both checks counted in the bucket
    expect(metrics[0]!.healthyChecks).toBe(2);
  });

  it('opens an HTTP issue for a down endpoint and resolves it when it recovers', async () => {
    const db = await bootDb();
    await seedOneEndpoint(db, 'https://example.com');

    // Down: a 500 is not the expected 200.
    vi.stubGlobal('fetch', vi.fn(async () => new Response('boom', { status: 500 })));
    await runCycle(db, testConfig());
    let open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open).toHaveLength(1);
    expect(open[0]!.source).toBe('http');

    vi.unstubAllGlobals();
    // Recovered.
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
    await runCycle(db, testConfig());
    open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open).toHaveLength(0); // the open issue was resolved
  });

  it('completes with no configured endpoints', async () => {
    const db = await bootDb();
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
    await expect(runCycle(db, testConfig())).resolves.toBeUndefined();
    expect(await db.select().from(schema.healthChecks)).toHaveLength(0);
  });

  it('prunes a dangling endpoint (and resolves its issue) so a phantom DNS failure self-heals', async () => {
    const db = await bootDb();
    // Reproduce the no-FK-cascade (Turso/HTTP) mode the reconcile defends: with FK
    // enforcement OFF, deleting a site does NOT cascade its endpoints, so a dangling
    // endpoint can survive — the structural ghost reconcileOrphanedEndpoints prunes.
    await db.run(sql`PRAGMA foreign_keys = OFF`);
    // A live, owned endpoint + a ghost endpoint whose owning site is deleted directly
    // (a no-FK-cascade leftover). An open dns issue targets the ghost's slug.
    const liveSlug = await seedOneEndpoint(db, 'https://example.com');
    const g2 = (await db.insert(schema.siteGroups).values({ slug: 'gh', name: 'GH' }).returning())[0];
    const s2 = (await db.insert(schema.monitoredSites).values({ siteGroupId: g2!.id, slug: 'gh', name: 'GH' }).returning())[0];
    const ghost = (await db.insert(schema.monitoredEndpoints).values({ siteId: s2!.id, url: 'https://ghost.example.com' }).returning())[0]!;
    await db.insert(schema.issues).values({ target: ghost.id, source: 'dns', name: 'ghost', severity: 'major', state: 'down', detail: 'DNS: does not resolve' });
    await db.delete(schema.monitoredSites).where(eq(schema.monitoredSites.id, s2!.id)); // strand the ghost endpoint

    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
    await runCycle(db, testConfig());

    // The ghost endpoint row is gone (only the live one remains)…
    const eps = await db.select().from(schema.monitoredEndpoints);
    expect(eps.map((e) => e.id)).toEqual([liveSlug]);
    // …and its open dns issue was reconciled away (no phantom Problem).
    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open.filter((i) => i.target === ghost.id)).toHaveLength(0);
  });

  it('uses the LATEST deploy per target (SQL max-per-group), not an arbitrary row', async () => {
    const db = await bootDb();
    // A site that OWNS the vercel project, so applyDeployIssues evaluates its target.
    const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0];
    const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g!.id, slug: 's', name: 'S' }).returning())[0];
    await db.insert(schema.monitoredEndpoints).values({
      siteId: s!.id, url: 'https://web-prod.example.com', platform: 'vercel', deployProject: 'web-prod', environment: 'production',
    });
    // Same target, two rows. The NEWER successful one is inserted FIRST (lower rowid)
    // and the OLDER failed one LAST (higher rowid) on purpose: a naive group-by would
    // surface the last/highest-rowid row (failed) and open a bogus issue. Only a correct
    // max(created_at) picks the newer success → no issue. So this distinguishes
    // "latest by time" from "whatever row the group happened to yield".
    await db.insert(schema.deployments).values([
      { id: 'vc_new', platform: 'vercel', projectName: 'web-prod', environment: 'production', deployPhase: 'deployed', createdAt: new Date() },
      { id: 'vc_old', platform: 'vercel', projectName: 'web-prod', environment: 'production', deployPhase: 'failed', createdAt: new Date(Date.now() - 60_000) },
    ]);
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));

    await runCycle(db, testConfig());

    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open.filter((i) => i.target === 'vercel|web-prod|')).toHaveLength(0);
  });

  it('a CANCELED skip on top of a fixed build RESOLVES the open issue (ignore-build-step wedge)', async () => {
    const db = await bootDb();
    const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0];
    const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g!.id, slug: 's', name: 'S' }).returning())[0];
    await db.insert(schema.monitoredEndpoints).values({
      siteId: s!.id, url: 'https://web-prod.example.com', platform: 'vercel', deployProject: 'web-prod', environment: 'production',
    });
    // The exact shape that wedged the three `projects-*` projects on lewis: a build
    // FAILED (issue opened), a later build FIXED it, and then an unrelated commit
    // produced a CANCELED skip (Vercel's Ignored Build Step) that became the newest
    // row. Judging the newest row alone reads "canceled" — neither bad nor resolving —
    // so the issue stays open forever. The newest CONCLUSIVE deploy is the success.
    await db.insert(schema.deployments).values([
      { id: 'vc_fail', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'failed', deployPhase: 'none', createdAt: new Date(Date.now() - 3 * 3600_000) },
      { id: 'vc_fixed', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'built', deployPhase: 'deployed', createdAt: new Date(Date.now() - 2 * 3600_000) },
      { id: 'vc_skip', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'canceled', deployPhase: 'none', createdAt: new Date(Date.now() - 3600_000) },
    ]);
    await db.insert(schema.issues).values({
      target: 'vercel|web-prod|', source: 'vercel', name: 'web-prod', severity: 'major', state: 'failed',
    });
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));

    await runCycle(db, testConfig());

    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open.filter((i) => i.target === 'vercel|web-prod|')).toHaveLength(0);
  });

  it('a CANCELED skip on top of a STILL-FAILING build keeps the issue open (skip carries no news)', async () => {
    const db = await bootDb();
    const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0];
    const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g!.id, slug: 's', name: 'S' }).returning())[0];
    await db.insert(schema.monitoredEndpoints).values({
      siteId: s!.id, url: 'https://web-prod.example.com', platform: 'vercel', deployProject: 'web-prod', environment: 'production',
    });
    // The other half of the invariant: skipping the canceled row must not skip the
    // FAILURE under it. The last real build still failed, so the Problem is still real.
    await db.insert(schema.deployments).values([
      { id: 'vc_fail', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'failed', deployPhase: 'none', createdAt: new Date(Date.now() - 2 * 3600_000) },
      { id: 'vc_skip', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'canceled', deployPhase: 'none', createdAt: new Date(Date.now() - 3600_000) },
    ]);
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));

    await runCycle(db, testConfig());

    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open.filter((i) => i.target === 'vercel|web-prod|')).toHaveLength(1);
  });

  it('an expired `unknown` DEPLOY on top of a failed build does NOT mask the failure (CONCLUSIVE excludes deploy-unknown)', async () => {
    const db = await bootDb();
    const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0];
    const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g!.id, slug: 's', name: 'S' }).returning())[0];
    await db.insert(schema.monitoredEndpoints).values({
      siteId: s!.id, url: 'https://web-prod.example.com', platform: 'vercel', deployProject: 'web-prod', environment: 'production',
    });
    // Newest row has a REAL build verdict (built) but a DEPLOY that expired unconfirmable
    // (deploy_phase = 'unknown'). CONCLUSIVE filtering only the BUILD phase let this row
    // count as conclusive, so its "unknown" combinedStatus buried the failed build under
    // it and the issue never opened. Excluding deploy-unknown surfaces the real failure.
    await db.insert(schema.deployments).values([
      { id: 'vc_fail', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'failed', deployPhase: 'none', createdAt: new Date(Date.now() - 2 * 3600_000) },
      { id: 'vc_unk', platform: 'vercel', projectName: 'web-prod', environment: 'production', buildPhase: 'built', deployPhase: 'unknown', createdAt: new Date(Date.now() - 3600_000) },
    ]);
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));

    await runCycle(db, testConfig());

    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open.filter((i) => i.target === 'vercel|web-prod|')).toHaveLength(1);
  });

  it('does NOT wipe an open deploy issue when the endpoint list is empty (empty != "all sites gone")', async () => {
    const db = await bootDb();
    // A recent failed deploy + its open deploy issue exist, but there are ZERO endpoints
    // and zero integrations. With an empty endpoint list every owned set is empty; without
    // the guard, applyDeployIssues would treat the deploy as owned-by-no-site and resolve
    // the issue — silently wiping a live outage on one transient empty read.
    await db.insert(schema.deployments).values({
      id: 'vc_d1',
      platform: 'vercel',
      projectName: 'web-prod',
      environment: 'production',
      deployPhase: 'error',
      createdAt: new Date(),
    });
    await db.insert(schema.issues).values({
      target: 'vercel|web-prod|',
      source: 'vercel',
      name: 'web-prod',
      severity: 'major',
      state: 'failed',
    });
    vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));

    await runCycle(db, testConfig());

    const open = await db.select().from(schema.issues).where(isNull(schema.issues.resolvedAt));
    expect(open).toHaveLength(1); // survived — the empty-endpoints guard held
    expect(open[0]!.target).toBe('vercel|web-prod|');
  });

  it('fail-soft: a provider poll that THROWS does not abort the cycle', async () => {
    const db = await bootDb();
    await seedOneEndpoint(db, 'https://example.com');
    // An active vercel integration with a token whose env var is set → the cycle
    // will call fetch for the provider; make EVERY fetch throw. The endpoint probe
    // also uses fetch, so seed a still-recorded check by letting the probe's own
    // error path classify it (down), and assert the cycle still completes.
    await db.insert(schema.deployIntegrations).values({
      platform: 'vercel',
      label: 'Vercel',
      config: { teamId: 't' },
      tokenEnvVar: 'TEST_VERCEL_TOKEN',
      isActive: true,
    });
    process.env.TEST_VERCEL_TOKEN = 'tok';
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('network down');
      }),
    );
    try {
      // First cycle must not throw despite every provider fetch throwing.
      await expect(runCycle(db, testConfig())).resolves.toBeUndefined();
      // The endpoint was still probed + recorded (as down, since fetch threw).
      const checks = await db.select().from(schema.healthChecks);
      expect(checks.length).toBeGreaterThanOrEqual(1);
      // The unreachable vercel poll advanced its debounce streak (no issue opens
      // on the FIRST failed poll — PLATFORM_UNREACHABLE_POLLS = 2).
      const streak = await db.select().from(schema.platformHealthState);
      expect(streak.some((s) => s.source === 'vercel' && s.consecutiveFailures >= 1)).toBe(true);

      // Second consecutive failed poll crosses the debounce threshold → the
      // platform-health issue opens for the unreachable vercel provider.
      await expect(runCycle(db, testConfig())).resolves.toBeUndefined();
      const platformIssues = await db
        .select()
        .from(schema.issues)
        .where(isNull(schema.issues.resolvedAt));
      expect(platformIssues.some((i) => i.target === 'platform-health|vercel')).toBe(true);
    } finally {
      delete process.env.TEST_VERCEL_TOKEN;
    }
  });
});

describe('upsertDeployments', () => {
  function deploy(over: Partial<ProviderDeploy>): ProviderDeploy {
    return {
      id: 'vc_up',
      platform: 'vercel',
      projectName: 'olylo',
      buildPhase: 'building',
      deployPhase: 'none',
      environment: 'production',
      commitHash: null,
      commitMessage: null,
      branch: null,
      commitRepo: null,
      url: null,
      createdAt: new Date('2026-07-10T10:00:00Z'),
      ...over,
    };
  }

  it('keeps the EARLIEST created_at on conflict — a later webhook event time never moves it forward', async () => {
    const db = await bootDb();
    const t0 = new Date('2026-07-10T10:00:00Z');
    await upsertDeployments(db, [deploy({ createdAt: t0 })]); // poll: true creation time
    // Webhook for the same deploy, carrying its (later) event-emission time.
    await upsertDeployments(db, [deploy({ buildPhase: 'built', createdAt: new Date('2026-07-10T10:05:00Z') })], { source: 'webhook' });
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(Math.floor(row!.createdAt.getTime() / 1000)).toBe(Math.floor(t0.getTime() / 1000));
    expect(row!.buildPhase).toBe('built'); // the phases still updated
  });

  it('a stale out-of-order WEBHOOK cannot regress a terminal row back to in-flight', async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy({ buildPhase: 'built', deployPhase: 'deployed' })]); // poll saw READY
    // Delayed deployment.created arrives after the fact.
    await upsertDeployments(db, [deploy({ buildPhase: 'queued', deployPhase: 'none' })], { source: 'webhook' });
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(row!.buildPhase).toBe('built');
    expect(row!.deployPhase).toBe('deployed');
  });

  it('a webhook still terminalizes an in-flight row (its whole purpose)', async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy({ buildPhase: 'building', deployPhase: 'none' })]);
    await upsertDeployments(db, [deploy({ buildPhase: 'failed', deployPhase: 'none' })], { source: 'webhook' });
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(row!.buildPhase).toBe('failed');
  });

  it('a webhook HEALS a stored `unknown` (expired) row — fresh truth overwrites the gave-up marker', async () => {
    const db = await bootDb();
    // A row the expiry sweep collapsed to `unknown` (in-flight, nothing re-confirmed).
    await db.insert(schema.deployments).values({
      id: 'vc_up', platform: 'vercel', projectName: 'olylo',
      buildPhase: 'unknown', deployPhase: 'none', environment: 'production',
      createdAt: new Date('2026-07-10T10:00:00Z'),
    });
    // A late webhook carrying an IN-FLIGHT phase must still heal it: `unknown` is
    // overwritable (the monitor's gave-up marker, not a provider verdict), so the guard
    // that blocks a terminal→in-flight regression deliberately does NOT protect it.
    await upsertDeployments(db, [deploy({ buildPhase: 'building', deployPhase: 'none' })], { source: 'webhook' });
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(row!.buildPhase).toBe('building');
  });

  it('a stale in-flight webhook does NOT regress a REAL verdict on the sibling lifecycle when the other is `unknown`', async () => {
    const db = await bootDb();
    // The realistic mixed shape from expireUnconfirmedDeploys on a settled build with a
    // wedged deploy: build is a REAL 'built' verdict, deploy expired to 'unknown'.
    await db.insert(schema.deployments).values({
      id: 'vc_up', platform: 'vercel', projectName: 'olylo',
      buildPhase: 'built', deployPhase: 'unknown', environment: 'production',
      createdAt: new Date('2026-07-10T10:00:00Z'),
    });
    // A stale, out-of-order in-flight webhook. The per-lifecycle guard heals the `unknown`
    // deploy but must PROTECT the real 'built' — a whole-row overwritable test regressed it.
    await upsertDeployments(db, [deploy({ buildPhase: 'queued', deployPhase: 'none' })], { source: 'webhook' });
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(row!.buildPhase).toBe('built'); // settled build verdict protected (was regressed to 'queued' pre-fix)
    expect(row!.deployPhase).toBe('none'); // the unknown deploy healed to the webhook's terminal 'none'
  });

  it('the POLL may take a terminal row back in flight (Vercel re-promotion is current truth)', async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy({ buildPhase: 'built', deployPhase: 'deployed' })]);
    await upsertDeployments(db, [deploy({ buildPhase: 'built', deployPhase: 'deploying' })]); // poll: ROLLING
    const [row] = await db.select().from(schema.deployments).where(eq(schema.deployments.id, 'vc_up'));
    expect(row!.deployPhase).toBe('deploying');
  });
});

describe('runMaintenance', () => {
  it('prunes health_checks older than the retention horizon, keeping recent ones', async () => {
    const db = await bootDb();
    const slug = await seedOneEndpoint(db, 'https://example.com');

    const old = new Date(Date.now() - 200 * 86_400 * 1000); // 200d — past the 90d default
    const recent = new Date(Date.now() - 1 * 86_400 * 1000); // 1d — kept
    await db.insert(schema.healthChecks).values([
      { serviceSlug: slug, status: 'healthy', checkedAt: old },
      { serviceSlug: slug, status: 'healthy', checkedAt: recent },
    ]);

    await runMaintenance(db);

    const remaining = await db.select().from(schema.healthChecks);
    expect(remaining).toHaveLength(1);
    // checked_at is stored as unix-SECONDS, so the round-trip truncates the ms —
    // compare at second granularity (the kept row is the recent one, not the old).
    expect(Math.floor(remaining[0]!.checkedAt.getTime() / 1000)).toBe(Math.floor(recent.getTime() / 1000));
  });
});
