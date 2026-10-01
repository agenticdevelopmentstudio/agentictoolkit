---
id: 4d7ed9a3-c6d8-491b-911a-cf257fde1c38
title: Daemon AI Chat
domain: agentictoolkit://cookbook/ai/chat/daemon-ai-chat
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/ai/plugins/ai-plugin
- agentictoolkit://cookbook/ai/plugins/plugin-descriptor
- agentictoolkit://cookbook/ai/chat/chat-context
- agentictoolkit://cookbook/ai/plugins/request-spec
- agentictoolkit://cookbook/ai/plugins/stream-event
- agentictoolkit://cookbook/ai/providers/provider-configuration
- agentictoolkit://cookbook/ai/providers/provider-config-keys
- agentictoolkit://cookbook/ai/providers/daemon-provider-resolver
- agentictoolkit://cookbook/ai/models/local/local-inference-guard
related:
- agentictoolkit://cookbook/ai/plugins/plugin-manager
references: []
approved-by: ''
approved-date: ''
---

# Daemon AI Chat

## Overview

This component is a non-instantiable namespace holding only static operations, whose single entry point is a headless host's reusable "ask the model one question" path — used by any daemon feature that needs a one-shot completion (session summaries, AI oversight, and similar) so every caller drives the exact same runtime rather than duplicating it. It takes a system prompt, a user prompt, a token budget, a CLI model name, and a timeout, plus injectable collaborators for reading provider settings, running the plugin, running the CLI, reading secrets, and guarding local inference.

The entry point chooses between two paths using the config-id-keyed registry the app syncs and reads back through the provider resolver:

- **Plugin path** (a configuration is selected): loads that configuration's plugin bundle, asks it to *describe* the request as a request spec, and drives it through the same transport the host's interactive chat backend uses. The model comes from the configuration's own stored value, falling back to the plugin descriptor's default.
- **CLI default** (no configuration selected): a `claude -p` subprocess — a zero-config path that needs no API key, so daemon features work before any provider has been configured.

When the plugin path's configuration points at a loopback model server (e.g. a local Ollama instance), the entry point additionally consults an injectable local-inference guard at two points — before the plugin loads (verdicting the configuration's *stored* model) and again inside the plugin path (verdicting the *effective* model, once the descriptor's default is known) — to refuse or defer a local model load that would exceed a RAM budget, and serializes allowed local completions process-wide so two host features cannot trigger two model loads at once. Remote providers and the CLI path bypass the guard entirely; opting out of the guard disables both checkpoints unconditionally.

Every collaborator the entry point touches — the plugin runtime (plugin load + run), the CLI runner (the CLI subprocess), the settings reader (the provider-registry reader), and the secret store (secure, Keychain-backed on Apple platforms) — is an injectable parameter with a production default, so the two dispatch paths, the guard's two checkpoints, and the template-scoped secret-resolution logic can all be exercised hermetically in tests without a real bundle, network call, subprocess, or secure-storage entry.

## Behavioral Requirements

- **namespace-only**: this component MUST be exposed as a non-instantiable namespace holding only static operations and type aliases.
- **plugin-runtime-injectable**: the plugin runtime interface MUST be a value type holding two independently substitutable operations, `load` and `run`, so a caller MAY substitute a fake implementation for hermetic testing without touching disk, network, or a subprocess, and MUST be safe to hand across concurrent callers.
- **plugin-runtime-live-load**: the plugin runtime interface's live `load` operation MUST resolve through the live plugin cache, and MUST run on the platform's UI-confined execution context, because the underlying plugin manager requires it.
- **plugin-runtime-live-run**: the plugin runtime interface's live `run` operation MUST be exactly the shared transport's `run`, so the plugin path streams events through the same transport the host's interactive chat backend uses.
- **cli-runner-type**: the CLI runner interface MUST be an operation accepting a prompt, a system prompt, a model, and a timeout, and returning the reply text or failing with an error; it MUST be safe to invoke from multiple concurrent callers.
- **cli-runner-live**: the CLI runner interface's live implementation MUST delegate to `ClaudeCLI.run` with the same four arguments, unmodified.
- **chaterror-cases**: the completion error type MUST expose exactly three distinct cases — a CLI-not-found case, a provider-error case carrying a message, and an empty-reply case — each with a distinct, non-empty description.
- **default-timeout-constant**: the default timeout MUST equal 60 seconds and MUST be the entry point's `timeout` parameter's default value.
- **plugin-path-selection**: this component MUST dispatch to the plugin path whenever the provider resolver's selected-configuration lookup returns a configuration.
- **cli-path-default**: this component MUST dispatch to the CLI path — passing the user prompt, system prompt, CLI model, and timeout unchanged — whenever no configuration is selected, and in that case MUST NOT call the plugin runtime's `load` operation or otherwise touch the plugin runtime.
- **guard-applicability**: the local-inference guard MUST be consulted for the plugin path if AND ONLY IF both a guard is supplied AND the loopback base-URL lookup returns a non-nil loopback base URL for the selected configuration; a remote provider (a non-loopback `baseURL`) or no supplied guard MUST skip both guard checkpoints and go straight to the plugin path.
- **loopback-detection**: the loopback base-URL lookup MUST read the configuration's `baseURL` field, trim whitespace and newlines, and return it only when non-empty AND it is recognized as a loopback address; otherwise it MUST return nothing.
- **guard-first-checkpoint**: when the guard applies, this component MUST verdict the configuration's STORED model (via the provider resolver's model lookup, which yields an empty string when unset) BEFORE the plugin is loaded or any request is built, and MUST throw the guard's own refusal error immediately on a blocked or deferred verdict, without falling back to the CLI path.
- **guard-exclusive-run**: on an allow verdict at the first checkpoint, this component MUST run the plugin path inside the guard's exclusive section, so local inference is serialized process-wide against every other caller sharing the same guard instance.
- **guard-recheck-in-lock**: immediately after entering the exclusive section, this component MUST re-verdict pressure alone and MUST throw the guard's own deferred refusal when that re-check yields a deferral, before proceeding to the plugin path — because the wait to acquire the lock MAY outlive the pre-park verdict.
- **guard-second-checkpoint**: inside the plugin path, when the STORED model was empty (the descriptor's default will be used) AND the guard applies, the effective model (the descriptor's resolved default) MUST be re-verdicted the moment it is known — BEFORE the plugin builds its request — and a blocked or deferred verdict MUST throw before the request is built.
- **guard-error-not-chaterror**: the guard's own refusal error type MUST be thrown as its own type, never wrapped in or converted to the completion error type, so a caller catching the completion error type cannot mistake a guard refusal for a retryable transport failure.
- **guard-opt-out**: opting out of the guard MUST disable both guard checkpoints unconditionally, even for a loopback configuration whose model would otherwise be blocked or deferred.
- **concurrency-scope**: this component's entry point carries no inherent ordering constraint of its own and MAY be called concurrently from any caller. The only serialization this component imposes is (a) the UI-confined-execution-context hop inside the plugin runtime's live load and (b) the shared exclusive section of the local-inference guard for a loopback configuration when the guard applies; every other combination of concurrent calls (two remote-provider configs, two CLI-path calls, a CLI-path call concurrent with a plugin-path call) MAY execute fully in parallel with no ordering guarantee between them.
- **cli-model-default**: the CLI path MUST call the CLI runner with `"haiku"` in place of the model whenever the given model string is empty; a non-empty `cliModel` is forwarded unchanged.
- **cli-error-mapping**: the CLI path MUST map a CLI-binary-not-found failure to the completion error type's CLI-not-found case, an empty-reply failure to its empty-reply case, a launch failure carrying a message to its provider-error case with the message `"Failed to launch claude: <message>"`, and a non-zero-exit failure to its provider-error case carrying the stderr text (or `"exit <code>"` when stderr is empty), truncated to its first 200 characters.
- **cli-runner-success-passthrough**: on success, the CLI path MUST return the CLI runner's result unmodified as the final reply.
- **plugin-search-paths-order**: the plugin search-paths lookup MUST return, in order, the directory `../PlugIns` relative to the running executable's location (standardized, included only when the executable's path is known) followed unconditionally by `~/.agenticplugins`.
- **plugin-load-error-passthrough**: the plugin path MUST rethrow a completion error thrown by the plugin runtime's `load` operation unchanged, and MUST wrap any other thrown error as a provider-error carrying the message `"Failed to load AI plugin '<id>': <underlying message>"`.
- **model-resolution-precedence**: the effective model MUST be the configuration's stored model (via the provider resolver) when non-empty, else the plugin descriptor's resolved default model.
- **ledger-driven-values**: the plugin path MUST rebuild the forwarded plugin config values from the host's non-secret fields ledger (a newline-separated field-name list) and each field's stored value, NOT by re-deriving keys from the plugin descriptor's own fields, so a template-level default beyond `baseURL`/`authMode` survives the headless path.
- **secret-scope-by-template**: secret values MUST be resolved only for the fields of the configuration's OWN template — the descriptor's resolved template matching the configuration's `templateId`, mapped through its declared fields — falling back to the full field union only when the configuration's `templateId` no longer resolves to any template.
- **keyless-template-no-phantom-secret**: a template whose resolved fields do not declare a given secret key (e.g. a keyless template overriding its fields to omit `apiKey`) MUST leave that key ABSENT from the forwarded plugin config values (`config.apiKey == nil`), never synthesize an empty string for it.
- **keyed-template-declares-empty-secret**: a template whose resolved fields DO declare a secret key MUST result in that key being present in the forwarded values, set to the secret store's lookup result or an empty string, even when no value is stored (`config.apiKey == ""`), distinguishing "declared but blank" from "not declared".
- **model-key-injected-last**: the plugin path MUST set the forwarded `"model"` value to the resolved effective model AFTER populating ledger and secret values, so it is authoritative over any same-named descriptor field.
- **single-user-message**: the plugin path MUST construct the request context's messages as exactly one message with the user role and the user prompt as its content; the parameter list carries no prior conversation turns.
- **build-request-error-wrapping**: a plugin request-build failure MUST be wrapped as a provider-error carrying the message `"Plugin could not build the request: <underlying message>"`.
- **stream-accumulation**: the plugin path MUST accumulate every `.textDelta(text)` event's `text` by string concatenation, in event order, into the returned reply.
- **stream-end-stops-consumption**: a `.end` event MUST terminate stream consumption immediately, regardless of `stopReason`, without treating any `stopReason` value as an error.
- **stream-tooluse-ignored**: a `.toolUse` event MUST be ignored (no side effect, no error), since a one-shot completion request declares no tools.
- **stream-error-wrapping**: any error thrown while consuming the plugin runtime's `run` stream MUST be wrapped as a provider-error carrying that error's description.
- **empty-reply-guard**: after streaming completes, the plugin path MUST throw the completion error type's empty-reply case when the accumulated reply is empty or all-whitespace after trimming, and MUST NOT return that blank/whitespace string.
- **timeout-cli-path-only**: the entry point's `timeout` parameter MUST govern only the CLI path's subprocess wait (forwarded verbatim); it MUST NOT be forwarded into the plugin path, whose own per-request budget is the plugin-supplied request spec's timeout and whose lock-hold budget is the guard's own exclusive-section deadline.
- **cache-reuse-by-search-paths**: the live plugin cache's `load` MUST reuse the cached plugin manager when the given search paths equal the previously cached ones; otherwise it MUST construct a new plugin manager, discover its plugins, replace the cached manager and paths, and clear every previously loaded plugin instance.
- **cache-unknown-identifier**: the live plugin cache's `load` MUST throw the completion error type's provider-error case with the message `"AI plugin not installed: <identifier>"` when the manager has no descriptor for that identifier.
- **cache-instance-reuse**: the live plugin cache's `load` MUST return an already-cached plugin instance for the identifier without loading it again; otherwise it MUST load it, cache the result, and return it.
- **cli-foreign-error-passthrough**: an error other than a `ClaudeCLI.CLIError` thrown by an injected CLI runner MUST propagate out of the CLI path and the entry point unchanged, not wrapped as a completion error; unlike the plugin path, whose failure handling wraps every failure as a provider-error, the CLI path catches only `ClaudeCLI.CLIError`. The CLI runner interface's documentation names `ClaudeCLI.CLIError` as the only error a runner throws.

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

- **Empty/blank prompts**: an empty user prompt or system prompt MUST be passed through unvalidated to the plugin's request-building step (or, on the CLI path, to the CLI runner/`claude -p` itself); this component performs no non-emptiness check of its own (see `single-user-message`).
- **Empty ledger**: an empty or absent non-secret fields ledger MUST result in the forwarded values containing only the injected `"model"` key — no ledger-derived field is forwarded (`ledger-driven-values`).
- **Malformed/absent registry**: a missing or non-JSON provider-configuration registry MUST make the provider resolver's selected-configuration lookup return nothing, so this component MUST take the CLI-default path; it performs no validation or error reporting of the registry itself.
- **Boundary `maxTokens`**: `0` or a negative `maxTokens` MUST be forwarded to the request context's `maxTokens` field and the plugin's request-building step unchanged and unvalidated; any rejection of an out-of-range value is the plugin's or provider's concern, not this component's.
- **Boundary `timeout`**: a `0` (or very small) `timeout` MUST still be forwarded verbatim to the CLI runner on the CLI path; the plugin path ignores this parameter entirely (`timeout-cli-path-only`).
- **Concurrent access, same loopback configuration**: two concurrent calls to this component for the SAME loopback configuration, each passing a shared guard, MUST be serialized FIFO by that guard so at most one is inside the plugin path at a time (`guard-exclusive-run`); a concurrent call that instead opts out of the guard MUST NOT be serialized against the others.
- **Concurrent access, unguarded paths**: two concurrent calls to this component for two remote-provider configurations, two CLI-path calls, or a CLI-path call concurrent with a plugin-path call MAY run fully in parallel with no ordering guarantee (`concurrency-scope`).
- **Guard refusal at either checkpoint**: a blocked or deferred verdict from the first (pre-load) or second (post-descriptor-resolution) checkpoint MUST abort before the plugin's request-building/transport ever runs (`guard-first-checkpoint`, `guard-second-checkpoint`); the CLI path is never used as a fallback for a guard refusal.
- **Plugin load failure**: an unknown plugin identifier, a bundle-load failure, or any other failure from the plugin runtime's `load` operation MUST surface as a provider-error (or an already-typed completion error passed through unchanged) — never an unhandled crash (`plugin-load-error-passthrough`).
- **Request-build failure**: a plugin's request-building step failing (e.g. because the resolved config is insufficient) MUST surface as a provider-error naming the underlying error (`build-request-error-wrapping`).
- **Transport/stream failure**: any error thrown while consuming the plugin runtime's `run` stream MUST surface as a provider-error carrying that error's description (`stream-error-wrapping`).
- **CLI failure taxonomy**: all four `ClaudeCLI.CLIError` cases MUST map to a specific, distinct completion-error case per `cli-error-mapping`; no fifth CLI failure shape is defined by `ClaudeCLI.CLIError` itself.
- **Non-`ClaudeCLI.CLIError` from an injected CLI runner**: propagates unchanged, unwrapped — see `cli-foreign-error-passthrough`.
- **Offline/disconnected state**: for the plugin path, this component performs no direct connectivity check of its own; an unreachable host surfaces only as whatever the shared transport's `run` throws, uniformly wrapped by `stream-error-wrapping`. For the CLI path, the CLI runner spawns a local subprocess with no network call originating in this component directly; if the CLI's own backend call fails due to connectivity, that most likely surfaces as a non-zero-exit failure, mapped like any other CLI failure — this component cannot and does not distinguish "offline" from any other non-zero exit or launch failure.
- **Cancellation**: cancelling the calling task while parked on the local-inference guard's FIFO queue (`guard-exclusive-run`) MUST cause the guard's acquire step to throw a cancellation error — a third error shape, neither the completion error type nor the guard's own refusal error type — which this component does not catch or rewrap, so it propagates to the caller as-is; this is the local-inference guard's own documented behavior, inherited unmodified here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `systemPrompt` | text | none — required | System prompt text for this one-shot turn |
| `userPrompt` | text | none — required | The single user message's text |
| `maxTokens` | integer | none — required | Forwarded unvalidated into the request context's `maxTokens` field on the plugin path; unused on the CLI path |
| `cliModel` | text | `"haiku"` | Model name for the CLI path only; an empty string is also treated as `"haiku"` by the CLI path |
| `timeout` | duration (seconds) | `defaultTimeout` (`60`) | Governs only the CLI path's subprocess wait; ignored on the plugin path |
| `settings` | settings-reader interface | none — required | Reads the host's synced provider-registry values, keyed by the provider-config-keys scheme |
| `runtime` | plugin runtime interface | live implementation | Injectable plugin-load/run seam |
| `cliRunner` | CLI runner interface | live implementation | Injectable CLI-subprocess seam |
| `secretStore` | secret store interface | Keychain-backed on Apple platforms | Source of a template's secret field values |
| `inferenceGuard` | local-inference guard (optional) | shared instance | The local-inference RAM guard; opting out disables both checkpoints |

This component reads settings keys under the provider-config-keys scheme, via the provider resolver and the plugin path: the configurations registry, the selected-configuration id, a configuration's stored model, its non-secret fields ledger, and each ledger field's stored value.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation destination.

## Localization

No message in this component is externalized through a localization key. Every user-facing string this component itself authors is a hardcoded English literal:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Claude CLI not found (install Claude Code or check PATH)` | the completion error type's CLI-not-found case description |
| (none — hardcoded) | `Empty reply from the model` | the completion error type's empty-reply case description |
| (none — hardcoded) | `Failed to launch claude: <message>` | the CLI path's launch-failure mapping |
| (none — hardcoded) | `claude -p failed: <stderr or "exit <code>", truncated to 200 chars>` | the CLI path's non-zero-exit mapping |
| (none — hardcoded) | `Failed to load AI plugin '<id>': <underlying message>` | the plugin path's plugin-load error wrap |
| (none — hardcoded) | `Plugin could not build the request: <underlying message>` | the plugin path's request-build error wrap |
| (none — hardcoded) | `AI plugin not installed: <identifier>` | the live plugin cache's unknown-identifier error |

The completion error type's provider-error case has one remaining call site (the stream-consumption wrap) that carries a plugin/transport-supplied error description through verbatim rather than authoring new text — that upstream string's own localization is out of this component's control.

## Accessibility Options

Not applicable: this is a non-UI logic component with no visible surface, so it consults none of the system accessibility display options (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: this component reads no feature-flag key and gates none of its behavior behind one; its two-path dispatch is driven entirely by whether a provider configuration is selected, not by a flag.

## Analytics

Not applicable: this component emits no analytics or event-tracking call.

## Privacy

- **Data handled**: the plugin path reads the host's non-secret settings ledger and, for the configuration's own resolved template, its declared secret fields (e.g. `apiKey`) via the injected secret store. This component does not decide what is sensitive — it forwards exactly what the ledger and secret store report, scoped by the provider-config-keys scheme and `secret-scope-by-template`.
- **Storage**: this component stores nothing itself. It reads through the settings reader (a plain key/value reader) and the secret store's lookup (Keychain-backed by default) and writes nothing back; the prompt text and the accumulated reply exist only as local variables for the duration of one call, with no persistence of either.
- **Transmission**: resolved values, including a secret, are packaged into the forwarded plugin config and request context, which are handed to the plugin's request-building step, which MAY embed a secret (e.g. as an `Authorization` header) into the returned request spec; the actual wire transmission happens inside the shared transport's `run`, not in this component. On the CLI path, the system prompt and user prompt are passed to the CLI runner, which spawns a local subprocess — no network call originates directly in this component for that path, though the CLI itself may reach a remote API.
- **Retention**: this component defines no retention, expiry, rotation, or revocation policy for any credential; whatever the secret store's lookup returns reflects the caller-supplied store's own retention. This component has no violation-detection logic of its own — a plugin-level authentication failure (e.g. an HTTP 401) surfaces only generically, as a provider-error carrying whatever message the plugin's error description or the shared transport's own generic HTTP-status message supplies, with no distinct handling for a credential problem versus any other provider error.

## Logging

Not applicable: this component contains no logging call; it is orchestration logic with no logging side effects of its own.

## Platform Notes

- **SwiftUI**: The source, `packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift`, has no view-layer dependency at all — `complete` is a plain `static func` a SwiftUI (or any other) host calls from a `Task`, typically wrapping the call in a view model that publishes the in-flight/succeeded/failed state, since `DaemonAIChat` itself is not observable and returns only a final `String` (no partial-progress callback).
- **Compose**: model the two-path dispatch as a `suspend fun complete(...)` in a plain Kotlin object, with `PluginRuntime` and `CLIRunner` as constructor-injected function types (or a small interface each) for the same hermetic-testing seam. Android has no `dlopen`/`NSPrincipalClass` equivalent for the plugin path itself (see the `ai-plugin-manager` recipe's Compose note); the guard's actor-based mutual exclusion maps to a `Mutex` (kotlinx.coroutines) guarding the local-inference critical section, and the FIFO recheck-after-acquire pattern (`guard-recheck-in-lock`) carries over directly since `Mutex.withLock` also has to reconsider state that may have changed while suspended waiting for the lock.
- **React/Web**: model `complete` as an `async function` returning `Promise<string>`, with `runtime`/`cliRunner`/`settings`/`secretStore` as injected parameters or closures for the same test seams. There is no local subprocess (`claude -p`) equivalent in a browser; a web port's "zero-config default" would more plausibly be a server-side proxy endpoint than an in-process CLI fallback. The local-inference guard's process-wide mutual exclusion has no direct browser analogue (there is one JS execution context per tab); a multi-tab web host would need a `BroadcastChannel`- or server-mediated equivalent of `LocalInferenceGuard.runExclusive` to serialize local-model calls across tabs.
- **AppKit / UIKit**: same note as SwiftUI — `DaemonAIChat.swift` has no AppKit/UIKit dependency; only the host embedding it differs. The `.aiplugin` bundle-loading path this file drives is macOS-only (see the `ai-plugin-manager` and `ai-plugin` recipes), which is why this recipe's `platforms` list `macos` and not `ios`; an iOS host could still use the CLI-independent plugin path if a plugin bundle-loading mechanism were ported, but never the `claude -p` subprocess fallback, since iOS sandboxes forbid spawning arbitrary subprocesses. Internally, the live plugin runtime's `load` hops onto the main actor via `MainActor.run`, because `AIPluginManager` (which `LivePluginCache` wraps) is `@MainActor`-isolated — a concurrency detail with no view dependency of its own. `LivePluginCache` itself is a `@MainActor`-isolated private enum whose mutable static state (the cached manager, its search paths, and loaded plugin instances) is safe to mutate without a separate lock because the main actor serializes all access to it. Separately, `ChatError` declares `Error, LocalizedError` conformance only, with no explicit `Sendable` conformance, so it must be treated as non-`Sendable` across a concurrency-domain boundary regardless of its sole associated value (`String`) being itself `Sendable`. The file also authors no localized string via `NSLocalizedString`/`String(localized:)` and makes no logging call (no `Logger`/`os` import).
- **WinUI 3**: model `complete` as an `async Task<string>` on a static class, with `PluginRuntime` (a record of two delegates) and `CLIRunner` as injected dependencies. `ClaudeCLI`'s subprocess fallback maps to `System.Diagnostics.Process`; `AssemblyLoadContext` is the nearest analogue for the plugin-loading half of the plugin path (see the `ai-plugin-manager` recipe's WinUI 3 note for the caching tradeoff this implies). The two-checkpoint local-inference guard maps to a `SemaphoreSlim`(1) guarding the critical section, with the same "re-check pressure after acquiring" pattern; `Windows.Storage`/Credential Locker stands in for the Keychain-backed `SecretStoring` this file reads through. Because `System.Diagnostics.Process` and `HttpClient` calls are both naturally `async`/awaitable on .NET, a WinUI 3 port has no equivalent of Swift's `AsyncThrowingStream`-based event consumption for `PluginRuntime.run`; `IAsyncEnumerable<AiStreamEvent>` is the direct substitute, with the `.end`/`.toolUse`/`.textDelta` switch in `completeViaPlugin` carrying over as a `switch` over an enum/discriminated union inside an `await foreach`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/chat/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
