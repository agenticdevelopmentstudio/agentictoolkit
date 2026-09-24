---
id: 3b310d80-e18d-4f45-9041-10a278f775c1
domain: agentictoolkit://recipes/ai-plugin-runtime-core-ai
type: ingredient
title: Core AI Runtime
version: 1.0.1
status: review
language: en
summary: Provider metadata, HTTP request building, and network-backed catalog stores
  for AI chat dispatch and model discovery
platforms:
- swift
- macos
tags:
- ai
- provider
- networking
- model-catalog
- caching
- concurrency
- subprocess
- cli
- security
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
approved-by: null
approved-date: null
copyright: 2026 Mike Fullerton
license: MIT
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/AI/AIProvider.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/AIRequestBuilder.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/ArtificialAnalysisStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/ClaudeCLI.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/ModelCatalogStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/OllamaModelMetadata.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/OllamaModelPageStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/AI/OpenAIModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/ModelCatalogStoreTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/ArtificialAnalysisStoreTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/OllamaModelPageStoreTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/OllamaModelMetadataTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/OpenAIModelCatalogTests.swift
  (agentictoolkit)
---

# Core AI Runtime

## Overview

The Core AI Runtime is the non-UI logic root for talking to AI chat backends and
discovering what models they offer. It has eight parts:

- `AIProvider` — the `Sendable` enum identifying the five supported backends
  (`claudeCLI`, `anthropic`, `openai`, `google`, `custom`) and their display
  metadata (name, default models, recommended model, API-key placeholder,
  default base URL).
- `AIRequestConfig` / `AIRequestBuilder` — turns a provider selection and a
  message list into a provider-shaped `URLRequest`, and parses a provider's
  JSON reply or error body back into plain text.
- `ArtificialAnalysisStore` — fetches and caches per-model intelligence/coding
  index rankings from the Artificial Analysis leaderboard API, and holds the
  API key that gates it.
- `ClaudeCLI` — runs the local `claude -p` binary as a subprocess so a caller
  can get a model reply without an API key, reusing the user's existing
  Claude Code login.
- `ModelCatalogStore` — fetches and merges prose model descriptions from
  OpenRouter, models.dev, and the adh provider-template catalog, then matches
  a bare or namespaced model id against them.
- `OllamaModelMetadata` (`LocalModelMetadataStore`) — asks a local Ollama
  server's native `/api/show` route what a pulled model can do and how big it
  is.
- `OllamaModelPageStore` — scrapes a model's `ollama.com` page for its author
  blurb and live popularity stats, the only place that prose exists for
  community fine-tunes.
- `OpenAIModelCatalog` — lists the models an OpenAI-compatible `/models`
  endpoint actually serves.

All eight types are Foundation-only: no SwiftUI, AppKit, or UIKit import
appears anywhere in this component, and none of them render anything.

## Behavioral Requirements

### AIProvider

- **provider-identity**: `AIProvider` MUST be a `String`-backed, `CaseIterable & Identifiable & Sendable` enum with exactly five cases: `claudeCLI` (raw value `"claude_cli"`), `anthropic`, `openai`, `google`, `custom`.
- **provider-display-metadata**: Each case MUST expose `displayName`, `defaultModels`, `recommendedModel`, `recommendedNote`, `apiKeyPlaceholder`, and `defaultBaseURL` as pure, non-throwing computed properties with a value for every case (`custom` and `claudeCLI` return empty strings/arrays where a fixed default has no meaning).
- **provider-cli-flag**: `usesCLI` MUST be `true` only for `.claudeCLI`, and `requiresAPIKey` MUST be the logical negation of `usesCLI` (`!usesCLI`) — every non-CLI provider requires an API key, the CLI provider never does.
- **provider-sendable**: Because `AIProvider` is `Sendable` and holds no reference state, it MAY cross isolation domains freely; callers MUST NOT need to hop actors just to read provider metadata.

### AIRequestConfig / AIRequestBuilder

- **request-config-shape**: `AIRequestConfig` MUST carry exactly `provider`, `model`, `apiKey`, `customBaseURL`, `maxTokens`, and `timeoutInterval`, all supplied through its memberwise-style public initializer.
- **request-config-isolation**: `AIRequestConfig` is a plain `public struct` with no `Sendable` conformance declared. It MUST be treated as non-Sendable and MUST stay confined to the isolation domain of the caller that constructs it (its doc comment names `MiniChatViewModel`, `TerminalSessionSummarizer`, and `WhippetSettingsViewModel` as the current callers).
- **request-dispatch-by-provider**: `AIRequestBuilder.buildRequest` MUST dispatch on `config.provider` and build an Anthropic Messages request for `.anthropic`, an OpenAI-compatible chat-completions request against the fixed `https://api.openai.com` base for `.openai`, a Gemini `generateContent` request for `.google`, and an OpenAI-compatible request against `config.customBaseURL` for `.custom`.
- **request-custom-requires-base-url**: `buildRequest` MUST throw `AIRequestError.missingBaseURL` when `config.provider == .custom` and `config.customBaseURL.isEmpty`, before attempting to build anything.
- **request-cli-provider-throws**: `buildRequest` MUST throw `AIRequestError.unsupportedProvider` for `.claudeCLI` rather than building an HTTP request — the CLI provider issues no network call from this layer, and callers MUST branch on `provider.usesCLI` before ever reaching `buildRequest`.
- **anthropic-request-shape**: The Anthropic builder MUST POST to `https://api.anthropic.com/v1/messages`, set `x-api-key` to `config.apiKey` and `anthropic-version` to `"2023-06-01"`, default an empty `config.model` to `"claude-haiku-4-5-20251001"`, and include `system` in the body only when `systemPrompt` is non-empty.
- **openai-compatible-request-shape**: The OpenAI-compatible builder (used for both `.openai` and `.custom`) MUST append `v1/chat/completions` to its base URL, set `Authorization: Bearer <apiKey>`, prepend a `system` message when `systemPrompt` is non-empty, and default an empty `config.model` to `"gpt-4.1-nano"` for `.openai` or to `config.model` itself for `.custom`.
- **openai-compatible-missing-url-throws**: The OpenAI-compatible builder MUST throw `AIRequestError.missingBaseURL` when `URL(string: baseURL)?.appendingPathComponent("v1/chat/completions")` fails to construct a URL.
- **google-request-shape**: The Google builder MUST target `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent?key=<apiKey>`, default an empty `config.model` to `"gemini-2.0-flash"`, remap any message whose `role == "assistant"` to Gemini's `"model"` role, and include `systemInstruction` in the body only when `systemPrompt` is non-empty.
- **reply-parsing-by-provider**: `parseAssistantReply` MUST return `"(Unable to parse response)"` when `data` is not a JSON object, and otherwise MUST extract `content[0].text` for `.anthropic`, `choices[0].message.content` for `.openai` and `.custom`, and `candidates[0].content.parts[0].text` for `.google`.
- **reply-parsing-empty-fallback**: `parseAssistantReply` MUST return `"(Empty response)"` whenever the provider-specific shape is not found in an otherwise-parseable JSON object.
- **claude-cli-reply-parsing**: NEEDS REVIEW: Not implemented in source. `parseAssistantReply`'s `.claudeCLI` case is an empty stub — the source itself flags it with a `// todo: fix this` comment before falling through to `break` — so a `.claudeCLI` reply is never actually extracted from `data`; it always falls through to the generic `"(Empty response)"` fallback regardless of what the CLI actually returned.
- **error-message-extraction**: `parseErrorMessage` MUST prefer `error.message`, then a top-level `message` field, from a parseable JSON error body, and MUST fall back to `"HTTP <statusCode>"` when the body is not JSON or carries neither field.
- **request-builder-statelessness**: `AIRequestBuilder` is a stateless `enum` namespace; none of its declarations require actor isolation, and it MAY be called from any isolation domain.

### ArtificialAnalysisStore

- **rank-store-isolation**: `ArtificialAnalysisStore` MUST be `@MainActor`-isolated; its mutable state (`apiKey`, `rankCache`, `lastGood`, `inflight`) is a `UserSetting` or a plain static and is serialized only by that actor.
- **rank-model-shape**: `ModelRank` MUST be `Codable & Sendable & Equatable` and carry `name`, `intelligenceIndex`, `codingIndex`, and `outputTokensPerSecond`, each numeric field optional.
- **rank-requires-api-key**: `isConfigured` MUST be `true` exactly when the stored `apiKey` is non-empty, and `rank(for:)` MUST return `nil` without performing any network fetch when `isConfigured` is `false`.
- **rank-join-or-start**: `allRanks()` MUST join an already-inflight fetch (`await inflight.value`) rather than starting a second one, so N concurrent callers of `rank(for:)` in the same round trigger exactly one HTTP request.
- **rank-last-good-fallback**: When a fetch round returns an empty parse, `allRanks()` MUST fall back to the previous non-empty result (`lastGood`) rather than surfacing an empty leaderboard, and MUST update `lastGood` only from a non-empty result.
- **rank-per-model-persistence**: `rank(for:)` MUST persist a successfully matched rank into `rankCache` keyed by the caller's original model id string, so `cachedRanks()` can paint a previously seen model instantly on reopen, before any live round completes.
- **rank-matching-reuse**: `rank(for:)` MUST resolve which leaderboard slug best matches `model` using `ModelCatalogStore.bestMatchKey`, the same conservative matching algorithm the description catalogs use — it MUST NOT implement a second matching algorithm.
- **rank-fetch-parse-purity**: `parse(_:)` and `fetchData` MUST be `nonisolated`; `parse` MUST be pure (no I/O, no shared-state mutation) and MUST skip any entry whose `slug` is missing or empty.
- **rank-fetch-degrades-to-nil**: `fetchData` MUST return `nil` — never throw — for any network failure, non-200 response, or malformed request, so a failed round degrades to `[:]` inside `allRanks()` rather than propagating an error.

### ClaudeCLI

- **cli-binary-search-order**: `findBinary()` MUST search, in order, `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, and MUST return the first path that `FileManager.isExecutableFile` confirms, or `nil` if none qualify.
- **cli-binary-missing-throws**: `run` MUST throw `CLIError.binaryNotFound` before spawning anything when `findBinary()` returns `nil`.
- **cli-argument-shape**: `run` MUST invoke the resolved binary with `-p --system-prompt <systemPrompt>`, and MUST append `--model <model>` only when `model` is non-empty, leaving the CLI's own default model selection intact otherwise.
- **cli-path-augmentation**: `run` MUST prepend `~/.local/bin`, `/usr/local/bin`, and `/opt/homebrew/bin` to the child process's inherited `PATH` environment variable before launch.
- **cli-headless-marker**: `run` MUST set `AGENTIC_TOOLKIT_HEADLESS=1` in the child's environment so an inherited session-tracking hook can identify this as a programmatic invocation rather than a real interactive session.
- **cli-launch-failure**: `run` MUST catch a `Process.run()` failure and rethrow it as `CLIError.launchFailed(<localizedDescription>)`, never letting the underlying error type escape.
- **cli-stdin-write-non-fatal**: `run` MUST write `prompt` to the child's stdin and close it using the throwing `FileHandle` API inside a `do`/`catch`, and MUST treat a write failure (child already exited) as non-fatal — it MUST proceed to read whatever the child emitted rather than failing the call.
- **cli-concurrent-drain**: `run` MUST read the child's stdout and stderr pipes concurrently with waiting for exit (via `async let`), never sequentially, to avoid deadlocking against a child that fills the pipe buffer (~64KB) before `run` starts draining it.
- **cli-wait-off-cooperative-pool**: `run` MUST perform `Process.waitUntilExit()` off the Swift concurrency cooperative thread pool (via a background `DispatchQueue` inside a `withCheckedContinuation`), since `waitUntilExit()` blocks its calling thread.
- **cli-timeout-terminates**: `run` MUST start a timeout `Task` that sleeps for `timeout` seconds and calls `process.terminate()` if the process is still running when the sleep completes, and MUST cancel that timeout task once the process has exited.
- **cli-nonzero-exit-throws**: `run` MUST throw `CLIError.nonZeroExit(code:stderr:)` when `process.terminationStatus != 0`, truncating the reported stderr to its first 200 characters in the error's `errorDescription`.
- **cli-empty-reply-throws**: `run` MUST throw `CLIError.emptyReply` when the trimmed stdout is empty on a zero exit status.
- **cli-error-sendable**: `CLIError` MUST conform to `Error & LocalizedError & Sendable` and MUST supply a non-nil `errorDescription` for every case.

### ModelCatalogStore

- **catalog-store-isolation**: `ModelCatalogStore` MUST be `@MainActor`-isolated for its stateful surface (`catalog()`, `lastGood`, `inflight`), while its pure helpers (`merged`, `isSubstantial`, `parseOpenRouter`, `parseModelsDev`, `parseAdhCatalog`, `bestMatch`, `bestMatchKey`, `fetchData`) MUST be declared `nonisolated` so they can run off the main actor.
- **catalog-shape**: `Catalog` MUST be `Sendable` and carry independent `openRouter`, `modelsDev`, and `adh` dictionaries (`[String: String]`), with `isEmpty` true only when all three are empty.
- **catalog-join-or-start**: `catalog()` MUST join an already-inflight fetch rather than starting a second one, so N concurrent callers trigger exactly one three-way network round.
- **catalog-concurrent-fetch**: `catalog()` MUST fetch OpenRouter, models.dev, and the adh endpoint concurrently (via `async let`), not sequentially.
- **catalog-per-side-fallback**: `merged(_:lastGood:)` MUST replace only the sides of `fresh` that are empty with the corresponding side of `lastGood`, and MUST leave a successfully fetched side untouched even when its sibling sides failed — one side's failure MUST NOT blank another side's data nor poison `lastGood` with a half-empty round.
- **catalog-description-priority**: `description(for:)` MUST try the adh catalog first, then OpenRouter, then models.dev, returning the first confident match — the adh catalog is the curated, operator-authored source and takes priority over the third-party catalogs.
- **catalog-adh-url-mutable**: `adhCatalogURL` MUST be a mutable `public static var` (not a constant), defaulting to `"https://api.agenticdeveloperhub.com/persona/provider-templates?pageSize=100"`, and its doc comment MUST be honored: it fetches a single page capped at `pageSize=100` and does not paginate through `total`.
- **openrouter-parse-skips-empty**: `parseOpenRouter` MUST map `data[].id` to `data[].description` and MUST skip any entry with a missing id or a missing/empty description.
- **modelsdev-parse-first-provider-wins**: `parseModelsDev` MUST iterate providers in sorted key order and MUST keep the first provider's description for a given model id, ignoring later providers' descriptions of the same id.
- **adh-parse-skips-empty**: `parseAdhCatalog` MUST map each catalog item's `models[].name` to `models[].description`, skipping entries with a missing/empty description or a name already claimed by an earlier item.
- **best-match-prefix-anchored**: `bestMatchKey`/`bestMatch` MUST require a candidate's last path segment, normalized to lowercase ASCII alphanumerics, to start with the model's normalized base name — a candidate that merely contains the base name MUST NOT match.
- **best-match-size-restriction**: When the queried model carries a parameter-size tag (e.g. `:8b`), matching MUST restrict to candidates sharing that exact size token when any exist, otherwise to size-less (family-level) candidates, and MUST NEVER match a candidate carrying a different size token.
- **best-match-shortest-wins**: Among qualifying candidates, `bestMatchKey` MUST prefer the one with the shortest normalized id, then the lexicographically first raw key, as a deterministic tiebreaker.
- **best-match-latest-retry**: `bestMatchKey` MUST retry the match with a trailing `"latest"` suffix stripped from the model's normalized base name when the first attempt fails and the base name is not itself exactly `"latest"`.
- **best-match-degenerate-inputs**: `bestMatch`/`bestMatchKey` MUST return `nil` for an empty model name, a model name whose base segment is empty (e.g. `":16b"`), or an empty candidate list — never throw or crash.
- **substantiality-threshold**: `isSubstantial` MUST require at least 40 characters AND at least one space character before a fetched description is allowed to satisfy the catalog fallback.
- **catalog-fetch-degrades-to-nil**: `fetchData` MUST return `nil` — never throw — for any network failure, non-200 response, or unparseable URL string.

### OllamaModelMetadata / LocalModelMetadataStore

- **ollama-metadata-shape**: `OllamaModelMetadata` MUST be `Codable & Equatable & Sendable` and carry `capabilities`, `parameterSize`, `quantization`, and `contextLength`, with `supportsTools`/`supportsVision` derived from whether `capabilities` contains `"tools"`/`"vision"`.
- **loopback-detection**: `isLoopback(baseURL:)` MUST return `true` only when the URL's host, lowercased, is one of `localhost`, `127.0.0.1`, `0.0.0.0`, `::1`, or `[::1]`, and `false` for any other host including a malformed URL.
- **native-base-derivation**: `nativeOllamaBase(fromOpenAIBase:)` MUST strip trailing slashes and, if present, a trailing `/v1` segment (plus any further trailing slashes) from the supplied OpenAI-compatible base URL to reach Ollama's native API root.
- **show-parse-requires-signal**: `parseShow` MUST return `nil` when the body is not a JSON object or when `capabilities` is empty AND `parameterSize`, `quantization`, and `contextLength` are all `nil` — a response carrying nothing useful MUST NOT produce a metadata value.
- **show-parse-context-length-key**: `parseShow` MUST locate `contextLength` by scanning `model_info` for the first key ending in `.context_length`, accepting either an `Int` or a `Double` JSON value for it.
- **metadata-fetch-degrades-to-nil**: `fetch(openAIBaseURL:model:timeout:)` MUST return `nil` — never throw — when the derived native base is empty, the URL/body fails to construct, the request fails, or the response is not a 200.
- **metadata-store-statelessness**: `LocalModelMetadataStore` is a stateless `enum` namespace holding no mutable static state; none of its declarations require actor isolation.

### OllamaModelPageStore

- **page-info-shape**: `PageInfo` MUST be `Sendable & Equatable` and carry optional `description`, `downloads`, and `updated`, with `isEmpty` true only when all three are `nil`.
- **page-url-routing**: `pageURL(for:)` MUST drop any `:tag` suffix from the model id, route a bare name to `https://ollama.com/library/<name>`, and route a `namespace/name` id to `https://ollama.com/<namespace>/<name>`.
- **page-url-rejects-malformed**: `pageURL(for:)` MUST return `nil` for an empty model id, or one whose name segment starts with `/` or ends with `/`.
- **description-parse-priority**: `parseDescription` MUST prefer an `og:description` meta tag (in either attribute order) over a plain `name="description"` meta tag, MUST entity-unescape the captured text (`&amp;` decoded last, so `&amp;lt;` yields `&lt;` rather than `<`), and MUST return `nil` when the trimmed result is empty or no matching tag exists.
- **stats-parse-independent-fields**: `parseStats` MUST extract `downloads` and `updated` independently via separate regular expressions, and MUST return `nil` for either field whose markup is absent, without requiring the other field to be present.
- **page-fetch-degrades-to-nil**: `fetchInfo(model:timeout:)` MUST return `nil` — never throw — when `pageURL` fails to construct, the request fails, the response is not a 200, or the body cannot be decoded as UTF-8.
- **page-store-statelessness**: `OllamaModelPageStore` is a stateless `enum` namespace; none of its declarations require actor isolation.

### OpenAIModelCatalog

- **catalog-fetch-shape**: `fetch(baseURL:apiKey:timeout:)` MUST append `models` as a path component to the trimmed `baseURL`, and MUST set `Authorization: Bearer <apiKey>` only when a non-empty `apiKey` is supplied.
- **catalog-fetch-degrades-to-empty**: `fetch` MUST return `[]` — never throw — when `baseURL` is empty or unparseable, the request fails, or the response status is outside `200..<300`.
- **catalog-parse-shape**: `parse(_:)` MUST extract `data[].id` from an OpenAI-shaped `/models` JSON body via `compactMap`, silently dropping any entry without a string `id`, and MUST return `[]` for a non-JSON body or a body without a `data` array.
- **model-catalog-statelessness**: `OpenAIModelCatalog` is a stateless `enum` namespace; none of its declarations require actor isolation.

### Security

- **api-key-in-memory-only-scope**: `AIRequestConfig.apiKey` and `.customBaseURL` MUST be understood as caller-supplied, in-memory values for the duration of one request — this component itself performs no persistence of them; the caller listed in `AIRequestBuilder`'s doc comment (a view model) is responsible for how they were obtained and stored.
- **artificial-analysis-key-storage**: `ArtificialAnalysisStore.apiKey` and `.rankCache` MUST be backed by `UserSetting` constructed WITHOUT `isSecure: true`, which routes their storage through the plain (non-Keychain) settings provider rather than the secure one — this is a genuine, unmitigated plaintext-storage fact about the shipped code, not a hypothetical.
- **google-key-in-url**: The Google request builder MUST place `config.apiKey` directly in the request URL's query string (`?key=<apiKey>`) per the Gemini API's documented contract — callers and any request-logging infrastructure downstream of this component MUST treat that URL as key-bearing.
- **custom-endpoint-scheme-validation**: NEEDS REVIEW: Not implemented in source. Neither `AIRequestBuilder`'s OpenAI-compatible builder (for the `.custom` provider's `customBaseURL`), nor `OpenAIModelCatalog.fetch`'s `baseURL` parameter, nor `LocalModelMetadataStore.fetch`'s `openAIBaseURL` parameter validates a URL scheme before use — an operator-supplied `http://` endpoint carries its `Authorization: Bearer <apiKey>` header in plaintext with no guard anywhere in this component.

## Appearance

Not applicable — this is server/network/process logic (provider metadata, HTTP request building, CLI subprocess execution, and catalog fetching/matching), not a visual component.

## States

Not applicable — this is server/network/process logic, not a visual component with view states.

## Accessibility

Not applicable — this is server/network/process logic, not a visual component that renders to an accessibility tree.

## Conformance Test Vectors

| ID | Input | Expected output / effect | Traced to |
|----|-------|---------------------------|-----------|
| core-ai-001 | `parseOpenRouter` on `{"data":[{"id":"qwen/qwen3-coder-next","description":"Sparse MoE coding model."},{"id":"empty/desc","description":""},{"id":"no/desc"}]}` | `["qwen/qwen3-coder-next": "Sparse MoE coding model."]` (other two skipped) | `ModelCatalogStoreTests.parsesOpenRouter` |
| core-ai-002 | `parseModelsDev` with providers `zeta` and `alpha` (sorted order: `alpha` first) both describing model id `gpt-5` | `["gpt-5": "alpha copy"]` — the first provider in sorted order wins | `ModelCatalogStoreTests.parsesModelsDev` |
| core-ai-003 | `parseAdhCatalog` with `deepseek-chat` (has description) and `deepseek-reasoner` (empty description) | `deepseek-chat` mapped, `deepseek-reasoner` absent from the result | `ModelCatalogStoreTests.parsesAdhCatalog` |
| core-ai-004 | `bestMatch(for: "qwen3-coder-next:latest", in: ["qwen/qwen3-coder-next": "the one", "qwen/qwen3-coder": "wrong"])` | `"the one"` | `ModelCatalogStoreTests.exactMatch` |
| core-ai-005 | `bestMatch(for: "llama3.1:8b", in: {70b: "seventy", 8b: "eight", non-prefix-anchored 8b: "not-prefix-anchored"})` | `"eight"` — size-tag restriction wins, and a non-prefix-anchored candidate is excluded | `ModelCatalogStoreTests.sizePreference` |
| core-ai-006 | `bestMatch(for: "qwen3.5:4b", in: ["qwen/qwen3.5-24b-instruct": "twenty-four"])` | `nil` — a `4b` query never matches a `24b` candidate | `ModelCatalogStoreTests.sizeDigitBoundary` |
| core-ai-007 | `bestMatch(for: "vaultbox/qwen3.5-uncensored:4b", in: ["qwen/qwen3.5": "official base model"])` | `nil` — a fine-tune never inherits its base model's blurb | `ModelCatalogStoreTests.noFineTuneInheritance` |
| core-ai-008 | `bestMatch(for: "grok-2-latest", in: ["x-ai/grok-2-1212": "grok"])` then `bestMatch(for: "latest", in: same)` | `"grok"` (retried with `-latest` stripped), then `nil` (bare `"latest"` never matches) | `ModelCatalogStoreTests.latestSuffix` |
| core-ai-009 | `bestMatch(for: "qwen2.5-coder:32b", in: {32b-instruct: "short", 32b-instruct-turbo: "long"})` | `"short"` — the shorter qualifying id wins deterministically | `ModelCatalogStoreTests.shortestWins` |
| core-ai-010 | `bestMatch(for: "", ...)`, `bestMatch(for: ":16b", ...)`, `bestMatch(for: "llama3.1", in: [:])` | `nil` in all three cases | `ModelCatalogStoreTests.degenerateInputs` |
| core-ai-011 | `merged` with a half-successful fresh round (`openRouter` fresh, `modelsDev`/`adh` empty) against a full `lastGood` | fresh `openRouter` kept; `modelsDev`/`adh` fall back to `lastGood`; a fully-empty fresh round against `lastGood` returns `lastGood` entirely; a fully-empty round with no `lastGood` stays empty | `ModelCatalogStoreTests.mergedPerSideFallback` |
| core-ai-012 | `isSubstantial("www.vaultbox.ai")`, `isSubstantial("Uncensored")`, `isSubstantial("An open-source Mixture-of-Experts code language model.")` | `false`, `false`, `true` | `ModelCatalogStoreTests.substantiality` |
| core-ai-013 | `ArtificialAnalysisStore.parse` on the documented v2 shape with one slugged, complete entry, one entry with no slug, and one bare-slug entry | 2 ranks kept (no-slug entry dropped); `o3-mini` carries `intelligenceIndex == 62.9`, `codingIndex == 55.8`, `outputTokensPerSecond == 153.831`; `bare-model` carries `name == "bare-model"` and `intelligenceIndex == nil` | `ArtificialAnalysisStoreTests.parsesDocumentedShape` |
| core-ai-014 | `ArtificialAnalysisStore.parse` on `"not json"` and on `{"data": {}}` | empty result in both cases | `ArtificialAnalysisStoreTests.parsesMalformed` |
| core-ai-015 | `pageURL(for: "llama3.2")` and `pageURL(for: "deepseek-coder-v2:16b")` | `https://ollama.com/library/llama3.2` and `https://ollama.com/library/deepseek-coder-v2` (tag stripped) | `OllamaModelPageStoreTests.libraryURL` |
| core-ai-016 | `pageURL(for: "huihui_ai/qwen3.5-abliterated:latest")` | `https://ollama.com/huihui_ai/qwen3.5-abliterated` | `OllamaModelPageStoreTests.communityURL` |
| core-ai-017 | `pageURL(for: "")`, `pageURL(for: ":latest")`, `pageURL(for: "/leading")`, `pageURL(for: "trailing/")` | `nil` in all four cases | `OllamaModelPageStoreTests.badNames` |
| core-ai-018 | `parseDescription` on HTML carrying both a plain `description` meta and an `og:description` meta with `&#39;`/`&amp;` entities | the `og:description` text wins, unescaped to `"Meta's Llama & friends"` | `OllamaModelPageStoreTests.parsesOG` |
| core-ai-019 | `parseStats` on HTML with a `117.4M`/`Downloads` span pair and an `Updated`/`1 year ago` span pair; and on `"<html></html>"` | `("117.4M", "1 year ago")`; and `(nil, nil)` when absent | `OllamaModelPageStoreTests.parsesStats`, `.parsesStatsEmpty` |
| core-ai-020 | `LocalModelMetadataStore.parseShow` on a body with `capabilities: ["completion","tools","insert"]`, `parameter_size: "32.8B"`, `quantization_level: "Q4_K_M"`, and a `qwen2.context_length: 32768` key | `capabilities`, `parameterSize == "32.8B"`, `quantization == "Q4_K_M"`, `contextLength == 32768`, `supportsTools == true`, `supportsVision == false` | `OllamaModelMetadataTests.parsesShow` |
| core-ai-021 | `nativeOllamaBase(fromOpenAIBase:)` on `".../v1"`, `".../v1/"`, and `"..."` (no suffix) | all three normalize to the same base with `/v1` and trailing slashes removed | `OllamaModelMetadataTests.derivesNativeBase` |
| core-ai-022 | `isLoopback(baseURL:)` on `http://localhost:11434/v1`, `http://127.0.0.1:11434/v1`, `https://api.openai.com/v1` | `true`, `true`, `false` | `OllamaModelMetadataTests.detectsLoopback` |
| core-ai-023 | `OpenAIModelCatalog.parse` on `{"data":[{"id":"a"},{"object":"model"},{"id":"b"}]}`, on `{"error":{"message":"nope"}}`, and on `"not json"` | `["a","b"]` (id-less entry skipped); `[]`; `[]` | `OpenAIModelCatalogTests.skipsEntriesWithoutId`, `.handlesMissingData`, `.handlesGarbage` |

## Edge Cases

- **No Artificial Analysis API key configured**: `rank(for:)` MUST return `nil` immediately and MUST NOT perform any network request when `ArtificialAnalysisStore.isConfigured` is `false`.
- **Empty custom base URL**: `AIRequestBuilder.buildRequest` MUST throw `AIRequestError.missingBaseURL` for a `.custom` provider whose `customBaseURL` is empty, rather than attempting to build a request against an empty string.
- **Size-tag boundary mismatch**: `ModelCatalogStore.bestMatch`/`bestMatchKey` MUST NEVER match a model carrying one parameter-size tag (e.g. `4b`) against a catalog candidate carrying a different one (e.g. `24b`), even when every other token matches.
- **Concurrent catalog/rank requests**: N concurrent callers of `ModelCatalogStore.catalog()` or `ArtificialAnalysisStore`'s internal `allRanks()` within the same round MUST result in exactly one network round-trip per source, joined via the shared `inflight` task, never N independent round-trips.
- **All-source network failure**: When every one of OpenRouter, models.dev, and the adh endpoint fails in the same round, `ModelCatalogStore.catalog()` MUST return the previous `lastGood` result (or an empty `Catalog` if none exists yet) rather than throwing.
- **Claude CLI binary absent**: `ClaudeCLI.run` MUST throw `CLIError.binaryNotFound` when none of the three candidate paths is an executable file, and MUST NOT attempt to spawn a process.
- **Claude CLI non-zero exit or timeout**: `ClaudeCLI.run` MUST throw `CLIError.nonZeroExit` on a non-zero termination status, and SHOULD terminate a hung child via `process.terminate()` once the caller-supplied `timeout` elapses.
- **Broken pipe writing to Claude CLI stdin**: `ClaudeCLI.run` MUST treat a failed stdin write (child exited before reading) as non-fatal and MUST proceed to read whatever the child already emitted, rather than propagating the write error.
- **Malformed/garbage JSON everywhere**: Every parsing function in this component (`parseOpenRouter`, `parseModelsDev`, `parseAdhCatalog`, `ArtificialAnalysisStore.parse`, `LocalModelMetadataStore.parseShow`, `OpenAIModelCatalog.parse`, `AIRequestBuilder.parseAssistantReply`) MUST return an empty/`nil` result for non-JSON or structurally unexpected input, and MUST NOT throw or crash.
- **Ollama page markup partially present**: `OllamaModelPageStore.parseStats` MUST return a result whose `downloads` and `updated` fields are independently `nil` when only one of the two markup patterns is present, rather than requiring both or neither.

## Configuration

| Name | Owner | Default | Notes |
|------|-------|---------|-------|
| `AIRequestConfig.provider` | caller | — (required) | Selects which of the 5 builders/parsers runs. |
| `AIRequestConfig.model` | caller | — (required, may be empty) | An empty string lets each provider's builder substitute its own default model. |
| `AIRequestConfig.apiKey` | caller | — (required) | Ignored entirely for `.claudeCLI`. |
| `AIRequestConfig.customBaseURL` | caller | — (required for `.custom`) | Unused by the other four providers. |
| `AIRequestConfig.maxTokens` | caller | — (required) | Passed through verbatim into every provider's request body / generation config. |
| `AIRequestConfig.timeoutInterval` | caller | — (required) | Set on the built `URLRequest` for the three HTTP-issuing providers. |
| `aiplugin.artificialAnalysisAPIKey` (`UserSetting<String>`) | `ArtificialAnalysisStore` | `""` | Non-secure storage (see Security). Gates `isConfigured`/`rank(for:)`. |
| `aiplugin.artificialAnalysisRankCache` (`UserSetting<[String: ModelRank]>`) | `ArtificialAnalysisStore` | `[:]` | Per-model-id resolved-rank cache, persisted across launches. |
| `ModelCatalogStore.adhCatalogURL` | `ModelCatalogStore` | `"https://api.agenticdeveloperhub.com/persona/provider-templates?pageSize=100"` | Mutable process-wide static; capped at `pageSize=100`, does not paginate. |
| `ClaudeCLI` binary search paths | `ClaudeCLI` | `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude` (first executable wins) | Fixed list, not configurable by a caller. |
| `ClaudeCLI.run(timeout:)` | caller | — (required) | Drives the terminate-on-timeout watchdog task. |
| `ArtificialAnalysisStore` fetch timeout | `ArtificialAnalysisStore.fetchData` | `10` seconds | Not caller-configurable. |
| `ModelCatalogStore` fetch timeout | `ModelCatalogStore.fetchData` | `10` seconds | Not caller-configurable; applies to all three concurrent fetches. |
| `LocalModelMetadataStore.fetch(timeout:)` | caller, default `5` seconds | `5` seconds | |
| `OllamaModelPageStore.fetchInfo(timeout:)` | caller, default `8` seconds | `8` seconds | |
| `OpenAIModelCatalog.fetch(timeout:)` | caller, default `8` seconds | `8` seconds | |

## Deep Linking

Not applicable: none of the 8 files parse or construct app URL schemes or universal links; the only URLs built are outbound HTTP(S) request targets (Anthropic, OpenAI, Google, Artificial Analysis, OpenRouter, models.dev, the adh catalog endpoint, ollama.com, and a caller-supplied Ollama-native/OpenAI-compatible base URL).

## Localization

None of the 8 files use `NSLocalizedString`, a `Bundle` lookup, or a String Catalog — every user-facing string below is a hardcoded English literal.

| Source | String(s) |
|--------|-----------|
| `AIProvider.displayName` | `"Claude Code CLI"`, `"Anthropic (Claude)"`, `"OpenAI (ChatGPT)"`, `"Google (Gemini)"`, `"Custom (OpenAI-compatible)"` |
| `AIProvider.recommendedNote` | `"Uses your existing Claude Code login — no API key needed"`, `"Haiku 4.5 — fast and inexpensive (~$0.80/M input tokens)"`, `"GPT-4.1 Nano — cheapest OpenAI model (~$0.10/M input tokens)"`, `"Gemini 2.0 Flash — fast, free tier available"` |
| `AIProvider.apiKeyPlaceholder` | `"sk-ant-..."`, `"sk-..."`, `"AIza..."`, `"API key"` |
| `AIRequestError.errorDescription` | `"Invalid server response"`, `"Custom base URL is required"`, `"This provider does not use HTTP requests"` |
| `AIRequestBuilder.parseAssistantReply` / `.parseErrorMessage` fallbacks | `"(Unable to parse response)"`, `"(Empty response)"`, `"HTTP \(statusCode)"` |
| `ClaudeCLI.CLIError.errorDescription` | `"Claude CLI not found (install Claude Code or check your PATH)"`, `"Failed to launch claude: \(message)"`, `"claude -p failed: ..."`, `"Empty reply from claude -p"` |

## Accessibility Options

Not applicable — this is non-UI logic with no rendering, so no dynamic type, VoiceOver, or reduced-motion accommodation applies.

## Feature Flags

Not applicable: no feature-flag or remote-config check appears in any of the 8 files; the closest analog, `ArtificialAnalysisStore.isConfigured`, gates behavior on stored API-key presence, not on a flag.

## Analytics

Not applicable: none of the 8 files emit an analytics or telemetry event. `ClaudeCLI.run` sets an environment marker (`AGENTIC_TOOLKIT_HEADLESS=1`) that a downstream session-tracking hook uses to EXCLUDE, not record, the invocation.

## Privacy

**Data collected**: user-entered API keys for Anthropic, OpenAI/custom, Google, and Artificial Analysis (via `AIRequestConfig.apiKey` / `ArtificialAnalysisStore.apiKey`); chat message and system-prompt content passed to `AIRequestBuilder`/`ClaudeCLI`; model id strings passed to the catalog/matching functions.

**Storage**: `ArtificialAnalysisStore.apiKey` and `.rankCache` persist via `UserSetting` constructed without `isSecure: true` — plain, non-Keychain storage (see Security). `AIRequestConfig.apiKey`/`.customBaseURL` are held only in memory by this component for the lifetime of one request; this component does not persist them itself. `ModelCatalogStore`'s `lastGood`/`inflight` and `ArtificialAnalysisStore`'s `lastGood`/`inflight` are process-lifetime, in-memory only, and are lost on relaunch.

**Transmission**: prompt/message content is sent over HTTPS to whichever provider `AIRequestConfig.provider` selects (Anthropic, OpenAI, Google, or a `.custom` OpenAI-compatible endpoint) or, for `.claudeCLI`, is passed only as local subprocess stdin/args to `claude -p` (no network). The Anthropic and Artificial Analysis calls send the API key in an `x-api-key` header; the OpenAI-compatible calls send it in an `Authorization: Bearer` header; the Google call places it directly in the request URL's query string. `ModelCatalogStore`, `OllamaModelPageStore`, and `OpenAIModelCatalog` send only model-id strings or scrape requests (no prompt content) to OpenRouter, models.dev, the adh endpoint, ollama.com, and the caller-supplied OpenAI-compatible `/models` route (which can carry a Bearer API key header — see Security for the missing scheme check on that route).

**Retention**: `rankCache` and the Artificial Analysis API key persist indefinitely in `UserSetting` storage until a caller overwrites or clears them; none of the 8 files implement a TTL or expiry for that persisted data.

## Logging

Not applicable: none of the 8 source files call a logger, `print`, or `os_log` — every failure is communicated only through a return value (`nil` / `[:]` / `[]`) or a thrown, typed error, never logged.

## Platform Notes

- **Apple (SwiftUI / AppKit / UIKit)**: source of truth. All 8 types are Foundation-only (`URLSession`, `JSONSerialization`, `Process`/`Pipe`, `NSRegularExpression`), so the same code serves both AppKit (macOS) and UIKit (iOS) call sites unchanged. The one Apple-only surface with no cross-platform equivalent is `ClaudeCLI.findBinary()`'s hardcoded Unix install paths.
- **Jetpack Compose (Android/Kotlin)**: `AIProvider` maps to a `sealed class`/`enum class` with computed properties; `AIRequestBuilder` maps to per-provider `OkHttpClient`/`Retrofit` request builders; the join-or-start cache maps to a `Mutex`-guarded nullable `Deferred<Catalog>` on a singleton `object`, `await()`ed by joiners rather than re-triggering a fetch; `ClaudeCLI` maps to `ProcessBuilder` with concurrent `InputStream` draining on `Dispatchers.IO`.
- **React/Web (TypeScript)**: `AIProvider` maps to a string-literal union type; `fetch()` replaces `URLSession`; the join-or-start pattern maps to a module-level `Promise<Catalog> | null` that concurrent callers `await` instead of re-invoking the fetch; `ClaudeCLI` has no browser equivalent (no subprocess access) — a web host would need a server-side Node process (`child_process.spawn`) behind an API route.
- **WinUI 3 (C#/.NET)**: `AIProvider` maps to a `sealed record`/enum with switch-expression properties; `AIRequestBuilder` maps to `HttpClient` plus `System.Text.Json.JsonSerializer`; `ArtificialAnalysisStore`'s API key SHOULD map to `Windows.Security.Credentials.PasswordVault` (`PasswordCredential`) rather than reproducing this component's non-secure storage; `ClaudeCLI` maps to `System.Diagnostics.Process` with `RedirectStandardInput/Output/Error` and concurrent `Task.Run` reads; the join-or-start cache maps to a `SemaphoreSlim`-guarded nullable `Task<T>`.

## Design Decisions

**Decision**: Every network-backed store (`ArtificialAnalysisStore.allRanks()`, `ModelCatalogStore.catalog()`) always performs a live fetch and never serves from a timed cache; concurrent callers instead join one shared, in-flight `Task`.
**Rationale**: the source doc comments state this directly — a chooser refreshing many models at once must trigger one network round, not one per model, while the very next burst after that round still gets fresh data rather than stale cached data.
**Approved**: pending

**Decision**: Catalog/rank matching (`ModelCatalogStore.bestMatchKey`) is prefix-anchored on the model's normalized base name and restricted by parameter-size tag, rather than a fuzzy or substring match.
**Rationale**: the source doc comment states the reason directly — neither OpenRouter nor models.dev knows about community fine-tunes, so an "uncensored" fine-tune must never inherit its base model's blurb; conservative matching trades recall for correctness.
**Approved**: pending

**Decision**: `ClaudeCLI.run` drains stdout/stderr concurrently with the exit wait, and performs the wait itself off the Swift concurrency cooperative thread pool.
**Rationale**: the source doc comment gives both reasons — a child that writes past the ~64KB pipe buffer would deadlock against a synchronous wait, and `Process.waitUntilExit()` blocks its calling thread, which would otherwise pin a concurrency worker for the duration of the call.
**Approved**: pending

**Decision**: `ClaudeCLI.run` marks its child process's environment with `AGENTIC_TOOLKIT_HEADLESS=1`.
**Rationale**: the source doc comment explains this lets an inherited session-tracking hook (named as "stenographer") distinguish a programmatic/headless invocation from a real interactive Claude Code session and exclude it from recording.
**Approved**: pending

**Decision**: `ModelCatalogStore.description(for:)` checks the adh provider-template catalog before OpenRouter or models.dev.
**Rationale**: the source doc comment states the adh catalog's descriptions are operator-authored and curated, and therefore authoritative where present, with OpenRouter/models.dev retained only as the fallback pair.
**Approved**: pending

## Compliance

| Check | Status | Notes |
|-------|--------|-------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | failed | `ArtificialAnalysisStore.apiKey` and `.rankCache` are constructed via `UserSetting` without `isSecure: true`, which routes them through plain (non-Keychain) storage rather than the secure provider this codebase already offers for exactly this purpose. |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | The four hardcoded provider base URLs are fixed HTTPS literals, but `customBaseURL`/`baseURL`/`openAIBaseURL` accepted from a caller for `.custom` and OpenAI-compatible/Ollama routes carry no scheme validation before an API key is attached to a request against them (see the open question on custom-endpoint-scheme-validation). |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Every fetch function across `ArtificialAnalysisStore`, `ModelCatalogStore`, `LocalModelMetadataStore`, `OllamaModelPageStore`, and `OpenAIModelCatalog` degrades to `nil`/`[:]`/`[]` on any failure rather than throwing, with `ArtificialAnalysisStore`/`ModelCatalogStore` additionally falling back to their last good data. |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | `ClaudeCLI.CLIError` and `AIRequestError` are typed, `LocalizedError`-conforming enums with a description for every case, but `parseAssistantReply`'s `.claudeCLI` branch silently falls through to a generic fallback string instead of surfacing its known-incomplete state as an error. |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Every user-facing string in `AIProvider`, `AIRequestError`, `ClaudeCLI.CLIError`, and `AIRequestBuilder`'s fallback strings is a hardcoded English literal; no localization mechanism appears in any of the 8 files. |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
