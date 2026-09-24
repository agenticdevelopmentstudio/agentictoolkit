---
id: 9a4aa2a8-c01b-4cec-b789-6c89c100d8d3
title: GitStatusProvider
domain: agentictoolkit://recipes/file-system-git
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Broadcasts a repository's git status to registered observers with coalesced
  refreshes, plus the status-to-color mapping git-status badges use.
platforms:
- swift
- macos
tags:
- git
- file-browser
- concurrency
- color
depends-on: []
related:
- agentictoolkit://recipes/file-browser-view-controller
- agentictoolkit://recipes/file-tree-outline-view-controller
references:
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitFileStatus+Color.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitStatusProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitFileStatus.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClientError.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitStatus.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/FileBrowser/GitStatusProviderRefreshTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a git-status broadcaster and status-to-color
mapping, not a visual component.

## States

Not applicable — this is a git-status broadcaster and status-to-color
mapping, not a visual component.

## Accessibility

Not applicable — this is a git-status broadcaster and status-to-color
mapping, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-system-git-001 | color-mapping-per-status | Evaluate `.color` on `.modified`, `.added`, `.deleted`, `.renamed`, `.copied`, `.untracked`, `.ignored`, `.conflicted`. | Returns `.orange`, `.green`, `.red`, `.blue`, `.blue`, `.green`, `.gray`, `.purple` respectively. |
| file-system-git-002 | ns-color-mapping-per-status | Evaluate `.nsColor` on the same eight cases. | Returns `.systemOrange`, `.systemGreen`, `.systemRed`, `.systemBlue`, `.systemBlue`, `.systemGreen`, `.systemGray`, `.systemPurple` respectively. |
| file-system-git-003 | color-and-ns-color-parity | Compare vector 001's result to vector 002's result, case by case. | Every case's `color` and `nsColor` name the same hue (e.g. `.modified` is orange in both). |
| file-system-git-004 | refresh-result-cases | Inspect the `GitStatusRefreshResult` declaration. | Exactly two cases exist, `.status(GitStatus)` and `.unavailable`; the type conforms to `Sendable`. |
| file-system-git-005 | observer-registration, observation-token-unregisters-on-release, weak-reference-in-cancellation-closure | `testDroppingTheObservationStopsDelivery`: register an observer, let its `GitStatusObservation` go out of scope, then call `refresh()` (`GitStatusProviderRefreshTests.swift`). | The dropped observer's callback is never invoked (the inverted `cancelled` expectation is not fulfilled). |
| file-system-git-006 | broadcast-to-all-observers, main-actor-delivery | `testRefreshDeliversStatusesOnTheMainThread`: register one observer on a real git checkout with an untracked file, call `refresh()` (`GitStatusProviderRefreshTests.swift`). | The observer is invoked with `Thread.isMainThread == true` and receives `.status(status)` where `status.files["new.txt"] == .untracked`. |
| file-system-git-007 | success-delivers-status-and-logs | Same setup as vector 006. | The delivered result is `.status`, and `logger.info` fires once naming `1` file and `0` directories (`status.files.count`, `status.directories.count`). |
| file-system-git-008 | failure-yields-unavailable-never-empty | `testAFailedStatusIsReportedAsUnavailableRatherThanAnEmptyStatus`: construct a provider on a `repoRoot` that does not exist, call `refresh()` (`GitStatusProviderRefreshTests.swift`). | The observer receives `.unavailable`, never `.status(.empty)` or any other status value. |
| file-system-git-009 | cancellation-yields-unavailable | Construct a `client` whose `status(in:)` throws `CancellationError`; call `refresh()`. | The observer receives `.unavailable`; no `error`-level log is emitted for this call. |
| file-system-git-010 | error-log-omits-git-output | Construct a `client` whose `status(in:)` throws `GitClientError.commandFailed(verb: "status", exitStatus: 128, standardError: "fatal: secret-looking-path")`; call `refresh()`. | The `error`-level log message contains `commandFailed(verb: status, exitStatus: 128)` and does not contain the string `"secret-looking-path"`. |
| file-system-git-011 | immediate-start-when-idle | Call `refresh()` on a newly constructed provider with no run in flight. | `client.status(in:)` is invoked without waiting for any other call; the provider's internal `isRunning` becomes `true` synchronously before the run's `await`. |
| file-system-git-012 | coalesced-overlap, bounded-burst-cost | Call `refresh()` five times in rapid succession while the first call's `client.status(in:)` is still awaiting. | `client.status(in:)` is invoked exactly twice in total for the burst — once for the in-flight run, once for the single coalesced follow-up — never five times. |
| file-system-git-013 | thread-safe-mutable-state | From multiple concurrent tasks, interleave calls to `observe(_:)` and `refresh()` on one provider instance. | No crash or data race occurs; the final registered-observer count equals the number of tokens still held, matching serialized access through `state.withLock`. |
| file-system-git-014 | injectable-client-with-shared-default | Construct `GitStatusProvider(repoRoot: someURL)` with no `client` argument, and separately `GitStatusProvider(repoRoot: someURL, client: fakeClient)`. | The first instance's `client` is `GitClient.shared`; the second instance's `client` is `fakeClient`, and no call through it reaches a real subprocess unless `fakeClient` chooses to spawn one. |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repoRoot` (parameter to `init`) | `URL` | none — required | The checkout this provider reports on; fixed for the instance's lifetime. |
| `client` (parameter to `init`) | `GitClient` | `.shared` | Injectable git client; a test substitutes a differently-configured or fake instance. |

Neither given source file reads an environment variable or a settings key
directly. The git executable path, timeout, and submodule handling are
`GitClientConfiguration` concerns reached only indirectly, through whichever
`client` is injected.

## Deep Linking

Not applicable: neither `GitFileStatus+Color.swift` nor
`GitStatusProvider.swift` defines a URL scheme, route, or navigation
destination.

## Localization

Not applicable: neither source file produces a user-facing string.
`GitFileStatus+Color.swift` returns colors, not text; `GitStatusProvider.swift`'s
only string output is composed for `os.Logger` (see Logging below), which is
diagnostic text, not user-facing text.

## Accessibility Options

Not applicable: neither source file renders anything —
`GitFileStatus+Color.swift` supplies color values and `GitStatusProvider.swift`
supplies status data to a caller (e.g. the outline view that pairs each
color with `GitFileStatus.displayCharacter`); Reduce Motion, Increase
Contrast, and Differentiate Without Color are concerns for that rendering
layer, with nothing in either given file to opt into or out of.

## Feature Flags

Not applicable: neither source file contains a feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: neither source file makes an analytics or event-tracking
call.

## Privacy

Not applicable: the only data either file touches is a local
repository-relative file path and a git status letter, both already visible
to the user in the file browser; neither file reads, stores, or transmits a
credential, token, or personal data.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset,
via the shared `Loggable` protocol) | Category: `GitStatusProvider`

| Event | Level | Message |
|-------|-------|---------|
| `client.status(in:)` succeeds | info | `Git status: <fileCount> files, <dirCount> directories` |
| `client.status(in:)` throws any error other than `CancellationError` | error | `Git status failed for <repoRoot.path>: <logDescription or type name>` |

`GitFileStatus+Color.swift` performs no logging of its own.

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

## Design Decisions

**Decision**: Overlapping `refresh()` calls coalesce into at most one
queued follow-up run, tracked with a single `isQueued` boolean rather than a
counter or a queue of distinct requests.
**Rationale**: Per the doc comment, "a burst of N requests costs two git
processes rather than N" — a run already in flight started before any
request that arrives during it, so it cannot be the answer to that request;
one trailing run answers every such caller, and nothing distinguishes one
pending caller's interest from another's.
**Approved**: pending

**Decision**: A `CancellationError` from `client.status(in:)` is reported
as `.unavailable`, the same result used for every other failure, rather
than being rethrown or given its own case.
**Rationale**: The doc comment states the reasoning directly: cancellation
is "not a status failure... but the one thing it is certainly not is
evidence that the tree is clean," so treating it as "we do not know" rather
than rethrowing keeps every caller of `load` on one simple, non-throwing
result type.
**Approved**: pending

**Decision**: The error-level log built in `load`'s failure branch never
uses `error.localizedDescription`, and for a `GitClientError` uses
`logDescription` instead of `errorDescription`.
**Rationale**: `errorDescription` interpolates `GitClientError.commandFailed`'s
`standardError` field, which is git's own output; the source comment states
the branch's logging rule plainly: "OSLog records what was called, never
what git said."
**Approved**: pending

**Decision**: `GitFileStatus` gets two color properties, `color` (SwiftUI)
and `nsColor` (AppKit), that must be kept in semantic agreement, rather than
one canonical color type both frameworks convert from.
**Rationale**: SwiftUI's `Color` and AppKit's `NSColor` are not
interchangeable for the callers this extension serves; the doc comment
frames the duplication explicitly as "two spellings of one fact rather than
two facts" so that whichever framework draws the badge, red still means
deleted.
**Approved**: pending

**Decision**: The cancellation closure captured by `observe(_:)` holds the
provider weakly, and unregistration happens only through a token's
`deinit`, never through an explicit `removeObserver` method.
**Rationale**: Per the doc comment, this is "modelled as a token rather
than an addObserver/removeObserver pair so a consumer cannot forget the
second half — the compiler's lifetime rules do the unregistering," and the
weak capture keeps a live registration from being the thing that keeps the
provider itself alive.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | Reliability |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |

Notes: separation-of-concerns passes because `GitStatusProvider` delegates
status computation entirely to `client.status(in:)`/`GitStatus.parse` and
delegates nothing about presentation to itself; the color mapping lives in
its own extension, independent of the broadcaster. unit-test-coverage is
partial because `GitStatusProviderRefreshTests.swift` exercises the three
core delivery paths (main-thread broadcast, unavailable-on-failure,
drop-stops-delivery) but has no test for the coalescing/queued-refresh path
(`coalesced-overlap`, `bounded-burst-cost`) or for `GitFileStatus+Color`'s
mapping at all. explicit-error-handling passes because every throw site in
`load` is caught and mapped onto `GitStatusRefreshResult.unavailable`, with
cancellation handled as its own branch rather than falling through the
generic catch. graceful-degradation passes because a failed status check
reports `.unavailable` rather than crashing or substituting an empty status,
letting a consumer keep its last-good badges. error-recovery is partial
because `GitStatusProvider` itself performs no retry or backoff after a
failure — recovery depends entirely on some caller invoking `refresh()`
again (an FSEvents burst, a menu command), not on anything this file does on
its own. secure-log-output passes because the failure branch is built from
`logDescription` (or the error's type name), explicitly never from
`error.localizedDescription` or `GitClientError.commandFailed`'s raw
`standardError` text.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
