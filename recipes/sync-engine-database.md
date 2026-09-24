---
id: ea580796-8b16-4832-b11d-ad3cae991ecd
title: Sync Engine Database
domain: agentictoolkit://recipes/sync-engine-database
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Deadline-bounded GRDB SQLite pool (one writer, N readers, runaway-query ejection,
  lane metrics) plus the app's shared storage-directory naming.
platforms:
- swift
- macos
- ios
tags:
- database
- sqlite
- grdb
- persistence
depends-on: []
related:
- agentictoolkit://recipes/sync-engine
- agentictoolkit://recipes/adh-offline-sync-client
- agentictoolkit://recipes/markdown-core
- agentictoolkit://recipes/git-client-projects-project-database
references:
- packages/apple/AgenticToolkit/Database/BoundedDatabase.swift
- packages/apple/AgenticToolkit/Database/AppStorageLocation.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitDatabaseTests/BoundedDatabaseTests.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitDatabaseTests/AppStorageLocationTests.swift
approved-by: ''
approved-date: ''
---

# Sync Engine Database

## Overview

The `AgenticToolkitDatabase` module is the storage floor the sync stack and
the app's other stores sit on. It has two parts:

- `BoundedDatabase` wraps a GRDB `DatabasePool` (or a serial `DatabaseQueue`
  for `:memory:`) with two guarantees so a runaway query can never wedge the
  process: a **bulkhead** (one writer plus N readers on WAL, so reads never
  queue behind the writer) and **ejection** (every `read`/`write` carries a
  monotonic deadline; a SQLite progress handler aborts any statement that
  passes it, surfaced as `BoundedDatabaseError.deadlineExceeded`). It keeps
  per-lane latency and eviction counters exposed as `stats`, and it is
  reentrant, so a code base can keep one `read`/`write` chokepoint instead of
  threading a `Database` handle everywhere.
- `AppStorageLocation` derives where an app keeps its files — a dotfolder in
  the home directory — from the bundle's display name, reduced to characters a
  path can hold.

Consumers include `GRDBSyncStore` (see
[ADH Offline Sync Client](agentictoolkit://recipes/adh-offline-sync-client)),
`MarkdownStore` (see [Markdown Core](agentictoolkit://recipes/markdown-core)),
and `ProjectDatabase` (see
[Project Database](agentictoolkit://recipes/git-client-projects-project-database)),
which names its file inside `AppStorageLocation.directory`.

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

### BoundedDatabase: metrics

- **in-flight-accounting**: Each top-level call MUST increment its lane's `inFlight` before acquiring a connection and decrement it when the call ends, whether it returns or throws.
- **completion-record**: A top-level call that returns MUST increment its lane's `completed` and append its duration to the lane's window.
- **eviction-record**: A top-level call that throws a `BoundedDatabaseError` MUST increment its lane's `evicted` and MUST NOT add its duration to the window.
- **other-errors-unrecorded**: A top-level call that throws any other error MUST NOT change `completed`, `evicted` or the window.
- **duration-includes-wait**: The recorded duration MUST run from before connection acquisition to the end of the call, so it includes queueing for the writer or a reader slot.
- **percentile-window**: Each lane MUST compute `p50Ms` and `p99Ms` over at most the 128 most recent completed durations, choosing the sorted element at index `round((count - 1) * q)`, in milliseconds.
- **percentile-empty**: A lane with no completed durations MUST report `p50Ms` and `p99Ms` of `0`.
- **stats-shape**: `stats` MUST return a `BoundedDatabaseStats` whose `lanes` array holds exactly two `Lane` values in the order `"write"`, then `"read"`, each carrying `lane`, `inFlight`, `completed`, `evicted`, `p50Ms` and `p99Ms`.
- **stats-consistency**: `stats` MUST read both lanes under one lock acquisition, so the snapshot is internally consistent.
- **stats-sendable**: `BoundedDatabaseStats` and `BoundedDatabaseStats.Lane` MUST be `Sendable` and `Equatable` value types with public memberwise initialisers.

### BoundedDatabase: concurrency

- **sendable-class**: `BoundedDatabase` MUST be safe to share across threads and tasks: it is declared `@unchecked Sendable`, relying on GRDB's thread-safe pool, an `NSLock` around the metrics, and per-op state kept in the executing thread's thread-local storage.
- **per-thread-state**: The armed deadline and the current connection MUST be stored per thread, so ops on different threads never observe each other's deadline or connection.

## Appearance

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## States

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## Accessibility

Not applicable — this is a database access layer and storage-path helper, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sed-001 | token-filter | `token(for: "Coffee Grinder")` | `"CoffeeGrinder"` (from `testStripsSpacesFromADisplayName`) |
| sed-002 | token-order | `token(for: "Percolator")` | `"Percolator"` (from `testLeavesASingleWordNameAlone`) |
| sed-003 | token-filter | `token(for: "Coffee/Grinder 2.0")` | `"CoffeeGrinder20"` (from `testStripsPunctuationAndPathSeparators`) |
| sed-004 | token-empty-fallback, fallback-token | `token(for: "   ")`; also `token(for: "")` | `"AgenticToolkit"` (from `testFallsBackWhenNothingUsableSurvives`) |
| sed-005 | token-non-ascii | `token(for: "Café")` | `"Café"` |
| sed-006 | directory-shape | `directory(inHome: /tmp/home, token: "CoffeeGrinder")` | path `/tmp/home/.coffeegrinder` (from `testDirectoryIsTheLowercasedTokenAsADotfolder`) |
| sed-007 | directory-case-fold | tokens `"COFFEEgrinder"` and `"CoffeeGrinder"` under `/tmp/home` | identical paths (from `testDirectoryIgnoresTheCaseOfTheToken`) |
| sed-008 | directory-no-io | `directory(inHome:)` for a home with no such dotfolder | URL returned; directory still does not exist afterwards |
| sed-009 | display-name-fallback | bundle with no `CFBundleName` (test harness) | `displayName == "AgenticToolkit"`; `token == "AgenticToolkit"` |
| sed-010 | write-transaction, read-reader, file-backed-pool | file DB, `readers: 2`; `write` creates `t(x)` and inserts `42`; then top-level `read` of `SELECT x FROM t` | `42` (from `testWriteThenReadAcrossLanes`) |
| sed-011 | read-your-writes, reentrant-inline | inside one `write`: create `t`, insert `7`, then nested `read` of `SELECT x FROM t` | nested read returns `7` before commit (from `testReadYourWritesInsideWrite`) |
| sed-012 | eviction-error, progress-interval | table `big` of 1500 rows; `read(deadline: .milliseconds(200))` of a triple self-join `count(*)` | throws `deadlineExceeded(lane: "read", _)` in under 3 s (from `testRunawayQueryIsEjectedWithinBudget`) |
| sed-013 | in-memory-queue | `path: ":memory:"`; `write` creates `t` and inserts `5`; then `read` | `5` (from `testInMemoryUsesSerialQueue`) |
| sed-014 | completion-record, in-flight-accounting, stats-shape | one `write` then one `read`, both returned | `write.completed > 0`, `read.completed > 0`, `read.evicted == 0`, both `inFlight == 0` (from `testStatsCountLanes`) |
| sed-015 | open-transaction-rollback, swallowed-eviction | `writeWithoutTransaction(deadline: 200 ms)`: `BEGIN`, `CREATE TABLE sink`, runaway SELECT, error caught inside body | call does not throw; a following `write` creating another table succeeds (from `testSwallowedEjectionInWriteWithoutTransactionDoesNotPoisonPool`) |
| sed-016 | eviction-record, percentile-window | sed-012 then read `stats` | `read.evicted == 1`; `read.completed` and `p50Ms` unchanged by the ejected call |
| sed-017 | non-positive-deadline | `read(deadline: .zero)` of a statement that needs more than 1000 VM instructions | throws `deadlineExceeded(lane: "read", _)`; no crash |
| sed-018 | nested-deadline-inherited, nested-eviction-error | `write(deadline: 200 ms)` whose body calls `read(deadline: .seconds(60))` on the runaway join | throws `deadlineExceeded(lane: "read", elapsedMs: 0)` about 200 ms in; `write.evicted` increments by 1, `read` lane unchanged |
| sed-019 | default-deadlines | `BoundedDatabase(path:, readDeadline: .milliseconds(100))`; `read` (no `deadline:`) of the runaway join | throws `deadlineExceeded(lane: "read", _)` |
| sed-020 | is-reentrant | read `isReentrant` outside any op, then inside a `write` body | `false`, then `true` |
| sed-021 | other-errors-unrecorded | `read` whose body throws a custom error | the custom error propagates; `read.completed` and `read.evicted` unchanged; `read.inFlight == 0` |
| sed-022 | percentile-empty | fresh database, read `stats` | both lanes have `completed == 0`, `p50Ms == 0`, `p99Ms == 0`; lane order `["write", "read"]` |
| sed-023 | write-transaction | `write` body inserts a row then throws | error propagates; a later `read` does not see the row |

## Edge Cases

- **Empty display name**: `token(for: "")` and a name made only of spaces or punctuation MUST return `"AgenticToolkit"`; a missing or empty `CFBundleName` MUST make `displayName` return `"AgenticToolkit"`.
- **Path separators in the name**: `/`, `.` and spaces MUST be dropped by `token(for:)`, so the result can never escape `home` or add a nested component.
- **Localized bundle name**: when an app localizes `CFBundleName`, `displayName` and `token` MUST follow the active localization, so the directory can differ between locales (see Design Decisions).
- **Non-ASCII names**: letters, combining marks and digits outside ASCII MUST survive `token(for:)`; the directory then carries non-ASCII characters, lowercased by Swift's locale-independent `lowercased()`.
- **Missing parent directory**: `BoundedDatabase.init` on a path whose directory does not exist MUST throw the GRDB open error; neither type creates the directory.
- **Near-miss in-memory paths**: only the exact string `":memory:"` MUST select the `DatabaseQueue`; any other spelling (such as a `file:` URI) MUST go to `DatabasePool` as a file path.
- **Reader count below 1**: `readers` is passed to GRDB unvalidated; GRDB owns the outcome.
- **Zero or negative deadline**: MUST eject at the first progress check rather than trap (`max(0, …)` in `armDeadline`).
- **Statement that never reaches a progress check**: ejection MUST only happen at a 1000-instruction boundary, so time blocked outside the SQLite VM (for example waiting on a lock, bounded instead by `busyTimeout`) is not interrupted by the deadline.
- **Locked database**: a write MUST wait up to `busyTimeout` seconds for the lock, then fail with the GRDB busy error, which propagates unchanged and is not counted in `stats`.
- **Body swallows the ejection**: the call MUST return the body's value and count as a completion; for `writeWithoutTransaction` any transaction left open MUST be rolled back before the connection is reused (sed-015).
- **Failed safety-net rollback**: covered by the open question on rollback-failure.
- **Write nested inside a read**: a `write` called inside a top-level `read` MUST run inline on the reader connection; this source adds no check, so the write statement fails with whatever GRDB/SQLite raises for a read-only connection, and that error propagates.
- **Nested op on a different instance**: covered by the open question on cross-instance-reentrancy.
- **Nested ejection details**: the thrown error MUST carry the nested call's lane and `elapsedMs: 0`, even though the enclosing op's lane records the eviction.
- **Concurrent callers**: top-level reads on different threads MAY run in parallel up to `readers`; top-level writes MUST queue on the single writer; `stats` MAY be read from any thread.
- **Cancellation**: there is no cancellation API; a Swift task cancellation does not interrupt a running call, and the deadline is the only way a statement is stopped.
- **Offline or network loss**: not applicable; the component performs only local file I/O.
- **Direct `writer` access**: statements run through `writer` MUST NOT be ejected or metered, because no deadline is armed on that thread.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | `String` | required | Database file path, or `":memory:"` for a private in-memory database on a serial queue. |
| `readers` | `Int` | `3` | GRDB `maximumReaderCount` — size of the read pool. |
| `readDeadline` | `Duration` | `.seconds(10)` | Default ejection ceiling for top-level `read`. |
| `writeDeadline` | `Duration` | `.seconds(60)` | Default ejection ceiling for top-level `write` and `writeWithoutTransaction`. |
| `busyTimeout` | `TimeInterval` | `5` | Seconds to wait on a locked database before failing. |
| `prepare` | `(@Sendable (Database) throws -> Void)?` | `nil` | Runs on every connection at open, after `PRAGMA temp_store=MEMORY` and before the ejection handler; for app pragmas or collations. |
| `deadline:` (per call) | `Duration?` | `nil` (use the lane default) | Overrides the deadline for one top-level call; ignored on nested calls. |
| `CFBundleName` (Info.plist) | `String` | `"AgenticToolkit"` when absent or empty | Source of `displayName` and `token`. |
| `home` (`directory(inHome:token:)`) | `URL` | required | Directory under which the dotfolder is placed. |
| `token` (`directory(inHome:token:)`) | `String` | `AppStorageLocation.token` | Name folded to lowercase for the dotfolder. |
| Progress-check interval | constant | `1000` VM instructions | Not configurable. |
| Percentile window | constant | `128` durations per lane | Not configurable. |

## Deep Linking

Not applicable: neither `BoundedDatabase.swift` nor `AppStorageLocation.swift` handles URLs or routes; the only URL is the filesystem URL `directory(inHome:token:)` returns.

## Localization

`AppStorageLocation` contains no user-facing string of its own; `fallbackToken` (`"AgenticToolkit"`) is a hardcoded, unlocalized identifier, and `displayName` returns the bundle's `CFBundleName` as `object(forInfoDictionaryKey:)` resolves it, which is the localized value when the app localizes that key. Consumers interpolate `displayName` into sentences the user reads.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `CFBundleName` (Info.plist, optionally InfoPlist.strings) | the app's bundle name, or `AgenticToolkit` when absent | Returned by `displayName`; also the input to `token` and therefore to the storage directory name. |

## Accessibility Options

Not applicable: this module has no visual surface, so Reduce Motion, Increase Contrast and Differentiate Without Color have nothing to act on.

## Feature Flags

Not applicable: neither source file reads a flag; every behavior is fixed or set through `init` parameters.

## Analytics

Not applicable: neither source file emits events; `stats` is an in-process snapshot the caller reads, and nothing leaves the process.

## Privacy

- **Data collected**: None by this module; it stores whatever rows its caller writes.
- **Storage**: A plain, unencrypted SQLite file (plus its `-wal` and `-shm` companions) at the caller's `path`, typically inside `~/.<token>`; `:memory:` databases are never written to disk.
- **Transmission**: None; the module performs no network I/O.
- **Retention**: Data persists until the caller deletes it or the file; the module deletes nothing.

## Logging

Not applicable: neither source file contains a `Logger`, `os_log` or `print` call; ejections surface as thrown `BoundedDatabaseError` values and as the `evicted` counters in `stats`.

## Platform Notes

- **SwiftUI**: Source platform (`Database/BoundedDatabase.swift`, `Database/AppStorageLocation.swift`, module `AgenticToolkitDatabase`). It imports `Foundation`, `SQLite3` (for `sqlite3_progress_handler`) and GRDB; the per-op deadline and current connection live in `Thread.current.threadDictionary`, which works because GRDB runs each sync op on one thread; the handler is a capture-free `@convention(c)` closure; `DispatchTime` supplies the monotonic clock and `NSLock` guards the metrics. A SwiftUI app owns one instance per database file and should call it off the main actor, since every call blocks.
- **Compose**: Start from Android's `SQLiteDatabase` with `enableWriteAheadLogging()` or Room with `JournalMode.WRITE_AHEAD_LOGGING`, which already gives one writer plus a reader pool. Android exposes no progress handler, so ejection maps to `CancellationSignal` passed to `rawQuery`/`query` and cancelled from a `withTimeout` coroutine; the thread-local reentrancy slot becomes a `ThreadLocal<SupportSQLiteDatabase?>` or, in coroutines, a `CoroutineContext` element (Room's `withTransaction` already does this). Metrics use `AtomicInteger` or a `Mutex`. The storage folder is `Context.filesDir` rather than a home dotfolder, so `AppStorageLocation` reduces to the token filter.
- **React/Web**: The closest equivalent is IndexedDB or SQLite-WASM (`@sqlite.org/sqlite-wasm` with OPFS) in a Web Worker; SQLite-WASM exposes `sqlite3_progress_handler`, so ejection ports directly, with `performance.now()` as the monotonic clock. Single-threaded JS has no thread-locals, so reentrancy needs an explicit "current connection" passed down or an `AsyncLocalStorage`-style context in Node (`better-sqlite3` offers a synchronous API and `db.function`-level hooks but no progress handler). The home dotfolder applies only to Node (`os.homedir()`).
- **AppKit / UIKit**: The same Swift sources apply unchanged. On iOS the home directory is the app sandbox container, so a caller passes `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` as `home` if a hidden dotfolder at the container root is not wanted; `Bundle.main` supplies `CFBundleName` in both.
- **WinUI 3**: Use `Microsoft.Data.Sqlite` with `PRAGMA journal_mode=WAL`, one `SqliteConnection` guarded by a `SemaphoreSlim(1, 1)` for writes and a small pool of read-only connections (`Mode=ReadOnly` in the connection string) for reads. `Microsoft.Data.Sqlite` does not expose `sqlite3_progress_handler`; eject instead with `SqliteCommand.Cancel()` fired from a `CancellationTokenSource.CancelAfter(deadline)` registration, or call the raw handler through `SQLitePCL.raw.sqlite3_progress_handler`. Measure with `Stopwatch` (monotonic). Reentrancy maps to an `AsyncLocal<SqliteConnection?>`, which flows across `await` unlike the source's thread-local, so nested calls stay correct in `async` code. Translate `SqliteException` with `SqliteErrorCode == 9` (`SQLITE_INTERRUPT`) into a `DeadlineExceededException(lane, elapsedMs)`. Busy waiting is `DefaultTimeout` / `PRAGMA busy_timeout`. Expose `stats` as an immutable record, or as an `INotifyPropertyChanged` view model marshalled through `DispatcherQueue.TryEnqueue` if a UI shows it. The storage folder is `Windows.Storage.ApplicationData.Current.LocalFolder` for packaged apps or `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)` plus the dotfolder for unpackaged ones, with the name from `Package.Current.DisplayName`.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from `BoundedDatabase.swift`, `AppStorageLocation.swift` and their tests |
