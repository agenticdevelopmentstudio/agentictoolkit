<!-- leaf: implement-general-2/mcp-plumbing--part-3 · source: mcp-plumbing.md -->

# MCP Plumbing — continued (part 3)

**Rules** (cite as `implement-general-2/mcp-plumbing--part-3#<slug>`):

- `registry-is-observable-on-main-actor` MUST
- `registry-clients-mirror-enabled-configurations-only` MUST
- `registry-subscribes-to-settings-changes` MUST
- `registry-reconcile-removes-first` MUST
- `registry-reconcile-adds-missing` MUST
- `registry-connect-failure-is-logged-not-thrown` MUST
- `registry-default-client-factory` MUST
- `registry-tools-for-ids` MUST
- `subprocess-transport-conforms-to-mcp-transport` MUST
- `subprocess-transport-default-logger-is-noop` MUST
- `subprocess-transport-three-state` MUST
- `subprocess-connect-is-idempotent` MUST
- `subprocess-connect-order` MUST
- `subprocess-blank-line-filtering` MUST
- `subprocess-disconnect-is-idempotent` MUST
- `subprocess-send-requires-connected-state` MUST
- `subprocess-receive-returns-stable-stream` MUST
- `host-server-is-main-actor` MUST
- `host-server-wires-in-memory-pair` MUST
- `host-server-declares-no-list-changed` MUST
- `host-server-start-and-stop` MUST
- `host-server-lists-two-tools` MUST
- `host-app-info-tool-body` MUST
- `host-open-chat-window-tool-effect` MUST
- `host-server-unknown-tool-is-not-an-error-throw` MUST
- `host-server-ignores-tool-arguments` MUST

- **registry-is-observable-on-main-actor**: `MCPServerRegistry` MUST be a `@MainActor` `final class` conforming to `ObservableObject`, and MUST publish `clients: [UUID: any MCPClientProtocol]` via `@Published`.
- **registry-clients-mirror-enabled-configurations-only**: `clients` MUST contain an entry only for a configuration whose `isEnabled` is `true`; a disabled or absent configuration's `id` MUST NOT appear as a key.
- **registry-subscribes-to-settings-changes**: `init` MUST combine `store.publisher(for: UserSettings.mcpServerConfigurations)` with `store.publisher(for: UserSettings.mcpServerSecrets)` via `combineLatest` and MUST call `reconcile(configurations:secrets:)` on every emission from either publisher.
- **registry-reconcile-removes-first**: `reconcile(configurations:secrets:)` MUST, for every `id` currently in `clients` that is not in the newly enabled set, remove that `id` from `clients` immediately and start that client's `disconnect()` in its own unstructured `Task` without awaiting it.
- **registry-reconcile-adds-missing**: For every enabled configuration whose `id` is not already in `clients`, `reconcile` MUST look up `secrets[configuration.id.uuidString] ?? [:]`, create a client via `clientFactory(configuration, serverSecrets)`, store it in `clients` under that `id`, and start `client.connect()` in its own unstructured `Task` without awaiting it.
- **registry-connect-failure-is-logged-not-thrown**: If the `Task` started in `registry-reconcile-adds-missing` throws from `connect()`, `reconcile` MUST catch the error and log it via `Self.logger.error(...)`, interpolating the configuration's `name` and the error's `localizedDescription` with `privacy: .public`, and MUST NOT remove the client from `clients` or rethrow.
- **registry-default-client-factory**: The `clientFactory` parameter MUST default to a closure that constructs a real `MCPClient(configuration:secrets:)`; a caller (test or otherwise) MAY substitute a different factory at `init`.
- **registry-tools-for-ids**: `tools(forIds:)` MUST, for each `id` in the given `Set<UUID>`, skip any `id` with no entry in `clients`, and otherwise await that client's `cachedTools` and append one `(client, tool)` pair per cached tool; the result MUST include every cached tool from every matching client and MUST NOT include tools from a client whose `id` is absent from `ids`.

`SubprocessTransport`

- **subprocess-transport-conforms-to-mcp-transport**: `SubprocessTransport` MUST be a public `actor` conforming to `MCP.Transport`, built over this codebase's `SubprocessChannel` rather than the MCP SDK's `StdioTransport`.
- **subprocess-transport-default-logger-is-noop**: `SubprocessTransport.init` MUST default `logger` to a `Logger` backed by `SwiftLogNoOpLogHandler` when the caller supplies none, matching `StdioTransport`'s own default, so every JSON-RPC frame of every MCP server is not logged by default.
- **subprocess-transport-three-state**: `SubprocessTransport` MUST track its lifecycle as one of exactly three states — `idle`, `connecting`, `connected` — rather than a `Bool`, because there is a window after `channel.launch()` returns and before `connect()` resumes in which a live child exists that only `terminate()` can reap.
- **subprocess-connect-is-idempotent**: `connect()` MUST be a no-op (`guard case .idle = state else { return }`) when called while `state` is `.connecting` or `.connected`; a second, concurrent call MUST return immediately without waiting for the first call and MUST NOT spawn a second child process.
- **subprocess-connect-order**: A `connect()` that proceeds MUST set `state = .connecting` before its first suspension, then call `channel.launch()`; on failure it MUST reset `state = .idle` and rethrow without spawning a pump. On success it MUST re-check `state == .connecting` (returning early otherwise) before calling `channel.messages()`, and MUST re-check `state == .connecting` a second time (returning early otherwise) before setting `state = .connected` and starting the forwarding task — both re-checks exist because a `disconnect()` may land in either suspension.
- **subprocess-blank-line-filtering**: The forwarding task MUST discard any frame for which every byte is one of LF (`0x0A`), CR (`0x0D`), space (`0x20`), or tab (`0x09`) — including an empty frame — and MUST NOT yield it into the message stream; every other frame MUST be yielded unmodified, with its trailing delimiter byte intact.
- **subprocess-disconnect-is-idempotent**: `disconnect()` MUST be a no-op when `state` is already `.idle`; otherwise it MUST set `state = .idle`, await `channel.terminate()`, await the forwarding task's completion, clear the forwarding task, and unconditionally call `messageContinuation.finish()` once more as a safety net.
- **subprocess-send-requires-connected-state**: `send(_:)` MUST throw `MCPError.transportError(Errno(rawValue: ENOTCONN))` when `state` is not `.connected` — sending before `connect()` or after `disconnect()` MUST fail with that specific error, matching `StdioTransport`'s contract byte for byte — and otherwise MUST forward the framed data to `channel.send(_:)`.
- **subprocess-receive-returns-stable-stream**: `receive()` MUST return the same `AsyncThrowingStream` instance on every call, not a new stream per call.

`HostMCPServer`

- **host-server-is-main-actor**: `HostMCPServer` MUST be a `@MainActor final class`.
- **host-server-wires-in-memory-pair**: `init` MUST create a connected `InMemoryTransport` pair via `InMemoryTransport.createConnectedPair()`, expose the client side as the public `clientTransport`, and retain the server side privately as `serverTransport`.
- **host-server-declares-no-list-changed**: The underlying `MCP.Server` MUST be constructed with `capabilities: MCP.Server.Capabilities(tools: .init(listChanged: false))` — this server MUST NOT claim it will emit `tools/list_changed`.
- **host-server-start-and-stop**: `start()` MUST register the tool handlers and then call `server.start(transport: serverTransport)`; `stop()` MUST call `server.stop()`.
- **host-server-lists-two-tools**: `ListTools` MUST return exactly two tools, `host_app_info` and `host_open_chat_window`, each declaring an object input schema with no properties.
- **host-app-info-tool-body**: `CallTool` for `host_app_info` MUST return non-error text containing `appName`, `appVersion`, and `pluginNames` joined by `", "`, or the literal `(none)` when `pluginNames` is empty.
- **host-open-chat-window-tool-effect**: `CallTool` for `host_open_chat_window` MUST invoke the `openChatWindow` closure supplied at `init` and MUST return the fixed non-error text "Opened a new chat window."
- **host-server-unknown-tool-is-not-an-error-throw**: `CallTool` for any tool name other than the two declared tools MUST return a result with `isError: true` and text "Unknown tool: \(params.name)" — it MUST NOT throw.
- **host-server-ignores-tool-arguments**: Neither tool handler MUST read `params.arguments` — both declared input schemas have no properties and no handler inspects the arguments dictionary, so any arguments a caller supplies are accepted and ignored.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configuration` (parameter to `MCPClient.init`) | `MCPServerConfiguration` | none — required | The server this client connects to: its transport, name, and id. |
| `secrets` (parameter to `MCPClient.init`) | `[String: String]` | `[:]` | Secret environment values merged over `configuration`'s own environment for a `.stdio` server, per `secrets-override-environment`. |
| `clientName` (parameter to `MCPClient.init`) | `String` | `"AgenticToolkit"` | The name this client presents to the MCP server during initialization. |
| `clientVersion` (parameter to `MCPClient.init`) | `String` | `"1.0.0"` | The version this client presents to the MCP server during initialization. |
| `store` (parameter to `MCPServerRegistry.init`) | `SettingsStore` | none — required | Source of the `mcp.serverConfigurations` and `mcp.serverSecrets` settings the registry reconciles against. |
| `clientFactory` (parameter to `MCPServerRegistry.init`) | `ClientFactory` (`@MainActor (MCPServerConfiguration, [String: String]) -> any MCPClientProtocol`) | Constructs a real `MCPClient(configuration:secrets:)` | Lets a caller substitute a test double; production code accepts the default. |
| `mcp.serverConfigurations` (settings key) | `[MCPServerConfiguration]` | `[]` | Non-secret server descriptions, routed to the regular settings provider. |
| `mcp.serverSecrets` (settings key) | `MCPServerSecrets` (`[String: [String: String]]`) | `[:]` | Secret environment values keyed by server id, routed to the secure (Keychain) settings provider. |
| `logger` (parameter to `SubprocessTransport.init`) | `Logger?` | `nil` (a no-op `SwiftLogNoOpLogHandler` logger) | Diagnostic logger for the transport's own debug messages; production code does not supply one. |
| `appName`, `appVersion` (parameters to `HostMCPServer.init`) | `String` | none — required | Reported by the `host_app_info` tool. |
| `pluginNames` (parameter to `HostMCPServer.init`) | `[String]` | `[]` | Reported by the `host_app_info` tool, joined by `", "` or rendered as `(none)` when empty. |
| `openChatWindow` (parameter to `HostMCPServer.init`) | `@Sendable () -> Void` | a no-op closure `{}` | Invoked when the `host_open_chat_window` tool is called. |
| `abandonedConnectBudgetSeconds` (private static constant on `MCPClient`) | `TimeInterval` | `1.0` | Fixed wall-clock bound `teardown()` gives an in-flight connect before abandoning it; not exposed to callers. |

