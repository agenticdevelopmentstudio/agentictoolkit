import type { Db } from '../../src/libsql/client';
import { createLibsqlStorage } from '../../src/libsql';
import { testConfig } from './config';

/** The full `AppDeps` shape a test needs to call `createApp`: the raw `db` (for
 *  suites that still assert against it directly or exercise routes that keep a
 *  `db` parameter alongside `storage`), the libsql-backed `Storage`, and the
 *  live-env test config. `createApp(testDeps(db))` is the one idiom every test
 *  should reach for instead of hand-assembling `{ db, config }`. */
export function testDeps(db: Db) {
  return { db, storage: createLibsqlStorage(db), config: testConfig() };
}
