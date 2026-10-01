---
id: 773a1876-24d8-4134-8815-41fbc8c53096
title: Activity Query Filter
domain: agentictoolkit://cookbook/status/dashboard/logic/filter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure case-insensitive, token-AND substring predicate that decides whether
  a row's search text matches a free-text query
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/source-filter
references: []
approved-by: ''
approved-date: ''
---

# Activity Query Filter

## Overview

This module exports one pure operation, the query-match operation, taking a haystack and a query. Its doc comment states the contract: "Case-insensitive, token-AND substring match. Every whitespace-separated token in the query must appear somewhere in the haystack. An empty query matches all."

Its one call site is the activity panel. The panel keeps a row when it passes the source filter ([Source Filter](agentictoolkit://cookbook/status/dashboard/state/source-filter)) AND the query-match operation on the row's search text and the current query is true. The current query is the raw text of the panel's search box. The row's search text joins the row's name, environment, status word, detail and commit body with single spaces. The module holds no state and does no I/O.

## Behavioral Requirements

- **signature**: the query-match operation MUST take two text values, `haystack` and `query`, and MUST return a true-or-false result.
- **synchronous-result**: the operation MUST return its result synchronously, with no promise, callback or deferred work.
- **no-side-effects**: the operation MUST NOT mutate its arguments, keep state between calls, or perform I/O. The same inputs MUST always give the same result.
- **query-trim**: The operation MUST remove leading and trailing whitespace from `query` before any other processing.
- **empty-query-matches-all**: When `query` is empty or only whitespace, the operation MUST return true for every `haystack`, including an empty `haystack`.
- **case-insensitive**: The operation MUST lowercase both `query` and `haystack` using locale-independent default case mapping, not a locale-aware case mapping, before comparing them.
- **tokenization**: The operation MUST split the trimmed, lowercased query into tokens on runs of one or more whitespace characters. A run of several spaces, tabs or newlines MUST count as one separator and MUST NOT produce an empty token.
- **token-and**: The operation MUST return true only when every token appears in the lowercased `haystack`. It MUST return false as soon as any one token is absent.
- **substring-anywhere**: A token MUST match at any position in `haystack`, including inside a word or across punctuation such as `.`. The operation MUST NOT require a word boundary or a prefix match.
- **literal-token**: Each token MUST be compared as a literal substring. Characters such as `.`, `*` or `(` MUST NOT be read as pattern syntax.
- **order-independent**: The result MUST NOT depend on the order of the tokens in `query`, or on where the tokens occur in `haystack` relative to each other.
- **overlap-allowed**: The operation MUST let several tokens match the same or overlapping characters of `haystack`. A duplicated token MUST NOT need a second occurrence.
- **haystack-untrimmed**: The operation MUST NOT trim or tokenize `haystack`. Its whitespace and punctuation stay part of the searched text.
- **no-normalization**: The operation MUST NOT apply Unicode normalization, diacritic folding or any fuzzy matching. Canonically equivalent strings in different normal forms do not match unless their code points match after lowercasing.
- **string-precondition**: Callers MUST pass text values for both arguments. The operation does no runtime type check; passing a value that is not text is a caller precondition violation, and its behavior in that case is implementation-defined rather than specified.
- **no-errors-for-strings**: For any two text-value arguments, the operation MUST NOT throw.

## Appearance

Not applicable — this is a pure string-matching predicate, not a visual component.

## States

Not applicable — this is a pure string-matching predicate, not a visual component.

## Accessibility

Not applicable — this is a pure string-matching predicate, not a visual component.

## Conformance Test Vectors

Vectors 001 to 006 come straight from the assertions in the module's own test suite. The rest follow from the code.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| filter-001 | empty-query-matches-all | haystack `"anything"`, query `""` | `true` |
| filter-002 | empty-query-matches-all, query-trim | haystack `"anything"`, query `"   "` | `true` |
| filter-003 | case-insensitive, substring-anywhere | haystack `"staging.adh deploy failed"`, query `"ADH"` | `true` |
| filter-004 | token-and | haystack `"staging.adh"`, query `"prod"` | `false` |
| filter-005 | token-and, tokenization | haystack `"testing.admin.adh deploy failed"`, query `"testing failed"` | `true` |
| filter-006 | token-and | haystack `"testing.admin.adh deploy failed"`, query `"testing deployed"` | `false` (`deployed` is absent) |
| filter-007 | empty-query-matches-all | haystack `""`, query `""` | `true` |
| filter-008 | token-and | haystack `""`, query `"x"` | `false` |
| filter-009 | query-trim, tokenization, order-independent | haystack `"staging.adh"`, query `"  adh   staging "` | `true` |
| filter-010 | tokenization | haystack `"deploy failed"`, query `"deploy\tfailed"` (a tab separates the tokens) | `true` |
| filter-011 | literal-token, substring-anywhere | haystack `"staging.adh"`, query `"g.a"` | `true` |
| filter-012 | literal-token | haystack `"stagingXadh"`, query `"g.a"` | `false` (`.` is not a wildcard) |
| filter-013 | overlap-allowed | haystack `"adh"`, query `"adh adh a"` | `true` |
| filter-014 | haystack-untrimmed | haystack `"adh deploy"`, query `"hdep"` | `false` (the space in `haystack` breaks the substring, and a token never contains whitespace) |
| filter-015 | case-insensitive | haystack `"Deploy FAILED"`, query `"deploy failed"` | `true` |
| filter-016 | no-normalization | haystack is `café` with a precomposed `é` (U+00E9), query is `café` with `e` plus a combining acute accent (U+0065 U+0301) | `false` |
| filter-017 | case-insensitive, no-normalization | haystack `"İstanbul"` (capital dotted I, U+0130), query `"istanbul"` | `false` (default lowercasing turns U+0130 into `i` plus a combining dot U+0307) |
| filter-018 | no-side-effects | The query-match operation on haystack `"staging.adh"`, query `"adh"`, called twice with the same arguments | `true` both times, and both argument strings are unchanged |
| filter-019 | no-errors-for-strings | haystack `"a"`, query `"("` | `false` with no exception (`(` is not parsed as a pattern) |

## Edge Cases

- **Empty or blank query**: An empty or whitespace-only `query` MUST match every `haystack` (filter-001, filter-002, filter-007). At the activity panel this means a cleared search box shows every row that passes the source filter.
- **Empty haystack**: An empty `haystack` MUST match only a blank query (filter-007, filter-008).
- **Repeated or mixed whitespace**: Extra spaces, tabs, newlines and other whitespace characters between tokens MUST collapse to single separators (filter-009, filter-010).
- **Pattern metacharacters**: Characters such as `.`, `*`, `(` and `[` MUST be matched literally and MUST NOT throw (filter-011, filter-012, filter-019).
- **Duplicate tokens**: A token repeated in `query` MUST NOT require repeated occurrences in `haystack` (filter-013).
- **Text spanning a haystack space**: Because tokens never contain whitespace, a token cannot match across a space in `haystack` (filter-014). Its only chance is a contiguous run with no whitespace.
- **Locale-sensitive case pairs**: Lowercasing is locale-independent, so Turkish dotted and dotless I pairs do not fold the way a Turkish user expects (filter-017). The source deliberately keeps case mapping locale-independent, so this MUST be kept in a conformant port.
- **Unicode normal forms**: Precomposed and decomposed forms of the same character MUST NOT match each other (filter-016). No normalization step exists.
- **Non-text arguments**: Outside static type checking, passing a value that is not text is a caller precondition violation (see **string-precondition**), and the one call site always passes text values.
- **Large inputs**: Cost grows with the number of tokens times the length of `haystack`, and both strings are lowercased again on every call. The operation sets no length limit, and the caller runs it once per row whenever its cached inputs change.
- **Concurrent access**: Not applicable. The operation is stateless, so calls cannot interleave.
- **Error states, offline, timeouts and cancellation**: Not applicable. The operation does no I/O and finishes synchronously, so there is nothing to time out, cancel or lose a connection to.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `haystack` | a text value | none (required) | The text searched. At the call site this is the row's search text: the row's name, environment, status word, detail and commit body joined with spaces. |
| `query` | a text value | none (required) | The user's free-text query. Trimmed, lowercased and split on whitespace into AND-ed tokens. A blank value matches everything. |

The operation reads no environment variables, settings keys or injected dependencies.

## Deep Linking

Not applicable: the module exports one pure operation and has no navigable surface. The query lives in the panel's local, in-memory query state, not in a URL.

## Localization

Not applicable: the operation returns a true-or-false result and produces no user-facing text. Its only locale-related behavior is the locale-independent lowercasing, covered under **case-insensitive**.

## Accessibility Options

Not applicable: the operation renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and the match rule always applies.

## Analytics

Not applicable: the operation emits no events.

## Privacy

Not applicable: the operation reads its two text arguments in memory and stores, logs and transmits nothing.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as a free function `func matchesQuery(_ haystack: String, _ query: String) -> Bool`. Trim with `trimmingCharacters(in: .whitespacesAndNewlines)`, lowercase with `lowercased()` (locale-independent, like the source), split with `split(whereSeparator: \.isWhitespace)` (which drops empty pieces), and test with `allSatisfy { h.contains($0) }`. Swift `String.contains` compares by Character with canonical equivalence, so precomposed and decomposed `é` DO match in Swift. To keep **no-normalization**, compare `unicodeScalars` or UTF-16 views instead. Use `localizedStandardContains` only if the port is meant to diverge from the source. Bind the query to a `@State` string and filter in a computed property.
- **Compose**: Write a top-level Kotlin `fun matchesQuery(haystack: String, query: String): Boolean`. Use `query.trim().lowercase()`, `split(Regex("\\s+"))` and `all { h.contains(it) }`. Kotlin `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `lowercase(Locale.getDefault())`. Kotlin `trim()` trims by `Char.isWhitespace`, and the `\s` regex class covers ASCII whitespace unless `UNICODE_CHARACTER_CLASS` is set, so no-break spaces behave differently from the source. Filter inside `remember(rows, query) { rows.filter { … } }` or `derivedStateOf`.
- **React/Web**: This is the source: `src/lib/filter.ts`, exporting `matchesQuery(haystack, query)`, tested by `src/lib/filter.test.ts` (vitest) and called only from `src/components/ActivityPanel.tsx` inside a `useMemo`, together with `rowSearchText` from `src/lib/row-model.ts`; the panel's query text comes from a `useState("")`. The TypeScript signature requires string arguments; the runtime does no check of its own, so a `null` or `undefined` query throws a `TypeError` from `trim` in plain JavaScript. It relies on `String.prototype.trim`, `toLowerCase` (not `toLocaleLowerCase`), `split(/\s+/)`, `Array.prototype.every` and `String.prototype.includes`. The operation is stateless and runs on the single JavaScript thread, so calls cannot interleave.
- **AppKit / UIKit**: Use the same pure Swift function as the SwiftUI port. In AppKit, feed it from an `NSSearchField`'s `stringValue` and filter the table's data source. In UIKit, feed it from `UISearchController.searchBar.text` in `updateSearchResults(for:)`. Nothing in the function is UI-bound, so it belongs in a shared framework target.
- **WinUI 3**: Port as `public static bool MatchesQuery(string haystack, string query)` in a `static class`. Use `query.Trim().ToLowerInvariant()` (not `ToLower()`, which follows `CultureInfo.CurrentCulture` and would fold Turkish I differently), then `q.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)` to split on all Unicode whitespace without empty entries, then `tokens.All(t => h.Contains(t, StringComparison.Ordinal))`. Use ordinal comparison: culture-aware comparison would treat canonically equivalent forms as equal and break **no-normalization**. An empty query returns `true` before splitting. The function stays synchronous with no `Task`. In the view model, bind an `AutoSuggestBox` or `TextBox` `Text` to a `Query` property that raises `INotifyPropertyChanged`, and on change rebuild an `ObservableCollection<Row>` (or set `AdvancedCollectionView.Filter` from the Community Toolkit) with `rows.Where(r => MatchesQuery(RowSearchText(r), Query))`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/filter.ts` |

## Design Decisions

**Decision**: AND the tokens together rather than OR them.
**Rationale**: Each extra word narrows the activity feed, so an operator can type `testing failed` to find failed runs on the testing environment (filter-005). An OR rule would widen the result with each word.
**Approved**: pending

**Decision**: Match plain substrings anywhere rather than whole words or prefixes.
**Rationale**: Row search text contains dotted names such as `staging.adh` and `testing.admin.adh`. Substring matching lets `adh` or `admin` hit inside those names without a tokenizer that knows about dots (filter-003, filter-011).
**Approved**: pending

**Decision**: A blank query matches everything.
**Rationale**: The doc comment declares it, and it makes an empty search box a no-op, so clearing the box restores the unfiltered feed.
**Approved**: pending

**Decision**: Use `includes` and `toLowerCase`, not a regular expression or a locale-aware collator. (React/Web implementation — `includes` and `toLowerCase` are this module's own choice of JavaScript API.)
**Rationale**: Literal substring matching means user input can never be read as a pattern or throw on metacharacters (filter-019). Locale-independent lowercasing gives the same result in every browser locale. The cost is no Unicode normalization and no locale-specific case folding, which the edge cases record.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |

**Separation of concerns.** The module holds only the match rule. It knows nothing about rows or the search box. The activity panel builds the haystack and applies the result.

**Unit test coverage.** The test suite covers the three behaviors in the doc comment: blank query, case-insensitive substring, and token-AND. It includes a negative case for each of the last two.

**Explicit error handling.** No failure path exists for text inputs. Tokens are matched with plain substring search, never compiled into a regular expression, so user input cannot cause a runtime error. Non-text input is excluded by the source's static type signature.

**Good test properties.** The tests are deterministic and isolated, with no mocks, clock or I/O. Each test names the single behavior it asserts.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from `filter.ts` and `filter.test.ts` |
