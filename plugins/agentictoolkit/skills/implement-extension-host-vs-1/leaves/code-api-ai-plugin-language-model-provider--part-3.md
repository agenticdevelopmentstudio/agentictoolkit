<!-- leaf: implement-extension-host-vs-1/code-api-ai-plugin-language-model-provider--part-3 · source: extension-host-vs-code-api-ai-plugin-language-model-provider.md -->

# AIPluginLanguageModelProvider — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pluginManager` | `AIPluginManager` | none (required) | Supplied to `init(pluginManager:)`; the sole source of plugin descriptors, templates, and loaded plugin instances. |
| `model` | `LanguageModelChatDescriptor` | none (required) | The descriptor `streamResponse` is asked to route; only its `id` field is consulted. |
| `messages` | `[ExtensionLanguageModelMessage]` | none (required) | The conversation history to send; mapped verbatim (minus `name`) to `[AIChatMessage]`. |
| `justification` | `String?` | none (optional) | Free text from `options.justification` (`vscode.d.ts`); recorded to the log only, per **justification-recorded-only**. |
| `extensionIdentifier` | `String` | none (required) | Identifies the calling extension for the justification log line; passed straight through with no validation. |
| `UserSettings.aiProviderConfigurations` | `UserSetting<[AIProviderConfiguration]>`, settings key `"aiplugin.configurations"` | `[]` | Read by `availableChatModels` and `resolveConfiguration(for:)`; observed by the `configurationsObserver` set up in `init`. |
| `AIModelCatalog.shared` | `AIModelCatalog` (singleton) | the loaded shared catalog | Consulted by `descriptor(for:configuration:template:)` for `contextWindow`; falls back to `defaultMaxInputTokens` (`4096`) when the model/template pair is unlisted. |

## Localization

`ProviderError.description`'s two case bodies — `"no configured language model with id '<id>'"` and `"the plugin '<identifier>' is not available"` — are hardcoded English string literals with no localization key, `String(localized:)` call, or String Catalog entry. Both strings are produced by `CustomStringConvertible`, the description a caller (ultimately the extension-host seam that turns a thrown `ProviderError` into a JavaScript-visible error) would surface. `LanguageModelChatDescriptor.name`'s `"<configuration.name> · <model>"` format uses a fixed `"·"` separator glyph around two data-derived strings (the user's own configuration name and a model identifier), not translatable prose.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `no configured language model with id '<id>'` | `ProviderError.unknownModel`'s `description`, surfaced when a descriptor's id no longer resolves. |
| (none — literal only) | `the plugin '<identifier>' is not available` | `ProviderError.pluginUnavailable`'s `description`, surfaced when the resolved plugin cannot be reached. |

## Privacy

- **Data collected**: `AIPluginLanguageModelProvider` itself collects no data beyond what its callers already hand it: `justification` (free text an extension supplies explaining why it wants a model) and `extensionIdentifier` are read only to log them, per **justification-recorded-only**. `messages` (the conversation) and the resolved configuration's values are forwarded into the request the plugin builds, but not retained by this type. No credential or secret value is read or handled here — those are resolved and injected by `AIProviderResolver`/`AIProviderConfigStore`, which this type calls but does not duplicate.
- **Storage**: `AIPluginLanguageModelProvider` performs no storage of its own; `UserSettings.aiProviderConfigurations` is owned and persisted elsewhere.
- **Transmission**: `messages`, the resolved model name, and the resolved configuration's values are transmitted to the external provider, but the transmission itself is performed by `PluginTransport`/the loaded `AIPlugin`, not by this file directly.
- **Retention**: this file retains nothing beyond the lifetime of one `streamResponse` call's local variables; the one value it logs (`justification`) persists only per OSLog's own system-level retention policy, which this file does not configure.

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
