<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat--part-2 · source: ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat.md -->

# DaemonAIChat — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat--part-2#<slug>`):

- `namespace-only` MUST
- `plugin-runtime-injectable` MUST
- `plugin-runtime-live-load` MUST
- `plugin-runtime-live-run` MUST
- `cli-runner-type` MUST
- `cli-runner-live` MUST
- `chaterror-cases` MUST
- `chaterror-non-sendable` MUST
- `default-timeout-constant` MUST
- `plugin-path-selection` MUST
- `cli-path-default` MUST
- `guard-applicability` MUST
- `loopback-detection` MUST
- `guard-first-checkpoint` MUST
- `guard-exclusive-run` MUST
- `guard-recheck-in-lock` MUST
- `guard-second-checkpoint` MUST
- `guard-error-not-chaterror` MUST
- `guard-opt-out` MUST
- `concurrency-scope` MAY
- `cli-model-default` MUST
- `cli-error-mapping` MUST
- `cli-runner-success-passthrough` MUST
- `plugin-search-paths-order` MUST
- `plugin-load-error-passthrough` MUST
- `model-resolution-precedence` MUST
- `ledger-driven-values` MUST
- `secret-scope-by-template` MUST
- `keyless-template-no-phantom-secret` MUST
- `keyed-template-declares-empty-secret` MUST
- `model-key-injected-last` MUST
- `single-user-message` MUST
- `build-request-error-wrapping` MUST
- `stream-accumulation` MUST
- `stream-end-stops-consumption` MUST
- `stream-tooluse-ignored` MUST
- `stream-error-wrapping` MUST
- `empty-reply-guard` MUST
- `timeout-cli-path-only` MUST

## Behavioral Requirements

- **namespace-only**: `DaemonAIChat` MUST be a non-instantiable namespace — a `public enum` with no cases — exposing only static members and typealiases, since a Swift enum with no cases cannot be constructed.
- **plugin-runtime-injectable**: `PluginRuntime` MUST be a `Sendable` struct holding two `@Sendable` closures (`load`, `run`), so a caller MAY substitute a fake implementation for hermetic testing without touching disk, network, or a subprocess.
- **plugin-runtime-live-load**: `PluginRuntime.live.load` MUST resolve to `LivePluginCache.load(identifier:searchPaths:)`, hopping onto the main actor via `MainActor.run`, since `AIPluginManager` (which `LivePluginCache` wraps) is `@MainActor`-isolated.
- **plugin-runtime-live-run**: `PluginRuntime.live.run` MUST be exactly `PluginTransport.run`, so the plugin path streams events through the same transport the host's interactive chat backend uses.
- **cli-runner-type**: `CLIRunner` MUST be a `@Sendable` closure type accepting `(prompt, systemPrompt, model, timeout)` and asynchronously returning a `String` or throwing.
- **cli-runner-live**: `liveCLIRunner` MUST delegate to `ClaudeCLI.run(prompt:systemPrompt:model:timeout:)` with the same four arguments, unmodified.
- **chaterror-cases**: `ChatError` MUST expose exactly three cases — `claudeNotFound`, `providerError(String)`, `emptyReply` — each with a distinct, non-nil `errorDescription`.
- **chaterror-non-sendable**: `ChatError` MUST be treated as non-`Sendable` across a concurrency-domain boundary, since the type declares `Error, LocalizedError` conformance only, with no explicit `Sendable` conformance, regardless of its sole associated value (`String`) being itself `Sendable`.
- **default-timeout-constant**: `defaultTimeout` MUST equal `60` seconds and MUST be `complete`'s `timeout` parameter's default value.
- **plugin-path-selection**: `complete` MUST dispatch to the plugin path (`completeViaPlugin`) whenever `DaemonProviderResolver.selectedConfiguration(settings)` returns a non-nil `AIProviderConfiguration`.
- **cli-path-default**: `complete` MUST dispatch to `completeViaCLI` — passing `userPrompt` as `prompt`, plus `systemPrompt`, `cliModel`, and `timeout` unchanged — whenever no configuration is selected, and in that case MUST NOT call `runtime.load` or otherwise touch the plugin runtime.
- **guard-applicability**: the local-inference guard MUST be consulted for the plugin path if AND ONLY IF both `inferenceGuard` is non-nil AND `localBaseURL(config:settings:)` returns a non-nil loopback base URL for the selected configuration; a remote provider (a non-loopback `baseURL`) or a `nil` `inferenceGuard` MUST skip both guard checkpoints and call `completeViaPlugin` directly.
- **loopback-detection**: `localBaseURL(config:settings:)` MUST read the configuration's `baseURL` field via `AIProviderConfigKeys.fieldKey(config:field:"baseURL")`, trim whitespace and newlines, and return it only when non-empty AND `LocalModelServer.isLoopback(baseURL:)` is true; otherwise it MUST return `nil`.
- **guard-first-checkpoint**: when the guard applies, `complete` MUST verdict the configuration's STORED model (`DaemonProviderResolver.model(config:settings:)`, which is `""` when unset) BEFORE the plugin is loaded or any request is built, and MUST throw `AIGuardError.blocked` or `AIGuardError.deferred` immediately on a `.block`/`.deferred` verdict, without falling back to the CLI path.
- **guard-exclusive-run**: on a `.allow` verdict at the first checkpoint, `complete` MUST run `completeViaPlugin` inside `inferenceGuard.runExclusive { ... }`, so local inference is serialized process-wide against every other caller sharing the same `LocalInferenceGuard` instance.
- **guard-recheck-in-lock**: immediately after entering the exclusive section, `complete` MUST re-verdict pressure alone via `inferenceGuard.pressureVerdict()` and MUST throw `AIGuardError.deferred` when that re-check yields `.deferred`, before proceeding to `completeViaPlugin` — because the wait to acquire the lock MAY outlive the pre-park verdict.
- **guard-second-checkpoint**: inside `completeViaPlugin`, when the STORED model was empty (the descriptor's default will be used) AND the guard applies, the effective model (`descriptor.resolvedDefaultModel`) MUST be re-verdicted the moment it is known — BEFORE `plugin.buildRequest` is called — and a `.block`/`.deferred` verdict MUST throw before the request is built.
- **guard-error-not-chaterror**: `AIGuardError` MUST be thrown as its own type, never wrapped in or converted to `ChatError`, so a caller catching `ChatError` cannot mistake a guard refusal for a retryable transport failure.
- **guard-opt-out**: passing `inferenceGuard: nil` MUST disable both guard checkpoints unconditionally, even for a loopback configuration whose model would otherwise be blocked or deferred.
- **concurrency-scope**: `complete` itself carries no actor isolation — it is a plain `static func` on a non-actor `enum` and MAY be called concurrently from any task. The only serialization `DaemonAIChat` imposes is (a) the main-actor hop inside `PluginRuntime.live.load` (via `LivePluginCache`) and (b) the shared `LocalInferenceGuard.runExclusive` section for a loopback configuration when the guard applies; every other combination of concurrent calls (two remote-provider configs, two CLI-path calls, a CLI-path call concurrent with a plugin-path call) MAY execute fully in parallel with no ordering guarantee between them.
- **cli-model-default**: `completeViaCLI` MUST call `cliRunner` with `"haiku"` in place of `model` whenever the given `model` string is empty; a non-empty `cliModel` is forwarded unchanged.
- **cli-error-mapping**: `completeViaCLI` MUST map `ClaudeCLI.CLIError.binaryNotFound` to `ChatError.claudeNotFound`, `.emptyReply` to `ChatError.emptyReply`, `.launchFailed(message)` to `ChatError.providerError("Failed to launch claude: \(message)")`, and `.nonZeroExit(code, stderr)` to `ChatError.providerError` carrying `stderr` (or `"exit \(code)"` when `stderr` is empty), truncated to its first 200 characters.
- **cli-runner-success-passthrough**: on success, `completeViaCLI` MUST return `cliRunner`'s result unmodified as the final reply.
- **plugin-search-paths-order**: `pluginSearchPaths()` MUST return, in order, the executable-relative `../PlugIns` directory (derived from `CommandLine.arguments.first`, standardized, included only when that first argument is non-empty) followed unconditionally by `~/.agenticplugins`.
- **plugin-load-error-passthrough**: `completeViaPlugin` MUST rethrow a `ChatError` thrown by `runtime.load` unchanged, and MUST wrap any other thrown error as `ChatError.providerError("Failed to load AI plugin '\(pluginId)': \(error.localizedDescription)")`.
- **model-resolution-precedence**: the effective `model` MUST be the configuration's stored model (`DaemonProviderResolver.model`) when non-empty, else `descriptor.resolvedDefaultModel`.
- **ledger-driven-values**: `completeViaPlugin` MUST rebuild the forwarded `AIPluginConfig` values from the host's non-secret fields ledger (`AIProviderConfigKeys.fieldsKey`, newline-split) and each field's stored value (`AIProviderConfigKeys.fieldKey`), NOT by re-deriving keys from `descriptor.fields`, so a template-level default beyond `baseURL`/`authMode` survives the headless path.
- **secret-scope-by-template**: secret values MUST be resolved only for the fields of the configuration's OWN template — `descriptor.resolvedTemplates.first { $0.id == config.templateId }` mapped through `descriptor.fields(for:)` — falling back to the full `descriptor.fields` union only when the configuration's `templateId` no longer resolves to any template.
- **keyless-template-no-phantom-secret**: a template whose resolved fields do not declare a given secret key (e.g. a keyless template overriding `fields` to omit `apiKey`) MUST leave that key ABSENT from the forwarded `AIPluginConfig.values` (`config.apiKey == nil`), never synthesize an empty string for it.
- **keyed-template-declares-empty-secret**: a template whose resolved fields DO declare a secret key MUST result in that key being present in `values`, set to `secretStore.get(forKey:) ?? ""`, even when no value is stored (`config.apiKey == ""`), distinguishing "declared but blank" from "not declared".
- **model-key-injected-last**: `completeViaPlugin` MUST set `values["model"]` to the resolved effective model AFTER populating ledger and secret values, so it is authoritative over any same-named descriptor field.
- **single-user-message**: `completeViaPlugin` MUST construct `AIChatContext.messages` as exactly one `AIChatMessage` with `role: .user` and `content: userPrompt`; the parameter list carries no prior conversation turns.
- **build-request-error-wrapping**: a `buildRequest(_:)` throw MUST be wrapped as `ChatError.providerError("Plugin could not build the request: \(error.localizedDescription)")`.
- **stream-accumulation**: `completeViaPlugin` MUST accumulate every `.textDelta(text)` event's `text` by string concatenation, in event order, into the returned reply.
- **stream-end-stops-consumption**: a `.end` event MUST terminate stream consumption immediately, regardless of `stopReason`, without treating any `stopReason` value as an error.
- **stream-tooluse-ignored**: a `.toolUse` event MUST be ignored (no side effect, no error), since a one-shot completion request declares no tools.
- **stream-error-wrapping**: any error thrown while consuming `runtime.run`'s stream MUST be wrapped as `ChatError.providerError(error.localizedDescription)`.
- **empty-reply-guard**: after streaming completes, `completeViaPlugin` MUST throw `ChatError.emptyReply` when the accumulated reply is empty or all-whitespace after trimming, and MUST NOT return that blank/whitespace string.
- **timeout-cli-path-only**: `complete`'s `timeout` parameter MUST govern only the CLI path's subprocess wait (forwarded verbatim into `completeViaCLI`); it MUST NOT be forwarded into `completeViaPlugin`, whose own per-request budget is the plugin-supplied `AIRequestSpec.timeout` and whose lock-hold budget is `LocalInferenceGuard.runExclusive`'s own deadline.
