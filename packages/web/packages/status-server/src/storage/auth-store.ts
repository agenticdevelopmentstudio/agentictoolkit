import { and, asc, count, eq, sql } from "drizzle-orm";
import { randomBytes, createHash } from "node:crypto";
import type { Db } from "../libsql/client";
import { users, sessions, type User } from "../libsql/schema";
import type { StatusConfig } from "../config/port";

// ---------------------------------------------------------------------------
// The user + session store. DB-only (no HTTP/cookie concerns — those live in
// src/auth/cookie.ts) so the auth routes, the requireAuth seam, and tests all
// share one store over an injected Db. Like the config store, FK cascades are
// done in app code (libSQL over HTTP does not enforce ON DELETE CASCADE).
// ---------------------------------------------------------------------------

export type UserRole = "pending" | "viewer" | "admin";

/** The request principal carried on the Hono context — never the password hash. */
export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
  role: UserRole;
}

const ROLES = new Set<UserRole>(["pending", "viewer", "admin"]);

/** Coerce the DB's text role to the union, defaulting an UNKNOWN value to the
 *  least-privileged `pending` (fail safe, not fail open) rather than casting blind. */
function asRole(role: string): UserRole {
  return ROLES.has(role as UserRole) ? (role as UserRole) : "pending";
}

/** Project a full user row down to the public principal (drops the password hash). */
/** SQLite/libSQL unique-index violation — the email/githubId already exists.
 *  The one representation of this check (routes + OAuth race recovery share it).
 *  Walks the cause chain: drizzle wraps the driver error in "Failed query: …",
 *  with the real "UNIQUE constraint failed" only on err.cause — matching the
 *  top-level message alone never fired. */
export function isUniqueViolation(err: unknown): boolean {
  for (let e: unknown = err; e instanceof Error; e = e.cause) {
    if (/UNIQUE constraint failed/i.test(e.message)) return true;
  }
  return false;
}

export function toAuthUser(u: User): AuthUser {
  return { id: u.id, email: u.email, displayName: u.displayName, role: asRole(u.role) };
}

// --- users -----------------------------------------------------------------

export async function findUserByEmail(db: Db, email: string): Promise<User | undefined> {
  const [row] = await db.select().from(users).where(eq(users.email, email.toLowerCase())).limit(1);
  return row;
}

export async function findUserByGithubId(db: Db, githubId: string): Promise<User | undefined> {
  const [row] = await db.select().from(users).where(eq(users.githubId, githubId)).limit(1);
  return row;
}

export async function getUserById(db: Db, id: string): Promise<User | undefined> {
  const [row] = await db.select().from(users).where(eq(users.id, id)).limit(1);
  return row;
}

export async function createUser(
  db: Db,
  input: { email: string; displayName: string; role: UserRole; passwordHash?: string | null; githubId?: string | null },
): Promise<User> {
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
  return row;
}

/** Link a GitHub identity onto an existing account (a password user who later
 *  signs in with GitHub) — avoids a duplicate row tripping the unique-email index. */
export async function attachGithubId(db: Db, userId: string, githubId: string): Promise<User | undefined> {
  const [row] = await db.update(users).set({ githubId }).where(eq(users.id, userId)).returning();
  return row;
}

export async function listUsers(db: Db): Promise<AuthUser[]> {
  const rows = await db.select().from(users).orderBy(asc(users.createdAt));
  return rows.map(toAuthUser);
}

// The last-admin guard lives INSIDE the write statement (not a separate count
// read before it): SQLite serializes statements, so embedding the count check
// in the WHERE makes "two concurrent demotes/deletes remove every admin" —
// a permanent lockout, since only an admin can promote — structurally
// impossible, where a read-then-write pair raced.

/** Change a user's role; demoting the LAST admin is atomically blocked.
 *  Returns the updated user, `'blocked'` (last-admin protection), or
 *  undefined (no such user). */
export async function setUserRoleGuarded(
  db: Db,
  id: string,
  role: UserRole,
): Promise<AuthUser | 'blocked' | undefined> {
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
  if (row) return toAuthUser(row);
  const exists = await getUserById(db, id);
  return exists ? 'blocked' : undefined;
}

/** Delete a user (and their sessions); deleting the LAST admin is atomically
 *  blocked. Returns true, `'blocked'`, or false (no such user). */
export async function deleteUserGuarded(db: Db, id: string): Promise<boolean | 'blocked'> {
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
  return (await getUserById(db, id)) ? 'blocked' : false;
}

export async function countAdmins(db: Db): Promise<number> {
  const [row] = await db.select({ n: count() }).from(users).where(eq(users.role, "admin"));
  return row?.n ?? 0;
}

/** Bootstrap rule: emails in ADMIN_EMAILS are admins from their first account;
 *  everyone else starts pending. */
export function roleForEmail(email: string, config: StatusConfig): UserRole {
  return config.adminEmails.includes(email.toLowerCase()) ? "admin" : "pending";
}

// --- sessions --------------------------------------------------------------

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

/** Mint a session: return the raw opaque cookie token; persist only its sha256. */
export async function createSession(db: Db, userId: string, ttlMs: number = SESSION_TTL_MS): Promise<string> {
  const token = randomBytes(32).toString("hex");
  await db.insert(sessions).values({
    userId,
    tokenHash: sha256(token),
    expiresAt: new Date(Date.now() + ttlMs),
  });
  return token;
}

/** Resolve a cookie token → the live user, or null (unknown/expired). Expired
 *  rows are reaped opportunistically. */
export async function resolveSession(db: Db, token: string | undefined): Promise<AuthUser | null> {
  if (!token) return null;
  const [s] = await db.select().from(sessions).where(eq(sessions.tokenHash, sha256(token))).limit(1);
  if (!s) return null;
  if (s.expiresAt.getTime() < Date.now()) {
    await db.delete(sessions).where(eq(sessions.id, s.id));
    return null;
  }
  const u = await getUserById(db, s.userId);
  return u ? toAuthUser(u) : null;
}

export async function revokeSession(db: Db, token: string | undefined): Promise<void> {
  if (!token) return;
  await db.delete(sessions).where(eq(sessions.tokenHash, sha256(token)));
}
