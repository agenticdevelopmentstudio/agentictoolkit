<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-catalog--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-local-model-catalog.md -->

# LocalModelCatalog

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-catalog--edge-cases#<slug>`):

- `empty-baseurl` MUST — sizeBytes(model:baseURL:) with baseURL: "" MUST return nil; LocalModelServer.nativeTagsURL(baseURL: "") returns nil, so …
- `baseurl-that-trims-to-empty` MUST — A baseURL such as "/v1" or "///" trims (via slash- and /v1-stripping) to an empty string inside …
- `empty-model-name` MUST — sizeBytes(model: "", baseURL:) MUST return nil unless the server's parsed sizes map literally contains the empty string …
- `ttl-boundary` MUST — An entry aged exactly successTTL (or failureTTL) seconds MUST be treated as expired, not fresh, because the freshness …
- `server-unreachable` MUST — When the local server's process is not running or the host is otherwise unreachable, fetcher throws …
- `fetch-timeout` MUST — liveFetcher's URLRequest.timeoutInterval is 5 seconds; a server that hangs past that bound causes URLSession to throw a …
- `task-cancellation-during-a-fetch` MUST — If the calling Task is cancelled while sizes(baseURL:) is suspended on await fetcher(url), the source applies no …
- `non-ollama-local-server` MUST — A local OpenAI-compatible server that isn't ollama has no native tags endpoint; a request to the derived /api/tags URL …
- `malformed-or-partially-malformed-api-tags-payload` MUST — Garbage bytes (LocalModelServer.parseSizes returns [:] on undecodable JSON) and a payload where some model entries have …

## Edge Cases

- **Empty `baseURL`.** `sizeBytes(model:baseURL:)` with `baseURL: ""` MUST
  return `nil`; `LocalModelServer.nativeTagsURL(baseURL: "")` returns `nil`,
  so no fetch is attempted and no cache entry is created
  (`unresolvable-base-url-is-uncached`).
- **`baseURL` that trims to empty.** A `baseURL` such as `"/v1"` or `"///"`
  trims (via slash- and `/v1`-stripping) to an empty string inside
  `LocalModelServer.nativeTagsURL(baseURL:)`, which then returns `nil` — the
  same `unresolvable-base-url-is-uncached` behavior as a literally empty
  `baseURL`. MUST.
- **Empty `model` name.** `sizeBytes(model: "", baseURL:)` MUST return `nil`
  unless the server's parsed sizes map literally contains the empty string
  as a key (it never does in practice, since ollama model names are
  non-empty) — ordinary dictionary-miss behavior of
  `LocalModelServer.size(of:in:)`, with no special-casing in this file.
- **TTL boundary.** An entry aged exactly `successTTL` (or `failureTTL`)
  seconds MUST be treated as expired, not fresh, because the freshness check
  uses strict `<`, not `<=` (`cache-freshness-window`). MUST.
- **Concurrent access, single instance.** `LocalModelCatalog` is a Swift
  `actor`; distinct calls from different tasks on the same instance are
  serialized at the statement level with no possibility of a torn read or
  write of `cache`. This is applicable — `LocalModelCatalog.shared` is
  read from at least `LocalInferenceGuard`, which itself runs from multiple
  callers — and is safe by construction for memory, but see the
  open question on concurrent-fetch-deduplication above: statement-level safety does not
  prevent two concurrent callers for the same key from each triggering their
  own network fetch.
- **Server unreachable (network/offline).** When the local server's process
  is not running or the host is otherwise unreachable, `fetcher` throws
  (`URLError(.cannotConnectToHost)` from `liveFetcher`, or any error from an
  injected fetcher); `sizes(baseURL:)` treats this exactly like any other
  failed attempt — `fetch-throw-yields-no-data`, then `stale-while-error` or
  `never-known-stays-nil` depending on prior cache state. MUST. There is no
  separate "offline" code path; connectivity loss is indistinguishable from
  any other fetch failure in this file.
- **Fetch timeout.** `liveFetcher`'s `URLRequest.timeoutInterval` is `5`
  seconds; a server that hangs past that bound causes `URLSession` to throw a
  timeout error, which is caught by the same `try?` as any other thrown
  error and handled identically (`fetch-throw-yields-no-data`). MUST.
- **Task cancellation during a fetch.** If the calling `Task` is cancelled
  while `sizes(baseURL:)` is suspended on `await fetcher(url)`, the source
  applies no special handling: whatever error (or a `CancellationError`,
  depending on the fetcher) surfaces from that suspension is caught by
  `try?` and folds into the ordinary failure path exactly like any other
  thrown error, with no distinct "cancelled" outcome. MUST (this is the
  behavior, not a recommendation).
- **Non-ollama local server (no `/api/tags`).** A local OpenAI-compatible
  server that isn't ollama has no native tags endpoint; a request to the
  derived `/api/tags` URL either fails outright or returns a body that
  `LocalModelServer.parseSizes` cannot decode into any model entries. Either
  way the outcome folds into `fetch-throw-yields-no-data` or
  `empty-parse-is-treated-as-failure`; the source does not special-case
  "non-ollama server" versus "ollama server that's down." MUST.
- **Malformed or partially malformed `/api/tags` payload.** Garbage bytes
  (`LocalModelServer.parseSizes` returns `[:]` on undecodable JSON) and a
  payload where some model entries have the wrong field types (skipped
  individually, per `LocalModelServerTests.parseSizesSkipsMalformedEntries`)
  both flow through `LocalModelCatalog` unchanged: a wholly malformed
  payload triggers `empty-parse-is-treated-as-failure`; a partially malformed
  payload yields whatever subset of sizes decoded successfully, which is
  cached and served as a normal success. MUST.
