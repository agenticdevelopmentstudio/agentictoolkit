<!-- leaf: implement-ai-plugin-2/runtime-core-ai-plugins--test-vectors · source: ai-plugin-runtime-core-ai-plugins.md -->

# Chat Stream Event & Tool Types

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
