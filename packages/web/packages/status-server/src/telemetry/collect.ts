import type { Db } from "../libsql/client";
import type { Fetcher, Store } from "./ports";

// The trigger-agnostic collection use-case: pull from a Fetcher, persist to a
// Store. The scheduler cycle, a manual refresh, or a webhook all reuse this —
// none of them knows the provider or the storage backend. A failed poll
// (ok:false) is NOT persisted, so a transient provider outage can never overwrite
// good data with an empty set.
//
// The Store here takes the db handle explicitly (this backend has no db
// singleton), so collect threads `db` through to save.
export async function collect<T>(
  fetcher: Fetcher<T>,
  store: Store<T>,
  db: Db,
): Promise<{ ok: boolean; count: number }> {
  const { ok, items, complete } = await fetcher.fetch();
  if (!ok) return { ok: false, count: 0 };
  // `complete` is threaded through UNINTERPRETED. Whether a partial answer is usable is
  // the store's semantics, not the trigger's: an appending store doesn't care, a
  // reconciling one must not sweep what it never asked about.
  await store.save(db, items, { complete: complete ?? true });
  return { ok: true, count: items.length };
}
