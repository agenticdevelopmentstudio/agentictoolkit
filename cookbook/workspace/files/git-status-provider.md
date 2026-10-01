---
id: 9a4aa2a8-c01b-4cec-b789-6c89c100d8d3
title: Git Status Provider
domain: agentictoolkit://cookbook/workspace/files/git-status-provider
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/workspace/files/file-browser-view
- agentictoolkit://cookbook/workspace/files/file-tree-view
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

# Git Status Provider

## Overview

This component asks a git client for one repository's working-tree status
and broadcasts the result to every registered observer, on the UI thread.
One provider serves every pane watching a checkout, so a refresh answers
"everyone's badges," not just whoever triggered it; overlapping refresh
calls coalesce into at most one queued follow-up run rather than one process
per call. A failed or cancelled check is reported as an explicit
"unavailable" result rather than an empty status, because an empty status
and "we could not ask" are different facts a consumer must not confuse. A
companion status-to-color mapping is what the badges this provider's status
feeds actually paint with: it gives every status value a fixed hue,
represented once per color type the platform's UI layer(s) require, so that
whichever one draws the badge, red still means deleted.

## Behavioral Requirements

- **color-mapping-per-status**: Each status value MUST resolve to a fixed
  hue, expressed as a color value in the platform's primary UI color type:
  orange for modified, green for added and untracked, red for deleted, blue
  for renamed and copied, purple for conflicted, and gray for ignored.
- **secondary-color-mapping-per-status**: On a platform whose UI layer ships
  more than one native color type, the same status-to-hue mapping MUST also
  be provided as a color value in each additional color type: orange for
  modified, green for added and untracked, red for deleted, blue for renamed
  and copied, purple for conflicted, and gray for ignored (see Platform
  Notes for the exact types used on Apple platforms).
- **color-representations-parity**: For every status value, every color
  representation the platform provides MUST name the same semantic hue
  (orange/orange, green/green, red/red, blue/blue, purple/purple,
  gray/gray) — two (or more) spellings of one fact rather than separate
  facts, so whichever UI layer draws a badge, red still means deleted.
- **refresh-result-cases**: The refresh-result type MUST provide exactly two
  cases, a status case wrapping the resulting status value and an
  unavailable case, and MUST be safe to share across concurrent observers.
- **observer-registration**: The observer-registration operation MUST
  register the supplied observer under a fresh UUID key so it receives
  every result the provider produces from the moment of registration
  onward, and MUST NOT replay any result delivered before it was
  registered.
- **observation-token-unregisters-on-release**: The observation token
  returned by the observer-registration operation MUST be the only way to
  stop receiving results; releasing it MUST remove the corresponding entry
  from the observers map, triggered automatically by the token's own
  deallocation rather than by a separate unregister call.
- **weak-reference-in-cancellation-closure**: The unregistration action
  associated with an observation token MUST hold a weak reference to the
  provider, so an outstanding, unreleased token MUST NOT keep the provider
  alive.
- **broadcast-to-all-observers**: A single refresh call's result MUST be
  delivered to every observer registered on the provider at delivery time,
  not only to whichever caller triggered the refresh.
- **ui-thread-delivery**: Every observer invocation MUST occur on the UI
  thread (see Platform Notes for the exact mechanism used on Apple
  platforms).
- **immediate-start-when-idle**: A refresh call made while no run is in
  flight (`isRunning == false`) MUST set `isRunning` and start a new run
  immediately, without waiting for any other event.
- **coalesced-overlap**: A refresh call made while a run is already in
  flight MUST NOT start a second concurrent status check; it MUST instead
  set `isQueued` and return, leaving the in-flight run to trigger the
  follow-up after it finishes delivering.
- **bounded-burst-cost**: Any number of refresh calls that arrive while one
  run is in flight MUST be coalesced into at most one follow-up run,
  because `isQueued` is a single boolean rather than a counter — a burst of
  N overlapping calls MUST cost at most two status-check invocations in
  total, never N.
- **success-delivers-status-and-logs**: When the underlying status check
  succeeds, the refresh operation MUST wrap the result in the status case,
  and MUST log one info-level message naming the resulting file and
  directory counts (see Logging, and Platform Notes for the exact privacy
  annotation used on Apple platforms).
- **cancellation-yields-unavailable**: When the underlying status check is
  cancelled, the refresh operation MUST return the unavailable case rather
  than propagating the cancellation, and MUST NOT emit an error-level log
  for that case — cancellation is reported as "we do not know," never
  treated as evidence the tree is clean.
- **failure-yields-unavailable-never-empty**: When the underlying status
  check fails for any reason other than cancellation, the refresh operation
  MUST return the unavailable case, never a default or empty status value,
  so a consumer cannot mistake "git could not be asked" for "the tree is
  clean".
- **error-log-omits-git-output**: The error-level log emitted on a
  non-cancellation failure MUST be built from a sanitized description of
  the underlying git-client error when the error originates from the git
  client, or from the error's type name otherwise, and MUST NOT use the
  error's full description or otherwise include git's raw standard-error
  text.
- **injectable-client-with-shared-default**: Construction MUST accept a git
  client and MUST default it to the shared git client instance when the
  caller supplies none.
- **thread-safe-mutable-state**: `observers`, `isRunning`, and `isQueued`
  MUST be read and written only under a single lock guarding all of the
  provider's mutable state, and the provider as a whole MUST be safe to
  share across concurrent callers on the strength of that discipline, since
  it holds no other mutable state (see Platform Notes for the exact locking
  primitive used on Apple platforms).

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
| file-system-git-001 | color-mapping-per-status | Evaluate the primary color mapping on `.modified`, `.added`, `.deleted`, `.renamed`, `.copied`, `.untracked`, `.ignored`, `.conflicted`. | Returns `.orange`, `.green`, `.red`, `.blue`, `.blue`, `.green`, `.gray`, `.purple` respectively. |
| file-system-git-002 | secondary-color-mapping-per-status | Evaluate the secondary color mapping on the same eight cases. | Returns the secondary color type's equivalents of orange, green, red, blue, blue, green, gray, purple respectively (see Platform Notes for the exact constants used on Apple platforms). |
| file-system-git-003 | color-representations-parity | Compare vector 001's result to vector 002's result, case by case. | Every case's color representations name the same hue (e.g. `.modified` is orange in every representation). |
| file-system-git-004 | refresh-result-cases | Inspect the refresh-result type's declaration. | Exactly two cases exist, a status case and an unavailable case; the type is safe to share across concurrent observers. |
| file-system-git-005 | observer-registration, observation-token-unregisters-on-release, weak-reference-in-cancellation-closure | Register an observer, let its observation token go out of scope, then trigger a refresh (confirmed by the provider's own test suite). | The dropped observer's callback is never invoked. |
| file-system-git-006 | broadcast-to-all-observers, ui-thread-delivery | Register one observer on a real git checkout with an untracked file, then trigger a refresh (confirmed by the provider's own test suite). | The observer is invoked on the UI thread and receives the status case, where `status.files["new.txt"] == .untracked`. |
| file-system-git-007 | success-delivers-status-and-logs | Same setup as vector 006. | The delivered result is the status case, and an info-level log fires once naming `1` file and `0` directories (`status.files.count`, `status.directories.count`). |
| file-system-git-008 | failure-yields-unavailable-never-empty | Construct a provider on a `repoRoot` that does not exist, then trigger a refresh (confirmed by the provider's own test suite). | The observer receives the unavailable case, never the status case wrapping an empty or any other status value. |
| file-system-git-009 | cancellation-yields-unavailable | Construct a git client whose status check is cancelled; trigger a refresh. | The observer receives the unavailable case; no error-level log is emitted for this call. |
| file-system-git-010 | error-log-omits-git-output | Construct a git client whose status check fails with a command-failure error (verb `status`, exit status 128, standard-error text `fatal: secret-looking-path`); trigger a refresh. | The error-level log message contains `commandFailed(verb: status, exitStatus: 128)` and does not contain the string `"secret-looking-path"`. |
| file-system-git-011 | immediate-start-when-idle | Trigger a refresh on a newly constructed provider with no run in flight. | The underlying status check is invoked without waiting for any other call; the provider's internal `isRunning` becomes `true` synchronously before the run suspends to await its result. |
| file-system-git-012 | coalesced-overlap, bounded-burst-cost | Trigger a refresh five times in rapid succession while the first call's underlying status check is still pending. | The underlying status check is invoked exactly twice in total for the burst — once for the in-flight run, once for the single coalesced follow-up — never five times. |
| file-system-git-013 | thread-safe-mutable-state | From multiple concurrent callers, interleave observer-registration and refresh calls on one provider instance. | No crash or data race occurs; the final registered-observer count equals the number of tokens still held, matching serialized access through the provider's guarding lock. |
| file-system-git-014 | injectable-client-with-shared-default | Construct a provider with no explicit git client, and separately construct one with a fake git client supplied. | The first instance's client is the shared git client; the second instance's client is the fake one supplied, and no call through it reaches a real subprocess unless the fake client chooses to spawn one. |

## Edge Cases

- **Null and empty input**: A `repoRoot` that does not exist, or is not
  inside a git repository, is not special-cased by this component; it is
  forwarded unchanged to the underlying status check, whose resulting error
  is caught by the generic branch and reported as the unavailable case
  (MUST, see `failure-yields-unavailable-never-empty`; confirmed by the
  provider's own test suite). Triggering a refresh while zero observers are
  registered still runs the underlying status check to completion — the
  delivery loop over the registered-observer collection simply iterates
  zero times — so the run's cost is paid with no observer ever told (MUST,
  matching `broadcast-to-all-observers`).
- **Boundary values**: `isQueued` is a single boolean, not a counter, so
  however many refresh calls arrive while a run is in flight, at most one
  follow-up run is owed; the boundary is exactly zero vs. one queued
  follow-up, never two or more (MUST, see `bounded-burst-cost`).
- **Concurrent access**: Registering an observer and triggering a refresh
  may be called concurrently from any thread; every read and write of
  `observers`, `isRunning`, and `isQueued` is serialized by the provider's
  guarding lock, so no interleaving can observe a torn state (MUST, see
  `thread-safe-mutable-state`). The order in which multiple observers
  registered on one provider are called for a given result is the
  iteration order over the registered-observer collection, which is not
  guaranteed to be insertion order or stable across calls (SHOULD NOT be
  relied upon by a consumer; the source makes no ordering promise across
  observers, only that every one of them is called).
- **Error states**: The distinct failure reasons the underlying git client
  can raise (executable not found, launch failed, timed out, command
  failed) are not distinguished from one another by this component; every
  one reaches the generic failure branch, is logged from a sanitized
  description of the error, and is reported as the unavailable case
  identically (MUST, see `failure-yields-unavailable-never-empty`,
  `error-log-omits-git-output`).
- **Offline or disconnected state**: Not applicable in the network sense —
  this component makes no network call; its only external dependency is
  the local status-check subprocess call, whose failure (including an
  unreachable or misconfigured git executable) is handled identically to
  the Error states above.
- **Cancellation and timeouts**: The refresh operation runs detached from
  its caller, so nothing external can cancel an in-flight refresh; the only
  cancellation path the refresh operation observes is a cancellation signal
  raised from within the underlying status check itself, which is reported
  as the unavailable case without an error log (MUST, see
  `cancellation-yields-unavailable`). A timeout — raised when git does not
  finish within the client's configured duration — is a distinct,
  non-cancellation case that falls to the generic failure branch instead,
  and is logged at error level like any other failure (MUST, see
  `failure-yields-unavailable-never-empty`).
- **Missing file or unreachable server**: A `repoRoot` that no longer exists
  on disk, or that points to a directory that is not a git repository,
  surfaces only as whatever error the underlying status check produces for
  that case; this component performs no existence or repository check of
  its own before calling it (MUST, handled identically to Error states
  above).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repoRoot` (construction parameter) | a file-system location | none — required | The checkout this provider reports on; fixed for the instance's lifetime. |
| `client` (construction parameter) | the git-client abstraction | the shared instance | Injectable git client; a test substitutes a differently-configured or fake instance. |

Neither this component nor its companion color mapping reads an environment
variable or a settings key directly. The git executable path, timeout, and
submodule handling are configuration concerns reached only indirectly,
through whichever client is injected.

## Deep Linking

Not applicable: neither this component nor its companion color mapping
defines a URL scheme, route, or navigation destination.

## Localization

Not applicable: neither this component nor its companion color mapping
produces a user-facing string. The color mapping returns colors, not text;
this component's only string output is composed for its diagnostic log (see
Logging below), which is diagnostic text, not user-facing text.

## Accessibility Options

Not applicable: neither this component nor its companion color mapping
renders anything — the color mapping supplies color values and this
component supplies status data to a caller (e.g. the tree view that pairs
each color with the status's display character); Reduce Motion, Increase
Contrast, and Differentiate Without Color are concerns for that rendering
layer, with nothing in either to opt into or out of.

## Feature Flags

Not applicable: neither this component nor its companion color mapping
contains a feature-flag or build-configuration check of any kind.

## Analytics

Not applicable: neither this component nor its companion color mapping
makes an analytics or event-tracking call.

## Privacy

Not applicable: the only data either touches is a local repository-relative
file path and a git status letter, both already visible to the user in the
file browser; neither reads, stores, or transmits a credential, token, or
personal data.

## Logging

Subsystem: the host application's bundle identifier (falls back to the
literal string `"nil"` if unset; see Platform Notes for the exact mechanism
used on Apple platforms) | Category: `GitStatusProvider`

| Event | Level | Message |
|-------|-------|---------|
| the underlying status check succeeds | info | `Git status: <fileCount> files, <dirCount> directories` |
| the underlying status check fails with any error other than a cancellation | error | `Git status failed for <repoRoot.path>: <sanitized error description or type name>` |

The companion color mapping performs no logging of its own.

## Platform Notes

- **SwiftUI**: The sources are
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitStatusProvider.swift`
  and `GitFileStatus+Color.swift` in the same directory, alongside their
  collaborators `GitClient.swift`, `GitStatus.swift`, `GitFileStatus.swift`,
  and `GitClientError.swift` (all under `Core/Git`). Both files are plain
  Swift with no SwiftUI-specific API beyond the color extension's
  `SwiftUI.Color` property; see the AppKit/UIKit note below for the
  concurrency, locking, and logging mechanisms the shipped implementation
  actually uses.
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
- **AppKit / UIKit**: The provider uses `OSAllocatedUnfairLock` to guard its
  mutable state (`observers`, `isRunning`, `isQueued`), an unstructured
  `Task` plus `MainActor.run` for the fetch-then-deliver cycle, and
  `os.Logger` via the shared `Loggable` protocol for logging, with
  `Bundle.main.bundleIdentifier` (falling back to the literal string
  `"nil"` if unset) as the log subsystem. The color extension is plain
  computed properties: `color: SwiftUI.Color` for the primary mapping and
  `nsColor: AppKit.NSColor` for the secondary one; the exact hue constants
  are `.systemOrange`, `.systemGreen` (added and untracked), `.systemRed`,
  `.systemBlue` (renamed and copied), `.systemPurple`, and `.systemGray`,
  paired with SwiftUI's `.orange`, `.green`, `.red`, `.blue`, `.purple`, and
  `.gray`. The error-level log message is built from
  `GitClientError.logDescription` when the failure originates from the git
  client, or from the error's type name otherwise — explicitly never from
  `errorDescription` or `error.localizedDescription`, since
  `errorDescription` interpolates the command-failure case's raw
  `standardError` text. The observation token's unregistration closure
  captures the provider weakly and fires from the token's own `deinit`, so a
  consumer cannot forget to unregister and an outstanding token cannot keep
  the provider alive. Nothing here is tied to AppKit specifically beyond the
  `NSColor` type; a UIKit (iOS) port needs only `UIColor`, one type, which
  removes the duplication the same way Compose does, and the provider itself
  ports unchanged.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/` |

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

**Decision**: A cancellation of the underlying status check is reported as
the unavailable case, the same result used for every other failure, rather
than being propagated or given its own case.
**Rationale**: The doc comment states the reasoning directly: cancellation
is "not a status failure... but the one thing it is certainly not is
evidence that the tree is clean," so treating it as "we do not know" rather
than propagating the cancellation keeps every caller of the refresh
operation on one simple, non-throwing result type.
**Approved**: pending

**Decision**: On Apple platforms, the error-level log built in the refresh
operation's failure branch never uses the error's full localized
description, and for a git-client error uses a sanitized description
property instead of the error's full description property.
**Rationale**: The full-description property interpolates the
command-failure case's raw standard-error text, which is git's own output;
the source comment states the branch's logging rule plainly: "OSLog
records what was called, never what git said."
**Approved**: pending

**Decision**: On Apple platforms, `GitFileStatus` gets two color
properties, `color` (SwiftUI) and `nsColor` (AppKit), that must be kept in
semantic agreement, rather than one canonical color type both frameworks
convert from.
**Rationale**: SwiftUI's `Color` and AppKit's `NSColor` are not
interchangeable for the callers this extension serves; the doc comment
frames the duplication explicitly as "two spellings of one fact rather than
two facts" so that whichever framework draws the badge, red still means
deleted.
**Approved**: pending

**Decision**: The observation token's unregistration is driven by the
token's own release rather than an explicit `removeObserver` method; on
Apple platforms this is implemented by having the unregistration closure
hold the provider weakly and fire from the token's `deinit`.
**Rationale**: Per the doc comment, this is "modelled as a token rather
than an addObserver/removeObserver pair so a consumer cannot forget the
second half — the compiler's lifetime rules do the unregistering," and
holding the provider weakly keeps a live registration from being the thing
that keeps the provider itself alive.
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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/files/. |
