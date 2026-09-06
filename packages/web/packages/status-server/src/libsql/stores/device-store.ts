import { and, eq, lt } from "drizzle-orm";
import type { Db } from "../client";
import { apiTokens, deviceAuthorizations } from "../schema";
import type { DeviceGrantRow, DeviceStore } from "../../storage/ports";

// SQLite/libSQL adapter of DeviceStore over `device_authorizations` +
// `api_tokens` (role/expiry lookup by id).

function toGrantRow(r: typeof deviceAuthorizations.$inferSelect): DeviceGrantRow {
  return {
    id: r.id,
    cliLabel: r.cliLabel,
    status: r.status as DeviceGrantRow['status'],
    createdAt: r.createdAt,
    expiresAt: r.expiresAt,
    lastPollAt: r.lastPollAt,
  };
}

export function createDeviceStore(db: Db): DeviceStore {
  return {
    async purgeExpired(): Promise<void> {
      await db.delete(deviceAuthorizations).where(lt(deviceAuthorizations.expiresAt, new Date()));
    },

    async create(input): Promise<void> {
      await db.insert(deviceAuthorizations).values(input);
    },

    async findByDeviceCodeHash(hash: string): Promise<DeviceGrantRow | null> {
      const [row] = await db
        .select()
        .from(deviceAuthorizations)
        .where(eq(deviceAuthorizations.deviceCodeHash, hash))
        .limit(1);
      return row ? toGrantRow(row) : null;
    },

    async findByUserCodeHash(hash: string): Promise<DeviceGrantRow | null> {
      const [row] = await db
        .select()
        .from(deviceAuthorizations)
        .where(eq(deviceAuthorizations.userCodeHash, hash))
        .limit(1);
      return row ? toGrantRow(row) : null;
    },

    async deleteById(id: string): Promise<void> {
      await db.delete(deviceAuthorizations).where(eq(deviceAuthorizations.id, id));
    },

    async markPolled(id: string): Promise<void> {
      await db.update(deviceAuthorizations).set({ lastPollAt: new Date() }).where(eq(deviceAuthorizations.id, id));
    },

    async consumeApproved(id: string): Promise<{ tokenRaw: string; tokenId: string } | null> {
      // SINGLE-USE, atomic: delete-returning both reads the held secret AND
      // consumes the row in one statement — a second concurrent poll's delete
      // matches zero rows and falls through to null.
      const [consumed] = await db.delete(deviceAuthorizations).where(eq(deviceAuthorizations.id, id)).returning();
      if (!consumed?.tokenRaw || !consumed.tokenId) return null;
      return { tokenRaw: consumed.tokenRaw, tokenId: consumed.tokenId };
    },

    async approve(id, patch): Promise<boolean> {
      const updated = await db
        .update(deviceAuthorizations)
        .set({ status: 'approved', tokenId: patch.tokenId, tokenRaw: patch.tokenRaw, approvedBy: patch.approvedBy })
        .where(and(eq(deviceAuthorizations.id, id), eq(deviceAuthorizations.status, 'pending')))
        .returning({ id: deviceAuthorizations.id });
      return updated.length > 0;
    },

    async deny(id: string): Promise<boolean> {
      const updated = await db
        .update(deviceAuthorizations)
        .set({ status: 'denied' })
        .where(and(eq(deviceAuthorizations.id, id), eq(deviceAuthorizations.status, 'pending')))
        .returning({ id: deviceAuthorizations.id });
      return updated.length > 0;
    },

    async tokenRoleAndExpiry(tokenId: string): Promise<{ role: 'admin' | 'user'; expiresAt: Date | null } | null> {
      const [tok] = await db.select().from(apiTokens).where(eq(apiTokens.id, tokenId)).limit(1);
      return tok ? { role: tok.role as 'admin' | 'user', expiresAt: tok.expiresAt } : null;
    },
  };
}
