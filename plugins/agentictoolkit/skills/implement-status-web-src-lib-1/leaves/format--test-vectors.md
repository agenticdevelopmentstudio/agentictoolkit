<!-- leaf: implement-status-web-src-lib-1/format--test-vectors · source: status-web-src-lib-format.md -->

# Display Format Helpers

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| format-001 | short-sha-prefix | `shortSha("abcdef1234567")` | `"abcdef1"` (from `format.test.ts`) |
| format-002 | short-sha-short-input | `shortSha("abc")` | `"abc"` (from `format.test.ts`) |
| format-003 | short-sha-empty-null | `shortSha(null)`, `shortSha(undefined)`, `shortSha("")` | `null` for each (from `format.test.ts`) |
| format-004 | short-sha-no-validation | `shortSha("  zz-not-hex")` | `"  zz-no"` |
| format-005 | first-line-subject | `commitFirstLine("subject\n\nbody text")` | `"subject"` (from `format.test.ts`) |
| format-006 | first-line-subject, first-line-under-cap | `commitFirstLine("just one line")` | `"just one line"` (from `format.test.ts`) |
| format-007 | first-line-empty-null | `commitFirstLine(null)`, `commitFirstLine(undefined)`, `commitFirstLine("")` | `null` for each (from `format.test.ts`) |
| format-008 | first-line-default-max, first-line-cap | `commitFirstLine("x" repeated 250 times)` | a string of length 200 (from `format.test.ts`) |
| format-009 | first-line-cap, first-line-no-ellipsis | `commitFirstLine("x" repeated 250 times, 10)` | `"xxxxxxxxxx"` — length 10, no ellipsis (from `format.test.ts`) |
| format-010 | first-line-under-cap | `commitFirstLine("short", 200)` | `"short"` (from `format.test.ts`) |
| format-011 | first-line-lf-only | `commitFirstLine("subject\r\nbody")` | `"subject\r"` |
| format-012 | first-line-empty-subject | `commitFirstLine("\nbody")` | `""` |
| format-013 | plural-singular-at-one, plural-output-shape | `plural(1, "site")` | `"1 site"` |
| format-014 | plural-default-form, plural-plural-otherwise | `plural(3, "site")` | `"3 sites"` |
| format-015 | plural-plural-otherwise | `plural(0, "project")` | `"0 projects"` |
| format-016 | plural-plural-otherwise | `plural(-1, "site")` | `"-1 sites"` |
| format-017 | plural-default-form | `plural(2, "person", "people")` | `"2 people"` |
| format-018 | plural-number-rendering | `plural(1000, "site")`, `plural(1.5, "site")` | `"1000 sites"`, `"1.5 sites"` |
| format-019 | plural-english-rule | `plural(21, "site")` | `"21 sites"` regardless of runtime locale |
| format-020 | utf16-length | `commitFirstLine("ab😀cd", 3)` | a 3-code-unit string: `"ab"` followed by the lone high surrogate of the emoji |
| format-021 | pure-functions, synchronous | call each export twice with the same arguments | identical return values; no observable side effect; the return value is not a Promise |
