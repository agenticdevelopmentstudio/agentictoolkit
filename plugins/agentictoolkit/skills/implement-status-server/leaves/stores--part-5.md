<!-- leaf: implement-status-server/stores--part-5 · source: status-server-stores.md -->

# Status Server Stores — continued (part 5)

**Rules** (cite as `implement-status-server/stores--part-5#<slug>`):

- `decision` MUST — make the WAL checkpoint and DB snapshot steps fail-soft (try/catch + console.error/console.warn, never a rethrow) …

## Design Decisions

- **Decision**: embed the last-admin check inside the same UPDATE/DELETE
  statement that performs the role change or deletion, instead of a
  separate `countAdmins` read followed by a conditional write.
  **Rationale**: a read-then-write split leaves a window in which two
  concurrent requests can each read "more than one admin remains" and
  then both demote/delete, leaving zero admins; folding the count into
  the statement's own WHERE clause makes the check and the write atomic
  under SQLite's single-statement execution, with no window between them.
  **Approved**: pending
- **Decision**: use `db.batch(...)` rather than `db.transaction(...)` for
  every atomic multi-statement write in `config-store.ts`.
  **Rationale**: the source comment documents that this driver's
  `transaction()` hands off the connection to a transaction-scoped handle
  and nulls its own, so the very next statement issued against the
  original handle lazily reopens a brand-new, empty `:memory:` database
  instead of continuing the one already written to — a behavior specific
  to the in-memory driver mode this backend's test suite relies on.
  `db.batch(...)` sends all statements in one round trip without that
  handle hand-off, so it is the only multi-statement primitive that stays
  correct against both a `:memory:` database and a persistent one.
  **Approved**: pending
- **Decision**: let a poll move a deployment's phase backward to
  in-flight while blocking a webhook from doing the same.
  **Rationale**: `monitor/deploy-status.ts`'s `webhookKeepsStoredSql`
  comment documents two failure modes a webhook is uniquely exposed to —
  a stale event overwriting an already-settled verdict, and a stale event
  overwriting a later in-flight phase — because webhook delivery order is
  not guaranteed. A poll has no such ordering problem: it reads the
  provider's current by-id state directly, so its result is definitionally
  current truth and applying it is always correct, including moving a
  phase backward.
  **Approved**: pending
- **Decision**: chunk every bulk write (`UPSERT_CHUNK_PROJECTS`,
  `DELETE_CHUNK_NAMES`, `PRUNE_CHUNK_ROWS`) and cap total prune work per
  call (`PRUNE_MAX_ROWS_PER_RUN`).
  **Rationale**: SQLite/libSQL bounds the number of parameters a single
  statement may bind; chunking keeps every generated statement under that
  bound regardless of input size, and capping the prune's total row
  budget per call keeps any single `runMaintenance` invocation's
  transaction small and bounded rather than proportional to however large
  the backlog has grown, deferring the remainder to the next scheduled run.
  **Approved**: pending
- **Decision**: make the WAL checkpoint and DB snapshot steps fail-soft
  (`try`/`catch` + `console.error`/`console.warn`, never a rethrow) inside
  `maintenance-store.ts`.
  **Rationale**: both are secondary, disk-housekeeping side effects
  riding along with the maintenance cycle; a failure in either MUST NOT
  prevent the rest of the cycle (the retention prune, the metrics rollup)
  from completing, and both failures are still visible operationally
  because each is logged, not silently discarded.
  **Approved**: pending
- **Decision**: recompute `config-store.ts`'s orphan set and
  `retireEndpoint`'s eligibility check as a subquery evaluated at delete
  time, rather than reading a set of ids first and deleting by that list.
  **Rationale**: a read-then-delete-by-id-list has a TOCTOU window in
  which the set changes between the read and the delete (another request
  reactivates an endpoint the reconcile is about to remove); a subquery
  re-evaluated as part of the DELETE statement itself closes that window
  because the eligibility check and the delete are the same atomic
  operation.
  **Approved**: pending
- **Decision**: make `errorsStore.save` a full reconciliation of the
  polled "currently unresolved" set — upserting what is present and
  sweeping to `resolved = true` whatever previously-open row is absent —
  instead of only ever appending or upserting-without-sweeping.
  **Rationale**: the source's own test-file comment documents the
  regression this closes: before the sweep existed, nothing in the
  codebase ever wrote `resolved = true`, so an issue that stopped being
  reported by the upstream poll stayed open in this table forever and a
  problem built on it could go red and never go green. Gating the sweep
  on `opts.complete !== false` prevents the same reconciliation from
  wrongly resolving rows past the edge of a truncated (paginated) poll.
  **Approved**: pending
- **Decision**: store only `tokenHash`/`deviceCodeHash`/`userCodeHash`
  across `auth-store.ts`, `token-store.ts`, and `device-store.ts`, with
  `deviceAuthorizations.tokenRaw` as the sole exception, held only between
  `approve` and the single successful `consumeApproved` call.
  **Rationale**: hashing every long-lived secret at rest means a database
  read (a backup, a leaked snapshot, an operator query) never yields a
  usable credential; the one raw-value exception is scoped as narrowly as
  the device-authorization flow allows — it exists only in the short
  window between a human approving a device and that device's single
  poll consuming the result, and `consumeApproved`'s delete-returning
  statement clears it as part of the same atomic read that hands it out.
  **Approved**: pending
