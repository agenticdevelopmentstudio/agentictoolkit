---
id: 4d7ed9a3-c6d8-491b-911a-cf257fde1c38
title: DaemonAIChat
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Headless one-shot completion entry point that resolves the host's selected
  AI provider, dispatches to its .aiplugin (gated by a local-inference RAM guard for
  loopback models) or falls back to a zero-config claude -p CLI call, and returns
  one accumulated reply string.
platforms:
- swift
- macos
tags:
- ai-plugin
- ai-plugin-runtime
- daemon
- headless-completion
- inference-guard
- cli-fallback
depends-on:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-request-spec
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-stream-event
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-configuration
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-daemon-provider-resolver
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-inference-guard
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager
references: []
approved-by: ''
approved-date: ''
---

# DaemonAIChat

## Overview

`DaemonAIChat.swift` (`packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift`) defines `DaemonAIChat`, a non-instantiable namespace whose single entry point, `complete(systemPrompt:userPrompt:maxTokens:cliModel:timeout:settings:runtime:cliRunner:secretStore:inferenceGuard:)`, is a headless host's reusable "ask the model one question" path — used by any daemon feature that needs a one-shot completion (session summaries, AI oversight, and similar) so every caller drives the exact same runtime rather than duplicating it.

`complete` chooses between two paths using the config-UUID-keyed registry the app syncs over `AIProviderConfigSync` and reads back through `DaemonProviderResolver`:

- **Plugin path** (a configuration is selected): loads that configuration's `.aiplugin` bundle, asks it to *describe* the request as an `AIRequestSpec`, and drives it through `PluginTransport` — the same runtime the host's interactive chat backend uses. The model comes from the configuration's own stored value, falling back to the plugin descriptor's default.
- **CLI default** (no configuration selected): a `claude -p` subprocess via `ClaudeCLI` — a zero-config path that needs no API key, so daemon features work before any provider has been configured.

When the plugin path's configuration points at a loopback model server (e.g. a local Ollama instance), `complete` additionally consults an injectable `LocalInferenceGuard` at two points — before the plugin loads (verdicting the configuration's *stored* model) and again inside the plugin path (verdicting the *effective* model, once the descriptor's default is known) — to refuse or defer a local model load that would exceed a RAM budget, and serializes allowed local completions process-wide so two host features cannot trigger two model loads at once. Remote providers and the CLI path bypass the guard entirely; passing `inferenceGuard: nil` opts out unconditionally.

Every collaborator `complete` touches — `runtime` (plugin load + run), `cliRunner` (the CLI subprocess), `settings` (the provider-registry reader), and `secretStore` (Keychain-backed secret lookup) — is an injectable parameter with a production default, so the two dispatch paths, the guard's two checkpoints, and the template-scoped secret-resolution logic can all be exercised hermetically in `DaemonAIChatTests.swift` and `DaemonAIChatGuardTests.swift` without a real bundle, network call, subprocess, or Keychain entry.

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
- **cache-main-actor-isolated**: `LivePluginCache` MUST be a `@MainActor`-isolated private enum whose mutable static state (`manager`, `managerPaths`, `loaded`) is safe to mutate without a separate lock, because the main actor serializes all access to it.
- **cache-reuse-by-search-paths**: `LivePluginCache.load` MUST reuse the cached `AIPluginManager` when the given `searchPaths` equals the previously cached `managerPaths`; otherwise it MUST construct a new `AIPluginManager`, call `discoverPlugins()`, replace the cached manager and paths, and clear every previously loaded plugin instance.
- **cache-unknown-identifier**: `LivePluginCache.load` MUST throw `ChatError.providerError("AI plugin not installed: \(identifier)")` when `mgr.descriptor(for: identifier)` is `nil`.
- **cache-instance-reuse**: `LivePluginCache.load` MUST return an already-cached plugin instance for `identifier` without calling `mgr.loadPlugin(identifier:)` again; otherwise it MUST call `loadPlugin`, cache the result, and return it.
- **cli-foreign-error-passthrough**: An error other than `ClaudeCLI.CLIError` thrown by an injected `cliRunner` MUST propagate out of `completeViaCLI` and `complete` unchanged, not wrapped as a `ChatError`; unlike `completeViaPlugin`, whose generic `catch` clauses wrap every failure as `ChatError.providerError`, the CLI path catches only `ClaudeCLI.CLIError`. `CLIRunner`'s doc comment names `ClaudeCLI.CLIError` as the only error a runner throws.

## Appearance

Not applicable — this is a headless one-shot AI-completion orchestrator, not a visual component.

## States

Not applicable — this is a headless one-shot AI-completion orchestrator, not a visual component.

## Accessibility

Not applicable — this is a headless one-shot AI-completion orchestrator, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| daemon-ai-chat-001 | plugin-path-selection, ledger-driven-values, secret-scope-by-template, keyed-template-declares-empty-secret, single-user-message, stream-accumulation, model-resolution-precedence | A selected configuration with `baseURL: "https://api.example/v1"` in the ledger and `apiKey: "sk-secret-123"` in the secret store; no stored model; a plugin runtime emitting `.textDelta("Hello "), .textDelta("world"), .end(stopReason: nil)` (`DaemonAIChatTests.swift`, `pluginPathResolvesConfigAndAccumulatesStream`) | Returns `"Hello world"`; the built `AIChatContext` has `maxTokens == 64`, `systemPrompt == "sys"`, `model == "fake-small"` (the descriptor default), `config.apiKey == "sk-secret-123"`, `config.baseURL == "https://api.example/v1"`, and exactly one `.user` message with content `"user question"` |
| daemon-ai-chat-002 | model-resolution-precedence | A selected configuration with stored model `"fake-large"` | The built context's `model` and `config.model` both equal `"fake-large"`, overriding the descriptor default |
| daemon-ai-chat-003 | ledger-driven-values | A selected configuration whose ledger includes `apiVersion: "2026-01-01"`, a key not declared by the descriptor's fields | `context.config["apiVersion"] == "2026-01-01"` — an arbitrary ledger value survives even though no descriptor field declares it |
| daemon-ai-chat-004 | empty-reply-guard | A plugin runtime emitting only `.end(stopReason: nil)` (no `.textDelta`) | `complete` throws `ChatError.emptyReply`, never returns an empty string |
| daemon-ai-chat-005 | stream-error-wrapping | A plugin runtime whose stream throws `FakeError.boom` | `complete` throws `ChatError.providerError` whose message contains `"boom"` |
| daemon-ai-chat-006 | secret-scope-by-template, keyless-template-no-phantom-secret | A configuration bound to the keyless `"ollama"` template (its resolved fields omit `apiKey`); no `apiKey` stored in the secret store (`templatedDescriptor()`, `pluginPathKeylessTemplateOmitsPhantomSecret`) | `context.config.apiKey == nil` (not `""`); `context.config.baseURL == "http://localhost:11434/v1"` |
| daemon-ai-chat-007 | secret-scope-by-template, keyed-template-declares-empty-secret | A configuration bound to the keyed `"api-key"` template (`fields: nil`, inherits `apiKey`); no value stored for that secret (`pluginPathKeyedTemplateDeclaresEmptySecret`) | `context.config.apiKey == ""` (declared but blank), distinguishing it from the keyless case's `nil` |
| daemon-ai-chat-008 | cli-path-default, cli-model-default, plugin-load-error-passthrough | No configuration selected; `runtime` is a fake that fails the test if `load` is ever called; `cliRunner` records its arguments and returns `"answer"` | Returns `"answer"`; the CLI runner is invoked with `model == "haiku"`, `systemPrompt == "sys"`, `prompt == "question"`; the plugin runtime's `load` is never invoked |
| daemon-ai-chat-009 | cli-error-mapping | No configuration selected; `cliRunner` throws `ClaudeCLI.CLIError.binaryNotFound` | `complete` throws `ChatError.claudeNotFound` |
| daemon-ai-chat-010 | cli-error-mapping | No configuration selected; `cliRunner` throws `ClaudeCLI.CLIError.emptyReply` | `complete` throws `ChatError.emptyReply` |
| daemon-ai-chat-011 | cli-error-mapping | No configuration selected; `cliRunner` throws `ClaudeCLI.CLIError.nonZeroExit(code: 2, stderr: "model unavailable")` | `complete` throws `ChatError.providerError` whose message contains `"model unavailable"` |
| daemon-ai-chat-012 | plugin-search-paths-order | Call `DaemonAIChat.pluginSearchPaths()` | The returned array contains `~/.agenticplugins` as a file URL; every returned URL is a file URL (`pluginSearchPathsIncludeHomeAgenticplugins`) |
| daemon-ai-chat-013 | guard-first-checkpoint | A loopback configuration with stored model `"big:latest"` (its on-disk size exceeds the fixed test RAM budget); guard pressure `.normal` (`blockedModelThrowsBeforeTransport`) | `complete` throws `AIGuardError`; the fake plugin runtime's `load`/`run` are never invoked (the fake fails the test if they are) |
| daemon-ai-chat-014 | guard-first-checkpoint | A loopback configuration with stored model `"small:latest"`; guard pressure `.warning` (`pressureDefersSmallModel`) | `complete` throws `AIGuardError.deferred`, even though the model's own size would otherwise be allowed under `.normal` pressure |
| daemon-ai-chat-015 | guard-exclusive-run | A loopback configuration with stored model `"small:latest"`; guard pressure `.normal`; a plugin runtime emitting `.textDelta("ok"), .end(stopReason: nil)` (`allowedLocalModelCompletes`) | Returns `"ok"` — an allowed local model completes through the plugin path |
| daemon-ai-chat-016 | guard-applicability | A configuration with `baseURL: "https://api.example/v1"` (non-loopback) and stored model `"big:latest"`; guard pressure `.critical` (`remoteProviderBypassesGuard`) | Returns `"remote ok"` — a remote provider bypasses the guard even under critical pressure |
| daemon-ai-chat-017 | guard-second-checkpoint | A loopback configuration with NO stored model (`""`); the loaded descriptor's `defaultModel` is `"big:latest"` (over budget); guard pressure `.normal` (`emptyStoredModelVerdictsResolvedDefault`) | `complete` throws `AIGuardError.blocked` whose reason names `"big:latest"` (the EFFECTIVE model, not the empty stored one); `runtime.run` is never invoked; `context` is never built |
| daemon-ai-chat-018 | guard-recheck-in-lock | A loopback configuration with stored model `"small:latest"` under `.normal` pressure; a second task holds the guard's exclusive section while pressure is raised to `.critical` before releasing it (`pressureRecheckInsideCriticalSectionDefers`) | The parked `complete` call — whose pre-park verdict already passed under `.normal` — throws `AIGuardError.deferred` once it enters the critical section and the in-lock pressure re-check runs |
| daemon-ai-chat-019 | guard-opt-out | A loopback configuration with stored model `"big:latest"` (over budget) but `inferenceGuard: nil`; a plugin runtime emitting `.textDelta("unguarded"), .end(stopReason: nil)` (`nilGuardOptsOut`) | Returns `"unguarded"` — the guard is skipped entirely despite a model that would otherwise be blocked |
| daemon-ai-chat-020 | guard-error-not-chaterror | Any of vectors 013, 014, 017, or 018 | The thrown value in every case is `AIGuardError`, never `DaemonAIChat.ChatError` — a caller pattern-matching on `ChatError` alone does not catch a guard refusal |

## Edge Cases

- **Empty/blank prompts**: an empty `userPrompt` or `systemPrompt` MUST be passed through unvalidated to the plugin's `buildRequest(_:)` (or, on the CLI path, to `cliRunner`/`claude -p` itself); `DaemonAIChat.swift` performs no non-emptiness check of its own (see `single-user-message`).
- **Empty ledger**: an empty or absent non-secret fields ledger (`AIProviderConfigKeys.fieldsKey` missing or `""`) MUST result in `values` containing only the injected `"model"` key — no ledger-derived field is forwarded (`ledger-driven-values`).
- **Malformed/absent registry**: a missing or non-JSON provider-configuration registry MUST make `DaemonProviderResolver.selectedConfiguration` return `nil`, so `complete` MUST take the CLI-default path; `DaemonAIChat.swift` performs no validation or error reporting of the registry itself.
- **Boundary `maxTokens`**: `0` or a negative `maxTokens` MUST be forwarded to `AIChatContext.maxTokens`/`plugin.buildRequest(_:)` unchanged and unvalidated; any rejection of an out-of-range value is the plugin's or provider's concern, not this file's.
- **Boundary `timeout`**: a `0` (or very small) `timeout` MUST still be forwarded verbatim to `cliRunner`/`ClaudeCLI.run` on the CLI path; `completeViaPlugin` ignores this parameter entirely (`timeout-cli-path-only`).
- **Concurrent access, same loopback configuration**: two concurrent `complete` calls for the SAME loopback configuration, each passing a shared `inferenceGuard`, MUST be serialized FIFO by that guard so at most one is inside `completeViaPlugin` at a time (`guard-exclusive-run`); a concurrent call that instead passes `inferenceGuard: nil` MUST NOT be serialized against the others.
- **Concurrent access, unguarded paths**: two concurrent `complete` calls for two remote-provider configurations, two CLI-path calls, or a CLI-path call concurrent with a plugin-path call MAY run fully in parallel with no ordering guarantee (`concurrency-scope`).
- **Guard refusal at either checkpoint**: `AIGuardError.blocked`/`.deferred` from the first (pre-load) or second (post-descriptor-resolution) checkpoint MUST abort before the plugin's `buildRequest`/transport ever runs (`guard-first-checkpoint`, `guard-second-checkpoint`); the CLI path is never used as a fallback for a guard refusal.
- **Plugin load failure**: an unknown plugin identifier, a bundle-load failure, or any other `runtime.load` throw MUST surface as `ChatError.providerError` (or an already-typed `ChatError` passed through unchanged) — never an unhandled crash (`plugin-load-error-passthrough`).
- **`buildRequest` failure**: a plugin's `buildRequest(_:)` throwing (e.g. because the resolved config is insufficient) MUST surface as `ChatError.providerError` naming the underlying error (`build-request-error-wrapping`).
- **Transport/stream failure**: any error thrown while consuming `runtime.run`'s stream MUST surface as `ChatError.providerError` carrying that error's `localizedDescription` (`stream-error-wrapping`).
- **CLI failure taxonomy**: all four `ClaudeCLI.CLIError` cases MUST map to a specific, distinct `ChatError` per `cli-error-mapping`; no fifth CLI failure shape is defined by `ClaudeCLI.CLIError` itself.
- **Non-`ClaudeCLI.CLIError` from an injected `cliRunner`**: propagates unchanged, unwrapped — see `cli-foreign-error-passthrough`.
- **Offline/disconnected state**: for the plugin path, `DaemonAIChat.swift` performs no direct connectivity check of its own; an unreachable host surfaces only as whatever `PluginTransport.run` throws, uniformly wrapped by `stream-error-wrapping`. For the CLI path, `ClaudeCLI.run` spawns a local subprocess with no network call originating in this file directly; if `claude -p`'s own backend call fails due to connectivity, that most likely surfaces as a `.nonZeroExit`, mapped like any other CLI failure — this file cannot and does not distinguish "offline" from any other non-zero exit or launch failure.
- **Cancellation**: cancelling the calling `Task` while parked on `LocalInferenceGuard`'s FIFO queue (`guard-exclusive-run`) MUST cause the guard's `acquire()` to throw `CancellationError` — a third error shape, neither `ChatError` nor `AIGuardError` — which `complete` does not catch or rewrap, so it propagates to the caller as-is; this is `LocalInferenceGuard`'s own documented behavior, inherited unmodified here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `systemPrompt` | `String` | none — required | System prompt text for this one-shot turn |
| `userPrompt` | `String` | none — required | The single user message's text |
| `maxTokens` | `Int` | none — required | Forwarded unvalidated into `AIChatContext.maxTokens` on the plugin path; unused on the CLI path |
| `cliModel` | `String` | `"haiku"` | Model name for the CLI path only; an empty string is also treated as `"haiku"` by `completeViaCLI` |
| `timeout` | `TimeInterval` | `defaultTimeout` (`60`) | Governs only `completeViaCLI`'s subprocess wait; ignored on the plugin path |
| `settings` | `ProviderSettingsReader` (`@escaping (String) -> String?`) | none — required | Reads the host's synced provider-registry values, keyed by `AIProviderConfigKeys` |
| `runtime` | `PluginRuntime` | `.live` | Injectable plugin-load/run seam |
| `cliRunner` | `CLIRunner` | `liveCLIRunner` | Injectable CLI-subprocess seam |
| `secretStore` | `any SecretStoring` | `KeychainSecretStore()` | Source of a template's secret field values |
| `inferenceGuard` | `LocalInferenceGuard?` | `.shared` | The local-inference RAM guard; `nil` disables both checkpoints |

`AIProviderConfigKeys`-namespaced settings keys `complete` (via `DaemonProviderResolver` and `completeViaPlugin`) reads through `settings`: the configurations registry, the selected-configuration id, a configuration's stored model, its non-secret fields ledger, and each ledger field's stored value.

## Deep Linking

Not applicable: `DaemonAIChat.swift` defines no URL scheme, route, or navigation destination.

## Localization

No message in this file is externalized through a localization key (no `NSLocalizedString`/`String(localized:)`). Every user-facing string this file itself authors is a hardcoded English literal:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Claude CLI not found (install Claude Code or check PATH)` | `ChatError.claudeNotFound.errorDescription` |
| (none — hardcoded) | `Empty reply from the model` | `ChatError.emptyReply.errorDescription` |
| (none — hardcoded) | `Failed to launch claude: <message>` | `completeViaCLI`'s `.launchFailed` mapping |
| (none — hardcoded) | `claude -p failed: <stderr or "exit <code>", truncated to 200 chars>` | `completeViaCLI`'s `.nonZeroExit` mapping |
| (none — hardcoded) | `Failed to load AI plugin '<id>': <underlying message>` | `completeViaPlugin`'s plugin-load error wrap |
| (none — hardcoded) | `Plugin could not build the request: <underlying message>` | `completeViaPlugin`'s `buildRequest` error wrap |
| (none — hardcoded) | `AI plugin not installed: <identifier>` | `LivePluginCache.load`'s unknown-identifier error |

`ChatError.providerError`'s remaining call site (the stream-consumption wrap) carries a plugin/transport-supplied `error.localizedDescription` through verbatim rather than authoring new text — that upstream string's own localization is out of this file's control.

## Accessibility Options

Not applicable: this is a non-UI logic component with no visible surface, so it consults none of the system accessibility display options (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: `DaemonAIChat.swift` reads no feature-flag key and gates none of its behavior behind one; its two-path dispatch is driven entirely by whether a provider configuration is selected, not by a flag.

## Analytics

Not applicable: `DaemonAIChat.swift` emits no analytics or event-tracking call.

## Privacy

- **Data handled**: `completeViaPlugin` reads the host's non-secret settings ledger and, for the configuration's own resolved template, its declared secret fields (e.g. `apiKey`) via the injected `secretStore`. `DaemonAIChat.swift` does not decide what is sensitive — it forwards exactly what the ledger and secret store report, scoped by `AIProviderConfigKeys` and `secret-scope-by-template`.
- **Storage**: `DaemonAIChat.swift` stores nothing itself. It reads through `settings` (a plain key/value reader) and `secretStore.get(forKey:)` (Keychain-backed by default, via `KeychainSecretStore`) and writes nothing back; the prompt text and the accumulated reply exist only as local variables for the duration of one `complete` call, with no persistence of either.
- **Transmission**: resolved values, including a secret, are packaged into `AIPluginConfig.values` → `AIChatContext.config` → `plugin.buildRequest(_:)`, which MAY embed a secret (e.g. as an `Authorization` header) into the returned `AIRequestSpec`; the actual wire transmission happens inside `PluginTransport.run`, not in this file. On the CLI path, `systemPrompt`/`userPrompt` are passed to `ClaudeCLI.run`, which spawns a local subprocess — no network call originates directly in `DaemonAIChat.swift` for that path, though `claude -p` may itself reach a remote API.
- **Retention**: `DaemonAIChat.swift` defines no retention, expiry, rotation, or revocation policy for any credential; whatever `secretStore.get(forKey:)` returns reflects the caller-supplied store's own retention. This file has no violation-detection logic of its own — a plugin-level authentication failure (e.g. an HTTP 401) surfaces only generically, as a `ChatError.providerError` carrying whatever message the plugin's `describeError` or `PluginTransport`'s own generic HTTP-status message supplies, with no distinct handling for a credential problem versus any other provider error.

## Logging

Not applicable: `DaemonAIChat.swift` contains no logging call (no `Logger`/`os` import); it is Foundation-plus-`AgenticToolkitCore` orchestration with no logging side effects of its own.

## Platform Notes

- **SwiftUI**: The source, `packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift`, has no view-layer dependency at all — `complete` is a plain `static func` a SwiftUI (or any other) host calls from a `Task`, typically wrapping the call in a view model that publishes the in-flight/succeeded/failed state, since `DaemonAIChat` itself is not observable and returns only a final `String` (no partial-progress callback).
- **Compose**: model the two-path dispatch as a `suspend fun complete(...)` in a plain Kotlin object, with `PluginRuntime` and `CLIRunner` as constructor-injected function types (or a small interface each) for the same hermetic-testing seam. Android has no `dlopen`/`NSPrincipalClass` equivalent for the plugin path itself (see the `ai-plugin-manager` recipe's Compose note); the guard's actor-based mutual exclusion maps to a `Mutex` (kotlinx.coroutines) guarding the local-inference critical section, and the FIFO recheck-after-acquire pattern (`guard-recheck-in-lock`) carries over directly since `Mutex.withLock` also has to reconsider state that may have changed while suspended waiting for the lock.
- **React/Web**: model `complete` as an `async function` returning `Promise<string>`, with `runtime`/`cliRunner`/`settings`/`secretStore` as injected parameters or closures for the same test seams. There is no local subprocess (`claude -p`) equivalent in a browser; a web port's "zero-config default" would more plausibly be a server-side proxy endpoint than an in-process CLI fallback. The local-inference guard's process-wide mutual exclusion has no direct browser analogue (there is one JS execution context per tab); a multi-tab web host would need a `BroadcastChannel`- or server-mediated equivalent of `LocalInferenceGuard.runExclusive` to serialize local-model calls across tabs.
- **AppKit / UIKit**: same note as SwiftUI — `DaemonAIChat.swift` has no AppKit/UIKit dependency; only the host embedding it differs. The `.aiplugin` bundle-loading path this file drives is macOS-only (see the `ai-plugin-manager` and `ai-plugin` recipes), which is why this recipe's `platforms` list `macos` and not `ios`; an iOS host could still use the CLI-independent plugin path if a plugin bundle-loading mechanism were ported, but never the `claude -p` subprocess fallback, since iOS sandboxes forbid spawning arbitrary subprocesses.
- **WinUI 3**: model `complete` as an `async Task<string>` on a static class, with `PluginRuntime` (a record of two delegates) and `CLIRunner` as injected dependencies. `ClaudeCLI`'s subprocess fallback maps to `System.Diagnostics.Process`; `AssemblyLoadContext` is the nearest analogue for the plugin-loading half of the plugin path (see the `ai-plugin-manager` recipe's WinUI 3 note for the caching tradeoff this implies). The two-checkpoint local-inference guard maps to a `SemaphoreSlim`(1) guarding the critical section, with the same "re-check pressure after acquiring" pattern; `Windows.Storage`/Credential Locker stands in for the Keychain-backed `SecretStoring` this file reads through. Because `System.Diagnostics.Process` and `HttpClient` calls are both naturally `async`/awaitable on .NET, a WinUI 3 port has no equivalent of Swift's `AsyncThrowingStream`-based event consumption for `PluginRuntime.run`; `IAsyncEnumerable<AiStreamEvent>` is the direct substitute, with the `.end`/`.toolUse`/`.textDelta` switch in `completeViaPlugin` carrying over as a `switch` over an enum/discriminated union inside an `await foreach`.

## Design Decisions

**Decision**: `complete` dispatches to `completeViaCLI` (a zero-config `claude -p` fallback) whenever no provider configuration is selected, rather than throwing a "not configured" error.
**Rationale**: the source's own doc comment states the CLI default "needs no API key, so it works before any provider is configured" — this lets a daemon feature call `complete` unconditionally, without special-casing the "user hasn't opened Settings yet" state.
**Approved**: pending

**Decision**: the local-inference guard is consulted twice — once against the configuration's STORED model before the plugin loads, and again against the EFFECTIVE (descriptor-default-resolved) model inside `completeViaPlugin`, immediately before the request is built.
**Rationale**: the stored model can be empty (meaning "use the plugin's own default"), which is only known once the plugin's descriptor has been loaded; a single early check against an empty string could pass a request whose real model is large enough to be refused, so the source adds a second checkpoint that re-verdicts the model that will actually run, per its own doc comment on `complete`.
**Approved**: pending

**Decision**: secret resolution scopes to the configuration's own resolved template's fields, not the plugin descriptor's full field union.
**Rationale**: the source's inline comment records that listing `descriptor.fields` (rather than the template's own fields) previously synthesized a phantom empty `apiKey` for a keyless template such as Ollama, which made `OpenAICompatiblePlugin` reject the request with "An API key is required" — breaking every daemon summarize/oversight call for that provider until the template-scoped fix.
**Approved**: pending

**Decision**: `LivePluginCache` retains a loaded `AIPlugin` instance and its owning `AIPluginManager` for the process's lifetime, rebuilding only when the given search-path set changes.
**Rationale**: the source's own comment documents this as an accepted tradeoff — a plugin installed after the daemon process started stays invisible until the daemon's next launch (which host installers perform anyway) — in exchange for never repeating discovery/`dlopen` work on the hot completion path.
**Approved**: pending

**Decision**: for a configuration with no stored model, whatever surfaces as "the model" in the AI-Log's ok-row column is the configuration's `pluginIdentifier`, not the descriptor-resolved default `completeViaPlugin` actually used.
**Rationale**: the source's own inline comment labels this an "accepted residual," noting that fixing it would require changing `complete`'s return type (to carry the resolved model back out alongside the reply text) — a larger change than the source's author judged worthwhile for a log-display detail.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | Reliability |

Secure-storage passes because `DaemonAIChat.swift` never persists a credential itself — it only reads through the injected `SecretStoring` abstraction (Keychain-backed by default) and forwards the resolved value in memory for the duration of one call, per the Privacy section. Explicit-error-handling is `partial`: every plugin-path failure (load, `buildRequest`, streaming, empty reply) and every guard refusal is a typed, thrown error, but the CLI path passes an error other than `ClaudeCLI.CLIError` through unwrapped (see `cli-foreign-error-passthrough`). No-hardcoded-strings fails because every `ChatError.errorDescription` and every constructed `providerError` message this file authors is an unlocalized English literal (see Localization). Graceful-degradation is `partial`: the CLI path IS a designed fallback for the "no provider configured yet" case, but a CONFIGURED provider's own failure (a guard refusal, a network error, an empty stream) never falls back to the CLI path — it hard-fails with a thrown `ChatError`/`AIGuardError` instead.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
