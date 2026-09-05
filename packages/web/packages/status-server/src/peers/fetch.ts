import { eq } from 'drizzle-orm';
import type { Db } from '../libsql/client';
import { peers, peerSnapshots } from '../libsql/schema';

/** Pull each active peer's /snapshot and upsert peer_snapshots. Fail-soft: an
 *  unreachable peer is recorded as reachable=false and never throws. */
export async function fetchPeers(db: Db, fetchImpl: typeof fetch = fetch): Promise<void> {
  const rows = await db.select().from(peers).where(eq(peers.isActive, true));
  await Promise.all(
    rows.map(async (peer) => {
      const base = { peerId: peer.id, fetchedAt: new Date() };
      try {
        const res = await fetchImpl(`${peer.baseUrl}/snapshot`, {
          headers: peer.token ? { Authorization: `Bearer ${peer.token}` } : {},
          signal: AbortSignal.timeout(10_000),
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const payload = (await res.json()) as { overall?: string };
        await upsert(db, {
          ...base,
          payload: payload as unknown,
          overall: payload.overall ?? null,
          reachable: true,
          error: null,
        });
      } catch (err) {
        await upsert(db, {
          ...base,
          payload: null,
          overall: null,
          reachable: false,
          error: (err as Error).message,
        });
      }
    }),
  );
}

async function upsert(db: Db, row: typeof peerSnapshots.$inferInsert): Promise<void> {
  await db
    .insert(peerSnapshots)
    .values(row)
    .onConflictDoUpdate({ target: peerSnapshots.peerId, set: row });
}
