<!-- leaf: implement-extension-host-vs-1/code-api-ai-plugin-language-model-provider--part-2 · source: extension-host-vs-code-api-ai-plugin-language-model-provider.md -->

# AIPluginLanguageModelProvider — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-ai-plugin-language-model-provider--part-2#<slug>`):

- `main-actor-isolation` MUST
- `protocol-conformance` MUST
- `injected-plugin-manager` MUST
- `configuration-observer-wiring` MUST
- `no-notification-on-construction` MUST
- `every-configured-model-listed` MUST
- `deterministic-model-order` MUST
- `unresolvable-template-skipped` MUST
- `descriptor-id-format` MUST
- `descriptor-id-separator-safety` MUST
- `descriptor-name` MUST
- `descriptor-vendor` MUST
- `descriptor-family` MUST
- `descriptor-version` MUST
- `descriptor-max-input-tokens` MUST
- `justification-recorded-only` MUST
- `justification-privacy` MUST
- `no-log-when-justification-absent` MUST
- `model-id-parse-failure` MUST
- `model-id-unknown-configuration` MUST
- `configuration-reread-per-call` MUST
- `plugin-resolution-failure` MUST
- `plugin-load-failure-collapsed` MUST
- `request-model-override` MUST
- `no-system-prompt` MUST
- `no-tools-forwarded` MUST
- `default-max-tokens` MUST
- `build-request-error-propagation` MUST
- `transport-delegation` MUST
- `response-part-mapping` MUST
- `message-role-mapping` MUST
- `message-name-dropped` MUST
- `stream-single-consumption` MUST
- `stream-cancellation-propagation` MUST
- `no-instance-caching` MUST
- `unknown-model-caller-guidance` SHOULD
- `model-name-membership` MUST

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

