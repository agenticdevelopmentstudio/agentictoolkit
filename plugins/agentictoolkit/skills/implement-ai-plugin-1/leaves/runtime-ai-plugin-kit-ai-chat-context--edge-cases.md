<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-chat-context.md -->

# AI Chat Context

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context--edge-cases#<slug>`):

- `empty-messages-array` MUST — AIChatContext.init MUST NOT reject messages: []; the source has no non-empty check. What a plugin's buildRequest(_:) …
- `empty-model-string` MUST — AIChatContext.init MUST NOT reject model: ""; the source performs no content validation on model.
- `aipluginconfig-with-an-empty-values-dictionary` MUST — apiKey, baseURL, model, and the keyed subscript MUST all return nil for any key, since an empty [String: String] …
- `aipluginconfig-subscript-with-an-unrecognized-key` MUST — MUST return nil; the subscript is a direct dictionary lookup with no fallback or default.
- `aitoolspec-parametersjsonschema-containing-non-json-or-malformed-bytes` MUST — AIToolSpec.init MUST NOT reject it; the type performs no validation that the Data it carries is well-formed JSON — …
- `aichatmessage-with-inconsistent-tool-fields` MUST (e.g., `toolArgumentsJSON` set but `toolName` and `toolUseId` both `nil`, or `role == .toolResult` with all four tool fields `nil`) — AIChatMessage.init MUST NOT reject any such combination; the source ties no field to any other, and to role, by …
- `concurrent-access` MAY — AIChatMessage, AIToolSpec, AIPluginConfig, and AIChatContext are immutable and Sendable; the same instance MAY be read …

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
