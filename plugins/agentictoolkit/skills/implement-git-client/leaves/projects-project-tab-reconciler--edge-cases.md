<!-- leaf: implement-git-client/projects-project-tab-reconciler--edge-cases · source: git-client-projects-project-tab-reconciler.md -->

# ProjectTabReconciler

**Rules** (cite as `implement-git-client/projects-project-tab-reconciler--edge-cases#<slug>`):

- `null-and-empty-input` MUST — stored and checkouts both empty MUST cause plan(...) to return a Plan whose keep, add, and drop are all empty and whose …
- `boundary-values` MUST — A stored record whose id equals activeTabID MUST be preferred by arrangement(...) over tabs.first even when it is not …
- `concurrent-access` MUST — plan(...), volumeIsMounted(...), arrangement(...), and makeRecords(...) hold all of their mutable state in local …
- `error-states` MUST — No function in this file can throw. volumeURL(of:)'s only failure surface — resourceValues(forKeys: [.volumeURLKey]) — …
- `missing-file-or-unreachable-directory` MUST — A stored record's directory that no longer exists anywhere on a mounted volume causes isGone to be true and isMounted …

## Edge Cases

- **Null and empty input**: `stored` and `checkouts` both empty MUST cause
  `plan(...)` to return a `Plan` whose `keep`, `add`, and `drop` are all
  empty and whose `isUnchanged` is `true`, since neither the stored-record
  loop nor the `add` filter has anything to iterate
  (`ProjectTabReconciler.swift`). MUST. `enabledEdges` empty in a
  call to `makeRecords(...)` MUST cause it to return an empty array without
  invoking `blueprint()` at all, since `enabledEdges.map { ... }` over an
  empty array never calls its closure (`ProjectTabReconciler.swift`). MUST.
- **Boundary values**: A stored record whose `id` equals `activeTabID` MUST
  be preferred by `arrangement(...)` over `tabs.first` even when it is not
  the first element of `tabs`; when no element matches, the boundary
  collapses to `tabs.first`, and when `tabs` itself is empty it collapses
  further to `nil` (`ProjectTabReconciler.swift`). MUST. A single
  stored `TabRecord` group with more than one enabled edge — several records
  sharing one `workingDirectory` — is evaluated independently per record by
  `plan(...)`'s loop, but since `isGone` and `isMounted` depend only on the
  shared directory, not on which record is being examined, every member of
  that group MUST reach the same keep-or-drop outcome; they can never be
  split between `keep` and `drop` (`ProjectTabReconciler.swift`).
  MUST.
- **Concurrent access**: `plan(...)`, `volumeIsMounted(...)`,
  `arrangement(...)`, and `makeRecords(...)` hold all of their mutable state
  in local variables, and `ProjectTabReconciler` itself declares no stored
  property of any kind, so independent concurrent calls with independent
  inputs cannot race against each other or against any state this file owns
  (`ProjectTabReconciler.swift`). MUST. The result they hand
  back is a different matter: neither `Plan` nor `TabRecord` is `Sendable`
  (see `plan-and-record-non-sendable`), so a caller that shares one `Plan`
  value, or the closures passed as `existsOnDisk`/`volumeIsMounted`, across
  concurrency domains without its own synchronization is not protected by
  this file's type signatures. MUST.
- **Error states**: No function in this file can throw. `volumeURL(of:)`'s
  only failure surface — `resourceValues(forKeys: [.volumeURLKey])` — is
  wrapped in `try?`, so a thrown error there always becomes `nil` rather
  than propagating; see `volume-lookup-failure-handling` for the case this
  swallowing makes ambiguous. MUST.
- **Offline or disconnected state**: Not applicable — nothing in this file
  makes a network call; its only I/O is local filesystem existence and
  volume-URL lookups through `existsOnDisk` and the default
  `FileManager`/`resourceValues` calls.
- **Missing file or unreachable directory**: A stored record's directory
  that no longer exists anywhere on a mounted volume causes `isGone` to be
  `true` and `isMounted` to be `true`, so the record proceeds into `drop`
  (`ProjectTabReconciler.swift`; verified by
  `testATabWhoseDirectoryVanishedIsDropped`). MUST. The same missing
  directory on an unmounted or unreachable volume causes `isMounted` to be
  `false`, so the record is kept instead, deliberately trading a possibly
  stale tab for never silently deleting one the user can no longer get back
  (`ProjectTabReconciler.swift`; verified by
  `testATabOnAnUnmountedVolumeIsKeptNotDropped`). MUST.
- **Cancellation and timeouts**: Not applicable — `plan(...)`,
  `volumeIsMounted(...)`, `arrangement(...)`, and `makeRecords(...)` are all
  synchronous, non-`async` computations with nothing to cancel and no
  operation that can run long enough to time out.
- **Duplicate checkout directories**: See `duplicate-checkout-directory-handling`
  above; the source neither rejects nor deduplicates two `checkouts` entries
  that name the same directory.
