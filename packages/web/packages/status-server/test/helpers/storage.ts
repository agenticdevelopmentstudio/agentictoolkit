import type { Db } from '../../src/libsql/client';
import { createLibsqlStorage } from '../../src/libsql';
import { createDefaultAuthGate } from '../../src/auth';
import { testConfig } from './config';

/** The full `AppDeps` shape a test needs to call `createApp`: the raw `db` (for
 *  suites that still assert against it directly or exercise routes that keep a
 *  `db` parameter alongside `storage`), the libsql-backed `Storage`, the default
 *  `AuthGate` bound to that same storage, and the live-env test config.
 *  `createApp(testDeps(db))` is the one idiom every test should reach for instead
 *  of hand-assembling `{ db, storage, auth, config }`. */
export function testDeps(db: Db) {
  const storage = createLibsqlStorage(db);
  const config = testConfig();
  return { db, storage, auth: createDefaultAuthGate(storage, config), config };
}
