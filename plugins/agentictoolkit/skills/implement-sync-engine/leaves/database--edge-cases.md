<!-- leaf: implement-sync-engine/database--edge-cases · source: sync-engine-database.md -->

# Sync Engine Database

**Rules** (cite as `implement-sync-engine/database--edge-cases#<slug>`):

- `empty-display-name` MUST — token(for: "") and a name made only of spaces or punctuation MUST return "AgenticToolkit"; a missing or empty …
- `path-separators-in-the-name` MUST — /, . and spaces MUST be dropped by token(for:), so the result can never escape home or add a nested component.
- `localized-bundle-name` MUST — when an app localizes CFBundleName, displayName and token MUST follow the active localization, so the directory can …
- `non-ascii-names` MUST — letters, combining marks and digits outside ASCII MUST survive token(for:); the directory then carries non-ASCII …
- `missing-parent-directory` MUST — BoundedDatabase.init on a path whose directory does not exist MUST throw the GRDB open error; neither type creates the …
- `near-miss-in-memory-paths` MUST — only the exact string ":memory:" MUST select the DatabaseQueue; any other spelling (such as a file: URI) MUST go to …
- `zero-or-negative-deadline` MUST — MUST eject at the first progress check rather than trap (max(0, …) in armDeadline).
- `statement-that-never-reaches-a-progress-check` MUST — ejection MUST only happen at a 1000-instruction boundary, so time blocked outside the SQLite VM (for example waiting on …
- `locked-database` MUST — a write MUST wait up to busyTimeout seconds for the lock, then fail with the GRDB busy error, which propagates …
- `body-swallows-the-ejection` MUST — the call MUST return the body's value and count as a completion; for writeWithoutTransaction any transaction left open …
- `write-nested-inside-a-read` MUST — a write called inside a top-level read MUST run inline on the reader connection; this source adds no check, so the …
- `nested-ejection-details` MUST — the thrown error MUST carry the nested call's lane and elapsedMs: 0, even though the enclosing op's lane records the …
- `concurrent-callers` MUST — top-level reads on different threads MAY run in parallel up to readers; top-level writes MUST queue on the single …
- `direct-writer-access` MUST — statements run through writer MUST NOT be ejected or metered, because no deadline is armed on that thread.

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
