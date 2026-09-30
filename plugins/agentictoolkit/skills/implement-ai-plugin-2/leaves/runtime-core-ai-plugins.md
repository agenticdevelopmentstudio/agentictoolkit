<!-- leaf: implement-ai-plugin-2/runtime-core-ai-plugins · source: ai-plugin-runtime-core-ai-plugins.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-core-ai-plugins#<slug>`):

- `stream-event-case-set` MUST
- `stream-event-sendable` MUST
- `text-delta-payload` MUST
- `tool-use-payload` MUST
- `tool-use-arguments-raw` MUST
- `end-stop-reason-optional` MUST
- `stream-emission-contract` MUST
- `tool-call-result-correlation` MUST
- `definition-identity` MUST
- `definition-equality` MUST
- `definition-sendable` MUST
- `definition-immutability` MUST
- `definition-schema-opaque` MUST
- `definition-provider-translation-elsewhere` MUST
- `result-identity` MUST
- `result-equality` MUST
- `result-sendable` MUST
- `result-immutability` MUST
- `result-error-flag-independence` MUST
- `cross-domain-safety` MAY
- `no-persistence-no-side-effects` MUST
- `data-handled` MAY — A .textDelta or .toolUse ChatStreamEvent MAY carry assistant-generated conversational content or the model's raw …

# Chat Stream Event & Tool Types

## Overview

`ChatStreamEvent.swift`, `ToolDefinition.swift`, and `ToolResult.swift` (all in `packages/apple/AgenticToolkit/Core/AIPlugins/`, part of the `AgenticToolkitCore` framework target) declare three small, Foundation-only value types that carry tool-calling data across the `Core` chat layer: `ChatStreamEvent` (a `Sendable` enum — one event in the assistant response stream that the tool-aware `ChatBackend.sendMessages(_:tools:)` overload returns), `ToolDefinition` (a `Sendable`, `Hashable` struct — one tool advertised to the model, the element type `ChatToolSource.toolDefinitions()` returns), and `ToolResult` (a `Sendable`, `Hashable` struct — the outcome of running one tool call, per its doc comment). None of the three performs I/O; each is a closed, immutable data shape with either a fixed case list or an explicit memberwise initializer and no other logic.

All three have counterparts elsewhere in the codebase that this recipe does not otherwise cover. `ChatStreamEvent` mirrors — but is a distinct type from — the sibling `AIStreamEvent` in `AIPluginKit`; `AIPluginChatBackend.chatEvent(for:)` maps one to the other case-for-case with no transformation. `ToolDefinition` similarly mirrors `AIToolSpec`; `LocalChatSession.withTools(_:)` and `AIPluginChatBackend.aiToolSpec(for:)` each copy a `ToolDefinition`'s three fields unchanged into an `AIToolSpec`. `ToolResult` has no current call site in this codebase that constructs it: the one tool-dispatch loop present, `LocalChatSession.runTurn`, builds an `AIChatMessage(role: .toolResult, ...)` directly from the `(content: String, isError: Bool)` tuple `ChatToolSource.callTool(name:argumentsJSON:)` returns, rather than a `ToolResult` value — see Design Decisions.

## Behavioral Requirements

- **stream-event-case-set**: `ChatStreamEvent` MUST have exactly three cases — `textDelta(String)`, `toolUse(id: String, name: String, argumentsJSON: Data)`, and `end(stopReason: String?)` (`ChatStreamEvent.swift`).
- **stream-event-sendable**: `ChatStreamEvent` MUST conform to `Sendable` (`ChatStreamEvent.swift`).
- **text-delta-payload**: `.textDelta`'s associated value MUST be exactly one `String` chunk of assistant text and carry no other data; the type imposes no constraint on chunk size or where a chunk boundary falls.
- **tool-use-payload**: `.toolUse`'s associated values MUST be `id: String`, `name: String`, and `argumentsJSON: Data`.
- **tool-use-arguments-raw**: `argumentsJSON` on a `.toolUse` event MUST carry the model's tool-call arguments as raw, undecoded JSON bytes, unchanged from the `AIStreamEvent.toolUse` value it is mapped from — `AIPluginChatBackend.chatEvent(for:)` passes `argumentsJSON` straight through with no parsing, and `ChatStreamEvent.swift` itself performs no JSON decoding of the field.
- **end-stop-reason-optional**: `.end`'s `stopReason` MUST be `Optional<String>`, so a producer MAY report `nil` when no reason is available.
- **stream-emission-contract**: Per the type's doc comment, a text-only backend MUST emit only `.textDelta` and `.end` events on a stream it returns, and a tool-capable backend MUST additionally emit one `.toolUse` event for each call the model requests ("Text-only backends only emit `.textDelta` and `.end`; tool-capable backends additionally emit `.toolUse` for each call the model wants to make").
- **tool-call-result-correlation**: The `id` carried by a `.toolUse` event MUST be the same identifier a caller later supplies when reporting that call's outcome, whether as `ToolResult.toolUseId` or as `AIChatMessage.toolUseId` on a `.toolResult`-role message — `LocalChatSession.runTurn` propagates the same `use.id` recorded from each pending tool call into the `AIChatMessage(role: .toolResult, ..., toolUseId: use.id, ...)` it later appends.
- **definition-identity**: `ToolDefinition` MUST require `name: String`, `description: String`, and `parametersJSONSchema: Data`, none of which has a default value (`ToolDefinition.swift`).
- **definition-equality**: `ToolDefinition` MUST conform to `Hashable`; two instances MUST compare equal if and only if their `name`, `description`, and `parametersJSONSchema` are each equal — the compiler-synthesized memberwise conformance over all three stored properties.
- **definition-sendable**: `ToolDefinition` MUST conform to `Sendable`.
- **definition-immutability**: `ToolDefinition` MUST declare `name`, `description`, and `parametersJSONSchema` as immutable `let` properties and MUST provide no method that mutates an existing instance (the type declares only the memberwise initializer).
- **definition-schema-opaque**: `parametersJSONSchema` MUST be treated as an opaque, pre-serialized JSON Schema byte buffer — `ToolDefinition` MUST NOT parse, decode, or validate it; no method in `ToolDefinition.swift` reads or transforms the field beyond storing and returning it.
- **definition-provider-translation-elsewhere**: Translating a `ToolDefinition` into a specific backend's provider tool schema (Anthropic `tools`, OpenAI `functions`, etc.) MUST happen in the consuming backend, not in `ToolDefinition` itself, per the type's doc comment ("Backends translate this into the provider-specific shape... before sending the request") — `AIPluginChatBackend.aiToolSpec(for:)` and `LocalChatSession.withTools(_:)` each perform exactly this translation, copying the three fields unchanged into an `AIToolSpec`.
- **result-identity**: `ToolResult` MUST require `toolUseId: String`, `content: String`, and `isError: Bool`, none of which has a default value (`ToolResult.swift`).
- **result-equality**: `ToolResult` MUST conform to `Hashable`; two instances MUST compare equal if and only if their `toolUseId`, `content`, and `isError` are each equal.
- **result-sendable**: `ToolResult` MUST conform to `Sendable`.
- **result-immutability**: `ToolResult` MUST declare `toolUseId`, `content`, and `isError` as immutable `let` properties and MUST provide no method that mutates an existing instance.
- **result-error-flag-independence**: `ToolResult` MUST NOT enforce any relationship between `isError` and `content` — the initializer stores both fields exactly as given, with no validation tying them together; a caller MAY construct `isError: true` with non-empty `content` (an error message) or `isError: false` with empty `content`.
- **cross-domain-safety**: Because `ChatStreamEvent`, `ToolDefinition`, and `ToolResult` are all `Sendable` and every stored or associated value is itself `Sendable` (`String`, `Data`, `Bool`, `String?`), an instance of any of the three types MAY cross a concurrency-domain boundary — e.g. from `AIPluginChatBackend`'s background `Task` into a `@MainActor` chat UI, or from `LocalChatSession`'s tool-dispatch loop into a `ChatToolSource` actor — with no additional synchronization.
- **no-persistence-no-side-effects**: Constructing or reading any case or field of `ChatStreamEvent`, `ToolDefinition`, or `ToolResult` MUST NOT perform file, database, `UserDefaults`, Keychain, or network access, and none of the three files persists or caches a value beyond the caller's own variable lifetime — each file declares only a case list or stored properties plus an initializer, with no I/O of any kind.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `textDelta` payload | `String` | none (required) | `ChatStreamEvent`'s chunk of assistant text for this event. |
| `toolUse.id` | `String` | none (required) | `ChatStreamEvent`'s identifier for one model-requested tool call. |
| `toolUse.name` | `String` | none (required) | `ChatStreamEvent`'s name of the tool the model wants to call. |
| `toolUse.argumentsJSON` | `Data` | none (required) | `ChatStreamEvent`'s raw, undecoded JSON arguments for the call. |
| `end.stopReason` | `String?` | none (`Optional`) | `ChatStreamEvent`'s provider-supplied reason the stream ended, or `nil`. |
| `name` | `String` | none (required) | `ToolDefinition`'s tool name advertised to the model. |
| `description` | `String` | none (required) | `ToolDefinition`'s tool description advertised to the model. |
| `parametersJSONSchema` | `Data` | none (required) | `ToolDefinition`'s opaque JSON Schema bytes for the tool's parameters. |
| `toolUseId` | `String` | none (required) | `ToolResult`'s identifier correlating this outcome with its originating `.toolUse` call. |
| `content` | `String` | none (required) | `ToolResult`'s result text, or error text, from running the tool. |
| `isError` | `Bool` | none (required) | `ToolResult`'s flag marking whether the tool call failed. |

These three files define no environment variable and no settings key of their own — every value arrives as an associated value on a `ChatStreamEvent` case, or as a parameter to `ToolDefinition.init`/`ToolResult.init`.

## Privacy

- **Data handled**: A `.textDelta` or `.toolUse` `ChatStreamEvent` MAY carry assistant-generated conversational content or the model's raw tool-call arguments; `ToolDefinition.description`/`parametersJSONSchema` carry host-declared tool metadata rather than end-user data; `ToolResult.content` MAY carry whatever a tool execution returns, which — per `MCPChatToolSource.callTool` — can include arbitrary MCP server output such as file contents or search results. None of the three types defines a credential or token field of its own.
- **Storage**: None of the three files persists anything — each is an in-memory value type with no file, database, `UserDefaults`, or Keychain access of its own.
- **Transmission**: None of the three files transmits data itself; a value is only carried in-memory between the model-facing backend that produces it and the chat UI or tool source that consumes it.
- **Retention**: None — an instance of any of the three types lives only as long as the caller holds it (one stream element, one advertised tool, one tool outcome); no cache in these files extends its lifetime.

