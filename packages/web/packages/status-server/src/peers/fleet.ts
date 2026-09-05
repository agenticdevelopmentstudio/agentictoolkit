import { eq } from 'drizzle-orm';
import type { Db } from '../libsql/client';
import { peers, peerSnapshots } from '../libsql/schema';

export interface FleetMember {
  self: boolean;
  label: string;
  baseUrl: string | null;
  overall: string | null;
  reachable: boolean;
  fetchedAt: string;
  payload: unknown;
}

/** This monitor's own compact snapshot + the latest stored snapshot per peer,
 *  each annotated with freshness. `self` is built from the live /snapshot body. */
export async function assembleFleet(
  db: Db,
  self: { label: string; snapshot: unknown; overall: string | null },
): Promise<FleetMember[]> {
  // Active peers only — the same filter `fetchPeers` polls on. An inactive peer is not
  // being checked, so its stored snapshot is frozen at whatever it last said; leaving
  // it on the board would show a permanently green (or permanently red) card for a
  // monitor nobody is watching, which is the one thing a status board must never do.
  const rows = await db.select().from(peers).where(eq(peers.isActive, true));
  const snaps = await db.select().from(peerSnapshots);
  const byPeer = new Map(snaps.map((s) => [s.peerId, s]));

  const selfMember: FleetMember = {
    self: true,
    label: self.label,
    baseUrl: null,
    overall: self.overall,
    reachable: true,
    fetchedAt: new Date().toISOString(),
    payload: self.snapshot,
  };

  // peerSnapshots.fetchedAt uses integer({ mode: 'timestamp' }) so Drizzle returns
  // a Date object — .toISOString() is correct. Fall back to epoch when no snap yet.
  const peerMembers: FleetMember[] = rows.map((p) => {
    const s = byPeer.get(p.id);
    return {
      self: false,
      label: p.label,
      baseUrl: p.baseUrl,
      overall: s?.overall ?? null,
      reachable: s?.reachable ?? false,
      fetchedAt: (s?.fetchedAt ?? new Date(0)).toISOString(),
      payload: s?.payload ?? null,
    };
  });

  return [selfMember, ...peerMembers];
}
