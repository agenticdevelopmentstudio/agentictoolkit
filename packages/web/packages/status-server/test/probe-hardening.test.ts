import { describe, it, expect, vi, afterEach } from 'vitest';
import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

// The DNS-timeout case needs a resolver that never answers; the body cases skip
// DNS entirely (all record checks off), so the mock never gates them.
const { resolve4, resolve6, resolveCname } = vi.hoisted(() => ({
  resolve4: vi.fn<(h: string) => Promise<string[]>>(),
  resolve6: vi.fn<(h: string) => Promise<string[]>>(),
  resolveCname: vi.fn<(h: string) => Promise<string[]>>(),
}));
vi.mock('node:dns', () => ({ promises: { resolve4, resolve6, resolveCname } }));

import { probe, PROBE_BODY_MAX_BYTES } from '../src/monitor/probe';
import type { ConfiguredEndpoint } from '../src/storage/config-store';

// These tests exercise the REAL fetch against a real local server: the failure
// modes under test (a body that never finishes, an endless body, an unread
// body's socket) live below the Response abstraction, so a stubbed fetch could
// never catch a regression in them.

const NO_DNS = { dnsCheckA: false, dnsCheckAaaa: false, dnsCheckCname: false } as const;

function endpoint(url: string, extra: Partial<ConfiguredEndpoint> = {}): ConfiguredEndpoint {
  return {
    slug: 'svc',
    group: 'test',
    name: 'Test Service',
    environment: null,
    url,
    kind: 'http',
    platform: null,
    deployProject: null,
    expectedStatus: 200,
    ...NO_DNS,
    ...extra,
  };
}

let server: Server | null = null;
const timers: NodeJS.Timeout[] = [];

function listen(handler: (res: ServerResponse) => void): Promise<string> {
  server = createServer((_req, res) => handler(res));
  return new Promise((resolve) => {
    server!.listen(0, '127.0.0.1', () => {
      const { port } = server!.address() as AddressInfo;
      resolve(`http://127.0.0.1:${port}/`);
    });
  });
}

afterEach(async () => {
  for (const t of timers) clearInterval(t);
  timers.length = 0;
  if (server) {
    server.closeAllConnections();
    await new Promise((resolve) => server!.close(resolve));
    server = null;
  }
  resolve4.mockReset();
  resolve6.mockReset();
  resolveCname.mockReset();
});

describe('probe body hardening', () => {
  it('times out a response whose body trickles forever (headers fast, body never ends)', async () => {
    // The outage vector: headers arrive instantly, then the body drips a byte at
    // a time forever. The probe's deadline must cover the BODY read too — before
    // the fix the abort timer was cleared at headers, so this hung indefinitely,
    // blew the cycle budget every tick, and restart-looped the container.
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.write('<html>');
      timers.push(setInterval(() => res.write('x'), 20));
    });
    // expectBody forces the body read; the marker never arrives.
    const result = await probe(endpoint(url, { expectBody: 'marker' }), { timeoutMs: 300 });
    expect(result.status).toBe('down');
    expect(result.error).toContain('Timeout');
  }, 3_000);

  it('stops reading an endless body once the marker fits in the capped read', async () => {
    // The marker is in the first chunk; the body then streams forever. The capped
    // reader must classify on what it has and close, not drain to the end.
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.write('<html>marker</html>');
      timers.push(setInterval(() => res.write('x'.repeat(64 * 1024)), 5));
    });
    const result = await probe(endpoint(url, { expectBody: 'marker' }), { timeoutMs: 2_000 });
    expect(result.status).toBe('healthy');
  }, 3_000);

  it('closes the connection of a plain endpoint without draining its body', async () => {
    // Plain http endpoints never read the body; the response socket must be
    // released (cancelled), not left open holding a keep-alive slot.
    let responseClosed = false;
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.write('<html>');
      res.on('close', () => {
        responseClosed = true;
      });
      timers.push(setInterval(() => res.write('x'), 20));
    });
    const result = await probe(endpoint(url), { timeoutMs: 2_000 });
    expect(result.status).toBe('healthy');
    await vi.waitFor(() => {
      expect(responseClosed).toBe(true);
    });
  }, 3_000);

  it('bounds a DNS resolution that never answers', async () => {
    resolve4.mockReturnValue(new Promise<string[]>(() => {})); // resolver black-holes
    resolve6.mockReturnValue(new Promise<string[]>(() => {}));
    resolveCname.mockReturnValue(new Promise<string[]>(() => {}));
    const result = await probe(
      endpoint('https://never-resolves.example', { dnsCheckA: true, dnsCheckAaaa: true, dnsCheckCname: true }),
      { timeoutMs: 2_000, dnsTimeoutMs: 200 },
    );
    expect(result.status).toBe('down');
    expect(result.dnsOk).toBe(false);
    expect(result.error).toContain('DNS');
  }, 3_000);
});

describe('probe body-read failure semantics', () => {
  it('keeps a 200 healthy when the BODY errors mid-stream (does not invent an outage)', async () => {
    // A body-read failure is not evidence the site is down: the server answered
    // 200 with good headers, then the connection broke mid-body (target's
    // graceful restart, flaky intermediary). The old res.text().catch(() => "")
    // swallowed this and classified from the status code. Since applyHttpIssues
    // has NO debounce, letting it hard-fail to `down` means ONE blip opens an
    // issue AND pages on-call — a false outage from a healthy site.
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html', 'Content-Length': '1000' });
      res.write('<html>partial');
      // Destroy the socket mid-body: the client's read rejects.
      setTimeout(() => res.destroy(), 20);
    });
    const result = await probe(endpoint(url, { kind: 'health' }), { timeoutMs: 2_000 });
    expect(result.status).not.toBe('down');
    expect(result.statusCode).toBe(200);
  }, 3_000);

  it('still reports down when the body read hits the probe DEADLINE', async () => {
    // The trickle case must remain `down` — that endpoint really is not serving.
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.write('<html>');
      timers.push(setInterval(() => res.write('x'), 20));
    });
    const result = await probe(endpoint(url, { expectBody: 'marker' }), { timeoutMs: 300 });
    expect(result.status).toBe('down');
    expect(result.error).toContain('Timeout');
  }, 3_000);

  it('says the body was TRUNCATED when a marker is missing only because of the cap', async () => {
    // A marker beyond PROBE_BODY_MAX_BYTES reads as missing. Reporting a bare
    // "expected content not found" is indistinguishable from a genuinely broken
    // page — the operator has no way to know the cap caused it.
    const url = await listen((res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.write('x'.repeat(PROBE_BODY_MAX_BYTES + 1024)); // marker would sit past the cap
      res.end();
    });
    const result = await probe(endpoint(url, { expectBody: 'marker-past-the-cap' }), { timeoutMs: 2_000 });
    expect(result.status).toBe('down');
    expect(result.error).toMatch(/truncat/i);
  }, 3_000);
});
