---
id: ea580796-8b16-4832-b11d-ad3cae991ecd
title: Database
domain: agentictoolkit://cookbook/data/storage/database
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Deadline-bounded SQLite connection pool (one writer, many readers, runaway-query
  ejection, lane metrics) plus the app's shared storage-directory naming.
platforms:
- swift
- macos
- ios
tags:
- database
- sqlite
- persistence
depends-on: []
related:
- agentictoolkit://cookbook/data/sync/sync-engine
- agentictoolkit://cookbook/data/sync/offline-sync-client
- agentictoolkit://cookbook/adh/hub/content/markdown-store
- agentictoolkit://cookbook/workspace/projects/project-database
references:
- packages/apple/AgenticToolkit/Database/BoundedDatabase.swift
- packages/apple/AgenticToolkit/Database/AppStorageLocation.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitDatabaseTests/BoundedDatabaseTests.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitDatabaseTests/AppStorageLocationTests.swift
approved-by: ''
approved-date: ''
---

# Database

## Overview

This module is the storage floor the sync stack and the app's other stores
sit on. It has two parts:

- The bounded database wraps an underlying multi-reader, single-writer
  database connection pool (or a single shared connection for a private
  in-memory database) with two guarantees so a runaway query can never
  wedge the process: a **bulkhead** (one writer plus N readers, using
  write-ahead logging, so reads never queue behind the writer) and
  **ejection** (every read/write carries a monotonic deadline; a low-level
  statement-abort mechanism aborts any statement that passes it, surfaced
  as a deadline-exceeded error). It keeps per-lane latency and eviction
  counters exposed as a metrics snapshot, and it is reentrant, so a code
  base can keep one read/write chokepoint instead of threading a raw
  connection handle everywhere.
- The storage-location helper derives where an app keeps its files — a
  dotfolder in the home directory — from the app's declared display name,
  reduced to characters a path can hold.

Consumers include the sync store (see
[Offline Sync Client](agentictoolkit://cookbook/data/sync/offline-sync-client)),
the markdown store (see [Markdown Core](agentictoolkit://cookbook/adh/hub/content/markdown-store)),
and the project database (see
[Project Database](agentictoolkit://cookbook/workspace/projects/project-database)),
which names its file inside the storage-location helper's directory.

## Behavioral Requirements

### Storage Location

- **fallback-token**: The fallback token MUST be the string `"AgenticToolkit"`.
- **token-filter**: The token-deriving operation MUST return the display name with every character that is not a letter, mark, or number removed, with no substitute character inserted.
- **token-order**: The token-deriving operation MUST keep the surviving characters in their original order and original case.
- **token-empty-fallback**: The token-deriving operation MUST return the fallback token when no character survives the filter, including for an empty input.
- **token-non-ascii**: The token-deriving operation MUST keep non-ASCII letters and digits (the filter matches any letter, mark, or number, not just ASCII ones), so `"Café"` stays `"Café"`.
- **display-name-source**: The display-name reader MUST read the app's declared display name from platform bundle metadata, resolved through the platform's own localization mechanism when the app localizes that value.
- **display-name-fallback**: The display-name reader MUST return the fallback token when the platform's declared display name is absent, is not a string, or is the empty string; absent and empty are the same answer.
- **display-name-unfiltered**: The display-name reader MUST return the name unfiltered ("spaces and all"); filtering happens only in the token-deriving operation.
- **running-token**: The default token MUST equal the token-deriving operation applied to the display name.
- **directory-shape**: The storage-directory operation MUST return the given home directory with one path component appended: `"."` followed by the token lowercased.
- **directory-case-fold**: The storage-directory operation MUST return the same location for two tokens that differ only in letter case.
- **directory-default-token**: The storage-directory operation MUST default its token argument to the default token.
- **directory-no-io**: The storage-directory operation MUST NOT touch the filesystem; it neither creates nor checks the directory.
- **shared-directory-distinct-files**: Each store MUST pick its own filename inside the shared directory and MUST NOT name that file after the token (naming it after its own contents instead); two stores MUST NOT share a file.

### Bounded Database: Construction

- **init-signature**: Constructing a bounded database MUST take a file path, a reader count (default `3`), a read deadline (default 10 seconds), a write deadline (default 60 seconds), a busy timeout in seconds (default `5`), and an optional prepare hook — a function that receives the raw connection and may raise (default none).
- **init-throws**: Construction MUST raise whatever the underlying database library raises while opening the database; it defines no error of its own for construction.
- **reader-count**: Construction MUST pass the reader count unchanged as the underlying database library's reader-count setting; this source does not validate it, and the behavior for values below 1 is owned by that library.
- **busy-mode**: Construction MUST configure every connection to wait up to the busy timeout, in seconds, on a locked database before failing.
- **temp-store-memory**: Every connection MUST apply a temp-store-in-memory setting at open, before the caller's prepare hook runs.
- **prepare-order**: The caller's prepare hook MUST run on every connection at open, after the temp-store setting and before the ejection mechanism is installed.
- **prepare-failure**: An error raised by the prepare hook MUST propagate out of the connection open (out of construction for the writer, out of the first read that opens a new reader).
- **ejection-installed**: Every connection MUST have the ejection mechanism installed at open without the caller asking for it.
- **file-backed-pool**: For any path other than exactly `":memory:"`, construction MUST open a write-ahead-logged, pooled connection at that path, giving one writer connection and up to the configured reader count of reader connections.
- **in-memory-queue**: For a path of exactly `":memory:"`, construction MUST open a single shared connection, so reads and writes share one connection; ejection and metrics MUST still apply.
- **writer-exposed**: The bounded database MUST expose the underlying writer connection object for direct access to the underlying database library; access through it bypasses deadlines and metrics.
- **no-directory-creation**: Construction MUST NOT create the parent directory of the path; a missing directory surfaces as the underlying database library's open error.

### Bounded Database: Operations

- **write-transaction**: The write operation MUST run its body on the writer connection inside a transaction and return its result; a failure from the body MUST roll the transaction back and propagate.
- **read-reader**: The read operation MUST run its body on a reader connection and return its result; a reader MUST see every write committed before it started.
- **read-concurrency**: Top-level reads on a file-backed database MUST NOT wait for the writer; up to the configured reader count of them MAY run in parallel.
- **write-serialised**: Top-level writes MUST be serialised on the single writer connection.
- **write-no-transaction**: The transaction-free write operation MUST run its body on the writer connection without opening a transaction, for bodies that issue their own begin/commit or run statements that cannot sit inside one (such as attaching another database file or reclaiming space).
- **open-transaction-rollback**: When a top-level transaction-free write's body returns or fails with a transaction still open, the database MUST roll that transaction back after the deadline is disarmed and before the connection is returned to the pool.
- **rollback-failure**: NEEDS REVIEW: Not implemented in source. The safety-net rollback is issued in a way that discards its own failure, so if it fails the error is lost and the writer connection returns to the pool still inside a transaction with no signal to the caller or to the metrics; evidence needed is whether a failed rollback should raise, log, or count as an eviction.
- **default-deadlines**: A top-level read with no explicit deadline MUST use the configured read deadline; a top-level write or transaction-free write with no explicit deadline MUST use the configured write deadline.
- **explicit-deadline**: An explicit deadline on a top-level call MUST replace the default for that call only.
- **synchronous-calls**: Every operation MUST be synchronous: it blocks the calling thread until its body finishes and returns the value or raises.

### Bounded Database: Ejection

- **deadline-clock**: The deadline MUST be measured on a monotonic clock, so a wall-clock step backward or a sleep/wake cannot stop ejection.
- **deadline-armed-on-connection**: The deadline MUST be armed after the connection is acquired and disarmed before any cleanup, so time spent waiting for the writer or a reader slot does not count against it and cleanup cannot itself be ejected.
- **non-positive-deadline**: A zero or negative deadline MUST eject at the first progress check instead of trapping.
- **progress-interval**: The ejection check MUST run every 1000 low-level execution steps on the statement's own thread and MUST abort the statement once the current monotonic time is at or past the armed deadline.
- **no-deadline-no-abort**: The ejection check MUST allow the statement to continue when no deadline is armed on the current thread, so statements run through direct writer access are never ejected.
- **eviction-error**: A top-level call whose statement is aborted by the deadline MUST raise the deadline-exceeded error, carrying a lane name of `"read"` for a read and `"write"` for a write or transaction-free write, and the elapsed milliseconds since the call began.
- **eviction-replaces-error**: The underlying low-level interruption error from an ejected statement MUST be replaced by the deadline-exceeded error; other errors from the body MUST propagate unchanged.
- **swallowed-eviction**: When the body catches the interruption itself and returns normally, the call MUST return that value and record a completion, not an eviction.
- **error-type**: The deadline-exceeded error MUST be a single, comparable value carrying a lane name (`"read"` or `"write"`) and elapsed milliseconds.

### Bounded Database: Reentrancy

- **reentrant-inline**: A read, write, or transaction-free write called on a thread already inside one MUST run its body inline on the enclosing operation's connection instead of re-entering the pool.
- **read-your-writes**: A read nested inside a write MUST see the enclosing write's uncommitted changes.
- **nested-no-transaction**: A nested write MUST NOT open its own transaction or savepoint; it runs inside whatever the enclosing operation has open.
- **nested-deadline-inherited**: A nested call MUST be bounded by the enclosing operation's armed deadline; its own deadline argument MUST be ignored.
- **nested-eviction-error**: An ejection inside a nested call MUST raise the deadline-exceeded error with the nested call's lane and an elapsed value of `0`; the enclosing top-level call then records one eviction on its own lane and re-raises that same error.
- **nested-not-metered**: A nested call MUST NOT change the in-flight, completed, or evicted counters; it is counted by its enclosing operation.
- **is-reentrant**: The reentrancy indicator MUST be true exactly when the calling thread is inside a read, write, or transaction-free write, so a consumer can translate errors only at the outermost boundary.
- **cross-instance-reentrancy**: NEEDS REVIEW: Not implemented in source. The reentrancy indicator's documentation says "on this database," but the current-connection slot is a single per-thread value shared by every bounded database instance, so a call on database B made inside an operation on database A runs B's body inline on A's connection and B's reentrancy indicator reports `true`; evidence needed is whether cross-instance nesting must be rejected, routed to B's own pool, or documented as unsupported.

### Bounded Database: Metrics

- **in-flight-accounting**: Each top-level call MUST increment its lane's in-flight counter before acquiring a connection and decrement it when the call ends, whether it returns or raises.
- **completion-record**: A top-level call that returns MUST increment its lane's completed counter and append its duration to the lane's window.
- **eviction-record**: A top-level call that raises the deadline-exceeded error MUST increment its lane's evicted counter and MUST NOT add its duration to the window.
- **other-errors-unrecorded**: A top-level call that raises any other error MUST NOT change the completed counter, the evicted counter, or the window.
- **duration-includes-wait**: The recorded duration MUST run from before connection acquisition to the end of the call, so it includes queueing for the writer or a reader slot.
- **percentile-window**: Each lane MUST compute its 50th- and 99th-percentile durations over at most the 128 most recent completed durations, choosing the sorted element at index `round((count - 1) * q)`, in milliseconds.
- **percentile-empty**: A lane with no completed durations MUST report both percentile values as `0`.
- **stats-shape**: The metrics snapshot MUST hold exactly two lane records in the order `"write"`, then `"read"`, each carrying a lane name, in-flight count, completed count, evicted count, and 50th-/99th-percentile durations.
- **stats-consistency**: The metrics snapshot MUST read both lanes under one lock acquisition, so the snapshot is internally consistent.
- **stats-sendable**: The metrics snapshot and its lane records MUST be plain, comparable data values, safe to pass across threads, with a straightforward public initializer.

### Bounded Database: Concurrency

- **sendable-class**: The bounded database MUST be safe to call concurrently from multiple threads and tasks, relying on the underlying database library's own thread safety for connections, a lock around the metrics, and per-thread state for the current operation's deadline and connection.
- **per-thread-state**: The armed deadline and the current connection MUST be stored per thread, so operations on different threads never observe each other's deadline or connection.

## Appearance

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## States

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## Accessibility

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sed-001 | token-filter | the display name `"Coffee Grinder"` | `"CoffeeGrinder"` |
| sed-002 | token-order | the display name `"Percolator"` | `"Percolator"` |
| sed-003 | token-filter | the display name `"Coffee/Grinder 2.0"` | `"CoffeeGrinder20"` |
| sed-004 | token-empty-fallback, fallback-token | an input of only spaces, and separately an empty string | `"AgenticToolkit"` in both cases |
| sed-005 | token-non-ascii | the display name `"Café"` | `"Café"` |
| sed-006 | directory-shape | home directory `/tmp/home`, token `"CoffeeGrinder"` | path `/tmp/home/.coffeegrinder` |
| sed-007 | directory-case-fold | tokens `"COFFEEgrinder"` and `"CoffeeGrinder"` under `/tmp/home` | identical paths |
| sed-008 | directory-no-io | the storage-directory operation for a home with no such dotfolder | a location is returned; the directory still does not exist afterward |
| sed-009 | display-name-fallback | no declared display name available | display name and token both resolve to `"AgenticToolkit"` |
| sed-010 | write-transaction, read-reader, file-backed-pool | a file-backed database configured with 2 readers; a write creates a table and inserts the value `42`; then a top-level read selects it back | `42` |
| sed-011 | read-your-writes, reentrant-inline | inside one write: create a table, insert the value `7`, then a nested read selects it back | the nested read returns `7` before the write commits |
| sed-012 | eviction-error, progress-interval | a table of 1500 rows; a read with a 200ms deadline runs a triple self-join count | raises the deadline-exceeded error for lane `"read"` in under 3 seconds |
| sed-013 | in-memory-queue | an in-memory database (`":memory:"`); a write creates a table and inserts the value `5`; then a read | `5` |
| sed-014 | completion-record, in-flight-accounting, stats-shape | one write then one read, both returning normally | the write lane's and read lane's completed counts are both greater than `0`; the read lane's evicted count is `0`; both lanes' in-flight counts are `0` |
| sed-015 | open-transaction-rollback, swallowed-eviction | a transaction-free write that begins a transaction, creates a table, then runs a runaway select whose interruption is caught inside the body | the call does not raise; a following write creating another table succeeds |
| sed-016 | eviction-record, percentile-window | running sed-012, then reading the metrics snapshot | the read lane's evicted count is `1`; the read lane's completed count and 50th-percentile duration are unchanged by the ejected call |
| sed-017 | non-positive-deadline | a read with a deadline of zero, on a statement that needs more than 1000 low-level execution steps | raises the deadline-exceeded error for lane `"read"`; no crash |
| sed-018 | nested-deadline-inherited, nested-eviction-error | a write with a 200ms deadline whose body runs a nested read with a 60-second deadline on the runaway join | raises the deadline-exceeded error for lane `"read"` with an elapsed value of `0`, about 200ms in; the write lane's evicted count increments by `1`, the read lane is unchanged |
| sed-019 | default-deadlines | a bounded database configured with a 100ms read deadline; a read with no explicit deadline on the runaway join | raises the deadline-exceeded error for lane `"read"` |
| sed-020 | is-reentrant | reading the reentrancy indicator outside any operation, then inside a write's body | `false`, then `true` |
| sed-021 | other-errors-unrecorded | a read whose body raises a custom error | the custom error propagates; the read lane's completed and evicted counts are unchanged; its in-flight count is `0` |
| sed-022 | percentile-empty | a freshly opened database, reading the metrics snapshot | both lanes report a completed count of `0` and both percentile durations of `0`; lane order is `["write", "read"]` |
| sed-023 | write-transaction | a write whose body inserts a row then raises | the error propagates; a later read does not see the row |

## Edge Cases

- **Empty display name**: The token-deriving operation applied to an empty string, or to a name made only of spaces or punctuation, MUST return `"AgenticToolkit"`; a missing or empty declared display name MUST make the display-name reader return `"AgenticToolkit"`.
- **Path separators in the name**: Path-separator characters, periods, and spaces MUST be dropped by the token-deriving operation, so the result can never escape the home directory or add a nested path component.
- **Localized bundle name**: When an app localizes its declared display name, the display-name reader and the token-deriving operation MUST follow the active localization, so the storage directory can differ between locales (see Design Decisions).
- **Non-ASCII names**: Letters, combining marks, and digits outside ASCII MUST survive the token-deriving operation; the directory then carries non-ASCII characters, lowercased by a locale-independent lowercasing operation.
- **Missing parent directory**: Constructing a bounded database on a path whose directory does not exist MUST raise the underlying database library's open error; neither component creates the directory.
- **Near-miss in-memory paths**: Only the exact string `":memory:"` MUST select the single-shared-connection mode; any other spelling (such as a file URI) MUST go to the pooled, file-backed mode.
- **Reader count below 1**: The reader count is passed to the underlying database library unvalidated; that library owns the outcome.
- **Zero or negative deadline**: MUST eject at the first progress check rather than trap.
- **Statement that never reaches a progress check**: Ejection MUST only happen at a 1000-step boundary, so time blocked outside actual statement execution (for example waiting on a lock, bounded instead by the busy timeout) is not interrupted by the deadline.
- **Locked database**: A write MUST wait up to the busy timeout for the lock, then fail with the underlying database library's busy error, which propagates unchanged and is not counted in the metrics.
- **Body swallows the ejection**: The call MUST return the body's value and count as a completion; for a transaction-free write, any transaction left open MUST be rolled back before the connection is reused (sed-015).
- **Failed safety-net rollback**: Covered by the open question on rollback-failure.
- **Write nested inside a read**: A write called inside a top-level read MUST run inline on the reader connection; this source adds no check, so the write statement fails with whatever error the underlying database library raises for a read-only connection, and that error propagates.
- **Nested op on a different instance**: Covered by the open question on cross-instance-reentrancy.
- **Nested ejection details**: The raised error MUST carry the nested call's lane and an elapsed value of `0`, even though the enclosing operation's lane records the eviction.
- **Concurrent callers**: Top-level reads on different threads MAY run in parallel up to the configured reader count; top-level writes MUST queue on the single writer; the metrics snapshot MAY be read from any thread.
- **Cancellation**: There is no cancellation interface; an external cancellation signal does not interrupt a running call, and the deadline is the only way a statement is stopped.
- **Offline or network loss**: Not applicable; the component performs only local file I/O.
- **Direct writer access**: Statements run through direct writer access MUST NOT be ejected or metered, because no deadline is armed on that thread.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | string | required | Database file path, or `":memory:"` for a private in-memory database using a single shared connection. |
| `readers` | integer | `3` | Size of the read connection pool. |
| `readDeadline` | duration | 10 seconds | Default ejection ceiling for a top-level read. |
| `writeDeadline` | duration | 60 seconds | Default ejection ceiling for a top-level write or transaction-free write. |
| `busyTimeout` | duration (seconds) | `5` | Seconds to wait on a locked database before failing. |
| `prepare` | optional hook function | none | Runs on every connection at open, after the temp-store setting and before the ejection mechanism is installed; for app-specific setup. |
| `deadline` (per call) | optional duration | none (use the lane default) | Overrides the deadline for one top-level call; ignored on nested calls. |
| Declared display name (platform bundle metadata) | string | `"AgenticToolkit"` when absent or empty | Source of the display name and token. |
| `home` (storage-directory operation) | location | required | Directory under which the dotfolder is placed. |
| `token` (storage-directory operation) | string | the default token | Name folded to lowercase for the dotfolder. |
| Progress-check interval | constant | 1000 execution steps | Not configurable. |
| Percentile window | constant | 128 durations per lane | Not configurable. |

## Deep Linking

Not applicable: neither component handles URLs or routes; the only location value is the filesystem location the storage-directory operation returns.

## Localization

The storage-location helper contains no user-facing string of its own; the fallback token (`"AgenticToolkit"`) is a hardcoded, unlocalized identifier, and the display-name reader returns the platform's own resolution of the declared display name, which is the localized value when the app localizes that value. Consumers interpolate the display name into sentences the user reads.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| Declared display name (platform bundle metadata) | the app's declared name, or `AgenticToolkit` when absent | Returned by the display-name reader; also the input to the token-deriving operation and therefore to the storage directory name. |

## Accessibility Options

Not applicable: this module has no visual surface, so Reduce Motion, Increase Contrast and Differentiate Without Color have nothing to act on.

## Feature Flags

Not applicable: neither component reads a flag; every behavior is fixed or set through construction parameters.

## Analytics

Not applicable: neither component emits events; the metrics snapshot is an in-process snapshot the caller reads, and nothing leaves the process.

## Privacy

- **Data collected**: None by this module; it stores whatever rows its caller writes.
- **Storage**: A plain, unencrypted SQLite database file (plus its companion write-ahead-log and shared-memory files) at the caller's configured path, typically inside a per-app dotfolder in the home directory; an in-memory database is never written to disk.
- **Transmission**: None; the module performs no network I/O.
- **Retention**: Data persists until the caller deletes it or the file; the module deletes nothing.

## Logging

Not applicable: neither component performs its own logging; ejections surface as raised deadline-exceeded errors and as the evicted counters in the metrics snapshot.

## Platform Notes

- **SwiftUI**: Source platform (`Database/BoundedDatabase.swift`, `Database/AppStorageLocation.swift`, module `AgenticToolkitDatabase`). It imports `Foundation`, `SQLite3` (for `sqlite3_progress_handler`) and GRDB; the per-op deadline and current connection live in `Thread.current.threadDictionary`, which works because GRDB runs each sync op on one thread; the handler is a capture-free `@convention(c)` closure; `DispatchTime` supplies the monotonic clock and `NSLock` guards the metrics. A SwiftUI app owns one instance per database file and should call it off the main actor, since every call blocks.
- **Compose**: Start from Android's `SQLiteDatabase` with `enableWriteAheadLogging()` or Room with `JournalMode.WRITE_AHEAD_LOGGING`, which already gives one writer plus a reader pool. Android exposes no progress handler, so ejection maps to `CancellationSignal` passed to `rawQuery`/`query` and cancelled from a `withTimeout` coroutine; the thread-local reentrancy slot becomes a `ThreadLocal<SupportSQLiteDatabase?>` or, in coroutines, a `CoroutineContext` element (Room's `withTransaction` already does this). Metrics use `AtomicInteger` or a `Mutex`. The storage folder is `Context.filesDir` rather than a home dotfolder, so `AppStorageLocation` reduces to the token filter.
- **React/Web**: The closest equivalent is IndexedDB or SQLite-WASM (`@sqlite.org/sqlite-wasm` with OPFS) in a Web Worker; SQLite-WASM exposes `sqlite3_progress_handler`, so ejection ports directly, with `performance.now()` as the monotonic clock. Single-threaded JS has no thread-locals, so reentrancy needs an explicit "current connection" passed down or an `AsyncLocalStorage`-style context in Node (`better-sqlite3` offers a synchronous API and `db.function`-level hooks but no progress handler). The home dotfolder applies only to Node (`os.homedir()`).
- **AppKit / UIKit**: The same Swift sources apply unchanged. On iOS the home directory is the app sandbox container, so a caller passes `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` as `home` if a hidden dotfolder at the container root is not wanted; `Bundle.main` supplies `CFBundleName` in both.
- **WinUI 3**: Use `Microsoft.Data.Sqlite` with `PRAGMA journal_mode=WAL`, one `SqliteConnection` guarded by a `SemaphoreSlim(1, 1)` for writes and a small pool of read-only connections (`Mode=ReadOnly` in the connection string) for reads. `Microsoft.Data.Sqlite` does not expose `sqlite3_progress_handler`; eject instead with `SqliteCommand.Cancel()` fired from a `CancellationTokenSource.CancelAfter(deadline)` registration, or call the raw handler through `SQLitePCL.raw.sqlite3_progress_handler`. Measure with `Stopwatch` (monotonic). Reentrancy maps to an `AsyncLocal<SqliteConnection?>`, which flows across `await` unlike the source's thread-local, so nested calls stay correct in `async` code. Translate `SqliteException` with `SqliteErrorCode == 9` (`SQLITE_INTERRUPT`) into a `DeadlineExceededException(lane, elapsedMs)`. Busy waiting is `DefaultTimeout` / `PRAGMA busy_timeout`. Expose `stats` as an immutable record, or as an `INotifyPropertyChanged` view model marshalled through `DispatcherQueue.TryEnqueue` if a UI shows it. The storage folder is `Windows.Storage.ApplicationData.Current.LocalFolder` for packaged apps or `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)` plus the dotfolder for unpackaged ones, with the name from `Package.Current.DisplayName`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Database/` |

## Design Decisions

### Deadline on the monotonic clock

**Decision**: The deadline is an uptime-nanosecond reading from `DispatchTime`, not wall-clock time.

**Rationale**: The `installEjectionHandler` comment: an NTP step or sleep/wake that moves the wall clock backward must not stop ejection, which "would re-enable the wedge this exists to prevent".

**Approved**: pending

### One armed deadline per thread

**Decision**: Nested calls run inline and inherit the enclosing op's deadline; their own `deadline:` is ignored and they are not metered separately.

**Rationale**: Re-entering GRDB's serial writer from inside a write would deadlock, and inline execution keeps a single `read`/`write` chokepoint without threading `Database` everywhere; the handler reads one thread-local deadline.

**Approved**: pending

### Rollback safety net for self-managed transactions

**Decision**: After a top-level `writeWithoutTransaction`, any transaction still open is rolled back with the deadline already disarmed.

**Rationale**: Interrupting a SELECT while a write is pending leaves the transaction open; if the body swallows the error, the pooled writer would come back mid-transaction and every later write would fail "cannot start a transaction within a transaction" (the scenario in `testSwallowedEjectionInWriteWithoutTransactionDoesNotPoisonPool`).

**Approved**: pending

### Serial queue for in-memory databases

**Decision**: `":memory:"` opens a `DatabaseQueue` rather than a `DatabasePool`.

**Rationale**: A pool needs a real WAL file, and in-memory databases are private per connection, so a reader connection would see an empty database.

**Approved**: pending

### Temp store in memory

**Decision**: Every connection runs `PRAGMA temp_store=MEMORY`.

**Rationale**: Recursive CTEs and ORDER BY spills then never need a temp file that a read-only connection could fail to create.

**Approved**: pending

### Drop, do not substitute, in the token

**Decision**: `token(for:)` removes non-alphanumerics instead of replacing them with `-` or `_`.

**Rationale**: A separator "would only move the problem" — `.coffee-grinder` versus `.coffee_grinder` is a guess every later lookup must repeat correctly.

**Approved**: pending

### Case-folded directory, content-named files

**Decision**: The dotfolder is the lowercased token, and stores name their files for their contents (`Markdown.db`, `Projects.db`), never for the app.

**Rationale**: Capitalization of a display name is cosmetic; renaming "Coffee grinder" to "Coffee Grinder" must not strand the store, and there is then no second spelling of the app name that could fold differently. The same reasoning does not cover a localized `CFBundleName`, which changes the token itself.

**Approved**: pending

### Absent and empty bundle name are the same

**Decision**: `displayName` treats a missing and an empty `CFBundleName` identically, returning `fallbackToken`.

**Rationale**: An empty name gives a user-facing sentence with a hole and a path component that silently collapses onto its parent; resolving it once avoids every call site having to remember.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |

The module keeps storage mechanics (pool, deadlines, metrics) and storage naming apart from every schema that uses it, and `BoundedDatabaseTests` and `AppStorageLocationTests` cover the cross-lane read, read-your-writes, ejection, in-memory, stats and poisoned-pool paths plus every token and directory rule. Every read and write carries a monotonic deadline and locked writes a busy timeout, and the reader pool keeps reads from queuing behind the writer. `stats` exposes in-flight, completed, evicted and p50/p99 per lane, so a wedge is visible. Explicit error handling is partial because the safety-net `ROLLBACK` discards its own failure, and errors other than an eviction go uncounted in `stats`. Data integrity is partial because the per-thread connection slot is shared across instances, so a call on one database nested inside an op on another runs against the wrong connection.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/storage/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from `BoundedDatabase.swift`, `AppStorageLocation.swift` and their tests |
