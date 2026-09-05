import { desc, eq } from 'drizzle-orm';
import { createHash, randomBytes } from 'node:crypto';
import type { Db } from '../libsql/client';
import { apiTokens } from '../libsql/schema';

// ---------------------------------------------------------------------------
// Opaque API bearer tokens (`sts_<64 hex>`) — the non-cookie auth channel for
// CLI / MCP / machine callers. Mirrors the hub ApiTokenStore mechanics
// (sha256 / reveal-once / bump-last-used) but WITHOUT hub's scope / application
// / persona machinery — a status token carries only a role + expiry. The raw
// value is shown to the caller exactly once, at mint; only its sha256 hex is
// persisted (token_hash), so a DB leak can't reconstruct a live token. `prefix`
// keeps the first chars for human-readable listing. DB-only (no Hono/cookie
// concerns), so the routes, the requireAuth seam, and tests share one store.
// ---------------------------------------------------------------------------

/** Every raw status token starts with this; the bearer seam only attempts a
 *  token lookup when the Authorization bearer begins with it (so the inert
 *  cookie-as-bearer the BFF forwards never pays a dead lookup). */
export const TOKEN_PREFIX = 'sts_';
/** How many leading chars of the raw value are stored as the display prefix. */
export const PREFIX_LEN = 12; // 'sts_' + 8 hex

/** The token principal recorded on the context (never the hash or raw value). */
export interface TokenPrincipal {
  id: string;
  name: string;
  role: 'admin' | 'user';
  expiresAt: Date | null;
}

/** Token metadata for listing — never the hash or the raw secret. */
export interface ApiTokenMeta {
  id: string;
  name: string;
  role: 'admin' | 'user';
  kind: 'minted' | 'device';
  prefix: string;
  createdBy: string;
  createdAt: Date;
  lastUsedAt: Date | null;
  expiresAt: Date | null;
  revokedAt: Date | null;
}

function sha256Hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

function generateOpaqueToken(): string {
  return randomBytes(32).toString('hex');
}

function toMeta(row: typeof apiTokens.$inferSelect): ApiTokenMeta {
  return {
    id: row.id,
    name: row.name,
    role: row.role,
    kind: row.kind,
    prefix: row.prefix,
    createdBy: row.createdBy,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    expiresAt: row.expiresAt,
    revokedAt: row.revokedAt,
  };
}

/**
 * Mint a token. Returns its metadata plus the raw value, which is shown to the
 * caller EXACTLY ONCE here — it is never recoverable afterwards (only the hash
 * is stored). `createdBy` is the session user who minted it.
 */
export async function mintApiToken(
  db: Db,
  input: {
    name: string;
    role: 'admin' | 'user';
    kind?: 'minted' | 'device';
    createdBy: string;
    expiresAt?: Date | null;
  },
): Promise<{ meta: ApiTokenMeta; raw: string }> {
  const raw = TOKEN_PREFIX + generateOpaqueToken();
  const [row] = await db
    .insert(apiTokens)
    .values({
      name: input.name,
      role: input.role,
      kind: input.kind ?? 'minted',
      prefix: raw.slice(0, PREFIX_LEN),
      tokenHash: sha256Hex(raw),
      createdBy: input.createdBy,
      expiresAt: input.expiresAt ?? null,
    })
    .returning();
  return { meta: toMeta(row), raw };
}

/**
 * Validate a raw bearer token → its principal, or null for an
 * unknown / revoked / expired token. Bumps last_used_at on success. The expiry
 * and revocation checks run in JS (Date math) — the timestamps are stored as
 * unix-seconds, so there's no format ambiguity to push into SQL.
 */
export async function validateApiToken(db: Db, raw: string): Promise<TokenPrincipal | null> {
  if (!raw.startsWith(TOKEN_PREFIX)) return null;
  const hash = sha256Hex(raw);
  const [row] = await db.select().from(apiTokens).where(eq(apiTokens.tokenHash, hash)).limit(1);
  if (!row) return null;
  if (row.revokedAt) return null;
  if (row.expiresAt && row.expiresAt.getTime() <= Date.now()) return null;
  await db.update(apiTokens).set({ lastUsedAt: new Date() }).where(eq(apiTokens.id, row.id));
  return { id: row.id, name: row.name, role: row.role, expiresAt: row.expiresAt };
}

/** List every token's metadata, newest first. NEVER returns a hash or raw value. */
export async function listApiTokens(db: Db): Promise<ApiTokenMeta[]> {
  const rows = await db.select().from(apiTokens).orderBy(desc(apiTokens.createdAt));
  return rows.map(toMeta);
}

/** Soft-revoke a token by id (sets revoked_at). Returns false when no such token
 *  exists — an already-revoked token still exists, so re-revoking it is idempotent
 *  (returns true), and only a genuinely unknown id yields the 404. */
export async function revokeApiToken(db: Db, id: string): Promise<boolean> {
  const rows = await db
    .update(apiTokens)
    .set({ revokedAt: new Date() })
    .where(eq(apiTokens.id, id))
    .returning({ id: apiTokens.id });
  return rows.length > 0;
}

/** Hard-delete a token row by id — leaves no litter. For a just-minted token
 *  that never got disclosed (e.g. a device-approval race loss undoing its
 *  mint), a soft revoke would still leave a dead row behind; this removes it
 *  outright. Returns false when no such token exists. */
export async function deleteApiToken(db: Db, id: string): Promise<boolean> {
  const rows = await db.delete(apiTokens).where(eq(apiTokens.id, id)).returning({ id: apiTokens.id });
  return rows.length > 0;
}
