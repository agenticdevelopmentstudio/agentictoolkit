<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins · source: ai-plugin-runtime-features-ai-plugins.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-features-ai-plugins#<slug>`):

- `coordinator-identity` MUST
- `coordinator-plugin-manager` MUST
- `coordinator-startup-order` MUST
- `coordinator-settings-panel` MUST
- `config-provider-shape` MUST
- `config-provider-resolved-values` MUST
- `chat-backend-conformance` MUST
- `chat-backend-weak-provider` MUST
- `chat-backend-is-ready` MUST
- `chat-backend-ready-changes` MUST
- `chat-backend-notify` MUST
- `chat-backend-deinit-cleanup` MUST
- `chat-backend-send-messages-text` MUST
- `chat-backend-send-messages-tools` MUST
- `chat-backend-cancellation` MUST
- `chat-backend-no-plugin` MUST
- `chat-backend-build-request-failure` MUST
- `chat-backend-transport-failure` MUST
- `chat-backend-message-mapping` MUST
- `provider-session-graph` MUST
- `provider-session-lifetime` MUST
- `plugin-config-store-key-convention` MUST
- `plugin-config-store-secret-routing` MUST
- `plugin-config-store-model-default` MUST
- `plugin-config-store-config-values` MUST
- `provider-configuration-identity` MUST
- `provider-configuration-unique-name` MUST
- `provider-settings-list` MUST
- `provider-settings-selection` MUST
- `provider-settings-guards` MUST

# AI Plugin Runtime Features (AIPlugins)

## Overview

The `macOS/Features/AIPlugins` folder is the runtime layer that turns a
discovered `AIPluginKit.AIPlugin` bundle into something a chat UI can talk to.
It has three responsibilities: (1) `AIPluginsCoordinator` owns the
`AIPluginManager` for the app's lifetime and runs discovery, one-time legacy
migration, and first-run seeding, in that order, at construction; (2)
`AIProviderConfiguration` / `AIProviderConfigStore` / `AIProviderResolver` /
`AIProviderDefaults` / `AIProviderMigration` / `PluginConfigStore` model a
user's named provider configurations, persist their field values (secrets
routed to the Keychain), and resolve a configuration back into the plugin
identifier, model, and value bag a request needs; and (3) two parallel
`ChatConfigProvider` + chat-engine pairs drive an actual conversation through
a plugin — the deprecated `ChatBackend`-based path (`AIPluginChatBackend`,
`AIProviderChatSession`, `PluginChatConfigProvider`,
`SingleConfigurationChatConfigProvider`) riding `ChatBackendSession`, and the
current `ChatSession`-based path (`LocalChatSession`,
`MCPChatToolSource`) that also runs a bounded tool-calling loop. Every type
in this component is `@MainActor`, an `@unchecked Sendable` class with its
own lock, or a plain `Sendable` value — never left unspecified.

## Behavioral Requirements

### AIPluginsCoordinator

- **coordinator-identity**: `AIPluginsCoordinator` MUST be a `@MainActor`
  subclass of `AppFeature`, so constructing one registers it with
  `AppFeatureRegistry.shared` (inherited from `AppFeature.init()`).
- **coordinator-plugin-manager**: `AIPluginsCoordinator.init(appName:additionalSearchPaths:)`
  MUST construct exactly one `AIPluginManager` (exposed as the public
  `pluginManager` property) scoped to `appName` and `additionalSearchPaths`.
- **coordinator-startup-order**: `AIPluginsCoordinator.init` MUST call, in
  order, `pluginManager.discoverPlugins()`, then
  `AIProviderMigration.runIfNeeded(pluginManager:)`, then
  `AIProviderDefaults.seedIfNeeded(pluginManager:)` — migration and default
  seeding both read `pluginManager.descriptors` / `availableTemplates`, which
  are empty until discovery has run.
- **coordinator-settings-panel**: `settingsPanel()` MUST return a fresh
  `AIPanelViewController` constructed with the coordinator's `pluginManager`.

### ChatConfigProvider (protocol)

- **config-provider-shape**: A `ChatConfigProvider` conformer MUST expose
  `selectedPluginIdentifier: String`, `selectedModel: String`, and
  `pluginConfigValues: [String: String]` as `@MainActor`-isolated read-only
  properties.
- **config-provider-resolved-values**: `pluginConfigValues` MUST be the
  already-resolved `[key: value]` map a plugin reads through
  `AIPluginConfig`, secrets included — the consuming chat backend MUST NOT
  read the Keychain or any settings store itself.

### AIPluginChatBackend

- **chat-backend-conformance**: `AIPluginChatBackend` MUST conform to
  `ChatBackend` and MUST be declared `@unchecked Sendable`; it is not itself
  `@MainActor`-isolated — every access to `pluginManager` or `configProvider`
  MUST happen inside a `MainActor.run` block, and every mutation of
  `subscribers` MUST happen while holding `lock` (`NSLock`).
- **chat-backend-weak-provider**: `AIPluginChatBackend` MUST hold
  `configProvider` `weak`; when it has been deallocated, `isReady`,
  `isReadyChanges()`, `notifyReadyChanged()`, and `sendMessages` MUST treat
  the missing provider as `selectedPluginIdentifier == ""`,
  `selectedModel == ""`, and `pluginConfigValues == [:]`.
- **chat-backend-is-ready**: `isReady` MUST be `true` if and only if
  `configProvider?.selectedPluginIdentifier` is non-empty; an empty string or
  a `nil` provider MUST yield `false`.
- **chat-backend-ready-changes**: `isReadyChanges()` MUST return an
  independent `AsyncStream<Bool>` per call; each stream MUST yield the
  current readiness value once for its new subscriber (computed
  asynchronously via `MainActor.run` right after subscription) and MUST yield
  again whenever `notifyReadyChanged()` runs while the subscriber is still
  registered.
- **chat-backend-notify**: `notifyReadyChanged()` MUST recompute readiness
  once and multicast that single value to every currently-registered
  subscriber; it MUST be a no-op cost (no recomputation broadcast to nobody)
  when `subscribers` is empty, and it is the host's responsibility to call
  it after a plugin- or credential-selection change — the backend MUST NOT
  observe those changes on its own.
- **chat-backend-deinit-cleanup**: `deinit` MUST finish every still-registered
  subscriber's continuation and clear `subscribers`, under `lock`.
- **chat-backend-send-messages-text**: `sendMessages(_:)` MUST build one
  `AIChatContext` from the current config-provider snapshot and an empty tool
  list, drive it through `PluginTransport.run`, and MUST forward only
  `.textDelta` payloads into the returned `AsyncThrowingStream<String, Error>`
  — `.toolUse` and `.end` events from the underlying stream MUST be dropped
  for this overload.
- **chat-backend-send-messages-tools**: `sendMessages(_:tools:)` MUST map
  every decoded `AIStreamEvent` 1:1 onto a `ChatStreamEvent`
  (`.textDelta` → `.textDelta`, `.toolUse(id,name,argumentsJSON)` →
  `.toolUse(id:name:argumentsJSON:)`, `.end(stopReason)` → `.end(stopReason:)`)
  with no other transformation.
- **chat-backend-cancellation**: Cancelling either returned stream's
  consuming task (via `onTermination`) MUST cancel the backing `Task` created
  by `Self.drive`.
- **chat-backend-no-plugin**: When `configProvider?.selectedPluginIdentifier`
  is empty, or `pluginManager.loadPlugin(identifier:)` throws for the
  resolved identifier, `makeInputs` MUST produce a `RequestInputs` whose
  `plugin` is `nil`, and `Self.drive` MUST finish the stream by throwing
  `AIPluginChatBackend.AIPluginChatError.pluginNotAvailable` without invoking
  `PluginTransport.run` at all. The three distinct failure reasons
  `AIPluginManager.AIPluginError` can throw for `loadPlugin` (not found, bundle
  load failure, missing/invalid principal class) are collapsed into the same
  single `pluginNotAvailable` case here — `AIPluginChatBackend` does not
  distinguish them.
- **chat-backend-build-request-failure**: If the resolved plugin's
  `buildRequest(_:)` throws, `Self.drive` MUST finish the stream by throwing
  that error unchanged (no wrapping), without ever calling
  `PluginTransport.run`.
- **chat-backend-transport-failure**: If `PluginTransport.run` throws while
  iterating, `Self.drive` MUST propagate that error unchanged as the stream's
  failure.
- **chat-backend-message-mapping**: `aiMessage(for:)` MUST translate a
  `ChatBackendMessage` to an `AIChatMessage` field-for-field (`role` via
  `aiRole(for:)`, `content`, `toolUseId`, `toolName`, `toolArgumentsJSON`,
  `toolIsError`), and `aiToolSpec(for:)` MUST translate a `ToolDefinition` to
  an `AIToolSpec` field-for-field (`name`, `description`,
  `parametersJSONSchema`) with no content transformation.

### AIProviderChatSession

- **provider-session-graph**: `AIProviderChatSession.init(configuration:pluginManager:)`
  MUST construct, in order, a `SingleConfigurationChatConfigProvider` pinned
  to `configuration`, an `AIPluginChatBackend` wired to that provider, and an
  `AIChatViewModel` wrapping a `ChatBackendSession(backend:)` built from that
  backend.
- **provider-session-lifetime**: `AIProviderChatSession` MUST hold a strong
  reference to its `backend`; since `AIPluginChatBackend` holds its
  `configProvider` weakly, this is the only thing that keeps the provider
  object alive for as long as the session exists.

### PluginConfigStore

- **plugin-config-store-key-convention**: `PluginConfigStore` MUST be the
  single place that derives per-plugin setting keys:
  `fieldKey(plugin:field:)` MUST return `"aiplugin.<identifier>.field.<key>"`
  and `modelKey(plugin:)` MUST return `"aiplugin.<identifier>.model"`.
- **plugin-config-store-secret-routing**: `fieldSetting(plugin:field:)` MUST
  construct its `UserSetting<String>` with `isSecure: field.isSecret` — a
  `.secret` field's value MUST be routed to the Keychain-backed store, and a
  `.text` field's value MUST be routed to the plain store.
- **plugin-config-store-model-default**: `selectedModel(for:)` MUST return
  the stored model value when non-empty, else `descriptor.resolvedDefaultModel`.
- **plugin-config-store-config-values**: `configValues(for:)` MUST return
  every field's current stored value keyed by `field.key`, plus a `"model"`
  entry from `selectedModel(for:)`.

### AIProviderConfiguration

- **provider-configuration-identity**: `AIProviderConfiguration` MUST be
  `Codable`, `Sendable`, `Identifiable`, `Equatable`, and `Hashable`, with an
  immutable `id` (defaulted to a fresh `UUID()`), a mutable `name`, and
  immutable `pluginIdentifier` and `templateId`.
- **provider-configuration-unique-name**: `uniqueName(_:avoiding:)` MUST
  return `base` unchanged when `base` is not in `taken`; otherwise it MUST
  return `"\(base) 2"`, `"\(base) 3"`, … — the first suffixed form not
  present in `taken`.

### UserSettings (AIProviderConfiguration.swift)

- **provider-settings-list**: `UserSettings.aiProviderConfigurations` MUST
  persist the ordered `[AIProviderConfiguration]` list under
  `"aiplugin.configurations"`, defaulting to `[]`.
- **provider-settings-selection**: `UserSettings.selectedAIProviderConfigurationId`
  MUST persist the selected configuration's `id.uuidString` under
  `"aiplugin.selectedConfigurationId"`, defaulting to `""`; an empty value
  MUST be interpreted by every consumer in this component as "no provider
  selected", not as an invalid reference.
- **provider-settings-guards**: `UserSettings.aiProvidersMigrated` and
  `UserSettings.aiDefaultConfigSeeded` MUST each persist an independent
  one-time boolean guard (`"aiplugin.migratedToConfigurations"` and
  `"aiplugin.defaultConfigSeeded"` respectively, both defaulting to `false`)
  so migration and default-seeding are tracked, and can each run at most
  once, independently of one another.

