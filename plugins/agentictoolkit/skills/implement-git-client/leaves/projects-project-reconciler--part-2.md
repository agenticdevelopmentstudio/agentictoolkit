<!-- leaf: implement-git-client/projects-project-reconciler--part-2 · source: git-client-projects-project-reconciler.md -->

# ProjectReconciler — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-reconciler--part-2#<slug>`):

- `plan-struct-shape` MUST
- `exact-path-match-lookup` MUST
- `unmatched-scan-collection` MUST
- `exact-path-match-remote-update` MUST
- `exact-path-match-increments-unchanged` MUST
- `missing-rows-exclude-seen` MUST
- `unreachable-path-skipped-not-deleted` MUST
- `move-by-remote-priority` MUST
- `move-by-remote-requires-uniqueness` MUST
- `move-by-name-fallback` MUST
- `unmatched-move-becomes-delete` MUST
- `move-preserves-identity-and-name` MUST
- `move-claims-target-path` MUST
- `move-precedes-insert` MUST
- `insert-unique-name` MUST
- `insert-fresh-fields` MUST
- `delete-whatever-remains` MUST
- `plan-defaults` MUST
- `repository-exists-check` MUST
- `unique-name-escalation` MUST
- `unique-name-empty-path` MUST
- `unique-name-exhausted-fallback` MUST
- `plan-pure-and-side-effect-free` MUST
- `reconciler-isolation-free` MUST

## Behavioral Requirements

- **plan-struct-shape**: `ProjectReconciler.Plan` MUST conform to `Sendable`
  and MUST store four properties — `inserts`, `updates`, and `deletes`, each
  an array of `GitRepo` values defaulting to empty, and `summary`, a
  `ProjectScanSummary` defaulting to a freshly constructed instance
  (`ProjectReconciler.swift`).
- **exact-path-match-lookup**: `plan(existing:scanned:now:isStillARepository:)`
  MUST build a lookup keyed by every existing row's `path` before considering
  any scanned repository, so a scanned repository's fate is decided by an
  exact string match against that lookup (`ProjectReconciler.swift`).
- **unmatched-scan-collection**: Every scanned repository whose `path` is not
  a key in that lookup MUST be added to the set of scans available to the
  later move and insert passes, in the order `scanned` was given
  (`ProjectReconciler.swift`).
- **exact-path-match-remote-update**: When a scanned repository's `path`
  exactly matches a known row and that row's stored `remote` differs from
  the scanned `remote`, `plan(...)` MUST overwrite the row's `remote` with
  the scanned value, MUST set its `lastSeen` to `now`, and MUST append the
  mutated row to `updates`; when the two `remote` values are equal,
  `plan(...)` MUST NOT append anything to `updates` for that row
  (`ProjectReconciler.swift`).
- **exact-path-match-increments-unchanged**: `plan(...)` MUST increment
  `summary.unchanged` by exactly one for every scanned repository whose path
  exactly matches a known row, regardless of whether that same row was also
  just appended to `updates` for a remote change — a row can count toward
  `unchanged` and appear in `updates` in the same call
  (`ProjectReconciler.swift`; verified by
  `testARepointedRemoteIsWrittenBack`).
- **missing-rows-exclude-seen**: After the exact-path pass, `plan(...)` MUST
  narrow the candidates for the skip, move, and delete passes to existing
  rows whose `id` was not marked seen during that pass
  (`ProjectReconciler.swift`).
- **unreachable-path-skipped-not-deleted**: A missing row for which
  `isStillARepository` returns `true` for that row's `path` MUST be excluded
  from both the move pass and the delete pass, and the count of such rows
  MUST be added to `summary.skipped` rather than `summary.removed`
  (`ProjectReconciler.swift`).
- **move-by-remote-priority**: For a missing row whose `remote` is present
  and non-empty, `plan(...)` MUST consider only unclaimed scanned
  repositories whose `remote` equals that exact string as move candidates
  before ever consulting directory-name equality
  (`ProjectReconciler.swift`).
- **move-by-remote-requires-uniqueness**: `plan(...)` MUST use a remote-based
  candidate as the match only when exactly one unclaimed scanned repository
  shares the missing row's `remote`; when zero or more than one share it,
  `plan(...)` MUST fall back to the directory-name comparison instead
  (`ProjectReconciler.swift`).
- **move-by-name-fallback**: `plan(...)` MUST match a missing row to an
  unclaimed scanned repository by directory-name equality — the scanned
  repository's `leafName` equal to `GitRepo.defaultName(forPath:)` of the
  missing row's path — only when both the missing row's `remote` and the
  candidate's `remote` are `nil` or the empty string, and only when exactly
  one such candidate exists (`ProjectReconciler.swift`).
- **unmatched-move-becomes-delete**: A missing row for which neither the
  remote pass nor the name pass yields a unique candidate MUST remain
  unresolved after the move pass and MUST end up in `deletes`
  (`ProjectReconciler.swift`; verified by
  `testAnAmbiguousMoveDeletesTheRow`).
- **move-preserves-identity-and-name**: When a missing row is matched,
  `plan(...)` MUST keep that row's `id` and `name` unchanged, MUST overwrite
  its `path` and `remote` with the matched scan's values, MUST set its
  `lastSeen` to `now`, MUST append it to `updates`, and MUST NOT also append
  it to `inserts` (`ProjectReconciler.swift`).
- **move-claims-target-path**: `plan(...)` MUST record a matched scan's
  `path` as claimed at the moment the match is made, so that no later
  iteration of the move pass, and no later evaluation of the insert pass,
  can match that same scanned path a second time
  (`ProjectReconciler.swift`).
- **move-precedes-insert**: `plan(...)` MUST resolve every possible move
  before evaluating any scanned repository for insertion, so a repository's
  destination path after a move is never also treated as a brand-new project
  (`ProjectReconciler.swift`; verified by
  `testAMoveIsResolvedBeforeTheNewPathIsAdopted`).
- **insert-unique-name**: For every scanned repository left unclaimed after
  the move pass, `plan(...)` MUST derive its name by calling
  `uniqueName(forPath:taken:)`, seeding `taken` from every existing row's
  current `name` and adding each newly assigned name to `taken` before
  processing the next unclaimed scan in the same call, so two repositories
  inserted by one `plan(...)` call MUST NOT receive the same name
  (`ProjectReconciler.swift`; verified by
  `testASecondRepoWithTheSameLeafNameIsQualifiedByItsParent`).
- **insert-fresh-fields**: Each newly inserted `GitRepo` MUST take its `path`
  and `remote` from the unmatched scan and MUST set both `firstSeen` and
  `lastSeen` to `now`, leaving `id` to `GitRepo.init`'s default of a freshly
  generated `UUID` (`ProjectReconciler.swift`).
- **delete-whatever-remains**: `plan(...)` MUST place every missing row that
  the skip pass and the move pass left unresolved into `deletes`, and MUST
  set `summary.removed` to the count of that final list
  (`ProjectReconciler.swift`).
- **plan-defaults**: `plan(existing:scanned:now:isStillARepository:)` MUST
  default `now` to `Date()` evaluated at the moment of the call and MUST
  default `isStillARepository` to `ProjectReconciler.repositoryExists` when
  the caller supplies neither (`ProjectReconciler.swift`).
- **repository-exists-check**: `repositoryExists(atPath:)` MUST return
  whether `FileManager.default` reports an entry named `.git` directly under
  `path`, and per its own doc comment — "its existence is the whole test" —
  MUST NOT additionally check whether that entry is a directory or contains
  a `HEAD` file (`ProjectReconciler.swift`).
- **unique-name-escalation**: `uniqueName(forPath:taken:)` MUST split `path`
  into its non-separator path components and MUST try, in order, the
  shortest trailing run of one component, then two, and so on, each joined
  with `/`, returning the first such candidate that is not a member of
  `taken` (`ProjectReconciler.swift`; verified by
  `testUniqueNameWalksUpUntilItIsFree`).
- **unique-name-empty-path**: `uniqueName(forPath:taken:)` MUST return
  `path` unchanged when `path` has no non-separator components
  (`ProjectReconciler.swift`).
- **unique-name-exhausted-fallback**: When every candidate through the full
  path, including the full path itself, is already present in `taken`,
  `uniqueName(forPath:taken:)` MUST return `path` unchanged, exactly as it
  was passed in, rather than appending a disambiguating suffix of any kind
  (`ProjectReconciler.swift`).
- **plan-pure-and-side-effect-free**: `plan(...)`, `repositoryExists(atPath:)`,
  and `uniqueName(forPath:taken:)` MUST each be synchronous and non-throwing,
  and none MUST perform network access, read or write a database, or store
  anything on `ProjectReconciler` itself, which declares no stored property
  of any kind (`ProjectReconciler.swift`).
- **reconciler-isolation-free**: `ProjectReconciler` MUST declare no `actor`
  or `@MainActor` isolation on itself or on any of its three static
  functions, so all three MUST be callable synchronously from any
  concurrency domain, matching the type doc comment's stated "Pure and
  `nonisolated`" intent (`ProjectReconciler.swift`).
- **plan-injection-closure-not-sendable-annotated**: The type of
  `isStillARepository` is a plain function value taking a `String` and
  returning a `Bool`; unlike `GitRepoScanner`'s `isCancelled` and
  `onProgress` parameters, it carries no `@Sendable` annotation, so nothing
  in this file's own signature obliges a caller-supplied closure to be safe
  to invoke from a different concurrency domain than the one that
  constructed it (`ProjectReconciler.swift`, contrast
  `GitRepoScanner.swift`).
- **duplicate-existing-path-handling**: `plan(existing:scanned:now:isStillARepository:)` does not validate that `existing` holds at most one row per `path`; it relies on its caller, and the `git_repo` table that `ProjectDatabase` reads `existing` from declares `path TEXT NOT NULL UNIQUE`, so database-supplied rows never repeat a path. A caller that passes hand-built rows with a repeated path gets the path-keyed lookup's last-wins behavior: the earlier row can never be matched by the exact-path pass and, if its own path still exists on disk, never appears in `inserts`, `updates`, or `deletes`.
- **duplicate-scanned-path-handling**: NEEDS REVIEW: Not implemented in source. `plan(existing:scanned:now:isStillARepository:)` never validates that `scanned` holds at most one entry per `path`; two `ScannedGitRepo` values sharing one path — plausible when a caller configures overlapping scan roots — are each processed independently through the exact-path pass and the unmatched-scan pass, so they can produce two separate `updates` entries carrying the same existing row's `id`, or two separate `inserts` for what is really one directory. What is missing: whether `GitRepoScanner` guarantees unique paths across a whole multi-root scan, or whether `plan` is expected to deduplicate its own input before matching. What would settle it: a doc-comment statement of that precondition on `scanned`, or evidence that overlapping roots are never a supported configuration.

