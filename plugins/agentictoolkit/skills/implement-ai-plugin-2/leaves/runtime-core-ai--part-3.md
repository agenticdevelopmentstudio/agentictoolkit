<!-- leaf: implement-ai-plugin-2/runtime-core-ai--part-3 · source: ai-plugin-runtime-core-ai.md -->

# Core AI Runtime — continued (part 3)

**Rules** (cite as `implement-ai-plugin-2/runtime-core-ai--part-3#<slug>`):

- `catalog-store-isolation` MUST
- `catalog-shape` MUST
- `catalog-join-or-start` MUST
- `catalog-concurrent-fetch` MUST
- `catalog-per-side-fallback` MUST
- `catalog-description-priority` MUST
- `catalog-adh-url-mutable` MUST
- `openrouter-parse-skips-empty` MUST
- `modelsdev-parse-first-provider-wins` MUST
- `adh-parse-skips-empty` MUST
- `best-match-prefix-anchored` MUST
- `best-match-size-restriction` MUST
- `best-match-shortest-wins` MUST
- `best-match-latest-retry` MUST
- `best-match-degenerate-inputs` MUST
- `substantiality-threshold` MUST
- `catalog-fetch-degrades-to-nil` MUST
- `ollama-metadata-shape` MUST
- `loopback-detection` MUST
- `native-base-derivation` MUST
- `show-parse-requires-signal` MUST
- `show-parse-context-length-key` MUST
- `metadata-fetch-degrades-to-nil` MUST
- `page-info-shape` MUST
- `page-url-routing` MUST
- `page-url-rejects-malformed` MUST
- `description-parse-priority` MUST
- `stats-parse-independent-fields` MUST
- `page-fetch-degrades-to-nil` MUST
- `catalog-fetch-shape` MUST
- `catalog-fetch-degrades-to-empty` MUST
- `catalog-parse-shape` MUST
- `api-key-in-memory-only-scope` MUST
- `artificial-analysis-key-storage` MUST
- `google-key-in-url` MUST

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

