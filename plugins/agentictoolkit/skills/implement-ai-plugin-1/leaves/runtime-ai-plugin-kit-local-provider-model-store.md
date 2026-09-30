<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-provider-model-store · source: ai-plugin-runtime-ai-plugin-kit-local-provider-model-store.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-provider-model-store#<slug>`):

- `loopback-detection` MUST
- `page-stats-shape` MUST
- `per-baseurl-cache-scope` MUST
- `global-cache-scope` MUST
- `cached-accessors-are-pure-reads` MUST
- `models-endpoint` MUST
- `models-fetch-success` MUST
- `models-fetch-failure` MUST
- `sizes-endpoint` MUST
- `sizes-parse-tolerance` MUST
- `sizes-fetch-success` MUST
- `sizes-fetch-failure` MUST
- `metadata-endpoint` MUST
- `metadata-merge-on-success` MUST
- `model-info-sequential-order` MUST
- `model-info-page-skipped` MUST
- `description-precedence` MUST
- `description-non-substantial-fallback` MUST
- `description-cache-write` MUST
- `stats-cache-write` MUST
- `rank-independent-of-page` MUST
- `per-field-independent-nil` MUST
- `no-request-coalescing` MUST
- `mainactor-atomic-cache-update` MUST
- `cancellation-as-ordinary-failure` MUST
- `cache-persistence` MUST
- `cache-non-secure-storage` MUST

# LocalProviderModelStore

## Overview

`LocalProviderModelStore` (`packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift`)
is a `@MainActor`-isolated Swift `enum` — no visual surface — that gives
AIPluginKit's model chooser live model discovery for **local** (loopback)
OpenAI-compatible providers such as Ollama. Per the type's own doc comment: a
local server's installed models are known only to that server, so a fixed
remote descriptor catalog can neither know what the user pulled nor stay
correct as models are pulled or removed; the store instead lists a local
server's models by asking it directly, caches the last successful fetch per
`baseURL` so the chooser paints instantly and keeps working while the server
is down, and re-fetches on every rebuild to catch changes. A second,
independent responsibility — `fetchModelInfo(model:viaOllamaPage:)` — batches
per-model enrichment (a prose description, ollama.com popularity stats, and
an Artificial Analysis leaderboard rank) from several live sources into one
call. Remote (non-loopback) providers are explicitly out of scope for this
type: per the doc comment, they "keep their descriptor catalog," which this
file does not touch.

## Behavioral Requirements

- **loopback-detection**: `isLocal(baseURL:)` MUST return
  `LocalModelServer.isLoopback(baseURL:)`'s result unchanged — `true` only
  when `URL(string: baseURL)?.host?.lowercased()` is exactly one of
  `localhost`, `127.0.0.1`, `0.0.0.0`, `::1`, or `[::1]`, and `false` for any
  other host or for a `baseURL` from which no host can be parsed.
- **page-stats-shape**: `LocalModelPageStats` MUST be `Codable`, `Sendable`,
  and `Equatable`, and MUST hold `downloads: String?` and `updated: String?`
  as two independently optional fields — one MAY be present without the
  other.
- **per-baseurl-cache-scope**: The models cache (`aiplugin.localModelCache`,
  `[String: [String]]`) and the sizes cache (`aiplugin.localModelSizeCache`,
  `[String: [String: Int]]`) MUST be keyed by the exact `baseURL` string
  passed to their respective `fetch*`/`cached*` functions, with no
  normalization of that key; the metadata cache
  (`aiplugin.localModelMetadataCache`, `[String: [String: OllamaModelMetadata]]`)
  MUST additionally nest by model id under each `baseURL`.
- **global-cache-scope**: The description cache
  (`aiplugin.ollamaModelDescriptionCache`, `[String: String]`) and the page-stats
  cache (`aiplugin.ollamaModelPageStatsCache`, `[String: LocalModelPageStats]`)
  MUST be keyed by model id alone, shared globally across every `baseURL` —
  two different servers that each expose a model of the same id share one
  cached description and one cached page-stats entry.
- **cached-accessors-are-pure-reads**: `cachedModels`, `cachedSizes`,
  `cachedMetadata`, `cachedDescriptions`, and `cachedPageStats` MUST read
  their respective cache synchronously, without making a network request,
  and MUST return an empty collection (`[]` or `[:]`) rather than `nil` when
  no entry exists for the requested key.
- **models-endpoint**: `fetchModels(baseURL:)` MUST strip at most one
  trailing `/` from `baseURL`, MUST build the request URL by appending the
  literal path `/models` to the result, and MUST issue a `GET` request with
  `timeoutInterval` `5` seconds.
- **models-fetch-success**: `fetchModels` MUST treat a response as
  successful only when the HTTP status is `200` and the body decodes as
  `{"data":[{"id": String}, ...]}` into a non-empty array of ids; on success
  it MUST replace the cached entry for `baseURL` with that id array and MUST
  return the same array.
- **models-fetch-failure**: `fetchModels` MUST return `nil`, and MUST leave
  the cached entry for `baseURL` unchanged, for every other outcome: an
  unbuildable request URL, a thrown transport error, a non-`200` status, an
  undecodable body, or a decoded-but-empty id array.
- **sizes-endpoint**: `fetchSizes(baseURL:)` MUST derive its request URL via
  `LocalModelServer.nativeTagsURL(baseURL:)` (which strips all trailing
  slashes and one trailing `/v1` before appending `/api/tags`) and MUST issue
  a `GET` request with `timeoutInterval` `5` seconds.
- **sizes-parse-tolerance**: `fetchSizes` MUST parse a `200` response body
  with `LocalModelServer.parseSizes(_:)`, which decodes each `models[]` entry
  independently and skips one that fails to decode rather than discarding the
  whole response.
- **sizes-fetch-success**: When `nativeTagsURL` succeeds, the response is
  `200`, and the parsed sizes map is non-empty, `fetchSizes` MUST replace the
  cached entry for `baseURL` with that map and MUST return it.
- **sizes-fetch-failure**: `fetchSizes` MUST return `nil`, and MUST leave the
  cached entry for `baseURL` unchanged, when `nativeTagsURL` returns `nil`,
  the request throws, the status is not `200`, or the parsed sizes map is
  empty.
- **metadata-endpoint**: `fetchMetadata(baseURL:model:)` MUST obtain metadata
  by calling `LocalModelMetadataStore.fetch(openAIBaseURL:model:)` and MUST
  return `nil` immediately, without modifying the metadata cache, when that
  call returns `nil`.
- **metadata-merge-on-success**: On a non-nil result, `fetchMetadata` MUST
  merge the new `model: meta` pair into the existing per-`baseURL` dictionary
  (creating one if none exists) rather than replacing the whole per-`baseURL`
  dictionary, so previously cached models under the same `baseURL` MUST
  remain present.
- **model-info-sequential-order**: `fetchModelInfo(model:viaOllamaPage:)`
  MUST `await` its three sources strictly in sequence — first
  `ModelCatalogStore.description(for:)`, then `ArtificialAnalysisStore.rank(for:)`,
  then, only when `viaOllamaPage` is `true`, `OllamaModelPageStore.fetchInfo(model:)`
  — never concurrently (no `async let`).
- **model-info-page-skipped**: When `viaOllamaPage` is `false`,
  `fetchModelInfo` MUST NOT call `OllamaModelPageStore.fetchInfo`, and the
  returned `stats` MUST be `nil`.
- **description-precedence**: `fetchModelInfo`'s returned `description` MUST
  be the page's description when `viaOllamaPage` is `true`, the page fetch
  succeeded, the page description is non-nil, AND
  `ModelCatalogStore.isSubstantial(_:)` (at least 40 characters and
  containing a space) returns `true` for it; otherwise it MUST fall back to
  the catalog description (`ModelCatalogStore.description(for:)`'s result)
  whenever that is non-nil.
- **description-non-substantial-fallback**: When the page description is
  non-nil but not substantial and the catalog produced no description
  (`catalogDescription == nil`), `fetchModelInfo` MUST return that
  non-substantial page description unchanged rather than discarding it.
- **description-cache-write**: Whenever `fetchModelInfo` resolves a non-nil
  `description`, it MUST write it into the description cache under `model`,
  overwriting any previous entry for that model regardless of which
  `baseURL` the call concerned.
- **stats-cache-write**: `fetchModelInfo` MUST write `stats` into the
  page-stats cache under `model`, and MUST return a non-nil `stats`, only
  when `viaOllamaPage` is `true`, the page fetch succeeded, and at least one
  of the page's `downloads`/`updated` is non-nil; in every other case it MUST
  leave the page-stats cache for `model` unchanged and MUST return `nil` for
  `stats`.
- **rank-independent-of-page**: `fetchModelInfo` MUST obtain and return
  `rank` (via `ArtificialAnalysisStore.rank(for:)`) regardless of the value
  of `viaOllamaPage`.
- **per-field-independent-nil**: `fetchModelInfo`'s three returned fields
  (`description`, `stats`, `rank`) MUST each independently be `nil` when
  their own respective source failed or was skipped, without one field's
  failure affecting another's value.
- **no-request-coalescing**: `fetchModels`, `fetchSizes`, and `fetchMetadata`
  MUST NOT deduplicate or join concurrent calls for the same key — unlike
  `ModelCatalogStore.catalog()` and `ArtificialAnalysisStore`'s `inflight`-task
  pattern, each concurrent call to one of these three functions MUST perform
  its own network request.
- **mainactor-atomic-cache-update**: `LocalProviderModelStore` MUST be
  `@MainActor`-isolated, and every read-modify-write of a cache dictionary
  (read `.value`, mutate the local copy, write `.value` back) MUST execute
  with no intervening `await`, so that two calls writing to *different* keys
  cannot interleave mid-update and lose one another's write.
- **cancellation-as-ordinary-failure**: `fetchModels` and `fetchSizes` MUST
  treat a `CancellationError` thrown from their `await` exactly like any
  other thrown error — caught by the same `catch`, returning `nil` and
  leaving the cache unmodified — with no distinct cancellation handling.
- **cache-persistence**: All five caches MUST be declared as `UserSetting`,
  so each persists through whichever settings store `UserSettings.shared`
  routes to (`UserDefaultsSettingsStorageProvider` by default) and MUST
  survive process restart for as long as that store retains the key.
- **cache-non-secure-storage**: None of the five `UserSetting` declarations
  MUST pass `isSecure: true`; all five default to `isSecure: false` and are
  therefore held by the non-secure settings provider, never the
  Keychain-backed secure provider.

One concern the code's own purpose calls for is left undefined by the
source:

- **concurrent-fetch-deduplication**: NEEDS REVIEW: Not implemented in source. `fetchModels`/`fetchSizes`/`fetchMetadata` each read the current cache, `await` a network call, and only afterward write a new value back; because `@MainActor` methods are reentrant across `await`, two concurrent calls for the same `baseURL` (or `baseURL`/`model` pair) can both observe the same pre-fetch cache state and both issue their own request, and the cached value that survives is whichever call's write statement runs last — determined by network completion order, not by which call was issued most recently. This cannot be resolved from `LocalProviderModelStore.swift` alone: it requires either an explicit statement that duplicate concurrent fetches for the same key are an accepted cost, or an in-flight-`Task` cache keyed by `baseURL`/model, mirroring `ModelCatalogStore.catalog()`'s own `inflight` pattern one file over.

A related behavior is a fact, not a gap:

- **fetch-error-is-fully-swallowed**: Every failure path in `fetchModels`,
  `fetchSizes`, `fetchMetadata`, and the sources `fetchModelInfo` calls into
  discards its error via a bare `catch { return nil }` or `try?`, and none of
  them logs — there is no `Logger`/`os_log`/`print` call anywhere in this
  file. A maintainer investigating why a local server's models stopped
  refreshing has no signal in this file distinguishing "server refused the
  connection" from "timed out" from "returned an undecodable body."

