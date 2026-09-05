import type { Db } from '../../src/libsql/client';
import { createLibsqlStorage } from '../../src/libsql';
import type { UserRole } from '../../src/storage/ports';

/** Mint a user of `role` on `db` and return the Cookie header carrying its session. */
export async function sessionHeaders(db: Db, role: UserRole): Promise<{ Cookie: string }> {
  const auth = createLibsqlStorage(db).auth;
  const user = await auth.createUser({ email: `${role}-${Math.random().toString(36).slice(2)}@test.local`, displayName: role, role });
  const token = await auth.createSession(user.id);
  return { Cookie: `status_auth=${token}` };
}
