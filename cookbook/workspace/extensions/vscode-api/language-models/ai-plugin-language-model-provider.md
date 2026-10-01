---
id: a602608c-c061-44b6-a7ab-829e798d6b0c
title: AI Plugin Language Model Provider
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/language-models/ai-plugin-language-model-provider
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
  - agentictoolkit://cookbook/ai/providers/provider-configuration
  - agentictoolkit://cookbook/ai/plugins/plugin-manager
  - agentictoolkit://cookbook/ai/plugins/plugin-descriptor
  - agentictoolkit://cookbook/ai/chat/chat-context
  - agentictoolkit://cookbook/ai/models/model-catalog
  - agentictoolkit://cookbook/ai/plugins/plugin-transport
  - agentictoolkit://cookbook/ai/plugins/stream-event
  - agentictoolkit://cookbook/ai/plugins/ai-plugin
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

# AI Plugin Language Model Provider

## Overview

This is the production language-model provider for the VS Code
extension-host seam: it offers extensions the chat models the user has
already configured in the app's own LLM Providers settings, and streams a
`sendRequest` call through the same underlying plugin path the app's own
chat surface uses. It adds no transport, no credential handling, and no
request shaping of its own — it reuses the provider-configuration/
resolver layer (which already joins a configuration to its plugin
template, stored credentials, and model) and the plugin-manager/transport
layer (which already loads a plugin and drives its request) rather than
opening a second route to a provider. Listing available chat models lists
the cross product of every model of every configuration the user has
saved — not the app's own single selected chat configuration — because
`vscode.lm.selectChatModels` asks what the host *has* and does its own
selector matching one layer above this provider. Streaming a response
turns a chat-model descriptor id of the form `"<configuration UUID>/
<model>"` back into a configuration and a model name, resolves the
configuration to a loadable plugin, builds a chat context, and adapts the
plugin transport's stream of events into the seam's own response-part
stream.

## Behavioral Requirements

- **thread-confined-access**: The provider MUST be confined to a single,
  serialized execution context; every stored value read and write, and
  the synchronous portion of every method, MUST execute on that same
  confined context.
- **protocol-conformance**: The provider MUST conform to the extension
  host's language-model-providing role, implementing both listing
  available chat models and streaming a response for a given model,
  message list, justification, and extension identifier.
- **injected-plugin-manager**: Constructing the provider MUST store the
  given plugin manager as the sole source of plugin descriptors and
  loaded plugin instances; the type MUST NOT construct its own plugin
  manager.
- **configuration-observer-wiring**: Constructing the provider MUST
  subscribe an observer to the saved provider-configuration list so that
  every subsequent write to that setting invokes the
  available-chat-models-changed notification.
- **no-notification-on-construction**: Constructing the provider MUST NOT
  itself invoke the available-chat-models-changed notification, even when
  the saved provider-configuration list already holds one or more
  configurations at construction time.
- **every-configured-model-listed**: Listing available chat models MUST
  return one descriptor for every model in every template of every
  configuration currently in the saved provider-configuration list — the
  full cross product of configurations and their templates' models, not
  the app's single selected configuration.
- **deterministic-model-order**: Listing available chat models MUST order
  its results first by the order configurations appear in the saved
  provider-configuration list, then by the order models appear in that
  configuration's resolved template's model list.
- **unresolvable-template-skipped**: When a configuration's template
  cannot be resolved from the plugin manager, listing available chat
  models MUST contribute no descriptor for that configuration and MUST
  continue processing the remaining configurations.
- **descriptor-id-format**: Each descriptor's id MUST be the string
  formed by joining the configuration's identifier and the model name
  with a single `"/"` separator.
- **descriptor-id-separator-safety**: The id split performed when
  resolving a configuration MUST use the FIRST occurrence of `"/"` only,
  so a model name that itself contains `"/"` is preserved verbatim in the
  parsed model name.
- **descriptor-name**: Each descriptor's name MUST be the configuration's
  name, a `"·"` separator, and the model name.
- **descriptor-vendor**: Each descriptor's vendor MUST be the resolved
  template's provider name, falling back to the template's display name
  when the provider name is absent.
- **descriptor-family**: Each descriptor's family MUST be the model's
  canonical identifier.
- **descriptor-version**: Each descriptor's version MUST be the raw model
  name, unmodified.
- **descriptor-max-input-tokens**: Each descriptor's maximum input tokens
  MUST be the model catalog's resolved context-window size when the
  catalog has an entry for that model/template pair, and MUST be `4096`
  when it does not.
- **justification-recorded-only**: When streaming a response is called
  with a present justification, it MUST log the extension identifier and
  the justification before doing anything else, and MUST NOT use the
  justification's content to gate, filter, or alter which model or plugin
  the request reaches.
- **justification-privacy**: The logged justification value MUST be
  logged as sensitive/redacted; the logged extension-identifier value
  MUST be logged as not sensitive.
- **no-log-when-justification-absent**: When justification is absent,
  streaming a response MUST NOT emit the justification log line at all.
- **model-id-parse-failure**: Resolving a configuration MUST throw an
  unknown-model error naming the requested id when that id contains no
  `"/"` character.
- **model-id-unknown-configuration**: Resolving a configuration MUST
  throw an unknown-model error naming the requested id when the substring
  before the first `"/"` does not parse as a valid identifier, or parses
  but names no configuration currently in the saved provider-configuration
  list.
- **configuration-reread-per-call**: Resolving a configuration MUST
  re-read the saved provider-configuration list on every call rather than
  reuse a value captured when the descriptor was built, so a
  configuration deleted after the descriptor was issued is reflected on
  the next call.
- **plugin-resolution-failure**: Streaming a response MUST throw a
  plugin-unavailable error naming the resolved configuration's plugin
  identifier when the provider-configuration resolver cannot resolve the
  configuration's plugin.
- **plugin-load-failure-collapsed**: Streaming a response MUST throw a
  plugin-unavailable error naming the resolved plugin identifier when
  loading the plugin fails, regardless of which specific load-failure case
  occurred (not found, load failed, no principal class, principal class
  not a plugin); the specific failure cause MUST be discarded.
- **request-model-override**: Streaming a response MUST set both the
  plugin's request-configuration bag's model entry and the chat context's
  model to the model name parsed from the requested descriptor's id,
  overriding whatever model the resolved configuration's own stored value
  would otherwise supply.
- **no-system-prompt**: Every chat context streaming a response builds
  MUST have no system prompt.
- **no-tools-forwarded**: Every chat context streaming a response builds
  MUST have an empty tool list; streaming a response's own parameters
  carry no tool list of their own for this to forward.
- **default-max-tokens**: Every chat context streaming a response builds
  MUST omit an explicit maximum-tokens argument, so every request uses
  the chat context's own default of `4096`, independent of the resolved
  descriptor's own maximum input tokens.
- **build-request-error-propagation**: When building the plugin's request
  throws, streaming a response MUST propagate that error unwrapped — it
  MUST NOT catch it or convert it into one of the provider's own named
  error cases.
- **transport-delegation**: Streaming a response MUST delegate all
  network access and subprocess execution to the plugin transport's run
  operation; the provider MUST perform no HTTP request, no subprocess
  launch, and no credential lookup of its own.
- **response-part-mapping**: Mapping a stream event to a response part
  MUST map a text-delta event to a text part, a tool-use event to a
  tool-call part carrying the same id, name, and arguments, and an end
  event to an end part carrying the same stop reason, with no case
  dropped or merged.
- **message-role-mapping**: Mapping a message MUST map a user-role
  message to a user-role chat message and MUST map an assistant-role
  message — the role's only other case — to an assistant-role chat
  message.
- **message-name-dropped**: Mapping a message MUST NOT carry the
  message's name into any field of the chat message it produces.
- **stream-single-consumption**: Streaming a response MUST return a fresh
  stream per call; it MUST NOT return or reuse a previously-returned
  stream.
- **stream-cancellation-propagation**: When the consumer of a streamed
  response terminates early, that termination MUST cancel the wrapping
  unit of work, which cancels the plugin transport stream it is
  iterating.
- **no-instance-caching**: Listing available chat models and resolving a
  configuration MUST NOT cache a prior call's result; each call MUST
  recompute from the current saved provider-configuration list and the
  current plugin-manager state.
- **unknown-model-caller-guidance**: A caller catching the unknown-model
  error SHOULD treat it as a stale descriptor and re-query available chat
  models, rather than as a malformed request from the extension —
  deviation is acceptable because both of that error's triggers (an
  unparseable id, or a configuration deleted since the descriptor was
  issued) originate from state that changed after the descriptor was
  handed out, not from anything the extension itself chose; both cases
  are "the same event from an extension's point of view: it held a model
  descriptor across the user deleting the provider behind it."
- **model-name-membership**: Neither resolving a configuration nor
  resolving its plugin checks that the model name parsed out of a
  descriptor's id is still present in the resolved template's current
  model list — only that the configuration id and its template id still
  resolve. If a plugin update removes or renames a model between the time
  a descriptor was built and a later request call parses it, streaming a
  response MUST send the request with the stale model name unchanged,
  leaving the plugin's own request builder and the provider to reject it;
  any such rejection surfaces to the caller as the stream's error.

## Appearance

Not applicable — this is the extension host's production language-model provider, not a visual component.

## States

Not applicable — this is the extension host's production language-model provider, not a visual component. Its only lifecycle-shaped behavior is the per-request streaming sequence (resolve, load, build, stream), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's production language-model provider, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-language-model-provider-001 | every-configured-model-listed, deterministic-model-order, descriptor-vendor, descriptor-family, descriptor-version, descriptor-max-input-tokens | One configuration "My Provider" on plugin "test.plugin"/template "template-a" with models `["model-a", "model-b"]` → list available chat models | Returns two descriptors with ids `"<configId>/model-a"` and `"<configId>/model-b"`, names `"My Provider · model-a"`/`"My Provider · model-b"`, vendor `"Template A"` for both, family/version equal to the model name, and maximum input tokens `4096` for both |
| ai-plugin-language-model-provider-002 | unresolvable-template-skipped | A configuration whose plugin identifier ("never.registered") is never registered with the plugin manager → list available chat models | Returns an empty list |
| ai-plugin-language-model-provider-003 | deterministic-model-order | Two configurations "First" and "Second" sharing one template whose models are `["only-model"]` → list available chat models | Returns names in order `["First · only-model", "Second · only-model"]` |
| ai-plugin-language-model-provider-004 | configuration-observer-wiring | Attach the available-chat-models-changed callback, then write a new value to the saved provider-configuration list, then let the confined context settle | The callback fires exactly once |
| ai-plugin-language-model-provider-005 | no-notification-on-construction | Construct the provider while a configuration is already present, attach the callback afterward, then let the confined context settle | The callback never fires |
| ai-plugin-language-model-provider-006 | model-id-parse-failure | Stream a response for a descriptor whose id is `"not-a-uuid-slash-model"` (no `"/"`) | Throws the unknown-model error before any plugin lookup |
| ai-plugin-language-model-provider-007 | model-id-unknown-configuration, configuration-reread-per-call | Stream a response for a descriptor whose id is `"<random UUID>/model-a"` naming no existing configuration | Throws the unknown-model error |
| ai-plugin-language-model-provider-008 | plugin-resolution-failure | A configuration whose plugin identifier ("never.registered") is never registered with the plugin manager → stream a response | Throws the plugin-unavailable error naming that configuration's plugin identifier |
| ai-plugin-language-model-provider-009 | descriptor-id-separator-safety | A template model name containing `"/"` (e.g. `"org/model-name"`) → build a descriptor for it, then resolve a configuration from the resulting id | The built id is `"<uuid>/org/model-name"`; resolving splits at the FIRST `"/"` only and returns the model name `"org/model-name"` unchanged |
| ai-plugin-language-model-provider-010 | request-model-override | The resolved configuration's own stored value already holds the app's own selected model string; stream a response for a descriptor naming a different model | Both the plugin's request-configuration bag and the chat context carry the extension-selected model name, not the configuration's stored app-selected model |
| ai-plugin-language-model-provider-011 | default-max-tokens | Any successful streamed response, regardless of the resolved descriptor's maximum input tokens | The chat context built for the request has a maximum-tokens value of `4096` |
| ai-plugin-language-model-provider-012 | no-system-prompt, no-tools-forwarded | Any successful streamed response | The built chat context has no system prompt and an empty tool list unconditionally |
| ai-plugin-language-model-provider-013 | response-part-mapping | The plugin transport's stream yields a text-delta event `"hi"`, then a tool-use event (id `"1"`, name `"x"`, empty arguments), then an end event with stop reason `"stop"` | The stream returned yields a text part `"hi"`, then a tool-call part with the same id/name/arguments, then an end part with stop reason `"stop"`, in the same order |
| ai-plugin-language-model-provider-014 | message-role-mapping, message-name-dropped | Messages: a user-role message named `"ignored"` with text `"hi"`, and an assistant-role message with no name and text `"hi back"` | Mapping produces a user-role chat message with content `"hi"` and an assistant-role chat message with content `"hi back"`; the `"ignored"` name value is dropped, appearing in no chat-message field |
| ai-plugin-language-model-provider-015 | stream-cancellation-propagation | The consumer of a streamed response stops iterating early (cancels) | The stream's termination handler fires and cancels the wrapping unit of work, which cancels the plugin transport stream it awaits |
| ai-plugin-language-model-provider-016 | justification-recorded-only, justification-privacy, no-log-when-justification-absent | Stream a response once with justification `"need vision"` and once with no justification, both otherwise routed to a configuration whose plugin fails to load | The info log line is produced exactly once, only on the present-justification call, with the extension identifier logged in the clear and the justification logged as redacted; neither call's routing to the plugin-unavailable error differs based on the justification's presence or content |
| ai-plugin-language-model-provider-017 | model-name-membership | A configuration's template is updated to drop `"model-a"` from its model list, but a previously-issued descriptor id still names `"model-a"`; stream a response with that stale descriptor id | No dedicated test exists in the given sources; the resolution logic shows neither step checks the parsed model name against the current template's model list, so the request proceeds to the plugin's own request builder with the stale model name — demonstrating the open question rather than resolving it |

## Edge Cases

- **Null/empty input**: an empty model id MUST be treated as "no separator found" and MUST cause resolving a configuration to throw the unknown-model error naming the empty string (MUST).
- **Null/empty input**: an empty message list MUST be mapped to an empty chat-message list and passed to the chat context unchanged; streaming a response performs no minimum-length check (MUST).
- **Null/empty input**: an absent justification MUST suppress the justification log line entirely, per **no-log-when-justification-absent** (MUST).
- **Boundary values**: a template's model list containing exactly one model is the minimum non-empty case for listing available chat models to contribute a descriptor for that configuration; it MUST still be ordered and formatted identically to a multi-model template (MUST).
- **Boundary values**: a model name containing one or more `"/"` characters MUST round-trip through building a descriptor and resolving a configuration unchanged, per **descriptor-id-separator-safety** (MUST).
- **Boundary values**: the chat context's maximum-tokens value is fixed at `4096` for every request regardless of how large or small the resolved descriptor's maximum input tokens is; no per-request scaling is performed (MUST).
- **Concurrent access**: the provider holds no per-call mutable state — listing available chat models and resolving a configuration each recompute from the saved provider-configuration list and the plugin manager on every call — so multiple concurrent streamed-response calls MUST NOT race against each other or against a concurrent listing read (MUST).
- **Concurrent access**: a write to the saved provider-configuration list concurrent with an in-flight streamed-response call MUST NOT affect that call's already-resolved configuration and model, because resolving a configuration reads the setting exactly once, synchronously, before any suspension point (MUST).
- **Error states**: the provider-configuration resolver answering "unresolvable" (the configuration's plugin descriptor exists but its template id no longer resolves) MUST surface as the plugin-unavailable error naming that configuration's plugin identifier, per **plugin-resolution-failure** (MUST).
- **Error states**: any of the plugin loader's four thrown failure cases MUST surface identically as the plugin-unavailable error naming the resolved plugin identifier, discarding which specific case occurred, per **plugin-load-failure-collapsed** (MUST).
- **Error states**: an error thrown by the plugin's own request builder MUST propagate to the caller of streaming a response unwrapped — not as one of the provider's own named error cases (MUST).
- **Error states**: an error thrown inside the plugin transport's stream (a transport-error case, or any other error a plugin's decoder or transport raises) MUST propagate unmodified to the consumer of the streamed response (MUST).
- **Offline or disconnected state**: the provider performs no network call itself; connectivity loss during an in-flight request surfaces however the plugin transport's underlying transport reports it (a thrown network error, or a timed-out transport error if the wall-clock budget lapses first), passed through unmodified rather than detected, retried, or translated by this type (MUST).
- **Cancellation and timeouts**: the provider enforces no timeout of its own; any request-level deadline belongs to the plugin transport's own timeout setting, applied one layer down. Consumer-initiated cancellation of a streamed response MUST propagate via the stream's termination handler, per **stream-cancellation-propagation** (MUST).
- **Missing file or unreachable server**: not applicable to this file directly — it opens no file and makes no network call itself; an unreachable server or a plugin bundle that fails to load surfaces as the plugin-unavailable error (load failure, per **plugin-load-failure-collapsed**) or as a transport error (an unreachable server during the request itself, per the Error states entries above).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pluginManager` | a plugin manager | none (required) | Supplied when constructing the provider; the sole source of plugin descriptors, templates, and loaded plugin instances. |
| `model` | a chat-model descriptor | none (required) | The descriptor streaming a response is asked to route; only its id field is consulted. |
| `messages` | a list of chat messages | none (required) | The conversation history to send; mapped verbatim (minus name) to the plugin's own message list. |
| `justification` | an optional string | none (optional) | Free text from `options.justification` (`vscode.d.ts`); recorded to the log only, per **justification-recorded-only**. |
| `extensionIdentifier` | a string | none (required) | Identifies the calling extension for the justification log line; passed straight through with no validation. |
| saved provider-configuration list | a list of provider configurations, settings key `"aiplugin.configurations"` | `[]` | Read by listing available chat models and by resolving a configuration; observed by the configuration observer set up when the provider is constructed. |
| model catalog | a shared, loaded catalog | the loaded shared catalog | Consulted when building a descriptor for its context-window size; falls back to the default maximum input tokens (`4096`) when the model/template pair is unlisted. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it is a language-model seam conformer with no navigation surface of its own.

## Localization

The provider's own two error descriptions — `"no configured language model with id '<id>'"` and `"the plugin '<identifier>' is not available"` — are hardcoded English string literals with no localization key or catalog entry. Both strings are produced by the error's own textual description, which a caller (ultimately the extension-host seam that turns a thrown error into an extension-visible error) would surface. Each descriptor's name uses a fixed `"·"` separator glyph around two data-derived strings (the user's own configuration name and a model identifier), not translatable prose.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `no configured language model with id '<id>'` | The unknown-model error's description, surfaced when a descriptor's id no longer resolves. |
| (none — literal only) | `the plugin '<identifier>' is not available` | The plugin-unavailable error's description, surfaced when the resolved plugin cannot be reached. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once the type is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its one telemetry-adjacent call is the diagnostic log line covered under Logging, which is not an analytics event.

## Privacy

- **Data collected**: the provider itself collects no data beyond what its callers already hand it: `justification` (free text an extension supplies explaining why it wants a model) and `extensionIdentifier` are read only to log them, per **justification-recorded-only**. `messages` (the conversation) and the resolved configuration's values are forwarded into the request the plugin builds, but not retained by this type. No credential or secret value is read or handled here — those are resolved and injected by the provider-configuration resolver/store, which this type calls but does not duplicate.
- **Storage**: the provider performs no storage of its own; the saved provider-configuration list is owned and persisted elsewhere.
- **Transmission**: `messages`, the resolved model name, and the resolved configuration's values are transmitted to the external provider, but the transmission itself is performed by the plugin transport/the loaded plugin, not by this component directly.
- **Retention**: this component retains nothing beyond the lifetime of one streamed-response call's local variables; the one value it logs (`justification`) persists only per the logging system's own system-level retention policy, which this component does not configure.

## Logging

Subsystem: the host's own logging subsystem | Category: this provider's own category

| Event | Level | Message |
|-------|-------|---------|
| An extension calls streaming a response with a present justification | info | `extension <extensionIdentifier> requested a language model, justification: <justification>` — the extension identifier is logged in the clear, the justification is logged redacted |

No other event in this file is logged: neither the unknown-model error nor the plugin-unavailable error is logged at the point it is thrown — both are facts the code surfaces to the caller as thrown errors instead, per **plugin-resolution-failure** and **model-id-parse-failure**/**model-id-unknown-configuration**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIPluginLanguageModelProvider.swift` imports only `Foundation`, `OSLog`, `AgenticToolkitCore`, and `AIPluginKit`, with no SwiftUI dependency; a SwiftUI-based LLM Providers settings surface would call `availableChatModels`/`streamResponse` unchanged, the same relationship the sibling `AIProviderConfiguration`/`AIPluginManager` recipes describe for these same dependencies.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/AIPluginLanguageModelProvider.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration (satisfying "thread-confined access" above), and its only consumer among the given sources is `MainThreadLanguageModels` (declaring the `ExtensionLanguageModelProviding` protocol this type conforms to, in the same `Extensions/VSCodeAPI` folder), itself also `@MainActor`. `ProviderError` is this type's own error enum with cases `unknownModel(String)` and `pluginUnavailable(String)`. The "plugin's request-configuration bag" of **request-model-override** is `AIPluginConfig`; the "chat context" is `AIChatContext`; the "response-part stream" is `ExtensionLanguageModelResponsePart`. The justification/extensionIdentifier privacy tagging of **justification-privacy** is OSLog's `privacy: .private`/`privacy: .public` string-interpolation annotations, applied at the `Self.logger.info(...)` call site.
- **Compose**: model this as a Kotlin `class AIPluginLanguageModelProvider(private val pluginManager: AIPluginManager) : ExtensionLanguageModelProviding` confined to the main dispatcher; `availableChatModels` becomes a computed property recomputed from whatever `StateFlow`/settings store mirrors the saved provider-configuration list, and `streamResponse` becomes a `suspend fun streamResponse(...): Flow<ExtensionLanguageModelResponsePart>` built with `callbackFlow`, whose `awaitClose` block plays the role of the stream's termination handler and cancels the underlying transport the same way. `ProviderError` becomes a `sealed class` with the same two cases (`UnknownModel(id: String)`, `PluginUnavailable(identifier: String)`).
- **React/Web**: model as a module exposing `availableChatModels(): LanguageModelChatDescriptor[]` and `async function* streamResponse(...)` — an async generator in place of an async throwing stream — where the consumer's early `return`/`break` (which triggers the generator's `finally` block) is the cancellation-propagation equivalent of the stream's termination handler. `ProviderError` becomes a custom `Error` subclass or discriminated union with the same two variants, and the settings read becomes whatever store backs the extension host's own provider-configuration list in that runtime.
- **WinUI 3**: model this provider as a class implementing an `IExtensionLanguageModelProviding` interface: `IReadOnlyList<LanguageModelChatDescriptor> AvailableChatModels { get; }`, `event Action? AvailableChatModelsChanged`, and `IAsyncEnumerable<ExtensionLanguageModelResponsePart> StreamResponseAsync(LanguageModelChatDescriptor model, IReadOnlyList<ExtensionLanguageModelMessage> messages, string? justification, string extensionIdentifier, [EnumeratorCancellation] CancellationToken cancellationToken = default)`, where a cancelled `CancellationToken` plays the role of the stream's termination handler and must propagate into the HttpClient call or process the same way. `ProviderError` becomes two custom `Exception` subclasses (`UnknownModelException`, `PluginUnavailableException`), since C# has no error enum with associated values. `HttpClient` and `System.Text.Json.JsonSerializer` are the .NET equivalents of the transport/decoding machinery one layer down in the plugin transport, which this type itself never calls directly. The settings read becomes an `ObservableCollection<AIProviderConfiguration>` or `INotifyPropertyChanged`-backed store, with its `CollectionChanged` event replacing the settings observer's subscription to raise `AvailableChatModelsChanged`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/AIPluginLanguageModelProvider.swift` |

## Design Decisions

**Decision** (Swift implementation): a descriptor's id is `"<configuration UUID>/<model>"`, and the split when resolving a configuration uses the FIRST `"/"` only.
**Rationale**: a UUID never contains `"/"`, so the split point is unambiguous, and splitting on the first occurrence rather than the last preserves a model name that itself contains `"/"` — several gateways use such names — stated directly in the source's own documentation.
**Approved**: pending

**Decision**: streaming a response collapses the plugin loader's four distinct failure cases (not found, load failed, no principal class, principal class not a plugin) into one plugin-unavailable error, discarding which specific case occurred.
**Rationale**: the provider's own error type frames its two cases as "what a request can fail on before a plugin is ever reached" — from the extension's point of view, every one of the loader's four failure modes means the same thing: the named plugin cannot serve the request right now. The specific cause is intentionally discarded.
**Approved**: pending

**Decision**: resolving a configuration re-reads the saved provider-configuration list fresh on every streamed-response call rather than resolving once when the descriptor was built.
**Rationale**: per the source's own documentation, "an extension may hold a descriptor for as long as it likes, and what the user has configured now is what a request can actually reach."
**Approved**: pending

**Decision**: every chat context streaming a response builds omits an explicit maximum-tokens value, so every request uses the chat context's own default of `4096` regardless of the resolved descriptor's own maximum input tokens (which can be a real, larger context window reported by the model catalog).
**Rationale**: not stated in the source. The context window recorded on the descriptor is informational — communicated to `vscode.lm` callers as the model's ceiling — but nothing in streaming a response reads it back when building the request, so the request's actual token budget is a fixed default rather than a computation derived from the same catalog lookup building a descriptor performs.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/language-models/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
