---
id: 7ae3de90-35f2-415c-93c7-cf579689e438
title: Project Checkout
domain: agentictoolkit://cookbook/workspace/projects/project-checkout
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/branch-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectCheckoutTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitWorktree.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Checkout

## Overview

A project checkout is the value the project controller opens one tab group
per: either a repository's own checkout or one of its linked git worktrees.
It is a small, comparable, concurrency-safe value holding a symlink-resolved
`directory`, an optional `branch` name, and an `isMain` flag, plus two
derived values — a stable, path-derived `identifier` and a `displayName`
that prefers the branch name. One factory operation projects a list of
worktree records (as parsed from `git worktree list --porcelain` output)
into the subset of checkout values that can actually be opened in a tab.

## Behavioral Requirements

- **checkout-identity-fields**: A checkout MUST expose exactly three
  fields — `directory` (a location value), `branch` (a string, optional),
  and `isMain` (a boolean) — and no others.
- **symlink-resolved-directory**: Creating a checkout MUST set `directory`
  to the symlink-resolved form of the location the caller passed in, never
  the caller's unresolved value.
- **resolution-not-standardization**: Creating a checkout MUST resolve
  `directory` by fully resolving symlinks rather than only normalizing the
  path, so that a path reached through a symlink and the same path reached
  through the symlink's target resolve to one identical `directory` value;
  normalization of `.` and `..` segments MUST also apply, since symlink
  resolution subsumes normalization.
- **hashable-includes-all-fields**: Two checkouts MUST compare equal, and
  MUST produce the same hash, only when their `directory`, `branch`, and
  `isMain` are all equal; equality and hashing are derived from all three
  fields, with no custom override that would exclude any of them.
- **value-type-concurrency-safety**: A checkout MUST be safe to read,
  compare, hash, and pass across concurrency domains with no
  synchronization, since every field is immutable and holds only
  concurrency-safe data, and the value has no reference-typed or mutable
  state.
- **path-derived-identifier**: `identifier` MUST compute a djb2 hash over
  the UTF-8 bytes of `directory`'s path string — seeded at `5381`, updated
  per byte as `hash = (hash * 33) + byte` using wrapping (overflow-safe)
  arithmetic — and MUST render the result as a lowercase hexadecimal
  string.
- **identifier-ignores-branch-and-main-flag**: `identifier` MUST depend only
  on `directory` and MUST NOT vary with `branch` or `isMain`, so a checkout
  keeps the same `identifier` across a branch switch on the same directory.
- **display-name-prefers-branch**: `displayName` MUST return `branch` when
  it is present, and MUST return the last path component of `directory`
  when `branch` is absent.
- **bare-worktrees-excluded**: The checkout projection MUST exclude every
  worktree record whose `isBare` is `true` from its returned list, because a
  bare entry has no working directory to open a tab in.
- **checkouts-preserve-order**: The checkout projection MUST return the
  surviving, non-bare worktrees in the same relative order they appear in
  the input list.
- **checkouts-projection-is-lossy-by-design**: The checkout projection MUST
  build each checkout from only its source worktree record's `directory`,
  `branch`, and `isMain`; the source record's `head` and `isDetached` values
  MUST NOT be carried into the produced checkout in any form.

## Appearance

Not applicable — this is a value type, not a visual component.

## States

Not applicable — this is a value type, not a visual component.

## Accessibility

Not applicable — this is a value type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-checkout-001 | path-derived-identifier, identifier-ignores-branch-and-main-flag | Checkouts: `first` (directory `/repo/a`, branch `x`, isMain `false`); `same` (directory `/repo/a/`, branch `y`, isMain `true`); `other` (directory `/repo/b`, branch `x`, isMain `false`). | `first`'s identifier equals `same`'s identifier; `first`'s identifier differs from `other`'s identifier; every character of `first`'s identifier is a hexadecimal digit. |
| git-client-projects-project-checkout-002 | resolution-not-standardization, path-derived-identifier | Checkouts: `first` (directory `/repo/x/../a`, branch `x`, isMain `false`); `same` (directory `/repo/a`, branch `y`, isMain `true`). | `first`'s identifier equals `same`'s identifier. |
| git-client-projects-project-checkout-003 | symlink-resolved-directory, resolution-not-standardization, hashable-includes-all-fields, path-derived-identifier | A real directory `target`, and `link` symlinked to `target`; checkouts `viaLink` (directory `link`, branch `main`, isMain `true`) and `viaTarget` (directory `target`, branch `main`, isMain `true`). | `viaLink`'s directory equals `viaTarget`'s directory; `viaLink`'s identifier equals `viaTarget`'s identifier; collecting `viaLink` and `viaTarget` into a set yields exactly one element. |
| git-client-projects-project-checkout-004 | display-name-prefers-branch | A checkout with directory `/repo/wt-spike`, branch absent, isMain `false`. | The checkout's display name is `"wt-spike"`. |
| git-client-projects-project-checkout-005 | bare-worktrees-excluded, checkouts-preserve-order, display-name-prefers-branch | Worktree records, in order: `main` (`/repo`, branch `main`, isMain `true`, isBare `false`); `bare` (`/repo.git`, branch absent, isBare `true`); `linked` (`/repo/.claude/worktrees/tabs`, branch `tabs`, isBare `false`) — projected into checkouts. | The resulting checkouts' display names, in order, are `"main"` then `"tabs"`; their isMain values, in order, are `true` then `false`; the `bare` entry produces no checkout. |
| git-client-projects-project-checkout-006 | checkouts-projection-is-lossy-by-design | Same input as vector 005: the `linked` worktree record additionally carries a head commit value of `"def"` and a detached-HEAD flag of `false`. | The checkout produced for `linked` has no head-commit or detached-HEAD field to inspect at all — the checkout's field set has no such member. |
| git-client-projects-project-checkout-007 | hashable-includes-all-fields, identifier-ignores-branch-and-main-flag | Not exercised by an existing test; derived directly from the definition: checkouts `a` (directory `/repo/a`, branch `main`, isMain `true`) and `b` (directory `/repo/a`, branch `other`, isMain `true`), with no custom equality or hashing override. | `a` equals `b` is `false` and their hashes differ in the general case, while `a`'s identifier equals `b`'s identifier is `true` — the same directory yields one identifier but two distinct, unequal checkout values because `branch` differs. |

## Edge Cases

- **Null and empty input**: `branch` being absent MUST fall back
  `displayName` to the last path component of `directory` rather than
  producing an empty or placeholder string. MUST. An empty list of worktree
  records passed to the checkout projection MUST return an empty list,
  since filtering and mapping over an empty collection produce no elements.
  MUST.
- **Boundary values**: A `directory` whose path is the single-character
  root `/` MUST still produce a deterministic, non-empty hexadecimal
  `identifier`, since the djb2 loop only iterates over the path's bytes and
  has no special case for a short path. MUST.
- **Concurrent access**: A checkout MUST be readable, comparable, and
  hashable concurrently from multiple threads with no synchronization,
  because every field is immutable and `identifier`/`displayName` are pure
  computations with no shared mutable state (see
  value-type-concurrency-safety). MUST. The checkout projection has no
  shared state of its own, so concurrent calls with different worktree-record
  lists MUST NOT interfere with one another. MUST.
- **Error states**: Resolving `directory`'s symlinks is a non-error-raising
  operation, and creating a checkout has no error-handling path at all; when
  `directory` names a path that does not exist on disk, creating the
  checkout MUST NOT raise or surface an error — it stores whatever the
  resolution step returns, which is a best-effort result rather than a
  validated one. MUST (this is a fact about a non-error-raising operation,
  not a swallowed error — there is no error here to swallow).
- **Offline or disconnected state**: Not applicable — creating or projecting
  a checkout makes no network call; `directory`, `branch`, and `isMain` are
  supplied by the caller or derived from a worktree record already read
  from local disk.
- **Duplicate worktree entries**: When the worktree-record list passed to
  the checkout projection contains two entries with the same `directory`,
  the projection MUST produce two separate checkout values rather than
  deduplicating them, since it performs a strict one-to-one mapping with no
  deduplication step. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directory` (construction parameter) | location value | none — required | Directory this checkout represents; stored as the symlink-resolved form of the caller's value, never the caller's unresolved value. |
| `branch` (construction parameter) | string, optional | none — required, may be absent | The checkout's live branch name, or absent when the worktree is in a detached-HEAD state. |
| `isMain` (construction parameter) | boolean | none — required | Whether this checkout is the repository's main worktree, typically forwarded from the source worktree record's own `isMain` field. |
| `worktrees` (projection parameter) | list of worktree records | none — required | The full worktree list, typically parsed from `git worktree list --porcelain` output, projected into checkout values with bare entries removed. |

Creating a checkout reads no environment variable and no persisted settings
key; every value it holds is supplied directly by its caller.

## Deep Linking

Not applicable: a checkout defines no URL scheme, route, or navigation
destination.

## Localization

Not applicable: a checkout produces no user-facing string; `displayName`
returns either the caller-supplied `branch` name or a filesystem path
component, both data values passed through unchanged, not localized UI
text.

## Accessibility Options

Not applicable: a checkout renders nothing; Reduce Motion, Increase
Contrast, and Differentiate Without Color have no surface here to apply to.

## Feature Flags

Not applicable: a checkout contains no feature-flag or build-configuration
check of any kind.

## Analytics

Not applicable: a checkout makes no analytics or event-tracking call.

## Privacy

- **Data collected**: A checkout value holds the caller's local filesystem
  `directory` path and, when present, the checkout's git `branch` name.
  Both are local workspace metadata the caller already possesses; creating
  a checkout does not read anything from disk beyond resolving `directory`'s
  symlinks.
- **Storage**: None — a checkout persists nothing; a value lives only as
  long as the caller retains it in memory.
- **Transmission**: None — creating or projecting a checkout makes no
  network call and transmits nothing.
- **Retention**: Not applicable — a checkout holds no state beyond the
  single value's lifetime; retention of any checkout the caller keeps is
  entirely the caller's responsibility.

## Logging

Not applicable: a checkout makes no logging call of any kind.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift`,
  using only Foundation's `URL` (`resolvingSymlinksInPath()`,
  `lastPathComponent`, `path`) and the sibling type `GitWorktree` from
  `packages/apple/AgenticToolkit/Core/Git/GitWorktree.swift`; nothing here is
  SwiftUI-specific — the type has no view and no observable state, and is
  used elsewhere purely as a `Hashable`/`Sendable` identity for tab groups.
  The `Sendable` conformance, together with every stored property being
  declared with `let` (immutable) and each of `URL`, `String?`, and `Bool`
  themselves being `Sendable`, is the mechanism behind
  value-type-concurrency-safety — nothing about it depends on `@MainActor`
  or any other isolation annotation.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
