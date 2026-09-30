<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context · source: ai-plugin-runtime-ai-plugin-kit-ai-chat-context.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context#<slug>`):

- `message-role` MUST
- `message-content` MUST
- `message-tool-fields-optional` MUST
- `message-tool-fields-independent` MUST
- `tool-spec-identity` MUST
- `tool-spec-equality` MUST
- `config-value-storage` MUST
- `config-conventional-accessors` MUST
- `config-host-resolved` MUST
- `context-messages-required` MUST
- `context-model-required` MUST
- `context-system-prompt-optional` MUST
- `context-max-tokens-default` MUST
- `context-tools-default-empty` MUST
- `context-config-required` MUST
- `immutability` MUST
- `sendability` MUST
- `concurrent-read-safety` MAY
- `no-persistence` MUST
- `no-side-effects` MUST
- `no-error-domain` MUST
- `tool-schema-translation-is-the-plugins-job` MUST

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

## Privacy

- **Data collected**: `AIPluginConfig.values` conventionally carries a credential (`apiKey`) alongside non-secret configuration (`baseURL`, `model`, and any other plugin-declared field). Per the type's doc comment, the host is expected to have already "injected secrets (API keys) from the Keychain" before constructing the value.
- **Storage**: `AIChatContext.swift` itself stores nothing durably — `AIPluginConfig` is an in-memory value type with no persistence of its own ("the plugin never touches storage itself," per the source doc comment); the actual credential storage (the Keychain) lives outside this file, in whatever `SecretStoring` implementation the host uses.
- **Transmission**: this file performs no transmission itself; `config.apiKey`, if present, leaves the value's scope only when `AIPlugin.buildRequest(_:)` (a different file) reads it to build an outgoing request's headers or body.
- **Retention**: `AIChatContext` and `AIPluginConfig` have no retention policy of their own — an instance is expected to be constructed fresh per request ("Everything a plugin needs to build one chat request," per the source doc comment) and released once the request is built; the source provides no caching that would extend a credential's in-memory lifetime beyond that.
- **Disclosure safeguard**: `AIPluginConfig` declares no `CustomStringConvertible`/`CustomDebugStringConvertible` override, so the compiler-synthesized default description of an `AIPluginConfig` (or of an `AIChatContext` containing one) would print the entire `values` dictionary, including any credential, if a caller were to log or print the value; no redacted description exists. No caller in this repo (`LocalChatSession.swift`, `AIPluginChatBackend.swift`, `AIPluginLanguageModelProvider.swift`, `DaemonAIChat.swift`) logs or prints an `AIChatContext`/`AIPluginConfig` value today, but the type itself provides no protection against a future one doing so.

