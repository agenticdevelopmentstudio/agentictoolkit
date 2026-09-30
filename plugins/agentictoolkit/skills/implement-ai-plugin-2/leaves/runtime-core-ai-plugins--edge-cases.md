<!-- leaf: implement-ai-plugin-2/runtime-core-ai-plugins--edge-cases · source: ai-plugin-runtime-core-ai-plugins.md -->

# Chat Stream Event & Tool Types

**Rules** (cite as `implement-ai-plugin-2/runtime-core-ai-plugins--edge-cases#<slug>`):

- `null-empty-input` MUST — ChatStreamEvent.textDelta(""), ToolDefinition(name: "", description: "", parametersJSONSchema: Data()), and …
- `concurrent-access` MAY — Because all three types are Sendable and every field or associated value is immutable, the same instance MAY be read …
- `malformed-argumentsjson-parametersjsonschema` MUST — MUST NOT be rejected by ChatStreamEvent or ToolDefinition themselves — neither field is validated as well-formed JSON …

## Edge Cases

- **Null / empty input**: `ChatStreamEvent.textDelta("")`, `ToolDefinition(name: "", description: "", parametersJSONSchema: Data())`, and `ToolResult(toolUseId: "", content: "", isError: false)` MUST all be constructible — none of the three files performs a non-empty check on any `String` or `Data` field.
- **Boundary values**: Not applicable in the numeric sense — none of the three types declares a size-limited field of its own (no maximum length on `content`, `description`, `argumentsJSON`, or `parametersJSONSchema`). Any upper bound on how large a tool's arguments or schema may grow is enforced by the transport or provider that eventually sends the bytes, not by these files.
- **Concurrent access**: Because all three types are `Sendable` and every field or associated value is immutable, the same instance MAY be read from multiple tasks concurrently with no synchronization; there is no shared mutable state in any of the three files to race on. A new instance is expected to be constructed per event, per advertised tool, or per tool outcome rather than mutated and reused.
- **Error states**: Not applicable to the three files themselves — none depends on a network, database, or file-system call of its own. A dependency's failure (a tool call that errors, a stream that fails) surfaces as `ToolResult.isError == true` / the `isError` element of `ChatToolSource.callTool`'s tuple, or as a thrown `Error` on the enclosing `AsyncThrowingStream<ChatStreamEvent, Error>` from `ChatBackend.sendMessages(_:tools:)` — never as a case or error type these three files declare themselves.
- **Offline / disconnected state**: Not applicable — none of the three types performs network access. Connectivity loss is a concern of the transport that produces the bytes a decoder turns into an `AIStreamEvent`, which `AIPluginChatBackend.chatEvent(for:)` then maps onto a `ChatStreamEvent`; these value types themselves have no notion of being online or offline.
- **Cancellation**: Not applicable in isolation — `ChatStreamEvent`, `ToolDefinition`, and `ToolResult` carry no cancellation token of their own, and Swift value construction is atomic, so no partially-constructed instance of any of the three can exist. A cancelled `Task` simply stops producing or consuming further instances upstream or downstream of these types.
- **Malformed `argumentsJSON` / `parametersJSONSchema`**: MUST NOT be rejected by `ChatStreamEvent` or `ToolDefinition` themselves — neither field is validated as well-formed JSON at construction (per `tool-use-arguments-raw` and `definition-schema-opaque` above); parsing is deferred entirely to whichever consumer reads it, e.g. `MCPChatToolSource.callTool`'s `try? JSONDecoder().decode([String: Value].self, from: argumentsJSON)`, which tolerates a decode failure by passing `nil` arguments onward rather than any of these three types rejecting construction.
