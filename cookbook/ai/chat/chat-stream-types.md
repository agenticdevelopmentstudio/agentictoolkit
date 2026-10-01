---
id: f305da79-fa03-493e-9c08-7186530943c6
title: Chat Stream Types
domain: agentictoolkit://cookbook/ai/chat/chat-stream-types
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The three immutable value shapes — a stream event, a tool definition,
  and a tool result — that carry chat tool-calling data across a chat backend
  and a tool source.
platforms:
- swift
- macos
tags:
- ai-plugin
- chat
- tool-calling
- streaming
- value-type
depends-on: []
related:
- agentictoolkit://cookbook/ai/plugins/stream-event
- agentictoolkit://cookbook/ai/chat/chat-context
references: []
approved-by: ''
approved-date: ''
---

# Chat Stream Types

## Overview

Three small, immutable value shapes carry tool-calling data across the chat
layer: the stream event (one event in the assistant response stream that a
tool-aware chat-backend sending method returns), the tool definition (one
tool advertised to the model, the element a tool source's tool-listing
method returns), and the tool result (the outcome of running one tool
call). None of the three performs I/O; each is a closed, immutable shape
with either a fixed set of cases or an explicit way to construct it from
its parts, and no other logic.

All three have counterparts elsewhere in this cookbook that this recipe
does not otherwise cover. The stream event mirrors — but is a distinct
shape from — the sibling stream-event contract described elsewhere; an
adapter maps one to the other case-for-case with no transformation. The
tool definition similarly mirrors the tool specification described in the
chat-context recipe; the local chat session and that same adapter each
copy a tool definition's three fields unchanged into a tool specification.
The tool result has no current call site in this codebase that constructs
it: the one tool-dispatch loop present builds a chat message with a
tool-result role directly from the content/is-error pair a tool source's
call-tool method returns, rather than a tool-result value — see Design
Decisions.

## Behavioral Requirements

- **stream-event-case-set**: the stream event MUST have exactly three
  cases — a text delta carrying a string chunk, a tool-use event carrying
  an identifier/name/raw JSON arguments, and an end event carrying an
  optional stop reason.
- **stream-event-sendable**: the stream event MUST be safe to pass across
  a concurrency-domain boundary.
- **text-delta-payload**: the text-delta case's payload MUST be exactly
  one string chunk of assistant text and carry no other data; this shape
  imposes no constraint on chunk size or where a chunk boundary falls.
- **tool-use-payload**: the tool-use case's payload MUST be an identifier,
  a tool name, and raw JSON arguments.
- **tool-use-arguments-raw**: the raw JSON arguments on a tool-use event
  MUST carry the model's tool-call arguments as raw, undecoded bytes,
  unchanged from the sibling stream-event contract's tool-use value it is
  mapped from — the mapping step passes the arguments straight through
  with no parsing, and this shape itself performs no JSON decoding of the
  field.
- **end-stop-reason-optional**: the end case's stop reason MUST be
  optional, so a producer MAY report nothing when no reason is available.
- **stream-emission-contract**: Per its own documentation, a text-only
  backend MUST emit only text-delta and end events on a stream it returns,
  and a tool-capable backend MUST additionally emit one tool-use event for
  each call the model requests ("Text-only backends only emit
  text-delta and end; tool-capable backends additionally emit tool-use for
  each call the model wants to make").
- **tool-call-result-correlation**: The identifier carried by a tool-use
  event MUST be the same identifier a caller later supplies when reporting
  that call's outcome, whether as the tool result's correlating identifier
  or as a chat message's matching identifier on a tool-result-role
  message — the local chat session propagates the same identifier recorded
  from each pending tool call into the tool-result-role message it later
  appends.
- **definition-identity**: the tool definition MUST require a name, a
  description, and raw JSON Schema bytes for its parameters, none of
  which has a default value.
- **definition-equality**: the tool definition MUST support equality
  comparison; two instances MUST compare equal if and only if their name,
  description, and parameter-schema bytes are each equal.
- **definition-sendable**: the tool definition MUST be safe to pass across
  a concurrency-domain boundary.
- **definition-immutability**: the tool definition MUST declare its name,
  description, and parameter-schema bytes as unchangeable once constructed
  and MUST provide no way to mutate an existing instance.
- **definition-schema-opaque**: the parameter-schema bytes MUST be treated
  as an opaque, pre-serialized JSON Schema byte buffer — the tool
  definition MUST NOT parse, decode, or validate it; nothing in this shape
  reads or transforms the field beyond storing and returning it.
- **definition-provider-translation-elsewhere**: Translating a tool
  definition into a specific backend's provider tool schema (e.g. one
  provider's `tools`, another's `functions`) MUST happen in the consuming
  backend, not in the tool definition itself, per its own documentation
  ("Backends translate this into the provider-specific shape... before
  sending the request") — the local chat session and the plugin-backed
  adapter each perform exactly this translation, copying the three fields
  unchanged into a tool specification.
- **result-identity**: the tool result MUST require a correlating
  identifier, content text, and an error flag, none of which has a
  default value.
- **result-equality**: the tool result MUST support equality comparison;
  two instances MUST compare equal if and only if their correlating
  identifier, content, and error flag are each equal.
- **result-sendable**: the tool result MUST be safe to pass across a
  concurrency-domain boundary.
- **result-immutability**: the tool result MUST declare its correlating
  identifier, content, and error flag as unchangeable once constructed and
  MUST provide no way to mutate an existing instance.
- **result-error-flag-independence**: the tool result MUST NOT enforce any
  relationship between its error flag and its content — constructing one
  stores both fields exactly as given, with no validation tying them
  together; a caller MAY construct an error result with non-empty content
  (an error message) or a non-error result with empty content.
- **cross-domain-safety**: Because the stream event, the tool definition,
  and the tool result are all safe to pass across concurrency boundaries
  and every value they carry is itself safe to share this way (strings,
  raw bytes, booleans, optional strings), an instance of any of the three
  MAY cross a concurrency-domain boundary — e.g. from a background task
  into a UI thread's chat surface, or from a tool-dispatch loop into a
  tool source running on its own execution context — with no additional
  synchronization.
- **no-persistence-no-side-effects**: Constructing or reading any case or
  field of the stream event, the tool definition, or the tool result MUST
  NOT perform file, database, secure-storage, or network access, and none
  of the three persists or caches a value beyond the caller's own variable
  lifetime — each is limited to a case list or stored values plus a way to
  construct one, with no I/O of any kind.

## Appearance

Not applicable — this is a set of chat tool-calling value shapes, not a
visual component.

## States

Not applicable — this is a set of chat tool-calling value shapes, not a
visual component.

## Accessibility

Not applicable — this is a set of chat tool-calling value shapes, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-tool-types-001 | stream-event-case-set, stream-event-sendable | Inspect the stream-event shape. | Exactly three cases — text delta, tool use, end — and the shape is declared safe to pass across concurrency boundaries. |
| chat-tool-types-002 | text-delta-payload | A text-delta event carrying the chunk `"Hello"`, read via its case-matching accessor. | The chunk reads `"Hello"`, with no other payload carried. |
| chat-tool-types-003 | tool-use-payload, tool-use-arguments-raw | A tool-use event with identifier `"call_1"`, name `"search"`, and raw JSON arguments `{"q":"cats"}`, read the same way the local chat session's dispatch loop pattern-matches it. | The identifier reads `"call_1"`, the name reads `"search"`, and the arguments equal the exact bytes given, byte for byte, unparsed. |
| chat-tool-types-004 | end-stop-reason-optional | Construct an end event with no stop reason given. | Constructs without error; the stop reason reads absent. |
| chat-tool-types-005 | stream-emission-contract | Drive a chat backend's default tool-aware sending method with a text-only stream of two chunks. | The returned stream yields two text-delta events, then exactly one end event with no stop reason — no tool-use event. |
| chat-tool-types-006 | tool-call-result-correlation | Run the local chat session's turn-processing step for a turn with one pending tool call whose identifier is `"call_1"`; inspect the tool-result-role chat message it appends. | The appended message's correlating identifier reads `"call_1"`, matching the identifier the session recorded from the tool-use event. |
| chat-tool-types-007 | definition-identity, definition-sendable | A tool definition constructed with name `"search"`, description `"Search the web"`, and empty-object parameter-schema bytes. | Constructs without error; all three fields hold the given values unchanged. |
| chat-tool-types-008 | definition-equality | Two tool definitions with identical name/description/parameter-schema bytes, versus a third with the same name/description but different parameter-schema bytes. | The first two compare equal; the third compares unequal to either. |
| chat-tool-types-009 | definition-immutability | Attempt to reassign a tool definition's name field after construction. | Rejected — the field is unchangeable once constructed. |
| chat-tool-types-010 | definition-provider-translation-elsewhere | The local chat session's tool-attaching operation, given one tool definition with name `"n"`, description `"d"`, and a given set of parameter-schema bytes. | Returns a chat context whose tools list contains one tool specification with the same name, description, and parameter-schema bytes — the three fields copied unchanged. |
| chat-tool-types-011 | result-identity, result-sendable | A tool result constructed with correlating identifier `"call_1"`, content `"42"`, and error flag `false`. | Constructs without error; all three fields hold the given values unchanged. |
| chat-tool-types-012 | result-equality | Two tool results with identical correlating identifier/content/error flag, versus a third with the error flag flipped. | The first two compare equal; the third compares unequal to either. |
| chat-tool-types-013 | result-error-flag-independence | A tool result with empty content and error flag `true`, and a second with content `"ok"` and error flag `false`. | Both construct without error — empty content with the error flag set, and non-empty content with the error flag clear, are both accepted. |
| chat-tool-types-014 | result-immutability | Attempt to reassign a tool result's content field after construction. | Rejected — the field is unchangeable once constructed. |
| chat-tool-types-015 | cross-domain-safety | Capture a list of tool definitions in a background task's closure, built on one thread of execution, then read it from a separate concurrent context. | Compiles/runs under strict concurrency checking with no safety violation. |
| chat-tool-types-016 | no-persistence-no-side-effects | Inspect the stream event, tool definition, and tool result shapes in full. | No file, database, secure-storage, or network access is referenced in any of the three. |
| chat-tool-types-017 | tool-use-payload, definition-schema-opaque | A tool definition constructed with name `"n"`, description `"d"`, and parameter-schema bytes containing the literal text `"not valid json"`. | Constructs without error — no JSON validation is performed on the parameter-schema bytes. |

## Edge Cases

- **Null / empty input**: constructing a text-delta event with an empty
  chunk, a tool definition with empty name/description/schema bytes, and a
  tool result with an empty identifier/empty content/error flag `false`
  MUST all succeed; none of the three performs a non-empty check on any
  string or byte field.
- **Boundary values**: Not applicable in the numeric sense — none of the
  three shapes declares a size-limited field of its own (no maximum length
  on content, description, arguments, or parameter-schema bytes). Any
  upper bound on how large a tool's arguments or schema may grow is
  enforced by the transport or provider that eventually sends the bytes,
  not by these shapes.
- **Concurrent access**: Because all three shapes are safe to pass across
  concurrency boundaries and every field or payload value is unchangeable,
  the same instance MAY be read from multiple points of execution
  concurrently with no synchronization; there is no shared mutable state
  in any of the three to race on. A new instance is expected to be
  constructed per event, per advertised tool, or per tool outcome rather
  than mutated and reused.
- **Error states**: Not applicable to the three shapes themselves — none
  depends on a network, database, or file-system call of its own. A
  dependency's failure (a tool call that errors, a stream that fails)
  surfaces as the tool result's error flag being set, or as the
  corresponding element of a tool source's call-tool outcome, or as a
  failure on the enclosing response stream from the chat backend's
  tool-aware sending method — never as a case or error type these three
  shapes declare themselves.
- **Offline / disconnected state**: Not applicable — none of the three
  shapes performs network access. Connectivity loss is a concern of the
  transport that produces the bytes a decoder turns into the sibling
  stream-event contract's value, which an adapter then maps onto this
  stream event; these value shapes themselves have no notion of being
  online or offline.
- **Cancellation**: Not applicable in isolation — the stream event, tool
  definition, and tool result carry no cancellation token of their own,
  and construction of any of the three is atomic, so no partially
  constructed instance of any can exist. Cancelling the surrounding
  operation simply stops producing or consuming further instances
  upstream or downstream of these shapes.
- **Malformed raw JSON arguments / parameter-schema bytes**: MUST NOT be
  rejected by the stream event or the tool definition themselves — neither
  field is validated as well-formed JSON at construction (per
  `tool-use-arguments-raw` and `definition-schema-opaque` above); parsing
  is deferred entirely to whichever consumer reads it, e.g. an MCP-backed
  tool source's argument-decoding step, which tolerates a decode failure
  by passing no arguments onward rather than any of these three shapes
  rejecting construction.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `textDelta` payload | string | none (required) | The stream event's chunk of assistant text for this event. |
| `toolUse.id` | string | none (required) | The stream event's identifier for one model-requested tool call. |
| `toolUse.name` | string | none (required) | The stream event's name of the tool the model wants to call. |
| `toolUse.argumentsJSON` | raw bytes | none (required) | The stream event's raw, undecoded JSON arguments for the call. |
| `end.stopReason` | optional string | absent | The stream event's provider-supplied reason the stream ended, or absent. |
| `name` | string | none (required) | The tool definition's tool name advertised to the model. |
| `description` | string | none (required) | The tool definition's tool description advertised to the model. |
| `parametersJSONSchema` | raw bytes | none (required) | The tool definition's opaque JSON Schema bytes for the tool's parameters. |
| `toolUseId` | string | none (required) | The tool result's identifier correlating this outcome with its originating tool-use call. |
| `content` | string | none (required) | The tool result's result text, or error text, from running the tool. |
| `isError` | boolean | none (required) | The tool result's flag marking whether the tool call failed. |

These three shapes define no environment variable and no settings key of
their own — every value arrives as an associated value on a stream-event
case, or as a parameter given when constructing a tool definition or tool
result.

## Deep Linking

Not applicable: none of the stream event, the tool definition, or the tool
result defines a URL scheme, route, or navigation destination — they carry
chat and tool-calling data, not app navigation.

## Localization

Not applicable: none of the three shapes contains a user-facing string
literal of its own — the text delta's text, the tool-use event's name, the
tool definition's name/description, and the tool result's content are all
caller- or model-supplied data, not strings these shapes author, format, or
display.

## Accessibility Options

Not applicable: none of the three shapes presents UI, so none responds to
Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three shapes contains a feature-flag or
settings-key reference of its own.

## Analytics

Not applicable: none of the three shapes contains an analytics or
event-tracking call.

## Privacy

- **Data handled**: A text-delta or tool-use stream event MAY carry
  assistant-generated conversational content or the model's raw tool-call
  arguments; the tool definition's description/parameter-schema bytes
  carry host-declared tool metadata rather than end-user data; the tool
  result's content MAY carry whatever a tool execution returns, which, for
  an MCP-backed tool source, can include arbitrary MCP output such as file
  contents or search results. None of the three shapes defines a
  credential or token field of its own.
- **Storage**: None of the three shapes persists anything — each is an
  in-memory value with no file, database, or secure-storage access of its
  own.
- **Transmission**: None of the three shapes transmits data itself; a
  value is only carried in-memory between the model-facing backend that
  produces it and the chat UI or tool source that consumes it.
- **Retention**: None — an instance of any of the three shapes lives only
  as long as the caller holds it (one stream element, one advertised tool,
  one tool outcome); nothing in these shapes extends its lifetime.

## Logging

Not applicable: none of the three shapes contains a logging call of any
kind; each is a pure data declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The sources are
  `packages/apple/AgenticToolkit/Core/AIPlugins/ChatStreamEvent.swift`,
  `ToolDefinition.swift`, and `ToolResult.swift`, part of the
  `AgenticToolkitCore` framework target, which `project.yml` declares as
  `platform: macOS` only (no iOS target exists for it today). Nothing in
  the three files is SwiftUI-specific — each imports only `Foundation` —
  so a SwiftUI or AppKit host consumes them identically.
- **Compose**: Model `ChatStreamEvent` as a Kotlin `sealed interface` with
  data classes `TextDelta(val text: String)`, `ToolUse(val id: String, val
  name: String, val argumentsJson: ByteArray)`, and `End(val stopReason:
  String?)`, matched with an exhaustive `when` expression. Model
  `ToolDefinition` and `ToolResult` as immutable `data class`es
  (`ToolDefinition(val name: String, val description: String, val
  parametersJsonSchema: ByteArray)`, `ToolResult(val toolUseId: String, val
  content: String, val isError: Boolean)`); `Hashable` conformance is free
  on a Kotlin `data class` (structural `equals`/`hashCode`).
- **React/Web**: Represent `ChatStreamEvent` as a discriminated union —
  `{ kind: 'textDelta', text: string } | { kind: 'toolUse', id: string,
  name: string, argumentsJSON: Uint8Array } | { kind: 'end', stopReason?:
  string }` — and `ToolDefinition`/`ToolResult` as `readonly`-field
  interfaces (`{ readonly name: string; readonly description: string;
  readonly parametersJSONSchema: Uint8Array }`, `{ readonly toolUseId:
  string; readonly content: string; readonly isError: boolean }`). There
  is no built-in structural-equality operator, so porting
  `definition-equality`/`result-equality` requires a manual
  deep-equality helper (or a library) rather than a free `==`.
- **AppKit / UIKit**: this is the source. `ChatStreamEvent.swift`,
  `ToolDefinition.swift`, and `ToolResult.swift` live in
  `packages/apple/AgenticToolkit/Core/AIPlugins/`, part of the
  `AgenticToolkitCore` framework target, which `project.yml` declares as
  `platform: macOS` only (no iOS target exists for it today).
  `ChatStreamEvent` is a `Sendable` enum with cases `textDelta(String)`,
  `toolUse(id: String, name: String, argumentsJSON: Data)`, and
  `end(stopReason: String?)`; `ToolDefinition` and `ToolResult` are
  `Sendable`, `Hashable` structs (`ToolDefinition(name: String,
  description: String, parametersJSONSchema: Data)`,
  `ToolResult(toolUseId: String, content: String, isError: Bool)`) with
  every stored property declared `let`. `ChatStreamEvent` mirrors the
  sibling `AIStreamEvent` (in `AIPluginKit`) case-for-case;
  `AIPluginChatBackend.chatEvent(for:)` maps one to the other with no
  transformation. `ToolDefinition` mirrors `AIToolSpec`;
  `LocalChatSession.withTools(_:)` and `AIPluginChatBackend.aiToolSpec(for:)`
  each copy its three fields unchanged into an `AIToolSpec`.
  `ChatStreamEvent` belongs to the `ChatBackend` protocol
  (`ChatBackend.swift`), marked deprecated in favor of
  `ChatSession`/`AIPluginKit` — the current, non-deprecated tool loop
  (`LocalChatSession`) consumes `AIStreamEvent` directly from its
  `EventStreamFactory` and never touches `ChatStreamEvent`. No call site in
  this codebase constructs a `ToolResult`; `LocalChatSession.runTurn`
  instead builds an `AIChatMessage(role: .toolResult, ...)` directly from
  the `(content: String, isError: Bool)` tuple
  `ChatToolSource.callTool(name:argumentsJSON:)` returns.
  `MCPChatToolSource.callTool` decodes `argumentsJSON` with `try?
  JSONDecoder().decode([String: Value].self, from: argumentsJSON)`,
  tolerating a decode failure by passing `nil` arguments onward. The
  cross-domain-safety test vector exercises a `[ToolDefinition]` captured
  in the `@Sendable` closure `AIPluginChatBackend.makeInputs(messages:tools:)`
  builds inside a `MainActor.run` block, read inside `Self.drive`'s
  background `Task`, compiling under `SWIFT_STRICT_CONCURRENCY: complete`.
- **WinUI 3**: Model `ChatStreamEvent` as an abstract `record` with three
  sealed derived records — `TextDelta(string Text)`, `ToolUse(string Id,
  string Name, byte[] ArgumentsJson)`, `End(string? StopReason)` —
  enabling exhaustive `switch` pattern matching over `is` patterns, the
  closest .NET analogue to a closed Swift enum. Model `ToolDefinition` and
  `ToolResult` as `record`s so equality is free, mirroring the synthesized
  `Hashable` — e.g. `public sealed record ToolDefinition(string Name,
  string Description, byte[] ParametersJsonSchema);` and `public sealed
  record ToolResult(string ToolUseId, string Content, bool IsError);`. Use
  `System.Text.Json`'s `JsonDocument`/`Utf8JsonReader` only where a
  consumer needs to inspect `ParametersJsonSchema`/`ArgumentsJson` — never
  inside these three ports themselves, matching `definition-schema-opaque`
  and `tool-use-arguments-raw` above, which require the bytes to pass
  through unparsed. A WinUI 3 chat surface would carry these records
  across `Task`-based async calls the same way the source crosses `Task`
  boundaries — no `ObservableCollection`/`INotifyPropertyChanged` is
  needed for the records themselves, since, like their Swift counterparts,
  they are immutable value snapshots rather than observable view-model
  state.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/AIPlugins/` |

## Design Decisions

**Decision**: the stream event duplicates the sibling stream-event
contract (same three cases, same payload shapes) instead of the chat layer
reusing that contract directly.
**Rationale**: (Swift implementation) `ChatStreamEvent` belongs to the
`ChatBackend` protocol (`ChatBackend.swift`), whose own doc comment marks
it "Deprecated. New code conforms to `ChatSession`" — it predates the
newer `ChatSession`/`AIPluginKit` split. `AIPluginChatBackend.chatEvent(for:)`
is a pure field-for-field mapping between the two shapes, and the current,
non-deprecated tool loop (`LocalChatSession`) consumes `AIStreamEvent`
directly from its `EventStreamFactory` and never touches `ChatStreamEvent`
at all. The duplication is a migration artifact tracked by the deprecation
notice on `ChatBackend`, not an independent design need.
**Approved**: pending

**Decision**: the tool result is fully declared (three required fields, an
explicit way to construct it, equality and cross-domain-safety support)
but no call site in this codebase currently constructs one.
**Rationale**: (Swift implementation) its own doc comment describes it as
what "the chat dispatch loop builds... from MCP responses," but the one
dispatch loop present, `LocalChatSession.runTurn`, instead builds an
`AIChatMessage(role: .toolResult, ...)` directly from the `(content,
isError)` tuple `ChatToolSource.callTool(name:argumentsJSON:)` returns.
This mirrors the sibling stream-event recipe's observation about its own
tool-use case: a fully and correctly specified part of a contract that no
current implementation happens to exercise is a source-fidelity note about
integration status, not a gap in the shape's own definition.
**Approved**: pending

**Decision**: None of the stream event, the tool definition, or the tool
result validates the well-formedness of any string or byte field it
carries (a tool description MAY be empty, the raw JSON arguments/
parameter-schema bytes MAY be non-JSON bytes).
**Rationale**: All three are pure carriers between a model-facing backend
and a chat UI or tool source; validation is deferred entirely to whichever
consumer reads the field — e.g. an MCP-backed tool source decodes its raw
arguments with a tolerant decode, passing nothing onward rather than the
value rejecting construction. This matches the same no-validation
convention the chat-context recipe documents for the tool specification's
parameter-schema bytes.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`separation-of-concerns` passes because all three files perform no I/O,
storage, or transport of their own — per `no-persistence-no-side-effects`
above, they are only the data shapes shared between a chat backend, a tool
source, and the chat UI, each of which owns its own logic elsewhere.
`explicit-error-handling` passes because `ToolResult` represents a failed
tool call as an explicit `isError: Bool` field on returned data rather than
throwing, swallowing, or logging the failure silently — the same
explicit-outcome shape `ChatToolSource.callTool`'s return tuple already
uses.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/chat/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
