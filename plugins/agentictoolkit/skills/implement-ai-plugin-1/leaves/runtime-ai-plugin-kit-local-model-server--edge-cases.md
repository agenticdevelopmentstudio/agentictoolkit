<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-local-model-server.md -->

# LocalModelServer

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server--edge-cases#<slug>`):

- `empty-baseurl-to-isloopback` MUST — isLoopback(baseURL: "") MUST return false — the URL(string:)?.host chain fails on an empty string …
- `scheme-less-baseurl-to-isloopback` MUST — A baseURL with no http:// or https:// prefix (e.g. "localhost:11434") parses with .host == nil, so isLoopback MUST …
- `baseurl-that-trims-to-empty-for-nativetagsurl` MUST — A baseURL such as "/v1" or "///" reduces, through the slash- and /v1-stripping passes, to an empty string, and …
- `repeated-trailing-slashes` MUST — A baseURL such as "http://localhost:11434/v1////" MUST resolve to "http://localhost:11434/api/tags"; both stripping …
- `mixed-case-v1-suffix` MUST — "http://localhost:11434/V1" MUST also strip to "http://localhost:11434/api/tags", because the suffix check is …
- `malformed-json-to-parsesizes` MUST — Non-JSON bytes (e.g. "not json") MUST yield [:], not a thrown error or a crash (parse-sizes-whole-decode-failure-empty).
- `well-formed-json-wrong-top-level-shape` MUST — JSON that is valid but does not contain a models array at all (e.g. {} or {"models": {}}) MUST also yield [:], because …
- `partially-malformed-entries` MUST — An entry array where some elements have wrong-typed fields MUST retain the well-formed elements and drop only the …
- `colliding-name-model-keys-across-distinct-entries` MUST — Two different entries in models that happen to share the same string in their name/model fields MUST resolve to the …
- `empty-model-string-to-size` MUST — size(of: "", in: sizes) MUST return nil unless sizes literally contains the empty string as a key (it never does from a …
- `concurrent-access` MUST — Not applicable as a race concern: LocalModelServer holds no mutable state — its only stored value, loopbackHosts, is an …

## Edge Cases

- **Empty `baseURL` to `isLoopback`.** `isLoopback(baseURL: "")` MUST return
  `false` — the `URL(string:)?.host` chain fails on an empty string
  (`is-loopback-unparseable-false`).
- **Scheme-less `baseURL` to `isLoopback`.** A `baseURL` with no `http://`
  or `https://` prefix (e.g. `"localhost:11434"`) parses with `.host ==
  nil`, so `isLoopback` MUST return `false` even though a human reader would
  recognize the string as local (`is-loopback-unparseable-false`).
- **`baseURL` that trims to empty for `nativeTagsURL`.** A `baseURL` such
  as `"/v1"` or `"///"` reduces, through the slash- and `/v1`-stripping
  passes, to an empty string, and `nativeTagsURL(baseURL:)` MUST return
  `nil` — the same outcome as a literally empty `baseURL`
  (`native-tags-url-empty-yields-nil`).
- **Repeated trailing slashes.** A `baseURL` such as
  `"http://localhost:11434/v1////"` MUST resolve to
  `"http://localhost:11434/api/tags"`; both stripping passes loop `while
  trimmed.hasSuffix("/")`, so any number of trailing slashes is removed, not
  just one (`native-tags-url-strip-trailing-slashes-first-pass`,
  `native-tags-url-strip-trailing-slashes-second-pass`).
- **Mixed-case `/v1` suffix.** `"http://localhost:11434/V1"` MUST also
  strip to `"http://localhost:11434/api/tags"`, because the suffix check is
  case-insensitive (`native-tags-url-strip-v1-suffix`).
- **Malformed JSON to `parseSizes`.** Non-JSON bytes (e.g. `"not json"`)
  MUST yield `[:]`, not a thrown error or a crash
  (`parse-sizes-whole-decode-failure-empty`).
- **Well-formed JSON, wrong top-level shape.** JSON that is valid but does
  not contain a `models` array at all (e.g. `{}` or `{"models": {}}`) MUST
  also yield `[:]`, because the outer `Tags` struct fails to decode
  (`parse-sizes-whole-decode-failure-empty`).
- **Partially malformed entries.** An entry array where some elements have
  wrong-typed fields MUST retain the well-formed elements and drop only the
  malformed ones, per element, rather than discarding the whole listing
  (`parse-sizes-per-element-tolerance`).
- **Colliding `name`/`model` keys across distinct entries.** Two different
  entries in `models` that happen to share the same string in their
  `name`/`model` fields MUST resolve to the later entry's `size` in the
  returned dictionary, with no error and no validation of the collision
  (`parse-sizes-array-order-last-write-wins`).
- **Empty `model` string to `size(of:in:)`.** `size(of: "", in: sizes)` MUST
  return `nil` unless `sizes` literally contains the empty string as a key
  (it never does from a real `/api/tags` response, since Ollama model names
  are non-empty) — ordinary dictionary-miss behavior, with no special-casing
  in this file (`size-of-total-miss-nil`).
- **Concurrent access.** Not applicable as a race concern: `LocalModelServer`
  holds no mutable state — its only stored value, `loopbackHosts`, is an
  immutable `private static let` — so any number of concurrent calls to any
  of its four functions from any threads or actors simultaneously MUST
  produce no data race, by construction, with no synchronization required.
- **Offline or disconnected state.** Not applicable to this file directly:
  `LocalModelServer.swift` performs no network I/O itself.
  `nativeTagsURL(baseURL:)` only derives a URL string, and `parseSizes(_:)`
  only parses `Data` the caller has already fetched (or failed to fetch);
  connectivity loss and its handling are the caller's concern
  (`LocalModelCatalog`, `LocalProviderModelStore`, `DaemonAIChat`), not
  this file's.
- **Missing or unreachable server / cancellation / timeout.** Not
  applicable to this file directly, for the same reason as offline state:
  there is no request, file handle, or async task in `LocalModelServer.swift`
  to time out, go unreachable, or be cancelled. Every one of its functions
  is synchronous and non-throwing (`synchronous-non-throwing`).
