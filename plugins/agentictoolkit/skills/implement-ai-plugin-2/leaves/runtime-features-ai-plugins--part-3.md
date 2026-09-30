<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--part-3 · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins) — continued (part 3)

**Rules** (cite as `implement-ai-plugin-2/runtime-features-ai-plugins--part-3#<slug>`):

- `local-session-conformance` MUST
- `local-session-events-initial` MUST
- `local-session-single-subscriber` MUST
- `local-session-send-busy-guard` MUST
- `local-session-interrupt` MUST
- `local-session-clear` MUST
- `local-session-close` MUST
- `local-session-turn-start` MUST
- `local-session-no-plugin` MUST
- `local-session-tool-loop-bound` MUST
- `local-session-stream-mapping` MUST
- `local-session-cooperative-cancellation` MUST
- `local-session-partial-text-kept` MUST
- `local-session-tool-turn-end` MUST
- `local-session-tool-execution` MUST
- `local-session-turn-finish` MUST
- `local-session-error-path` MUST
- `local-session-with-tools` MUST
- `mcp-tool-source-conformance` MUST
- `mcp-tool-source-namespacing` MUST
- `mcp-tool-source-schema-encoding` MUST
- `mcp-tool-source-unknown-tool` MUST
- `mcp-tool-source-dispatch` MUST
- `mcp-tool-source-error-mapping` MUST
- `mcp-tool-source-content-flatten` MUST
- `provider-defaults-on-unresolved` MUST
- `plugin-chat-config-provider-selection` MUST
- `single-configuration-provider-pinning` MUST

### LocalChatSession

- **local-session-conformance**: `LocalChatSession` MUST conform to
  `ChatSession` and MUST be declared `@unchecked Sendable`; `history` and
  `continuation` MUST be accessed only while holding `lock` (`NSLock`), and
  the busy flag MUST be accessed only through `turnActiveMutex`
  (`Synchronization.Mutex<Bool>`).
- **local-session-events-initial**: `events()` MUST return an `AsyncStream`
  that immediately yields `.stateChanged(.ready)` to its subscriber before
  any turn runs.
- **local-session-single-subscriber**: `events()` MUST replace any
  previously stored continuation with the new one on each call — this
  component supports at most one live subscriber's continuation at a time.
- **local-session-send-busy-guard**: `send(_:)` MUST be a silent no-op —
  emitting no event and starting no turn — when a turn is already active
  (`turnActiveMutex` holds `true`); otherwise it MUST set the busy flag and
  start `runTurn` as a new tracked `Task`.
- **local-session-interrupt**: `interrupt()` MUST cancel the live turn's
  `Task` and MUST reset the busy flag to `false`, allowing an immediate
  subsequent `send(_:)` even if the cancelled turn's own cleanup has not yet
  run.
- **local-session-clear**: `clear()` MUST remove all entries from `history`
  and MUST NOT affect an in-flight turn.
- **local-session-close**: `close()` MUST cancel the live turn, reset the
  busy flag, emit `.stateChanged(.closed)`, and finish the stored
  continuation, ending `events()`.
- **local-session-turn-start**: `runTurn(userText:)` MUST emit
  `.userMessage` for the user's text, append it to `history` as an
  `AIChatMessage(role: .user, ...)`, and emit `.stateChanged(.responding)`
  before doing anything else.
- **local-session-no-plugin**: When `resolvePlugin()` returns `nil`,
  `runTurn` MUST emit `.turnFailed(ChatError(message: "No AI provider is
  configured.", isRetryable: false))` followed by `.stateChanged(.ready)`,
  and MUST NOT emit `.responseStarted` or attempt any request. The user's
  already-appended history entry MUST remain in `history`.
- **local-session-tool-loop-bound**: `runTurn` MUST iterate the
  build-request/stream/tool-execute cycle at most `maxToolIterations` (`8`)
  times per turn; when the model still requests tools on the final
  permitted iteration, the loop MUST end after that iteration without
  starting a ninth, and without emitting any distinct "budget exceeded"
  signal.
- **local-session-stream-mapping**: Within one iteration, `runTurn` MUST
  emit `.responseStarted` the first time a `.textDelta` arrives (once per
  turn) and MUST emit `.responseDelta` for every `.textDelta` chunk; it MUST
  collect every `.toolUse` event into `pendingTools` and emit
  `.toolCall(phase: .started)` for it; it MUST ignore `.end` events from the
  stream (never surfacing the provider's `stopReason` for that event).
- **local-session-cooperative-cancellation**: `runTurn` MUST check
  `Task.isCancelled` between stream events and `break` out of the inner
  event loop when cancelled, without cancelling mid-event.
- **local-session-partial-text-kept**: After an iteration's stream ends
  (normally or via the cancellation break), if the accumulated `turnText` is
  non-empty, `runTurn` MUST append it to `history` as an assistant message
  even when the iteration was cut short.
- **local-session-tool-turn-end**: `runTurn` MUST end the iteration loop
  (without a further plugin call) once `pendingTools.isEmpty` is true, or
  once `toolSource` is `nil` even if `pendingTools` is non-empty.
- **local-session-tool-execution**: When continuing the loop,
  `runTurn` MUST execute every pending tool call sequentially, in the order
  received: append a `.toolUse` history entry, `await`
  `toolSource!.callTool(name:argumentsJSON:)`, append a `.toolResult` history
  entry carrying the result's `isError`, and emit
  `.toolCall(phase: .completed)` — before moving to the next pending tool.
- **local-session-turn-finish**: When the iteration loop ends, `runTurn`
  MUST emit `.responseFinished(stopReason: nil)` if and only if
  `.responseStarted` was emitted at least once during the turn, always
  passing `stopReason: nil` (the provider's own stop reason is never
  surfaced), then MUST emit `.stateChanged(.ready)`.
- **local-session-error-path**: Any error thrown by `plugin.buildRequest`,
  by the event-stream factory, or propagated from `PluginTransport.run`
  MUST end the turn by emitting `.turnFailed(ChatError(from: error,
  isRetryable: true))` — always `isRetryable: true` regardless of the
  error's underlying cause — followed by `.stateChanged(.ready)`.
- **local-session-with-tools**: The private `AIChatContext.withTools(_:)`
  helper MUST return a copy of the context with `tools` replaced by the
  mapped `AIToolSpec`s and every other field (`messages`, `model`,
  `systemPrompt`, `maxTokens`, `config`) unchanged.

### MCPChatToolSource

- **mcp-tool-source-conformance**: `MCPChatToolSource` MUST conform to
  `ChatToolSource` and MUST be declared `@unchecked Sendable`; its
  `registry` and `activeServerIds` MUST be fixed at initialization time (a
  snapshot, not a live-observed set).
- **mcp-tool-source-namespacing**: `toolDefinitions()` and `callTool` MUST
  identify a tool by `"<server-name>__<tool-name>"` (`namespaced`, separator
  `"__"`), built from `registry.tools(forIds: activeServerIds)`.
- **mcp-tool-source-schema-encoding**: `toolDefinitions()` MUST build one
  `ToolDefinition` per registry pair whose `inputSchema` JSON-encodes
  successfully, and MUST silently drop (via `compactMap`) any pair whose
  schema fails to encode — no error is surfaced for a dropped pair.
- **mcp-tool-source-unknown-tool**: `callTool(name:argumentsJSON:)` MUST
  return `("Unknown tool: <name>", true)` when no currently-registered pair's
  namespaced name matches `name`.
- **mcp-tool-source-dispatch**: `callTool` MUST re-fetch
  `registry.tools(forIds: activeServerIds)` on every call (not cached from
  `toolDefinitions()`), find the matching pair, and invoke
  `pair.client.callTool(name:arguments:)`.
- **mcp-tool-source-error-mapping**: `callTool` MUST convert any error thrown
  by the underlying MCP call into `("Tool error: <error.localizedDescription>",
  true)`.
- **mcp-tool-source-content-flatten**: `callTool` MUST join only the `.text`
  content items of a successful call's response with `"\n"`
  (`flatten`), and MUST silently drop any non-text content item.
- **mcp-tool-source-argument-validation**: NEEDS REVIEW: Not implemented in source. `callTool` decodes `argumentsJSON` with `try?` and, on a decode failure, silently substitutes `nil` arguments rather than surfacing a validation error — a malformed tool-call payload from the model is forwarded to `pair.client.callTool` as though no arguments were supplied, instead of being reported back as a tool error the model or user could act on.

### PluginChatConfigProvider / SingleConfigurationChatConfigProvider

- **provider-defaults-on-unresolved**: Both `PluginChatConfigProvider` and
  `SingleConfigurationChatConfigProvider` MUST return `""` for
  `selectedPluginIdentifier`, `""` for `selectedModel`, and `[:]` for
  `pluginConfigValues` whenever the underlying `AIProviderResolver.resolve`
  call returns `nil` — neither type MUST throw.
- **plugin-chat-config-provider-selection**: `PluginChatConfigProvider`'s
  `resolved` MUST derive its configuration from
  `UserSettings.selectedAIProviderConfigurationId`: an empty string, a string
  that does not parse as a `UUID`, or a `UUID` with no matching entry in
  `UserSettings.aiProviderConfigurations` MUST each result in `resolved ==
  nil`.
- **single-configuration-provider-pinning**: `SingleConfigurationChatConfigProvider`
  MUST resolve against the exact `AIProviderConfiguration` passed to its
  initializer, independent of `UserSettings.selectedAIProviderConfigurationId`,
  on every access — an edit made elsewhere to the same configuration's
  stored fields or model MUST be visible on the next access, since `resolved`
  is recomputed live rather than cached.

