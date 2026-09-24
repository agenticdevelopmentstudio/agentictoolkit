---
id: 0396e49d-f933-4454-bacc-5cf97beda7de
title: ProjectFilter
domain: agentictoolkit://recipes/git-client-projects-project-filter
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The single case-insensitive substring matcher that decides both which projects survive a search and which characters a row highlights.
platforms:
- swift
- macos
tags:
- git
- projects
- filter
- search
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectFilter.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectBrowserViewController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/BreadcrumbPopoverViewController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectFilterTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectFilter

## Overview

`ProjectFilter.swift` defines a caseless, stored-state-free `enum` (a
namespace, not an instantiable type) with two static functions: `ranges(of:in:)`,
which returns every case-insensitive occurrence of a query string inside a
piece of text as an array of `NSRange`, and `matches(_:query:)`, which decides
whether a `GitRepo` survives a search by checking whether the query appears in
its `name` or its `path`. Both answers are deliberately routed through the
same `ranges(of:in:)` computation "so the characters a row highlights can
never disagree with the reason that row survived the filter" (source doc
comment) — the file's own word for this is `dry`. It is consumed by
two callers: `ProjectBrowserViewController.applyFilter()`, which filters the
project tree and bolds matched characters in each row's label, and
`BreadcrumbPopoverViewController.applyFilter()`/`attributedTitle(for:)`, which
does the same for a breadcrumb's file-tree popover.

## Behavioral Requirements

- **empty-query-yields-no-ranges**: `ranges(of:in:)` MUST return `[]`
  immediately when `query` is empty, without inspecting `text` (`guard
  !query.isEmpty else { return [] }`).
- **literal-substring-matching**: `ranges(of:in:)` MUST treat `query` as a
  literal substring, not a regular expression — it MUST search with
  `NSString.range(of:options:range:)` passing only the `.caseInsensitive`
  option, never `.regularExpression`, so a query containing regex
  metacharacters (e.g. `"."`, `"*"`, `"["`) MUST match only that literal
  character sequence.
- **case-insensitive-matching**: `ranges(of:in:)` MUST locate occurrences of
  `query` in `text` using the `.caseInsensitive` comparison option, so a
  query and text differing only in letter case MUST still match.
- **utf16-range-coordinates**: Each returned `NSRange` MUST express
  `location` and `length` in UTF-16 code units of `text as NSString`, not
  `String.Index` offsets — per the doc comment, this is deliberate because
  UTF-16 ranges are what an attributed string indexes by, and `String.Index`
  "would have to be converted at every call site to be of any use here."
- **all-occurrences-returned-left-to-right**: `ranges(of:in:)` MUST return
  every occurrence of `query` found by scanning `text` left to right, in the
  order encountered, and MUST NOT stop after the first occurrence.
- **non-overlapping-scan-advance**: After finding a match, the scan MUST
  resume at `match.location + max(match.length, 1)` before searching for the
  next occurrence, so an occurrence that would overlap the just-found match
  (e.g. a second `"aa"` starting inside a first `"aa"` match within `"aaa"`)
  MUST NOT be reported as a separate range.
- **empty-text-yields-no-ranges**: `ranges(of:in:)` MUST return `[]` when
  `text` is empty, for any non-empty `query`, because the scan loop's
  condition (`start < haystack.length`) is false before the loop body ever
  runs.
- **ranges-loop-terminates**: Because `start` strictly increases by at least
  one UTF-16 unit every iteration and the loop condition is bounded by
  `haystack.length`, `ranges(of:in:)` MUST return after at most
  `haystack.length` iterations for any `text`/`query` pair — it MUST NOT
  loop indefinitely.
- **empty-query-matches-every-repo**: `matches(_:query:)` MUST return `true`
  for any `GitRepo` when `query` is empty, without inspecting `repo.name` or
  `repo.path` (`guard !query.isEmpty else { return true }`).
- **matches-by-name-or-path-only**: For a non-empty `query`,
  `matches(_:query:)` MUST return `true` if and only if
  `ranges(of: query, in: repo.name)` is non-empty or
  `ranges(of: query, in: repo.path)` is non-empty; matching against
  `repo.remote`, `repo.id`, `repo.firstSeen`, `repo.lastSeen`, or
  `repo.lastOpened` MUST NOT affect the result, since `matches(_:query:)`
  reads only `repo.name` and `repo.path`.
- **matches-short-circuits-on-name**: `matches(_:query:)` MUST evaluate
  `ranges(of: query, in: repo.name)` before `ranges(of: query, in:
  repo.path)`, and MUST NOT evaluate the `repo.path` check at all when the
  `repo.name` check already produced a non-empty result, per Swift's `||`
  short-circuit evaluation.
- **single-source-for-filter-and-highlight**: A caller deciding which rows to
  keep (via `matches(_:query:)`) and a caller deciding which characters to
  highlight in a kept row (via `ranges(of:in:)`) MUST derive both decisions
  from `ProjectFilter`'s own scan logic; no caller MUST implement a separate
  substring search of its own, so the set of matched characters a row
  displays MUST always be consistent with the reason that row was kept.
- **stateless-and-pure**: `ProjectFilter` MUST declare no case and no stored
  `static var`, and both `ranges(of:in:)` and `matches(_:query:)` MUST be
  pure functions of their arguments — calling either function repeatedly
  with the same arguments, from any thread, MUST return an equal result
  every time.

## Appearance

Not applicable — this is a substring-matching function pair, not a visual
component.

## States

Not applicable — this is a substring-matching function pair, not a visual
component. It has no runtime state machine of its own; `ProjectFilter` is
called anew on every keystroke by its callers' own `applyFilter()` methods,
which hold the query text and the resulting row list, not `ProjectFilter`.

## Accessibility

Not applicable — this is a substring-matching function pair, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| PF-001 | empty-query-yields-no-ranges | `ProjectFilter.ranges(of: "", in: "whippet")` | `[]` — `ProjectFilterTests.testAnEmptyQueryHighlightsNothing` |
| PF-002 | all-occurrences-returned-left-to-right | `ProjectFilter.ranges(of: "hip", in: "whippet")` | `[NSRange(location: 1, length: 3)]` — `ProjectFilterTests.testTheQueryMatchesAnywhereInTheText` |
| PF-003 | case-insensitive-matching | `ProjectFilter.ranges(of: "WHIP", in: "whippet")` | `[NSRange(location: 0, length: 4)]` — `ProjectFilterTests.testMatchingIgnoresCase` |
| PF-004 | all-occurrences-returned-left-to-right | `ProjectFilter.ranges(of: "ab", in: "abcab")` | `[NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)]` — `ProjectFilterTests.testEveryOccurrenceIsReturned` |
| PF-005 | empty-text-yields-no-ranges | `ProjectFilter.ranges(of: "zz", in: "whippet")` | `[]` — `ProjectFilterTests.testTextWithoutTheQueryHighlightsNothing` (no match, not an empty haystack, but exercises the same not-found path) |
| PF-006 | matches-by-name-or-path-only | `ProjectFilter.matches(GitRepo(path: "/Users/someone/dev/whippet", name: "whippet"), query: "hipp")` | `true` — `ProjectFilterTests.testAProjectMatchesOnItsName` |
| PF-007 | matches-by-name-or-path-only | `ProjectFilter.matches(GitRepo(path: "/Users/someone/dev/whippet", name: "whippet"), query: "someone")` | `true` — `ProjectFilterTests.testAProjectMatchesOnItsPath` |
| PF-008 | matches-by-name-or-path-only | `ProjectFilter.matches(GitRepo(path: "/Users/someone/dev/whippet", name: "whippet"), query: "stenographer")` | `false` — `ProjectFilterTests.testAProjectMatchingNeitherIsFilteredOut` |
| PF-009 | empty-query-matches-every-repo | `ProjectFilter.matches(GitRepo(path: "/Users/someone/dev/whippet", name: "whippet"), query: "")` | `true` — `ProjectFilterTests.testAnEmptyQueryMatchesEverything` |
| PF-010 | non-overlapping-scan-advance | `ProjectFilter.ranges(of: "aa", in: "aaa")` | `[NSRange(location: 0, length: 2)]` only — the second, overlapping `"aa"` starting at location 1 is not reported (traced to the `start = match.location + max(match.length, 1)` advance; no dedicated test in the given suite) |
| PF-011 | literal-substring-matching | `ProjectFilter.ranges(of: ".", in: "a.b.c")` | `[NSRange(location: 1, length: 1), NSRange(location: 3, length: 1)]` — matches the two literal periods only, not treated as a regex wildcard (traced to the `.caseInsensitive`-only options set, with no `.regularExpression`; no dedicated test in the given suite) |
| PF-012 | ranges-loop-terminates | `ProjectFilter.ranges(of: "z", in: String(repeating: "a", count: 10_000))` | Returns `[]` and returns control to the caller — the scan makes no forward progress past `haystack.length` iterations regardless of input size (traced to the bounded `while start < haystack.length` loop; no dedicated test in the given suite) |

## Edge Cases

- **Null and empty input**: An empty `query` short-circuits both functions
  before either inspects `text` or `repo` — `ranges(of:in:)` returns `[]`
  and `matches(_:query:)` returns `true` (MUST, see
  `empty-query-yields-no-ranges`, `empty-query-matches-every-repo`,
  PF-001, PF-009). An empty `text` (or an empty `repo.name`/`repo.path`)
  makes the scan loop's initial condition false, so `ranges(of:in:)`
  returns `[]` for any non-empty query (MUST, see
  `empty-text-yields-no-ranges`).
- **Boundary values**: A `query` exactly as long as `text`, or longer than
  the remaining unsearched portion of `text`, causes
  `haystack.range(of:options:range:)` to return `NSNotFound`, which the
  `guard match.location != NSNotFound else { break }` catches, ending the
  scan with whatever ranges were already found (MUST). A `query` that
  overlaps itself when repeated in `text` (e.g. `"aa"` in `"aaa"`) is
  under-counted by design, not by accident — see
  `non-overlapping-scan-advance` and PF-010 (MUST).
- **Concurrent access**: `ProjectFilter` declares no case, no stored
  property, and no `static var`; `ranges(of:in:)` and `matches(_:query:)`
  are pure functions over their `String`/`GitRepo` arguments, and the
  `NSString` each call bridges via `text as NSString` is a fresh, immutable
  value local to that call. Concurrent calls from any thread or isolation
  domain MUST be safe with no additional synchronization required (MUST,
  see `stateless-and-pure`).
- **Error states**: Not applicable — no function in `ProjectFilter.swift`
  throws, returns an `Optional` that the caller must unwrap, or calls
  anything that can fail; the one failure signal in the source,
  `NSNotFound`, is checked with a `guard` and turned into a normal loop
  exit, never surfaced to the caller as an error.
- **Offline or disconnected state**: Not applicable — `ProjectFilter.swift`
  performs no network call and depends on no connectivity; it operates only
  on in-memory `String` values already held by the caller.
- **Missing file or unreachable server**: Not applicable — `ProjectFilter.swift`
  performs no file-system or network I/O of its own; `repo.path` is a
  string it compares textually, never a path it opens, stats, or reads.
- **Cancellation and timeouts**: Not applicable — every call to
  `ranges(of:in:)` and `matches(_:query:)` is synchronous and non-`async`;
  neither function spawns a subprocess or a long-running operation that
  something else could cancel or that could time out (MUST, see
  `ranges-loop-terminates` for the source's own bound on how long a single
  call can run).
- **Concurrent calls with different arguments**: Because both functions are
  pure and stateless, two callers invoking `ranges(of:in:)` or
  `matches(_:query:)` with different `query`/`text`/`repo` arguments at the
  same time on different threads MUST each observe only their own inputs
  and outputs, with no cross-talk between the two calls (MUST, see
  `stateless-and-pure`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `query` (`ranges(of:in:)`, `matches(_:query:)`) | `String` | none — required | The search text; empty means "match nothing" for `ranges(of:in:)` and "match everything" for `matches(_:query:)`. |
| `text` (`ranges(of:in:)`) | `String` | none — required | The haystack scanned for `query`; a caller passes `repo.name` or a tree node's `name`. |
| `repo` (`matches(_:query:)`) | `GitRepo` | none — required | The candidate repository; only its `name` and `path` fields are read. |

`ProjectFilter.swift` reads no environment variable, settings key, or
injected dependency; the only configuration is the arguments supplied at
each call site.

## Deep Linking

Not applicable: `ProjectFilter.swift` defines no URL scheme, route, or
navigable destination — it is a text-matching function pair with no
navigation surface of its own.

## Localization

Not applicable: `ProjectFilter.swift` produces no user-facing string of its
own. It returns `[NSRange]` and `Bool` values; any text the caller renders
(the project's own `name`, or a static string like `"No projects yet"`) is
built and localized, if at all, by the caller
(`ProjectBrowserViewController`, `BreadcrumbPopoverViewController`), not by
this file.

## Accessibility Options

Not applicable: `ProjectFilter.swift` renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — it only returns match data a caller's view
may later use to decide what to draw.

## Feature Flags

Not applicable: `ProjectFilter.swift` contains no feature-flag or
remote-config check of any kind.

## Analytics

Not applicable: `ProjectFilter.swift` emits no analytics or telemetry event
of any kind.

## Privacy

Not applicable: `ProjectFilter.swift` collects, stores, transmits, and
retains nothing. It reads `text`/`repo.name`/`repo.path` from the arguments
passed to it for the duration of a single, synchronous call and returns a
result to the caller; it writes nothing to disk, sends nothing over a
network, and keeps no reference to its inputs after returning.

## Logging

Not applicable: `ProjectFilter.swift` contains no `Logger`, `os.log`,
`print`, or any other logging call.

## Platform Notes

- **SwiftUI**: The source
  (`packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectFilter.swift`,
  tests `Tests/AgenticToolkitMacOSTests/Projects/ProjectFilterTests.swift`)
  imports only `Foundation` — no AppKit, UIKit, or SwiftUI dependency — so it
  ports unchanged into a SwiftUI-hosted app. A SwiftUI list would call
  `ProjectFilter.matches(_:query:)` inside its data source's `filter` and
  `ProjectFilter.ranges(of:in:)` to build an `AttributedString` with bolded
  matched runs for each row, exactly as `ProjectBrowserViewController` does
  today with `NSAttributedString`.
- **Compose**: Model `ProjectFilter` as a Kotlin `object` with `fun
  ranges(query: String, text: String): List<IntRange>` and `fun
  matches(repo: GitRepo, query: String): Boolean`. Kotlin's `String` has no
  UTF-16-`NSRange`-shaped search API, so implement the scan with
  `text.indexOf(query, startIndex = start, ignoreCase = true)` in the same
  left-to-right loop, breaking on `-1` and advancing
  `start = index + maxOf(query.length, 1)` to reproduce
  `non-overlapping-scan-advance`; because `indexOf` performs a literal
  search, `literal-substring-matching` carries over with no extra work.
- **React/Web**: Model the two functions as `rangesOf(query: string, text:
  string): Array<[number, number]>` and `matchesRepo(repo: GitRepo, query:
  string): boolean`, using `text.toLowerCase().indexOf(query.toLowerCase(),
  start)` in the same loop (JavaScript strings are UTF-16-indexed, so the
  returned `[start, length]` pairs line up with the Swift `NSRange`
  coordinates directly, satisfying `utf16-range-coordinates` with no
  conversion). Render matches by slicing `text` at the returned pairs into
  bold/`<mark>` spans, mirroring `ThemedHighlightLabel`'s role.
- **AppKit / UIKit**: This is the file's actual runtime home today.
  `ProjectBrowserViewController.applyFilter()` calls
  `ProjectFilter.matches(_:query:)` to decide which `GitRepo` rows survive
  into the `NSOutlineView`-backed project tree, and `ProjectRowView` calls
  `ProjectFilter.ranges(of:in:)` to bold matched characters in each row's
  `ThemedHighlightLabel`. `BreadcrumbPopoverViewController.applyFilter()`
  and `attributedTitle(for:)` reuse the same two functions to filter and
  bold-highlight an `NSTableView`'s rows. Nothing in `ProjectFilter.swift`
  itself is AppKit-specific — `NSRange`/`NSString` are equally available
  under UIKit, so it ports unchanged.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `ProjectFilter` as a static class with `public static IReadOnlyList<(int
  Location, int Length)> Ranges(string query, string text)` and `public
  static bool Matches(GitRepo repo, string query)`. .NET `string` is
  already UTF-16-indexed the same way `NSString` is, so
  `text.IndexOf(query, start, StringComparison.OrdinalIgnoreCase)`
  reproduces `case-insensitive-matching` and `literal-substring-matching`
  directly (`IndexOf` never treats `query` as a pattern), and the same
  `start = index + Math.Max(query.Length, 1)` advance reproduces
  `non-overlapping-scan-advance` with no coordinate conversion needed.
  Bind the returned ranges to a `TextBlock`'s `Inlines` — a bold `Run` per
  matched range and a regular `Run` for the gaps between them — inside the
  `ItemsRepeater`/`TreeView` `DataTemplate` that lists projects, and filter
  the bound `ObservableCollection<GitRepo>` with `Matches` from the search
  box's `TextChanged` handler, mirroring `applyFilter()`'s role.

## Design Decisions

**Decision**: `matches(_:query:)` and every row-highlighting caller derive
their answer from the same `ranges(of:in:)` computation rather than each
implementing its own substring search.
**Rationale**: Per the source's top-of-file doc comment, this keeps "the
characters a row highlights" from ever disagreeing "with the reason that row
survived the filter" — the source's own name for this is `dry`. A second,
independently-written search (even one intended to behave identically) would
be free to drift from this one over time.
**Approved**: pending

**Decision**: the scan in `ranges(of:in:)` advances by `max(match.length, 1)`
rather than by `match.length` alone.
**Rationale**: The source comment explains this guards against a query whose
match has zero length leaving `start` unchanged, which would loop forever;
with only the `.caseInsensitive` option in use, a non-empty query is not
expected to ever produce a zero-length match, but the guard makes the loop's
termination (`ranges-loop-terminates`) hold regardless. The same advance rule
produces the non-overlapping scan behavior in `non-overlapping-scan-advance`
as a side effect, not as its primary purpose.
**Approved**: pending

**Decision**: `ranges(of:in:)` searches with `.caseInsensitive` only, never
`.regularExpression`.
**Rationale**: The component's purpose is matching what a user typed against
a project's name and path; treating a query literally means a user who types
a period, a bracket, or an asterisk while searching for a real file or folder
name gets a search for that literal character, not a broken or
surprising pattern match.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |

Notes: separation-of-concerns passes because `ProjectFilter.swift` contains
only the substring-search and repo-matching logic — no `NSView`, no
`NSOutlineView`/`NSTableView` code, and no persistence — leaving row
construction to `ProjectBrowserViewController`/`ProjectRowView` and
`BreadcrumbPopoverViewController`, and leaving the `GitRepo` data shape to
`GitRepo.swift`. unit-test-coverage passes because
`ProjectFilterTests.swift` exercises both public functions with meaningful
assertions: anywhere-in-text matching, case-insensitivity, multiple
occurrences, an empty query on both functions, a non-matching query on both
`ranges(of:in:)` and `matches(_:query:)`, and both the name- and
path-matching branches of `matches(_:query:)` (see PF-001 through PF-009).
good-test-properties passes because every test in `ProjectFilterTests.swift`
is a synchronous, in-memory `XCTAssertEqual`/`XCTAssertTrue`/`XCTAssertFalse`
call against a locally constructed `GitRepo` or literal string, with no
shared fixture, no I/O, and no ordering dependency between tests — each is
fast, isolated, repeatable, and self-validating on its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
