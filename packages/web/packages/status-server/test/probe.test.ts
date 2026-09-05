import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Mock node:dns so the DNS-resolution checks are deterministic (the real probe
// does a live lookup). Hoisted so the mock factory can reference the spies.
const { resolve4, resolve6, resolveCname } = vi.hoisted(() => ({
  resolve4: vi.fn<(h: string) => Promise<string[]>>(),
  resolve6: vi.fn<(h: string) => Promise<string[]>>(),
  resolveCname: vi.fn<(h: string) => Promise<string[]>>(),
}));
vi.mock('node:dns', () => ({ promises: { resolve4, resolve6, resolveCname } }));

import { probe } from '../src/monitor/probe';
import type { ConfiguredEndpoint } from '../src/storage/config-store';

// Base endpoint shape — fields required by ConfiguredEndpoint.
const base: ConfiguredEndpoint = {
  slug: 'svc',
  group: 'test',
  name: 'Test Service',
  environment: null,
  url: 'https://example.com',
  kind: 'http',
  platform: null,
  deployProject: null,
  expectedStatus: 200,
};

beforeEach(() => {
  // Default: the host resolves via an A record, and fetch answers 200.
  resolve4.mockResolvedValue(['93.184.216.34']);
  resolve6.mockResolvedValue([]);
  resolveCname.mockResolvedValue([]);
  vi.stubGlobal('fetch', vi.fn(async () => new Response('ok', { status: 200 })));
});

afterEach(() => {
  vi.unstubAllGlobals();
  resolve4.mockReset();
  resolve6.mockReset();
  resolveCname.mockReset();
});

describe('probe', () => {
  it('classifies a healthy endpoint', async () => {
    const result = await probe(base);
    expect(result.status).toBe('healthy');
    expect(result.statusCode).toBe(200);
    expect(result.dnsOk).toBe(true);
    expect(result.error).toBeNull();
    expect(result.slug).toBe('svc');
  });

  it('marks an endpoint down on a 500', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('err', { status: 500 })));
    const result = await probe(base);
    expect(result.status).toBe('down');
    expect(result.statusCode).toBe(500);
    expect(result.dnsOk).toBe(true);
    expect(result.error).toContain('500');
  });

  it('treats a CNAME-only host as resolvable when all record checks are on (default)', async () => {
    resolve4.mockResolvedValue([]);
    resolve6.mockResolvedValue([]);
    resolveCname.mockResolvedValue(['cname.vercel-dns.com']);
    const result = await probe(base);
    expect(result.dnsOk).toBe(true);
    expect(result.status).toBe('healthy');
  });

  it('fails DNS when only the enabled record types do not resolve', async () => {
    // Only the A check is enabled, but the host resolves via CNAME → DNS fails,
    // and the disabled CNAME check is never queried.
    resolve4.mockResolvedValue([]);
    resolveCname.mockResolvedValue(['cname.vercel-dns.com']);
    const result = await probe({ ...base, dnsCheckA: true, dnsCheckAaaa: false, dnsCheckCname: false });
    expect(result.status).toBe('down');
    expect(result.dnsOk).toBe(false);
    expect(result.error).toContain('DNS');
    expect(resolveCname).not.toHaveBeenCalled();
    expect(resolve6).not.toHaveBeenCalled();
  });

  it('skips DNS resolution entirely when every record check is off', async () => {
    resolve4.mockResolvedValue([]);
    resolve6.mockResolvedValue([]);
    resolveCname.mockResolvedValue([]);
    const result = await probe({ ...base, dnsCheckA: false, dnsCheckAaaa: false, dnsCheckCname: false });
    // No DNS query was made, so the (failing) lookups don't gate the HTTP probe.
    expect(resolve4).not.toHaveBeenCalled();
    expect(resolve6).not.toHaveBeenCalled();
    expect(resolveCname).not.toHaveBeenCalled();
    expect(result.dnsOk).toBe(true);
    expect(result.status).toBe('healthy');
  });
});
