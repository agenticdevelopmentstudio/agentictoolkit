<!-- leaf: implement-git-client/projects-project-reconciler--edge-cases · source: git-client-projects-project-reconciler.md -->

# ProjectReconciler

**Rules** (cite as `implement-git-client/projects-project-reconciler--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An existing array and a scanned array that are both empty MUST cause plan(...) to return a Plan whose inserts, updates, …
- `boundary-values` MUST — A single-component relative path such as "alpha" (no leading separator) produces exactly one path component from …
- `concurrent-access` MUST — plan(...), repositoryExists(atPath:), and uniqueName(forPath:taken:) hold all of their mutable state in local …
- `error-states` MUST — No function in this file can throw. repositoryExists's only failure surface — FileManager.default.fileExists(atPath:) — …
- `missing-file-or-unreachable-directory` MUST — A missing row's path that no longer exists at all on disk (the ordinary "vanished repository" case) causes …

## Edge Cases

- **Null and empty input**: An `existing` array and a `scanned` array that are
  both empty MUST cause `plan(...)` to return a `Plan` whose `inserts`,
  `updates`, and `deletes` are all empty and whose `summary` has every count
  at its default of zero, since none of the four passes has anything to
  iterate (`ProjectReconciler.swift`). MUST.
  A scanned or existing `remote` of the empty string is treated as
  equivalent to `nil` for the purposes of `move-by-remote-priority` (the
  `!remote.isEmpty` guard rejects it) and for `move-by-name-fallback`'s
  eligibility check (`(remote ?? "").isEmpty`), even though `GitRepo` and
  `ScannedGitRepo` themselves store `nil` and `""` as distinct values
  (`ProjectReconciler.swift`). MUST.
- **Boundary values**: A single-component relative path such as `"alpha"`
  (no leading separator) produces exactly one path component from
  `URL(fileURLWithPath:).pathComponents`, so `uniqueName(forPath:taken:)`'s
  loop runs exactly once and either returns `"alpha"` or falls through to
  the exhausted-fallback return of the same string
  (`ProjectReconciler.swift`). MUST. When every possible
  suffix candidate — including the full path — is already in `taken`,
  `uniqueName(forPath:taken:)` returns the original `path` string verbatim
  rather than producing a numbered or otherwise disambiguated name, so two
  calls in the same `plan(...)` run can only collide if the caller
  populates `taken` with every level of one candidate's own ancestry in
  advance; ordinary use (seeding `taken` from existing row names) does not
  reach this boundary in the given tests (`ProjectReconciler.swift`). MUST.
- **Concurrent access**: `plan(...)`, `repositoryExists(atPath:)`, and
  `uniqueName(forPath:taken:)` hold all of their mutable state in local
  variables, and their parameter and return types (`GitRepo`,
  `ScannedGitRepo`, `ProjectReconciler.Plan`) are all `Sendable`, so multiple
  concurrent calls with independent inputs cannot race against each other
  or against any state owned by `ProjectReconciler` itself, which declares
  none (`ProjectReconciler.swift`). MUST. The
  `isStillARepository` closure parameter's type carries no `@Sendable`
  annotation (see `plan-injection-closure-not-sendable-annotated`), so a
  caller that hands `plan(...)` a closure capturing mutable state shared
  with another concurrency domain is not protected by this file's type
  signature; the default `ProjectReconciler.repositoryExists` captures
  nothing and is safe to call from anywhere. MUST.
- **Error states**: No function in this file can throw. `repositoryExists`'s
  only failure surface — `FileManager.default.fileExists(atPath:)` — never
  throws either; a permission-denied ancestor directory, a `.git` path that
  never existed, and a path on an unmounted volume all collapse to the same
  `false` result, which `plan(...)` then treats identically to "genuinely
  gone" (`ProjectReconciler.swift`). This collapsing is
  exactly what the doc comment on `repositoryExists` describes as the
  intended, sole test ("its existence is the whole test,"),
  not a swallowed error. MUST.
- **Offline or disconnected state**: Not applicable — nothing in this file
  makes a network call; its only I/O is the local filesystem existence
  check inside `repositoryExists(atPath:)`.
- **Missing file or unreachable directory**: A missing row's `path` that no
  longer exists at all on disk (the ordinary "vanished repository" case)
  causes `isStillARepository` to return `false`, so the row proceeds
  normally into the move pass and, absent a match, into `deletes`
  (`ProjectReconciler.swift`; verified by
  `testAVanishedRepoIsDeleted`). MUST.
- **Cancellation and timeouts**: Not applicable — `plan(...)`,
  `repositoryExists(atPath:)`, and `uniqueName(forPath:taken:)` are all
  synchronous, non-`async` computations with nothing to cancel and no
  operation that can run long enough to time out.
- **Duplicate paths in the inputs**: See `duplicate-existing-path-handling`
  (a caller precondition the database schema enforces) and the open question
  on duplicate-scanned-path-handling; the source neither rejects nor
  normalizes either.
