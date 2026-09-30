<!-- leaf: implement-general-2/mcp-plumbing--part-2 · source: mcp-plumbing.md -->

# MCP Plumbing — continued (part 2)

**Rules** (cite as `implement-general-2/mcp-plumbing--part-2#<slug>`):

- `client-disconnected-error-message` MUST
- `client-state-shape` MUST
- `client-protocol-surface` MUST
- `client-identity` MUST
- `client-initial-state` MUST
- `connect-guard-is-first` MUST
- `connect-runs-in-held-task` MUST
- `connect-success-transition` MUST
- `connect-failure-transition` MUST
- `establish-connection-order` MUST
- `disconnect-is-terminal` MUST
- `teardown-sequence` MUST
- `abandoned-connect-budget-value` MUST
- `teardown-error-suppression` MUST
- `transport-selection` MUST
- `secrets-override-environment` MUST
- `stdio-transport-configuration` MUST
- `tool-list-changed-refresh` MUST
- `refresh-tools-replaces-cache` MUST
- `call-tool-forwards-and-defaults-error-flag` MUST
- `client-is-an-actor` MUST
- `connect-suspension-hook-is-nil-in-production` MUST
- `configuration-shape` MUST
- `configuration-transport-shape` MUST
- `configuration-default-id` MUST
- `configuration-id-is-stable` MUST
- `configuration-equality-covers-all-fields` MUST
- `configuration-secrets-live-elsewhere` MUST
- `server-secrets-shape` MUST
- `configurations-setting-routing` MUST
- `secrets-setting-routing` MUST

## Behavioral Requirements

`MCPClientError` and `MCPClientState`

- **client-disconnected-error-message**: `MCPClientError.clientHasBeenDisconnected` MUST provide a `LocalizedError.errorDescription` of "The MCP server was disabled or removed before its connection finished starting; nothing was launched." — a bare `Swift.Error` enum reaching `localizedDescription` otherwise reads as an opaque "The operation couldn't be completed" message in every logger and alert that consumes it.
- **client-state-shape**: `MCPClientState` MUST be one of exactly four cases — `disconnected`, `connecting`, `connected`, `failed(String)` — and MUST conform to `Sendable` and `Equatable`.

`MCPClientProtocol`

- **client-protocol-surface**: Any `MCPClientProtocol` conformer MUST be an `Actor` and MUST expose `id` and `name` as `nonisolated` (readable without an `await`), plus actor-isolated `state: MCPClientState` and `cachedTools: [MCP.Tool]`, and the four operations `connect() async throws`, `disconnect() async`, `refreshTools() async throws`, and `callTool(name:arguments:) async throws -> (content: [MCP.Tool.Content], isError: Bool)`.

`MCPClient`

- **client-identity**: `MCPClient.id` and `MCPClient.name` MUST be taken from `configuration.id` and `configuration.name` at `init` and MUST NOT change for the life of the instance.
- **client-initial-state**: A newly initialized `MCPClient` MUST report `state == .disconnected` and `cachedTools == []` before `connect()` is ever called.
- **connect-guard-is-first**: `connect()` MUST check `isShutDown` as its first statement, before any suspension point, and MUST throw `MCPClientError.clientHasBeenDisconnected` without doing anything else when `disconnect()` has already completed on this instance.
- **connect-runs-in-held-task**: `connect()` MUST set `state = .connecting`, then run `establishConnection()`'s work inside a `Task` retained as `connectTask`, rather than inline, so that a concurrent `teardown()` has a specific task to cancel and await.
- **connect-success-transition**: On success, `connect()` MUST clear `connectTask` only if it still equals the task that just finished, and MUST advance `state` to `.connected` only if `state` is still `.connecting` at that point — a `teardown()` that ran to completion while this `connect()` was suspended MAY have already reset both, in which case `connect()` MUST return successfully anyway while `state` reads `.disconnected` and the client owns no transport.
- **connect-failure-transition**: On failure, `connect()` MUST clear `connectTask` under the same equality guard, MUST set `state = .failed("\(error)")` only if `state` is still `.connecting`, MUST call `teardown()` before returning, and MUST rethrow the original error.
- **establish-connection-order**: `establishConnection()` MUST, in order: check `Task.checkCancellation()`, build the transport via `makeTransport()` and assign it to `self.transport`, call `MCP.Client.connect(transport:)`, register the tool-list-changed notification handler, then call `refreshTools()`.
- **disconnect-is-terminal**: `disconnect()` MUST set `isShutDown = true` before any suspension, MUST NOT ever clear that flag, MUST call `teardown()`, and MUST set `state = .disconnected` afterward — a later `connect()` on the same instance MUST throw rather than starting a second server; reconnecting requires constructing a new `MCPClient`.
- **teardown-sequence**: `teardown()` MUST perform, in this exact order: (1) synchronously cancel `connectTask`; (2) `await transport?.disconnect()`; (3) `await client.disconnect()`; (4) if a `connectTask` is still set, await its `.value` under a fixed wall-clock budget (`abandonedConnectBudgetSeconds`), discarding both the operation's own error and a budget-exceeded error, then cancel the task again and clear `connectTask`; (5) `await transport?.disconnect()` again and clear `transport`; (6) `await client.disconnect()` again. Each of the two repeated calls MUST run even though the first of its pair may already have been a no-op, because the ordering that makes step 4's wait bounded is exactly the ordering step 2 and step 3 cannot reach.
- **abandoned-connect-budget-value**: The wall-clock budget `teardown()` gives an in-flight `connectTask` MUST be `1.0` seconds (`abandonedConnectBudgetSeconds`), and it MUST NOT be configurable per instance.
- **teardown-error-suppression**: An error thrown by the awaited `connectTask` in step 4 of `teardown-sequence`, or a `WallClockBudgetExceeded` from the budget itself, MUST NOT propagate out of `teardown()` — both MUST be discarded via `try?`.
- **transport-selection**: `makeTransport()` MUST return a `SubprocessTransport` for `configuration.transport == .stdio(command, arguments, environment)` and an `HTTPClientTransport` for `.http(endpoint, streaming)`.
- **secrets-override-environment**: For a `.stdio` transport, the child's environment MUST be `configuration.transport`'s `environment` merged with `self.secrets`, with a key present in both MUST resolving to the secret's value (`environment.merging(secrets) { _, secret in secret }`).
- **stdio-transport-configuration**: The `SubprocessTransport` built for a `.stdio` server MUST use `SubprocessChannel.Configuration` with `environmentPolicy: .mergeOverParent` (so the child still inherits `PATH`/`HOME` from the host process) and `framing: .newlineDelimited`.
- **tool-list-changed-refresh**: `registerToolListChangedHandler()` MUST register a handler for `ToolListChangedNotification` that calls `refreshTools()` on the client whenever the server emits that notification.
- **refresh-tools-replaces-cache**: `refreshTools()` MUST call `client.listTools()` and MUST replace `cachedTools` with the returned tool list in full (not merge or append).
- **call-tool-forwards-and-defaults-error-flag**: `callTool(name:arguments:)` MUST forward `name` and `arguments` to the underlying `MCP.Client.callTool(name:arguments:)` and MUST return `(result.content, result.isError ?? false)` — a `nil` `isError` from the server MUST be treated as `false`.
- **client-is-an-actor**: `MCPClient` MUST be declared as an `actor`, so `state`, `cachedTools`, `connectTask`, `isShutDown`, and `transport` are all actor-isolated and every call from outside serializes onto the same isolation domain; only `id` and `name` are `nonisolated`.
- **connect-suspension-hook-is-nil-in-production**: `connectSuspensionHook` MUST default to `nil` and MUST only be set by test code through the `internal` `setConnectSuspensionHook(_:)` method; with no hook installed, the two call sites in `establishConnection()` MUST cost exactly one optional-chain nil check each and MUST NOT suspend.

`MCPServerConfiguration`

- **configuration-shape**: `MCPServerConfiguration` MUST be `Codable`, `Sendable`, `Identifiable`, `Equatable`, and `Hashable`, and MUST expose `id: UUID` (immutable), `name: String`, `transport: Transport`, and `isEnabled: Bool`.
- **configuration-transport-shape**: `MCPServerConfiguration.Transport` MUST be one of exactly two cases — `.stdio(command: String, arguments: [String], environment: [String: String])` or `.http(endpoint: URL, streaming: Bool)` — and MUST be `Codable`, `Sendable`, `Equatable`, and `Hashable`.
- **configuration-default-id**: `init` MUST generate a fresh `UUID()` for `id` when the caller does not supply one, and MUST default `isEnabled` to `true`.
- **configuration-id-is-stable**: Mutating `name`, `transport`, or `isEnabled` on a value with a given `id` MUST NOT change that value's `id`.
- **configuration-equality-covers-all-fields**: Two `MCPServerConfiguration` values MUST compare equal only when `id`, `name`, `transport`, and `isEnabled` all match, and MUST compare unequal if any one field differs.
- **configuration-secrets-live-elsewhere**: `MCPServerConfiguration` MUST carry no secret material of its own — secret environment values for a server MUST be looked up separately, keyed by `id.uuidString`, from `UserSettings.mcpServerSecrets`.

`MCPSettings` / `UserSettings`

- **server-secrets-shape**: `MCPServerSecrets` MUST be `[String: [String: String]]`, where the outer key is a server's `id.uuidString` and the inner dictionary maps an environment-variable name to its secret value.
- **configurations-setting-routing**: `UserSettings.mcpServerConfigurations` MUST be declared with key `"mcp.serverConfigurations"`, default `[]`, and MUST NOT be marked `isSecure`, so it routes to the regular (non-secure) settings storage provider.
- **secrets-setting-routing**: `UserSettings.mcpServerSecrets` MUST be declared with key `"mcp.serverSecrets"`, default `[:]`, and MUST be marked `isSecure: true`, so it routes to the secure storage provider (Keychain in production) and never reaches the regular settings file.

`MCPServerRegistry`
