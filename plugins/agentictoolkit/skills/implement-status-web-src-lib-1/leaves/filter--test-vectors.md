<!-- leaf: implement-status-web-src-lib-1/filter--test-vectors · source: status-web-src-lib-filter.md -->

# Activity Query Filter

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
