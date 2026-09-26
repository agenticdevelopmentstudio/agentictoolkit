---
id: e886e448-6aa5-4359-979d-49fba713ab2a
title: AI Plugin Runtime Features (AIPlugins)
domain: agentictoolkit://cookbook/macos/features/ai-plugins
type: ingredient
version: 1.0.3
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Wires AIPluginManager-discovered plugins into chat sessions: per-configuration
  storage, one-time migration, first-run defaults, template resolution, and two ChatSession/ChatBackend
  runtimes.'
platforms:
- swift
- macos
tags:
- ai-plugins
- chat-session
- configuration
- runtime
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

### AIProviderConfigStore

- **config-store-key-delegation**: `AIProviderConfigStore.fieldKey(config:field:)`
  and `modelKey(config:)` MUST delegate to `AIProviderConfigKeys`, producing
  `"aiplugin.config.<uuid>.field.<key>"` and
  `"aiplugin.config.<uuid>.model"` respectively.
- **config-store-secret-routing**: `fieldSetting(config:field:)` MUST
  construct its `UserSetting<String>` with `isSecure: field.isSecret`.
- **config-store-model-default**: `selectedModel(config:template:)` MUST
  return the stored model value when non-empty, else
  `template.resolvedDefaultModel`.
- **config-store-values-overlay**: `configValues(for:template:fields:)` MUST
  start from `template.defaultValues`, then for each field overlay the
  stored value into the result UNDER TWO CONDITIONS: the field `isSecret`
  (always overlaid, even when the stored value is empty), or the stored
  value is non-empty. A field that is not secret and whose stored value is
  empty MUST NOT overwrite a template default for that key. The result MUST
  always include a `"model"` entry from `selectedModel(config:template:)`.
- **config-store-seed**: `seed(config:template:fields:)` MUST, for each
  field that has an entry in `template.defaultValues`, write that default
  into the field's stored setting; a field with no corresponding template
  default MUST be left at its setting's own default (`""`). It MUST also set
  the model setting to `template.resolvedDefaultModel`.
- **config-store-clear**: `clearStoredValues(config:fields:)` MUST reset
  every given field's stored value to `""` and the configuration's model
  setting to `""`; because a secret field's `UserSetting` has
  `isSecure: true`, writing `""` MUST remove that value from the Keychain.
  `clearStoredValues` MUST accept no `template` parameter, so it remains
  callable even when the configuration's template no longer resolves (a
  removed plugin or a renamed template).

### AIProviderDefaults

- **defaults-guarded-once**: `seedIfNeeded(pluginManager:)` MUST return
  immediately without side effects once `UserSettings.aiDefaultConfigSeeded`
  is `true`; otherwise it MUST set `aiDefaultConfigSeeded` to `true` before
  returning, regardless of whether seeding actually produced a configuration.
- **defaults-only-when-empty**: `seedIfNeeded` MUST NOT write to
  `UserSettings.aiProviderConfigurations` when that list is already
  non-empty — an existing user- or migration-created list MUST be left
  untouched.
- **defaults-template-lookup**: `seedIfNeeded` MUST look up a template whose
  `id == "claude-local"` (`AIProviderDefaults.defaultTemplateId`) among
  `pluginManager.availableTemplates`; when no such template is advertised, it
  MUST leave `aiProviderConfigurations` empty.
- **defaults-seeded-configuration**: When the `claude-local` template is
  found and the list is empty, `seedIfNeeded` MUST build one
  `AIProviderConfiguration` named after the template's `displayName`, seed
  its stored field values and model via `AIProviderConfigStore.seed`, and set
  `aiProviderConfigurations.value` to the single-element array containing it.
- **defaults-leaves-unselected**: `seedIfNeeded` MUST NOT set
  `UserSettings.selectedAIProviderConfigurationId` — the seeded configuration
  is deliberately left unselected so behavior matches the daemon's
  zero-config "Default (Claude CLI)" path exactly.

### AIProviderMigration

- **migration-plan-is-pure**: `AIProviderMigration.plan(descriptors:legacySelected:oldValues:)`
  MUST be a pure function of its arguments — it MUST perform no I/O and MUST
  NOT read or write any `UserSetting`.
- **migration-template-selection**: For each descriptor, `plan` MUST select
  the template whose `id` matches `legacyTemplateId[descriptor.identifier]`
  when that lookup succeeds and the descriptor advertises a template with
  that id, else the first entry of `descriptor.resolvedTemplates`.
- **migration-inclusion-rule**: `plan` MUST include a descriptor in the
  output only if at least one of the following holds: (a) some secret field
  has a non-empty legacy value (`hasSecret`), (b) the descriptor's identifier
  equals `legacySelected` and `legacySelected` is non-empty (`isSelected`),
  or (c) some non-secret field's legacy value is non-empty and differs from
  that field's template default (`hasCustomField`). A descriptor matching
  none of these MUST be skipped entirely — no configuration, field write, or
  model write MUST be produced for it.
- **migration-name-dedup**: `plan` MUST name each produced configuration via
  `AIProviderConfiguration.uniqueName(descriptor.displayName, avoiding:)`,
  avoiding the names already assigned to configurations earlier in the same
  plan.
- **migration-field-write-rule**: For an included descriptor, `plan` MUST
  emit a `FieldWrite` for a field only when
  `values[field.key] ?? template.defaultValues[field.key] ?? ""` is
  non-empty; a field that resolves to empty after that fallback MUST NOT
  produce a `FieldWrite`.
- **migration-model-write-rule**: For an included descriptor, `plan` MUST
  emit exactly one model write per configuration, using
  `values["model"]` when present and non-empty, else
  `template.resolvedDefaultModel`.
- **migration-selected-id**: `plan.selectedId` MUST be set to the newly
  created configuration's `id.uuidString` for the (at most one) descriptor
  where `isSelected` is true, and MUST remain `""` otherwise.
- **migration-run-once**: `runIfNeeded(pluginManager:)` MUST return
  immediately, performing no writes, once `UserSettings.aiProvidersMigrated`
  is `true`.
- **migration-apply**: When migration has not yet run, `runIfNeeded` MUST
  build a plan from `pluginManager.descriptors`,
  `PluginConfigStore.selectedPluginSetting().currentValue`, and
  `PluginConfigStore.configValues(for:)`, then apply every `fieldWrites`
  entry (via a fresh `UserSetting<String>` keyed by
  `AIProviderConfigStore.fieldKey` with `isSecure: write.isSecret`) and every
  `modelWrites` entry (via `AIProviderConfigStore.modelKey`), then set
  `UserSettings.aiProviderConfigurations` to `plan.configurations` (even when
  that array is empty), then set
  `UserSettings.selectedAIProviderConfigurationId` to `plan.selectedId` ONLY
  when `plan.selectedId` is non-empty (an empty `plan.selectedId` MUST leave
  the existing selection setting untouched), and finally set
  `UserSettings.aiProvidersMigrated` to `true`.
- **migration-legacy-values-untouched**: `runIfNeeded` MUST NOT delete,
  clear, or overwrite any legacy `PluginConfigStore`-keyed setting
  (`"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, or
  `"aiplugin.selectedPlugin"`) as part of migrating it — it only reads them.
- **migration-legacy-secret-retained**: after `AIProviderMigration.runIfNeeded`
  copies a legacy secret (`"aiplugin.<identifier>.field.<key>"`, written with
  `isSecure: true`) into the new per-configuration key, the legacy Keychain
  entry MUST remain in place; no code path removes it.

### AIProviderResolver

- **resolver-shape**: `AIProviderResolver.resolve(_:manager:)` MUST return an
  optional `Resolved` value carrying `pluginIdentifier`, `model`, `values`,
  and `fields`.
- **resolver-descriptor-lookup**: `resolve` MUST return `nil` when
  `manager.descriptor(for: config.pluginIdentifier)` returns `nil` (the
  plugin is no longer installed/discovered).
- **resolver-fails-closed-on-template**: `resolve` MUST return `nil` when the
  resolved descriptor's `resolvedTemplates` contains no template whose `id`
  equals `config.templateId`. `resolve` MUST NOT fall back to
  `resolvedTemplates.first` in this case — doing so would silently bind the
  configuration's stored credentials and model to an unrelated provider
  template.
- **resolver-values**: When both lookups succeed, `resolve` MUST return
  `values` from `AIProviderConfigStore.configValues(for:template:fields:)`
  and `model` from `AIProviderConfigStore.selectedModel(config:template:)`,
  using `fields = descriptor.fields(for: template)`.

### LocalChatSession

- **local-session-conformance**: `LocalChatSession` MUST conform to
  `ChatSession` and MUST be declared `@unchecked Sendable`; `history` and
  `continuation` MUST be accessed only while holding `lock` (`NSLock`), and
  the busy flag MUST be accessed only through `turnActiveMutex`
  (`Synchronization.Mutex<Bool>`).
- **local-session-events-initial**: `events()` MUST return an `AsyncStream`
  that immediately yields `.stateChanged(.ready)` to its subscriber before
  any turn runs.
- **local-session-single-subscriber**: `events()` MUST replace any
  previously stored continuation with the new one on each call — this
  component supports at most one live subscriber's continuation at a time.
- **local-session-send-busy-guard**: `send(_:)` MUST be a silent no-op —
  emitting no event and starting no turn — when a turn is already active
  (`turnActiveMutex` holds `true`); otherwise it MUST set the busy flag and
  start `runTurn` as a new tracked `Task`.
- **local-session-interrupt**: `interrupt()` MUST cancel the live turn's
  `Task` and MUST reset the busy flag to `false`, allowing an immediate
  subsequent `send(_:)` even if the cancelled turn's own cleanup has not yet
  run.
- **local-session-clear**: `clear()` MUST remove all entries from `history`
  and MUST NOT affect an in-flight turn.
- **local-session-close**: `close()` MUST cancel the live turn, reset the
  busy flag, emit `.stateChanged(.closed)`, and finish the stored
  continuation, ending `events()`.
- **local-session-turn-start**: `runTurn(userText:)` MUST emit
  `.userMessage` for the user's text, append it to `history` as an
  `AIChatMessage(role: .user, ...)`, and emit `.stateChanged(.responding)`
  before doing anything else.
- **local-session-no-plugin**: When `resolvePlugin()` returns `nil`,
  `runTurn` MUST emit `.turnFailed(ChatError(message: "No AI provider is
  configured.", isRetryable: false))` followed by `.stateChanged(.ready)`,
  and MUST NOT emit `.responseStarted` or attempt any request. The user's
  already-appended history entry MUST remain in `history`.
- **local-session-tool-loop-bound**: `runTurn` MUST iterate the
  build-request/stream/tool-execute cycle at most `maxToolIterations` (`8`)
  times per turn; when the model still requests tools on the final
  permitted iteration, the loop MUST end after that iteration without
  starting a ninth, and without emitting any distinct "budget exceeded"
  signal.
- **local-session-stream-mapping**: Within one iteration, `runTurn` MUST
  emit `.responseStarted` the first time a `.textDelta` arrives (once per
  turn) and MUST emit `.responseDelta` for every `.textDelta` chunk; it MUST
  collect every `.toolUse` event into `pendingTools` and emit
  `.toolCall(phase: .started)` for it; it MUST ignore `.end` events from the
  stream (never surfacing the provider's `stopReason` for that event).
- **local-session-cooperative-cancellation**: `runTurn` MUST check
  `Task.isCancelled` between stream events and `break` out of the inner
  event loop when cancelled, without cancelling mid-event.
- **local-session-partial-text-kept**: After an iteration's stream ends
  (normally or via the cancellation break), if the accumulated `turnText` is
  non-empty, `runTurn` MUST append it to `history` as an assistant message
  even when the iteration was cut short.
- **local-session-tool-turn-end**: `runTurn` MUST end the iteration loop
  (without a further plugin call) once `pendingTools.isEmpty` is true, or
  once `toolSource` is `nil` even if `pendingTools` is non-empty.
- **local-session-tool-execution**: When continuing the loop,
  `runTurn` MUST execute every pending tool call sequentially, in the order
  received: append a `.toolUse` history entry, `await`
  `toolSource!.callTool(name:argumentsJSON:)`, append a `.toolResult` history
  entry carrying the result's `isError`, and emit
  `.toolCall(phase: .completed)` — before moving to the next pending tool.
- **local-session-turn-finish**: When the iteration loop ends, `runTurn`
  MUST emit `.responseFinished(stopReason: nil)` if and only if
  `.responseStarted` was emitted at least once during the turn, always
  passing `stopReason: nil` (the provider's own stop reason is never
  surfaced), then MUST emit `.stateChanged(.ready)`.
- **local-session-error-path**: Any error thrown by `plugin.buildRequest`,
  by the event-stream factory, or propagated from `PluginTransport.run`
  MUST end the turn by emitting `.turnFailed(ChatError(from: error,
  isRetryable: true))` — always `isRetryable: true` regardless of the
  error's underlying cause — followed by `.stateChanged(.ready)`.
- **local-session-with-tools**: The private `AIChatContext.withTools(_:)`
  helper MUST return a copy of the context with `tools` replaced by the
  mapped `AIToolSpec`s and every other field (`messages`, `model`,
  `systemPrompt`, `maxTokens`, `config`) unchanged.

### MCPChatToolSource

- **mcp-tool-source-conformance**: `MCPChatToolSource` MUST conform to
  `ChatToolSource` and MUST be declared `@unchecked Sendable`; its
  `registry` and `activeServerIds` MUST be fixed at initialization time (a
  snapshot, not a live-observed set).
- **mcp-tool-source-namespacing**: `toolDefinitions()` and `callTool` MUST
  identify a tool by `"<server-name>__<tool-name>"` (`namespaced`, separator
  `"__"`), built from `registry.tools(forIds: activeServerIds)`.
- **mcp-tool-source-schema-encoding**: `toolDefinitions()` MUST build one
  `ToolDefinition` per registry pair whose `inputSchema` JSON-encodes
  successfully, and MUST silently drop (via `compactMap`) any pair whose
  schema fails to encode — no error is surfaced for a dropped pair.
- **mcp-tool-source-unknown-tool**: `callTool(name:argumentsJSON:)` MUST
  return `("Unknown tool: <name>", true)` when no currently-registered pair's
  namespaced name matches `name`.
- **mcp-tool-source-dispatch**: `callTool` MUST re-fetch
  `registry.tools(forIds: activeServerIds)` on every call (not cached from
  `toolDefinitions()`), find the matching pair, and invoke
  `pair.client.callTool(name:arguments:)`.
- **mcp-tool-source-error-mapping**: `callTool` MUST convert any error thrown
  by the underlying MCP call into `("Tool error: <error.localizedDescription>",
  true)`.
- **mcp-tool-source-content-flatten**: `callTool` MUST join only the `.text`
  content items of a successful call's response with `"\n"`
  (`flatten`), and MUST silently drop any non-text content item.
- **mcp-tool-source-argument-validation**: NEEDS REVIEW: Not implemented in source. `callTool` decodes `argumentsJSON` with `try?` and, on a decode failure, silently substitutes `nil` arguments rather than surfacing a validation error — a malformed tool-call payload from the model is forwarded to `pair.client.callTool` as though no arguments were supplied, instead of being reported back as a tool error the model or user could act on.

### PluginChatConfigProvider / SingleConfigurationChatConfigProvider

- **provider-defaults-on-unresolved**: Both `PluginChatConfigProvider` and
  `SingleConfigurationChatConfigProvider` MUST return `""` for
  `selectedPluginIdentifier`, `""` for `selectedModel`, and `[:]` for
  `pluginConfigValues` whenever the underlying `AIProviderResolver.resolve`
  call returns `nil` — neither type MUST throw.
- **plugin-chat-config-provider-selection**: `PluginChatConfigProvider`'s
  `resolved` MUST derive its configuration from
  `UserSettings.selectedAIProviderConfigurationId`: an empty string, a string
  that does not parse as a `UUID`, or a `UUID` with no matching entry in
  `UserSettings.aiProviderConfigurations` MUST each result in `resolved ==
  nil`.
- **single-configuration-provider-pinning**: `SingleConfigurationChatConfigProvider`
  MUST resolve against the exact `AIProviderConfiguration` passed to its
  initializer, independent of `UserSettings.selectedAIProviderConfigurationId`,
  on every access — an edit made elsewhere to the same configuration's
  stored fields or model MUST be visible on the next access, since `resolved`
  is recomputed live rather than cached.

## Appearance

Not applicable — this is the AI Plugins runtime feature (plugin discovery,
configuration storage, and two chat-session/backend implementations), not a
visual component.

## States

Not applicable — this is the AI Plugins runtime feature, not a visual
component. The runtime's own state machines (`ChatSessionState`'s
`.ready`/`.responding`/`.closed` transitions driven by `LocalChatSession` and
`ChatBackendSession`, and the `AIPluginChatBackend.isReadyChanges()` boolean
readiness stream) are specified under Behavioral Requirements above, not
here.

## Accessibility

Not applicable — this is the AI Plugins runtime feature, not a visual
component; none of the given sources render UI (`AIPluginsCoordinator`
imports `AppKit` only to construct menu/status-item contributions and hand
back an `AIPanelViewController`, never drawing anything itself).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| aiplugins-001 | coordinator-startup-order | Construct `AIPluginsCoordinator(appName: "Test")` | `pluginManager.discoverPlugins()` runs before `AIProviderMigration.runIfNeeded` and `AIProviderDefaults.seedIfNeeded`, per the fixed call order in `AIPluginsCoordinator.init` |
| aiplugins-002 | chat-backend-is-ready | `configProvider.selectedPluginIdentifier == ""` | `await backend.isReady == false` |
| aiplugins-003 | chat-backend-is-ready | `configProvider.selectedPluginIdentifier == "com.x.plugin"` | `await backend.isReady == true` |
| aiplugins-004 | chat-backend-no-plugin | `configProvider.selectedPluginIdentifier == ""`, call `sendMessages([...])` | Returned stream throws `AIPluginChatBackend.AIPluginChatError.pluginNotAvailable`; zero text chunks yielded |
| aiplugins-005 | local-session-stream-mapping, local-session-turn-finish (traced to `LocalChatSessionTests.streamsAndFinishes`) | `send("hi")` with a fake `eventStreamFactory` yielding `.textDelta("Hel")`, `.textDelta("lo")`, `.end(stopReason: "end_turn")` | Events include `.responseStarted` before the first `.responseDelta`; concatenated delta text `== "Hello"`; a terminal `.responseFinished` fires; `.stateChanged(.ready)` follows |
| aiplugins-006 | local-session-send-busy-guard | Call `session.send("first")`, then `session.send("second")` before the first turn's `runTurn` completes | The second call produces no `.userMessage`/`.responseStarted` pair in `events()` — it is dropped |
| aiplugins-007 | local-session-no-plugin | `resolvePlugin` returns `nil`, then `send("hi")` | Events emit `.turnFailed(ChatError(message: "No AI provider is configured.", isRetryable: false))` then `.stateChanged(.ready)`; no `.responseStarted` |
| aiplugins-008 | config-store-seed, config-store-values-overlay (traced to `AIProviderConfigStoreTests.seedPrefills` / `overlay`) | `seed(config:template:fields:)` with a template whose `defaultValues == ["baseURL": "https://api.groq.com/openai/v1"]` and a secret `apiKey` field, then read `configValues` | `values["baseURL"] == "https://api.groq.com/openai/v1"`, `values["model"] == "m1"`, `(values["apiKey"] ?? "").isEmpty == true`; after `fieldSetting(apiKey).value = "sk-test"`, `configValues()["apiKey"] == "sk-test"` |
| aiplugins-009 | resolver-fails-closed-on-template (traced to `AIProviderResolverTests.returnsNilForUnknownTemplate`) | `config.templateId == "renamed-away"`, a template the descriptor no longer advertises | `AIProviderResolver.resolve(config, manager:) == nil` |
| aiplugins-010 | migration-inclusion-rule (traced to `AIProviderMigrationTests.skipsEmpty`) | One descriptor, `legacySelected == ""`, `oldValues` returns `["apiKey": ""]` | `plan.configurations.isEmpty == true`, `plan.selectedId == ""` |
| aiplugins-011 | migration-inclusion-rule, migration-field-write-rule (traced to `AIProviderMigrationTests.migratesKeylessConfigured`) | A descriptor with a non-secret `baseURL` field, `legacySelected == ""`, `oldValues` returns `baseURL == "http://localhost:1234"` (differs from the template default `""`) | `plan.configurations.count == 1`; `plan.fieldWrites` contains an entry with `fieldKey == "baseURL"` and `value == "http://localhost:1234"` |
| aiplugins-012 | defaults-only-when-empty (traced to `AIProviderDefaultsTests.skipsWhenNotEmpty`) | `UserSettings.aiProviderConfigurations` already holds one entry; call `seedIfNeeded` | The list is unchanged (still exactly the pre-existing entry); `aiDefaultConfigSeeded.value == true` |
| aiplugins-013 | mcp-tool-source-unknown-tool | `callTool(name: "fs__nonexistent", argumentsJSON: Data())` where no registered pair namespaces to that name | Returns `("Unknown tool: fs__nonexistent", true)` |
| aiplugins-014 | mcp-tool-source-namespacing | Registry returns one pair `(client.name == "fs", tool.name == "read")` with an encodable `inputSchema` | `toolDefinitions()` returns exactly one `ToolDefinition` named `"fs__read"` |

## Edge Cases

- **Null/empty input**: An empty `selectedPluginIdentifier` MUST make
  `AIPluginChatBackend.isReady` `false` and MUST make `loadPlugin("")` throw,
  which `AIPluginChatBackend` maps to `pluginNotAvailable` (see
  chat-backend-no-plugin). An empty `legacySelected` MUST leave
  `plan.selectedId == ""` (see migration-selected-id). Empty
  `pluginConfigValues` MUST still build a valid `AIPluginConfig([:])` — an
  empty config bag is passed to the plugin unmodified; validating it is the
  plugin's concern, not this component's.
- **Null/empty input**: `MCPChatToolSource.callTool` decoding an empty or
  malformed `argumentsJSON` MUST NOT throw — `try? JSONDecoder().decode(...)`
  swallows the failure and passes `nil` arguments to the underlying MCP call
  (the open question on mcp-tool-source-argument-validation).
- **Boundary values**: `LocalChatSession.maxToolIterations == 8` is a hard
  cap. On the 8th iteration, if the model still returns `.toolUse` events,
  the outer loop MUST still end after that iteration completes — there is no
  9th plugin call, and no explicit signal to the UI that the cap was hit
  (see local-session-tool-loop-bound).
- **Concurrent access**: `LocalChatSession.send(_:)` calls made while a turn
  is active MUST be dropped, not queued (local-session-send-busy-guard).
  `AIPluginChatBackend.subscribers` MUST only ever be mutated under `lock`,
  so concurrent `isReadyChanges()`/`notifyReadyChanged()` calls from
  different threads MUST NOT corrupt the registry (chat-backend-conformance).
  `AIProviderConfigStore`, `AIProviderMigration`, `AIProviderDefaults`,
  `AIProviderResolver`, and `PluginConfigStore` are all `@MainActor`-isolated,
  so the compiler MUST reject a concurrent call from a non-main-actor
  context outright — no runtime race is possible for those types.
- **Concurrent access**: A new `isReadyChanges()` subscriber's "seed" value
  (computed asynchronously right after registration) and a concurrent
  `notifyReadyChanged()` call MAY race; the subscriber is guaranteed at
  least one yield of a readiness value, but the relative order between the
  seed and a concurrent notify SHOULD NOT be relied upon.
- **Error states**: A throw from `pluginManager.loadPlugin(identifier:)` (any
  of `AIPluginManager.AIPluginError`'s cases) MUST surface identically as
  `AIPluginChatBackend.AIPluginChatError.pluginNotAvailable` — the specific
  failure reason is not preserved (chat-backend-no-plugin). A throw from
  `plugin.buildRequest` or from `PluginTransport.run` MUST surface as
  `.turnFailed(ChatError(from: error, isRetryable: true))` in
  `LocalChatSession`, or as the stream's thrown error unchanged in
  `AIPluginChatBackend` — in both cases `isRetryable` is always reported
  `true` for `LocalChatSession`, regardless of whether the underlying cause
  is transient (a timeout) or permanent (a misconfigured plugin).
  `ChatBackendSession`'s analogous catch block does the same.
- **Error states**: `MCPChatToolSource.callTool` MUST convert any thrown MCP
  error into `("Tool error: <localizedDescription>", true)`, never
  propagating the original error type to the model (mcp-tool-source-error-mapping).
- **Offline/disconnected state**: None of the given sources perform network
  I/O directly — that is `PluginTransport`'s responsibility. From this
  component's perspective, a network failure (unreachable host, timeout, a
  non-2xx response) MUST surface through the same generic error path as any
  other thrown error: `LocalChatSession.runTurn`'s catch block and
  `AIPluginChatBackend.drive`'s `onFinish(error)` — neither distinguishes an
  offline/unreachable failure from any other kind of error.
- **Offline/disconnected state**: `MCPChatToolSource.callTool` re-fetches
  `registry.tools(forIds:)` on every call; if the MCP server for a
  previously-listed tool has disconnected between `toolDefinitions()` and
  `callTool`, the tool is simply absent from the re-fetched pairs and the
  call MUST return `("Unknown tool: <name>", true)` — identical to a tool
  that never existed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appName` | `String` | — (required) | Passed to `AIPluginsCoordinator.init` / `AIPluginManager.init`; used to derive the per-app plugins search path under Application Support. |
| `additionalSearchPaths` | `[URL]` | `[]` | Passed to `AIPluginsCoordinator.init`; extra directories `AIPluginManager` scans for `.aiplugin` bundles. |
| `resolvePlugin` | `@Sendable () async -> (any AIPlugin)?` | — (required) | Injected into `LocalChatSession.init`; resolves which plugin instance serves the next turn. |
| `makeContext` | `@Sendable ([AIChatMessage]) async -> AIChatContext` | — (required) | Injected into `LocalChatSession.init`; builds the per-turn `AIChatContext` from the current history snapshot. |
| `eventStreamFactory` | `LocalChatSession.EventStreamFactory` | `{ PluginTransport.run(spec: $0, plugin: $1) }` | Injected into `LocalChatSession.init`; the seam tests use to fake a plugin's response stream. |
| `toolSource` | `(any ChatToolSource)?` | `nil` | Injected into `LocalChatSession.init`; when `nil`, the tool loop never runs even if the plugin emits `.toolUse` events. |
| `registry` | `MCPServerRegistry` | — (required) | Passed to `MCPChatToolSource.init`; the source of active MCP servers and their tools. |
| `activeServerIds` | `Set<UUID>` | — (required) | Passed to `MCPChatToolSource.init`; a fixed snapshot of which servers' tools are exposed to the model. |
| `"aiplugin.configurations"` | `[AIProviderConfiguration]` (settings key) | `[]` | `UserSettings.aiProviderConfigurations` — the ordered list of configured providers. |
| `"aiplugin.selectedConfigurationId"` | `String` (settings key) | `""` | `UserSettings.selectedAIProviderConfigurationId` — empty means the daemon's zero-config Default path. |
| `"aiplugin.migratedToConfigurations"` | `Bool` (settings key) | `false` | `UserSettings.aiProvidersMigrated` — one-time migration guard. |
| `"aiplugin.defaultConfigSeeded"` | `Bool` (settings key) | `false` | `UserSettings.aiDefaultConfigSeeded` — one-time default-seeding guard. |
| `"aiplugin.config.<uuid>.field.<key>"` | `String` (settings key, secret-routed per field) | `""` | Per-configuration field value, via `AIProviderConfigKeys.fieldKey` / `AIProviderConfigStore.fieldSetting`. |
| `"aiplugin.config.<uuid>.model"` | `String` (settings key) | template's `resolvedDefaultModel` | Per-configuration selected model, via `AIProviderConfigKeys.modelKey`. |
| `"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, `"aiplugin.selectedPlugin"` | `String` (legacy settings keys) | `""` | Read (never written) by `AIProviderMigration.runIfNeeded` via `PluginConfigStore`; superseded by the per-configuration keys above. |

## Deep Linking

Not applicable: none of the given sources register a URL scheme, handle
`NSUserActivity`, or parse an incoming URL — the AI Plugins runtime has no
externally-addressable destinations.

## Localization

None of the given sources route their user-facing strings through
`NSLocalizedString` or `String(localized:)`; they are hardcoded English
literals, listed here as facts rather than as a marker per source fidelity:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `No AI provider is configured.` | `LocalChatSession.runTurn`'s `ChatError.message` when `resolvePlugin()` returns `nil` |
| (none — hardcoded literal) | `Unknown tool: <name>` | `MCPChatToolSource.callTool`'s error text when no pair matches the namespaced tool name |
| (none — hardcoded literal) | `Tool error: <error.localizedDescription>` | `MCPChatToolSource.callTool`'s error text when the underlying MCP call throws |

## Accessibility Options

Not applicable: the AI Plugins runtime has no UI and responds to no Rule 15
display accommodation (Reduce Motion, Increase Contrast, Differentiate
Without Color) in any of the given sources.

## Feature Flags

Not applicable: none of the given sources check a feature-flag value; every
behavioral branch (migration, default-seeding, the tool loop) is
unconditional given its own stated preconditions, not gated by a flag.

## Analytics

Not applicable: none of the given sources emit an analytics event; there is
no call to any event-logging API in this component.

## Privacy

- **Data collected**: Provider credentials and connection settings the user
  enters for a configuration — secret fields (e.g. an `apiKey`, kind
  `.secret`) and plain fields (e.g. a `baseURL`, kind `.text`), plus the
  chosen `model` — are the sensitive data this component stores and
  resolves. `ChatConfigProvider.pluginConfigValues` is explicitly documented
  as "secrets included."
- **Storage**: A field's `isSecret` (`AIPluginDescriptor.Field.Kind.secret`)
  routes its `UserSetting<String>` to construct with `isSecure: true`
  (`AIProviderConfigStore.fieldSetting`, `PluginConfigStore.fieldSetting`),
  which persists it to the Keychain rather than plain user defaults; a
  `.text` field is persisted to the plain (non-Keychain) settings store.
  Setting a secret field's value to `""` (via `clearStoredValues`) removes
  it from the Keychain.
- **Transmission**: This component never performs network I/O itself. It
  assembles the resolved value bag into an `AIPluginConfig` inside an
  `AIChatContext` and hands that to the selected plugin's `buildRequest(_:)`;
  the plugin (outside this component's given sources) decides which of
  those values, including any secret, become part of the outgoing request
  that `PluginTransport` then performs.
- **Retention**: Stored field/model values persist indefinitely (Keychain
  for secrets, plain settings for the rest) until `clearStoredValues` is
  called for that configuration — there is no expiry, rotation, or
  time-based invalidation logic anywhere in this component; a stored value
  is valid until explicitly overwritten or cleared.

## Logging

Not applicable: none of the given sources call `logger.info`, `.warning`, or
`.error`. `AIPluginsCoordinator` conforms to `Loggable` (declaring a
`makeLogger()`-backed static logger) but never invokes it anywhere in the
given source — the conformance is present, but unused.

## Platform Notes

- **SwiftUI** (source): This is a plain Foundation/AppKit runtime layer, not
  a SwiftUI component. `AIPluginsCoordinator.swift` imports `AppKit` to
  compose menu/status-item contributions as an `AppFeature`; the actual chat
  UI (outside this component) binds to `AIChatViewModel`'s
  `@Published`/`ObservableObject` surface fed by `ChatBackendSession` or
  `LocalChatSession`'s `events()` `AsyncStream`. State that would be
  `@Observable`/`ObservableObject` elsewhere is here plain `NSLock`- or
  `Synchronization.Mutex`-guarded mutable state on `@unchecked Sendable`
  classes, and persistence goes through `UserSetting<T>` (Combine-backed,
  Keychain-routed when `isSecure`).
- **Compose** (Android/Kotlin): `kotlinx.coroutines.flow.Flow`/`SharedFlow`
  replaces the `AsyncStream`/`AsyncThrowingStream` event pipelines;
  `kotlinx.coroutines.sync.Mutex` replaces `NSLock`/`Synchronization.Mutex`
  for the busy-guard and subscriber registry; the Keychain-routed secret
  fields become `EncryptedSharedPreferences` or an Android
  Keystore-backed store, and the plain fields become ordinary
  `SharedPreferences`/`DataStore`; the `.aiplugin` bundle + `dlopen` +
  `NSPrincipalClass` discovery model has no direct Android analogue — a
  static `ServiceLoader`-style registry or a signed dynamic-feature module
  would replace it, since arbitrary native code loading is far more
  restricted.
- **React/Web**: Async generators or an RxJS `Observable` replace
  `AsyncStream`; because JS is single-threaded, the `NSLock`/`Mutex` guards
  collapse to a plain boolean busy flag (no actual lock needed); the
  Keychain-routed secret store becomes a server-side vault or, client-side,
  a WebCrypto-wrapped value in `IndexedDB` (never plain `localStorage` for a
  secret); dynamic `import()` of a plugin module, driven by a fetched
  `descriptor.json`-equivalent manifest, replaces `Bundle` + `dlopen`
  discovery.
- **AppKit / UIKit**: The given sources already target AppKit; a UIKit
  (iOS) port would replace `AIPluginsCoordinator`'s `AppFeature`/menu-bar
  lifecycle hooks with `UIApplicationDelegate` equivalents, and would need
  to drop the `dlopen`-based `.aiplugin` bundle loading entirely — dynamic
  loading of unsigned code is not permitted under App Store code-signing —
  in favor of statically linked or App Extension–hosted plugins. The
  Foundation-level pieces (`NSLock`, `UserDefaults`, Keychain Services)
  need no change.
- **WinUI 3**: `System.Net.Http.HttpClient` performs the HTTP half of what
  `PluginTransport` drives (the given sources hand it an `AIRequestSpec`,
  never touch `HttpClient` directly), and `System.Diagnostics.Process` /
  `ProcessStartInfo` covers the subprocess (`.command`) transport case;
  `System.Text.Json` replaces `Foundation.JSONEncoder`/`JSONDecoder` for
  `descriptor.json` decoding and for `MCPChatToolSource`'s tool-schema and
  tool-argument JSON; `Windows.Storage.ApplicationData.Current.LocalSettings`
  replaces the plain (`isSecure: false`) `UserSetting` keys, and
  `Windows.Security.Credentials.PasswordVault` replaces the Keychain for
  secret fields; `System.Threading.SemaphoreSlim` or a plain `lock` object
  replaces `NSLock`/`Synchronization.Mutex` for `LocalChatSession`'s busy
  guard and `AIPluginChatBackend`'s subscriber registry;
  `System.Threading.Channels.Channel<T>` or `IAsyncEnumerable<T>` replaces
  `AsyncStream`/`AsyncThrowingStream` for `events()` and the plugin-transport
  event streams; `ObservableCollection<T>` + `INotifyPropertyChanged`
  replaces `@Published`/`ObservableObject` for the settings-backed
  configuration list and view models; and the Managed Extensibility
  Framework (`System.ComponentModel.Composition`) or a plain
  `Assembly.LoadFrom` call is the .NET analogue of `Bundle` + `dlopen` +
  `NSPrincipalClass` discovery — read a manifest first, load the assembly
  only on first use.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/` |

## Design Decisions

- **Decision**: `AIPluginChatBackend` and `LocalChatSession` are declared
  `@unchecked Sendable` rather than `actor`s or fully `@MainActor` types.
  **Rationale**: each type's own doc comment states the invariant that makes
  this safe — every mutable field is guarded by exactly one synchronization
  primitive (`NSLock` for `subscribers`/`history`/`continuation`, a
  `Synchronization.Mutex` for the busy flag), and any `@MainActor`-isolated
  dependency (`pluginManager`, `configProvider`) is read only inside a
  `MainActor.run` block — so the compiler's inability to verify isolation
  across an `async` boundary is a known limitation being worked around, not
  an unverified assumption.
  **Approved**: pending.
- **Decision**: `AIProviderResolver.resolve` returns `nil` rather than
  falling back to `descriptor.resolvedTemplates.first` when the
  configuration's `templateId` no longer resolves.
  **Rationale**: falling back would silently bind the configuration's
  already-stored credentials and model to whatever template happens to be
  first — an unrelated provider, base URL, and auth mode — and push that to
  the daemon as though nothing had changed. Failing closed surfaces the
  break instead of masking it.
  **Approved**: pending.
- **Decision**: `AIProviderConfigStore.configValues` always overlays a
  secret field's stored value (even when empty) but only overlays a
  non-secret field's stored value when it is non-empty.
  **Rationale**: an empty non-secret value would otherwise silently clobber
  a meaningful template default (e.g. a `baseURL`); a secret field has no
  default to clobber, and including it even when blank is what lets a
  plugin distinguish "this template requires a key and it is blank" from
  "this template has no secret field at all."
  **Approved**: pending.
- **Decision**: `AIProviderDefaults.seedIfNeeded` seeds a default
  `claude-local` configuration but leaves it unselected.
  **Rationale**: an empty `selectedAIProviderConfigurationId` and a selected
  `claude-local` configuration both resolve to the same effective behavior
  at the daemon (its own zero-config "Default (Claude CLI)" path), so
  leaving the selection empty avoids pushing a plugin id the daemon might
  not itself resolve, at no behavioral cost.
  **Approved**: pending.
- **Decision**: `AIProviderMigration.plan` carries forward a keyless
  descriptor whose only signal is a customized non-secret field
  (`hasCustomField`), not only descriptors with a secret or the legacy
  selection.
  **Rationale**: an OpenAI-compatible-style provider pointed at a local,
  keyless endpoint has no secret to detect and may never have been the
  legacy selection, but a customized `baseURL` is still evidence the user
  configured it; treating it as unconfigured would silently drop that
  setup during migration.
  **Approved**: pending.
- **Decision**: `LocalChatSession.maxToolIterations` is fixed at `8` with no
  configuration point and no explicit UI signal when the cap is reached.
  **Rationale**: bounds the worst-case latency and cost of a runaway
  tool-calling loop; the source gives no rationale for the specific value
  `8` beyond the constant itself, and a caller cannot distinguish "the model
  stopped on its own" from "the turn hit the iteration cap" from the emitted
  events alone.
  **Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: separation-of-concerns passes because the component splits into three
independent responsibilities — plugin lifecycle (`AIPluginsCoordinator`),
configuration modeling and persistence (`AIProviderConfigStore`,
`AIProviderResolver`, `AIProviderDefaults`, `AIProviderMigration`,
`PluginConfigStore`), and conversation driving (the two
`ChatConfigProvider` + chat-engine pairs) — and none reaches into another's
storage. unit-test-coverage passes because the conformance vectors trace to
`LocalChatSessionTests`, `AIProviderConfigStoreTests`,
`AIProviderResolverTests`, `AIProviderMigrationTests`, and
`AIProviderDefaultsTests`, which exercise streaming, seeding, resolution,
migration, and first-run defaults without a live provider. secure-storage
passes because every `.secret` field is persisted through a
`UserSetting<String>` constructed with `isSecure: true`, so credentials land
in the Keychain and never in plain user defaults (see Privacy).
input-sanitization and explicit-error-handling are partial because
`MCPChatToolSource.callTool` decodes the model's `argumentsJSON` with `try?`
and forwards `nil` arguments on a decode failure instead of reporting a tool
error — the open question on mcp-tool-source-argument-validation — while
the other failure paths (no configured provider, unknown tool, a throwing
MCP call) surface as explicit `ChatError` or tool-error text.
no-hardcoded-strings fails because the user-facing error strings listed
under Localization are English literals with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
