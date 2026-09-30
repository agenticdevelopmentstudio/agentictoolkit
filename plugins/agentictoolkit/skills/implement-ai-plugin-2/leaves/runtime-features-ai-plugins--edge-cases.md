<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--edge-cases · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins)

**Rules** (cite as `implement-ai-plugin-2/runtime-features-ai-plugins--edge-cases#<slug>`):

- `null-empty-input` MUST — An empty selectedPluginIdentifier MUST make AIPluginChatBackend.isReady false and MUST make loadPlugin("") throw, which …
- `null-empty-input-2` MUST — MCPChatToolSource.callTool decoding an empty or malformed argumentsJSON MUST NOT throw — try? JSONDecoder().decode(...) …
- `boundary-values` MUST — LocalChatSession.maxToolIterations == 8 is a hard cap. On the 8th iteration, if the model still returns .toolUse …
- `concurrent-access` MUST — LocalChatSession.send(_:) calls made while a turn is active MUST be dropped, not queued …
- `concurrent-access-2` SHOULD — A new isReadyChanges() subscriber's "seed" value (computed asynchronously right after registration) and a concurrent …
- `error-states` MUST — A throw from pluginManager.loadPlugin(identifier:) (any of AIPluginManager.AIPluginError's cases) MUST surface …
- `error-states-2` MUST — MCPChatToolSource.callTool MUST convert any thrown MCP error into ("Tool error: <localizedDescription>", true), never …
- `offline-disconnected-state` MUST — None of the given sources perform network I/O directly — that is PluginTransport's responsibility. From this …
- `offline-disconnected-state-2` MUST — MCPChatToolSource.callTool re-fetches registry.tools(forIds:) on every call; if the MCP server for a previously-listed …

## Edge Cases

- **Null/empty input**: An empty `selectedPluginIdentifier` MUST make
  `AIPluginChatBackend.isReady` `false` and MUST make `loadPlugin("")` throw,
  which `AIPluginChatBackend` maps to `pluginNotAvailable` (see
  chat-backend-no-plugin). An empty `legacySelected` MUST leave
  `plan.selectedId == ""` (see migration-selected-id). Empty
  `pluginConfigValues` MUST still build a valid `AIPluginConfig([:])` — an
  empty config bag is passed to the plugin unmodified; validating it is the
  plugin's concern, not this component's.
- **Null/empty input**: `MCPChatToolSource.callTool` decoding an empty or
  malformed `argumentsJSON` MUST NOT throw — `try? JSONDecoder().decode(...)`
  swallows the failure and passes `nil` arguments to the underlying MCP call
  (the open question on mcp-tool-source-argument-validation).
- **Boundary values**: `LocalChatSession.maxToolIterations == 8` is a hard
  cap. On the 8th iteration, if the model still returns `.toolUse` events,
  the outer loop MUST still end after that iteration completes — there is no
  9th plugin call, and no explicit signal to the UI that the cap was hit
  (see local-session-tool-loop-bound).
- **Concurrent access**: `LocalChatSession.send(_:)` calls made while a turn
  is active MUST be dropped, not queued (local-session-send-busy-guard).
  `AIPluginChatBackend.subscribers` MUST only ever be mutated under `lock`,
  so concurrent `isReadyChanges()`/`notifyReadyChanged()` calls from
  different threads MUST NOT corrupt the registry (chat-backend-conformance).
  `AIProviderConfigStore`, `AIProviderMigration`, `AIProviderDefaults`,
  `AIProviderResolver`, and `PluginConfigStore` are all `@MainActor`-isolated,
  so the compiler MUST reject a concurrent call from a non-main-actor
  context outright — no runtime race is possible for those types.
- **Concurrent access**: A new `isReadyChanges()` subscriber's "seed" value
  (computed asynchronously right after registration) and a concurrent
  `notifyReadyChanged()` call MAY race; the subscriber is guaranteed at
  least one yield of a readiness value, but the relative order between the
  seed and a concurrent notify SHOULD NOT be relied upon.
- **Error states**: A throw from `pluginManager.loadPlugin(identifier:)` (any
  of `AIPluginManager.AIPluginError`'s cases) MUST surface identically as
  `AIPluginChatBackend.AIPluginChatError.pluginNotAvailable` — the specific
  failure reason is not preserved (chat-backend-no-plugin). A throw from
  `plugin.buildRequest` or from `PluginTransport.run` MUST surface as
  `.turnFailed(ChatError(from: error, isRetryable: true))` in
  `LocalChatSession`, or as the stream's thrown error unchanged in
  `AIPluginChatBackend` — in both cases `isRetryable` is always reported
  `true` for `LocalChatSession`, regardless of whether the underlying cause
  is transient (a timeout) or permanent (a misconfigured plugin).
  `ChatBackendSession`'s analogous catch block does the same.
- **Error states**: `MCPChatToolSource.callTool` MUST convert any thrown MCP
  error into `("Tool error: <localizedDescription>", true)`, never
  propagating the original error type to the model (mcp-tool-source-error-mapping).
- **Offline/disconnected state**: None of the given sources perform network
  I/O directly — that is `PluginTransport`'s responsibility. From this
  component's perspective, a network failure (unreachable host, timeout, a
  non-2xx response) MUST surface through the same generic error path as any
  other thrown error: `LocalChatSession.runTurn`'s catch block and
  `AIPluginChatBackend.drive`'s `onFinish(error)` — neither distinguishes an
  offline/unreachable failure from any other kind of error.
- **Offline/disconnected state**: `MCPChatToolSource.callTool` re-fetches
  `registry.tools(forIds:)` on every call; if the MCP server for a
  previously-listed tool has disconnected between `toolDefinitions()` and
  `callTool`, the tool is simply absent from the re-fetched pairs and the
  call MUST return `("Unknown tool: <name>", true)` — identical to a tool
  that never existed.
