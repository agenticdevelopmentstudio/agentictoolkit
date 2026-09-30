<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-ai-chat-context.md -->

# AI Chat Context

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
