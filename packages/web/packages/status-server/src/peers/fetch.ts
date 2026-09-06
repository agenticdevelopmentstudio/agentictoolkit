import type { Storage } from '../storage/ports';

/** Pull each active peer's /snapshot and upsert peer_snapshots. Fail-soft: an
 *  unreachable peer is recorded as reachable=false and never throws. */
export async function fetchPeers(storage: Storage, fetchImpl: typeof fetch = fetch): Promise<void> {
  const rows = await storage.peers.listActive();
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
        await storage.peers.upsertSnapshot({
          ...base,
          payload: payload as unknown,
          overall: payload.overall ?? null,
          reachable: true,
          error: null,
        });
      } catch (err) {
        await storage.peers.upsertSnapshot({
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
