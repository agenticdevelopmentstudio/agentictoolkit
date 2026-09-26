---
id: 7ae3de90-35f2-415c-93c7-cf579689e438
title: ProjectCheckout
domain: agentictoolkit://cookbook/macos/features/projects/project-checkout
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The directory a project opens a tab group in: the repository''s own checkout
  or a linked worktree, identified by a symlink-resolved path.'
platforms:
- swift
- macos
tags:
- git
- projects
- checkout
- worktree
- value-type
- sendable
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/projects/branch-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectCheckoutTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitWorktree.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectCheckout

## Overview

`ProjectCheckout` is the value the project controller opens one tab group
per: either a repository's own checkout or one of its linked git worktrees
(`ProjectCheckout.swift`). It is a small `Hashable`, `Sendable`
value type holding a symlink-resolved `directory`, an optional `branch`, and
an `isMain` flag, plus two derived values — a stable, path-derived
`identifier` and a `displayName` that prefers the branch name. Its one
static factory, `checkouts(from:)`, projects a `GitWorktree` list (as
produced by `GitWorktree.parse(porcelain:)`) into the subset of
`ProjectCheckout` values the project controller can actually open a tab in.

## Behavioral Requirements

- **checkout-identity-fields**: `ProjectCheckout` MUST expose exactly three
  stored properties — `directory: URL`, `branch: String?`, and
  `isMain: Bool` — and no others (`ProjectCheckout.swift`).
- **symlink-resolved-directory**: `init(directory:branch:isMain:)` MUST set
  `directory` to `directory.resolvingSymlinksInPath()` of the value the
  caller passed in, never the caller's unresolved `URL` (`ProjectCheckout.swift`).
- **resolution-not-standardization**: `init(directory:branch:isMain:)` MUST
  resolve `directory` with `resolvingSymlinksInPath()` rather than
  `standardizedFileURL`, so that a path reached through a symlink and the
  same path reached through the symlink's target resolve to one identical
  `directory` value; `resolvingSymlinksInPath()`'s normalization of `.` and
  `..` segments MUST also apply, since resolving subsumes standardizing
  (`ProjectCheckout.swift`).
- **hashable-includes-all-fields**: Two `ProjectCheckout` values MUST
  compare equal, and MUST hash identically, only when their `directory`,
  `branch`, and `isMain` are all equal; `ProjectCheckout` declares no custom
  `==` or `hash(into:)`, so `Hashable` conformance is derived from all three
  stored properties (`ProjectCheckout.swift`).
- **sendable-value-type**: `ProjectCheckout` MUST be safe to read, compare,
  hash, and pass across concurrency domains with no synchronization, since it
  is declared `Sendable`, every stored property is itself immutable (`let`)
  and `Sendable` (`URL`, `String?`, `Bool`), and it has no reference-typed or
  mutable state (`ProjectCheckout.swift`).
- **path-derived-identifier**: `identifier` MUST compute a djb2 hash over
  `directory.path`'s UTF-8 bytes — seeded at `5381`, updated per byte as
  `hash = (hash &* 33) &+ UInt64(byte)` — and MUST render the result as a
  hexadecimal string via `String(hash, radix: 16)` (`ProjectCheckout.swift`).
- **identifier-ignores-branch-and-main-flag**: `identifier` MUST depend only
  on `directory` and MUST NOT vary with `branch` or `isMain`, so a checkout
  keeps the same `identifier` across a branch switch on the same directory
  (`ProjectCheckout.swift`).
- **display-name-prefers-branch**: `displayName` MUST return `branch` when
  it is non-nil, and MUST return `directory.lastPathComponent` when `branch`
  is `nil` (`ProjectCheckout.swift`).
- **bare-worktrees-excluded**: `checkouts(from:)` MUST exclude every
  `GitWorktree` whose `isBare` is `true` from its returned array, because a
  bare entry has no working directory to open a tab in
  (`ProjectCheckout.swift`).
- **checkouts-preserve-order**: `checkouts(from:)` MUST return the
  surviving, non-bare worktrees in the same relative order they appear in
  the `worktrees` argument (`ProjectCheckout.swift`).
- **checkouts-projection-is-lossy-by-design**: `checkouts(from:)` MUST build
  each `ProjectCheckout` from only its source `GitWorktree`'s `directory`,
  `branch`, and `isMain`; the source `GitWorktree`'s `head` and `isDetached`
  values MUST NOT be carried into the produced `ProjectCheckout` in any form
  (`ProjectCheckout.swift`).

## Appearance

Not applicable — this is a value type, not a visual component.

## States

Not applicable — this is a value type, not a visual component.

## Accessibility

Not applicable — this is a value type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-checkout-001 | path-derived-identifier, identifier-ignores-branch-and-main-flag | `testTheIdentifierIsStableAndPathDerived`: `first = ProjectCheckout(directory: "/repo/a", branch: "x", isMain: false)`, `same = ProjectCheckout(directory: "/repo/a/", branch: "y", isMain: true)`, `other = ProjectCheckout(directory: "/repo/b", branch: "x", isMain: false)` (`ProjectCheckoutTests.swift`). | `first.identifier == same.identifier`; `first.identifier != other.identifier`; every character of `first.identifier` satisfies `isHexDigit`. |
| git-client-projects-project-checkout-002 | resolution-not-standardization, path-derived-identifier | `testTheIdentifierNormalizesDotDotSegments`: `first = ProjectCheckout(directory: "/repo/x/../a", branch: "x", isMain: false)`, `same = ProjectCheckout(directory: "/repo/a", branch: "y", isMain: true)`. | `first.identifier == same.identifier`. |
| git-client-projects-project-checkout-003 | symlink-resolved-directory, resolution-not-standardization, hashable-includes-all-fields, path-derived-identifier | `testASymlinkedPathIsTheSameCheckoutAsItsTarget`: a real temporary directory `target`, and `link` symlinked to `target`; `viaLink = ProjectCheckout(directory: link, branch: "main", isMain: true)`, `viaTarget = ProjectCheckout(directory: target, branch: "main", isMain: true)`. | `viaLink.directory == viaTarget.directory`; `viaLink.identifier == viaTarget.identifier`; `Set([viaLink, viaTarget]).count == 1`. |
| git-client-projects-project-checkout-004 | display-name-prefers-branch | `testADetachedCheckoutIsNamedAfterItsFolder`: `checkout = ProjectCheckout(directory: "/repo/wt-spike", branch: nil, isMain: false)`. | `checkout.displayName == "wt-spike"`. |
| git-client-projects-project-checkout-005 | bare-worktrees-excluded, checkouts-preserve-order, display-name-prefers-branch | `testCheckoutsSkipBareEntriesAndKeepOrder`: `main` (`/repo`, branch `main`, `isMain: true`, `isBare: false`), `bare` (`/repo.git`, branch `nil`, `isBare: true`), `linked` (`/repo/.claude/worktrees/tabs`, branch `tabs`, `isBare: false`), passed to `checkouts(from:)` in that order. | `checkouts.map(\.displayName) == ["main", "tabs"]`; `checkouts.map(\.isMain) == [true, false]`; the `bare` entry produces no `ProjectCheckout`. |
| git-client-projects-project-checkout-006 | checkouts-projection-is-lossy-by-design | Same input as vector 005: `linked` carries `head: "def"` and `isDetached: false` on the source `GitWorktree`. | The `ProjectCheckout` produced for `linked` has no `head` or `isDetached` property to inspect at all — `ProjectCheckout` declares no such stored property (`ProjectCheckout.swift`). |
| git-client-projects-project-checkout-007 | hashable-includes-all-fields, identifier-ignores-branch-and-main-flag | Not exercised by an existing test; derived directly from the type declaration: `a = ProjectCheckout(directory: "/repo/a", branch: "main", isMain: true)`, `b = ProjectCheckout(directory: "/repo/a", branch: "other", isMain: true)` (`ProjectCheckout.swift`, no custom `Equatable`/`Hashable`). | `a == b` is `false` and `a.hashValue != b.hashValue` in the general case, while `a.identifier == b.identifier` is `true` — the same directory yields one `identifier` but two distinct, unequal `ProjectCheckout` values because `branch` differs. |

## Edge Cases

- **Null and empty input**: `branch == nil` MUST fall back `displayName` to
  `directory.lastPathComponent` rather than producing an empty or placeholder
  string (`ProjectCheckout.swift`). MUST. An empty `worktrees`
  array passed to `checkouts(from:)` MUST return an empty array, since
  `filter` and `map` over an empty collection produce no elements
  (`ProjectCheckout.swift`). MUST.
- **Boundary values**: A `directory` whose `path` is the single-character
  root `/` MUST still produce a deterministic, non-empty hexadecimal
  `identifier`, since the djb2 loop only iterates over
  `directory.path.utf8` and has no special case for a short path
  (`ProjectCheckout.swift`). MUST.
- **Concurrent access**: `ProjectCheckout` MUST be readable, comparable, and
  hashable concurrently from multiple threads or actors with no
  synchronization, because it is `Sendable`, every stored property is
  immutable, and `identifier`/`displayName` are pure computations with no
  shared mutable state (`ProjectCheckout.swift`). MUST.
  `checkouts(from:)` is a `static func` with no shared state of its own, so
  concurrent calls on different `worktrees` arguments MUST NOT interfere
  with one another (`ProjectCheckout.swift`). MUST.
- **Error states**: `resolvingSymlinksInPath()` is a non-throwing API, and
  `init(directory:branch:isMain:)` has no `throws` and no error-handling
  path at all; when `directory` names a path that does not exist on disk,
  the initializer MUST NOT raise or surface an error — it stores whatever
  `resolvingSymlinksInPath()` returns, which is a best-effort result rather
  than a validated one (`ProjectCheckout.swift`). MUST (this is
  a fact about a non-throwing API, not a swallowed error — there is no
  throwing call here to swallow).
- **Offline or disconnected state**: Not applicable — `ProjectCheckout.swift`
  makes no network call; `directory`, `branch`, and `isMain` are supplied by
  the caller or derived from a `GitWorktree` value already read from local
  disk (`ProjectCheckout.swift`, entire file).
- **Duplicate worktree entries**: When `worktrees` passed to
  `checkouts(from:)` contains two entries with the same `directory`,
  `checkouts(from:)` MUST produce two separate `ProjectCheckout` values
  rather than deduplicating them, since `.map` performs a strict one-to-one
  projection with no `Set` or dedup step (`ProjectCheckout.swift`). MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directory` (init parameter) | `URL` | none — required | Directory this checkout represents; stored as `directory.resolvingSymlinksInPath()`, never the caller's unresolved value. |
| `branch` (init parameter) | `String?` | none — required, may be `nil` | The checkout's live branch name, or `nil` when the worktree is in a detached-HEAD state. |
| `isMain` (init parameter) | `Bool` | none — required | Whether this checkout is the repository's main worktree, typically forwarded from `GitWorktree.isMain`. |
| `worktrees` (`checkouts(from:)` parameter) | `[GitWorktree]` | none — required | The full worktree list, typically `GitWorktree.parse(porcelain:)`'s output, projected into `ProjectCheckout` values with bare entries removed. |

`ProjectCheckout.swift` reads no environment variable and no persisted
settings key; every value it holds is supplied directly by its caller.

## Deep Linking

Not applicable: `ProjectCheckout.swift` defines no URL scheme, route, or
navigation destination.

## Localization

Not applicable: `ProjectCheckout.swift` produces no user-facing string;
`displayName` returns either the caller-supplied `branch` name or a
filesystem path component, both data values passed through unchanged, not
localized UI text.

## Accessibility Options

Not applicable: `ProjectCheckout.swift` renders nothing; Reduce Motion,
Increase Contrast, and Differentiate Without Color have no surface here to
apply to.

## Feature Flags

Not applicable: `ProjectCheckout.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `ProjectCheckout.swift` makes no analytics or
event-tracking call.

## Privacy

- **Data collected**: A `ProjectCheckout` value holds the caller's local
  filesystem `directory` path and, when present, the checkout's git
  `branch` name (`ProjectCheckout.swift`). Both are local
  workspace metadata the caller already possesses; `ProjectCheckout` does
  not read anything from disk beyond resolving `directory`'s symlinks.
- **Storage**: None — `ProjectCheckout.swift` persists nothing; a value
  lives only as long as the caller retains it in memory.
- **Transmission**: None — `ProjectCheckout.swift` makes no network call
  and transmits nothing.
- **Retention**: Not applicable — `ProjectCheckout.swift` holds no state
  beyond the single value's lifetime; retention of any `ProjectCheckout` the
  caller keeps is entirely the caller's responsibility.

## Logging

Not applicable: `ProjectCheckout.swift` makes no logging call of any kind.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift`,
  using only Foundation's `URL` (`resolvingSymlinksInPath()`,
  `lastPathComponent`, `path`) and the sibling type `GitWorktree` from
  `packages/apple/AgenticToolkit/Core/Git/GitWorktree.swift`; nothing here is
  SwiftUI-specific — the type has no view and no observable state, and is
  used elsewhere purely as a `Hashable`/`Sendable` identity for tab groups.
- **Compose**: Represent as a Kotlin `data class ProjectCheckout(val
  directory: File, val branch: String?, val isMain: Boolean)`, resolving
  `directory` in a secondary constructor or factory function with
  `File.canonicalFile`, the closest Kotlin/JVM equivalent of
  `resolvingSymlinksInPath()` in that it both resolves symlinks and
  normalizes `.`/`..` segments in one call. A Kotlin `data class` derives
  `equals`/`hashCode` over every constructor property automatically, which
  matches `hashable-includes-all-fields` without extra code. Compute
  `identifier` with the identical djb2 loop over
  `directory.path.toByteArray(Charsets.UTF_8)`, formatted with
  `java.lang.Long.toHexString`.
- **React/Web**: A browser has no filesystem, symlink, or worktree concept;
  a faithful port only exists in a Node-hosted process. Represent
  `ProjectCheckout` as a small immutable object (`{ directory: string;
  branch: string | null; isMain: boolean }`), resolve `directory` with
  `fs.realpathSync`, Node's equivalent of `resolvingSymlinksInPath()`, and
  compute `identifier` with the same djb2 loop over
  `Buffer.from(directory, "utf8")`, converting the running hash to a hex
  string. Because JavaScript object identity is reference-based, port
  `hashable-includes-all-fields` explicitly — a value-equality helper, or a
  `Map` keyed on a composite string of `directory`, `branch`, and `isMain`
  — rather than relying on `===`.
- **AppKit / UIKit**: Identical to the SwiftUI note — the type is
  UI-framework-independent Foundation code. An AppKit consumer uses it
  exactly as the macOS project controller does today, as `Set` membership
  and dictionary keys mapping checkouts to open tab groups; an iOS port has
  no analogous "worktree" concept unless a UIKit-based checkout picker is
  built on top of it separately.
- **WinUI 3**: Port as a C# `readonly record struct ProjectCheckout(string
  Directory, string? Branch, bool IsMain)`; a `record struct` synthesizes
  `Equals`/`GetHashCode` over all three properties automatically, matching
  `hashable-includes-all-fields` with no extra code. There is no single
  .NET call that both resolves a symlink and normalizes `.`/`..` segments
  the way `resolvingSymlinksInPath()` does, so chain
  `System.IO.Path.GetFullPath` (normalization) with
  `new DirectoryInfo(path).ResolveLinkTarget(returnFinalTarget: true)`
  (symlink resolution) in the constructor. Compute `Identifier` as a
  read-only property running the same djb2 loop over
  `System.Text.Encoding.UTF8.GetBytes(Directory)`, formatted with
  `.ToString("x")`. Nothing here touches `Windows.Storage` (this is not
  packaged-app storage) or `Task`/`async` (nothing here is asynchronous or
  networked).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift` |

## Design Decisions

**Decision**: `init(directory:branch:isMain:)` resolves `directory` with
`resolvingSymlinksInPath()` rather than `standardizedFileURL`.
**Rationale**: The doc comment states the two sides being compared reach a
directory by different routes — `git worktree list` prints the fully
resolved path while a workspace's directory comes from the path the user
gave — so only resolving symlinks (which subsumes standardizing `.`/`..`
too) makes every `Set` lookup and dictionary key pairing them succeed
(`ProjectCheckout.swift`).
**Approved**: pending

**Decision**: `identifier` is derived only from `directory`, deliberately
excluding `branch` and `isMain`.
**Rationale**: The doc comment states the identifier is "path-derived so a
checkout keeps its identity across branch switches" — a stable value for a
checkout-namespaced command id even as the checkout's live branch changes
(`ProjectCheckout.swift`).
**Approved**: pending

**Decision**: `checkouts(from:)` drops every `GitWorktree` whose `isBare` is
`true`, and does not carry `head` or `isDetached` into the `ProjectCheckout`
values it produces.
**Rationale**: The doc comment gives the reason for the bare exclusion
directly — "bare entries have no working directory to open a tab in" — and
the projection to just `directory`, `branch`, and `isMain` reflects that
`ProjectCheckout` only needs what identifies a tab-openable location, not
the full worktree record (`ProjectCheckout.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

Notes: separation-of-concerns passes because `ProjectCheckout.swift` defines
only an identity/value type and a pure projection function — it has no
dependency on any UI framework, view controller, or presentation code, and
the project controller's tab-grouping policy that consumes it lives entirely
in other files. unit-test-coverage passes because
`ProjectCheckoutTests.swift` exercises the bare-entry filter and order
preservation, detached-checkout naming, identifier stability and path
derivation (including `..` normalization), and symlink-to-target identity
across both `directory` equality and `Set` membership. explicit-error-handling
passes because `ProjectCheckout.swift` contains no throwing call and no
forced unwrap to mishandle — `displayName`'s only optional handling is a
plain `??` nil-coalescing expression, and `resolvingSymlinksInPath()` is a
non-throwing API, so there is no error path capable of being silently
swallowed.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
