---
id: 0396e49d-f933-4454-bacc-5cf97beda7de
title: Project Filter
domain: agentictoolkit://cookbook/workspace/projects/project-filter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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

# Project Filter

## Overview

This component is the single case-insensitive substring matcher used
everywhere a project list or a file-tree popover is searched. It exposes
two operations, deliberately routed through the same underlying scan so
neither can drift from the other: finding ranges, which returns every
case-insensitive occurrence of a query string inside a piece of text as a
list of position/length pairs, and checking a match, which decides
whether a repository record survives a search by checking whether the
query appears in its name or its path. The design's own rationale is that
keeping both answers on one code path means the characters a row
highlights can never disagree with the reason that row survived the
filter. It is consumed by two callers: the project browser's filter step,
which filters the project tree and bolds matched characters in each row's
label, and a breadcrumb's file-tree popover, which does the same for its
own rows.

## Behavioral Requirements

- **empty-query-yields-no-ranges**: Finding ranges MUST return no ranges
  immediately when the query is empty, without inspecting the text.
- **literal-substring-matching**: Finding ranges MUST treat the query as a
  literal substring, not a regular expression — it MUST search with a
  case-insensitive-only literal comparison, never a pattern/regex search,
  so a query containing regex metacharacters (e.g. `"."`, `"*"`, `"["`)
  MUST match only that literal character sequence.
- **case-insensitive-matching**: Finding ranges MUST locate occurrences of
  the query in the text using case-insensitive comparison, so a query and
  text differing only in letter case MUST still match.
- **utf16-range-coordinates**: Each returned range MUST express its
  position and length in UTF-16 code units of the text, not in
  character-cluster offsets — this is deliberate: UTF-16 code-unit offsets
  are the coordinate system many platforms' highlighted-text
  representations (attributed strings) index by, and a character-cluster
  offset would have to be converted at every call site to be of any use
  here.
- **all-occurrences-returned-left-to-right**: Finding ranges MUST return
  every occurrence of the query found by scanning the text left to right,
  in the order encountered, and MUST NOT stop after the first occurrence.
- **non-overlapping-scan-advance**: After finding a match, the scan MUST
  resume at the match's position plus its length (or plus one position for
  a zero-length match) before searching for the next occurrence, so an
  occurrence that would overlap the just-found match (e.g. a second
  `"aa"` starting inside a first `"aa"` match within `"aaa"`) MUST NOT be
  reported as a separate range.
- **empty-text-yields-no-ranges**: Finding ranges MUST return no ranges
  when the text is empty, for any non-empty query, because the scan has
  nothing to scan.
- **ranges-loop-terminates**: Because the scan position strictly increases
  by at least one UTF-16 unit every iteration and is bounded by the text's
  length, finding ranges MUST return after at most as many iterations as
  the text is long, for any text/query pair — it MUST NOT loop
  indefinitely.
- **empty-query-matches-every-repo**: Checking a match MUST return true
  for any repository record when the query is empty, without inspecting
  the record's name or path.
- **matches-by-name-or-path-only**: For a non-empty query, checking a
  match MUST return true if and only if the query is found somewhere in
  the record's name or somewhere in its path; matching against the
  record's remote URL, identifier, first-seen time, last-seen time, or
  last-opened time MUST NOT affect the result, since checking a match
  reads only the record's name and path.
- **matches-short-circuits-on-name**: Checking a match MUST check the
  record's name before its path, and MUST NOT check the path at all when
  the name check already found a match.
- **single-source-for-filter-and-highlight**: A caller deciding which rows
  to keep (via checking a match) and a caller deciding which characters to
  highlight in a kept row (via finding ranges) MUST derive both decisions
  from this component's own scan logic; no caller MUST implement a
  separate substring search of its own, so the set of matched characters a
  row displays MUST always be consistent with the reason that row was
  kept.
- **stateless-and-pure**: This component MUST hold no internal state of
  its own, and both finding ranges and checking a match MUST be pure
  functions of their arguments — calling either operation repeatedly with
  the same arguments, from any thread, MUST return an equal result every
  time.

## Appearance

Not applicable — this is a substring-matching operation pair, not a
visual component.

## States

Not applicable — this is a substring-matching operation pair, not a
visual component. It has no runtime state machine of its own; it is
called anew on every keystroke by its callers' own filter steps, which
hold the query text and the resulting row list, not this component.

## Accessibility

Not applicable — this is a substring-matching operation pair, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| PF-001 | empty-query-yields-no-ranges | Finding ranges with an empty query against the text "whippet" | No ranges |
| PF-002 | all-occurrences-returned-left-to-right | Finding ranges with the query "hip" against the text "whippet" | One range: position 1, length 3 |
| PF-003 | case-insensitive-matching | Finding ranges with the query "WHIP" against the text "whippet" | One range: position 0, length 4 |
| PF-004 | all-occurrences-returned-left-to-right | Finding ranges with the query "ab" against the text "abcab" | Two ranges, in order: position 0 length 2, then position 3 length 2 |
| PF-005 | empty-text-yields-no-ranges | Finding ranges with the query "zz" against the text "whippet" | No ranges (no match found; exercises the same not-found path as an empty haystack) |
| PF-006 | matches-by-name-or-path-only | Checking a match for a repository record named "whippet" at path "/Users/someone/dev/whippet", with the query "hipp" | Match |
| PF-007 | matches-by-name-or-path-only | Checking a match for the same record, with the query "someone" | Match |
| PF-008 | matches-by-name-or-path-only | Checking a match for the same record, with the query "stenographer" | No match |
| PF-009 | empty-query-matches-every-repo | Checking a match for the same record, with an empty query | Match |
| PF-010 | non-overlapping-scan-advance | Finding ranges with the query "aa" against the text "aaa" | One range only: position 0, length 2 — the second, overlapping "aa" starting at position 1 is not reported |
| PF-011 | literal-substring-matching | Finding ranges with the query "." against the text "a.b.c" | Two ranges: position 1 length 1, then position 3 length 1 — matches the two literal periods only, never treated as a wildcard |
| PF-012 | ranges-loop-terminates | Finding ranges with the query "z" against a text of 10,000 repeated "a" characters | No ranges, and the scan returns control to the caller — it makes no forward progress past as many iterations as the text is long, regardless of input size |

## Edge Cases

- **Null and empty input**: An empty query short-circuits both operations
  before either inspects the text or the record — finding ranges returns
  no ranges and checking a match returns true (MUST, see
  `empty-query-yields-no-ranges`, `empty-query-matches-every-repo`,
  PF-001, PF-009). Empty text (or an empty name/path on the record) makes
  the scan's starting condition false, so finding ranges returns no ranges
  for any non-empty query (MUST, see `empty-text-yields-no-ranges`).
- **Boundary values**: A query exactly as long as the text, or longer
  than the remaining unsearched portion of the text, causes the
  underlying search to report no match, ending the scan with whatever
  ranges were already found (MUST). A query that overlaps itself when
  repeated in the text (e.g. `"aa"` in `"aaa"`) is under-counted by
  design, not by accident — see `non-overlapping-scan-advance` and
  PF-010 (MUST).
- **Concurrent access**: This component holds no internal state; finding
  ranges and checking a match are pure functions over their
  text/query/record arguments, and any intermediate representation a call
  builds is a fresh, immutable value local to that call. Concurrent calls
  from any thread or execution context MUST be safe with no additional
  synchronization required (MUST, see `stateless-and-pure`).
- **Error states**: Not applicable — no operation here throws, returns a
  value the caller must unwrap, or calls anything that can fail; the one
  not-found signal in the underlying search is turned into a normal loop
  exit, never surfaced to the caller as an error.
- **Offline or disconnected state**: Not applicable — this component
  performs no network call and depends on no connectivity; it operates
  only on in-memory text values already held by the caller.
- **Missing file or unreachable server**: Not applicable — this component
  performs no file-system or network I/O of its own; a record's path is a
  string it compares textually, never a path it opens, stats, or reads.
- **Cancellation and timeouts**: Not applicable — every call to finding
  ranges and checking a match is synchronous; neither operation spawns a
  subprocess or a long-running task that something else could cancel or
  that could time out (MUST, see `ranges-loop-terminates` for the bound
  on how long a single call can run).
- **Concurrent calls with different arguments**: Because both operations
  are pure and stateless, two callers invoking finding ranges or checking
  a match with different query/text/record arguments at the same time on
  different threads MUST each observe only their own inputs and outputs,
  with no cross-talk between the two calls (MUST, see
  `stateless-and-pure`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `query` (finding ranges, checking a match) | string | none — required | The search text; empty means "match nothing" for finding ranges and "match everything" for checking a match. |
| `text` (finding ranges) | string | none — required | The haystack scanned for the query; a caller passes a repository's name or a tree node's name. |
| `repo` (checking a match) | repository record | none — required | The candidate repository; only its name and path fields are read. |

This component reads no environment variable, settings key, or injected
dependency; the only configuration is the arguments supplied at each call
site.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or
navigable destination — it is a text-matching operation pair with no
navigation surface of its own.

## Localization

Not applicable: this component produces no user-facing string of its
own. It returns a list of ranges and a true/false result; any text the
caller renders (a project's own name, or a static string like "No
projects yet") is built and localized, if at all, by the caller (the
project browser, the breadcrumb popover), not by this component.

## Accessibility Options

Not applicable: this component renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — it only returns match data a caller's view
may later use to decide what to draw.

## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check of any kind.

## Analytics

Not applicable: this component emits no analytics or telemetry event of
any kind.

## Privacy

Not applicable: this component collects, stores, transmits, and retains
nothing. It reads the text/name/path arguments passed to it for the
duration of a single, synchronous call and returns a result to the
caller; it writes nothing to disk, sends nothing over a network, and
keeps no reference to its inputs after returning.

## Logging

Not applicable: this component contains no logging call of any kind.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectFilter.swift` |

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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
