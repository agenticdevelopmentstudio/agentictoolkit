<!-- leaf: implement-sync-engine/database--part-3 · source: sync-engine-database.md -->

# Sync Engine Database — continued (part 3)

**Rules** (cite as `implement-sync-engine/database--part-3#<slug>`):

- `in-flight-accounting` MUST
- `completion-record` MUST
- `eviction-record` MUST
- `other-errors-unrecorded` MUST
- `duration-includes-wait` MUST
- `percentile-window` MUST
- `percentile-empty` MUST
- `stats-shape` MUST
- `stats-consistency` MUST
- `stats-sendable` MUST
- `sendable-class` MUST
- `per-thread-state` MUST

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

## Localization

`AppStorageLocation` contains no user-facing string of its own; `fallbackToken` (`"AgenticToolkit"`) is a hardcoded, unlocalized identifier, and `displayName` returns the bundle's `CFBundleName` as `object(forInfoDictionaryKey:)` resolves it, which is the localized value when the app localizes that key. Consumers interpolate `displayName` into sentences the user reads.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `CFBundleName` (Info.plist, optionally InfoPlist.strings) | the app's bundle name, or `AgenticToolkit` when absent | Returned by `displayName`; also the input to `token` and therefore to the storage directory name. |

## Privacy

- **Data collected**: None by this module; it stores whatever rows its caller writes.
- **Storage**: A plain, unencrypted SQLite file (plus its `-wal` and `-shm` companions) at the caller's `path`, typically inside `~/.<token>`; `:memory:` databases are never written to disk.
- **Transmission**: None; the module performs no network I/O.
- **Retention**: Data persists until the caller deletes it or the file; the module deletes nothing.

## Platform Notes

- **SwiftUI**: Source platform (`Database/BoundedDatabase.swift`, `Database/AppStorageLocation.swift`, module `AgenticToolkitDatabase`). It imports `Foundation`, `SQLite3` (for `sqlite3_progress_handler`) and GRDB; the per-op deadline and current connection live in `Thread.current.threadDictionary`, which works because GRDB runs each sync op on one thread; the handler is a capture-free `@convention(c)` closure; `DispatchTime` supplies the monotonic clock and `NSLock` guards the metrics. A SwiftUI app owns one instance per database file and should call it off the main actor, since every call blocks.
- **Compose**: Start from Android's `SQLiteDatabase` with `enableWriteAheadLogging()` or Room with `JournalMode.WRITE_AHEAD_LOGGING`, which already gives one writer plus a reader pool. Android exposes no progress handler, so ejection maps to `CancellationSignal` passed to `rawQuery`/`query` and cancelled from a `withTimeout` coroutine; the thread-local reentrancy slot becomes a `ThreadLocal<SupportSQLiteDatabase?>` or, in coroutines, a `CoroutineContext` element (Room's `withTransaction` already does this). Metrics use `AtomicInteger` or a `Mutex`. The storage folder is `Context.filesDir` rather than a home dotfolder, so `AppStorageLocation` reduces to the token filter.
- **React/Web**: The closest equivalent is IndexedDB or SQLite-WASM (`@sqlite.org/sqlite-wasm` with OPFS) in a Web Worker; SQLite-WASM exposes `sqlite3_progress_handler`, so ejection ports directly, with `performance.now()` as the monotonic clock. Single-threaded JS has no thread-locals, so reentrancy needs an explicit "current connection" passed down or an `AsyncLocalStorage`-style context in Node (`better-sqlite3` offers a synchronous API and `db.function`-level hooks but no progress handler). The home dotfolder applies only to Node (`os.homedir()`).
- **AppKit / UIKit**: The same Swift sources apply unchanged. On iOS the home directory is the app sandbox container, so a caller passes `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` as `home` if a hidden dotfolder at the container root is not wanted; `Bundle.main` supplies `CFBundleName` in both.
- **WinUI 3**: Use `Microsoft.Data.Sqlite` with `PRAGMA journal_mode=WAL`, one `SqliteConnection` guarded by a `SemaphoreSlim(1, 1)` for writes and a small pool of read-only connections (`Mode=ReadOnly` in the connection string) for reads. `Microsoft.Data.Sqlite` does not expose `sqlite3_progress_handler`; eject instead with `SqliteCommand.Cancel()` fired from a `CancellationTokenSource.CancelAfter(deadline)` registration, or call the raw handler through `SQLitePCL.raw.sqlite3_progress_handler`. Measure with `Stopwatch` (monotonic). Reentrancy maps to an `AsyncLocal<SqliteConnection?>`, which flows across `await` unlike the source's thread-local, so nested calls stay correct in `async` code. Translate `SqliteException` with `SqliteErrorCode == 9` (`SQLITE_INTERRUPT`) into a `DeadlineExceededException(lane, elapsedMs)`. Busy waiting is `DefaultTimeout` / `PRAGMA busy_timeout`. Expose `stats` as an immutable record, or as an `INotifyPropertyChanged` view model marshalled through `DispatcherQueue.TryEnqueue` if a UI shows it. The storage folder is `Windows.Storage.ApplicationData.Current.LocalFolder` for packaged apps or `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)` plus the dotfolder for unpackaged ones, with the name from `Package.Current.DisplayName`.

