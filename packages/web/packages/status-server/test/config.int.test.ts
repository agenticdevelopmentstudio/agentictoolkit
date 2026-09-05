import { describe, it, expect, beforeAll } from 'vitest';
import { createApp } from '../src/app';
import { sessionHeaders } from './helpers/auth';
import { freshDb as bootDb } from './helpers/db';
import { testConfig } from './helpers/config';

describe('/config CRUD', () => {
  let app: ReturnType<typeof createApp>;
  let viewAuth: { Cookie: string };
  let adminAuth: { Cookie: string };

  beforeAll(async () => {
    const db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    adminAuth = await sessionHeaders(db, 'admin');
    app = createApp({ db, config: testConfig() });
  });

  it('view token cannot create a site-group (403)', async () => {
    const res = await app.request('/config/site-groups', {
      method: 'POST',
      headers: { ...viewAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ slug: 'g', name: 'G' }),
    });
    expect(res.status).toBe(403);
  });

  let peerId: string;

  it('admin token creates a peer (201) and the response never echoes the PEER_TOKEN', async () => {
    const res = await app.request('/config/peers', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'B', baseUrl: 'https://b.example.com', token: 'peerB' }),
    });
    expect(res.status).toBe(201);
    // The token is accepted on write but is a fleet secret — it must NEVER come back out.
    const row = await res.json() as { id: string; baseUrl: string; token?: unknown };
    expect(row.baseUrl).toBe('https://b.example.com');
    expect('token' in row).toBe(false);
    peerId = row.id;
  });

  it('admin can list peers and sees the created one, with the token redacted', async () => {
    const res = await app.request('/config/peers', { headers: adminAuth });
    expect(res.status).toBe(200);
    const peers = await res.json() as { baseUrl: string; token?: unknown }[];
    expect(Array.isArray(peers)).toBe(true);
    const created = peers.find((p) => p.baseUrl === 'https://b.example.com');
    expect(created).toBeDefined();
    // No peer row on the list surface may carry the secret token.
    expect(peers.every((p) => !('token' in p))).toBe(true);
  });

  it('admin can patch a peer and the updated response omits the token', async () => {
    const res = await app.request(`/config/peers/${peerId}`, {
      method: 'PATCH',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'B2', token: 'rotated' }),
    });
    expect(res.status).toBe(200);
    const row = await res.json() as { label: string; token?: unknown };
    expect(row.label).toBe('B2');
    expect('token' in row).toBe(false);
  });

  // `hasToken` is the ONLY thing a read surface may say about the secret: the config UI
  // needs to distinguish "this peer authenticates" from "its reads are public" without
  // ever receiving the value it would otherwise have to render in an input.
  it('peer rows report hasToken instead of the secret', async () => {
    const res = await app.request('/config/peers', { headers: adminAuth });
    const peers = await res.json() as { id: string; hasToken: boolean }[];
    expect(peers.find((p) => p.id === peerId)?.hasToken).toBe(true);

    const open = await app.request('/config/peers', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'Open', baseUrl: 'https://open.example.com' }),
    });
    expect(open.status).toBe(201);
    expect(await open.json()).toMatchObject({ hasToken: false });
  });

  it('patching token:null clears the secret and flips hasToken back to false', async () => {
    const res = await app.request(`/config/peers/${peerId}`, {
      method: 'PATCH',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: null }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ hasToken: false });

    // Put it back — later tests read this peer as the authenticated one.
    await app.request(`/config/peers/${peerId}`, {
      method: 'PATCH',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: 'peerB' }),
    });
  });

  it('a peer baseUrl is stored canonically — trimmed, no trailing slash', async () => {
    const res = await app.request('/config/peers', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'Slashy', baseUrl: '  https://slashy.example.com/// ' }),
    });
    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({ baseUrl: 'https://slashy.example.com' });
  });

  it('a duplicate baseUrl is a 409, not an opaque 500 — trailing slashes included', async () => {
    const res = await app.request('/config/peers', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'Dupe', baseUrl: 'https://b.example.com/' }),
    });
    expect(res.status).toBe(409);
  });

  // The unique index on base_url is byte-exact, so the ONLY thing keeping one monitor
  // from being added (and polled, and drawn) twice is that these all canonicalize to the
  // same string. Each of these is https://b.example.com wearing a different hat.
  it('folds case, the default port, and query/fragment before the uniqueness check', async () => {
    for (const baseUrl of [
      'https://B.Example.COM',
      'https://b.example.com:443',
      'https://b.example.com/?utm=1#top',
    ]) {
      const res = await app.request('/config/peers', {
        method: 'POST',
        headers: { ...adminAuth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ label: 'Dupe', baseUrl }),
      });
      expect(res.status, `baseUrl ${baseUrl} should collide with the existing peer`).toBe(409);
    }
  });

  // A monitor is already the `self` card on its own fleet board. Adding itself as a peer
  // would have it poll its own /public/status-summary and draw a second, laggier copy.
  it('rejects this monitor’s own URL as a peer (400), however it is spelled', async () => {
    const previous = process.env.PUBLIC_BASE_URL;
    process.env.PUBLIC_BASE_URL = 'https://self.example.com';
    try {
      for (const baseUrl of ['https://self.example.com', 'https://SELF.example.com/', 'https://self.example.com:443']) {
        const res = await app.request('/config/peers', {
          method: 'POST',
          headers: { ...adminAuth, 'Content-Type': 'application/json' },
          body: JSON.stringify({ label: 'Me', baseUrl }),
        });
        expect(res.status, `baseUrl ${baseUrl} is this monitor itself`).toBe(400);
      }
    } finally {
      if (previous === undefined) delete process.env.PUBLIC_BASE_URL;
      else process.env.PUBLIC_BASE_URL = previous;
    }
  });

  it('a baseUrl that is not an absolute http(s) URL is rejected (400)', async () => {
    for (const baseUrl of ['b.example.com', '/relative', 'ftp://b.example.com', 'javascript:alert(1)']) {
      const res = await app.request('/config/peers', {
        method: 'POST',
        headers: { ...adminAuth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ label: 'Bad', baseUrl }),
      });
      expect(res.status, `baseUrl ${baseUrl} should be rejected`).toBe(400);
    }
  });

  it('admin can delete a peer', async () => {
    const create = await app.request('/config/peers', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'Temp', baseUrl: 'https://temp.example.com' }),
    });
    const { id } = await create.json() as { id: string };

    const del = await app.request(`/config/peers/${id}`, { method: 'DELETE', headers: adminAuth });
    expect(del.status).toBe(200);

    const list = await app.request('/config/peers', { headers: adminAuth });
    const peers = await list.json() as { id: string }[];
    expect(peers.some((p) => p.id === id)).toBe(false);
  });

  it('admin creates a site-group', async () => {
    const res = await app.request('/config/site-groups', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ slug: 'grp-test', name: 'Test Group' }),
    });
    expect(res.status).toBe(201);
    const row = await res.json() as { id: string; slug: string; name: string };
    expect(row.slug).toBe('grp-test');
    expect(row.name).toBe('Test Group');
  });

  it('admin can list site-groups', async () => {
    const res = await app.request('/config/site-groups', { headers: adminAuth });
    expect(res.status).toBe(200);
    const rows = await res.json() as { slug: string }[];
    expect(Array.isArray(rows)).toBe(true);
    expect(rows.some((g) => g.slug === 'grp-test')).toBe(true);
  });

  it('admin can patch a site-group', async () => {
    // Create one to patch
    const create = await app.request('/config/site-groups', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ slug: 'patch-me', name: 'Before' }),
    });
    const created = await create.json() as { id: string };
    const id = created.id;

    const patch = await app.request(`/config/site-groups/${id}`, {
      method: 'PATCH',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'After' }),
    });
    expect(patch.status).toBe(200);
    const updated = await patch.json() as { name: string };
    expect(updated.name).toBe('After');
  });

  it('admin can delete a site-group', async () => {
    const create = await app.request('/config/site-groups', {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ slug: 'delete-me', name: 'Deletable' }),
    });
    const created = await create.json() as { id: string };

    const del = await app.request(`/config/site-groups/${created.id}`, {
      method: 'DELETE',
      headers: adminAuth,
    });
    expect(del.status).toBe(200);
    const body = await del.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('POST /config/seed populates groups, sites, and endpoints', async () => {
    // Use a fresh DB so seed counts are deterministic
    const db2 = await bootDb();
    const adminAuth2 = await sessionHeaders(db2, 'admin');
    const app2 = createApp({ db: db2, config: testConfig() });

    const res = await app2.request('/config/seed', {
      method: 'POST',
      headers: adminAuth2,
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; groups: number; sites: number; endpoints: number };
    expect(body.ok).toBe(true);
    expect(body.groups).toBeGreaterThan(0);
    expect(body.sites).toBeGreaterThan(0);
    expect(body.endpoints).toBeGreaterThan(0);
  });
});
