---
id: 8bdba644-d7ad-45e4-a2f5-0156bfd40e15
title: Local Provider Model Store
domain: agentictoolkit://cookbook/ai/models/local/local-provider-model-store
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Live model discovery and caching for local (loopback) OpenAI-compatible
  providers such as Ollama, plus description, size, metadata, and rank enrichment.
platforms:
- swift
- macos
tags:
- local-model
- caching
- ollama
depends-on: []
related:
- agentictoolkit://cookbook/ai/models/local/local-model-catalog
- agentictoolkit://cookbook/ai/models/local/local-inference-guard
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

# Local Provider Model Store

## Overview

The local provider model store is a **logic** component — no visual
surface — that gives a model chooser live model discovery for **local**
(loopback) OpenAI-compatible providers such as Ollama. Per the component's
own stated purpose: a local server's installed models are known only to
that server, so a fixed remote descriptor catalog can neither know what the
user pulled nor stay correct as models are pulled or removed; the store
instead lists a local server's models by asking it directly, caches the
last successful fetch per base URL so the chooser paints instantly and keeps
working while the server is down, and re-fetches on every rebuild to catch
changes. A second, independent responsibility — fetching per-model info —
batches per-model enrichment (a prose description, Ollama.com popularity
stats, and an Artificial Analysis leaderboard rank) from several live
sources into one call. Remote (non-loopback) providers are explicitly out
of scope for this component: per its own stated purpose, they "keep their
descriptor catalog," which this component does not touch.

## Behavioral Requirements

- **loopback-detection**: The locality check MUST return the result of the
  model server helper's loopback detection unchanged — true only when the
  base URL's host, lowercased, is exactly one of `localhost`, `127.0.0.1`,
  `0.0.0.0`, `::1`, or `[::1]`, and false for any other host or for a base
  URL from which no host can be parsed.
- **page-stats-shape**: The page-stats structure MUST support being
  encoded, decoded, and compared for equality, and MUST hold a `downloads`
  field and an `updated` field, each independently optional — one MAY be
  present without the other.
- **per-baseurl-cache-scope**: The models cache (`aiplugin.localModelCache`,
  a map of base URL to an array of model ids) and the sizes cache
  (`aiplugin.localModelSizeCache`, a map of base URL to a map of model id to
  size in bytes) MUST be keyed by the exact base URL string passed to their
  respective fetch/cached operations, with no normalization of that key;
  the metadata cache (`aiplugin.localModelMetadataCache`, a map of base URL
  to a map of model id to metadata) MUST additionally nest by model id
  under each base URL.
- **global-cache-scope**: The description cache
  (`aiplugin.ollamaModelDescriptionCache`, a map of model id to description)
  and the page-stats cache (`aiplugin.ollamaModelPageStatsCache`, a map of
  model id to page stats) MUST be keyed by model id alone, shared globally
  across every base URL — two different servers that each expose a model of
  the same id share one cached description and one cached page-stats entry.
- **cached-accessors-are-pure-reads**: The cached-value accessors for
  models, sizes, metadata, descriptions, and page stats MUST read their
  respective cache synchronously, without making a network request, and
  MUST return an empty collection rather than nothing when no entry exists
  for the requested key.
- **models-endpoint**: The models fetch MUST strip at most one trailing
  slash from the base URL, MUST build the request URL by appending the
  literal path `/models` to the result, and MUST issue a `GET` request with
  a 5 second timeout.
- **models-fetch-success**: The models fetch MUST treat a response as
  successful only when the HTTP status is `200` and the body decodes as
  `{"data":[{"id": string}, ...]}` into a non-empty array of ids; on success
  it MUST replace the cached entry for the base URL with that id array and
  MUST return the same array.
- **models-fetch-failure**: The models fetch MUST return nothing, and MUST
  leave the cached entry for the base URL unchanged, for every other
  outcome: an unbuildable request URL, a failed request, a non-`200`
  status, an undecodable body, or a decoded-but-empty id array.
- **sizes-endpoint**: The sizes fetch MUST derive its request URL via the
  model server helper's native tags URL derivation (which strips all
  trailing slashes and one trailing `/v1` before appending `/api/tags`) and
  MUST issue a `GET` request with a 5 second timeout.
- **sizes-parse-tolerance**: The sizes fetch MUST parse a `200` response
  body with the model server helper's response parser, which decodes each
  `models[]` entry independently and skips one that fails to decode rather
  than discarding the whole response.
- **sizes-fetch-success**: When native tags URL derivation succeeds, the
  response is `200`, and the parsed sizes map is non-empty, the sizes fetch
  MUST replace the cached entry for the base URL with that map and MUST
  return it.
- **sizes-fetch-failure**: The sizes fetch MUST return nothing, and MUST
  leave the cached entry for the base URL unchanged, when native tags URL
  derivation returns nothing, the request fails, the status is not `200`,
  or the parsed sizes map is empty.
- **metadata-endpoint**: The metadata fetch MUST obtain metadata by calling
  a local model metadata store's fetch operation and MUST return nothing
  immediately, without modifying the metadata cache, when that call returns
  nothing.
- **metadata-merge-on-success**: On a successful result, the metadata fetch
  MUST merge the new model/metadata pair into the existing per-base-URL map
  (creating one if none exists) rather than replacing the whole
  per-base-URL map, so previously cached models under the same base URL
  MUST remain present.
- **model-info-sequential-order**: Fetching per-model info MUST wait for
  its three sources strictly in sequence — first the catalog description,
  then the leaderboard rank, then, only when the Ollama-page flag is true,
  the Ollama page fetch — never concurrently.
- **model-info-page-skipped**: When the Ollama-page flag is false, fetching
  per-model info MUST NOT call the Ollama page fetch, and the returned
  stats MUST be nothing.
- **description-precedence**: The description that fetching per-model info
  returns MUST be the page's description when the Ollama-page flag is
  true, the page fetch succeeded, the page description is present, AND it
  is judged substantial (at least 40 characters and containing a space);
  otherwise it MUST fall back to the catalog description whenever that is
  present.
- **description-non-substantial-fallback**: When the page description is
  present but not substantial and the catalog produced no description,
  fetching per-model info MUST return that non-substantial page description
  unchanged rather than discarding it.
- **description-cache-write**: Whenever fetching per-model info resolves a
  non-empty description, it MUST write it into the description cache under
  the model id, overwriting any previous entry for that model regardless of
  which base URL the call concerned.
- **stats-cache-write**: Fetching per-model info MUST write stats into the
  page-stats cache under the model id, and MUST return non-empty stats,
  only when the Ollama-page flag is true, the page fetch succeeded, and at
  least one of the page's downloads/updated fields is present; in every
  other case it MUST leave the page-stats cache for that model id unchanged
  and MUST return nothing for stats.
- **rank-independent-of-page**: Fetching per-model info MUST obtain and
  return the leaderboard rank regardless of the Ollama-page flag's value.
- **per-field-independent-nil**: Fetching per-model info's three returned
  fields (description, stats, rank) MUST each independently be empty when
  their own respective source failed or was skipped, without one field's
  failure affecting another's value.
- **no-request-coalescing**: The models fetch, sizes fetch, and metadata
  fetch MUST NOT deduplicate or join concurrent calls for the same key —
  unlike the catalog store's and the leaderboard store's in-flight-task
  coalescing pattern, each concurrent call to one of these three operations
  MUST perform its own network request.
- **serialized-atomic-cache-update**: The store MUST serialize its
  operations so that every read-modify-write of a cache map (read the
  current value, mutate the local copy, write it back) executes with no
  intervening suspension, so that two calls writing to *different* keys
  cannot interleave mid-update and lose one another's write.
- **cancellation-as-ordinary-failure**: The models fetch and sizes fetch
  MUST treat a cancellation signal from their wait exactly like any other
  failure — caught the same way, returning nothing and leaving the cache
  unmodified — with no distinct cancellation handling.
- **cache-persistence**: All five caches MUST persist through whichever
  settings store the shared settings instance routes to (a local key-value
  store by default) and MUST survive process restart for as long as that
  store retains the key.
- **cache-non-secure-storage**: None of the five cache declarations MUST
  mark itself secure; all five default to non-secure and are therefore held
  by the non-secure settings provider, never a credential-secured one.

One concern the component's own purpose calls for is left undefined:

- **concurrent-fetch-deduplication**: NEEDS REVIEW: Not implemented. The
  models/sizes/metadata fetch operations each read the current cache, wait
  on a network call, and only afterward write a new value back; because
  that wait is reentrant, two concurrent calls for the same base URL (or
  base URL/model pair) can both observe the same pre-fetch cache state and
  both issue their own request, and the cached value that survives is
  whichever call's write statement runs last — determined by network
  completion order, not by which call was issued most recently. This cannot
  be resolved from the store's own behavior alone: it requires either an
  explicit statement that duplicate concurrent fetches for the same key are
  an accepted cost, or an in-flight-request cache keyed by base URL/model,
  mirroring the catalog store's own in-flight pattern used elsewhere in
  this family.

A related behavior is a fact, not a gap:

- **fetch-error-is-fully-swallowed**: Every failure path in the models
  fetch, sizes fetch, metadata fetch, and the sources fetching per-model
  info calls into discards its error with no diagnostic, and none of them
  logs. A maintainer investigating why a local server's models stopped
  refreshing has no signal in this component distinguishing "server
  refused the connection" from "timed out" from "returned an undecodable
  body."

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
| local-provider-model-store-001 | loopback-detection | Check locality for base URL `http://localhost:11434/v1` and for `https://api.openai.com/v1` (delegating to loopback detection). | First returns true (host `localhost` is in the loopback set); second returns false (host `api.openai.com` is not). |
| local-provider-model-store-002 | page-stats-shape | Round-trip page stats `{downloads: "117.4M", updated: none}` and `{downloads: none, updated: "1 year ago"}` through encode/decode. | Both decode back to equal values; each field is independently present/absent, and the two instances are not equal to each other. |
| local-provider-model-store-003 | per-baseurl-cache-scope, cached-accessors-are-pure-reads | Read cached models for base URL `http://a/v1` and for `http://b/v1` when only `http://a/v1` has ever been fetched successfully. | The first call returns the cached ids for `a`; the second returns an empty array for `b` — neither call makes a network request. |
| local-provider-model-store-004 | global-cache-scope | Fetch model info for model `llama3` with the Ollama-page flag on, once, then read cached descriptions and cached page stats with no base URL argument. | Both accessors return the values resolved for `llama3` regardless of which server's chooser triggered the fetch — there is no per-server variant of either cache. |
| local-provider-model-store-005 | models-endpoint, models-fetch-success | Fetch models for base URL `http://localhost:11434/v1/` against a stub that returns `200` with body `{"data":[{"id":"llama3"},{"id":"mistral"}]}`. | The request targets `GET http://localhost:11434/v1/models` (one trailing slash stripped, then `/models` appended); the fetch returns `["llama3","mistral"]`, and a subsequent read of cached models for the same base URL returns the same array. |
| local-provider-model-store-006 | models-fetch-failure | Fetch models against a stub returning `500`, and separately against one returning `200` with body `{"data":[]}`. | Both calls return nothing; the cached models afterward are unchanged from whatever they held before each call. |
| local-provider-model-store-007 | sizes-endpoint, sizes-parse-tolerance, sizes-fetch-success | Fetch sizes for base URL `http://localhost:11434/v1` against a stub at the derived `GET http://localhost:11434/api/tags` returning `200` with body `{"models":[{"name":"a","size":123},{"name":"b"}]}` (`b` carries no size). | The request targets the `/v1`-stripped native tags URL; the fetch returns `{"a": 123}` — the malformed `b` entry is skipped rather than failing the whole parse. |
| local-provider-model-store-008 | sizes-fetch-failure | Fetch sizes for an empty base URL, for which native tags URL derivation returns nothing. | The fetch returns nothing immediately; no request is attempted and the sizes cache is untouched. |
| local-provider-model-store-009 | metadata-endpoint, metadata-merge-on-success | The metadata cache already holds `{http://x/v1: {modelA: metaA}}`; fetch metadata for base URL `http://x/v1` and model `modelB`, which succeeds via a stub returning `metaB`. | Cached metadata for `http://x/v1` afterward returns `{modelA: metaA, modelB: metaB}` — `modelA`'s entry survives the merge. |
| local-provider-model-store-010 | metadata-endpoint | Fetch metadata where the stubbed metadata lookup returns nothing. | The fetch returns nothing; cached metadata for the base URL is unchanged from before the call. |
| local-provider-model-store-011 | model-info-sequential-order | Instrument the catalog description, leaderboard rank, and Ollama page lookups to record call timestamps; fetch model info with the Ollama-page flag on. | The three calls are observed strictly in order — the catalog call completes before the rank call begins, and the rank call completes before the page call begins — never overlapping. |
| local-provider-model-store-012 | model-info-page-skipped | Fetch model info for model `gpt-4o` with the Ollama-page flag off. | The Ollama page lookup is never invoked; the returned stats is empty. |
| local-provider-model-store-013 | description-precedence | Ollama-page flag on; page description `"A capable general-purpose chat model tuned for long-context reasoning tasks."` (≥40 characters, contains a space); catalog description `"Short."` | Returned description equals the page's description — the page wins because it is substantial. |
| local-provider-model-store-014 | description-non-substantial-fallback | Ollama-page flag on; page description `"www.x.ai"` (8 characters, no space — not substantial); catalog description `"A widely used open model."` | Returned description equals the catalog description — the fallback applies because the page text fails the substantiality check. |
| local-provider-model-store-015 | description-non-substantial-fallback | Same as above, but the catalog produces no description. | Returned description equals the original non-substantial page text `"www.x.ai"`, unchanged — used as-is rather than discarded, since there is nothing to fall back to. |
| local-provider-model-store-016 | description-cache-write | Fetching model info resolves description `"X"` for model `"m"`. | Cached descriptions for `m` equal `"X"` immediately after the call returns. |
| local-provider-model-store-017 | stats-cache-write | Ollama-page flag on, page `downloads: "10K"`, `updated: none` (at least one present). | Returned stats equal `{downloads: "10K", updated: none}`, and cached page stats for that model hold the same value. |
| local-provider-model-store-018 | stats-cache-write | Ollama-page flag on, page `downloads: none` and `updated: none` (neither present). | Returned stats is empty; the page-stats cache entry for that model is left unchanged. |
| local-provider-model-store-019 | rank-independent-of-page | Fetch model info with the Ollama-page flag off, with the leaderboard rank lookup stubbed to return a non-empty rank. | Returned rank is that non-empty value even though the Ollama-page flag is off and no page fetch ever occurs. |
| local-provider-model-store-020 | per-field-independent-nil | Fetch model info where the catalog call returns nothing and the page call fails, but the rank call succeeds. | Description is empty, stats is empty, rank is the successful non-empty value — one field's failure does not null out the others. |
| local-provider-model-store-021 | no-request-coalescing, concurrent-fetch-deduplication | Two concurrent operations both fetch models for base URL `http://x/v1` against a call-counting stub, for a base URL with no prior cache entry. | The stub's handler is invoked twice (no coalescing); the final cached entry for `http://x/v1` is whichever call's write executes last — not necessarily the call issued last, since neither call's completion order is guaranteed. |
| local-provider-model-store-022 | serialized-atomic-cache-update | Two concurrent operations fetch models for two *different* base URLs (`http://a/v1`, `http://b/v1`) whose stubbed responses resolve in overlapping windows. | Both entries end up correctly present afterward — cached models for `a` and for `b` each return their own fetched ids; neither call's write is lost, because each call's own read-modify-write of the cache runs with no intervening suspension. |
| local-provider-model-store-023 | cancellation-as-ordinary-failure | An operation fetching models is cancelled while waiting on the network request. | The fetch returns nothing (the cancellation is caught by the generic failure handling), and the cache entry for that base URL is left exactly as it was before the call. |
| local-provider-model-store-024 | cache-persistence, cache-non-secure-storage | Fetch models successfully against a real persisted settings store; tear down and reconstruct the settings store against the same underlying storage; then read cached models. | The previously fetched ids are still returned after reconstruction (persisted, not memory-only); a spy secure-storage provider substituted for the settings store's secure provider records zero calls across the whole scenario, since none of the five caches is marked secure. |
| local-provider-model-store-025 | fetch-error-is-fully-swallowed | Fetch models, sizes, and metadata each invoked against a stub that fails with a distinguishable cause (e.g. a connection failure vs. a timeout). | All three return nothing with no observable difference between the two distinct causes — no log line, thrown error, or return value lets a caller or maintainer tell them apart. |

## Edge Cases

- **Null and empty input**: An empty base URL passed to the models fetch
  yields a trimmed empty string, and the relative path `/models` still
  parses successfully as a schemeless relative URL, so the request is
  attempted and fails at the transport layer (folds into
  models-fetch-failure), MUST. An empty base URL passed to the sizes fetch
  or metadata fetch (via native tags URL derivation / the metadata store's
  own base-URL derivation) trims to empty and yields no usable URL before
  any request is made, MUST. An empty model string is not special-cased
  anywhere in this component — it is forwarded verbatim to the metadata
  store's fetch, the Ollama page lookup (which returns nothing for an empty
  name), and the catalog description / leaderboard rank lookups (which
  fail their internal matching), so fetching model info for an empty model
  resolves every field to whatever its collaborator returns for an empty
  id — typically all empty — with no explicit empty-string guard.
- **Boundary values**: A base URL with exactly one trailing slash is
  stripped correctly by the models fetch; a base URL with two or more
  trailing slashes has only one removed, so the request URL ends up with an
  embedded double slash before `/models` — a direct, undocumented
  consequence of the single (not looping) strip, unlike native tags URL
  derivation's loop, which strips all of them. This recipe records that
  divergence rather than assuming both operations normalize identically
  (see Design Decisions).
- **Concurrent access**: The store serializes its operations, so calls
  interleave only at defined suspension points; a single call's own
  read-modify-write of a cache map is never split across a suspension
  point, so writes to *different* keys never corrupt or lose one another
  (MUST, see serialized-atomic-cache-update). Two *concurrent* calls for
  the *same* key are not deduplicated and race on which one's result is
  cached last (MUST NOT deduplicate, see no-request-coalescing; final value
  undefined, see the open question on concurrent-fetch-deduplication).
- **Error states**: Every network failure — a bad URL, a failed request, a
  non-`200` status, an undecodable body, or (for the sizes fetch) a parse
  that yields no entries — is treated identically: the affected operation
  returns nothing and its cache entry is left exactly as it was (MUST, see
  models-fetch-failure, sizes-fetch-failure, metadata-endpoint). None of
  these paths logs, raises to the caller, or otherwise signals which
  specific failure occurred — see fetch-error-is-fully-swallowed in
  Behavioral Requirements.
- **Offline or disconnected state**: When the target base URL server is
  unreachable (process not running, host down), every direct request in
  this component (`/models`, the derived `/api/tags`, and, via the metadata
  fetch, the derived `/api/show`) fails with a transport failure that is
  caught and folded into the ordinary failure path above; callers are
  expected to keep rendering cached models/sizes/metadata for that base
  URL in the meantime, per the component's own stated purpose ("keeps
  working when the server is down"), MUST.
- **Cancellation and timeouts**: The models fetch and sizes fetch bound
  their own request to a `5`-second timeout; a timeout is an ordinary
  failure caught the same way as any other transport failure (MUST, see
  cancellation-as-ordinary-failure). Cancellation during any of the waits
  inside fetching model info (the catalog, rank, or page call) is not
  special-cased in this component; whatever each collaborator returns for
  a cancelled call (typically empty, per each collaborator's own
  degrade-to-empty contract) flows through unchanged.
- **Missing file or unreachable server**: Not applicable as a distinct
  code path — a local server process that has quit, or one that is running
  but is not Ollama (so `/api/tags`/`/api/show` don't exist), is
  indistinguishable in this component from any other transport failure or
  non-`200`/undecodable response; see Error states above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseURL` (parameter to the locality check and the fetch/cached operations) | string | none — required per call | The OpenAI-compatible base URL identifying the target server; used verbatim as the per-base-URL cache key and, after per-operation trimming, as the network request target. |
| `model` (parameter to fetching model info and metadata) | string | none — required per call | The model id to enrich or fetch metadata for; used verbatim as the global cache key for description/page-stats, and forwarded to each collaborator. |
| `viaOllamaPage` (parameter to fetching model info) | boolean | none — required per call | Gates whether the Ollama page lookup (and therefore the returned/cached stats) is attempted at all. |
| `aiplugin.localModelCache` | persisted key, map of base URL to array of model ids | `{}` | Per-base-URL cache of the last successfully fetched model ids. |
| `aiplugin.localModelSizeCache` | persisted key, map of base URL to map of model id to size in bytes | `{}` | Per-base-URL, per-model cache of sizes in bytes from `/api/tags`. |
| `aiplugin.localModelMetadataCache` | persisted key, map of base URL to map of model id to metadata | `{}` | Per-base-URL, per-model cache of `/api/show` metadata. |
| `aiplugin.ollamaModelDescriptionCache` | persisted key, map of model id to description | `{}` | Global (model-id-only) cache of the last resolved description. |
| `aiplugin.ollamaModelPageStatsCache` | persisted key, map of model id to page stats | `{}` | Global (model-id-only) cache of the last resolved Ollama.com page stats. |
| Request timeout (models fetch, sizes fetch) | number (seconds), constant | `5` seconds | Fixed at each call site; not a parameter and not overridable from this component. |
| Loopback host set (model server helper) | set of strings, constant | `{localhost, 127.0.0.1, 0.0.0.0, ::1, [::1]}` | Fixed in the collaborator component; not configurable from this store. |

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination of any kind — every URL it constructs is a network fetch
target, never a deep link.

## Localization

Not applicable: this component contains no user-facing string literal of
its own. The `downloads`/`updated` text it caches (page stats) is scraped
verbatim from Ollama.com's page markup by its collaborator (the Ollama page
lookup), in whatever language that page renders (effectively English); this
component neither composes, formats, nor localizes that text.

## Accessibility Options

Not applicable: this component renders nothing and reads no Reduce Motion,
Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check; every code path is reached purely through its parameters and cached
state.

## Analytics

Not applicable: this component emits no analytics or event-tracking call of
any kind.

## Privacy

- **Data collected**: No personal or account data. The store transmits a
  model id string to Ollama.com's public model page (fetching model info
  when the Ollama-page flag is true, via the Ollama page lookup) and to the
  caller-supplied base URL (a user-configured local/loopback server) for
  the `/models`, `/api/tags`, and `/api/show` lookups. Fetching model info
  also triggers its collaborators the catalog store (openrouter.ai,
  models.dev, and the ADH catalog endpoint) and the leaderboard store
  (artificialanalysis.ai, which attaches any user-stored API key as an
  `x-api-key` header) — those requests originate inside those collaborator
  components, not this one, but are triggered by this component's call.
- **Storage**: Cached values (model ids, byte sizes, metadata, free-text
  descriptions, page stats) persist on-device through the five persisted
  keys listed under Configuration, via the default (non-secure) settings
  provider; none is marked secure.
- **Transmission**: Plain HTTP(S) `GET` requests to `{baseURL}/models`, the
  derived `.../api/tags`, and Ollama.com's model page; one HTTP(S) `POST` to
  the derived `.../api/show` with a small JSON body (`{"model": <model>}`).
  No request in this component carries a credential or token.
- **Retention**: Cached values are retained indefinitely — this component
  provides no explicit clear, remove, or expiry operation for any of its
  five caches. A value is only ever replaced by a later successful fetch
  for the same key, or removed if the underlying settings store is cleared
  externally.

## Logging

Not applicable: this component performs no logging. Every fetch or parse
failure is discarded silently — see fetch-error-is-fully-swallowed in
Behavioral Requirements.

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
  Reproduce `serialized-atomic-cache-update` by performing each cache's
  read-modify-write inside a `SemaphoreSlim(1, 1)` (or by marshaling onto a
  single `DispatcherQueue`), and reproduce `model-info-sequential-order` with
  `await catalogTask; await rankTask; await pageTask;` — never
  `Task.WhenAll` — so the port preserves the source's deliberate ordering
  rather than parallelizing it.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift` |

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
not deduplicated (`no-request-coalescing`; see the open question on
concurrent-fetch-deduplication). explicit-error-handling fails because every fetch,
HTTP-status, and parse failure is discarded with zero diagnostic signal
(`fetch-error-is-fully-swallowed`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
