import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { pingHeartbeat } from '../src/monitor/heartbeat';
import { runMonitorCycle } from '../src/monitor/cycle-runner';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

const HEARTBEAT_URL = 'https://hc.example.com/ping/abc';

// The dead-man's switch: every layer of the watchdog chain lives INSIDE the
// container — when the container itself dies (volume, Railway, restart retries
// exhausted) nothing tells anyone. Each successful full sync pings
// HEARTBEAT_URL (healthchecks.io-style); a missed ping alerts externally no
// matter how the monitor died.

async function freshDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

beforeEach(() => {
  vi.stubEnv('HEARTBEAT_URL', 'https://hc.example.com/ping/abc');
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('pingHeartbeat', () => {
  it('GETs the configured URL with a bounded signal', async () => {
    const fetchMock = vi.fn(async (_u: string | URL, init?: RequestInit) => {
      expect(init?.signal).toBeTruthy();
      return new Response('ok');
    });
    vi.stubGlobal('fetch', fetchMock);
    await pingHeartbeat(HEARTBEAT_URL);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(String(fetchMock.mock.calls[0]![0])).toBe('https://hc.example.com/ping/abc');
  });

  it('is a no-op without a url and fail-soft on network errors', async () => {
    const fetchMock = vi.fn(async () => {
      throw new Error('down');
    });
    vi.stubGlobal('fetch', fetchMock);
    await pingHeartbeat(null); // no url → no fetch
    expect(fetchMock).not.toHaveBeenCalled();
    await expect(pingHeartbeat(HEARTBEAT_URL)).resolves.toBeUndefined(); // failure logged, never thrown
  });
});

describe('cycle-runner heartbeat wiring', () => {
  it('pings after a successful FULL sync, not on probe-only ticks', async () => {
    const db = await freshDb();
    const pings: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (u: string | URL) => {
        pings.push(String(u));
        return new Response('ok');
      }),
    );

    await runMonitorCycle(db, { fullSync: false, config: testConfig(), conn: { url: ':memory:' } });
    expect(pings.filter((u) => u.includes('hc.example.com'))).toHaveLength(0);

    await runMonitorCycle(db, { fullSync: true, config: testConfig(), conn: { url: ':memory:' } });
    expect(pings.filter((u) => u.includes('hc.example.com'))).toHaveLength(1);
  });

  it('does NOT ping when the sync fails', async () => {
    // Un-migrated DB: the cycle's first read throws — the heartbeat must stay
    // silent so the external monitor sees the miss.
    const db = drizzle(createClient({ url: ':memory:' }), { schema });
    const pings: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (u: string | URL) => {
        pings.push(String(u));
        return new Response('ok');
      }),
    );
    await expect(runMonitorCycle(db, { fullSync: true, config: testConfig(), conn: { url: ':memory:' } })).rejects.toThrow();
    expect(pings.filter((u) => u.includes('hc.example.com'))).toHaveLength(0);
  });
});

describe('pingHeartbeat response status', () => {
  it('logs a non-2xx check-in instead of treating it as a successful ping', async () => {
    // A typo'd/expired HEARTBEAT_URL answers 404. fetch() RESOLVES, so without a
    // status check every cycle believes it checked in while the external
    // dead-man service never sees a valid ping — the watchdog silently never arms.
    const errors: string[] = [];
    const spy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
      errors.push(args.map(String).join(' '));
    });
    vi.stubGlobal('fetch', vi.fn(async () => new Response('not found', { status: 404 })));
    try {
      await pingHeartbeat(HEARTBEAT_URL);
      expect(errors.join('\n')).toMatch(/heartbeat/i);
      expect(errors.join('\n')).toContain('404');
    } finally {
      spy.mockRestore();
    }
  });
});
