import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import {
  noteRateLimited,
  rateLimitedUntil,
  DEFAULT_COOLDOWN_MS,
  MAX_COOLDOWN_MS,
  _resetProviderCooldowns,
} from '@agentic-toolkit/deploy-platform/cooldown';
import { fetchVercelDeployments } from '../src/monitor/fetch-vercel';
import { fetchRailwayDeployments } from '../src/monitor/fetch-railway';
import { fetchCloudflareDeployments } from '../src/monitor/fetch-cloudflare';

beforeEach(() => _resetProviderCooldowns());
afterEach(() => vi.unstubAllGlobals());

// A rate-limited provider re-hit at full cadence never de-escalates: every poll
// (cycle, dashboard enumeration, self-check) burns more quota and extends the
// throttle. After a 429 the provider is left alone until the cooldown lapses.

describe('provider cooldown registry', () => {
  it('defaults to 60s and clears after expiry', () => {
    const t0 = 1_000_000;
    noteRateLimited('vercel', null, t0);
    expect(rateLimitedUntil('vercel', t0 + 1)).toBe(t0 + DEFAULT_COOLDOWN_MS);
    expect(rateLimitedUntil('vercel', t0 + DEFAULT_COOLDOWN_MS + 1)).toBeNull();
    expect(rateLimitedUntil('railway', t0)).toBeNull(); // per-provider, not global
  });

  it('honors a numeric Retry-After and caps runaway values', () => {
    const t0 = 1_000_000;
    noteRateLimited('vercel', '7', t0);
    expect(rateLimitedUntil('vercel', t0 + 1)).toBe(t0 + 7_000);
    noteRateLimited('railway', '86400', t0); // a day — cap it
    expect(rateLimitedUntil('railway', t0 + 1)).toBe(t0 + MAX_COOLDOWN_MS);
  });
});

describe('fetchers under 429', () => {
  it('vercel: a 429 poll opens the cooldown; the next poll never touches the network', async () => {
    const fetchMock = vi.fn(async () => new Response('slow down', { status: 429, headers: { 'retry-after': '30' } }));
    vi.stubGlobal('fetch', fetchMock);

    const first = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });
    expect(first.ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const second = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });
    expect(second.ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1); // cooling down — no new request
  });

  it('railway: a 429 on the GraphQL endpoint cools the provider down', async () => {
    const fetchMock = vi.fn(async () => new Response('slow down', { status: 429 }));
    vi.stubGlobal('fetch', fetchMock);

    await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok' });
    const callsAfterFirst = fetchMock.mock.calls.length;
    await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok' });
    expect(fetchMock.mock.calls.length).toBe(callsAfterFirst); // no further requests
  });

  it('cloudflare: a 429 on the script listing cools the provider down', async () => {
    const fetchMock = vi.fn(async () => new Response('slow down', { status: 429 }));
    vi.stubGlobal('fetch', fetchMock);

    await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    const callsAfterFirst = fetchMock.mock.calls.length;
    const second = await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    expect(second.ok).toBe(false);
    expect(fetchMock.mock.calls.length).toBe(callsAfterFirst);
  });
});

describe('the cycle guard gates on the cooldown (a fetcher cannot forget)', () => {
  it('skips a provider poll entirely while that provider is cooling down', async () => {
    const { guard } = await import('../src/monitor/sync');
    noteRateLimited('railway', '120');

    let polled = false;
    const out = await guard<{ ok: boolean; deploys: [] }>('railway', 'railway', { ok: false, deploys: [] }, async () => {
      polled = true;
      return { ok: true, deploys: [] };
    });

    expect(polled).toBe(false); // never reached the network
    expect(out.ok).toBe(false); // reported as not-ok, so the prune is skipped
  });

  it('runs the poll normally when the provider is not cooling down', async () => {
    const { guard } = await import('../src/monitor/sync');
    let polled = false;
    const out = await guard<{ ok: boolean; deploys: [] }>('vercel', 'vercel', { ok: false, deploys: [] }, async () => {
      polled = true;
      return { ok: true, deploys: [] };
    });
    expect(polled).toBe(true);
    expect(out.ok).toBe(true);
  });
});
