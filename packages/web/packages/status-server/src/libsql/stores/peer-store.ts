import { eq } from "drizzle-orm";
import type { Db } from "../client";
import { peers, peerSnapshots } from "../schema";
import type { PeerRow, PeerSnapshotRow, PeerSnapshotUpsert, PeerStore } from "../../storage/ports";

// SQLite/libSQL adapter of PeerStore over `peers` + `peer_snapshots`.

export function createPeerStore(db: Db): PeerStore {
  return {
    async listActive(): Promise<PeerRow[]> {
      return db.select().from(peers).where(eq(peers.isActive, true));
    },

    async upsertSnapshot(row: PeerSnapshotUpsert): Promise<void> {
      await db
        .insert(peerSnapshots)
        .values(row)
        .onConflictDoUpdate({ target: peerSnapshots.peerId, set: row });
    },

    async listSnapshots(): Promise<PeerSnapshotRow[]> {
      return db.select().from(peerSnapshots);
    },
  };
}
