import type { Db } from '../../src/libsql/client';
import { createUser, createSession, type UserRole } from '../../src/storage/auth-store';

/** Mint a user of `role` on `db` and return the Cookie header carrying its session. */
export async function sessionHeaders(db: Db, role: UserRole): Promise<{ Cookie: string }> {
  const user = await createUser(db, { email: `${role}-${Math.random().toString(36).slice(2)}@test.local`, displayName: role, role });
  const token = await createSession(db, user.id);
  return { Cookie: `status_auth=${token}` };
}
