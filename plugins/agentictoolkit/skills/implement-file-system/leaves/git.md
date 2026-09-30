<!-- leaf: implement-file-system/git · source: file-system-git.md -->

**Rules** (cite as `implement-file-system/git#<slug>`):

- `color-mapping-per-status` MUST
- `ns-color-mapping-per-status` MUST
- `color-and-ns-color-parity` MUST
- `refresh-result-cases` MUST
- `observer-registration` MUST
- `observation-token-unregisters-on-release` MUST
- `weak-reference-in-cancellation-closure` MUST
- `broadcast-to-all-observers` MUST
- `main-actor-delivery` MUST
- `immediate-start-when-idle` MUST
- `coalesced-overlap` MUST
- `bounded-burst-cost` MUST
- `success-delivers-status-and-logs` MUST
- `cancellation-yields-unavailable` MUST
- `failure-yields-unavailable-never-empty` MUST
- `error-log-omits-git-output` MUST
- `injectable-client-with-shared-default` MUST
- `thread-safe-mutable-state` MUST

# GitStatusProvider

## Overview

`GitStatusProvider` asks `GitClient` for one repository's working-tree status
and broadcasts the result to every registered observer on the main actor.
One provider serves every pane watching a checkout, so a refresh answers
"everyone's badges," not just whoever triggered it; overlapping `refresh()`
calls coalesce into at most one queued follow-up run rather than one process
per call. A failed or cancelled check is reported as `GitStatusRefreshResult.unavailable`
rather than an empty status, because an empty status and "we could not ask"
are different facts a consumer must not confuse. `GitFileStatus+Color.swift`
is the companion extension the badges this provider's status feeds actually
paint with: it gives every `GitFileStatus` case a fixed SwiftUI `Color` and
an AppKit `NSColor`, two spellings of the same fact so that whichever
framework draws the badge, red still means deleted.

## Behavioral Requirements

- **color-mapping-per-status**: `GitFileStatus.color` MUST return SwiftUI
  `Color.orange` for `.modified`, `Color.green` for `.added` and
  `.untracked`, `Color.red` for `.deleted`, `Color.blue` for `.renamed` and
  `.copied`, `Color.purple` for `.conflicted`, and `Color.gray` for
  `.ignored` (`GitFileStatus+Color.swift`).
- **ns-color-mapping-per-status**: `GitFileStatus.nsColor` MUST return the
  AppKit equivalent for each case: `NSColor.systemOrange` for `.modified`,
  `.systemGreen` for `.added` and `.untracked`, `.systemRed` for `.deleted`,
  `.systemBlue` for `.renamed` and `.copied`, `.systemPurple` for
  `.conflicted`, and `.systemGray` for `.ignored` (`GitFileStatus+Color.swift`).
- **color-and-ns-color-parity**: For every `GitFileStatus` case, `color` and
  `nsColor` MUST name the same semantic hue (orange/orange, green/green,
  red/red, blue/blue, purple/purple, gray/gray); per the doc comment these
  are "the same colors for AppKit callers... two spellings of one fact
  rather than two facts," so whichever framework draws a badge, red still
  means deleted (`GitFileStatus+Color.swift`).
- **refresh-result-cases**: `GitStatusRefreshResult` MUST provide exactly two
  cases, `.status(GitStatus)` and `.unavailable`, and MUST conform to
  `Sendable` (`GitStatusProvider.swift`).
- **observer-registration**: `observe(_:)` MUST register the supplied
  observer under a fresh `UUID` key so it receives every result the provider
  produces from the moment of registration onward, and MUST NOT replay any
  result delivered before it was registered (`GitStatusProvider.swift`).
- **observation-token-unregisters-on-release**: The `GitStatusObservation`
  returned by `observe(_:)` MUST be the only way to stop receiving results;
  releasing it (letting it deinitialize) MUST remove the corresponding entry
  from the observers map via its `deinit`-invoked `cancel` closure
  (`GitStatusProvider.swift`).
- **weak-reference-in-cancellation-closure**: The `cancel` closure captured
  by `observe(_:)` MUST hold `self` weakly, so an outstanding, unreleased
  `GitStatusObservation` MUST NOT keep the owning `GitStatusProvider` alive
  (`GitStatusProvider.swift`).
- **broadcast-to-all-observers**: A single `refresh()` call's result MUST be
  delivered to every observer registered on the provider at delivery time,
  not only to whichever caller triggered the refresh (`GitStatusProvider.swift`).
- **main-actor-delivery**: Every observer invocation MUST occur on the main
  actor, matching the `Observer` typealias's `@MainActor` annotation
  (`GitStatusProvider.swift`).
- **immediate-start-when-idle**: A `refresh()` call made while no run is in
  flight (`isRunning == false`) MUST set `isRunning` and start a new run
  immediately, without waiting for any other event (`GitStatusProvider.swift`).
- **coalesced-overlap**: A `refresh()` call made while a run is already in
  flight MUST NOT start a second concurrent `client.status(in:)` call; it
  MUST instead set `isQueued` and return, leaving the in-flight run to
  trigger the follow-up after it finishes delivering (`GitStatusProvider.swift`).
- **bounded-burst-cost**: Any number of `refresh()` calls that arrive while
  one run is in flight MUST be coalesced into at most one follow-up run,
  because `isQueued` is a single boolean rather than a counter — a burst of
  N overlapping calls MUST cost at most two `client.status(in:)` invocations
  in total, never N (`GitStatusProvider.swift`).
- **success-delivers-status-and-logs**: When `client.status(in:)` succeeds,
  `load` MUST wrap the result in `.status(status)`, and MUST log one
  `info`-level message naming the resulting file and directory counts with
  `.public` privacy (`GitStatusProvider.swift`).
- **cancellation-yields-unavailable**: When `client.status(in:)` throws
  `CancellationError`, `load` MUST return `.unavailable` rather than
  rethrowing, and MUST NOT emit an error-level log for that case —
  cancellation is reported as "we do not know," never treated as evidence
  the tree is clean (`GitStatusProvider.swift`).
- **failure-yields-unavailable-never-empty**: When `client.status(in:)`
  throws any error other than `CancellationError`, `load` MUST return
  `.unavailable`, never a default or empty `GitStatus`, so a consumer cannot
  mistake "git could not be asked" for "the tree is clean"
  (`GitStatusProvider.swift`).
- **error-log-omits-git-output**: The error-level log emitted on a
  non-cancellation failure MUST be built from `GitClientError.logDescription`
  when the error is a `GitClientError`, or from
  `String(describing: type(of: error))` otherwise, and MUST NOT use
  `error.localizedDescription` or otherwise include git's raw `standardError`
  text (`GitStatusProvider.swift`).
- **injectable-client-with-shared-default**: `init(repoRoot:client:)` MUST
  accept a `GitClient` and MUST default it to `GitClient.shared` when the
  caller supplies none (`GitStatusProvider.swift`).
- **thread-safe-mutable-state**: `observers`, `isRunning`, and `isQueued`
  MUST be read and written only inside a `state.withLock` closure on the
  `OSAllocatedUnfairLock`-backed `state` property; `GitStatusProvider` MUST
  be declared `Sendable` on the strength of that discipline, since it holds
  no other mutable state (`GitStatusProvider.swift`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repoRoot` (parameter to `init`) | `URL` | none — required | The checkout this provider reports on; fixed for the instance's lifetime. |
| `client` (parameter to `init`) | `GitClient` | `.shared` | Injectable git client; a test substitutes a differently-configured or fake instance. |

Neither given source file reads an environment variable or a settings key
directly. The git executable path, timeout, and submodule handling are
`GitClientConfiguration` concerns reached only indirectly, through whichever
`client` is injected.

## Platform Notes

- **SwiftUI**: The sources are
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitStatusProvider.swift`
  and `GitFileStatus+Color.swift` in the same directory, alongside their
  collaborators `GitClient.swift`, `GitStatus.swift`, `GitFileStatus.swift`,
  and `GitClientError.swift` (all under `Core/Git`). The provider uses
  `OSAllocatedUnfairLock` for its guarded state, an unstructured `Task` plus
  `MainActor.run` for the fetch-then-deliver cycle, and `os.Logger` via the
  shared `Loggable` protocol for logging; the color extension is plain
  computed properties over `SwiftUI.Color` and `AppKit.NSColor`. Nothing
  here is SwiftUI-specific beyond the `Color` type itself.
- **Compose**: Jetpack Compose has one `androidx.compose.ui.graphics.Color`
  type, so the `color`/`nsColor` duplication has no reason to exist on this
  platform — port both into a single `val GitFileStatus.color: Color`
  extension. For the provider, use a `kotlinx.coroutines.sync.Mutex` (or a
  plain `synchronized` block) to guard a data class equivalent to `State`, a
  `MutableStateFlow`/`SharedFlow<GitStatusRefreshResult>` or a listener
  `MutableList` under that lock in place of the UUID-keyed observer map, and
  `Dispatchers.Main.immediate` for delivery. Kotlin listeners are typically
  removed explicitly rather than via `deinit`, so a faithful port should keep
  an explicit disposable/token type returned from `observe` to preserve the
  "cannot forget to unregister" guarantee.
- **React/Web**: Model the provider as a small class exposing
  `subscribe(observer)` that returns an unsubscribe function — the returned
  function stands in for `GitStatusObservation` — backed by a `Set` of
  callbacks; no extra locking is needed since JavaScript has no preemptive
  threads. A browser cannot spawn a process at all, so git status can only
  be asked from a Node-hosted process (`child_process.execFile` running
  `git`); a browser-only port of this pattern has no `GitClient` equivalent
  to call. Use CSS custom properties or a token map (a `modified` key mapped
  to an orange value) in place of `Color`/`NSColor`.
- **AppKit / UIKit**: Identical to the SwiftUI note — neither file is tied
  to a UI framework beyond the color extension's two color types. A UIKit
  (iOS) port needs only `UIColor`, one type, which removes the duplication
  the same way Compose does; the provider itself ports unchanged.
- **WinUI 3**: Port `GitStatusProvider` as a plain C# class holding a lock
  object (or `System.Threading.Lock`) guarding a private record equivalent
  to `State` — a `Dictionary<Guid, Action<GitStatusRefreshResult>>` for
  observers, plus `isRunning`/`isQueued` booleans — and expose
  `IDisposable Observe(Action<GitStatusRefreshResult> observer)` returning a
  disposable whose `Dispose()` removes the entry, the direct analogue of a
  `deinit`-triggered token. Marshal delivery to the UI thread with
  `DispatcherQueue.TryEnqueue` in place of `MainActor.run`. Represent
  `GitStatusRefreshResult` as a small discriminated union or a two-case
  class hierarchy. Use `Microsoft.UI.Colors`/`Windows.UI.Color` for the
  status-to-color mapping — again one color type, no `NSColor`-style
  duplicate needed. Log with `Microsoft.Extensions.Logging`'s `ILogger`,
  taking care that whatever formats the failure message never interpolates
  the git subprocess's raw standard-error text, mirroring `logDescription`'s
  omission.

