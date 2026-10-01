---
id: 613d7a36-d0cd-4415-97be-d983b3d6c644
title: Chat Context
domain: agentictoolkit://cookbook/ai/chat/chat-context
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The four immutable value shapes that carry one chat turn's conversation,
  tools, and resolved configuration into a plugin's request-building step.
platforms:
- swift
- macos
tags:
- ai-plugin
- chat
- value-type
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Chat Context

## Overview

Four small, immutable value shapes together form the input contract passed
into a plugin's request-building step for one chat turn: the chat message
(one turn of conversation history), the tool specification (one tool the
model may call), the plugin configuration (the plugin's resolved,
ready-to-use configuration values), and the chat context itself (the
conversation, model, limits, tools, and configuration bundled for a single
request). None of the four performs I/O, validation beyond what its own
field constraints express, or any side effect — they are pure data carried
from the host into the request-building step, which turns them into a
description of the outgoing request (an HTTP call or a subprocess
invocation). This contract has no logic of its own: it is the shape of the
data, not an implementation of it.

## Behavioral Requirements

- **message-role**: the chat message's role MUST be one of `system`,
  `user`, `assistant`, `toolUse`, or `toolResult`, and MUST serialize as a
  string, where `toolUse` serializes as `"tool_use"` and `toolResult`
  serializes as `"tool_result"` (not the case name itself) and the other
  three cases serialize as their lowercase name.
- **message-content**: the chat message MUST carry a required text
  `content` field with no default value.
- **message-tool-fields-optional**: the chat message MUST allow
  `toolUseId`, `toolName`, `toolArgumentsJSON`, and `toolIsError` to be
  absent, and constructing one MUST default each of the four to absent when
  the caller omits it.
- **message-tool-fields-independent**: the chat message MUST NOT enforce
  any relationship between `role` and the four tool-related fields; a
  message may combine any `role` with any combination of `toolUseId`,
  `toolName`, `toolArgumentsJSON`, and `toolIsError` being present or
  absent.
- **tool-spec-identity**: the tool specification MUST require `name`,
  `description`, and `parametersJSONSchema` (raw JSON Schema bytes), none
  of which has a default value.
- **tool-spec-equality**: the tool specification MUST support equality
  comparison; two instances MUST compare equal if and only if their `name`,
  `description`, and `parametersJSONSchema` are each equal.
- **config-value-storage**: the plugin configuration MUST store its values
  as a string-keyed dictionary of strings and MUST expose a keyed lookup
  that returns the value for a key present in the dictionary, or nothing
  for a key that is absent.
- **config-conventional-accessors**: the plugin configuration MUST expose
  `apiKey`, `baseURL`, and `model` as convenience accessors reading the
  `"apiKey"`, `"baseURL"`, and `"model"` keys of its value dictionary
  respectively, returning nothing when the corresponding key is absent.
- **config-host-resolved**: the plugin configuration's values MUST already
  be fully resolved (settings-schema fields merged with secrets injected
  from secure storage) by the caller before the value is constructed; per
  its own documentation, "the plugin never touches storage itself" — the
  plugin configuration and the chat context MUST NOT perform any storage or
  settings-schema access of their own.
- **context-messages-required**: the chat context MUST require a
  `messages` list of chat messages with no default value, representing the
  full conversation history for the turn in caller-supplied order.
- **context-model-required**: the chat context MUST require a `model`
  string with no default value.
- **context-system-prompt-optional**: the chat context MUST allow
  `systemPrompt` to be absent and MUST default it to absent when the caller
  omits it.
- **context-max-tokens-default**: the chat context MUST default
  `maxTokens` to `4096` when the caller omits it.
- **context-tools-default-empty**: the chat context MUST default `tools`
  to an empty list when the caller omits it.
- **context-config-required**: the chat context MUST require a `config`
  (a plugin configuration value) with no default value.
- **immutability**: the chat message, the tool specification, the plugin
  configuration, and the chat context MUST expose every stored value as
  unchangeable once constructed; none of the four MUST provide any way to
  mutate an existing instance after construction.
- **sendability**: the chat message, its role, the tool specification, the
  plugin configuration, and the chat context MUST each be safe to pass
  across a concurrency-domain boundary; because each holds only values that
  are themselves safe to share this way (strings, raw bytes, whole numbers,
  booleans, string-keyed dictionaries of strings, and lists thereof), no
  manual synchronization is required to move an instance from the host into
  a plugin's request-building step.
- **concurrent-read-safety**: Because every value on all four types is
  unchangeable and safe to share across concurrency boundaries, a single
  constructed instance MAY be read concurrently from multiple points of
  execution with no additional locking, and no operation defined by this
  contract mutates shared state, so no ordering or serialization rule is
  needed between concurrent reads of the same instance.
- **no-persistence**: the chat message, the tool specification, the plugin
  configuration, and the chat context MUST NOT persist or cache any of
  their fields; none defines any file, database, or secure-storage access,
  and each instance exists only as a transient parameter for one call into
  a plugin's request-building step.
- **no-side-effects**: Constructing or reading any field of the chat
  message, the tool specification, the plugin configuration, or the chat
  context MUST NOT perform network access, file I/O, subprocess execution,
  or notification posting; each is limited to stored values, simple
  accessors over those values, and a way to construct one from its parts.
- **no-error-domain**: Constructing any of the four types MUST NOT fail
  with an error, and this contract MUST NOT declare an error type of its
  own; rejecting an insufficient chat context (e.g., a `config` missing a
  required field) is the request-building step's responsibility, which is
  defined to be able to fail for exactly that purpose ("Fails if the
  context is insufficient, e.g. a required config value is missing") —
  this contract itself performs no such validation.
- **tool-schema-translation-is-the-plugins-job**: Translating the chat
  context's `tools` into a specific provider's tool/function schema MUST
  happen inside the consuming plugin's request-building step, not in this
  contract; the tool specification's role is limited to carrying `name`,
  `description`, and `parametersJSONSchema` unchanged.

## Appearance

Not applicable — this is a data-only contract with no visual
representation.

## States

Not applicable — this is a data-only contract; it has no lifecycle or
visual states of its own (any runtime state, such as "loading" or
"streaming," belongs to the caller driving the request and decoding its
response, not to this contract).

## Accessibility

Not applicable — this is a data-only contract, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-chat-context-001 | context-max-tokens-default | A chat context constructed with an empty message list, model `"m"`, and an empty-valued plugin configuration, with `maxTokens` omitted | `maxTokens` reads `4096` |
| ai-chat-context-002 | context-tools-default-empty | Same construction as 001, with `tools` omitted | `tools` reads empty |
| ai-chat-context-003 | context-system-prompt-optional | Same construction as 001, with `systemPrompt` omitted | `systemPrompt` reads absent |
| ai-chat-context-004 | message-tool-fields-optional | A chat message constructed with role `user` and content `"hi"`, with no other arguments given | `toolUseId`, `toolName`, `toolArgumentsJSON`, and `toolIsError` all read absent |
| ai-chat-context-005 | message-role | The serialized form of the `toolUse` and `toolResult` roles | `"tool_use"` and `"tool_result"` respectively |
| ai-chat-context-006 | config-value-storage, config-conventional-accessors | A plugin configuration built from `{"apiKey": "k", "baseURL": "https://h", "model": "m", "extra": "x"}` (traced to `AIPluginKitTests.configAccessors`) | `apiKey` reads `"k"`, `baseURL` reads `"https://h"`, `model` reads `"m"`, the `"extra"` key reads `"x"`, and a `"missing"` key reads absent |
| ai-chat-context-007 | tool-spec-equality | Two tool specifications with identical `name`, `description`, and `parametersJSONSchema` bytes, versus a third with the same `name`/`description` but different `parametersJSONSchema` bytes | The first two compare equal; the third compares unequal to either |
| ai-chat-context-008 | context-config-required, context-model-required, no-error-domain | A minimal test plugin's request-building step, given a chat context with one user message `"hi"`, model `"test-model"`, and a plugin configuration holding only `apiKey: "secret"` (traced to `AIPluginKitTests.pluginBuildsRequest`) | The resulting request description carries `"secret"` under an `x-api-key` header and a body equal to the literal text `"test-model"`, demonstrating `model` and the configuration's `apiKey` reach the plugin unchanged |

## Edge Cases

- **Empty `messages` list**: constructing a chat context MUST NOT reject an
  empty message list; nothing in this contract requires a non-empty
  history. What a plugin's request-building step does with zero
  conversation turns is outside this contract's scope.
- **Empty `model` string**: constructing a chat context MUST NOT reject
  `model: ""`; this contract performs no content validation on `model`.
- **`maxTokens` non-positive**: constructing a chat context does not
  reject `0` or a negative `maxTokens`; there is no lower-bound check, and
  every plugin currently implemented forwards `context.maxTokens` verbatim
  into its provider's request body with no clamping either (see Platform
  Notes for which plugins), so a non-positive value reaches the network
  layer unvalidated. Per the Design Decisions section below, this is
  deliberate: `maxTokens` is treated as an opaque budget number, and
  enforcing a floor is left to the request-building step or a downstream
  layer, not to this contract.
- **Plugin configuration with an empty value dictionary**: `apiKey`,
  `baseURL`, `model`, and the keyed lookup MUST all return nothing for any
  key, since an empty dictionary returns nothing for every lookup.
- **Plugin configuration lookup with an unrecognized key**: MUST return
  nothing; the lookup is a direct dictionary read with no fallback or
  default.
- **Tool specification's `parametersJSONSchema` containing non-JSON or
  malformed bytes**: constructing a tool specification MUST NOT reject it;
  this contract performs no validation that the raw bytes it carries are
  well-formed JSON — despite the field's name, it is treated as an opaque
  byte buffer. Any parsing or validation happens in the plugin that reads
  it.
- **Chat message with inconsistent tool fields** (e.g., `toolArgumentsJSON`
  set but `toolName` and `toolUseId` both absent, or `role == toolResult`
  with all four tool fields absent): constructing a chat message MUST NOT
  reject any such combination; this contract ties no field to any other,
  or to `role`, by validation.
- **Concurrent access**: the chat message, the tool specification, the
  plugin configuration, and the chat context are all unchangeable and safe
  to share across concurrency boundaries; the same instance MAY be read
  from multiple points of execution concurrently with no synchronization,
  and no shared mutable state exists in this contract to race on. A new
  instance is expected to be constructed per request rather than mutated
  and reused.
- **Error states from a dependency**: Not applicable — this contract has
  no dependency (no network, database, or file-system call) to fail; a
  swallowed error or an unreachable server is a concern of the resulting
  request description or the host's transport, not this contract.
- **Offline or disconnected state**: Not applicable — this contract
  performs no network access of its own; connectivity loss mid-request is
  a concern of the host's transport layer, driven over a network
  connection or a subprocess, not this data.
- **Cancellation and timeouts**: Not applicable — the chat context carries
  no cancellation token and no timeout of its own (timeout lives on the
  sibling request-description type, not here); cancelling or timing out
  the underlying request is the host's responsibility.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `messages` | list of chat messages | none (required) | The chat context's conversation history for the turn, in caller-supplied order. |
| `model` | string | none (required) | The chat context's chosen model identifier, forwarded to the plugin. |
| `systemPrompt` | optional string | absent | The chat context's optional system prompt. |
| `maxTokens` | whole number | `4096` | The chat context's token budget for the response; unvalidated (see Edge Cases). |
| `tools` | list of tool specifications | empty | The chat context's tools the host wants exposed to the model for this turn. |
| `config` | plugin configuration value | none (required) | The chat context's resolved, host-supplied configuration values (including any secret). |
| `role` | role value | none (required) | The chat message's speaker/kind: `system`, `user`, `assistant`, `toolUse`, or `toolResult`. |
| `content` | string | none (required) | The chat message's text content. |
| `toolUseId` | optional string | absent | The chat message's identifier correlating a tool call with its result. |
| `toolName` | optional string | absent | The chat message's tool name, when the message represents a tool call or result. |
| `toolArgumentsJSON` | optional raw bytes | absent | The chat message's raw JSON arguments for a tool call. |
| `toolIsError` | optional boolean | absent | The chat message's flag marking a tool result as an error. |
| `name` | string | none (required) | The tool specification's tool name. |
| `description` | string | none (required) | The tool specification's tool description. |
| `parametersJSONSchema` | raw bytes | none (required) | The tool specification's raw JSON Schema bytes for the tool's parameters. |
| `values` | string-keyed dictionary of strings | none (required) | The plugin configuration's resolved key/value bag, conventionally including `apiKey`, `baseURL`, and `model`. |

## Deep Linking

Not applicable: this contract defines no URL routing, navigation, or scheme
handling — it is data passed into a plugin's request-building step,
unrelated to app navigation.

## Localization

Not applicable: this contract contains no user-facing string literals of
its own; `content`, `toolName`, `model`, and every other string field is
caller-supplied data, not a string this contract displays or hardcodes.

## Accessibility Options

Not applicable: this is a data-only contract with no UI, so it responds to
no Reduce Motion, Increase Contrast, or Differentiate Without Color
setting.

## Feature Flags

Not applicable: this contract declares no feature-flag key and contains no
conditional feature-gating logic.

## Analytics

Not applicable: this contract contains no analytics or event-emission
calls.

## Privacy

- **Data collected**: the plugin configuration's values conventionally
  carry a credential (`apiKey`) alongside non-secret configuration
  (`baseURL`, `model`, and any other plugin-declared field). Per its own
  documentation, the host is expected to have already "injected secrets
  (API keys) from secure storage" before constructing the value.
- **Storage**: this contract itself stores nothing durably — the plugin
  configuration is an in-memory value with no persistence of its own ("the
  plugin never touches storage itself," per its own documentation); the
  actual credential storage lives outside this contract, in whatever
  secure-storage mechanism the host uses.
- **Transmission**: this contract performs no transmission itself; the
  configuration's `apiKey`, if present, leaves the value's scope only when
  a plugin's request-building step reads it to build an outgoing request's
  headers or body.
- **Retention**: the chat context and the plugin configuration have no
  retention policy of their own — an instance is expected to be constructed
  fresh per request ("Everything a plugin needs to build one chat
  request," per its own documentation) and released once the request is
  built; nothing in this contract caches a value in a way that would
  extend a credential's in-memory lifetime beyond that.
- **Disclosure safeguard**: the plugin configuration provides no redacted
  description of itself, so a caller's default way of printing or logging
  one (or of a chat context containing one) would include the entire value
  dictionary, including any credential. No caller in this codebase logs or
  prints a chat context or plugin configuration value today (see Platform
  Notes for which files were checked), but this contract itself provides
  no protection against a future one doing so.

## Logging

Not applicable: this contract contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIChatContext.swift` imports
  only `Foundation`, with no SwiftUI dependency; any SwiftUI-based host or
  plugin consumes these value types unchanged, since all four are
  `Sendable` and carry no UI state.
- **AppKit / UIKit**: this is the source. The file is
  `packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift`, part of
  the `AIPluginKit` framework target, which `project.yml` declares as
  `platform: macOS` only (no iOS target exists for it today). It declares
  four Foundation-only, `Sendable` value types: `AIChatMessage` (with a
  `Role: String`-backed enum whose `toolUse`/`toolResult` cases have
  explicit raw values `"tool_use"`/`"tool_result"`), `AIToolSpec`
  (`Hashable` via compiler-synthesized memberwise conformance over `name`,
  `description`, `parametersJSONSchema: Data`), `AIPluginConfig` (wrapping
  a `[String: String]` named `values`, with `apiKey`/`baseURL`/`model` as
  computed properties over `values[...]`, plus a keyed `subscript`), and
  `AIChatContext` itself (`messages: [AIChatMessage]`, `model: String`,
  `systemPrompt: String?`, `maxTokens: Int = 4096`, `tools: [AIToolSpec] =
  []`, `config: AIPluginConfig`). All four are `struct`s
  (`AIChatMessage.Role` is an `enum`) with every stored property declared
  `let`, so immutability and `Sendable` conformance are both
  compiler-enforced; none declares a throwing initializer, matching
  `no-error-domain` — rejecting an insufficient context is `AIPlugin
  .buildRequest(_:) throws`'s job, on the sibling `AIPlugin.swift`.
  `AIPluginConfig`'s doc comment states the plugin never touches storage
  itself; the host is expected to merge the plugin's settings-schema
  fields with secrets it has already read from the Keychain (via whatever
  `SecretStoring` implementation the host uses) before constructing one.
  `AIPluginConfig` declares no `CustomStringConvertible`/
  `CustomDebugStringConvertible` override, so its compiler-synthesized
  default description prints the entire `values` dictionary — including
  any credential — if logged or printed; no current caller
  (`LocalChatSession.swift`, `AIPluginChatBackend.swift`,
  `AIPluginLanguageModelProvider.swift`, `DaemonAIChat.swift`) does so
  today. The unclamped-`maxTokens` edge case above traces to
  `GooglePlugin.swift`, `OpenAICompatiblePlugin.swift`,
  `ClaudeAPIPlugin.swift`, and `OpenAIPlugin.swift`, each of which forwards
  `context.maxTokens` into its provider's request body with no clamping.
- **Compose**: a Kotlin port would model `AIChatMessage`, `AIToolSpec`,
  `AIPluginConfig`, and `AIChatContext` as immutable `data class`es with
  `val` properties; `AIChatMessage.Role` as a `kotlinx.serialization`-backed
  enum whose `@SerialName` values are `"tool_use"`/`"tool_result"`
  (matching the raw-value divergence from the case names); `parametersJSONSchema`
  /`toolArgumentsJSON` as `ByteArray`; `AIToolSpec`'s `Hashable` conformance
  is free on a Kotlin `data class` (structural `equals`/`hashCode`).
- **React/Web**: a TypeScript port would use `readonly`-field interfaces or
  types for all four shapes; `Role` as the string-literal union `'system' |
  'user' | 'assistant' | 'tool_use' | 'tool_result'` (the union members
  already match the raw values, unlike the case names); `Data` fields as
  `Uint8Array` or pre-parsed `unknown`/`JSONSchema` values depending on
  whether the schema travels as raw bytes or parsed JSON on that platform;
  there is no built-in structural-equality operator, so porting
  `tool-spec-equality` requires a manual deep-equality helper (or a
  library) rather than a free `==`.
- **WinUI 3**: a .NET port would model the four types as `record`s so
  equality is free, mirroring the synthesized `Hashable` on `AIToolSpec` —
  e.g. `public sealed record AIToolSpec(string Name, string Description,
  byte[] ParametersJsonSchema);`. `AIChatMessage.Role` would be a C# `enum`
  with `[EnumMember(Value = "tool_use")]`/`[EnumMember(Value =
  "tool_result")]` (or a custom `JsonConverter`) so JSON serialization
  preserves the same raw strings. `AIChatContext` would be a `record` with
  C# default parameter values matching the defaults exactly — `int
  MaxTokens = 4096` and `IReadOnlyList<AIToolSpec> Tools =
  Array.Empty<AIToolSpec>()` — and `AIPluginConfig` would wrap an
  `IReadOnlyDictionary<string, string>` with `ApiKey`/`BaseUrl`/`Model`
  properties reading the same three conventional keys via `TryGetValue`.
  `byte[]` plus `System.Text.Json.JsonSerializer`/`JsonDocument` replace
  Foundation's `Data`/`JSONSerialization` for the two JSON-carrying fields.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift` |

## Design Decisions

**Decision**: the plugin configuration stores configuration as a flat
string-keyed dictionary of strings with three convenience accessors
(`apiKey`, `baseURL`, `model`), rather than a strongly-typed shape with one
field per plugin-declared value.
**Rationale**: (Swift implementation) a plugin's settings schema (its
`descriptor.json`, described alongside `AIPlugin.swift`) is host-resolved
data, not compile-time-known fields — a stringly-typed bag is the only
shape that can carry an arbitrary, plugin-declared field set without this
contract knowing every plugin's schema in advance. Callers SHOULD use the
literal keys `apiKey`, `baseURL`, and `model` for those conventional
fields, since the plugin configuration performs no key aliasing or
normalization — a caller that stores an API key under a different key name
will find `apiKey` returns nothing.
**Approved**: pending

**Decision**: the chat context's `maxTokens` defaults to `4096` with no
enforced minimum or maximum.
**Rationale**: this contract treats `maxTokens` as an opaque budget number
to forward to whichever provider the plugin targets; per the Edge Cases
entry above, no validation exists anywhere in the current call chain (this
contract, the request-building step, or any of the plugins implemented
today), so `4096` is a convenience default rather than a validated floor.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |

`separation-of-concerns` passes because `AIChatContext.swift` performs no
I/O, storage, or transport of its own — per its own doc comments, the host
resolves and injects configuration, `AIPlugin.buildRequest(_:)` translates
the context into a request, and this file is only the data shape shared
between them. `data-minimization` is `partial`: `AIPluginConfig.values`
carries the plugin's *entire* resolved field set — including a credential,
when the template declares one — as a single undifferentiated dictionary
passed into `AIChatContext`, with no narrower, credential-free view
available to a caller that only needs `model` or `baseURL`, and no
redaction safeguard on the type's default description (see the Privacy
section).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/chat/. |
