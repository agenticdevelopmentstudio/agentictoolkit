---
id: 3b310d80-e18d-4f45-9041-10a278f775c1
domain: agentictoolkit://cookbook/ai/providers/provider-runtime
type: ingredient
title: Provider Runtime
version: 1.1.0
status: review
language: en
summary: Provider metadata, HTTP request building, and network-backed catalog stores
  for AI chat dispatch and model discovery.
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
modified: '2026-09-27'
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

# Provider Runtime

## Overview

The provider runtime is the non-UI logic root for talking to AI chat backends and discovering what models they offer. It has eight parts:

- the provider identity — identifies the five supported backends (`claudeCLI`, `anthropic`, `openai`, `google`, `custom`) and their display metadata (name, default models, recommended model, API-key placeholder, default base URL).
- the request configuration and builder — turns a provider selection and a message list into a provider-shaped HTTP request, and parses a provider's JSON reply or error body back into plain text.
- the model ranking store (backed by the Artificial Analysis leaderboard) — fetches and caches per-model intelligence/coding index rankings, and holds the API key that gates it.
- the local CLI runner — runs the local `claude -p` binary as a subprocess so a caller can get a model reply without an API key, reusing the user's existing Claude Code login.
- the model catalog store — fetches and merges prose model descriptions from OpenRouter, models.dev, and the adh provider-template catalog, then matches a bare or namespaced model id against them.
- the local model metadata store — asks a local Ollama server's native `/api/show` route what a pulled model can do and how big it is.
- the model page store — scrapes a model's `ollama.com` page for its author blurb and live popularity stats, the only place that prose exists for community fine-tunes.
- the model listing store (OpenAI-compatible) — lists the models an OpenAI-compatible `/models` endpoint actually serves.

All eight parts are pure logic with no rendering of their own and no dependency on a UI framework.

## Behavioral Requirements

### Provider Identity

- **provider-identity**: The provider identity MUST be a fixed set of exactly five cases: `claudeCLI` (wire value `"claude_cli"`), `anthropic`, `openai`, `google`, `custom`, and MUST support iterating all cases and reading a stable per-case identity value.
- **provider-display-metadata**: Each case MUST expose a display name, default-models list, recommended model, a note about the recommendation, an API-key placeholder, and a default base URL, each a pure, non-throwing lookup with a value for every case (`custom` and `claudeCLI` return empty strings/lists where a fixed default has no meaning).
- **provider-cli-flag**: A "uses CLI" flag MUST be true only for the CLI provider, and a "requires API key" flag MUST be the logical negation of "uses CLI" — every non-CLI provider requires an API key, the CLI provider never does.
- **provider-safe-to-share**: Because the provider identity holds no reference state, a value MAY be read from any concurrent context; callers MUST NOT need to switch execution contexts just to read provider metadata.

### Request Configuration and Builder

- **request-config-shape**: The request configuration MUST carry exactly a provider selection, a model, an API key, a custom base URL, a max-tokens value, and a timeout interval, all supplied through its constructor.
- **request-config-isolation**: The request configuration MUST be treated as owned by a single caller and MUST NOT be shared across concurrent execution contexts without an explicit handoff — it stays confined to whichever caller constructed it (its current callers are a mini chat view model, a terminal session summarizer, and a settings view model).
- **request-dispatch-by-provider**: The builder MUST dispatch on the configured provider and build an Anthropic Messages request for `anthropic`, an OpenAI-compatible chat-completions request against the fixed `https://api.openai.com` base for `openai`, a Gemini `generateContent` request for `google`, and an OpenAI-compatible request against the configured custom base URL for `custom`.
- **request-custom-requires-base-url**: The builder MUST fail with a missing-base-url error when the provider is `custom` and no custom base URL is supplied, before attempting to build anything.
- **request-cli-provider-throws**: The builder MUST fail with an unsupported-provider error for the CLI provider rather than building an HTTP request — the CLI provider issues no network call from this layer, and callers MUST check whether a provider uses the CLI before ever calling the builder.
- **anthropic-request-shape**: The Anthropic builder MUST POST to `https://api.anthropic.com/v1/messages`, set `x-api-key` to the configured API key and `anthropic-version` to `"2023-06-01"`, default an empty model to `"claude-haiku-4-5-20251001"`, and include `system` in the body only when the system prompt is non-empty.
- **openai-compatible-request-shape**: The OpenAI-compatible builder (used for both `openai` and `custom`) MUST append `v1/chat/completions` to its base URL, set `Authorization: Bearer <apiKey>`, prepend a `system` message when the system prompt is non-empty, and default an empty model to `"gpt-4.1-nano"` for `openai` or leave it as supplied for `custom`.
- **openai-compatible-missing-url-throws**: The OpenAI-compatible builder MUST fail with a missing-base-url error when appending `v1/chat/completions` to the base URL does not yield a valid URL.
- **google-request-shape**: The Google builder MUST target `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent?key=<apiKey>`, default an empty model to `"gemini-2.0-flash"`, remap any message whose role is `"assistant"` to Gemini's `"model"` role, and include `systemInstruction` in the body only when the system prompt is non-empty.
- **reply-parsing-by-provider**: Reply parsing MUST return `"(Unable to parse response)"` when the response body is not a JSON object, and otherwise MUST extract `content[0].text` for `anthropic`, `choices[0].message.content` for `openai` and `custom`, and `candidates[0].content.parts[0].text` for `google`.
- **reply-parsing-empty-fallback**: Reply parsing MUST return `"(Empty response)"` whenever the provider-specific shape is not found in an otherwise-parseable JSON object.
- **claude-cli-reply-parsing**: NEEDS REVIEW: Not implemented. Reply parsing for the CLI provider is an unfinished stub — flagged in the source with a `// todo: fix this` comment before it falls through — so a CLI reply is never actually extracted from the response body; it always falls through to the generic `"(Empty response)"` fallback regardless of what the CLI actually returned.
- **error-message-extraction**: Error message extraction MUST prefer an `error.message` field, then a top-level `message` field, from a parseable JSON error body, and MUST fall back to `"HTTP <statusCode>"` when the body is not JSON or carries neither field.
- **request-builder-statelessness**: The builder holds no state of its own; none of its operations require confinement to a particular execution context, and it MAY be called from any context.

### Model Ranking (Artificial Analysis)

- **rank-store-isolation**: Mutations to the ranking store's state (the API key, the rank cache, the last-good result, and the in-flight fetch) MUST be serialized to a single execution context, so no two operations can race on them.
- **rank-model-shape**: A model-rank record MUST be equality-comparable and safe to share across concurrent contexts, and MUST carry a name, an intelligence index, a coding index, and an output-tokens-per-second figure, each numeric field optional.
- **rank-requires-api-key**: The store MUST report itself configured exactly when its stored API key is non-empty, and resolving a rank for a model MUST return no result, performing no network fetch, when the store is not configured.
- **rank-join-or-start**: Fetching all ranks MUST join an already-inflight fetch rather than starting a second one, so N concurrent callers resolving a rank in the same round trigger exactly one HTTP request.
- **rank-last-good-fallback**: When a fetch round returns an empty parse, fetching all ranks MUST fall back to the previous non-empty result rather than surfacing an empty leaderboard, and MUST update that fallback only from a non-empty result.
- **rank-per-model-persistence**: Resolving a rank for a model MUST persist a successfully matched rank into the rank cache keyed by the caller's original model id string, so cached ranks can paint a previously seen model instantly on reopen, before any live round completes.
- **rank-matching-reuse**: Resolving a rank for a model MUST resolve which leaderboard slug best matches the model using the model catalog store's best-match-key logic, the same conservative matching algorithm the description catalogs use — it MUST NOT implement a second matching algorithm.
- **rank-fetch-parse-purity**: Parsing and fetching the leaderboard data MUST be independent of the store's serialized state; parsing MUST be pure (no I/O, no shared-state mutation) and MUST skip any entry whose slug is missing or empty.
- **rank-fetch-degrades-to-nil**: Fetching leaderboard data MUST return no result — never throw — for any network failure, non-200 response, or malformed request, so a failed round degrades to an empty result inside "fetch all ranks" rather than propagating an error.

### Local CLI Runner

- **cli-binary-search-order**: Locating the CLI binary MUST search, in order, `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, and MUST return the first path confirmed executable, or no result if none qualify.
- **cli-binary-missing-throws**: Running the CLI MUST fail with a binary-not-found error before spawning anything when no binary can be located.
- **cli-argument-shape**: Running the CLI MUST invoke the resolved binary with `-p --system-prompt <systemPrompt>`, and MUST append `--model <model>` only when a model is non-empty, leaving the CLI's own default model selection intact otherwise.
- **cli-path-augmentation**: Running the CLI MUST prepend `~/.local/bin`, `/usr/local/bin`, and `/opt/homebrew/bin` to the child process's inherited `PATH` environment variable before launch.
- **cli-headless-marker**: Running the CLI MUST set `AGENTIC_TOOLKIT_HEADLESS=1` in the child's environment so an inherited session-tracking hook can identify this as a programmatic invocation rather than a real interactive session.
- **cli-launch-failure**: Running the CLI MUST catch a failure to launch the process and re-surface it as a launch-failed error carrying the underlying failure's description, never letting the underlying error type escape.
- **cli-stdin-write-non-fatal**: Running the CLI MUST write the prompt to the child's standard input and close it, and MUST treat a write failure (child already exited) as non-fatal — it MUST proceed to read whatever the child emitted rather than failing the call.
- **cli-concurrent-drain**: Running the CLI MUST read the child's standard output and standard error streams concurrently with waiting for exit, never sequentially, to avoid deadlocking against a child that fills a stream buffer (~64KB) before draining starts.
- **cli-wait-off-async-scheduler**: Running the CLI MUST perform the blocking wait-for-exit call off whatever asynchronous scheduling pool the runtime's own concurrency depends on, since that wait call blocks its calling thread.
- **cli-timeout-terminates**: Running the CLI MUST start a timeout that, once elapsed, terminates the process if it is still running, and MUST cancel that timeout once the process has exited.
- **cli-nonzero-exit-throws**: Running the CLI MUST fail with a non-zero-exit error carrying the exit code and captured stderr when the process's termination status is non-zero, truncating the reported stderr to its first 200 characters.
- **cli-empty-reply-throws**: Running the CLI MUST fail with an empty-reply error when the trimmed standard output is empty on a zero exit status.
- **cli-error-safe-to-share**: Every CLI error case MUST be safe to share across concurrent contexts and MUST supply a non-nil description for every case.

### Model Catalog

- **catalog-store-isolation**: Mutations to the catalog store's stateful surface (fetching the catalog, the last-good result, the in-flight fetch) MUST be serialized to a single execution context, while its pure helpers (merging, substantiality checks, the per-source parsers, best-match resolution, and the raw fetch) MUST be independent of that context so they can run anywhere.
- **catalog-shape**: A catalog value MUST be safe to share across concurrent contexts and MUST carry independent OpenRouter, models.dev, and adh maps (each a string-to-string mapping), with emptiness true only when all three are empty.
- **catalog-join-or-start**: Fetching the catalog MUST join an already-inflight fetch rather than starting a second one, so N concurrent callers trigger exactly one three-way network round.
- **catalog-concurrent-fetch**: Fetching the catalog MUST fetch OpenRouter, models.dev, and the adh endpoint concurrently, not sequentially.
- **catalog-per-side-fallback**: Merging a fresh result with the last-good result MUST replace only the sides of the fresh result that are empty with the corresponding side of the last-good result, and MUST leave a successfully fetched side untouched even when its sibling sides failed — one side's failure MUST NOT blank another side's data nor poison the last-good result with a half-empty round.
- **catalog-description-priority**: Looking up a description MUST try the adh catalog first, then OpenRouter, then models.dev, returning the first confident match — the adh catalog is the curated, operator-authored source and takes priority over the third-party catalogs.
- **catalog-adh-url-mutable**: The adh catalog URL MUST be a mutable, process-wide value (not fixed), defaulting to `"https://api.agenticdeveloperhub.com/persona/provider-templates?pageSize=100"`; it fetches a single page capped at `pageSize=100` and does not paginate through `total`.
- **openrouter-parse-skips-empty**: Parsing the OpenRouter catalog MUST map `data[].id` to `data[].description` and MUST skip any entry with a missing id or a missing/empty description.
- **modelsdev-parse-first-provider-wins**: Parsing the models.dev catalog MUST iterate providers in sorted key order and MUST keep the first provider's description for a given model id, ignoring later providers' descriptions of the same id.
- **adh-parse-skips-empty**: Parsing the adh catalog MUST map each catalog item's `models[].name` to `models[].description`, skipping entries with a missing/empty description or a name already claimed by an earlier item.
- **best-match-prefix-anchored**: Best-match resolution MUST require a candidate's last path segment, normalized to lowercase ASCII alphanumerics, to start with the model's normalized base name — a candidate that merely contains the base name MUST NOT match.
- **best-match-size-restriction**: When the queried model carries a parameter-size tag (e.g. `:8b`), matching MUST restrict to candidates sharing that exact size token when any exist, otherwise to size-less (family-level) candidates, and MUST NEVER match a candidate carrying a different size token.
- **best-match-shortest-wins**: Among qualifying candidates, best-match resolution MUST prefer the one with the shortest normalized id, then the lexicographically first raw key, as a deterministic tiebreaker.
- **best-match-latest-retry**: Best-match resolution MUST retry the match with a trailing `"latest"` suffix stripped from the model's normalized base name when the first attempt fails and the base name is not itself exactly `"latest"`.
- **best-match-degenerate-inputs**: Best-match resolution MUST return no match for an empty model name, a model name whose base segment is empty (e.g. `":16b"`), or an empty candidate list — never throw or crash.
- **substantiality-threshold**: A substantiality check MUST require at least 40 characters AND at least one space character before a fetched description is allowed to satisfy the catalog fallback.
- **catalog-fetch-degrades-to-nil**: The raw catalog fetch MUST return no result — never throw — for any network failure, non-200 response, or unparseable URL string.

### Local Model Metadata

- **ollama-metadata-shape**: A local model metadata record MUST be equality-comparable and safe to share across concurrent contexts, and MUST carry capabilities, parameter size, quantization, and context length, with tool-support and vision-support flags derived from whether capabilities contains `"tools"`/`"vision"`.
- **loopback-detection**: Determining whether a base URL is a loopback address MUST return true only when the URL's host, lowercased, is one of `localhost`, `127.0.0.1`, `0.0.0.0`, `::1`, or `[::1]`, and false for any other host including a malformed URL.
- **native-base-derivation**: Deriving the native API base from an OpenAI-compatible base URL MUST strip trailing slashes and, if present, a trailing `/v1` segment (plus any further trailing slashes), to reach Ollama's native API root.
- **show-parse-requires-signal**: Parsing a model-info response MUST return no result when the body is not a JSON object or when capabilities is empty AND parameter size, quantization, and context length are all absent — a response carrying nothing useful MUST NOT produce a metadata value.
- **show-parse-context-length-key**: Parsing MUST locate the context length by scanning the model-info payload for the first key ending in `.context_length`, accepting either an integer or a floating-point JSON value for it.
- **metadata-fetch-degrades-to-nil**: Fetching metadata MUST return no result — never throw — when the derived native base is empty, the URL/body fails to construct, the request fails, or the response is not a 200.
- **metadata-store-statelessness**: The local model metadata store holds no mutable state of its own; none of its operations require confinement to a particular execution context.

### Model Page Info

- **page-info-shape**: A page-info record MUST be equality-comparable and safe to share across concurrent contexts, and MUST carry optional description, downloads, and updated fields, with emptiness true only when all three are absent.
- **page-url-routing**: Building a page URL MUST drop any `:tag` suffix from the model id, route a bare name to `https://ollama.com/library/<name>`, and route a `namespace/name` id to `https://ollama.com/<namespace>/<name>`.
- **page-url-rejects-malformed**: Building a page URL MUST return no result for an empty model id, or one whose name segment starts with `/` or ends with `/`.
- **description-parse-priority**: Parsing the description MUST prefer an `og:description` meta tag (in either attribute order) over a plain `name="description"` meta tag, MUST entity-unescape the captured text (`&amp;` decoded last, so `&amp;lt;` yields `&lt;` rather than `<`), and MUST return no result when the trimmed text is empty or no matching tag exists.
- **stats-parse-independent-fields**: Parsing stats MUST extract downloads and updated independently via separate matching passes, and MUST return no value for either field whose markup is absent, without requiring the other field to be present.
- **page-fetch-degrades-to-nil**: Fetching page info MUST return no result — never throw — when the page URL fails to construct, the request fails, the response is not a 200, or the body cannot be decoded as text.
- **page-store-statelessness**: The model page store holds no mutable state of its own; none of its operations require confinement to a particular execution context.

### Model Listing (OpenAI-Compatible)

- **catalog-fetch-shape**: Fetching the model listing MUST append `models` as a path component to the trimmed base URL, and MUST set `Authorization: Bearer <apiKey>` only when a non-empty API key is supplied.
- **catalog-fetch-degrades-to-empty**: Fetching the model listing MUST return an empty list — never throw — when the base URL is empty or unparseable, the request fails, or the response status is outside `200..<300`.
- **catalog-parse-shape**: Parsing the model listing MUST extract `data[].id` from an OpenAI-shaped `/models` JSON body, silently dropping any entry without a string id, and MUST return an empty list for a non-JSON body or a body without a `data` array.
- **model-catalog-statelessness**: The model listing store holds no mutable state of its own; none of its operations require confinement to a particular execution context.

### Security

- **api-key-in-memory-only-scope**: The API key and custom base URL held by the request configuration MUST be understood as caller-supplied, in-memory values for the duration of one request — this component itself performs no persistence of them; responsibility for how they were obtained and stored belongs to the caller (a chat view model, a terminal summarizer, or a settings view model).
- **artificial-analysis-key-storage**: The API key and rank cache backing the model ranking store MUST be persisted via the plain settings store rather than the secure credential store — this is a genuine, unmitigated plaintext-storage fact about the shipped code, not a hypothetical (see Platform Notes for the storage mechanism this maps to).
- **google-key-in-url**: The Google request builder MUST place the configured API key directly in the request URL's query string (`?key=<apiKey>`) per the Gemini API's documented contract — callers and any request-logging infrastructure downstream of this component MUST treat that URL as key-bearing.
- **custom-endpoint-scheme-validation**: NEEDS REVIEW: Not implemented. Neither the request builder's OpenAI-compatible path (for the custom provider's base URL), nor the model listing store's fetch, nor the local model metadata store's fetch validates a URL scheme before use — an operator-supplied `http://` endpoint carries its `Authorization: Bearer <apiKey>` header in plaintext with no guard anywhere in this component.

## Appearance

Not applicable — this is server/network/process logic (provider metadata, HTTP request building, CLI subprocess execution, and catalog fetching/matching), not a visual component.

## States

Not applicable — this is server/network/process logic, not a visual component with view states.

## Accessibility

Not applicable — this is server/network/process logic, not a visual component that renders to an accessibility tree.

## Conformance Test Vectors

| ID | Input | Expected output / effect | Traced to |
|----|-------|---------------------------|-----------|
| core-ai-001 | Parse the OpenRouter catalog response `{"data":[{"id":"qwen/qwen3-coder-next","description":"Sparse MoE coding model."},{"id":"empty/desc","description":""},{"id":"no/desc"}]}` | `["qwen/qwen3-coder-next": "Sparse MoE coding model."]` (other two skipped) | the model catalog's test coverage |
| core-ai-002 | Parse the models.dev catalog with providers `zeta` and `alpha` (sorted order: `alpha` first) both describing model id `gpt-5` | `["gpt-5": "alpha copy"]` — the first provider in sorted order wins | the model catalog's test coverage |
| core-ai-003 | Parse the adh catalog with `deepseek-chat` (has description) and `deepseek-reasoner` (empty description) | `deepseek-chat` mapped, `deepseek-reasoner` absent from the result | the model catalog's test coverage |
| core-ai-004 | Best-match `"qwen3-coder-next:latest"` against candidates `{"qwen/qwen3-coder-next": "the one", "qwen/qwen3-coder": "wrong"}` | `"the one"` | the model catalog's test coverage |
| core-ai-005 | Best-match `"llama3.1:8b"` against candidates `{70b: "seventy", 8b: "eight", non-prefix-anchored 8b: "not-prefix-anchored"}` | `"eight"` — size-tag restriction wins, and a non-prefix-anchored candidate is excluded | the model catalog's test coverage |
| core-ai-006 | Best-match `"qwen3.5:4b"` against candidates `{"qwen/qwen3.5-24b-instruct": "twenty-four"}` | no match — a `4b` query never matches a `24b` candidate | the model catalog's test coverage |
| core-ai-007 | Best-match `"vaultbox/qwen3.5-uncensored:4b"` against candidates `{"qwen/qwen3.5": "official base model"}` | no match — a fine-tune never inherits its base model's blurb | the model catalog's test coverage |
| core-ai-008 | Best-match `"grok-2-latest"` against `{"x-ai/grok-2-1212": "grok"}`, then best-match `"latest"` against the same candidates | `"grok"` (retried with `-latest` stripped), then no match (bare `"latest"` never matches) | the model catalog's test coverage |
| core-ai-009 | Best-match `"qwen2.5-coder:32b"` against candidates `{32b-instruct: "short", 32b-instruct-turbo: "long"}` | `"short"` — the shorter qualifying id wins deterministically | the model catalog's test coverage |
| core-ai-010 | Best-match `""`, best-match `":16b"`, best-match `"llama3.1"` against an empty candidate list | no match in all three cases | the model catalog's test coverage |
| core-ai-011 | Merge a half-successful fresh round (OpenRouter side fresh, models.dev/adh sides empty) against a full last-good result | fresh OpenRouter side kept; models.dev/adh sides fall back to the last-good result; a fully-empty fresh round against a last-good result returns that last-good result entirely; a fully-empty round with no last-good result stays empty | the model catalog's test coverage |
| core-ai-012 | Substantiality check on `"www.vaultbox.ai"`, `"Uncensored"`, `"An open-source Mixture-of-Experts code language model."` | false, false, true | the model catalog's test coverage |
| core-ai-013 | Parse the model-ranking response on the documented v2 shape with one slugged, complete entry, one entry with no slug, and one bare-slug entry | 2 ranks kept (no-slug entry dropped); `o3-mini` carries an intelligence index of `62.9`, a coding index of `55.8`, and an output-tokens-per-second value of `153.831`; `bare-model` carries name `"bare-model"` and no intelligence index | the model ranking store's test coverage |
| core-ai-014 | Parse the model-ranking response on `"not json"` and on `{"data": {}}` | empty result in both cases | the model ranking store's test coverage |
| core-ai-015 | Build a page URL for `"llama3.2"` and for `"deepseek-coder-v2:16b"` | `https://ollama.com/library/llama3.2` and `https://ollama.com/library/deepseek-coder-v2` (tag stripped) | the model page store's test coverage |
| core-ai-016 | Build a page URL for `"huihui_ai/qwen3.5-abliterated:latest"` | `https://ollama.com/huihui_ai/qwen3.5-abliterated` | the model page store's test coverage |
| core-ai-017 | Build a page URL for `""`, `":latest"`, `"/leading"`, `"trailing/"` | no result in all four cases | the model page store's test coverage |
| core-ai-018 | Parse the description from HTML carrying both a plain `description` meta and an `og:description` meta with `&#39;`/`&amp;` entities | the `og:description` text wins, unescaped to `"Meta's Llama & friends"` | the model page store's test coverage |
| core-ai-019 | Parse stats from HTML with a `117.4M`/`Downloads` span pair and an `Updated`/`1 year ago` span pair; and from `"<html></html>"` | `("117.4M", "1 year ago")`; and no value for either field when absent | the model page store's test coverage |
| core-ai-020 | Parse a model-info response with `capabilities: ["completion","tools","insert"]`, `parameter_size: "32.8B"`, `quantization_level: "Q4_K_M"`, and a `qwen2.context_length: 32768` key | capabilities preserved, parameter size `"32.8B"`, quantization `"Q4_K_M"`, context length `32768`, tool-support true, vision-support false | the local model metadata store's test coverage |
| core-ai-021 | Derive the native Ollama base from `".../v1"`, `".../v1/"`, and `"..."` (no suffix) | all three normalize to the same base with `/v1` and trailing slashes removed | the local model metadata store's test coverage |
| core-ai-022 | Loopback check on `http://localhost:11434/v1`, `http://127.0.0.1:11434/v1`, `https://api.openai.com/v1` | true, true, false | the local model metadata store's test coverage |
| core-ai-023 | Parse the model listing on `{"data":[{"id":"a"},{"object":"model"},{"id":"b"}]}`, on `{"error":{"message":"nope"}}`, and on `"not json"` | `["a","b"]` (id-less entry skipped); empty list; empty list | the model listing store's test coverage |

## Edge Cases

- **No model-ranking API key configured**: resolving a rank for a model MUST return no result immediately and MUST NOT perform any network request when the model ranking store is not configured.
- **Empty custom base URL**: the request builder MUST fail with a missing-base-url error for a `custom` provider whose custom base URL is empty, rather than attempting to build a request against an empty string.
- **Size-tag boundary mismatch**: best-match resolution MUST NEVER match a model carrying one parameter-size tag (e.g. `4b`) against a catalog candidate carrying a different one (e.g. `24b`), even when every other token matches.
- **Concurrent catalog/rank requests**: N concurrent callers fetching the catalog or resolving ranks within the same round MUST result in exactly one network round-trip per source, joined via the shared in-flight fetch, never N independent round-trips.
- **All-source network failure**: When every one of OpenRouter, models.dev, and the adh endpoint fails in the same round, fetching the catalog MUST return the previous last-good result (or an empty catalog if none exists yet) rather than throwing.
- **CLI binary absent**: running the CLI MUST fail with a binary-not-found error when none of the three candidate paths is an executable file, and MUST NOT attempt to spawn a process.
- **CLI non-zero exit or timeout**: running the CLI MUST fail with a non-zero-exit error on a non-zero termination status, and SHOULD terminate a hung child once the caller-supplied timeout elapses.
- **Broken pipe writing to the CLI's standard input**: running the CLI MUST treat a failed standard-input write (child exited before reading) as non-fatal and MUST proceed to read whatever the child already emitted, rather than propagating the write error.
- **Malformed/garbage JSON everywhere**: every parsing function in this component (the per-source catalog parsers, the ranking parser, the model-info parser, the model-listing parser, the reply parser) MUST return an empty/no result for non-JSON or structurally unexpected input, and MUST NOT throw or crash.
- **Ollama page markup partially present**: parsing stats MUST return a result whose downloads and updated fields are independently absent when only one of the two markup patterns is present, rather than requiring both or neither.

## Configuration

| Name | Owner | Default | Notes |
|------|-------|---------|-------|
| provider (request configuration) | caller | — (required) | Selects which of the 5 builders/parsers runs. |
| model (request configuration) | caller | — (required, may be empty) | An empty string lets each provider's builder substitute its own default model. |
| apiKey (request configuration) | caller | — (required) | Ignored entirely for the CLI provider. |
| customBaseURL (request configuration) | caller | — (required for `custom`) | Unused by the other four providers. |
| maxTokens (request configuration) | caller | — (required) | Passed through verbatim into every provider's request body / generation config. |
| timeoutInterval (request configuration) | caller | — (required) | Set on the built request for the three HTTP-issuing providers. |
| `aiplugin.artificialAnalysisAPIKey` | the model ranking store | `""` | Plain (non-secure) storage (see Security). Gates whether the store is configured and can resolve ranks. |
| `aiplugin.artificialAnalysisRankCache` | the model ranking store | `[:]` | Per-model-id resolved-rank cache, persisted across launches. |
| adh catalog URL | the model catalog store | `"https://api.agenticdeveloperhub.com/persona/provider-templates?pageSize=100"` | Mutable process-wide value; capped at `pageSize=100`, does not paginate. |
| CLI binary search paths | the local CLI runner | `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude` (first executable wins) | Fixed list, not configurable by a caller. |
| CLI run timeout | caller | — (required) | Drives the terminate-on-timeout watchdog. |
| model ranking store fetch timeout | the model ranking store | `10` seconds | Not caller-configurable. |
| model catalog store fetch timeout | the model catalog store | `10` seconds | Not caller-configurable; applies to all three concurrent fetches. |
| local model metadata fetch timeout | caller, default `5` seconds | `5` seconds | |
| model page store fetch timeout | caller, default `8` seconds | `8` seconds | |
| model listing store fetch timeout | caller, default `8` seconds | `8` seconds | |

## Deep Linking

Not applicable: none of the 8 parts parse or construct app URL schemes or universal links; the only URLs built are outbound HTTP(S) request targets (Anthropic, OpenAI, Google, Artificial Analysis, OpenRouter, models.dev, the adh catalog endpoint, ollama.com, and a caller-supplied Ollama-native/OpenAI-compatible base URL).

## Localization

None of the 8 parts use a runtime string-table or localized-bundle lookup — every user-facing string below is a hardcoded English literal.

| Source | String(s) |
|--------|-----------|
| provider identity's display names | `"Claude Code CLI"`, `"Anthropic (Claude)"`, `"OpenAI (ChatGPT)"`, `"Google (Gemini)"`, `"Custom (OpenAI-compatible)"` |
| provider identity's recommendation notes | `"Uses your existing Claude Code login — no API key needed"`, `"Haiku 4.5 — fast and inexpensive (~$0.80/M input tokens)"`, `"GPT-4.1 Nano — cheapest OpenAI model (~$0.10/M input tokens)"`, `"Gemini 2.0 Flash — fast, free tier available"` |
| provider identity's API-key placeholders | `"sk-ant-..."`, `"sk-..."`, `"AIza..."`, `"API key"` |
| request error descriptions | `"Invalid server response"`, `"Custom base URL is required"`, `"This provider does not use HTTP requests"` |
| reply/error parsing fallbacks | `"(Unable to parse response)"`, `"(Empty response)"`, `"HTTP \(statusCode)"` |
| CLI error descriptions | `"Claude CLI not found (install Claude Code or check your PATH)"`, `"Failed to launch claude: \(message)"`, `"claude -p failed: ..."`, `"Empty reply from claude -p"` |

## Accessibility Options

Not applicable — this is non-UI logic with no rendering, so no dynamic type, VoiceOver, or reduced-motion accommodation applies.

## Feature Flags

Not applicable: no feature-flag or remote-config check appears in any of the 8 parts; the closest analog, the model ranking store's "is configured" check, gates behavior on stored API-key presence, not on a flag.

## Analytics

Not applicable: none of the 8 parts emit an analytics or telemetry event. Running the CLI sets an environment marker (`AGENTIC_TOOLKIT_HEADLESS=1`) that a downstream session-tracking hook uses to EXCLUDE, not record, the invocation.

## Privacy

**Data collected**: user-entered API keys for Anthropic, OpenAI/custom, Google, and the model ranking store (via the request configuration's API key / the ranking store's stored key); chat message and system-prompt content passed to the request builder and the CLI runner; model id strings passed to the catalog/matching functions.

**Storage**: the model ranking store's API key and rank cache persist via the plain settings store, not the secure credential store (see Security). The request configuration's API key/custom base URL are held only in memory by this component for the lifetime of one request; this component does not persist them itself. The model catalog store's and model ranking store's last-good/in-flight state is process-lifetime, in-memory only, and is lost on relaunch.

**Transmission**: prompt/message content is sent over HTTPS to whichever provider is configured (Anthropic, OpenAI, Google, or a `custom` OpenAI-compatible endpoint) or, for the CLI provider, is passed only as local subprocess input/arguments (no network). The Anthropic and model-ranking calls send the API key in an `x-api-key` header; the OpenAI-compatible calls send it in an `Authorization: Bearer` header; the Google call places it directly in the request URL's query string. The model catalog store, model page store, and model listing store send only model-id strings or scrape requests (no prompt content) to OpenRouter, models.dev, the adh endpoint, ollama.com, and the caller-supplied OpenAI-compatible `/models` route (which can carry a Bearer API key header — see Security for the missing scheme check on that route).

**Retention**: the rank cache and the model-ranking API key persist indefinitely until a caller overwrites or clears them; none of the 8 parts implement a TTL or expiry for that persisted data.

## Logging

Not applicable: none of the 8 parts call a logger of any kind — every failure is communicated only through a return value (no result / empty map / empty list) or a typed error, never logged.

## Platform Notes

- **Apple (SwiftUI / AppKit / UIKit)**: source of truth. All 8 types are Foundation-only (`URLSession`, `JSONSerialization`, `Process`/`Pipe`, `NSRegularExpression`), so the same code serves both AppKit (macOS) and UIKit (iOS) call sites unchanged. `AIProvider` is a `String`-backed `CaseIterable & Identifiable & Sendable` enum; `AIRequestConfig` is a plain, non-`Sendable` `struct` confined to its caller's isolation domain (current callers: `MiniChatViewModel`, `TerminalSessionSummarizer`, `WhippetSettingsViewModel`). `ArtificialAnalysisStore` and `ModelCatalogStore` are `@MainActor`-isolated for their stateful surface with `nonisolated` pure helpers; their persisted state is backed by `UserSetting`, and the model-ranking API key/cache are stored via `UserSetting` constructed WITHOUT `isSecure: true` — plain, non-Keychain storage, not the secure (Keychain-backed) provider this codebase also offers (see Security). `ClaudeCLI.run` drains `Process`/`Pipe` stdout/stderr concurrently via `async let`, waits for exit off Swift's concurrency cooperative thread pool via a background `DispatchQueue` inside a `withCheckedContinuation`, and writes to the child's `FileHandle` stdin inside a `do`/`catch`. `ModelCatalogStore`, `ArtificialAnalysisStore`, `LocalModelMetadataStore`, `OllamaModelPageStore`, and `OpenAIModelCatalog` use no `NSLocalizedString`, `Bundle` lookup, or String Catalog — every user-facing string is a hardcoded English literal. The one Apple-only surface with no cross-platform equivalent is `ClaudeCLI.findBinary()`'s hardcoded Unix install paths.
- **Jetpack Compose (Android/Kotlin)**: `AIProvider` maps to a `sealed class`/`enum class` with computed properties; `AIRequestBuilder` maps to per-provider `OkHttpClient`/`Retrofit` request builders; the join-or-start cache maps to a `Mutex`-guarded nullable `Deferred<Catalog>` on a singleton `object`, `await()`ed by joiners rather than re-triggering a fetch; `ClaudeCLI` maps to `ProcessBuilder` with concurrent `InputStream` draining on `Dispatchers.IO`.
- **React/Web (TypeScript)**: `AIProvider` maps to a string-literal union type; `fetch()` replaces `URLSession`; the join-or-start pattern maps to a module-level `Promise<Catalog> | null` that concurrent callers `await` instead of re-invoking the fetch; `ClaudeCLI` has no browser equivalent (no subprocess access) — a web host would need a server-side Node process (`child_process.spawn`) behind an API route.
- **WinUI 3 (C#/.NET)**: `AIProvider` maps to a `sealed record`/enum with switch-expression properties; `AIRequestBuilder` maps to `HttpClient` plus `System.Text.Json.JsonSerializer`; `ArtificialAnalysisStore`'s API key SHOULD map to `Windows.Security.Credentials.PasswordVault` (`PasswordCredential`) rather than reproducing this component's non-secure storage; `ClaudeCLI` maps to `System.Diagnostics.Process` with `RedirectStandardInput/Output/Error` and concurrent `Task.Run` reads; the join-or-start cache maps to a `SemaphoreSlim`-guarded nullable `Task<T>`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/AI/` |

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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
