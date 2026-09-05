import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { serve, type ServerType } from '@hono/node-server';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { createApp } from '../src/app';
import { freshDb, type Db } from './helpers/db';
import { sessionHeaders } from './helpers/auth';
import { listSiteGroups } from '../src/storage/config-store';
import { ALL_TOOLS, selectTools } from '../src/mcp/tools';
import { testConfig } from './helpers/config';

type ToolEnvelope = { ok: boolean; data?: unknown; error?: string; code?: string };

let db: Db;
let server: ServerType;
let baseUrl = '';
let adminToken = '';
let viewToken = '';

const json = { 'content-type': 'application/json' };

/** Read the JSON envelope a status tool writes into its single text content block. */
function envelope(result: unknown): ToolEnvelope {
  const content = (result as { content: Array<{ text: string }> }).content;
  return JSON.parse(content[0].text) as ToolEnvelope;
}

/** Connect a real MCP client to /mcp over Streamable HTTP with a bearer token. */
function connect(token: string): Promise<Client> {
  const client = new Client({ name: 'test-client', version: '1.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(`${baseUrl}/mcp`), {
    requestInit: { headers: { Authorization: `Bearer ${token}` } },
  });
  return client.connect(transport).then(() => client);
}

/** Mint an `sts_` bearer of the given role through the REAL POST /tokens route
 *  (admin-session-gated), returning the raw secret shown once. */
async function mintToken(app: ReturnType<typeof createApp>, adminCookie: string, role: 'admin' | 'user'): Promise<string> {
  const res = await app.request('/tokens', {
    method: 'POST',
    headers: { Cookie: adminCookie, 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: `mcp-${role}`, role }),
  });
  if (res.status !== 201) throw new Error(`mint ${role} token failed: ${res.status}`);
  return ((await res.json()) as { token: string }).token;
}

beforeAll(async () => {
  // The seam must actually validate the bearer — not bypass to admin (AUTH_DISABLED)
  // or accept the machine PEER_TOKEN.
  delete process.env.AUTH_DISABLED;
  delete process.env.PEER_TOKEN;

  db = await freshDb();
  const app = createApp({ db, config: testConfig() });
  await new Promise<void>((resolve) => {
    server = serve({ fetch: app.fetch, port: 0, hostname: '127.0.0.1' }, (info) => {
      baseUrl = `http://127.0.0.1:${info.port}`;
      // The Streamable-HTTP transport's DNS-rebinding guard checks the Host header,
      // which carries the ephemeral port — allow it.
      process.env.MCP_ALLOWED_HOSTS = `127.0.0.1:${info.port}`;
      resolve();
    });
  });

  const adminCookie = (await sessionHeaders(db, 'admin')).Cookie;
  adminToken = await mintToken(app, adminCookie, 'admin');
  viewToken = await mintToken(app, adminCookie, 'user');
}, 60_000);

afterAll(async () => {
  await new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve()));
});

describe('status /mcp over Streamable HTTP', () => {
  it('rejects a request with no bearer token (401)', async () => {
    const res = await fetch(`${baseUrl}/mcp`, {
      method: 'POST',
      headers: { ...json, accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} }),
    });
    expect(res.status).toBe(401);
  });

  it('admin token lists ALL tools; view token lists only the viewer-visible tools', async () => {
    const admin = await connect(adminToken);
    const view = await connect(viewToken);
    try {
      const adminTools = (await admin.listTools()).tools.map((t) => t.name);
      const viewTools = (await view.listTools()).tools.map((t) => t.name);

      expect(adminTools.length).toBe(ALL_TOOLS.length);
      expect(new Set(adminTools)).toEqual(new Set(ALL_TOOLS.map((t) => t.name)));

      // 18 read tools minus the 6 admin-only reads = 12 viewer-visible tools.
      expect(viewTools.length).toBe(12);
      expect(viewTools.length).toBe(selectTools('view').length);
      // Viewer-visible reads — every field is reachable through a NON-admin REST route
      // (/status, /snapshot, /live, /uptime, /history, /telemetry, /fleet, /deploy-projects).
      for (const name of [
        'get_status_summary',
        'get_problems',
        'get_uptime',
        'query_history',
        'get_fleet',
        'list_platform_projects',
        'find_unconfigured_sites',
        'get_links',
      ]) {
        expect(viewTools).toContain(name);
      }
      // Fail-closed layer 1: writes are not registered for view...
      expect(viewTools).not.toContain('create_group');
      // ...and neither are the admin-only reads. REST is the access authority — every one
      // of these has ONLY an admin-gated REST twin (/config/* or /users), so MCP must not
      // widen it. sites/groups expose raw config rows the curated /status DTO never shows.
      for (const name of ['list_sites', 'get_site', 'list_groups', 'list_users', 'list_platforms', 'list_peers']) {
        expect(viewTools).not.toContain(name);
      }
    } finally {
      await admin.close();
      await view.close();
    }
  });

  it('round-trips a read tool (get_status_summary) for an admin token', async () => {
    const admin = await connect(adminToken);
    try {
      const result = await admin.callTool({ name: 'get_status_summary', arguments: {} });
      const env = envelope(result);
      expect(env.ok).toBe(true);
      expect(env.data).toMatchObject({ overall: expect.any(String) });
      expect(Array.isArray((env.data as { services: unknown }).services)).toBe(true);
    } finally {
      await admin.close();
    }
  });

  it('round-trips a write tool (create_group) and persists the DB row', async () => {
    const admin = await connect(adminToken);
    try {
      const result = await admin.callTool({ name: 'create_group', arguments: { name: 'MCP Group', slug: 'mcp-grp' } });
      const env = envelope(result);
      expect(env.ok).toBe(true);
      expect(env.data).toMatchObject({ slug: 'mcp-grp', name: 'MCP Group' });

      // The write went through the SAME store the REST route uses — the row exists.
      const groups = await listSiteGroups(db);
      expect(groups.some((g) => g.slug === 'mcp-grp')).toBe(true);
    } finally {
      await admin.close();
    }
  });

  it('surfaces a failed write as an isError envelope (update a missing group)', async () => {
    const admin = await connect(adminToken);
    try {
      const result = await admin.callTool({ name: 'update_group', arguments: { id: 'does-not-exist', name: 'x' } });
      expect(result.isError).toBe(true);
      const env = envelope(result);
      expect(env.ok).toBe(false);
      expect(env.code).toBe('execution_error');
    } finally {
      await admin.close();
    }
  });

  it('refuses a write from a view-tier token (isError, fail-closed)', async () => {
    const view = await connect(viewToken);
    try {
      // create_group is not in the view tool set, so the call is refused: the SDK
      // surfaces the "tool not found" as an isError result — a view token can never
      // reach a write path.
      const result = await view.callTool({ name: 'create_group', arguments: { name: 'nope', slug: 'nope' } });
      expect(result.isError).toBe(true);
      // And the store was never touched.
      const groups = await listSiteGroups(db);
      expect(groups.some((g) => g.slug === 'nope')).toBe(false);
    } finally {
      await view.close();
    }
  });

  it('refuses an admin-only READ (list_users) from a view-tier token (isError, REST parity)', async () => {
    const view = await connect(viewToken);
    try {
      // list_users is a read, but its REST route (/users) is admin-only — so it is NOT in
      // the view tool set. The SDK surfaces the "tool not found" as an isError result: a
      // viewer can never read the roster over MCP, matching the REST access gate.
      const result = await view.callTool({ name: 'list_users', arguments: {} });
      expect(result.isError).toBe(true);
    } finally {
      await view.close();
    }
  });

  it('refuses an admin-only config READ (list_sites) from a view-tier token (isError, REST parity)', async () => {
    const view = await connect(viewToken);
    try {
      // list_sites is a read, but its ONLY REST twin (GET /config/sites) is admin-only —
      // it returns raw SiteRow config the curated /status DTO never exposes. So it is NOT
      // in the view tool set: a viewer can never read site config over MCP.
      const result = await view.callTool({ name: 'list_sites', arguments: {} });
      expect(result.isError).toBe(true);
    } finally {
      await view.close();
    }
  });
});
