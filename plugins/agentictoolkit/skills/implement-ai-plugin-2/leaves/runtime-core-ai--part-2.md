<!-- leaf: implement-ai-plugin-2/runtime-core-ai--part-2 · source: ai-plugin-runtime-core-ai.md -->

# Core AI Runtime — continued (part 2)

**Rules** (cite as `implement-ai-plugin-2/runtime-core-ai--part-2#<slug>`):

- `provider-identity` MUST
- `provider-display-metadata` MUST
- `provider-cli-flag` MUST
- `provider-sendable` MUST
- `request-config-shape` MUST
- `request-config-isolation` MUST
- `request-dispatch-by-provider` MUST
- `request-custom-requires-base-url` MUST
- `request-cli-provider-throws` MUST
- `anthropic-request-shape` MUST
- `openai-compatible-request-shape` MUST
- `openai-compatible-missing-url-throws` MUST
- `google-request-shape` MUST
- `reply-parsing-by-provider` MUST
- `reply-parsing-empty-fallback` MUST
- `error-message-extraction` MUST
- `request-builder-statelessness` MAY
- `rank-store-isolation` MUST
- `rank-model-shape` MUST
- `rank-requires-api-key` MUST
- `rank-join-or-start` MUST
- `rank-last-good-fallback` MUST
- `rank-per-model-persistence` MUST
- `rank-matching-reuse` MUST
- `rank-fetch-parse-purity` MUST
- `rank-fetch-degrades-to-nil` MUST
- `cli-binary-search-order` MUST
- `cli-binary-missing-throws` MUST
- `cli-argument-shape` MUST
- `cli-path-augmentation` MUST
- `cli-headless-marker` MUST
- `cli-launch-failure` MUST
- `cli-stdin-write-non-fatal` MUST
- `cli-concurrent-drain` MUST
- `cli-wait-off-cooperative-pool` MUST
- `cli-timeout-terminates` MUST
- `cli-nonzero-exit-throws` MUST
- `cli-empty-reply-throws` MUST
- `cli-error-sendable` MUST

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

