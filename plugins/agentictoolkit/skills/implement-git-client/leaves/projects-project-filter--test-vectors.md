<!-- leaf: implement-git-client/projects-project-filter--test-vectors · source: git-client-projects-project-filter.md -->

# ProjectFilter

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
