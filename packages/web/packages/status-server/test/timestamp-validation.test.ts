import { describe, it, expect, vi, afterEach } from 'vitest';
import { toValidDate, providerDeployToDTO, type ProviderDeploy } from '../src/monitor/provider-deploy';
import { mapVercelDeployEvent, mapRailwayDeployEvent } from '../src/monitor/webhook-events';
import { fetchVercelDeployments } from '../src/monitor/fetch-vercel';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

afterEach(() => vi.unstubAllGlobals());

// One malformed provider timestamp must never poison the pipeline: an Invalid
// Date that reaches the deployments upsert fails the WHOLE cycle (repeatedly,
// while the deploy stays in the provider window → /health stale → restart
// loop), and one that reaches providerDeployToDTO throws a RangeError that
// 500s /live for everyone.

describe('toValidDate', () => {
  it('accepts ISO strings, epoch numbers, and Dates', () => {
    expect(toValidDate('2026-07-12T00:00:00.000Z')?.toISOString()).toBe('2026-07-12T00:00:00.000Z');
    expect(toValidDate(1_750_000_000_000)?.getTime()).toBe(1_750_000_000_000);
    const d = new Date();
    expect(toValidDate(d)?.getTime()).toBe(d.getTime());
  });

  it('rejects garbage, missing, and out-of-range values as null', () => {
    expect(toValidDate('not a date')).toBeNull();
    expect(toValidDate(undefined)).toBeNull();
    expect(toValidDate(null)).toBeNull();
    expect(toValidDate(Number.NaN)).toBeNull();
    expect(toValidDate(8.7e15)).toBeNull(); // past Date's representable range → Invalid Date
    expect(toValidDate(new Date('garbage'))).toBeNull();
  });
});

describe('webhook mappers under malformed timestamps', () => {
  it('vercel: a garbage createdAt falls back to receipt time, never Invalid Date', () => {
    const row = mapVercelDeployEvent({
      type: 'deployment.succeeded',
      createdAt: 'garbage-timestamp',
      payload: { deployment: { id: 'd1', name: 'proj' } },
    });
    expect(row).not.toBeNull();
    expect(Number.isFinite(row!.createdAt.getTime())).toBe(true);
  });

  it('railway: a garbage timestamp falls back to receipt time, never Invalid Date', () => {
    const row = mapRailwayDeployEvent({
      id: 'r1',
      status: 'SUCCESS',
      project: { id: 'p1', name: 'proj' },
      timestamp: 'garbage-timestamp',
    });
    expect(row).not.toBeNull();
    expect(Number.isFinite(row!.createdAt.getTime())).toBe(true);
  });
});

describe('poll fetchers under malformed timestamps', () => {
  it('vercel: drops ONLY the deploy with an unparseable created, keeps the rest', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        Response.json({
          deployments: [
            { uid: 'good', name: 'proj-a', created: 1_750_000_000_000, state: 'READY' },
            { uid: 'bad', name: 'proj-b', created: 'garbage', state: 'READY' },
          ],
        }),
      ),
    );
    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });
    expect(out.ok).toBe(true);
    expect(out.deploys.map((d) => d.id)).toEqual(['vc_good']);
  });
});

describe('providerDeployToDTO read-side belt', () => {
  it('serializes a poisoned legacy Date to epoch instead of throwing', () => {
    const poisoned: ProviderDeploy = {
      id: 'vc_x',
      platform: 'vercel',
      projectName: 'p',
      buildPhase: null,
      deployPhase: 'none',
      environment: null,
      commitHash: null,
      commitMessage: null,
      branch: null,
      commitRepo: null,
      url: null,
      createdAt: new Date('garbage'),
    };
    const dto = providerDeployToDTO(poisoned, null);
    expect(dto.createdAt).toBe(new Date(0).toISOString());
  });
});

describe('upsertDeployments is the LAST line of defence', () => {
  it('drops an invalid-timestamp row at the DB boundary instead of failing the batch', async () => {
    // Every fetcher validates at its own boundary — but that is a convention each
    // one has to remember. The choke point EVERY deploy crosses before the DB must
    // enforce it too, so a new (or edited) fetcher that forgets cannot poison the
    // upsert and fail the whole cycle, repeatedly, forever.
    const { createClient } = await import('@libsql/client');
    const { drizzle } = await import('drizzle-orm/libsql');
    const { migrate } = await import('drizzle-orm/libsql/migrator');
    const schema = await import('../src/libsql/schema');
    const { upsertDeployments } = await import('../src/monitor/sync');

    const db = drizzle(createClient({ url: ':memory:' }), { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });

    const row = (id: string, createdAt: Date): ProviderDeploy => ({
      id,
      platform: 'vercel',
      projectName: 'proj',
      buildPhase: null,
      deployPhase: 'none',
      environment: 'production',
      commitHash: null,
      commitMessage: null,
      branch: null,
      commitRepo: null,
      url: null,
      createdAt,
    });

    await expect(
      upsertDeployments(db, [row('vc_good', new Date()), row('vc_poison', new Date('garbage'))]),
    ).resolves.toBeUndefined(); // the batch must NOT throw

    const stored = await db.select().from(schema.deployments);
    expect(stored.map((d) => d.id)).toEqual(['vc_good']); // the good row landed; the poison did not
  });
});
