import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  listWorkerCustomDomains,
  canonicalHostByWorker,
  resolveCfAccountId,
  _resetCfAccountCache,
} from '@agentic-toolkit/deploy-platform/providers';

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.CLOUDFLARE_ACCOUNT_ID;
  _resetCfAccountCache(); // discovery is memoized per token — clear it between cases
});

const signal = new AbortController().signal;

describe('listWorkerCustomDomains', () => {
  it('builds a lowercased host→worker map from /workers/domains', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        Response.json({
          success: true,
          result: [
            { hostname: 'temporal.today', service: 'temporal-web', environment: 'production' },
            { hostname: 'Temporal.Company', service: 'temporal-landing', environment: 'production' },
            { hostname: 'admin.temporal.today', service: 'temporal-admin', environment: 'production' },
          ],
        }),
      ),
    );
    const map = await listWorkerCustomDomains('acct', 'tok', signal);
    expect(map).toEqual({
      'temporal.today': 'temporal-web',
      'temporal.company': 'temporal-landing', // host lowercased
      'admin.temporal.today': 'temporal-admin',
    });
  });

  it('hits the account workers/domains endpoint with the bearer token', async () => {
    const fetchMock = vi.fn(async (_url: string, _init?: RequestInit) => Response.json({ success: true, result: [] }));
    vi.stubGlobal('fetch', fetchMock);
    await listWorkerCustomDomains('my-account', 'secret-tok', signal);
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe('https://api.cloudflare.com/client/v4/accounts/my-account/workers/domains');
    expect(init?.headers).toMatchObject({ Authorization: 'Bearer secret-tok' });
  });

  it('skips entries missing a hostname or service', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        Response.json({
          success: true,
          result: [
            { hostname: 'ok.example.com', service: 'worker-a' },
            { hostname: '', service: 'worker-b' }, // no hostname
            { hostname: 'no-service.example.com' }, // no service
          ],
        }),
      ),
    );
    expect(await listWorkerCustomDomains('a', 't', signal)).toEqual({ 'ok.example.com': 'worker-a' });
  });

  it('returns null on a non-2xx response (caller falls back to the static map)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('nope', { status: 403 })));
    expect(await listWorkerCustomDomains('a', 't', signal)).toBeNull();
  });

  it('returns null when the API reports success:false', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ success: false, errors: [{ message: 'x' }] })));
    expect(await listWorkerCustomDomains('a', 't', signal)).toBeNull();
  });

  it('returns null when fetch throws (network/abort)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('aborted');
      }),
    );
    expect(await listWorkerCustomDomains('a', 't', signal)).toBeNull();
  });
});

describe('canonicalHostByWorker', () => {
  it('inverts host→worker into worker→one canonical host', () => {
    // temporal-landing fronts an apex + its www alias; the apex wins.
    const map = canonicalHostByWorker({
      'temporal.today': 'temporal-web',
      'temporal.company': 'temporal-landing',
      'www.temporal.company': 'temporal-landing',
      'admin.temporal.today': 'temporal-admin',
    });
    expect(map).toEqual({
      'temporal-web': 'temporal.today',
      'temporal-landing': 'temporal.company',
      'temporal-admin': 'admin.temporal.today',
    });
  });

  it('is empty for an empty map (no custom domains → no entries)', () => {
    expect(canonicalHostByWorker({})).toEqual({});
  });
});

describe('resolveCfAccountId', () => {
  it('returns the configured id without any network call', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    expect(await resolveCfAccountId('cfg-acct', 'tok', signal)).toBe('cfg-acct');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('trims and ignores a blank/whitespace configured id', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ success: true, result: [{ id: 'only' }] })));
    expect(await resolveCfAccountId('  ', 'tok', signal)).toBe('only');
    expect(await resolveCfAccountId('  spaced  ', 'tok', signal)).toBe('spaced');
  });

  it('falls back to CLOUDFLARE_ACCOUNT_ID env before hitting the API', async () => {
    process.env.CLOUDFLARE_ACCOUNT_ID = 'env-acct';
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBe('env-acct');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('auto-discovers from /accounts when the token sees exactly one account', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      expect(url).toBe('https://api.cloudflare.com/client/v4/accounts?per_page=50');
      return Response.json({ success: true, result: [{ id: 'sole-acct', name: 'X' }] });
    });
    vi.stubGlobal('fetch', fetchMock);
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBe('sole-acct');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('does NOT guess when the token sees several accounts', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => Response.json({ success: true, result: [{ id: 'a' }, { id: 'b' }] })),
    );
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBeNull();
  });

  it('returns null when the token sees zero accounts', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ success: true, result: [] })));
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBeNull();
  });

  it('memoizes a successful discovery per token (no second /accounts probe)', async () => {
    const fetchMock = vi.fn(async () => Response.json({ success: true, result: [{ id: 'sole-acct' }] }));
    vi.stubGlobal('fetch', fetchMock);
    expect(await resolveCfAccountId(undefined, 'memo-tok', signal)).toBe('sole-acct');
    expect(await resolveCfAccountId(undefined, 'memo-tok', signal)).toBe('sole-acct');
    expect(fetchMock).toHaveBeenCalledTimes(1); // second call served from the memo
  });

  it('does NOT cache a null result (a transient failure is re-probed)', async () => {
    const fetchMock = vi.fn(async () => new Response('no', { status: 500 }));
    vi.stubGlobal('fetch', fetchMock);
    expect(await resolveCfAccountId(undefined, 'flaky-tok', signal)).toBeNull();
    expect(await resolveCfAccountId(undefined, 'flaky-tok', signal)).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(2); // null isn't cached → re-probed
  });

  it('returns null when /accounts fails (non-2xx, success:false, or throw)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('no', { status: 403 })));
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBeNull();
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ success: false })));
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBeNull();
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('net'); }));
    expect(await resolveCfAccountId(undefined, 'tok', signal)).toBeNull();
  });
});
