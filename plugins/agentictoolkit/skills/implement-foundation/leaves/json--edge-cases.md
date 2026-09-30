<!-- leaf: implement-foundation/json--edge-cases · source: foundation-json.md -->

# JSONCPreprocessor

**Rules** (cite as `implement-foundation/json--edge-cases#<slug>`):

- `null-empty-input` MUST — strip("") MUST return "" — there is nothing for either scanner to act on. jsonObject(from: Data()) MUST throw: the …
- `boundary-values` MUST — The scanners impose no maximum input length; removingComments and removingTrailingCommas each MUST make one linear pass …
- `concurrent-access` MUST — Per stateless-concurrency-safety, JSONCPreprocessor MUST behave identically under any number of concurrent calls, since …
- `error-states` MUST — A document that fails to decode under every candidate encoding, or that decodes but fails to parse under every …

## Edge Cases

- **Null / empty input**: `strip("")` MUST return `""` — there is nothing for either scanner to act on. `jsonObject(from: Data())` MUST throw: the UTF-8 candidate decodes the empty bytes to `""`, which strips to `""` and fails to parse as JSON via `JSONSerialization`; every other candidate encoding either fails to decode zero bytes or produces the same empty, unparseable text, so the loop exhausts all six candidates and the final fallback call on the empty `Data` also throws, propagating to the caller — this is a MUST, since nothing in the source special-cases an empty payload.
- **Boundary values**: The scanners impose no maximum input length; `removingComments` and `removingTrailingCommas` each MUST make one linear pass over every character of `text` regardless of size, with no early exit and no configurable ceiling — a caller passing an arbitrarily large `Data` value MUST have every byte considered by both scanners. A document consisting of a single unmatched `"` (an opened-but-never-closed string) MUST leave both scanners in `inString == true` for the remainder of the text, meaning any `//`, `/*`, or trailing comma after that point MUST be preserved rather than treated as syntax, and the resulting document MUST then fail to parse (the mechanism is `block-comment-unterminated-consumes-rest`'s sibling case, not a separate one — the source draws no distinction between an unterminated string and an unterminated comment: both simply run to the end of the text).
- **Concurrent access**: Per `stateless-concurrency-safety`, `JSONCPreprocessor` MUST behave identically under any number of concurrent calls, since it holds no actor isolation and no mutable state of any kind — this is not a caveat but the direct consequence of being a caseless `enum` with one immutable `static let`.
- **Error states**: A document that fails to decode under every candidate encoding, or that decodes but fails to parse under every candidate after stripping, MUST cause `jsonObject(from:)` to throw the error `JSONSerialization.jsonObject(with: data)` raises for the caller's original, unmodified bytes (`jsonobject-fallback-on-raw-bytes`) — the source never wraps, annotates, or replaces that error with one of its own, and never returns a partial or best-effort result. `jsonData(from:)` MUST propagate that same error unchanged when its re-encode path is taken (`jsondata-propagates-jsonobject-errors`).
- **Offline / disconnected state**: Not applicable — `JSONCPreprocessor` performs no network I/O of any kind (`no-side-effects`); it operates only on the `text`/`data` parameter a caller already holds in memory.
