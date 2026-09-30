<!-- leaf: implement-sync-engine/database--part-2 · source: sync-engine-database.md -->

# Sync Engine Database — continued (part 2)

**Rules** (cite as `implement-sync-engine/database--part-2#<slug>`):

- `fallback-token` MUST
- `token-filter` MUST
- `token-order` MUST
- `token-empty-fallback` MUST
- `token-non-ascii` MUST
- `display-name-source` MUST
- `display-name-fallback` MUST
- `display-name-unfiltered` MUST
- `running-token` MUST
- `directory-shape` MUST
- `directory-case-fold` MUST
- `directory-default-token` MUST
- `directory-no-io` MUST
- `shared-directory-distinct-files` MUST
- `init-signature` MUST
- `init-throws` MUST
- `reader-count` MUST
- `busy-mode` MUST
- `temp-store-memory` MUST
- `prepare-order` MUST
- `prepare-failure` MUST
- `ejection-installed` MUST
- `file-backed-pool` MUST
- `in-memory-queue` MUST
- `writer-exposed` MUST
- `no-directory-creation` MUST
- `write-transaction` MUST
- `read-reader` MUST
- `read-concurrency` MUST
- `write-serialised` MUST
- `write-no-transaction` MUST
- `open-transaction-rollback` MUST
- `default-deadlines` MUST
- `explicit-deadline` MUST
- `synchronous-calls` MUST
- `deadline-clock` MUST
- `deadline-armed-on-connection` MUST
- `non-positive-deadline` MUST
- `progress-interval` MUST
- `no-deadline-no-abort` MUST
- `eviction-error` MUST
- `eviction-replaces-error` MUST
- `swallowed-eviction` MUST
- `error-type` MUST
- `reentrant-inline` MUST
- `read-your-writes` MUST
- `nested-no-transaction` MUST
- `nested-deadline-inherited` MUST
- `nested-eviction-error` MUST
- `nested-not-metered` MUST
- `is-reentrant` MUST

## Behavioral Requirements

### AppStorageLocation

- **fallback-token**: `AppStorageLocation.fallbackToken` MUST be the string `"AgenticToolkit"`.
- **token-filter**: `token(for:)` MUST return the display name with every Unicode scalar that is not in `CharacterSet.alphanumerics` (letters, marks and numbers) removed, with no substitute character inserted.
- **token-order**: `token(for:)` MUST keep the surviving scalars in their original order and original case.
- **token-empty-fallback**: `token(for:)` MUST return `fallbackToken` when no scalar survives the filter, including for an empty input.
- **token-non-ascii**: `token(for:)` MUST keep non-ASCII letters and digits (the filter is Unicode `alphanumerics`, not ASCII), so `"Café"` stays `"Café"`.
- **display-name-source**: `displayName` MUST read the `CFBundleName` value of `Bundle.main` through `object(forInfoDictionaryKey:)`, which returns the localized value when the bundle localizes that key.
- **display-name-fallback**: `displayName` MUST return `fallbackToken` when `CFBundleName` is absent, is not a string, or is the empty string; absent and empty are the same answer.
- **display-name-unfiltered**: `displayName` MUST return the name unfiltered ("spaces and all"); filtering happens only in `token`.
- **running-token**: The static `token` property MUST equal `token(for: displayName)`.
- **directory-shape**: `directory(inHome:token:)` MUST return `home` with one path component appended: `"."` followed by `token.lowercased()`.
- **directory-case-fold**: `directory(inHome:token:)` MUST return the same URL for two tokens that differ only in letter case.
- **directory-default-token**: `directory(inHome:token:)` MUST default `token` to `AppStorageLocation.token`.
- **directory-no-io**: `directory(inHome:token:)` MUST NOT touch the filesystem; it neither creates nor checks the directory.
- **shared-directory-distinct-files**: Each store MUST pick its own filename inside the shared directory and MUST NOT name that file after the token (the doc comment cites `Markdown.db` and `Projects.db`); two stores MUST NOT share a file.

### BoundedDatabase: construction

- **init-signature**: `BoundedDatabase.init(path:readers:readDeadline:writeDeadline:busyTimeout:prepare:)` MUST take a `String` path, an `Int` reader count (default `3`), a read deadline (default 10 seconds), a write deadline (default 60 seconds), a busy timeout in seconds (default `5`), and an optional `@Sendable (Database) throws -> Void` prepare hook (default `nil`).
- **init-throws**: `init` MUST throw whatever GRDB throws while opening the database; it defines no error of its own for construction.
- **reader-count**: `init` MUST pass `readers` unchanged as the GRDB `maximumReaderCount`; this source does not validate it, and the behavior for values below 1 is owned by GRDB.
- **busy-mode**: `init` MUST configure every connection to wait up to `busyTimeout` seconds on a locked database before failing.
- **temp-store-memory**: Every connection MUST execute `PRAGMA temp_store=MEMORY` at open, before the caller's `prepare` hook runs.
- **prepare-order**: The caller's `prepare` hook MUST run on every connection at open, after `temp_store` setup and before the ejection handler is installed.
- **prepare-failure**: An error thrown by `prepare` MUST propagate out of the connection open (out of `init` for the writer, out of the first `read` that opens a new reader).
- **ejection-installed**: Every connection MUST have the ejection progress handler installed at open without the caller asking for it.
- **file-backed-pool**: For any `path` other than exactly `":memory:"`, `init` MUST open a WAL `DatabasePool` at that path, giving one writer connection and up to `readers` reader connections.
- **in-memory-queue**: For `path == ":memory:"`, `init` MUST open a serial `DatabaseQueue`, so reads and writes share a single connection; ejection and metrics MUST still apply.
- **writer-exposed**: `writer` MUST expose the underlying GRDB `DatabaseWriter` (`DatabasePool` or `DatabaseQueue`) for direct GRDB access; access through it bypasses deadlines and metrics.
- **no-directory-creation**: `init` MUST NOT create the parent directory of `path`; a missing directory surfaces as the GRDB open error.

### BoundedDatabase: operations

- **write-transaction**: `write(deadline:_:)` MUST run `body` on the writer connection inside a transaction and return its result; a throw from `body` MUST roll the transaction back (GRDB `write` semantics) and propagate.
- **read-reader**: `read(deadline:_:)` MUST run `body` on a reader connection and return its result; a reader MUST see every write committed before it started.
- **read-concurrency**: Top-level reads on a file-backed database MUST NOT wait for the writer; up to `readers` of them MAY run in parallel.
- **write-serialised**: Top-level writes MUST be serialised on the single writer connection.
- **write-no-transaction**: `writeWithoutTransaction(deadline:_:)` MUST run `body` on the writer connection without opening a transaction, for bodies that issue their own `BEGIN`/`COMMIT` or run statements that cannot sit inside one (`ATTACH`, `VACUUM`).
- **open-transaction-rollback**: When a top-level `writeWithoutTransaction` body returns or throws with a transaction still open, the database MUST execute `ROLLBACK` after the deadline is disarmed and before the connection is returned to the pool.
- **rollback-failure**: NEEDS REVIEW: Not implemented in source. The safety-net `ROLLBACK` in `run` is issued with `try?`, so if it fails the error is discarded and the writer connection returns to the pool still inside a transaction with no signal to the caller or to `stats`; evidence needed is whether a failed `ROLLBACK` should throw, log, or count as an eviction.
- **default-deadlines**: A top-level `read` with `deadline: nil` MUST use `readDeadline`; a top-level `write` or `writeWithoutTransaction` with `deadline: nil` MUST use `writeDeadline`.
- **explicit-deadline**: A non-nil `deadline:` on a top-level call MUST replace the default for that call only.
- **synchronous-calls**: Every operation MUST be synchronous: it blocks the calling thread until `body` finishes and returns the value or throws.

### BoundedDatabase: ejection

- **deadline-clock**: The deadline MUST be measured on the monotonic uptime clock (`DispatchTime` uptime nanoseconds), so a wall-clock step backward or sleep/wake cannot stop ejection.
- **deadline-armed-on-connection**: The deadline MUST be armed after the connection is acquired and disarmed before any cleanup, so time spent waiting for the writer or a reader slot does not count against it and cleanup cannot itself be ejected.
- **non-positive-deadline**: A zero or negative deadline MUST eject at the first progress check instead of trapping.
- **progress-interval**: The ejection check MUST run every 1000 SQLite VM instructions on the statement's own thread and MUST abort the statement once the current monotonic time is at or past the armed deadline.
- **no-deadline-no-abort**: The progress handler MUST return "continue" when no deadline is armed on the current thread, so statements run through `writer` directly are never ejected.
- **eviction-error**: A top-level call whose statement is aborted by the deadline MUST throw `BoundedDatabaseError.deadlineExceeded(lane:elapsedMs:)`, with `lane` `"read"` for `read` and `"write"` for `write`/`writeWithoutTransaction`, and `elapsedMs` the milliseconds since the call began.
- **eviction-replaces-error**: The SQLite `SQLITE_INTERRUPT` error from an ejected statement MUST be replaced by `deadlineExceeded`; other errors from `body` MUST propagate unchanged.
- **swallowed-eviction**: When `body` catches the interrupt itself and returns normally, the call MUST return that value and record a completion, not an eviction.
- **error-type**: `BoundedDatabaseError` MUST be `Error`, `Sendable` and `Equatable`, with the single case `deadlineExceeded(lane: String, elapsedMs: Double)`.

### BoundedDatabase: reentrancy

- **reentrant-inline**: A `read`, `write` or `writeWithoutTransaction` called on a thread already inside one MUST run `body` inline on the enclosing op's connection instead of re-entering the pool.
- **read-your-writes**: A `read` nested inside a `write` MUST see the enclosing write's uncommitted changes.
- **nested-no-transaction**: A nested `write` MUST NOT open its own transaction or savepoint; it runs inside whatever the enclosing op has open.
- **nested-deadline-inherited**: A nested call MUST be bounded by the enclosing op's armed deadline; its own `deadline:` argument MUST be ignored.
- **nested-eviction-error**: An ejection inside a nested call MUST throw `deadlineExceeded` with the nested call's lane and `elapsedMs` of `0`; the enclosing top-level call then records one eviction on its own lane and rethrows that same error value.
- **nested-not-metered**: A nested call MUST NOT change `inFlight`, `completed` or `evicted`; it is counted by its enclosing op.
- **is-reentrant**: `isReentrant` MUST be `true` exactly when the calling thread is inside a `read`, `write` or `writeWithoutTransaction`, so a consumer can translate errors only at the outermost boundary.
- **cross-instance-reentrancy**: NEEDS REVIEW: Not implemented in source. `isReentrant`'s doc comment says "on this database", but the current-connection slot is a single per-thread key shared by every `BoundedDatabase` instance, so a call on database B made inside an op on database A runs B's body inline on A's connection and `B.isReentrant` reports `true`; evidence needed is whether cross-instance nesting must be rejected, routed to B's own pool, or documented as unsupported.

