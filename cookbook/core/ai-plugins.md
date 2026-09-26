---
id: f305da79-fa03-493e-9c08-7186530943c6
title: Chat Stream Event & Tool Types
domain: agentictoolkit://cookbook/core/ai-plugins
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Three Sendable value types — ChatStreamEvent, ToolDefinition, ToolResult
  — that carry chat tool-calling data across ChatBackend and ChatToolSource.
platforms:
- swift
- macos
tags:
- ai-plugin
- chat
- tool-calling
- streaming
- value-type
- sendable
- foundation
depends-on: []
related:
- agentictoolkit://cookbook/ai-plugin-kit/ai-stream-event
- agentictoolkit://cookbook/ai-plugin-kit/ai-chat-context
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a set of Sendable chat tool-calling value types, not a visual component.

## States

Not applicable — this is a set of Sendable chat tool-calling value types, not a visual component.

## Accessibility

Not applicable — this is a set of Sendable chat tool-calling value types, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-tool-types-001 | stream-event-case-set, stream-event-sendable | Inspect `ChatStreamEvent.swift`. | Exactly three cases — `textDelta`, `toolUse`, `end` — and the enum declares `Sendable` conformance. |
| chat-tool-types-002 | text-delta-payload | `ChatStreamEvent.textDelta("Hello")`, pattern-matched with `if case let .textDelta(text) = event`. | `text == "Hello"`, with no other payload carried. |
| chat-tool-types-003 | tool-use-payload, tool-use-arguments-raw | `ChatStreamEvent.toolUse(id: "call_1", name: "search", argumentsJSON: Data("{\"q\":\"cats\"}".utf8))`, pattern-matched as `LocalChatSession.swift`'s `case .toolUse(let id, let name, let args):` does. | `id == "call_1"`, `name == "search"`, and `args` equals the exact `Data` given, byte for byte, unparsed. |
| chat-tool-types-004 | end-stop-reason-optional | Construct `ChatStreamEvent.end(stopReason: nil)`. | Constructs without error; `stopReason` is `nil`. |
| chat-tool-types-005 | stream-emission-contract | Drive `ChatBackend`'s default `sendMessages(_:tools:)` extension (`ChatBackend.swift`) with a text-only `sendMessages(_:)` stream of two chunks. | The returned `ChatStreamEvent` stream yields two `.textDelta` events, then exactly one `.end(stopReason: nil)` — no `.toolUse`. |
| chat-tool-types-006 | tool-call-result-correlation | Run `LocalChatSession.runTurn` for a turn with one pending tool call `id == "call_1"`; inspect the `AIChatMessage(role: .toolResult, ...)` it appends. | The appended message's `toolUseId == "call_1"`, matching the `id` `LocalChatSession` recorded from the `.toolUse` event. |
| chat-tool-types-007 | definition-identity, definition-sendable | `ToolDefinition(name: "search", description: "Search the web", parametersJSONSchema: Data("{}".utf8))`. | Constructs without error; all three fields hold the given values unchanged. |
| chat-tool-types-008 | definition-equality | Two `ToolDefinition` values with identical `name`/`description`/`parametersJSONSchema` bytes, versus a third with the same `name`/`description` but different `parametersJSONSchema` bytes. | The first two compare `==`; the third compares `!=` to either. |
| chat-tool-types-009 | definition-immutability | Attempt `toolDef.name = "other"` where `toolDef: ToolDefinition` is a `let`. | Fails to compile — `name` is declared `let`, not `var`. |
| chat-tool-types-010 | definition-provider-translation-elsewhere | `LocalChatSession.withTools([ToolDefinition(name: "n", description: "d", parametersJSONSchema: schema)])` (`LocalChatSession.swift`). | Returns an `AIChatContext` whose `tools` contains one `AIToolSpec(name: "n", description: "d", parametersJSONSchema: schema)` — the three fields copied unchanged. |
| chat-tool-types-011 | result-identity, result-sendable | `ToolResult(toolUseId: "call_1", content: "42", isError: false)`. | Constructs without error; all three fields hold the given values unchanged. |
| chat-tool-types-012 | result-equality | Two `ToolResult` values with identical `toolUseId`/`content`/`isError`, versus a third with `isError` flipped. | The first two compare `==`; the third compares `!=` to either. |
| chat-tool-types-013 | result-error-flag-independence | `ToolResult(toolUseId: "call_1", content: "", isError: true)` and `ToolResult(toolUseId: "call_2", content: "ok", isError: false)`. | Both construct without error — empty `content` with `isError: true`, and non-empty `content` with `isError: false`, are both accepted. |
| chat-tool-types-014 | result-immutability | Attempt `toolResult.content = "x"` where `toolResult: ToolResult` is a `let`. | Fails to compile — `content` is declared `let`. |
| chat-tool-types-015 | cross-domain-safety | Capture a `[ToolDefinition]` in the `@Sendable` closure `AIPluginChatBackend.makeInputs(messages:tools:)` builds inside a `MainActor.run` block, then read it inside `Self.drive`'s background `Task` (`AIPluginChatBackend.swift`). | Compiles under `SWIFT_STRICT_CONCURRENCY: complete` with no `Sendable`-conformance error. |
| chat-tool-types-016 | no-persistence-no-side-effects | Inspect `ChatStreamEvent.swift`, `ToolDefinition.swift`, and `ToolResult.swift` in full. | No file, database, `UserDefaults`, Keychain, or network API is referenced in any of the three files. |
| chat-tool-types-017 | tool-use-payload, definition-schema-opaque | `ToolDefinition(name: "n", description: "d", parametersJSONSchema: Data("not valid json".utf8))`. | Constructs without error — the type performs no JSON validation on `parametersJSONSchema`. |

## Edge Cases

- **Null / empty input**: `ChatStreamEvent.textDelta("")`, `ToolDefinition(name: "", description: "", parametersJSONSchema: Data())`, and `ToolResult(toolUseId: "", content: "", isError: false)` MUST all be constructible — none of the three files performs a non-empty check on any `String` or `Data` field.
- **Boundary values**: Not applicable in the numeric sense — none of the three types declares a size-limited field of its own (no maximum length on `content`, `description`, `argumentsJSON`, or `parametersJSONSchema`). Any upper bound on how large a tool's arguments or schema may grow is enforced by the transport or provider that eventually sends the bytes, not by these files.
- **Concurrent access**: Because all three types are `Sendable` and every field or associated value is immutable, the same instance MAY be read from multiple tasks concurrently with no synchronization; there is no shared mutable state in any of the three files to race on. A new instance is expected to be constructed per event, per advertised tool, or per tool outcome rather than mutated and reused.
- **Error states**: Not applicable to the three files themselves — none depends on a network, database, or file-system call of its own. A dependency's failure (a tool call that errors, a stream that fails) surfaces as `ToolResult.isError == true` / the `isError` element of `ChatToolSource.callTool`'s tuple, or as a thrown `Error` on the enclosing `AsyncThrowingStream<ChatStreamEvent, Error>` from `ChatBackend.sendMessages(_:tools:)` — never as a case or error type these three files declare themselves.
- **Offline / disconnected state**: Not applicable — none of the three types performs network access. Connectivity loss is a concern of the transport that produces the bytes a decoder turns into an `AIStreamEvent`, which `AIPluginChatBackend.chatEvent(for:)` then maps onto a `ChatStreamEvent`; these value types themselves have no notion of being online or offline.
- **Cancellation**: Not applicable in isolation — `ChatStreamEvent`, `ToolDefinition`, and `ToolResult` carry no cancellation token of their own, and Swift value construction is atomic, so no partially-constructed instance of any of the three can exist. A cancelled `Task` simply stops producing or consuming further instances upstream or downstream of these types.
- **Malformed `argumentsJSON` / `parametersJSONSchema`**: MUST NOT be rejected by `ChatStreamEvent` or `ToolDefinition` themselves — neither field is validated as well-formed JSON at construction (per `tool-use-arguments-raw` and `definition-schema-opaque` above); parsing is deferred entirely to whichever consumer reads it, e.g. `MCPChatToolSource.callTool`'s `try? JSONDecoder().decode([String: Value].self, from: argumentsJSON)`, which tolerates a decode failure by passing `nil` arguments onward rather than any of these three types rejecting construction.

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

## Deep Linking

Not applicable: none of `ChatStreamEvent.swift`, `ToolDefinition.swift`, or `ToolResult.swift` defines a URL scheme, route, or navigation destination — they carry chat and tool-calling data, not app navigation.

## Localization

Not applicable: none of the three files contains a user-facing string literal of its own — `textDelta`'s text, `toolUse`'s `name`, `ToolDefinition`'s `name`/`description`, and `ToolResult`'s `content` are all caller- or model-supplied data, not strings these files author, format, or display.

## Accessibility Options

Not applicable: none of the three files presents UI, so none responds to Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three files contains a feature-flag or settings-key reference of its own.

## Analytics

Not applicable: none of the three files contains an analytics or event-tracking call.

## Privacy

- **Data handled**: A `.textDelta` or `.toolUse` `ChatStreamEvent` MAY carry assistant-generated conversational content or the model's raw tool-call arguments; `ToolDefinition.description`/`parametersJSONSchema` carry host-declared tool metadata rather than end-user data; `ToolResult.content` MAY carry whatever a tool execution returns, which — per `MCPChatToolSource.callTool` — can include arbitrary MCP server output such as file contents or search results. None of the three types defines a credential or token field of its own.
- **Storage**: None of the three files persists anything — each is an in-memory value type with no file, database, `UserDefaults`, or Keychain access of its own.
- **Transmission**: None of the three files transmits data itself; a value is only carried in-memory between the model-facing backend that produces it and the chat UI or tool source that consumes it.
- **Retention**: None — an instance of any of the three types lives only as long as the caller holds it (one stream element, one advertised tool, one tool outcome); no cache in these files extends its lifetime.

## Logging

Not applicable: none of the three files contains an `os_log`, `Logger`, `print`, or other logging call; each is a pure data declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/AIPlugins/ChatStreamEvent.swift`, `ToolDefinition.swift`, and `ToolResult.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). Nothing in the three files is SwiftUI-specific — each imports only `Foundation` — so a SwiftUI or AppKit host consumes them identically.
- **Compose**: Model `ChatStreamEvent` as a Kotlin `sealed interface` with data classes `TextDelta(val text: String)`, `ToolUse(val id: String, val name: String, val argumentsJson: ByteArray)`, and `End(val stopReason: String?)`, matched with an exhaustive `when` expression. Model `ToolDefinition` and `ToolResult` as immutable `data class`es (`ToolDefinition(val name: String, val description: String, val parametersJsonSchema: ByteArray)`, `ToolResult(val toolUseId: String, val content: String, val isError: Boolean)`); `Hashable` conformance is free on a Kotlin `data class` (structural `equals`/`hashCode`).
- **React/Web**: Represent `ChatStreamEvent` as a discriminated union — `{ kind: 'textDelta', text: string } | { kind: 'toolUse', id: string, name: string, argumentsJSON: Uint8Array } | { kind: 'end', stopReason?: string }` — and `ToolDefinition`/`ToolResult` as `readonly`-field interfaces (`{ readonly name: string; readonly description: string; readonly parametersJSONSchema: Uint8Array }`, `{ readonly toolUseId: string; readonly content: string; readonly isError: boolean }`). There is no built-in structural-equality operator, so porting `definition-equality`/`result-equality` requires a manual deep-equality helper (or a library) rather than a free `==`.
- **AppKit / UIKit**: Identical to the SwiftUI note — these three files are UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract.
- **WinUI 3**: Model `ChatStreamEvent` as an abstract `record` with three sealed derived records — `TextDelta(string Text)`, `ToolUse(string Id, string Name, byte[] ArgumentsJson)`, `End(string? StopReason)` — enabling exhaustive `switch` pattern matching over `is` patterns, the closest .NET analogue to Swift's closed enum. Model `ToolDefinition` and `ToolResult` as `record`s so equality is free, mirroring Swift's synthesized `Hashable` — e.g. `public sealed record ToolDefinition(string Name, string Description, byte[] ParametersJsonSchema);` and `public sealed record ToolResult(string ToolUseId, string Content, bool IsError);`. Use `System.Text.Json`'s `JsonDocument`/`Utf8JsonReader` only where a consumer needs to inspect `ParametersJsonSchema`/`ArgumentsJson` — never inside these three ports themselves, matching `definition-schema-opaque` and `tool-use-arguments-raw` above, which require the bytes to pass through unparsed. A WinUI 3 chat surface would carry these records across `Task`-based async calls the same way the Swift source crosses `Task` boundaries — no `ObservableCollection`/`INotifyPropertyChanged` is needed for the records themselves, since, like their Swift counterparts, they are immutable value snapshots rather than observable view-model state.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/AIPlugins/` |

## Design Decisions

**Decision**: `ChatStreamEvent` duplicates the sibling `AIStreamEvent` (same three cases, same associated-value shapes) instead of the `Core` chat layer reusing `AIStreamEvent` directly.
**Rationale**: `ChatStreamEvent` belongs to the `ChatBackend` protocol (`ChatBackend.swift`), which its own doc comment marks "Deprecated. New code conforms to `ChatSession`" — it predates the newer `ChatSession`/`AIPluginKit` split. `AIPluginChatBackend.chatEvent(for:)` is a pure field-for-field mapping between the two types, and the current, non-deprecated tool loop (`LocalChatSession`) consumes `AIStreamEvent` directly from its `EventStreamFactory` and never touches `ChatStreamEvent` at all. The duplication is a migration artifact tracked by the deprecation notice on `ChatBackend`, not an independent design need.
**Approved**: pending

**Decision**: `ToolResult` is fully declared (three required fields, an explicit initializer, `Sendable`/`Hashable` conformance) but no call site in this codebase currently constructs one.
**Rationale**: The type's own doc comment describes it as what "the chat dispatch loop builds... from MCP responses," but the one dispatch loop present, `LocalChatSession.runTurn`, instead builds an `AIChatMessage(role: .toolResult, ...)` directly from the `(content, isError)` tuple `ChatToolSource.callTool(name:argumentsJSON:)` returns. This mirrors the sibling `AIStreamEvent` recipe's observation about its own `.toolUse` case: a fully and correctly specified part of a contract that no current implementation happens to exercise is a source-fidelity note about integration status, not a gap in the type's own definition.
**Approved**: pending

**Decision**: None of `ChatStreamEvent`, `ToolDefinition`, or `ToolResult` validates the well-formedness of any `String` or `Data` field it carries (a tool description MAY be empty, `argumentsJSON`/`parametersJSONSchema` MAY be non-JSON bytes).
**Rationale**: All three are pure carriers between a model-facing backend and a chat UI or tool source; validation is deferred entirely to whichever consumer reads the field — e.g. `MCPChatToolSource.callTool` decodes `argumentsJSON` with `try? JSONDecoder()`, tolerating a decode failure by passing `nil` arguments onward rather than the value type rejecting construction. This matches the same no-validation convention the sibling `AIChatContext` recipe documents for `AIToolSpec.parametersJSONSchema`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`separation-of-concerns` passes because all three files perform no I/O, storage, or transport of their own — per `no-persistence-no-side-effects` above, they are only the data shapes shared between a chat backend, a tool source, and the chat UI, each of which owns its own logic elsewhere. `explicit-error-handling` passes because `ToolResult` represents a failed tool call as an explicit `isError: Bool` field on returned data rather than throwing, swallowing, or logging the failure silently — the same explicit-outcome shape `ChatToolSource.callTool`'s return tuple already uses.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
