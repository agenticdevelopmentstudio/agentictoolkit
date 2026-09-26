---
id: 773a1876-24d8-4134-8815-41fbc8c53096
title: Activity Query Filter
domain: agentictoolkit://cookbook/status-web/lib/filter
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/status-web/hooks/use-source-filter
references: []
approved-by: ''
approved-date: ''
---

# Activity Query Filter

## Overview

`filter.ts` (`packages/web/packages/status-web/src/lib/filter.ts`) exports one pure function, `matchesQuery(haystack, query)`. Its doc comment states the contract: "Case-insensitive, token-AND substring match. Every whitespace-separated token in `query` must appear somewhere in `haystack`. An empty query matches all."

Its one call site is `ActivityPanel` (`src/components/ActivityPanel.tsx`). Inside a `useMemo`, the panel keeps a row when it passes the source filter ([useSourceFilter](agentictoolkit://cookbook/status-web/hooks/use-source-filter)) AND `matchesQuery(rowSearchText(r), q)` is true. `q` is the raw text of the panel's search box. `rowSearchText` (`src/lib/row-model.ts`) joins the row's `name`, `environment`, `statusWord`, `detail` and `commitBody` with single spaces. The module holds no state and does no I/O.

## Behavioral Requirements

- **signature**: `matchesQuery` MUST take two strings, `haystack` and `query`, and MUST return a `boolean`.
- **synchronous-result**: `matchesQuery` MUST return its result synchronously, with no promise, callback or deferred work.
- **no-side-effects**: `matchesQuery` MUST NOT mutate its arguments, keep state between calls, or perform I/O. The same inputs MUST always give the same result.
- **query-trim**: The function MUST remove leading and trailing whitespace from `query` before any other processing.
- **empty-query-matches-all**: When `query` is empty or only whitespace, the function MUST return `true` for every `haystack`, including an empty `haystack`.
- **case-insensitive**: The function MUST lowercase both `query` and `haystack` with the locale-independent default case mapping (`toLowerCase`, not `toLocaleLowerCase`) before comparing them.
- **tokenization**: The function MUST split the trimmed, lowercased query into tokens on runs of one or more whitespace characters. A run of several spaces, tabs or newlines MUST count as one separator and MUST NOT produce an empty token.
- **token-and**: The function MUST return `true` only when every token appears in the lowercased `haystack`. It MUST return `false` as soon as any one token is absent.
- **substring-anywhere**: A token MUST match at any position in `haystack`, including inside a word or across punctuation such as `.`. The function MUST NOT require a word boundary or a prefix match.
- **literal-token**: Each token MUST be compared as a literal substring. Characters such as `.`, `*` or `(` MUST NOT be read as pattern syntax.
- **order-independent**: The result MUST NOT depend on the order of the tokens in `query`, or on where the tokens occur in `haystack` relative to each other.
- **overlap-allowed**: The function MUST let several tokens match the same or overlapping characters of `haystack`. A duplicated token MUST NOT need a second occurrence.
- **haystack-untrimmed**: The function MUST NOT trim or tokenize `haystack`. Its whitespace and punctuation stay part of the searched text.
- **no-normalization**: The function MUST NOT apply Unicode normalization, diacritic folding or any fuzzy matching. Canonically equivalent strings in different normal forms do not match unless their code points match after lowercasing.
- **string-precondition**: Callers MUST pass string values for both arguments, as the TypeScript signature requires. The function does no runtime type check, so a `null` or `undefined` `query` throws a `TypeError` from `trim` in plain JavaScript.
- **no-errors-for-strings**: For any two string arguments, `matchesQuery` MUST NOT throw.

## Appearance

Not applicable — this is a pure string-matching predicate, not a visual component.

## States

Not applicable — this is a pure string-matching predicate, not a visual component.

## Accessibility

Not applicable — this is a pure string-matching predicate, not a visual component.

## Conformance Test Vectors

Vectors 001 to 006 come straight from the assertions in `src/lib/filter.test.ts`. The rest follow from the code in `filter.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| filter-001 | empty-query-matches-all | `matchesQuery("anything", "")` | `true` |
| filter-002 | empty-query-matches-all, query-trim | `matchesQuery("anything", "   ")` | `true` |
| filter-003 | case-insensitive, substring-anywhere | `matchesQuery("staging.adh deploy failed", "ADH")` | `true` |
| filter-004 | token-and | `matchesQuery("staging.adh", "prod")` | `false` |
| filter-005 | token-and, tokenization | `matchesQuery("testing.admin.adh deploy failed", "testing failed")` | `true` |
| filter-006 | token-and | `matchesQuery("testing.admin.adh deploy failed", "testing deployed")` | `false` (`deployed` is absent) |
| filter-007 | empty-query-matches-all | `matchesQuery("", "")` | `true` |
| filter-008 | token-and | `matchesQuery("", "x")` | `false` |
| filter-009 | query-trim, tokenization, order-independent | `matchesQuery("staging.adh", "  adh   staging ")` | `true` |
| filter-010 | tokenization | `matchesQuery("deploy failed", "deploy\tfailed")` (a tab separates the tokens) | `true` |
| filter-011 | literal-token, substring-anywhere | `matchesQuery("staging.adh", "g.a")` | `true` |
| filter-012 | literal-token | `matchesQuery("stagingXadh", "g.a")` | `false` (`.` is not a wildcard) |
| filter-013 | overlap-allowed | `matchesQuery("adh", "adh adh a")` | `true` |
| filter-014 | haystack-untrimmed | `matchesQuery("adh deploy", "hdep")` | `false` (the space in `haystack` breaks the substring, and a token never contains whitespace) |
| filter-015 | case-insensitive | `matchesQuery("Deploy FAILED", "deploy failed")` | `true` |
| filter-016 | no-normalization | `haystack` is `café` with a precomposed `é` (U+00E9), `query` is `café` with `e` plus a combining acute accent (U+0065 U+0301) | `false` |
| filter-017 | case-insensitive, no-normalization | `matchesQuery("İstanbul", "istanbul")` (capital dotted I, U+0130) | `false` (default lowercasing turns U+0130 into `i` plus a combining dot U+0307) |
| filter-018 | no-side-effects | Call `matchesQuery("staging.adh", "adh")` twice with the same arguments | `true` both times, and both argument strings are unchanged |
| filter-019 | no-errors-for-strings | `matchesQuery("a", "(")` | `false` with no exception (`(` is not parsed as a pattern) |

## Edge Cases

- **Empty or blank query**: An empty or whitespace-only `query` MUST match every `haystack` (filter-001, filter-002, filter-007). In `ActivityPanel` this means a cleared search box shows every row that passes the source filter.
- **Empty haystack**: An empty `haystack` MUST match only a blank query (filter-007, filter-008).
- **Repeated or mixed whitespace**: Extra spaces, tabs, newlines and other characters matched by the regular-expression `\s` class between tokens MUST collapse to single separators (filter-009, filter-010).
- **Pattern metacharacters**: Characters such as `.`, `*`, `(` and `[` MUST be matched literally and MUST NOT throw (filter-011, filter-012, filter-019).
- **Duplicate tokens**: A token repeated in `query` MUST NOT require repeated occurrences in `haystack` (filter-013).
- **Text spanning a haystack space**: Because tokens never contain whitespace, a token cannot match across a space in `haystack` (filter-014). Its only chance is a contiguous run with no whitespace.
- **Locale-sensitive case pairs**: Lowercasing is locale-independent, so Turkish dotted and dotless I pairs do not fold the way a Turkish user expects (filter-017). The source deliberately uses `toLowerCase`, so this MUST be kept in a conformant port.
- **Unicode normal forms**: Precomposed and decomposed forms of the same character MUST NOT match each other (filter-016). No normalization step exists.
- **Non-string arguments**: Outside TypeScript's type checking, a `null` or `undefined` argument throws a `TypeError`. The signature makes string arguments a caller precondition (see **string-precondition**), and the one call site always passes strings: `rowSearchText` returns a template string and `q` is `useState("")` text.
- **Large inputs**: Cost grows with the number of tokens times the length of `haystack`, and both strings are lowercased again on every call. The function sets no length limit, and `ActivityPanel` calls it once per row whenever its `useMemo` dependencies change.
- **Concurrent access**: Not applicable. The function is stateless and runs on single-threaded JavaScript, so calls cannot interleave.
- **Error states, offline, timeouts and cancellation**: Not applicable. The function does no I/O and finishes synchronously, so there is nothing to time out, cancel or lose a connection to.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `haystack` | `string` | none (required) | The text searched. At the call site this is `rowSearchText(row)`: the row's `name`, `environment`, `statusWord`, `detail` and `commitBody` joined with spaces. |
| `query` | `string` | none (required) | The user's free-text query. Trimmed, lowercased and split on whitespace into AND-ed tokens. A blank value matches everything. |

The function reads no environment variables, settings keys or injected dependencies.

## Deep Linking

Not applicable: `filter.ts` exports one pure function and has no navigable surface. The query lives in `ActivityPanel`'s local `useState`, not in a URL.

## Localization

Not applicable: the function returns a `boolean` and produces no user-facing text. Its only locale-related behavior is the locale-independent `toLowerCase`, covered under **case-insensitive**.

## Accessibility Options

Not applicable: the function renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and the match rule always applies.

## Analytics

Not applicable: the function emits no events.

## Privacy

Not applicable: the function reads its two string arguments in memory and stores, logs and transmits nothing.

## Logging

Not applicable: `filter.ts` makes no log calls.

## Platform Notes

- **SwiftUI**: Port as a free function `func matchesQuery(_ haystack: String, _ query: String) -> Bool`. Trim with `trimmingCharacters(in: .whitespacesAndNewlines)`, lowercase with `lowercased()` (locale-independent, like `toLowerCase`), split with `split(whereSeparator: \.isWhitespace)` (which drops empty pieces), and test with `allSatisfy { h.contains($0) }`. Swift `String.contains` compares by Character with canonical equivalence, so precomposed and decomposed `é` DO match in Swift. To keep **no-normalization**, compare `unicodeScalars` or UTF-16 views instead. Use `localizedStandardContains` only if the port is meant to diverge from the source. Bind the query to a `@State` string and filter in a computed property.
- **Compose**: Write a top-level Kotlin `fun matchesQuery(haystack: String, query: String): Boolean`. Use `query.trim().lowercase()`, `split(Regex("\\s+"))` and `all { h.contains(it) }`. Kotlin `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `lowercase(Locale.getDefault())`. Kotlin `trim()` trims by `Char.isWhitespace`, and the `\s` regex class covers ASCII whitespace unless `UNICODE_CHARACTER_CLASS` is set, so no-break spaces behave differently from JavaScript. Filter inside `remember(rows, query) { rows.filter { … } }` or `derivedStateOf`.
- **React/Web**: This is the source: `src/lib/filter.ts`, tested by `src/lib/filter.test.ts` (vitest) and called only from `src/components/ActivityPanel.tsx` together with `rowSearchText` from `src/lib/row-model.ts`. It relies on `String.prototype.trim`, `toLowerCase`, `split(/\s+/)`, `Array.prototype.every` and `String.prototype.includes`.
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

**Decision**: Use `includes` and `toLowerCase`, not a regular expression or a locale-aware collator.
**Rationale**: Literal `includes` means user input can never be read as a pattern or throw on metacharacters (filter-019). Locale-independent lowercasing gives the same result in every browser locale. The cost is no Unicode normalization and no locale-specific case folding, which the edge cases record.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |

**Separation of concerns.** `filter.ts` holds only the match rule. It knows nothing about rows, React or the search box. `ActivityPanel` builds the haystack through `rowSearchText` and applies the result.

**Unit test coverage.** `filter.test.ts` covers the three behaviors in the doc comment: blank query, case-insensitive substring, and token-AND. It includes a negative case for each of the last two.

**Explicit error handling.** No failure path exists for string inputs. Tokens are matched with `includes`, never compiled into a regular expression, so user input cannot cause a runtime error. Non-string input is excluded by the TypeScript signature.

**Good test properties.** The tests are deterministic and isolated, with no mocks, clock or I/O. Each `it` block names the single behavior it asserts.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from `filter.ts` and `filter.test.ts` |
