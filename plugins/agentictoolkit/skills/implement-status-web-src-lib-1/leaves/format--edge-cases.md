<!-- leaf: implement-status-web-src-lib-1/format--edge-cases · source: status-web-src-lib-format.md -->

# Display Format Helpers

**Rules** (cite as `implement-status-web-src-lib-1/format--edge-cases#<slug>`):

- `null-and-empty-input` MUST — shortSha and commitFirstLine MUST return null for null, undefined and "" (format-003, format-007). plural with an empty …
- `whitespace-only-input` MUST — A hash or message consisting only of spaces is non-empty and MUST be processed, not treated as missing: shortSha(" ") …
- `boundary-at-exactly-7-and-exactly-max` MUST — A 7-character hash MUST be returned unchanged; a subject whose length equals max MUST be returned unchanged, because …
- `max-of-zero` MUST — commitFirstLine("abc", 0) MUST return "".
- `negative-max` MUST — The function does not validate max. With a negative max the length test is always true and the slice counts from the …
- `nan-max` MUST — A length compared with NaN is never greater, so commitFirstLine(s, NaN) MUST return the whole first line uncapped.
- `non-integer-n-in-plural` MUST — plural(1.0, "site") MUST return "1 site" (1.0 equals 1); plural(NaN, "site") MUST return "NaN sites".
- `surrogate-pairs` MAY — Truncation counts UTF-16 code units and MAY split a surrogate pair at the cap (format-020); commit hashes are ASCII, so …
- `windows-line-endings` MUST — A CRLF message MUST keep the trailing carriage return on the subject (format-011).

## Edge Cases

- **Null and empty input**: `shortSha` and `commitFirstLine` MUST return `null` for `null`, `undefined` and `""` (format-003, format-007). `plural` with an empty `singular` MUST return the number, a space, and `"s"` for `n !== 1` (for example `plural(2, "")` is `"2 s"`) or the number and a trailing space for `n === 1`.
- **Whitespace-only input**: A hash or message consisting only of spaces is non-empty and MUST be processed, not treated as missing: `shortSha("   ")` returns `"   "`.
- **Boundary at exactly 7 and exactly `max`**: A 7-character hash MUST be returned unchanged; a subject whose length equals `max` MUST be returned unchanged, because the cap applies only when the length is strictly greater than `max`.
- **`max` of zero**: `commitFirstLine("abc", 0)` MUST return `""`.
- **Negative `max`**: The function does not validate `max`. With a negative `max` the length test is always true and the slice counts from the end, so `commitFirstLine("abcdef", -2)` MUST return `"abcd"` (the last two characters dropped). No caller in the package passes `max`; the default 200 is the only value used.
- **`NaN` `max`**: A length compared with `NaN` is never greater, so `commitFirstLine(s, NaN)` MUST return the whole first line uncapped.
- **Non-integer `n` in `plural`**: `plural(1.0, "site")` MUST return `"1 site"` (1.0 equals 1); `plural(NaN, "site")` MUST return `"NaN sites"`.
- **Surrogate pairs**: Truncation counts UTF-16 code units and MAY split a surrogate pair at the cap (format-020); commit hashes are ASCII, so `shortSha` is unaffected in practice.
- **Windows line endings**: A CRLF message MUST keep the trailing carriage return on the subject (format-011).
- **Concurrent access**: Not applicable — the functions are pure, synchronous and stateless, so concurrent callers cannot observe each other.
- **Error states**: Not applicable — the functions touch no file, network or other dependency and cannot fail for inputs of their declared types.
- **Offline or disconnected state**: Not applicable — no network is involved.
