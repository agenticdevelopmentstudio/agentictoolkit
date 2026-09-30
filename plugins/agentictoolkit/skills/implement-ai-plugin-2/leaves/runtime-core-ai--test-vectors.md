<!-- leaf: implement-ai-plugin-2/runtime-core-ai--test-vectors · source: ai-plugin-runtime-core-ai.md -->

# Core AI Runtime

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
