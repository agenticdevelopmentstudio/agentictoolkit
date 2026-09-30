<!-- leaf: implement-status-web-src-lib-1/filter · source: status-web-src-lib-filter.md -->

**Rules** (cite as `implement-status-web-src-lib-1/filter#<slug>`):

- `signature` MUST
- `synchronous-result` MUST
- `no-side-effects` MUST
- `query-trim` MUST
- `empty-query-matches-all` MUST
- `case-insensitive` MUST
- `tokenization` MUST
- `token-and` MUST
- `substring-anywhere` MUST
- `literal-token` MUST
- `order-independent` MUST
- `overlap-allowed` MUST
- `haystack-untrimmed` MUST
- `no-normalization` MUST
- `string-precondition` MUST
- `no-errors-for-strings` MUST

# Activity Query Filter

## Overview

`filter.ts` (`packages/web/packages/status-web/src/lib/filter.ts`) exports one pure function, `matchesQuery(haystack, query)`. Its doc comment states the contract: "Case-insensitive, token-AND substring match. Every whitespace-separated token in `query` must appear somewhere in `haystack`. An empty query matches all."

Its one call site is `ActivityPanel` (`src/components/ActivityPanel.tsx`). Inside a `useMemo`, the panel keeps a row when it passes the source filter (useSourceFilter) AND `matchesQuery(rowSearchText(r), q)` is true. `q` is the raw text of the panel's search box. `rowSearchText` (`src/lib/row-model.ts`) joins the row's `name`, `environment`, `statusWord`, `detail` and `commitBody` with single spaces. The module holds no state and does no I/O.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `haystack` | `string` | none (required) | The text searched. At the call site this is `rowSearchText(row)`: the row's `name`, `environment`, `statusWord`, `detail` and `commitBody` joined with spaces. |
| `query` | `string` | none (required) | The user's free-text query. Trimmed, lowercased and split on whitespace into AND-ed tokens. A blank value matches everything. |

The function reads no environment variables, settings keys or injected dependencies.

## Platform Notes

- **SwiftUI**: Port as a free function `func matchesQuery(_ haystack: String, _ query: String) -> Bool`. Trim with `trimmingCharacters(in: .whitespacesAndNewlines)`, lowercase with `lowercased()` (locale-independent, like `toLowerCase`), split with `split(whereSeparator: \.isWhitespace)` (which drops empty pieces), and test with `allSatisfy { h.contains($0) }`. Swift `String.contains` compares by Character with canonical equivalence, so precomposed and decomposed `é` DO match in Swift. To keep **no-normalization**, compare `unicodeScalars` or UTF-16 views instead. Use `localizedStandardContains` only if the port is meant to diverge from the source. Bind the query to a `@State` string and filter in a computed property.
- **Compose**: Write a top-level Kotlin `fun matchesQuery(haystack: String, query: String): Boolean`. Use `query.trim().lowercase()`, `split(Regex("\\s+"))` and `all { h.contains(it) }`. Kotlin `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `lowercase(Locale.getDefault())`. Kotlin `trim()` trims by `Char.isWhitespace`, and the `\s` regex class covers ASCII whitespace unless `UNICODE_CHARACTER_CLASS` is set, so no-break spaces behave differently from JavaScript. Filter inside `remember(rows, query) { rows.filter { … } }` or `derivedStateOf`.
- **React/Web**: This is the source: `src/lib/filter.ts`, tested by `src/lib/filter.test.ts` (vitest) and called only from `src/components/ActivityPanel.tsx` together with `rowSearchText` from `src/lib/row-model.ts`. It relies on `String.prototype.trim`, `toLowerCase`, `split(/\s+/)`, `Array.prototype.every` and `String.prototype.includes`.
- **AppKit / UIKit**: Use the same pure Swift function as the SwiftUI port. In AppKit, feed it from an `NSSearchField`'s `stringValue` and filter the table's data source. In UIKit, feed it from `UISearchController.searchBar.text` in `updateSearchResults(for:)`. Nothing in the function is UI-bound, so it belongs in a shared framework target.
- **WinUI 3**: Port as `public static bool MatchesQuery(string haystack, string query)` in a `static class`. Use `query.Trim().ToLowerInvariant()` (not `ToLower()`, which follows `CultureInfo.CurrentCulture` and would fold Turkish I differently), then `q.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)` to split on all Unicode whitespace without empty entries, then `tokens.All(t => h.Contains(t, StringComparison.Ordinal))`. Use ordinal comparison: culture-aware comparison would treat canonically equivalent forms as equal and break **no-normalization**. An empty query returns `true` before splitting. The function stays synchronous with no `Task`. In the view model, bind an `AutoSuggestBox` or `TextBox` `Text` to a `Query` property that raises `INotifyPropertyChanged`, and on change rebuild an `ObservableCollection<Row>` (or set `AdvancedCollectionView.Filter` from the Community Toolkit) with `rows.Where(r => MatchesQuery(RowSearchText(r), Query))`.

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
