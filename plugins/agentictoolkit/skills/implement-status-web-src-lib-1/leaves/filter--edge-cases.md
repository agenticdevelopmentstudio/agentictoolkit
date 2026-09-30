<!-- leaf: implement-status-web-src-lib-1/filter--edge-cases · source: status-web-src-lib-filter.md -->

# Activity Query Filter

**Rules** (cite as `implement-status-web-src-lib-1/filter--edge-cases#<slug>`):

- `empty-or-blank-query` MUST — An empty or whitespace-only query MUST match every haystack (filter-001, filter-002, filter-007). In ActivityPanel this …
- `empty-haystack` MUST — An empty haystack MUST match only a blank query (filter-007, filter-008).
- `repeated-or-mixed-whitespace` MUST — Extra spaces, tabs, newlines and other characters matched by the regular-expression \s class between tokens MUST …
- `pattern-metacharacters` MUST — Characters such as ., *, ( and [ MUST be matched literally and MUST NOT throw (filter-011, filter-012, filter-019).
- `duplicate-tokens` MUST — A token repeated in query MUST NOT require repeated occurrences in haystack (filter-013).
- `locale-sensitive-case-pairs` MUST — Lowercasing is locale-independent, so Turkish dotted and dotless I pairs do not fold the way a Turkish user expects …
- `unicode-normal-forms` MUST — Precomposed and decomposed forms of the same character MUST NOT match each other (filter-016). No normalization step …

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
