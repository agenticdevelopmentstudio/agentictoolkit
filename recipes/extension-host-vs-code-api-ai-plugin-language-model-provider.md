---
id: a602608c-c061-44b6-a7ab-829e798d6b0c
title: AIPluginLanguageModelProvider
domain: agentictoolkit://recipes/extension-host-vs-code-api-ai-plugin-language-model-provider
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The production ExtensionLanguageModelProviding conformer: lists every configured
  AI-plugin model as a vscode.lm chat model and streams sendRequest through the existing
  AIPlugin/PluginTransport path.'
platforms:
  - swift
  - macos
tags:
  - extension-host
  - vscode-api
  - ai-plugin
  - language-model
  - streaming
depends-on:
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-configuration
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-model-catalog
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-plugin-transport
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-stream-event
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin
related: []
references:
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/AIPluginLanguageModelProvider.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguageModels.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/AIPluginLanguageModelProviderTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderResolver.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderConfiguration.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/AIModelCatalog.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ""
approved-date: ""
---

# AIPluginLanguageModelProvider

## Overview

`AIPluginLanguageModelProvider` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/AIPluginLanguageModelProvider.swift`) is the production `ExtensionLanguageModelProviding` conformer for the VS Code extension-host seam: it offers extensions the chat models the user has already configured in the app's own LLM Providers settings, and streams a `sendRequest` call through the same `AIPlugin` path the app's own chat surface uses. Per its own doc comment, it adds no transport, no credential handling, and no request shaping of its own — it reuses `AIProviderConfiguration`/`AIProviderResolver` (which already join a configuration to its plugin template, stored credentials, and model) and `AIPluginManager`/`PluginTransport` (which already load a plugin and drive its request) rather than opening a second route to a provider. `availableChatModels` lists the cross product of every model of every configuration the user has saved — not the app's own single selected chat configuration — because `vscode.lm.selectChatModels` asks what the host *has* and does its own selector matching one layer up, in `MainThreadLanguageModels`. `streamResponse` turns a `LanguageModelChatDescriptor.id` of the form `"<configuration UUID>/<model>"` back into a configuration and a model name, resolves the configuration to a loadable plugin, builds an `AIChatContext`, and adapts `PluginTransport`'s `AIStreamEvent` stream into the seam's own `ExtensionLanguageModelResponsePart` stream.

## Behavioral Requirements

- **main-actor-isolation**: `AIPluginLanguageModelProvider` MUST be declared `@MainActor`; every stored property read and write, and the synchronous portion of every method, MUST execute on the main actor.
- **protocol-conformance**: `AIPluginLanguageModelProvider` MUST conform to `ExtensionLanguageModelProviding`, implementing both `availableChatModels` and `streamResponse(for:messages:justification:extensionIdentifier:)`.
- **injected-plugin-manager**: `init(pluginManager:)` MUST store the given `AIPluginManager` as the sole source of plugin descriptors and loaded plugin instances; the type MUST NOT construct its own `AIPluginManager`.
- **configuration-observer-wiring**: `init(pluginManager:)` MUST subscribe a `UserSettingObserver` to `UserSettings.aiProviderConfigurations` so that every subsequent write to that setting invokes `onAvailableChatModelsChanged`.
- **no-notification-on-construction**: Constructing an `AIPluginLanguageModelProvider` MUST NOT itself invoke `onAvailableChatModelsChanged`, even when `UserSettings.aiProviderConfigurations` already holds one or more configurations at construction time.
- **every-configured-model-listed**: `availableChatModels` MUST return one `LanguageModelChatDescriptor` for every model in every template of every configuration currently in `UserSettings.aiProviderConfigurations.currentValue` — the full cross product of configurations and their templates' models, not the app's single selected configuration (`UserSettings.selectedAIProviderConfigurationId`).
- **deterministic-model-order**: `availableChatModels` MUST order its results first by the order configurations appear in `UserSettings.aiProviderConfigurations.currentValue`, then by the order models appear in that configuration's resolved template's `models` array.
- **unresolvable-template-skipped**: When `pluginManager.template(pluginIdentifier:templateId:)` returns `nil` for a configuration, `availableChatModels` MUST contribute no descriptor for that configuration and MUST continue processing the remaining configurations.
- **descriptor-id-format**: Each `LanguageModelChatDescriptor.id` MUST be the string formed by joining `configuration.id.uuidString` and the model name with a single `"/"` separator.
- **descriptor-id-separator-safety**: The `id` split performed in `resolveConfiguration(for:)` MUST use the FIRST occurrence of `"/"` only, so a model name that itself contains `"/"` is preserved verbatim in the parsed model name.
- **descriptor-name**: Each descriptor's `name` MUST be the configuration's `name`, a `"·"` separator, and the model name.
- **descriptor-vendor**: Each descriptor's `vendor` MUST be the resolved template's `provider`, falling back to the template's `displayName` when `provider` is `nil`.
- **descriptor-family**: Each descriptor's `family` MUST be `AIModelCatalog.canonicalID(model)`.
- **descriptor-version**: Each descriptor's `version` MUST be the raw model name, unmodified.
- **descriptor-max-input-tokens**: Each descriptor's `maxInputTokens` MUST be `AIModelCatalog.shared.resolve(model:template:).contextWindow` when the catalog has an entry for that model/template pair, and MUST be `4096` when it does not.
- **justification-recorded-only**: When `streamResponse` is called with a non-nil `justification`, it MUST log the extension identifier and the justification via `Self.logger.info` before doing anything else, and MUST NOT use the justification's content to gate, filter, or alter which model or plugin the request reaches.
- **justification-privacy**: The logged `justification` value MUST be tagged `.private`; the logged `extensionIdentifier` value MUST be tagged `.public`.
- **no-log-when-justification-absent**: When `justification` is `nil`, `streamResponse` MUST NOT emit the justification log line at all.
- **model-id-parse-failure**: `resolveConfiguration(for:)` MUST throw `ProviderError.unknownModel(model.id)` when `model.id` contains no `"/"` character.
- **model-id-unknown-configuration**: `resolveConfiguration(for:)` MUST throw `ProviderError.unknownModel(model.id)` when the substring before the first `"/"` does not parse as a `UUID`, or parses but names no configuration currently in `UserSettings.aiProviderConfigurations.currentValue`.
- **configuration-reread-per-call**: `resolveConfiguration(for:)` MUST re-read `UserSettings.aiProviderConfigurations.currentValue` on every call rather than reuse a value captured when the descriptor was built, so a configuration deleted after the descriptor was issued is reflected on the next call.
- **plugin-resolution-failure**: `streamResponse` MUST throw `ProviderError.pluginUnavailable(configuration.pluginIdentifier)` when `AIProviderResolver.resolve(_:manager:)` returns `nil` for the resolved configuration.
- **plugin-load-failure-collapsed**: `streamResponse` MUST throw `ProviderError.pluginUnavailable(resolved.pluginIdentifier)` when `pluginManager.loadPlugin(identifier:)` throws, regardless of which of `AIPluginManager.AIPluginError`'s cases (`notFound`, `loadFailed`, `noPrincipalClass`, `principalClassNotPlugin`) was thrown; the specific thrown error MUST be discarded via `try?`.
- **request-model-override**: `streamResponse` MUST set both the `AIPluginConfig` bag's `model` entry and `AIChatContext.model` to the model name parsed from the requested descriptor's `id`, overriding whatever model the resolved configuration's own stored value would otherwise supply.
- **no-system-prompt**: Every `AIChatContext` `streamResponse` builds MUST have `systemPrompt == nil`.
- **no-tools-forwarded**: Every `AIChatContext` `streamResponse` builds MUST have `tools == []`; `streamResponse`'s parameters carry no tool list of its own for this to forward.
- **default-max-tokens**: Every `AIChatContext` `streamResponse` builds MUST omit an explicit `maxTokens` argument, so every request uses `AIChatContext.init`'s own default of `4096`, independent of the resolved descriptor's `maxInputTokens`.
- **build-request-error-propagation**: When `plugin.buildRequest(_:)` throws, `streamResponse` MUST propagate that error unwrapped — it MUST NOT catch it or convert it into a `ProviderError` case.
- **transport-delegation**: `streamResponse` MUST delegate all network access and subprocess execution to `PluginTransport.run(spec:plugin:)`; `AIPluginLanguageModelProvider` MUST perform no HTTP request, no subprocess launch, and no credential lookup of its own.
- **response-part-mapping**: `responsePart(for:)` MUST map `AIStreamEvent.textDelta` to `.text`, `.toolUse(id:name:argumentsJSON:)` to `.toolCall(id:name:argumentsJSON:)`, and `.end(stopReason:)` to `.end(stopReason:)`, with no case dropped or merged.
- **message-role-mapping**: `chatMessage(for:)` MUST map `ExtensionLanguageModelMessage.Role.user` to `AIChatMessage.Role.user` and MUST map `ExtensionLanguageModelMessage.Role.assistant` — the enum's only other case — to `AIChatMessage.Role.assistant`.
- **message-name-dropped**: `chatMessage(for:)` MUST NOT carry `ExtensionLanguageModelMessage.name` into any field of the `AIChatMessage` it produces.
- **stream-single-consumption**: `streamResponse` MUST return a fresh `AsyncThrowingStream` per call; it MUST NOT return or reuse a previously-returned stream.
- **stream-cancellation-propagation**: When the consumer of `streamResponse`'s returned stream terminates early, `continuation.onTermination` MUST cancel the wrapping `Task`, which cancels the `PluginTransport.run` stream it is iterating.
- **no-instance-caching**: `availableChatModels` and `resolveConfiguration(for:)` MUST NOT cache a prior call's result; each call MUST recompute from the current `UserSettings.aiProviderConfigurations.currentValue` and the current `pluginManager` state.
- **unknown-model-caller-guidance**: A caller catching `ProviderError.unknownModel` SHOULD treat it as a stale descriptor and re-query `availableChatModels`, rather than as a malformed request from the extension — deviation is acceptable because both of `unknownModel`'s triggers (an unparseable id, or a configuration deleted since the descriptor was issued) originate from state that changed after the descriptor was handed out, not from anything the extension itself chose; per the type's own doc comment, both cases are "the same event from an extension's point of view: it held a model descriptor across the user deleting the provider behind it."
- **model-name-membership**: Neither `resolveConfiguration(for:)` nor `AIProviderResolver.resolve(_:manager:)` checks that the model name parsed out of a descriptor's `id` is still present in the resolved template's current `models` array — only that the configuration id and its `templateId` still resolve. If a plugin update removes or renames a model between the time a descriptor was built and a later `sendRequest` call parses it, `streamResponse` MUST send the request with the stale model name unchanged, leaving `plugin.buildRequest(_:)` and the provider to reject it; any such rejection surfaces to the caller as the stream's error.

## Appearance

Not applicable — this is the extension host's production `ExtensionLanguageModelProviding` conformer, not a visual component.

## States

Not applicable — this is the extension host's production `ExtensionLanguageModelProviding` conformer, not a visual component. Its only lifecycle-shaped behavior is the per-request `streamResponse` sequence (resolve, load, build, stream), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's production `ExtensionLanguageModelProviding` conformer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-language-model-provider-001 | every-configured-model-listed, deterministic-model-order, descriptor-vendor, descriptor-family, descriptor-version, descriptor-max-input-tokens | One configuration "My Provider" on plugin "test.plugin"/template "template-a" with `models == ["model-a", "model-b"]` → `provider.availableChatModels` | Returns two descriptors with ids `"<configId>/model-a"` and `"<configId>/model-b"`, names `"My Provider · model-a"`/`"My Provider · model-b"`, `vendor == "Template A"` for both, `family`/`version` equal to the model name, and `maxInputTokens == 4096` for both — `AIPluginLanguageModelProviderTests.availableChatModelsExposesEveryModelOfEveryConfiguredProvider` |
| ai-plugin-language-model-provider-002 | unresolvable-template-skipped | A configuration whose `pluginIdentifier` ("never.registered") is never registered with `pluginManager` → `availableChatModels` | Returns `[]` — `AIPluginLanguageModelProviderTests.aConfigurationWhosePluginIsUnregisteredContributesNoModels` |
| ai-plugin-language-model-provider-003 | deterministic-model-order | Two configurations "First" and "Second" sharing one template whose `models == ["only-model"]` → `availableChatModels` | Returns names in order `["First · only-model", "Second · only-model"]` — `AIPluginLanguageModelProviderTests.availableChatModelsOrdersByConfigurationThenModelOrder` |
| ai-plugin-language-model-provider-004 | configuration-observer-wiring | Attach `onAvailableChatModelsChanged`, then write a new value to `UserSettings.aiProviderConfigurations`, then drain the main queue | The callback fires exactly once — `AIPluginLanguageModelProviderTests.onAvailableChatModelsChangedFiresWhenTheConfiguredProviderListChanges` |
| ai-plugin-language-model-provider-005 | no-notification-on-construction | Construct the provider while a configuration is already present, attach the callback afterward, then drain | The callback never fires — `AIPluginLanguageModelProviderTests.constructingTheProviderDoesNotFireOnAvailableChatModelsChanged` |
| ai-plugin-language-model-provider-006 | model-id-parse-failure | `streamResponse` for a descriptor whose `id == "not-a-uuid-slash-model"` (no `"/"`) | Throws `ProviderError.unknownModel(model.id)` before any plugin lookup — `AIPluginLanguageModelProviderTests.streamResponseThrowsUnknownModelForADescriptorIDWithNoSeparator` |
| ai-plugin-language-model-provider-007 | model-id-unknown-configuration, configuration-reread-per-call | `streamResponse` for a descriptor `id == "<random UUID>/model-a"` naming no existing configuration | Throws `ProviderError.unknownModel(model.id)` — `AIPluginLanguageModelProviderTests.streamResponseThrowsUnknownModelForAConfigurationIDNoLongerInSettings` |
| ai-plugin-language-model-provider-008 | plugin-resolution-failure | A configuration whose `pluginIdentifier` ("never.registered") is never registered with `pluginManager` → `streamResponse` | Throws `ProviderError.pluginUnavailable(configuration.pluginIdentifier)` — `AIPluginLanguageModelProviderTests.streamResponseThrowsPluginUnavailableWhenThePluginIsUnregistered` |
| ai-plugin-language-model-provider-009 | descriptor-id-separator-safety | A template model name containing `"/"` (e.g. `"org/model-name"`) → `descriptor(for:configuration:template:)` then `resolveConfiguration(for:)` on the resulting id | The built id is `"<uuid>/org/model-name"`; `resolveConfiguration` splits at the FIRST `"/"` only and returns `modelName == "org/model-name"` unchanged — traced to `model.id.firstIndex(of: idSeparator)` and the source's own doc comment claiming a model name containing `"/"` is preserved because the split is on the first separator only |
| ai-plugin-language-model-provider-010 | request-model-override | `resolved.values["model"]` already holds the app's own selected model string; `streamResponse` is called for a descriptor naming a different model | The `AIPluginConfig` bag and `AIChatContext.model` both carry the extension-selected model name, not the configuration's stored app-selected model — traced to `values["model"] = modelName` executing after `var values = resolved.values` |
| ai-plugin-language-model-provider-011 | default-max-tokens | Any successful `streamResponse` call, regardless of the resolved descriptor's `maxInputTokens` | The `AIChatContext` built for the request has `maxTokens == 4096` — traced to the `AIChatContext(...)` call site omitting `maxTokens` and to `AIChatContext.init`'s default parameter value |
| ai-plugin-language-model-provider-012 | no-system-prompt, no-tools-forwarded | Any successful `streamResponse` call | The built `AIChatContext` has `systemPrompt == nil` and `tools == []` unconditionally — traced to the literal `systemPrompt: nil` and `tools: []` arguments at the call site |
| ai-plugin-language-model-provider-013 | response-part-mapping | `PluginTransport`'s stream yields `.textDelta("hi")`, then `.toolUse(id: "1", name: "x", argumentsJSON: Data())`, then `.end(stopReason: "stop")` | The stream `streamResponse` returns yields `.text("hi")`, then `.toolCall(id: "1", name: "x", argumentsJSON: Data())`, then `.end(stopReason: "stop")`, in the same order — traced to `responsePart(for:)`'s three-case switch |
| ai-plugin-language-model-provider-014 | message-role-mapping, message-name-dropped | `messages == [ExtensionLanguageModelMessage(role: .user, name: "ignored", text: "hi"), ExtensionLanguageModelMessage(role: .assistant, name: nil, text: "hi back")]` | `chatMessage(for:)` maps these to `AIChatMessage(role: .user, content: "hi")` and `AIChatMessage(role: .assistant, content: "hi back")`; the `"ignored"` name value is dropped, appearing in no `AIChatMessage` field — traced to `chatMessage(for:)`'s ternary and its doc comment ("Dropped rather than misfiled") |
| ai-plugin-language-model-provider-015 | stream-cancellation-propagation | The consumer of `streamResponse`'s returned stream stops iterating early (cancels) | `continuation.onTermination` fires and cancels the wrapping `Task`, which cancels the `PluginTransport.run` stream it awaits — traced to `continuation.onTermination = { _ in task.cancel() }` and `PluginTransport.run`'s own doc comment ("Cancelling the consuming task cancels the underlying transfer or terminates the subprocess") |
| ai-plugin-language-model-provider-016 | justification-recorded-only, justification-privacy, no-log-when-justification-absent | `streamResponse` called once with `justification == "need vision"` and once with `justification == nil`, both otherwise routed to a configuration whose plugin fails to load | `Self.logger.info` is invoked exactly once, only on the non-nil call, with `extensionIdentifier` tagged `.public` and `justification` tagged `.private`; neither call's routing to `ProviderError.pluginUnavailable` differs based on the justification's presence or content — traced to the `if let justification { Self.logger.info(...) }` guard preceding `resolveConfiguration` |
| ai-plugin-language-model-provider-017 | model-name-membership | A configuration's template is updated to drop `"model-a"` from `models`, but a previously-issued descriptor id still names `"model-a"`; `streamResponse` is called with that stale descriptor id | No dedicated test exists in the given sources; reading `resolveConfiguration(for:)` and `AIProviderResolver.resolve(_:manager:)` shows neither checks the parsed model name against the current template's `models` array, so the request proceeds to `plugin.buildRequest(_:)` with the stale model name — demonstrating the open question rather than resolving it |

## Edge Cases

- **Null/empty input**: `model.id == ""` MUST be treated as "no separator found" and MUST cause `resolveConfiguration(for:)` to throw `ProviderError.unknownModel("")` (MUST).
- **Null/empty input**: an empty `messages` array MUST be mapped to an empty `[AIChatMessage]` and passed to `AIChatContext` unchanged; `streamResponse` performs no minimum-length check (MUST).
- **Null/empty input**: `justification == nil` MUST suppress the justification log line entirely, per **no-log-when-justification-absent** (MUST).
- **Boundary values**: a `template.models` array containing exactly one model is the minimum non-empty case for `availableChatModels` to contribute a descriptor for that configuration; it MUST still be ordered and formatted identically to a multi-model template (MUST).
- **Boundary values**: a model name containing one or more `"/"` characters MUST round-trip through `descriptor(for:)` and `resolveConfiguration(for:)` unchanged, per **descriptor-id-separator-safety** (MUST).
- **Boundary values**: `AIChatContext`'s `maxTokens` is fixed at `4096` for every request regardless of how large or small the resolved descriptor's `maxInputTokens` is; no per-request scaling is performed (MUST).
- **Concurrent access**: `AIPluginLanguageModelProvider` holds no per-call mutable state — `availableChatModels` and `resolveConfiguration(for:)` each recompute from `UserSettings.aiProviderConfigurations.currentValue` and `pluginManager` on every call — so multiple concurrent `streamResponse` calls MUST NOT race against each other or against a concurrent `availableChatModels` read (MUST).
- **Concurrent access**: a write to `UserSettings.aiProviderConfigurations` concurrent with an in-flight `streamResponse` call MUST NOT affect that call's already-resolved configuration and model, because `resolveConfiguration(for:)` reads the setting exactly once, synchronously, before any `await` (MUST).
- **Error states**: `AIProviderResolver.resolve(_:manager:)` returning `nil` (the configuration's plugin descriptor exists but its `templateId` no longer resolves) MUST surface as `ProviderError.pluginUnavailable(configuration.pluginIdentifier)`, per **plugin-resolution-failure** (MUST).
- **Error states**: any of `AIPluginManager.loadPlugin(identifier:)`'s four thrown cases MUST surface identically as `ProviderError.pluginUnavailable(resolved.pluginIdentifier)`, discarding which specific case occurred, per **plugin-load-failure-collapsed** (MUST).
- **Error states**: an error thrown by `plugin.buildRequest(_:)` MUST propagate to the caller of `streamResponse` unwrapped — not as a `ProviderError` case (MUST).
- **Error states**: an error thrown inside the stream returned by `PluginTransport.run` (a `PluginTransport.TransportError` case, or any other error a plugin's decoder or transport raises) MUST propagate through `continuation.finish(throwing: error)` unmodified to the consumer of `streamResponse`'s stream (MUST).
- **Offline or disconnected state**: `AIPluginLanguageModelProvider` performs no network call itself; connectivity loss during an in-flight request surfaces however `PluginTransport`'s underlying transport reports it (a thrown `URLError` from `URLSession`, or `TransportError.timedOut` if the wall-clock budget lapses first), passed through unmodified rather than detected, retried, or translated by this type (MUST).
- **Cancellation and timeouts**: `AIPluginLanguageModelProvider` enforces no timeout of its own; any request-level deadline is `PluginTransport`'s `spec.timeout`, applied one layer down. Consumer-initiated cancellation of `streamResponse`'s stream MUST propagate via `continuation.onTermination`, per **stream-cancellation-propagation** (MUST).
- **Missing file or unreachable server**: not applicable to this file directly — it opens no file and makes no network call itself; an unreachable server or a plugin bundle that fails to load surfaces as `ProviderError.pluginUnavailable` (load failure, per **plugin-load-failure-collapsed**) or as a `PluginTransport.TransportError` (an unreachable server during the request itself, per the Error states entries above).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pluginManager` | `AIPluginManager` | none (required) | Supplied to `init(pluginManager:)`; the sole source of plugin descriptors, templates, and loaded plugin instances. |
| `model` | `LanguageModelChatDescriptor` | none (required) | The descriptor `streamResponse` is asked to route; only its `id` field is consulted. |
| `messages` | `[ExtensionLanguageModelMessage]` | none (required) | The conversation history to send; mapped verbatim (minus `name`) to `[AIChatMessage]`. |
| `justification` | `String?` | none (optional) | Free text from `options.justification` (`vscode.d.ts:20392`); recorded to the log only, per **justification-recorded-only**. |
| `extensionIdentifier` | `String` | none (required) | Identifies the calling extension for the justification log line; passed straight through with no validation. |
| `UserSettings.aiProviderConfigurations` | `UserSetting<[AIProviderConfiguration]>`, settings key `"aiplugin.configurations"` | `[]` | Read by `availableChatModels` and `resolveConfiguration(for:)`; observed by the `configurationsObserver` set up in `init`. |
| `AIModelCatalog.shared` | `AIModelCatalog` (singleton) | the loaded shared catalog | Consulted by `descriptor(for:configuration:template:)` for `contextWindow`; falls back to `defaultMaxInputTokens` (`4096`) when the model/template pair is unlisted. |

## Deep Linking

Not applicable: `AIPluginLanguageModelProvider.swift` defines no URL, route, or navigable destination — it is a language-model seam conformer with no navigation surface of its own.

## Localization

`ProviderError.description`'s two case bodies — `"no configured language model with id '<id>'"` and `"the plugin '<identifier>' is not available"` — are hardcoded English string literals with no localization key, `String(localized:)` call, or String Catalog entry. Both strings are produced by `CustomStringConvertible`, the description a caller (ultimately the extension-host seam that turns a thrown `ProviderError` into a JavaScript-visible error) would surface. `LanguageModelChatDescriptor.name`'s `"<configuration.name> · <model>"` format uses a fixed `"·"` separator glyph around two data-derived strings (the user's own configuration name and a model identifier), not translatable prose.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `no configured language model with id '<id>'` | `ProviderError.unknownModel`'s `description`, surfaced when a descriptor's id no longer resolves. |
| (none — literal only) | `the plugin '<identifier>' is not available` | `ProviderError.pluginUnavailable`'s `description`, surfaced when the resolved plugin cannot be reached. |

## Accessibility Options

Not applicable: `AIPluginLanguageModelProvider.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once the type is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its one telemetry-adjacent call is the OSLog line covered under Logging, which is diagnostic logging, not an analytics event.

## Privacy

- **Data collected**: `AIPluginLanguageModelProvider` itself collects no data beyond what its callers already hand it: `justification` (free text an extension supplies explaining why it wants a model) and `extensionIdentifier` are read only to log them, per **justification-recorded-only**. `messages` (the conversation) and the resolved configuration's values are forwarded into the request the plugin builds, but not retained by this type. No credential or secret value is read or handled here — those are resolved and injected by `AIProviderResolver`/`AIProviderConfigStore`, which this type calls but does not duplicate.
- **Storage**: `AIPluginLanguageModelProvider` performs no storage of its own; `UserSettings.aiProviderConfigurations` is owned and persisted elsewhere.
- **Transmission**: `messages`, the resolved model name, and the resolved configuration's values are transmitted to the external provider, but the transmission itself is performed by `PluginTransport`/the loaded `AIPlugin`, not by this file directly.
- **Retention**: this file retains nothing beyond the lifetime of one `streamResponse` call's local variables; the one value it logs (`justification`) persists only per OSLog's own system-level retention policy, which this file does not configure.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `AIPluginLanguageModelProvider`

| Event | Level | Message |
|-------|-------|---------|
| An extension calls `streamResponse` with a non-nil `justification` | info | `extension <extensionIdentifier, privacy: .public> requested a language model, justification: <justification, privacy: .private>` |

No other event in this file is logged: neither `ProviderError.unknownModel` nor `ProviderError.pluginUnavailable` is logged at the point it is thrown — both are facts the code surfaces to the caller as thrown errors instead, per **plugin-resolution-failure** and **model-id-parse-failure**/**model-id-unknown-configuration**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIPluginLanguageModelProvider.swift` imports only `Foundation`, `OSLog`, `AgenticToolkitCore`, and `AIPluginKit`, with no SwiftUI dependency; a SwiftUI-based LLM Providers settings surface would call `availableChatModels`/`streamResponse` unchanged, the same relationship the sibling `AIProviderConfiguration`/`AIPluginManager` recipes describe for these same dependencies.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/AIPluginLanguageModelProvider.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration, and its only consumer among the given sources is `MainThreadLanguageModels` (`ExtensionLanguageModelProviding`'s declaring protocol, in the same `Extensions/VSCodeAPI` folder), itself also `@MainActor`.
- **Compose**: model this as a Kotlin `class AIPluginLanguageModelProvider(private val pluginManager: AIPluginManager) : ExtensionLanguageModelProviding` confined to the main dispatcher; `availableChatModels` becomes a computed property recomputed from whatever `StateFlow`/settings store mirrors `UserSettings.aiProviderConfigurations`, and `streamResponse` becomes a `suspend fun streamResponse(...): Flow<ExtensionLanguageModelResponsePart>` built with `callbackFlow`, whose `awaitClose` block plays the role of `onTermination` and cancels the underlying transport the same way. `ProviderError` becomes a `sealed class` with the same two cases (`UnknownModel(id: String)`, `PluginUnavailable(identifier: String)`).
- **React/Web**: model as a module exposing `availableChatModels(): LanguageModelChatDescriptor[]` and `async function* streamResponse(...)` — an async generator in place of `AsyncThrowingStream` — where the consumer's early `return`/`break` (which triggers the generator's `finally` block) is the cancellation-propagation equivalent of `continuation.onTermination`. `ProviderError` becomes a custom `Error` subclass or discriminated union with the same two variants, and the settings read becomes whatever store backs the extension host's own provider-configuration list in that runtime.
- **WinUI 3**: model `AIPluginLanguageModelProvider` as a class implementing an `IExtensionLanguageModelProviding` interface: `IReadOnlyList<LanguageModelChatDescriptor> AvailableChatModels { get; }`, `event Action? AvailableChatModelsChanged`, and `IAsyncEnumerable<ExtensionLanguageModelResponsePart> StreamResponseAsync(LanguageModelChatDescriptor model, IReadOnlyList<ExtensionLanguageModelMessage> messages, string? justification, string extensionIdentifier, [EnumeratorCancellation] CancellationToken cancellationToken = default)`, where a cancelled `CancellationToken` plays the role of `continuation.onTermination`'s `task.cancel()` and must propagate into the HttpClient call or process the same way. `ProviderError` becomes two custom `Exception` subclasses (`UnknownModelException`, `PluginUnavailableException`), since C# has no error enum with associated values. `HttpClient` and `System.Text.Json.JsonSerializer` are the .NET equivalents of the `URLSession`/`JSONDecoder` machinery one layer down in `PluginTransport`, which this type itself never calls directly. The settings read (`UserSettings.aiProviderConfigurations`) becomes an `ObservableCollection<AIProviderConfiguration>` or `INotifyPropertyChanged`-backed store, with its `CollectionChanged` event replacing `UserSettingObserver`'s Combine-based `dropFirst()` subscription to raise `AvailableChatModelsChanged`.

## Design Decisions

**Decision**: `AIPluginLanguageModelProvider`'s `LanguageModelChatDescriptor.id` is `"<configuration UUID>/<model>"`, and the split in `resolveConfiguration(for:)` uses the FIRST `"/"` only.
**Rationale**: a UUID never contains `"/"`, so the split point is unambiguous, and splitting on the first occurrence rather than the last preserves a model name that itself contains `"/"` — several gateways use such names — stated directly in the source's own doc comment.
**Approved**: pending

**Decision**: `streamResponse` collapses `AIPluginManager.loadPlugin(identifier:)`'s four distinct thrown cases (`notFound`, `loadFailed`, `noPrincipalClass`, `principalClassNotPlugin`) into one `ProviderError.pluginUnavailable(identifier)`, discarding which specific case occurred.
**Rationale**: `ProviderError`'s own doc comment frames its two cases as "what a request can fail on before a plugin is ever reached" — from the extension's point of view, every one of `loadPlugin`'s four failure modes means the same thing: the named plugin cannot serve the request right now. `try?` intentionally discards the specific cause.
**Approved**: pending

**Decision**: `resolveConfiguration(for:)` re-reads `UserSettings.aiProviderConfigurations.currentValue` fresh on every `streamResponse` call rather than resolving once when the descriptor was built.
**Rationale**: per the source's own doc comment, "an extension may hold a descriptor for as long as it likes, and what the user has configured now is what a request can actually reach."
**Approved**: pending

**Decision**: every `AIChatContext` `streamResponse` builds omits an explicit `maxTokens`, so every request uses `AIChatContext.init`'s default of `4096` regardless of the resolved descriptor's own `maxInputTokens` (which can be a real, larger context window reported by `AIModelCatalog`).
**Rationale**: not stated in the source. The context window recorded on the descriptor is informational — communicated to `vscode.lm` callers as the model's ceiling — but nothing in `streamResponse` reads it back when building the request, so the request's actual token budget is a fixed default rather than a computation derived from the same catalog lookup `descriptor(for:)` performs.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's only responsibilities are listing descriptors and adapting one request/response shape to another; it performs no transport, no credential handling, and no plugin-loading logic of its own, reusing `AIProviderResolver`, `AIPluginManager`, and `PluginTransport` for all of that instead (see Overview). `unit-test-coverage` is partial: the given test suite covers `availableChatModels`' listing/ordering/skipping behavior and all three of `streamResponse`'s pre-plugin error paths, but no test in the given sources exercises the success path (`buildRequest` succeeding, `PluginTransport.run` streaming real events, or cancellation actually propagating). `explicit-error-handling` is partial: the two guard failures are explicit, typed, and `Equatable` (`ProviderError`), but `plugin-load-failure-collapsed` deliberately discards which of four distinct load failures occurred, trading diagnostic specificity for a simpler caller-facing contract. `secure-log-output` passes because the one potentially sensitive value logged, `justification`, is tagged `.private`, while `extensionIdentifier` is tagged `.public` (see Logging). `no-hardcoded-strings` fails because `ProviderError.description`'s two case bodies are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
