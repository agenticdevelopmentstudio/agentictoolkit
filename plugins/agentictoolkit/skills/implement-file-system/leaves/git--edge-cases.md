<!-- leaf: implement-file-system/git--edge-cases · source: file-system-git.md -->

# GitStatusProvider

**Rules** (cite as `implement-file-system/git--edge-cases#<slug>`):

- `null-and-empty-input` MUST — A repoRoot that does not exist, or is not inside a git repository, is not special-cased by GitStatusProvider; it is …
- `boundary-values` MUST — isQueued is a single Bool, not a counter, so however many refresh() calls arrive while a run is in flight, at most one …
- `concurrent-access` MUST — observe(_:) and refresh() may be called concurrently from any thread; every read and write of observers, isRunning, and …
- `error-states` MUST — GitClientError.executableNotFound, .launchFailed, .timedOut, and .commandFailed are not distinguished from one another …
- `cancellation-and-timeouts` MUST — start()'s Task { ... } is unstructured and its handle is discarded, so nothing external can cancel an in-flight …
- `missing-file-or-unreachable-server` MUST — A repoRoot that no longer exists on disk, or that points to a directory that is not a git repository, surfaces only as …

## Edge Cases

- **Null and empty input**: A `repoRoot` that does not exist, or is not
  inside a git repository, is not special-cased by `GitStatusProvider`; it
  is forwarded unchanged to `client.status(in:)`, whose resulting error is
  caught by the generic branch and reported as `.unavailable` (MUST, see
  `failure-yields-unavailable-never-empty`; exercised by
  `testAFailedStatusIsReportedAsUnavailableRatherThanAnEmptyStatus`). Calling
  `refresh()` while zero observers are registered still runs
  `client.status(in:)` to completion — the delivery loop over
  `Array($0.observers.values)` simply iterates zero times — so the run's
  cost is paid with no observer ever told (MUST, matching
  `broadcast-to-all-observers`).
- **Boundary values**: `isQueued` is a single `Bool`, not a counter, so
  however many `refresh()` calls arrive while a run is in flight, at most
  one follow-up run is owed; the boundary is exactly zero vs. one queued
  follow-up, never two or more (MUST, see `bounded-burst-cost`).
- **Concurrent access**: `observe(_:)` and `refresh()` may be called
  concurrently from any thread; every read and write of `observers`,
  `isRunning`, and `isQueued` is serialized by `OSAllocatedUnfairLock`, so no
  interleaving can observe a torn state (MUST, see
  `thread-safe-mutable-state`). The order in which multiple observers
  registered on one provider are called for a given result is the iteration
  order of `Array($0.observers.values)` over a `[UUID: Observer]`
  dictionary, which is not guaranteed to be insertion order or stable across
  calls (SHOULD NOT be relied upon by a consumer; the source makes no
  ordering promise across observers, only that every one of them is
  called).
- **Error states**: `GitClientError.executableNotFound`, `.launchFailed`,
  `.timedOut`, and `.commandFailed` are not distinguished from one another
  by `GitStatusProvider`; every one reaches the generic `catch` branch, is
  logged via `logDescription`, and is reported as `.unavailable` identically
  (MUST, see `failure-yields-unavailable-never-empty`,
  `error-log-omits-git-output`).
- **Offline or disconnected state**: Not applicable in the network sense —
  `GitStatusProvider.swift` makes no network call; its only external
  dependency is the local `client.status(in:)` subprocess call, whose
  failure (including an unreachable or misconfigured git executable) is
  handled identically to the Error states above.
- **Cancellation and timeouts**: `start()`'s `Task { ... }` is unstructured
  and its handle is discarded, so nothing external can cancel an in-flight
  refresh; the only cancellation path `load` observes is a
  `CancellationError` thrown from within `client.status(in:)` itself, which
  is reported as `.unavailable` without an error log (MUST, see
  `cancellation-yields-unavailable`). `GitClientError.timedOut` — raised
  when git does not finish within the client's configured timeout — is a
  distinct, non-`CancellationError` case that falls to the generic failure
  branch instead, and is logged at error level like any other failure
  (MUST, see `failure-yields-unavailable-never-empty`).
- **Missing file or unreachable server**: A `repoRoot` that no longer exists
  on disk, or that points to a directory that is not a git repository,
  surfaces only as whatever error `client.status(in:)` produces for that
  case; `GitStatusProvider.swift` performs no existence or repository check
  of its own before calling it (MUST, handled identically to Error states
  above).
