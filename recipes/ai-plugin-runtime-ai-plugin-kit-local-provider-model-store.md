---
id: 8bdba644-d7ad-45e4-a2f5-0156bfd40e15
title: LocalProviderModelStore
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-provider-model-store
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AIPluginKit's live model discovery and cache for local (loopback) OpenAI-compatible
  providers such as Ollama, plus description, size, metadata, and rank enrichment.
platforms:
- swift
- macos
tags:
- ai-plugin
- local-model
- caching
- ollama
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-model-catalog
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-inference-guard
references:
- packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/StorableSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/ModelCatalogStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/ArtificialAnalysisStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/OllamaModelPageStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/OllamaModelMetadata.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

Two concerns the code's own purpose calls for are left undefined by the
source:

- **concurrent-fetch-deduplication**: NEEDS REVIEW: Not implemented in
  source. `fetchModels`/`fetchSizes`/`fetchMetadata` each read the current
  cache, `await` a network call, and only afterward write a new value back;
  because `@MainActor` methods are reentrant across `await`, two concurrent
  calls for the same `baseURL` (or `baseURL`/`model` pair) can both observe
  the same pre-fetch cache state and both issue their own request. The
  cached value that survives is whichever call's write statement runs last —
  determined by network completion order, not by which call was issued most
  recently. This cannot be resolved from `LocalProviderModelStore.swift`
  alone: it requires either an explicit statement that duplicate concurrent
  fetches for the same key are an accepted cost, or an in-flight-`Task`
  cache keyed by `baseURL`/model, mirroring `ModelCatalogStore.catalog()`'s
  own `inflight` pattern one file over.
- **fetch-error-is-fully-swallowed**: NEEDS REVIEW: Not implemented in
  source. Every failure path in `fetchModels`, `fetchSizes`, `fetchMetadata`,
  and the sources `fetchModelInfo` calls into discards its error via a bare
  `catch { return nil }` or `try?`, with no log call anywhere in this file.
  A maintainer investigating why a local server's models stopped refreshing
  has no signal distinguishing "server refused the connection" from
  "timed out" from "returned an undecodable body." Resolved by logging the
  discarded error (subsystem/category to be defined) or by a maintainer
  confirming that silence is intentional for this instant-paint, cache-backed
  discovery path.

## Appearance

Not applicable — this is a live model-discovery cache, not a visual
component.

## States

Not applicable — this is a live model-discovery cache, not a visual
component.

## Accessibility

Not applicable — this is a live model-discovery cache, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| local-provider-model-store-001 | loopback-detection | `isLocal(baseURL: "http://localhost:11434/v1")` and `isLocal(baseURL: "https://api.openai.com/v1")` (lines 53-55, delegating to `LocalModelServer.isLoopback`). | First returns `true` (host `localhost` is in the loopback set); second returns `false` (host `api.openai.com` is not). |
| local-provider-model-store-002 | page-stats-shape | Round-trip `LocalModelPageStats(downloads: "117.4M", updated: nil)` and `LocalModelPageStats(downloads: nil, updated: "1 year ago")` through `JSONEncoder`/`JSONDecoder` (lines 19-26). | Both decode back to equal values; each field is independently `nil`/non-`nil`, and the two instances are not `Equatable`-equal to each other. |
| local-provider-model-store-003 | per-baseurl-cache-scope, cached-accessors-are-pure-reads | `cachedModels(baseURL: "http://a/v1")` and `cachedModels(baseURL: "http://b/v1")` when only `"http://a/v1"` has ever been fetched successfully (lines 58-60). | The first call returns the cached ids for `a`; the second returns `[]` for `b` — neither call makes a network request. |
| local-provider-model-store-004 | global-cache-scope | Call `fetchModelInfo(model: "llama3", viaOllamaPage: true)` once, then read `cachedDescriptions()["llama3"]` and `cachedPageStats()["llama3"]` with no `baseURL` argument (lines 44-50, 75-82). | Both accessors return the values resolved for `"llama3"` regardless of which server's chooser triggered the fetch — there is no per-server variant of either cache. |
| local-provider-model-store-005 | models-endpoint, models-fetch-success | `fetchModels(baseURL: "http://localhost:11434/v1/")` against a stub that returns `200` with body `{"data":[{"id":"llama3"},{"id":"mistral"}]}` (lines 144-159). | The request targets `GET http://localhost:11434/v1/models` (one trailing slash stripped, then `/models` appended); `fetchModels` returns `["llama3","mistral"]`, and a subsequent `cachedModels(baseURL: "http://localhost:11434/v1/")` returns the same array. |
| local-provider-model-store-006 | models-fetch-failure | `fetchModels(baseURL:)` against a stub returning `500`, and separately against one returning `200` with body `{"data":[]}` (lines 151-155). | Both calls return `nil`; `cachedModels(baseURL:)` afterward is unchanged from whatever it held before each call. |
| local-provider-model-store-007 | sizes-endpoint, sizes-parse-tolerance, sizes-fetch-success | `fetchSizes(baseURL: "http://localhost:11434/v1")` against a stub at the derived `GET http://localhost:11434/api/tags` returning `200` with body `{"models":[{"name":"a","size":123},{"name":"b"}]}` (`b` carries no `size`) (lines 168-180). | The request targets the `/v1`-stripped native tags URL; `fetchSizes` returns `["a": 123]` — the malformed `b` entry is skipped rather than failing the whole parse. |
| local-provider-model-store-008 | sizes-fetch-failure | `fetchSizes(baseURL: "")`, for which `LocalModelServer.nativeTagsURL(baseURL:)` returns `nil` (line 169). | `fetchSizes` returns `nil` immediately; no request is attempted and the sizes cache is untouched. |
| local-provider-model-store-009 | metadata-endpoint, metadata-merge-on-success | The metadata cache already holds `["http://x/v1": ["modelA": metaA]]`; `fetchMetadata(baseURL: "http://x/v1", model: "modelB")` succeeds via a stub returning `metaB` (lines 128-138). | `cachedMetadata(baseURL: "http://x/v1")` afterward returns `["modelA": metaA, "modelB": metaB]` — `modelA`'s entry survives the merge. |
| local-provider-model-store-010 | metadata-endpoint | `fetchMetadata(baseURL:model:)` where the stubbed `LocalModelMetadataStore.fetch` returns `nil` (line 129). | `fetchMetadata` returns `nil`; `cachedMetadata(baseURL:)` is unchanged from before the call. |
| local-provider-model-store-011 | model-info-sequential-order | Instrument `ModelCatalogStore.description`, `ArtificialAnalysisStore.rank`, and `OllamaModelPageStore.fetchInfo` to record call timestamps; call `fetchModelInfo(model:, viaOllamaPage: true)` (lines 100-102). | The three calls are observed strictly in order — the catalog call completes before the rank call begins, and the rank call completes before the page call begins — never overlapping. |
| local-provider-model-store-012 | model-info-page-skipped | `fetchModelInfo(model: "gpt-4o", viaOllamaPage: false)` (line 102). | `OllamaModelPageStore.fetchInfo` is never invoked; the returned `stats` is `nil`. |
| local-provider-model-store-013 | description-precedence | `viaOllamaPage: true`; page description `"A capable general-purpose chat model tuned for long-context reasoning tasks."` (≥40 characters, contains a space); catalog description `"Short."` (lines 104-107). | Returned `description` equals the page's description — the page wins because it is substantial. |
| local-provider-model-store-014 | description-non-substantial-fallback | `viaOllamaPage: true`; page description `"www.x.ai"` (8 characters, no space — not substantial); catalog description `"A widely used open model."` (lines 105-106). | Returned `description` equals the catalog description — the fallback applies because the page text fails `isSubstantial`. |
| local-provider-model-store-015 | description-non-substantial-fallback | Same as above, but the catalog produces `nil` (line 106's `if let catalogDescription` guard). | Returned `description` equals the original non-substantial page text `"www.x.ai"`, unchanged — used as-is rather than discarded, since there is nothing to fall back to. |
| local-provider-model-store-016 | description-cache-write | `fetchModelInfo` resolves description `"X"` for model `"m"` (lines 108-112). | `cachedDescriptions()["m"] == "X"` immediately after the call returns. |
| local-provider-model-store-017 | stats-cache-write | `viaOllamaPage: true`, page `downloads: "10K"`, `updated: nil` (at least one non-nil) (lines 114-120). | Returned `stats == LocalModelPageStats(downloads: "10K", updated: nil)`, and `cachedPageStats()["model"]` holds the same value. |
| local-provider-model-store-018 | stats-cache-write | `viaOllamaPage: true`, page `downloads: nil` and `updated: nil` (line 115's `page.downloads != nil \|\| page.updated != nil` is `false`). | Returned `stats` is `nil`; the page-stats cache entry for that model is left unchanged. |
| local-provider-model-store-019 | rank-independent-of-page | `fetchModelInfo(model:, viaOllamaPage: false)` with `ArtificialAnalysisStore.rank` stubbed to return a non-nil rank (line 101). | Returned `rank` is that non-nil value even though `viaOllamaPage` is `false` and no page fetch ever occurs. |
| local-provider-model-store-020 | per-field-independent-nil | `fetchModelInfo` where the catalog call returns `nil` and the page call fails, but the rank call succeeds. | `description` is `nil`, `stats` is `nil`, `rank` is the successful non-nil value — one field's failure does not null out the others. |
| local-provider-model-store-021 | no-request-coalescing, concurrent-fetch-deduplication (the open question) | Two concurrent tasks both call `fetchModels(baseURL: "http://x/v1")` against a call-counting stub, for a `baseURL` with no prior cache entry (lines 144-163). | The stub's handler is invoked twice (no coalescing, per `no-request-coalescing`); the final cached entry for `"http://x/v1"` is whichever call's write executes last — not necessarily the call issued last, since neither call's completion order is guaranteed (the open question). |
| local-provider-model-store-022 | mainactor-atomic-cache-update | Two concurrent tasks call `fetchModels` for two *different* base URLs (`"http://a/v1"`, `"http://b/v1"`) whose stubbed responses resolve in overlapping windows (lines 156-158). | Both entries end up correctly present afterward — `cachedModels` for `a` and for `b` each return their own fetched ids; neither call's write is lost, because each call's own read-modify-write of `cache.value` runs with no intervening `await`. |
| local-provider-model-store-023 | cancellation-as-ordinary-failure | A task calling `fetchModels(baseURL:)` is cancelled while suspended on `URLSession.shared.data(for:)` (lines 149-162). | `fetchModels` returns `nil` (the thrown `CancellationError` is caught by the generic `catch`), and the cache entry for that `baseURL` is left exactly as it was before the call. |
| local-provider-model-store-024 | cache-persistence, cache-non-secure-storage | Call `fetchModels` successfully against `UserSettings.shared` backed by a real `UserDefaultsSettingsStorageProvider` suite; tear down and reconstruct `UserSettings.shared` against the same suite; then call `cachedModels(baseURL:)` (lines 29-30). | The previously fetched ids are still returned after reconstruction (persisted, not memory-only); a spy `SecureSettingsStorageProvider` substituted for `UserSettings.shared`'s secure provider records zero calls across the whole scenario, since none of the five caches is `isSecure`. |
| local-provider-model-store-025 | fetch-error-is-fully-swallowed (the open question) | `fetchModels`, `fetchSizes`, and `fetchMetadata` each invoked against a stub that throws a distinguishable error (e.g. `URLError(.cannotConnectToHost)` vs. `URLError(.timedOut)`) (lines 160-162, 181-183). | All three return `nil` with no observable difference between the two distinct causes — no log line, thrown error, or return value lets a caller or maintainer tell them apart (the open question). |

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
  stripped correctly by `fetchModels` (`hasSuffix("/")` check, line 145); a
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
  see `concurrent-fetch-deduplication`, the open question).
- **Error states**: Every network failure — a bad URL, a thrown transport
  error, a non-`200` status, an undecodable body, or (for `fetchSizes`) a
  parse that yields no entries — is treated identically: the affected
  function returns `nil` and its cache entry is left exactly as it was
  (MUST, see `models-fetch-failure`, `sizes-fetch-failure`,
  `metadata-endpoint`). None of these paths logs, throws to the caller, or
  otherwise signals which specific failure occurred (see
  `fetch-error-is-fully-swallowed`, the open question).
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseURL` (parameter to `isLocal`, `fetchModels`, `fetchSizes`, `fetchMetadata`, and the `cached*` reads) | `String` | none — required per call | The OpenAI-compatible base URL identifying the target server; used verbatim as the per-`baseURL` cache key and, after per-function trimming, as the network request target. |
| `model` (parameter to `fetchModelInfo`, `fetchMetadata`) | `String` | none — required per call | The model id to enrich or fetch metadata for; used verbatim as the global cache key for description/page-stats, and forwarded to each collaborator. |
| `viaOllamaPage` (parameter to `fetchModelInfo`) | `Bool` | none — required per call | Gates whether `OllamaModelPageStore.fetchInfo` (and therefore the returned/cached `stats`) is attempted at all. |
| `aiplugin.localModelCache` | settings key, `[String: [String]]` | `[:]` | Per-`baseURL` cache of the last successfully fetched model ids. |
| `aiplugin.localModelSizeCache` | settings key, `[String: [String: Int]]` | `[:]` | Per-`baseURL`, per-model cache of sizes in bytes from `/api/tags`. |
| `aiplugin.localModelMetadataCache` | settings key, `[String: [String: OllamaModelMetadata]]` | `[:]` | Per-`baseURL`, per-model cache of `/api/show` metadata. |
| `aiplugin.ollamaModelDescriptionCache` | settings key, `[String: String]` | `[:]` | Global (model-id-only) cache of the last resolved description. |
| `aiplugin.ollamaModelPageStatsCache` | settings key, `[String: LocalModelPageStats]` | `[:]` | Global (model-id-only) cache of the last resolved ollama.com page stats. |
| Request timeout (`fetchModels`, `fetchSizes`) | `TimeInterval` constant | `5` seconds | Hardcoded at each call site (lines 147, 170); not a parameter and not overridable from this file. |
| Loopback host set (`LocalModelServer`) | `Set<String>` constant | `{localhost, 127.0.0.1, 0.0.0.0, ::1, [::1]}` | Fixed in the collaborator type; not configurable from `LocalProviderModelStore`. |

## Deep Linking

Not applicable: `LocalProviderModelStore.swift` defines no URL scheme,
route, or navigation destination of any kind — every URL it constructs is a
network fetch target, never a deep link.

## Localization

Not applicable: `LocalProviderModelStore.swift` contains no user-facing
string literal of its own. The `downloads`/`updated` text it caches
(`LocalModelPageStats`) is scraped verbatim from ollama.com's page markup by
its collaborator `OllamaModelPageStore`, in whatever language that page
renders (effectively English); this file neither composes, formats, nor
localizes that text.

## Accessibility Options

Not applicable: `LocalProviderModelStore.swift` renders nothing and reads no
Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `LocalProviderModelStore.swift` contains no feature-flag or
remote-config check; every code path is reached purely through its
parameters and cached state.

## Analytics

Not applicable: `LocalProviderModelStore.swift` emits no analytics or
event-tracking call of any kind.

## Privacy

- **Data collected**: No personal or account data. The store transmits a
  model id string to ollama.com's public model page (`fetchModelInfo` when
  `viaOllamaPage` is `true`, via `OllamaModelPageStore`) and to the
  caller-supplied `baseURL` (a user-configured local/loopback server) for
  the `/models`, `/api/tags`, and `/api/show` lookups. `fetchModelInfo` also
  triggers its collaborators `ModelCatalogStore` (openrouter.ai, models.dev,
  and the adh catalog endpoint) and `ArtificialAnalysisStore`
  (artificialanalysis.ai, which attaches any user-stored API key as an
  `x-api-key` header) — those requests originate inside those collaborator
  types, not this file, but are triggered by this file's call.
- **Storage**: Cached values (model ids, byte sizes, `OllamaModelMetadata`,
  free-text descriptions, page stats) persist on-device through the five
  `UserSetting`-backed keys listed under Configuration, via the default
  (non-secure) settings provider; none is marked `isSecure`.
- **Transmission**: Plain HTTP(S) `GET` requests to `{baseURL}/models`, the
  derived `.../api/tags`, and ollama.com's model page; one HTTP(S) `POST` to
  the derived `.../api/show` with a small JSON body (`{"model": <model>}`).
  No request in this file carries a credential or token.
- **Retention**: Cached values are retained indefinitely — this file
  provides no explicit clear, remove, or expiry operation for any of its
  five caches. A value is only ever replaced by a later successful fetch for
  the same key, or removed if the underlying settings store is cleared
  externally.

## Logging

Not applicable: `LocalProviderModelStore.swift` contains no `Logger`/
`os_log`/`print` call. Every fetch or parse failure is discarded silently —
see `fetch-error-is-fully-swallowed` in Behavioral Requirements.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift`,
  which `import AgenticToolkitCore`s its collaborators
  `LocalModelServer.swift` (same target) and, from Core,
  `ModelCatalogStore.swift`, `ArtificialAnalysisStore.swift`,
  `OllamaModelPageStore.swift`, `OllamaModelMetadata.swift` (which also
  defines `LocalModelMetadataStore`), and the `UserSetting`/`UserSettings`/
  `StorableSetting`/`SettingsStore` settings-storage stack. It has no
  SwiftUI dependency at all — its current consumers,
  `ModelChooserViewController.swift`/`ModelChooserContent.swift`, are
  AppKit, not SwiftUI. Concurrency comes from `@MainActor`, persistence from
  `UserSetting` (UserDefaults-backed by default), networking from
  `URLSession.shared`, and parsing from `JSONDecoder`.
- **Compose**: A Kotlin port has no direct `@MainActor` equivalent; use a
  plain singleton `object` whose mutating functions are confined to
  `Dispatchers.Main.immediate` (or guarded by a `Mutex`) to reproduce the
  same non-interleaved read-modify-write guarantee. Replace the five
  `UserSetting`s with `DataStore<Preferences>` (or a small Room table) keyed
  by the same string names, `kotlinx.serialization.json` in place of
  `JSONDecoder`/`JSONSerialization`, and `OkHttp`/Ktor `HttpClient` with a
  5-second timeout for the two direct GET/POST calls this file makes.
- **React/Web**: A module of plain async functions plus a module-level
  cache object (or `localStorage`/`IndexedDB` for persistence across
  reloads), each cache entry `JSON.stringify`d the way `Codable` serializes
  here. Use `fetch` with `AbortSignal.timeout(5000)` for the two 5-second
  bounds, and preserve `fetchModelInfo`'s ordering with `await catalog();
  await rank(); await (viaOllamaPage ? page() : null);` rather than
  `Promise.all`, since the source deliberately awaits sequentially, not
  concurrently.
- **AppKit / UIKit**: Identical to the SwiftUI note — this type is
  UI-framework-agnostic, and is in fact consumed today from AppKit
  (`ModelChooserViewController`), not SwiftUI. Nothing in the contract
  changes under UIKit.
- **WinUI 3**: Model `LocalProviderModelStore` as a plain static class (or a
  singleton service registered in DI) mirroring the enum-of-statics shape.
  Replace each `UserSetting<T>` with a JSON-serialized string stored in
  `Windows.Storage.ApplicationData.Current.LocalSettings` (its
  `ApplicationDataCompositeValue` does not natively hold nested
  dictionaries, so serialize each cache's value with `System.Text.Json`
  before storing, matching `Codable`'s round-trip here) — never the secure/
  credential-locker equivalent, matching `cache-non-secure-storage`. Use
  `HttpClient` with `Timeout = TimeSpan.FromSeconds(5)` for the `/models`
  and `/api/tags` `GET`s and a `POST` with `JsonContent.Create` for
  `/api/show`. Represent `LocalModelPageStats` as a
  `record struct LocalModelPageStats(string? Downloads, string? Updated)`.
  Reproduce `mainactor-atomic-cache-update` by performing each cache's
  read-modify-write inside a `SemaphoreSlim(1, 1)` (or by marshaling onto a
  single `DispatcherQueue`), and reproduce `model-info-sequential-order` with
  `await catalogTask; await rankTask; await pageTask;` — never
  `Task.WhenAll` — so the port preserves the source's deliberate ordering
  rather than parallelizing it.

## Design Decisions

**Decision**: `fetchModels` strips at most one trailing `/` from `baseURL`
before appending `/models`, while `LocalModelServer.nativeTagsURL(baseURL:)`
(used by `fetchSizes`) strips every trailing slash and a trailing `/v1` in a
loop.
**Rationale**: Not stated in a source comment; this is a design fact rather
than a documented rationale. The practical effect is that a `baseURL` with
more than one trailing slash produces a well-formed native tags URL via
`fetchSizes` but a request with an embedded double slash via `fetchModels`,
which typically 404s and folds into the ordinary failure path rather than
crashing.
**Approved**: pending

**Decision**: `fetchModelInfo` awaits the catalog description, the rank, and
(conditionally) the ollama.com page strictly in sequence, never concurrently.
**Rationale**: Per the doc comment, "The catalog and rank awaits come FIRST
so a chooser's N per-model tasks all join the same live round of each before
fanning out to N page fetches" — the sequencing exists to line up with
`ModelCatalogStore.catalog()`'s and `ArtificialAnalysisStore`'s own
in-flight-task coalescing (see their respective sources), not to slow this
call down; the page fetch runs last because it has no such coalescing and is
the one call unique to each model.
**Approved**: pending

**Decision**: The description and page-stats caches are keyed by model id
alone (global), while the models, sizes, and metadata caches are keyed by
`baseURL` (or `baseURL` plus model id).
**Rationale**: Per the doc comment on `descriptionCache`, "Remote models
only ever get catalog text... Keyed by model name alone, not by server" — a
model's prose description and community popularity are properties of the
model itself, not of which server happens to be hosting it, so two servers
exposing the same model id intentionally share one cached description and
one cached stats entry.
**Approved**: pending

**Decision**: `fetchModels`/`fetchSizes`/`fetchMetadata` provide no locality
guard of their own — nothing stops a caller from invoking them with a
non-loopback `baseURL`.
**Rationale**: `isLocal(baseURL:)` exists specifically as the caller-facing
decision point (as `ModelChooserViewController` uses it before choosing
between this store and the remote descriptor catalog); `fetchModels` in
particular is a generic OpenAI-compatible `/models` listing with no
inherent local-only assumption, so baking a loopback check into it would
narrow a function that is otherwise reusable.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | failed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |

Notes: graceful-degradation passes because every failure path resolves to
`nil` (or, for `fetchModelInfo`, a `nil` field) rather than a thrown error or
a crash, and callers are documented to keep showing cached data.
fault-tolerance fails because, unlike the sibling `LocalModelCatalog`'s
TTL-based backoff, this file applies no cadence at all — per its own doc
comment, "every rebuild re-fetches," so a persistently down or slow server
is hit on every single caller-triggered call with no throttling; this is a
deliberate freshness-over-load-shedding tradeoff, not an oversight, but it
does not meet the reliability bar as written. idempotent-operations is
partial for the same reason as `LocalModelCatalog`: repeated successful
calls converge on the same result, but concurrent calls for the same key are
not deduplicated (`no-request-coalescing`, `concurrent-fetch-deduplication`,
the open question). explicit-error-handling fails because every fetch,
HTTP-status, and parse failure is discarded with zero diagnostic signal
(`fetch-error-is-fully-swallowed`, the open question).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
