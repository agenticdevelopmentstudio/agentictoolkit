---
id: 613d7a36-d0cd-4415-97be-d983b3d6c644
title: AI Chat Context
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The Sendable value types (AIChatMessage, AIToolSpec, AIPluginConfig, AIChatContext)
  that carry one chat turn's conversation, tools, and resolved config into AIPlugin.buildRequest.
platforms:
- swift
- macos
tags:
- ai-plugin
- chat
- value-type
- sendable
- foundation
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# AI Chat Context

## Overview

`AIChatContext.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift`) defines four `Sendable` Foundation-only value types that together form the input contract an `AIPlugin` receives for one chat turn: `AIChatMessage` (one turn of conversation history), `AIToolSpec` (one tool the model may call), `AIPluginConfig` (the plugin's resolved, ready-to-use configuration values), and `AIChatContext` itself (the conversation, model, limits, tools, and config bundled for a single request). None of the four types performs I/O, validation beyond what the compiler enforces, or any side effect — they are pure data carried from the host into `AIPlugin.buildRequest(_:)`, which turns them into an `AIRequestSpec` describing the outgoing HTTP or subprocess request. The file has no logic of its own: it is the shape of the contract, not an implementation of it.

## Behavioral Requirements

- **message-role**: `AIChatMessage.Role` MUST be one of `system`, `user`, `assistant`, `toolUse`, or `toolResult`, backed by a `String` raw value, where `toolUse` serializes as `"tool_use"` and `toolResult` serializes as `"tool_result"` (not the Swift case names) and the other three cases serialize as their lowercase case name.
- **message-content**: `AIChatMessage` MUST carry a required `content: String` field with no default value.
- **message-tool-fields-optional**: `AIChatMessage` MUST allow `toolUseId`, `toolName`, `toolArgumentsJSON`, and `toolIsError` to be `nil`, and its initializer MUST default each of the four to `nil` when the caller omits it.
- **message-tool-fields-independent**: `AIChatMessage` MUST NOT enforce any relationship between `role` and the four tool-related fields; a message may combine any `role` with any combination of `toolUseId`, `toolName`, `toolArgumentsJSON`, and `toolIsError` being present or `nil`.
- **tool-spec-identity**: `AIToolSpec` MUST require `name: String`, `description: String`, and `parametersJSONSchema: Data`, none of which has a default value.
- **tool-spec-equality**: `AIToolSpec` MUST conform to `Hashable`; two instances MUST compare equal if and only if their `name`, `description`, and `parametersJSONSchema` are each equal (the compiler-synthesized memberwise conformance over all three stored properties).
- **config-value-storage**: `AIPluginConfig` MUST store its values as a `[String: String]` dictionary and MUST expose a keyed subscript that returns the value for a key present in the dictionary, or `nil` for a key that is absent.
- **config-conventional-accessors**: `AIPluginConfig` MUST expose `apiKey`, `baseURL`, and `model` as computed properties reading `values["apiKey"]`, `values["baseURL"]`, and `values["model"]` respectively, returning `nil` when the corresponding key is absent.
- **config-host-resolved**: `AIPluginConfig`'s values MUST already be fully resolved (settings-schema fields merged with secrets injected from the Keychain) by the caller before the value is constructed; per the type's doc comment, "the plugin never touches storage itself" — `AIPluginConfig` and `AIChatContext` MUST NOT perform any storage, Keychain, or settings-schema access of their own.
- **context-messages-required**: `AIChatContext` MUST require `messages: [AIChatMessage]` with no default value, representing the full conversation history for the turn in caller-supplied order.
- **context-model-required**: `AIChatContext` MUST require `model: String` with no default value.
- **context-system-prompt-optional**: `AIChatContext` MUST allow `systemPrompt` to be `nil` and MUST default it to `nil` when the caller omits it.
- **context-max-tokens-default**: `AIChatContext` MUST default `maxTokens` to `4096` when the caller omits it.
- **context-tools-default-empty**: `AIChatContext` MUST default `tools` to an empty `[AIToolSpec]` when the caller omits it.
- **context-config-required**: `AIChatContext` MUST require `config: AIPluginConfig` with no default value.
- **immutability**: `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` MUST expose every stored property as an immutable `let`; none of the four types MUST provide any method or property that mutates an existing instance after initialization.
- **sendability**: `AIChatMessage`, `AIChatMessage.Role`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` MUST conform to `Sendable`; because each is declared `Sendable` and holds only `Sendable` stored properties (`String`, `Data`, `Int`, `Bool`, `[String: String]`, arrays thereof), the compiler enforces this conformance and no manual synchronization is required to pass an instance across a concurrency-domain boundary (e.g., from the host actor into `AIPlugin.buildRequest(_:)`).
- **concurrent-read-safety**: Because every property of all four types is immutable and `Sendable`, a single constructed instance MAY be read concurrently from multiple tasks with no additional locking, and no operation defined in this file mutates shared state, so no ordering or serialization rule is needed between concurrent reads of the same instance.
- **no-persistence**: `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` MUST NOT persist or cache any of their fields; the source contains no file, database, `UserDefaults`, or Keychain access, and each instance exists only as a transient parameter for one call to `AIPlugin.buildRequest(_:)`.
- **no-side-effects**: Constructing or reading any property of `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, or `AIChatContext` MUST NOT perform network access, file I/O, subprocess execution, or notification posting; the source declares only stored properties, computed accessors over stored properties, and memberwise initializers.
- **no-error-domain**: None of the initializers in this file MUST throw, and this file MUST NOT declare an `Error` type; rejecting an insufficient `AIChatContext` (e.g., a `config` missing a required field) is `AIPlugin.buildRequest(_:)`'s responsibility, which is declared `throws` for exactly that purpose (per `AIPlugin.swift`'s doc comment: "Throws if the context is insufficient (e.g. a required config value is missing)") — this file itself performs no such validation.
- **tool-schema-translation-is-the-plugins-job**: Per `AIToolSpec`'s doc comment, translating `AIChatContext.tools` into a specific provider's tool/function schema MUST happen inside the consuming `AIPlugin`'s `buildRequest(_:)`, not in `AIChatContext.swift`; this file's role is limited to carrying `name`, `description`, and `parametersJSONSchema` unchanged.

## Appearance

Not applicable — this is a data-only value-type file with no visual representation.

## States

Not applicable — this is a data-only value-type file; it has no lifecycle or visual states of its own (any runtime state, such as "loading" or "streaming," belongs to the caller driving `AIRequestSpec`/`AIStreamDecoder`, not to this file).

## Accessibility

Not applicable — this is a data-only value-type file, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-chat-context-001 | context-max-tokens-default | `AIChatContext(messages: [], model: "m", config: AIPluginConfig([:]))` with `maxTokens` omitted | `context.maxTokens == 4096` |
| ai-chat-context-002 | context-tools-default-empty | Same construction as 001, `tools` omitted | `context.tools.isEmpty == true` |
| ai-chat-context-003 | context-system-prompt-optional | Same construction as 001, `systemPrompt` omitted | `context.systemPrompt == nil` |
| ai-chat-context-004 | message-tool-fields-optional | `AIChatMessage(role: .user, content: "hi")` with no other arguments | `toolUseId == nil`, `toolName == nil`, `toolArgumentsJSON == nil`, `toolIsError == nil` |
| ai-chat-context-005 | message-role | `AIChatMessage.Role.toolUse.rawValue` and `AIChatMessage.Role.toolResult.rawValue` | `"tool_use"` and `"tool_result"` respectively |
| ai-chat-context-006 | config-value-storage, config-conventional-accessors | `AIPluginConfig(["apiKey": "k", "baseURL": "https://h", "model": "m", "extra": "x"])` (traced to `AIPluginKitTests.configAccessors`) | `config.apiKey == "k"`, `config.baseURL == "https://h"`, `config.model == "m"`, `config["extra"] == "x"`, `config["missing"] == nil` |
| ai-chat-context-007 | tool-spec-equality | Two `AIToolSpec` values with identical `name`, `description`, and `parametersJSONSchema` bytes, versus a third with the same `name`/`description` but different `parametersJSONSchema` bytes | First two compare `==`; the third compares `!=` to either |
| ai-chat-context-008 | context-config-required, context-model-required, no-error-domain | `EchoPlugin().buildRequest(AIChatContext(messages: [AIChatMessage(role: .user, content: "hi")], model: "test-model", config: AIPluginConfig(["apiKey": "secret"])))` (traced to `AIPluginKitTests.pluginBuildsRequest`) | Returned spec's `headers["x-api-key"] == "secret"` and `body == Data("test-model".utf8)`, demonstrating `model` and `config.apiKey` reach the plugin unchanged |

## Edge Cases

- **Empty `messages` array**: `AIChatContext.init` MUST NOT reject `messages: []`; the source has no non-empty check. What a plugin's `buildRequest(_:)` does with zero conversation turns is outside this file's scope.
- **Empty `model` string**: `AIChatContext.init` MUST NOT reject `model: ""`; the source performs no content validation on `model`.
- **`maxTokens` non-positive**: `AIChatContext.init` does not reject `0` or a negative `maxTokens`; the source has no lower-bound check, and every current plugin (`GooglePlugin.swift`, `OpenAICompatiblePlugin.swift`, `ClaudeAPIPlugin.swift`, `OpenAIPlugin.swift`) forwards `context.maxTokens` verbatim into its provider's request body with no clamping either, so a non-positive value reaches the network layer unvalidated. Per the Design Decisions section below, this is deliberate: `maxTokens` is treated as an opaque budget number, and enforcing a floor is left to `AIPlugin.buildRequest(_:)` or a downstream layer, not to this file.
- **`AIPluginConfig` with an empty `values` dictionary**: `apiKey`, `baseURL`, `model`, and the keyed subscript MUST all return `nil` for any key, since an empty `[String: String]` returns `nil` for every lookup.
- **`AIPluginConfig` subscript with an unrecognized key**: MUST return `nil`; the subscript is a direct dictionary lookup with no fallback or default.
- **`AIToolSpec.parametersJSONSchema` containing non-JSON or malformed bytes**: `AIToolSpec.init` MUST NOT reject it; the type performs no validation that the `Data` it carries is well-formed JSON — despite the field's name, `AIToolSpec` treats it as an opaque byte buffer. Any parsing or validation happens in the plugin that reads it.
- **`AIChatMessage` with inconsistent tool fields** (e.g., `toolArgumentsJSON` set but `toolName` and `toolUseId` both `nil`, or `role == .toolResult` with all four tool fields `nil`): `AIChatMessage.init` MUST NOT reject any such combination; the source ties no field to any other, and to `role`, by validation.
- **Concurrent access**: `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` are immutable and `Sendable`; the same instance MAY be read from multiple tasks concurrently with no synchronization, and no shared mutable state exists in this file to race on. A new instance is expected to be constructed per request rather than mutated and reused.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) to fail; a swallowed error or an unreachable server is a concern of `AIRequestSpec`/the host's transport, not this file.
- **Offline or disconnected state**: Not applicable — this file performs no network access of its own; connectivity loss mid-request is a concern of the host's transport layer (`AIRequestSpec`, driven over `URLSession` or a subprocess), not this data type.
- **Cancellation and timeouts**: Not applicable — `AIChatContext` carries no cancellation token and no timeout of its own (`timeout` lives on the sibling type `AIRequestSpec`, not here); cancelling or timing out the underlying request is the host's responsibility.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `messages` | `[AIChatMessage]` | none (required) | `AIChatContext`'s conversation history for the turn, in caller-supplied order. |
| `model` | `String` | none (required) | `AIChatContext`'s chosen model identifier, forwarded to the plugin. |
| `systemPrompt` | `String?` | `nil` | `AIChatContext`'s optional system prompt. |
| `maxTokens` | `Int` | `4096` | `AIChatContext`'s token budget for the response; unvalidated (see Edge Cases). |
| `tools` | `[AIToolSpec]` | `[]` | `AIChatContext`'s tools the host wants exposed to the model for this turn. |
| `config` | `AIPluginConfig` | none (required) | `AIChatContext`'s resolved, host-supplied configuration values (including any secret). |
| `role` | `AIChatMessage.Role` | none (required) | `AIChatMessage`'s speaker/kind: `system`, `user`, `assistant`, `toolUse`, or `toolResult`. |
| `content` | `String` | none (required) | `AIChatMessage`'s text content. |
| `toolUseId` | `String?` | `nil` | `AIChatMessage`'s identifier correlating a tool call with its result. |
| `toolName` | `String?` | `nil` | `AIChatMessage`'s tool name, when the message represents a tool call or result. |
| `toolArgumentsJSON` | `Data?` | `nil` | `AIChatMessage`'s raw JSON arguments for a tool call. |
| `toolIsError` | `Bool?` | `nil` | `AIChatMessage`'s flag marking a tool result as an error. |
| `name` | `String` | none (required) | `AIToolSpec`'s tool name. |
| `description` | `String` | none (required) | `AIToolSpec`'s tool description. |
| `parametersJSONSchema` | `Data` | none (required) | `AIToolSpec`'s raw JSON Schema bytes for the tool's parameters. |
| `values` | `[String: String]` | none (required) | `AIPluginConfig`'s resolved key/value bag, conventionally including `apiKey`, `baseURL`, and `model`. |

## Deep Linking

Not applicable: `AIChatContext.swift` defines no URL routing, navigation, or scheme handling — it is a data structure passed to `AIPlugin.buildRequest(_:)`, unrelated to app navigation.

## Localization

Not applicable: the source contains no user-facing string literals; `content`, `toolName`, `model`, and every other `String` field is caller-supplied data, not a string this file displays or hardcodes.

## Accessibility Options

Not applicable: this is a data-only value-type file with no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the source contains no analytics or event-emission calls.

## Privacy

- **Data collected**: `AIPluginConfig.values` conventionally carries a credential (`apiKey`) alongside non-secret configuration (`baseURL`, `model`, and any other plugin-declared field). Per the type's doc comment, the host is expected to have already "injected secrets (API keys) from the Keychain" before constructing the value.
- **Storage**: `AIChatContext.swift` itself stores nothing durably — `AIPluginConfig` is an in-memory value type with no persistence of its own ("the plugin never touches storage itself," per the source doc comment); the actual credential storage (the Keychain) lives outside this file, in whatever `SecretStoring` implementation the host uses.
- **Transmission**: this file performs no transmission itself; `config.apiKey`, if present, leaves the value's scope only when `AIPlugin.buildRequest(_:)` (a different file) reads it to build an outgoing request's headers or body.
- **Retention**: `AIChatContext` and `AIPluginConfig` have no retention policy of their own — an instance is expected to be constructed fresh per request ("Everything a plugin needs to build one chat request," per the source doc comment) and released once the request is built; the source provides no caching that would extend a credential's in-memory lifetime beyond that.
- **Disclosure safeguard**: `AIPluginConfig` declares no `CustomStringConvertible`/`CustomDebugStringConvertible` override, so the compiler-synthesized default description of an `AIPluginConfig` (or of an `AIChatContext` containing one) would print the entire `values` dictionary, including any credential, if a caller were to log or print the value; no redacted description exists. No caller in this repo (`LocalChatSession.swift`, `AIPluginChatBackend.swift`, `AIPluginLanguageModelProvider.swift`, `DaemonAIChat.swift`) logs or prints an `AIChatContext`/`AIPluginConfig` value today, but the type itself provides no protection against a future one doing so.

## Logging

Not applicable: the source contains no `os_log`, `Logger`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIChatContext.swift` imports only `Foundation`, with no SwiftUI dependency; any SwiftUI-based host or plugin consumes these value types unchanged, since all four are `Sendable` and carry no UI state.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). The file is plain Foundation — `struct`/`enum` value types, `Sendable` conformance, no AppKit import — so nothing in it is macOS-specific beyond the target's current platform scope.
- **Compose**: a Kotlin port would model `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` as immutable `data class`es with `val` properties; `AIChatMessage.Role` as a `kotlinx.serialization`-backed enum whose `@SerialName` values are `"tool_use"`/`"tool_result"` (matching the raw-value divergence from the case names); `parametersJSONSchema`/`toolArgumentsJSON` as `ByteArray`; `AIToolSpec`'s `Hashable` conformance is free on a Kotlin `data class` (structural `equals`/`hashCode`).
- **React/Web**: a TypeScript port would use `readonly`-field interfaces or types for all four shapes; `Role` as the string-literal union `'system' | 'user' | 'assistant' | 'tool_use' | 'tool_result'` (the union members already match the Swift raw values, unlike the Swift case names); `Data` fields as `Uint8Array` or pre-parsed `unknown`/`JSONSchema` values depending on whether the schema travels as raw bytes or parsed JSON on that platform; there is no built-in structural-equality operator, so porting `tool-spec-equality` requires a manual deep-equality helper (or a library) rather than a free `==`.
- **WinUI 3**: a .NET port would model the four types as `record`s so equality is free, mirroring Swift's synthesized `Hashable` on `AIToolSpec` — e.g. `public sealed record AIToolSpec(string Name, string Description, byte[] ParametersJsonSchema);`. `AIChatMessage.Role` would be a C# `enum` with `[EnumMember(Value = "tool_use")]`/`[EnumMember(Value = "tool_result")]` (or a custom `JsonConverter`) so JSON serialization preserves the same raw strings the Swift `rawValue`s produce. `AIChatContext` would be a `record` with C# default parameter values matching the Swift defaults exactly — `int MaxTokens = 4096` and `IReadOnlyList<AIToolSpec> Tools = Array.Empty<AIToolSpec>()` — and `AIPluginConfig` would wrap an `IReadOnlyDictionary<string, string>` with `ApiKey`/`BaseUrl`/`Model` properties reading the same three conventional keys via `TryGetValue`. `byte[]` plus `System.Text.Json.JsonSerializer`/`JsonDocument` replace Foundation's `Data`/`JSONSerialization` for the two JSON-carrying fields.

## Design Decisions

**Decision**: `AIPluginConfig` stores configuration as a flat `[String: String]` dictionary with three convenience accessors (`apiKey`, `baseURL`, `model`), rather than a strongly-typed struct with one property per plugin field.
**Rationale**: a plugin's settings schema (its `descriptor.json`, described in `AIPlugin.swift`'s doc comment) is host-resolved data, not compile-time-known fields — a stringly-typed bag is the only shape that can carry an arbitrary, plugin-declared field set without `AIPluginKit` knowing every plugin's schema in advance. Callers SHOULD use the literal keys `apiKey`, `baseURL`, and `model` for those conventional fields, since `AIPluginConfig` performs no key aliasing or normalization — a caller that stores an API key under a different key name will find `config.apiKey` returns `nil`.
**Approved**: pending

**Decision**: `AIChatContext.maxTokens` defaults to `4096` with no enforced minimum or maximum.
**Rationale**: the source treats `maxTokens` as an opaque budget number to forward to whichever provider the plugin targets; per the Edge Cases entry above, no validation exists anywhere in the current call chain (this file, `AIPlugin.buildRequest(_:)`, or any of the four current plugins), so `4096` is a convenience default rather than a validated floor.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |

`separation-of-concerns` passes because `AIChatContext.swift` performs no I/O, storage, or transport of its own — per its own doc comments, the host resolves and injects configuration, `AIPlugin.buildRequest(_:)` translates the context into a request, and this file is only the data shape shared between them. `data-minimization` is `partial`: `AIPluginConfig.values` carries the plugin's *entire* resolved field set — including a credential, when the template declares one — as a single undifferentiated dictionary passed into `AIChatContext`, with no narrower, credential-free view available to a caller that only needs `model` or `baseURL`, and no redaction safeguard on the type's default description (see the Privacy section).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited NEEDS REVIEW markers against the marker rules; kept markers are one-line named bullets. |
