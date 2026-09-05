import { and, asc, count, eq, sql } from "drizzle-orm";
import { randomBytes, createHash } from "node:crypto";
import type { Db } from "../client";
import { users, sessions } from "../schema";
import { toAuthUser, type AuthStore, type AuthUser, type UserRecord, type UserRole } from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `AuthStore` — the user + session store. Bodies
// moved verbatim from the pre-port `src/storage/auth-store.ts` (a `db`-closure
// factory instead of a `db` parameter on every free function). Like the config
// store, FK cascades are done in app code (libSQL over HTTP does not enforce
// ON DELETE CASCADE).
// ---------------------------------------------------------------------------

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

function toUserRecord(u: typeof users.$inferSelect): UserRecord {
  return {
    id: u.id,
    email: u.email,
    passwordHash: u.passwordHash,
    githubId: u.githubId,
    displayName: u.displayName,
    role: u.role,
    createdAt: u.createdAt,
  };
}

/** Build the `AuthStore` port over one connection. */
export function createAuthStore(db: Db): AuthStore {
  return {
    async findUserByEmail(email: string): Promise<UserRecord | undefined> {
      const [row] = await db.select().from(users).where(eq(users.email, email.toLowerCase())).limit(1);
      return row ? toUserRecord(row) : undefined;
    },

    async findUserByGithubId(githubId: string): Promise<UserRecord | undefined> {
      const [row] = await db.select().from(users).where(eq(users.githubId, githubId)).limit(1);
      return row ? toUserRecord(row) : undefined;
    },

    async getUserById(id: string): Promise<UserRecord | undefined> {
      const [row] = await db.select().from(users).where(eq(users.id, id)).limit(1);
      return row ? toUserRecord(row) : undefined;
    },

    async createUser(input): Promise<UserRecord> {
      const [row] = await db
        .insert(users)
        .values({
          email: input.email.toLowerCase(),
          displayName: input.displayName,
          role: input.role,
          passwordHash: input.passwordHash ?? null,
          githubId: input.githubId ?? null,
        })
        .returning();
      return toUserRecord(row!);
    },

    /** Link a GitHub identity onto an existing account (a password user who later
     *  signs in with GitHub) — avoids a duplicate row tripping the unique-email index. */
    async attachGithubId(userId: string, githubId: string): Promise<UserRecord | undefined> {
      const [row] = await db.update(users).set({ githubId }).where(eq(users.id, userId)).returning();
      return row ? toUserRecord(row) : undefined;
    },

    async listUsers(): Promise<AuthUser[]> {
      const rows = await db.select().from(users).orderBy(asc(users.createdAt));
      return rows.map((r) => toAuthUser(toUserRecord(r)));
    },

    // The last-admin guard lives INSIDE the write statement (not a separate count
    // read before it): SQLite serializes statements, so embedding the count check
    // in the WHERE makes "two concurrent demotes/deletes remove every admin" —
    // a permanent lockout, since only an admin can promote — structurally
    // impossible, where a read-then-write pair raced.

    /** Change a user's role; demoting the LAST admin is atomically blocked.
     *  Returns the updated user, `'blocked'` (last-admin protection), or
     *  undefined (no such user). */
    async setUserRoleGuarded(id: string, role: UserRole): Promise<AuthUser | "blocked" | undefined> {
      const [row] = await db
        .update(users)
        .set({ role })
        .where(
          and(
            eq(users.id, id),
            // Guard applies only when this write would REMOVE an admin.
            sql`(${users.role} != 'admin' or ${role} = 'admin' or (select count(*) from users where role = 'admin') > 1)`,
          ),
        )
        .returning();
      if (row) return toAuthUser(toUserRecord(row));
      const [exists] = await db.select().from(users).where(eq(users.id, id)).limit(1);
      return exists ? "blocked" : undefined;
    },

    /** Delete a user (and their sessions); deleting the LAST admin is atomically
     *  blocked. Returns true, `'blocked'`, or false (no such user). */
    async deleteUserGuarded(id: string): Promise<boolean | "blocked"> {
      const rows = await db
        .delete(users)
        .where(
          and(
            eq(users.id, id),
            sql`(${users.role} != 'admin' or (select count(*) from users where role = 'admin') > 1)`,
          ),
        )
        .returning();
      if (rows.length > 0) {
        // Cascade in app code — only AFTER the guarded delete succeeded, so a
        // blocked delete never strips the surviving admin's sessions.
        await db.delete(sessions).where(eq(sessions.userId, id));
        return true;
      }
      const [exists] = await db.select().from(users).where(eq(users.id, id)).limit(1);
      return exists ? "blocked" : false;
    },

    async countAdmins(): Promise<number> {
      const [row] = await db.select({ n: count() }).from(users).where(eq(users.role, "admin"));
      return row?.n ?? 0;
    },

    /** Mint a session: return the raw opaque cookie token; persist only its sha256. */
    async createSession(userId: string, ttlMs: number = SESSION_TTL_MS): Promise<string> {
      const token = randomBytes(32).toString("hex");
      await db.insert(sessions).values({
        userId,
        tokenHash: sha256(token),
        expiresAt: new Date(Date.now() + ttlMs),
      });
      return token;
    },

    /** Resolve a cookie token → the live user, or null (unknown/expired). Expired
     *  rows are reaped opportunistically. */
    async resolveSession(token: string | undefined): Promise<AuthUser | null> {
      if (!token) return null;
      const [s] = await db.select().from(sessions).where(eq(sessions.tokenHash, sha256(token))).limit(1);
      if (!s) return null;
      if (s.expiresAt.getTime() < Date.now()) {
        await db.delete(sessions).where(eq(sessions.id, s.id));
        return null;
      }
      const [u] = await db.select().from(users).where(eq(users.id, s.userId)).limit(1);
      return u ? toAuthUser(toUserRecord(u)) : null;
    },

    async revokeSession(token: string | undefined): Promise<void> {
      if (!token) return;
      await db.delete(sessions).where(eq(sessions.tokenHash, sha256(token)));
    },
  };
}
