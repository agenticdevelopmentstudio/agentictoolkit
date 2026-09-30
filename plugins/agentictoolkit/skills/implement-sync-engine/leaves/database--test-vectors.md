<!-- leaf: implement-sync-engine/database--test-vectors · source: sync-engine-database.md -->

# Sync Engine Database

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
