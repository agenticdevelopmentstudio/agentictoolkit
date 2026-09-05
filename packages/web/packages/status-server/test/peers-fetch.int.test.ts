import { describe, it, expect } from 'vitest';
import * as schema from '../src/libsql/schema';
import { fetchPeers } from '../src/peers/fetch';
import { freshDb } from './helpers/db';

describe('fetchPeers', () => {
  it('stores a reachable peer snapshot', async () => {
    const db = await freshDb();
    await db.insert(schema.peers).values({ label: 'B', baseUrl: 'https://b.example.com', token: 't' });
    const fakeFetch = async () => new Response(JSON.stringify({ overall: 'healthy' }), { status: 200 });
    await fetchPeers(db, fakeFetch as unknown as typeof fetch);
    const snap = await db.select().from(schema.peerSnapshots);
    expect(snap[0].reachable).toBe(true);
    expect(snap[0].overall).toBe('healthy');
  });

  it('records an unreachable peer without throwing', async () => {
    const db = await freshDb();
    await db.insert(schema.peers).values({ label: 'B', baseUrl: 'https://b.example.com' });
    const failFetch = async () => {
      throw new Error('ECONNREFUSED');
    };
    await fetchPeers(db, failFetch as unknown as typeof fetch);
    const snap = await db.select().from(schema.peerSnapshots);
    expect(snap[0].reachable).toBe(false);
    expect(snap[0].error).toContain('ECONNREFUSED');
  });
});
