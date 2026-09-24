---
id: 52650804-a096-4b71-b4eb-da3afa95ac56
title: MCP Plumbing
domain: agentictoolkit://recipes/mcp-plumbing
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owns the lifecycle of one Model Context Protocol server connection and reconciles
  the live client set against stored server configurations and secrets.
platforms:
- swift
- macos
tags:
- mcp
- subprocess
- concurrency
- registry
- settings
depends-on: []
related:
- agentictoolkit://recipes/mcp-chips-bar-view
references: []
approved-by: ''
approved-date: ''
---

# MCP Plumbing

## Overview

`mcp-plumbing` is `AgenticToolkitCore`'s and `AgenticToolkitMacOS`'s connection
layer for the Model Context Protocol: the code that turns a stored
`MCPServerConfiguration` into a live, tool-capable connection, keeps that
connection's lifecycle safe under concurrent connect/disconnect requests, and
lets the host application itself act as an in-process MCP server. It spans
six files:

- `packages/apple/AgenticToolkit/Core/MCP/MCPClient.swift` — the `MCPClient`
  actor, its `MCPClientProtocol` surface, `MCPClientState`, and
  `MCPClientError`. One instance owns one server's transport, its cached tool
  list, and the connect/disconnect race-safety documented on `teardown()`.
- `packages/apple/AgenticToolkit/Core/MCP/MCPServerConfiguration.swift` — the
  `Codable`, user-editable description of one server (a stdio command or an
  HTTP endpoint) that `SettingsStore` persists.
- `packages/apple/AgenticToolkit/Core/MCP/MCPServerRegistry.swift` — the
  `@MainActor` `ObservableObject` that reconciles a set of live `MCPClient`s
  against the configurations and secrets `SettingsStore` reports, and exposes
  `tools(forIds:)` to callers assembling a tool list across servers.
- `packages/apple/AgenticToolkit/Core/MCP/MCPSettings.swift` — the
  `UserSetting` declarations that route non-secret server descriptions to the
  regular settings provider and secret environment values to the secure
  (Keychain) provider.
- `packages/apple/AgenticToolkit/Core/MCP/SubprocessTransport.swift` — the
  `MCP.Transport` conformance built on this codebase's shared
  `SubprocessChannel`, used for every `.stdio` server instead of the MCP
  SDK's own `StdioTransport`.
- `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` — a
  self-contained, macOS-only in-process MCP server that exposes host
  application info and a "open a chat window" tool over an in-memory
  transport pair, with no subprocess and no registry integration.

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

## Appearance

Not applicable — this is a Model Context Protocol connection and reconciliation layer, not a visual component.

## States

Not applicable — this is a Model Context Protocol connection and reconciliation layer, not a visual component; its runtime state machines (`MCPClientState`, `SubprocessTransport`'s idle/connecting/connected) are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a Model Context Protocol connection and reconciliation layer with no user interface of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| mcp-plumbing-001 | registry-clients-mirror-enabled-configurations-only | A freshly constructed `MCPServerRegistry` with no configurations set | `registry.clients.isEmpty == true` (`MCPServerRegistryTests.testStartsEmpty`) |
| mcp-plumbing-002 | registry-reconcile-adds-missing | `store.set([enabledConfig], for: .mcpServerConfigurations)` | `registry.clients.count == 1`, `registry.client(for: enabledConfig.id)` is non-nil, and the fake factory's `connectCalls` reaches `1` (`MCPServerRegistryTests.testCreatesClientForEnabledConfiguration`) |
| mcp-plumbing-003 | registry-clients-mirror-enabled-configurations-only | `store.set([disabledConfig], for: .mcpServerConfigurations)` where `isEnabled == false` | `registry.clients.isEmpty == true` (`MCPServerRegistryTests.testIgnoresDisabledConfiguration`) |
| mcp-plumbing-004 | registry-reconcile-removes-first | An enabled config is stored, then re-stored with `isEnabled = false` | `registry.clients.isEmpty == true` and the fake factory's `disconnectCalls` reaches `1` (`MCPServerRegistryTests.testDisablingConfigurationRemovesClient`) |
| mcp-plumbing-005 | registry-reconcile-removes-first | An enabled config is stored, then `store.set([], for: .mcpServerConfigurations)` | `registry.clients.isEmpty == true` and the removed client's `disconnect()` is eventually called (`MCPServerRegistryTests.testRemovingConfigurationDisconnectsClient`) |
| mcp-plumbing-006 | registry-reconcile-adds-missing | `store.set([config.id.uuidString: ["GITHUB_TOKEN": "ghp_test"]], for: .mcpServerSecrets)` stored before the matching configuration | The fake factory's `lastSecrets == ["GITHUB_TOKEN": "ghp_test"]` (`MCPServerRegistryTests.testPassesSecretsToFactory`) |
| mcp-plumbing-007 | registry-tools-for-ids | Two enabled configs `A` and `B`, each client given one cached tool (`tool_a`, `tool_b`) | `tools(forIds: [A.id, B.id])` yields both names; `tools(forIds: [A.id])` yields only `tool_a` (`MCPServerRegistryTests.testToolsCollectsFromMatchingClients`) |
| mcp-plumbing-008 | configurations-setting-routing, secrets-setting-routing | `store.set(configs, for: .mcpServerConfigurations)`; `store.set(secrets, for: .mcpServerSecrets)` | `regular.contains(.mcpServerConfigurations) == true` and `secure.contains(.mcpServerConfigurations) == false`; conversely `secure.contains(.mcpServerSecrets) == true` and `regular.contains(.mcpServerSecrets) == false` (`MCPSettingsTests.testConfigurationsRouteToRegularProvider`, `testSecretsRouteToSecureProvider`) |
| mcp-plumbing-009 | configuration-transport-shape, configuration-equality-covers-all-fields | A `.stdio` and an `.http` `MCPServerConfiguration` are each round-tripped through `JSONEncoder`/`JSONDecoder` | The decoded value equals the original for both transport kinds (`MCPServerConfigurationTests.testStdioRoundTrip`, `testHttpRoundTrip`) |
| mcp-plumbing-010 | configuration-id-is-stable | A configuration's `name` and `isEnabled` are mutated after construction | `id` is unchanged (`MCPServerConfigurationTests.testIdentifiableUsesStableId`) |
| mcp-plumbing-011 | connect-guard-is-first | `disconnect()` is called on a freshly constructed `MCPClient`, then `connect()` is called | `connect()` throws `MCPClientError.clientHasBeenDisconnected`, no server process is ever spawned, and `state == .disconnected` (`MCPClientRaceTests.connectAfterDisconnectThrows`) |
| mcp-plumbing-012 | teardown-sequence | `connect()` is started (unawaited) against a child that never answers `initialize`, then `disconnect()` is called after the spawn is observed | No matching process survives once `disconnect()` returns (`MCPClientRaceTests.parkedConnectIsStillReapedByDisconnect`) |
| mcp-plumbing-013 | connect-success-transition, teardown-sequence | `connect()` is started unawaited and immediately raced with `disconnect()`, repeated 20 times with fresh clients | No probe process survives across all 20 iterations (`MCPClientRaceTests.disconnectRacingConnectStopsTheChild`) |
| mcp-plumbing-014 | abandoned-connect-budget-value, teardown-error-suppression | A connect is suspended (via the test seam) exactly between publishing the transport and calling `MCP.Client.connect(transport:)`, then `disconnect()` is called | `disconnect()` returns within its budget (well under 8s) and no probe process survives (`MCPClientRaceTests.teardownAbandonsAWedgedConnectAndStillReapsTheChild`) |
| mcp-plumbing-015 | teardown-sequence | Same wedged-connect setup as mcp-plumbing-014, with CPU consumption measured for 1 second after `disconnect()` returns | Measured CPU consumption stays under the test's `0.25` CPU-second ceiling, and the abandoned connect task itself completes (`MCPClientRaceTests.teardownFreesTheAbandonedConnectRatherThanSpinning`) |
| mcp-plumbing-016 | client-is-an-actor, connect-suspension-hook-is-nil-in-production | A connect is suspended (via the test seam) before its `Task.checkCancellation()`, then raced with `disconnect()` | The connect task ends with a `CancellationError` (not a spawn), `disconnect()` returns, and no probe process survives (`MCPClientRaceTests.connectCancelledBeforeItBuildsATransportNeverSpawns`) |
| mcp-plumbing-017 | subprocess-blank-line-filtering | A raw frame consisting of the two bytes `0x0D 0x0A` (a CRLF blank line) is produced by the child | `SubprocessTransport.isBlankLine(frame) == true`, and the frame is never yielded into the message stream |
| mcp-plumbing-018 | subprocess-send-requires-connected-state | `send(_:)` is called on a `SubprocessTransport` whose state is `.idle` | The call throws `MCPError.transportError(Errno(rawValue: ENOTCONN))` without touching `channel` |
| mcp-plumbing-019 | host-app-info-tool-body | `HostMCPServer(appName: "Demo", appVersion: "2.0", pluginNames: [])` receives a `CallTool` for `host_app_info` | Returned text reads `Host: Demo\nVersion: 2.0\nPlugins: (none)`, `isError == false` |
| mcp-plumbing-020 | host-server-unknown-tool-is-not-an-error-throw | `CallTool` is invoked with `params.name == "nonexistent_tool"` | Returned result has `isError == true` and text `Unknown tool: nonexistent_tool`; no error is thrown |

## Edge Cases

- **Null/empty input**: `MCPServerConfiguration.Transport.stdio` with `environment: [:]` MUST leave `secrets-override-environment`'s merge as exactly `secrets` (MUST). `HostMCPServer` with `pluginNames: []` MUST render the plugin list as the literal `(none)` (MUST). `MCPServerRegistry.reconcile` with `secrets[configuration.id.uuidString]` absent MUST treat the server's secrets as `[:]`, not fail (MUST). `tools(forIds: [])` MUST return `[]` (MUST).
- **Boundary values**: The `abandonedConnectBudgetSeconds` constant is fixed at `1.0`; `teardown()`'s step-4 wait MUST NOT exceed that bound regardless of how long the abandoned connect would otherwise take (MUST). `SubprocessTransport.isBlankLine` applied to a zero-length `Data()` MUST return `true` (`allSatisfy` over an empty collection is vacuously true), so an empty frame MUST be filtered exactly as a whitespace-only one is (MUST).
- **Concurrent access**: `MCPClient` is an actor, so its own `connect()`, `disconnect()`, `refreshTools()`, and `callTool(name:arguments:)` calls are serialized onto one isolation domain; a `connect()` racing a `disconnect()` on the same instance MUST resolve deterministically per `teardown-sequence` and `connect-guard-is-first`, never stranding a child process (MUST). `MCPServerRegistry.reconcile` starts each client's `connect()` or `disconnect()` in its own unstructured `Task` and does not await any of them from within `reconcile` itself, so multiple servers' connections and teardowns proceed concurrently and independently of one another (MUST, per `registry-reconcile-removes-first` and `registry-reconcile-adds-missing`). A second, concurrent `SubprocessTransport.connect()` call while the first is still `.connecting` MUST return immediately without spawning a second child (MUST, per `subprocess-connect-is-idempotent`).
- **Error states**: A `.stdio` command that cannot be launched surfaces as a thrown error out of `channel.launch()`, which `SubprocessTransport.connect()` propagates after resetting its own state to `.idle`, and which `MCPClient.connect()` propagates after setting `state = .failed("\(error)")` and running `teardown()` (MUST). A `connect()` failure raised inside `MCPServerRegistry.reconcile`'s unawaited `Task` is caught and logged via `Self.logger.error(...)`, and the client remains present in `clients` with its own `state == .failed(...)`; `reconcile` itself never throws or crashes on a connect failure (MUST, per `registry-connect-failure-is-logged-not-thrown`). `send(_:)` on a `SubprocessTransport` that is not `.connected` throws `MCPError.transportError(Errno(rawValue: ENOTCONN))` rather than whatever the underlying channel would otherwise raise (MUST).
- **Offline/disconnected state**: `disconnect()` called on a `SubprocessTransport` that never had `connect()` called (still `.idle`) MUST be a no-op — `channel.terminate()` MUST NOT be invoked (MUST, per `subprocess-disconnect-is-idempotent`). A `connect()` that spawns a child which never answers the MCP `initialize` handshake (an unresponsive or hung server) is not freed by cancellation alone — cancelling `connectTask` cannot unwedge a bare continuation with no cancellation handler — and is only unwedged by a subsequent `disconnect()`'s `teardown()`, per `abandoned-connect-budget-value` and `teardown-error-suppression` (MUST).
- **Cancellation**: Cancelling the unstructured `Task` a caller wraps around `MCPClient.connect()` before that task reaches its own suspension points does not, by itself, stop `establishConnection()` — cancellation is only observed at `establish-connection-order`'s `Task.checkCancellation()` check, and once a transport has been built and `MCP.Client.connect(transport:)` has been called, cancellation alone cannot recover the child; only `teardown()`'s two `transport?.disconnect()` calls and two `client.disconnect()` calls reliably reap it (MUST, per `teardown-sequence`).
- **tool-list-refresh-failure**: NEEDS REVIEW: Not implemented in source. `registerToolListChangedHandler`'s handler calls `try? await self.refreshTools()`; if `refreshTools()` throws when the server emits `tools/list_changed`, the error is discarded with no log entry, no state transition, and no retry, so `cachedTools` simply remains whatever it was before the notification. Settling whether that silence is acceptable, or whether a failed refresh should log or set `state = .failed(...)`, needs a decision from whoever owns `MCPClient`'s error-reporting contract.
- **HTTP transport abandoned connect**: `teardown()` runs the same `teardown-sequence` for a `.http` server as for a `.stdio` one, including the repeated `client.disconnect()`. That repeat is documented and measured only against `SubprocessTransport.receive()` returning its finished stream and spinning `MCP.Client`'s message loop; how `HTTPClientTransport` behaves after an abandoned connect is owned by the MCP SDK package, outside these six sources.

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

## Deep Linking

Not applicable: none of the six sources define a URL scheme, route, or navigation destination — `MCPServerConfiguration.Transport.http`'s `URL` addresses an MCP server's HTTP endpoint, not an app deep link.

## Localization

`MCPClientError` and `MCPServerRegistry` produce hardcoded, unlocalized English strings with no string-catalog key, and `HostMCPServer`'s tool descriptions and tool-call bodies are likewise hardcoded English:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The MCP server was disabled or removed before its connection finished starting; nothing was launched." | `MCPClientError.clientHasBeenDisconnected.errorDescription` |
| (none — literal, no catalog key) | "Failed to connect MCP server %@: %@" (interpolated with `configuration.name` and `error.localizedDescription`) | `MCPServerRegistry.reconcile`'s failure log line |
| (none — literal, no catalog key) | "Return the host application's name, version, and configured AI plugins." | `host_app_info`'s tool `description` |
| (none — literal, no catalog key) | "Open a new AI chat window in the host application." | `host_open_chat_window`'s tool `description` |
| (none — literal, no catalog key) | "Host: %@\nVersion: %@\nPlugins: %@" | `host_app_info`'s success body |
| (none — literal, no catalog key) | "Opened a new chat window." | `host_open_chat_window`'s success body |
| (none — literal, no catalog key) | "Unknown tool: %@" | `CallTool`'s default-case body for an unrecognized tool name |

## Accessibility Options

Not applicable: none of the six sources render UI, so none observes Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the six sources reads a feature-flag or settings key beyond the two `UserSetting`s (`mcp.serverConfigurations`, `mcp.serverSecrets`) already documented under Configuration, neither of which gates a feature on or off.

## Analytics

Not applicable: none of the six sources contains an analytics or event-tracking call.

## Privacy

- **Data handled**: `MCPServerConfiguration`'s stdio `environment` and `MCPServerSecrets`' per-server secret dictionary MAY each carry credentials (e.g. `"GITHUB_TOKEN"`) that a user supplies when configuring a server; `MCPClient` forwards the merged environment to the spawned subprocess (`secrets-override-environment`) or, for an HTTP server, whatever `MCPServerConfiguration.Transport.http`'s `endpoint` and the SDK's `HTTPClientTransport` send, with no inspection of its own beyond the merge itself.
- **Storage**: Non-secret server descriptions are stored by `SettingsStore` under `"mcp.serverConfigurations"` in the regular settings provider; secret environment values are stored under `"mcp.serverSecrets"`, routed to the secure provider (Keychain in production) via `isSecure: true`, per `secrets-setting-routing` — secrets MUST NOT reach the regular settings file.
- **Transmission**: For a `.stdio` server, secrets are transmitted only as environment variables to a locally spawned child process, never over the network by this component itself; for a `.http` server, whatever headers or body the SDK's `HTTPClientTransport` sends travel to `endpoint` over HTTPS or HTTP as that URL specifies. `MCPServerRegistry`'s failure log (`registry-connect-failure-is-logged-not-thrown`) interpolates only `configuration.name` and `error.localizedDescription`, never a secret or environment value.
- **Retention**: Secrets persist in the secure provider until the user edits or removes the corresponding server configuration; the source defines no expiry, rotation, or automatic revocation for a stored secret.
- **Token lifecycle**: the component implements no expiry, rotation, or revocation for a stored server secret; a secret stays valid in the secure provider until the user edits or removes the server configuration.

## Logging

Subsystem: `com.mikefullerton.agentictoolkit` | Category: `MCPClient`, `MCPServerRegistry`

| Event | Level | Message |
|-------|-------|---------|
| A client's `connect()` throws during `MCPServerRegistry.reconcile` | error | "Failed to connect MCP server \(configuration.name): \(error.localizedDescription)" |
| `SubprocessTransport.connect()` completes its pump setup | debug | "Transport connected successfully" |
| `SubprocessTransport.disconnect()` finishes | debug | "Transport disconnected" |

`MCPClient` itself conforms to `Loggable` and exposes a `nonisolated static let logger`, but the given source contains no call site that emits through it directly — the capability exists without an observed emission in `MCPClient.swift`.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/MCP/*.swift` (built into the `AgenticToolkitCore` framework target, macOS-only) and `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` (built into the `AgenticToolkitMacOS` target). `MCPServerRegistry`'s `@Published clients` and `MCPClient`'s `state`/`cachedTools` are consumed reactively by SwiftUI views (e.g. the sibling `MCPChipsBarView` recipe) via `ObservableObject`, but nothing in these six files imports `SwiftUI` itself — the layer is UI-framework-agnostic.
- **Compose**: Model `MCPClient` as a class wrapping a `Mutex`-guarded `MutableStateFlow<MCPClientState>` and `MutableStateFlow<List<Tool>>` in place of the actor's isolated `state`/`cachedTools`, with `connect`/`disconnect`/`refreshTools`/`callTool` as `suspend` functions; reproduce `teardown-sequence`'s ordering with `withTimeoutOrNull(1_000L) { connectJob?.join() }` in place of the wall-clock budget, and `connectJob?.cancel()` in place of `connectTask?.cancel()`. Model `MCPServerRegistry` as a class exposing `StateFlow<Map<UUID, MCPClientProtocol>>`, driven by `combine` over two settings `Flow`s in place of Combine's `combineLatest`. Model `SubprocessTransport` with `ProcessBuilder`, reading stdout line-by-line on a background dispatcher to reproduce `.newlineDelimited` framing, and filtering blank lines the same way `subprocess-blank-line-filtering` does. Route secrets through Android's `EncryptedSharedPreferences` in place of Keychain.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive and no OS keychain), model `MCPClient` as an `EventEmitter`-based class or an async class exposing `state`/`cachedTools` getters, with `connect`/`disconnect` as `async` methods; reproduce `teardown-sequence`'s bounded wait with `Promise.race([connectPromise, delay(1000)])` in place of the wall-clock budget. Model `MCPServerRegistry` as a class holding a `Map<string, MCPClientProtocol>` and re-running its reconcile logic on every settings-store change event. Model `SubprocessTransport` with `child_process.spawn`, reading `.stdout` through `readline.createInterface` (or manual `\n`-splitting) for `.newlineDelimited` framing, and filtering blank lines per `subprocess-blank-line-filtering`; route secrets through an OS-keychain wrapper (e.g. `keytar`) in place of Keychain, and support only the `.http` transport in an Electron renderer sandbox that cannot spawn arbitrary executables.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AgenticToolkitCore`/`AgenticToolkitMacOS` differs, never this contract.
- **WinUI 3**: Model the `.http` path of `MCPClient`/`SubprocessTransport` with `System.Net.Http.HttpClient`, and the `.stdio` path with `System.Diagnostics.Process`/`ProcessStartInfo` (`RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` all `true`), reading stdout via a `StreamReader.ReadLineAsync()` loop to reproduce `.newlineDelimited` framing and `subprocess-blank-line-filtering`'s blank-line skip. Reproduce `teardown-sequence`'s bounded wait for an abandoned connect with a `CancellationTokenSource` whose `CancelAfter(TimeSpan.FromSeconds(1))` gates a `Task.WhenAny(connectTask, Task.Delay(Timeout.Infinite, token))`, in place of `withWallClockBudget`. Represent `MCPServerRegistry.clients` as an `ObservableCollection<KeyValuePair<Guid, IMcpClient>>` or a `Dictionary` behind a type implementing `INotifyPropertyChanged`/`INotifyCollectionChanged`, raised from the `reconcile` equivalent the same way `@Published` raises `objectWillChange`. Store `mcp.serverConfigurations` via `Windows.Storage.ApplicationData.LocalSettings` (serialized with `System.Text.Json`) and route `mcp.serverSecrets` through `Windows.Security.Credentials.PasswordVault` in place of Keychain, since `Windows.Storage`'s settings containers are not encrypted at rest the way `mcp.serverSecrets` requires.

## Design Decisions

**Decision**: `teardown()` disconnects the transport and the underlying `MCP.Client` twice each (steps 2+5 and 3+6), rather than once.
**Rationale**: Per `MCPClient.swift`'s own doc comment on `teardown()`, the first pair (steps 2-3) closes the window `MCP.Client.send`'s unstructured registration opens for a request that is mid-flight when a disconnect lands, while the second pair (steps 5-6) reaps a connect that resumes *after* steps 1-3 have already run out of things to catch — a connect suspended between publishing `self.transport` and calling `MCP.Client.connect(transport:)`. Both `SubprocessTransport.disconnect()` and `MCP.Client.disconnect()` are documented no-ops when already idle, so the repeated calls cost nothing in every ordering except the one each pair exists for.
**Approved**: pending

**Decision**: `teardown()`'s wait for an abandoned `connectTask` (step 4) is bounded to `abandonedConnectBudgetSeconds` (1.0 second) and both the operation's own error and a `WallClockBudgetExceeded` are discarded with `try?`.
**Rationale**: Per the source's own measurements cited in its doc comment, an unbounded wait here never returns for a connect wedged on the MCP SDK's bare `initialize` continuation, because nothing but step 6's `client.disconnect()` can resume it — and step 6 only runs after this wait ends. A bounded wait trades a fixed, small delay (measured at roughly 1.01-1.03 seconds end to end) for guaranteeing steps 5 and 6 run; propagating either the operation's error or the budget's own timeout error would serve no caller, since `teardown()`'s job is releasing resources, not reporting the abandoned connect's outcome.
**Approved**: pending

**Decision**: `SubprocessTransport` tracks `idle`/`connecting`/`connected` as a three-case enum rather than a `Bool`.
**Rationale**: Per the type's own doc comment, a `Bool` set only after `connect()`'s suspension at `channel.launch()` would let a `disconnect()` landing in that window observe "not yet connected" and become a no-op while a live child exists — stranding it for the life of the app. The `connecting` case exists precisely to make `disconnect()` treat that window the same as a fully connected one.
**Approved**: pending

**Decision**: `HostMCPServer` is self-contained, with no integration into `MCPServerRegistry` and no new case added to `MCPServerConfiguration.Transport` for an in-process server.
**Rationale**: Per the type's own doc comment, this keeps the sample from expanding the `Transport` enum with an in-process variant; a host application that wants `HostMCPServer`'s tools available to its own chat surface is expected to build an `MCP.Client` directly against `clientTransport` and wire that in wherever it already routes tool calls, rather than this component doing so on the host's behalf.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | failed | Security |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

`separation-of-concerns` passes because connection lifecycle and settings-reconciliation logic live entirely in these six files, with `MCPServerRegistry` exposing only `client(for:)` and `tools(forIds:)` to UI-layer consumers such as the sibling `MCPChipsBarView` recipe. `unit-test-coverage` is partial because `MCPClientRaceTests`, `MCPServerRegistryTests`, `MCPServerConfigurationTests`, and `MCPSettingsTests` cover `MCPClient`, `MCPServerRegistry`, `MCPServerConfiguration`, and the `UserSetting` routing thoroughly, but the given sources include no dedicated test file for `SubprocessTransport` or `HostMCPServer`. `explicit-error-handling` is partial because most failure paths throw a specific, named error or log explicitly, but two paths deliberately swallow an error with `try?` and no signal at all: `registerToolListChangedHandler`'s notification handler (a failed `refreshTools()` leaves `cachedTools` silently stale, see the Edge Cases "Tool list refresh failure" item) and `teardown()`'s step-4 wait (`teardown-error-suppression`) — the latter is a documented, argued trade-off, the former is a genuine open gap. `secure-storage` passes because `mcp.serverSecrets` is the only field carrying credential-shaped data and it is routed to the secure (Keychain) provider via `isSecure: true`, per `secrets-setting-routing`. `secure-log-output` passes because the only log call in these six sources (`registry-connect-failure-is-logged-not-thrown`) interpolates only a server's `name` and `error.localizedDescription`, never an environment value or secret. `token-lifecycle` fails because the source defines no expiry, rotation, or revocation for a stored server secret, as detailed in the Privacy section's Token lifecycle bullet. `timeout-handling` passes because `teardown-sequence`'s wall-clock budget leaves `MCPClient` in a consistent state — `connectTask` cleared, `transport` disconnected exactly twice, `client` disconnected exactly twice — whether the awaited task finishes first or the budget expires first. `fault-tolerance` is partial because `connect()` itself has no wall-clock bound of its own (only an already-torn-down client's `teardown()` is bounded), so a `.stdio` server whose child never answers `initialize`, or a `.http` server behind an unresponsive endpoint, can leave a single `connect()` call hanging indefinitely until some other code path calls `disconnect()`.

Two further gaps that qualify these findings are recorded beside the requirements they concern rather than here: the open question on tool-list-refresh-failure (Edge Cases), and the abandoned-connect teardown over the `.http` transport, whose repeated-disconnect fix is measured only for `.stdio` (Edge Cases, "HTTP transport abandoned connect").

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
