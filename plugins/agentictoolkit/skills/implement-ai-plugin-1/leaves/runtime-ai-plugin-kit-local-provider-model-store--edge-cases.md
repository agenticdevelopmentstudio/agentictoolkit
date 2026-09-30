<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-provider-model-store--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-local-provider-model-store.md -->

# LocalProviderModelStore

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-provider-model-store--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty baseURL passed to fetchModels yields trimmed == "", and URL(string: "/models") still parses successfully as a …
- `concurrent-access` MUST — LocalProviderModelStore is @MainActor-isolated, so calls interleave only at await points; a single call's own …
- `error-states` MUST — Every network failure — a bad URL, a thrown transport error, a non-200 status, an undecodable body, or (for fetchSizes) …
- `offline-or-disconnected-state` MUST — When the target baseURL server is unreachable (process not running, host down), every direct request in this file …
- `cancellation-and-timeouts` MUST — fetchModels and fetchSizes bound their own URLRequest to a 5-second timeoutInterval; a timeout is an ordinary thrown …

## Edge Cases

- **Null and empty input**: An empty `baseURL` passed to `fetchModels` yields
  `trimmed == ""`, and `URL(string: "/models")` still parses successfully as
  a schemeless relative URL, so the request is attempted and fails at the
  transport layer (folds into `models-fetch-failure`), MUST. An empty
  `baseURL` passed to `fetchSizes` or `fetchMetadata` (via
  `LocalModelServer.nativeTagsURL`/`LocalModelMetadataStore.nativeOllamaBase`)
  trims to empty and yields `nil`/no usable URL before any request is made,
  MUST. An empty `model` string is not special-cased anywhere in this file —
  it is forwarded verbatim to `LocalModelMetadataStore.fetch`,
  `OllamaModelPageStore.fetchInfo` (which returns `nil` for an empty name),
  and `ModelCatalogStore.description(for:)`/`ArtificialAnalysisStore.rank(for:)`
  (which fail their internal matching), so `fetchModelInfo(model: "", ...)`
  resolves every field to whatever its collaborator returns for an empty id
  — typically all `nil` — with no explicit empty-string guard.
- **Boundary values**: A `baseURL` with exactly one trailing slash is
  stripped correctly by `fetchModels` (`hasSuffix("/")` check); a
  `baseURL` with two or more trailing slashes has only one removed, so the
  request URL ends up with an embedded double slash before `/models` — a
  direct, undocumented consequence of the single (not looping) strip,
  unlike `LocalModelServer.nativeTagsURL`'s `while` loop, which strips all of
  them. This recipe records that divergence rather than assuming both
  functions normalize identically (see Design Decisions).
- **Concurrent access**: `LocalProviderModelStore` is `@MainActor`-isolated,
  so calls interleave only at `await` points; a single call's own
  read-modify-write of a cache dictionary is never split across an `await`,
  so writes to *different* keys never corrupt or lose one another (MUST, see
  `mainactor-atomic-cache-update`). Two *concurrent* calls for the *same*
  key are not deduplicated and race on which one's result is cached last
  (MUST NOT deduplicate, see `no-request-coalescing`; final value undefined,
  see the open question on concurrent-fetch-deduplication).
- **Error states**: Every network failure — a bad URL, a thrown transport
  error, a non-`200` status, an undecodable body, or (for `fetchSizes`) a
  parse that yields no entries — is treated identically: the affected
  function returns `nil` and its cache entry is left exactly as it was
  (MUST, see `models-fetch-failure`, `sizes-fetch-failure`,
  `metadata-endpoint`). None of these paths logs, throws to the caller, or
  otherwise signals which specific failure occurred — see
  `fetch-error-is-fully-swallowed` in Behavioral Requirements.
- **Offline or disconnected state**: When the target `baseURL` server is
  unreachable (process not running, host down), every direct request in this
  file (`/models`, the derived `/api/tags`, and, via `fetchMetadata`, the
  derived `/api/show`) throws a transport error that is caught and folded
  into the ordinary failure path above; callers are expected to keep
  rendering `cachedModels`/`cachedSizes`/`cachedMetadata` for that `baseURL`
  in the meantime, per the type's own doc comment ("keeps working when the
  server is down"), MUST.
- **Cancellation and timeouts**: `fetchModels` and `fetchSizes` bound their
  own `URLRequest` to a `5`-second `timeoutInterval`; a timeout is an
  ordinary thrown error caught by the same `catch` as any other transport
  failure (MUST, see `cancellation-as-ordinary-failure`). Task cancellation
  during any of the `await`s inside `fetchModelInfo` (the catalog, rank, or
  page call) is not special-cased in this file; whatever each collaborator
  returns for a cancelled call (typically `nil`, per each collaborator's own
  degrade-to-`nil` contract) flows through unchanged.
- **Missing file or unreachable server**: Not applicable as a distinct
  code path — a local server process that has quit, or one that is running
  but is not Ollama (so `/api/tags`/`/api/show` don't exist), is
  indistinguishable in this file from any other transport failure or
  non-`200`/undecodable response; see Error states above.
