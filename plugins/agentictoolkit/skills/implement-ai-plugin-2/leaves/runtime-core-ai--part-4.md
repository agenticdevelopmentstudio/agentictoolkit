<!-- leaf: implement-ai-plugin-2/runtime-core-ai--part-4 · source: ai-plugin-runtime-core-ai.md -->

# Core AI Runtime — continued (part 4)

**Rules** (cite as `implement-ai-plugin-2/runtime-core-ai--part-4#<slug>`):

- `winui-3` SHOULD — AIProvider maps to a sealed record/enum with switch-expression properties; AIRequestBuilder maps to HttpClient plus …

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

## Privacy

**Data collected**: user-entered API keys for Anthropic, OpenAI/custom, Google, and Artificial Analysis (via `AIRequestConfig.apiKey` / `ArtificialAnalysisStore.apiKey`); chat message and system-prompt content passed to `AIRequestBuilder`/`ClaudeCLI`; model id strings passed to the catalog/matching functions.

**Storage**: `ArtificialAnalysisStore.apiKey` and `.rankCache` persist via `UserSetting` constructed without `isSecure: true` — plain, non-Keychain storage (see Security). `AIRequestConfig.apiKey`/`.customBaseURL` are held only in memory by this component for the lifetime of one request; this component does not persist them itself. `ModelCatalogStore`'s `lastGood`/`inflight` and `ArtificialAnalysisStore`'s `lastGood`/`inflight` are process-lifetime, in-memory only, and are lost on relaunch.

**Transmission**: prompt/message content is sent over HTTPS to whichever provider `AIRequestConfig.provider` selects (Anthropic, OpenAI, Google, or a `.custom` OpenAI-compatible endpoint) or, for `.claudeCLI`, is passed only as local subprocess stdin/args to `claude -p` (no network). The Anthropic and Artificial Analysis calls send the API key in an `x-api-key` header; the OpenAI-compatible calls send it in an `Authorization: Bearer` header; the Google call places it directly in the request URL's query string. `ModelCatalogStore`, `OllamaModelPageStore`, and `OpenAIModelCatalog` send only model-id strings or scrape requests (no prompt content) to OpenRouter, models.dev, the adh endpoint, ollama.com, and the caller-supplied OpenAI-compatible `/models` route (which can carry a Bearer API key header — see Security for the missing scheme check on that route).

**Retention**: `rankCache` and the Artificial Analysis API key persist indefinitely in `UserSetting` storage until a caller overwrites or clears them; none of the 8 files implement a TTL or expiry for that persisted data.

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
