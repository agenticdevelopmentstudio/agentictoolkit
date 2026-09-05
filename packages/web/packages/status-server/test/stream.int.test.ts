import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { createScheduler, type Scheduler } from '../src/scheduler';
import { publishSnapshot, resetLiveEvents } from '../src/live/live-events';
import { resetCheckThrottle } from '../src/routes/stream';
import { sessionHeaders } from './helpers/auth';
import { liveSnapshot } from './helpers/snapshot';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

type Db = ReturnType<typeof drizzle<typeof schema>>;

const snap = (generatedAt: string) => liveSnapshot({ generatedAt });

function fakeScheduler(runNowDetached: () => boolean): Scheduler {
  return {
    start() {},
    stop() {},
    runNow: async () => runNowDetached(),
    runNowDetached,
    lastCycleAt: () => new Date('2026-06-30T00:00:00.000Z'),
    nextCycleAt: () => new Date('2026-06-30T00:01:00.000Z'),
    cycleStale: () => false,
  };
}

async function bootApp(runNowDetached: () => boolean): Promise<{ app: ReturnType<typeof createApp>; db: Db }> {
  const client = createClient({ url: ':memory:' });
  const db = drizzle(client, { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  const app = createApp({ db, scheduler: fakeScheduler(runNowDetached), config: testConfig() });
  return { app, db };
}

describe('GET /live/stream', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let cookie: { Cookie: string };

  beforeAll(async () => {
    ({ app, db } = await bootApp(() => true));
    cookie = await sessionHeaders(db, 'viewer');
  });

  afterEach(() => resetLiveEvents());

  it('401s without a session', async () => {
    const res = await app.fetch(new Request('http://x/live/stream'));
    expect(res.status).toBe(401);
  });

  it('opens as text/event-stream and sends the current snapshot + cadence on connect', async () => {
    const res = await app.fetch(new Request('http://x/live/stream', { headers: cookie }));
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/event-stream');

    // One reader for the whole test (a second getReader on a locked body throws).
    const reader = res.body!.getReader();
    const dec = new TextDecoder();
    let acc = '';
    for (let i = 0; i < 8 && !acc.includes('event: schedule'); i++) {
      const { value, done } = await reader.read();
      if (done) break;
      acc += dec.decode(value, { stream: true });
    }
    await reader.cancel();

    expect(acc).toContain('event: snapshot'); // opening snapshot
    expect(acc).toContain('"generatedAt"');
    expect(acc).toContain('event: schedule');
    expect(acc).toContain('2026-06-30T00:01:00.000Z'); // nextCheckAt = scheduler.nextCycleAt()
  });

  it('pushes a published snapshot to a connected client (the real fan-out path, no mocks)', async () => {
    const res = await app.fetch(new Request('http://x/live/stream', { headers: cookie }));
    const reader = res.body!.getReader();
    const dec = new TextDecoder();
    let acc = '';
    const pump = async (until: (a: string) => boolean): Promise<void> => {
      for (let i = 0; i < 8 && !until(acc); i++) {
        const { value, done } = await reader.read();
        if (done) break;
        acc += dec.decode(value, { stream: true });
      }
    };

    // Drain the opening frames so the subscription is registered, THEN publish.
    await pump((a) => a.includes('event: schedule'));
    publishSnapshot(snap('PUSHED-2026'));
    await pump((a) => a.includes('PUSHED-2026'));
    await reader.cancel();

    expect(acc).toContain('event: snapshot');
    expect(acc).toContain('PUSHED-2026');
  });
});

describe('POST /live/check', () => {
  beforeAll(() => resetCheckThrottle());
  afterEach(() => {
    resetLiveEvents();
    resetCheckThrottle(); // module-global throttle must not bleed between cases
  });

  it('triggers a backend cycle (runNow) for a viewer, and debounces a click-storm', async () => {
    const runNow = vi.fn(() => true);
    const { app, db } = await bootApp(runNow);
    const cookie = await sessionHeaders(db, 'viewer');

    const first = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: cookie }));
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ ok: true, ran: true });
    expect(runNow).toHaveBeenCalledTimes(1);

    // A second click inside the floor coalesces — no second provider sweep.
    const second = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: cookie }));
    expect(await second.json()).toEqual({ ok: true, ran: false, reason: 'debounced' });
    expect(runNow).toHaveBeenCalledTimes(1);
  });

  it('throttles per-caller — a different viewer is not debounced by another viewer’s check', async () => {
    const runNow = vi.fn(() => true);
    const { app, db } = await bootApp(runNow);
    const userA = await sessionHeaders(db, 'viewer'); // sessionHeaders mints a fresh user each call
    const userB = await sessionHeaders(db, 'viewer');

    const a = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: userA }));
    expect(await a.json()).toEqual({ ok: true, ran: true });
    // B's first click within A's 3s floor must NOT be debounced by A's timestamp.
    const b = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: userB }));
    expect(await b.json()).toEqual({ ok: true, ran: true });
    expect(runNow).toHaveBeenCalledTimes(2);
  });

  it('reports ran:false when the scheduler coalesced into an in-flight cycle', async () => {
    const runNow = vi.fn(() => false); // already in flight
    const { app, db } = await bootApp(runNow);
    const cookie = await sessionHeaders(db, 'viewer');
    const res = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: cookie }));
    expect(await res.json()).toEqual({ ok: true, ran: false });
  });

  it('401s without a session', async () => {
    const { app } = await bootApp(() => true);
    const res = await app.fetch(new Request('http://x/live/check', { method: 'POST' }));
    expect(res.status).toBe(401);
  });

  it('responds immediately while the manual cycle is still running (SSE carries the result)', async () => {
    // A manual full sync can run minutes; holding the HTTP response open that
    // long ties up the proxy and the client for nothing — the fresh snapshot
    // reaches every open tab via the stream anyway. `ran` is knowable
    // synchronously (started vs coalesced), so the route must answer at once.
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const scheduler = createScheduler({ cycle: () => gate, intervalMs: 60_000 });
    const client = createClient({ url: ':memory:' });
    const db = drizzle(client, { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
    const app = createApp({ db, scheduler, config: testConfig() });
    const cookie = await sessionHeaders(db, 'viewer');

    try {
      const res = await Promise.race([
        app.fetch(new Request('http://x/live/check', { method: 'POST', headers: cookie })),
        new Promise<never>((_, rej) => setTimeout(() => rej(new Error('route blocked on the running cycle')), 1_000)),
      ]);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ ok: true, ran: true });

      // While that cycle is still in flight, a DIFFERENT viewer's check coalesces.
      const other = await sessionHeaders(db, 'viewer');
      const second = await app.fetch(new Request('http://x/live/check', { method: 'POST', headers: other }));
      expect(await second.json()).toEqual({ ok: true, ran: false });
    } finally {
      release();
    }
  });
});
