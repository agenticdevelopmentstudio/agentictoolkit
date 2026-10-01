---
id: 52650804-a096-4b71-b4eb-da3afa95ac56
title: MCP Plumbing
domain: agentictoolkit://cookbook/ai/mcp/mcp-plumbing
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/ai/chat/chat-window/mcp-chips-bar-view
references: []
approved-by: ''
approved-date: ''
---

# MCP Plumbing

## Overview

MCP Plumbing is the connection-lifecycle and reconciliation layer for the
Model Context Protocol: it turns a stored server configuration into a live,
tool-capable connection, keeps that connection's lifecycle safe under
concurrent connect/disconnect requests, and lets the host application itself
act as an in-process MCP server. It spans six files:

- `packages/apple/AgenticToolkit/Core/MCP/MCPClient.swift` — the client, its
  client-protocol surface, its connection-state type, and its error type. One
  instance owns one server's transport, its cached tool list, and the
  connect/disconnect race-safety documented on `teardown()`.
- `packages/apple/AgenticToolkit/Core/MCP/MCPServerConfiguration.swift` — the
  persisted, user-editable description of one server (a stdio command or an
  HTTP endpoint).
- `packages/apple/AgenticToolkit/Core/MCP/MCPServerRegistry.swift` — the
  registry that reconciles a set of live clients against the configurations
  and secrets the settings store reports, and exposes `tools(forIds:)` to
  callers assembling a tool list across servers.
- `packages/apple/AgenticToolkit/Core/MCP/MCPSettings.swift` — the settings
  declarations that route non-secret server descriptions to the regular
  settings provider and secret environment values to the secure (Keychain)
  provider.
- `packages/apple/AgenticToolkit/Core/MCP/SubprocessTransport.swift` — the
  subprocess transport, an implementation of MCP's own transport contract
  built on this codebase's shared subprocess-channel abstraction, used for
  every `.stdio` server instead of the MCP SDK's own stock stdio transport.
- `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` — a
  self-contained in-process MCP server that exposes host
  application info and a "open a chat window" tool over an in-memory
  transport pair, with no subprocess and no registry integration.

## Behavioral Requirements

The client's error and connection-state types

- **client-disconnected-error-message**: The client's "already disconnected" error MUST provide the human-readable description "The MCP server was disabled or removed before its connection finished starting; nothing was launched." — an error with no explicit description otherwise reads as an opaque, generic failure message in every logger and alert that consumes it.
- **client-state-shape**: The client's connection state MUST be one of exactly four values — disconnected, connecting, connected, failed (carrying a message) — and MUST support equality comparison and safe use across concurrent contexts.

The client protocol

- **client-protocol-surface**: Any implementation of the client protocol MUST serialize its own operations so concurrent calls resolve deterministically, and MUST expose `id` and `name` as immediately readable without waiting on that serialization, plus a readable connection state and cached tool list. It MUST support exactly four operations: connect, disconnect, refresh the tool list, and call a tool by name with arguments — returning the tool's content and an error flag.

The client

- **client-identity**: The client's `id` and `name` MUST be taken from the server configuration's own `id` and `name` at construction and MUST NOT change for the life of the instance.
- **client-initial-state**: A newly constructed client MUST report a disconnected state and an empty cached tool list before connecting is ever attempted.
- **connect-guard-is-first**: Connecting MUST check whether the client has already been shut down as its first action, before doing anything else, and MUST throw the "already disconnected" error without doing anything else when disconnecting has already completed on this instance.
- **connect-runs-in-held-task**: Connecting MUST mark itself connecting, then run the connection-establishment work as a separately tracked, cancellable operation rather than inline, so that a concurrent teardown has a specific operation to cancel and wait for.
- **connect-success-transition**: On success, connecting MUST stop tracking that operation only if it is still the one that just finished, and MUST advance the state to connected only if the state is still connecting at that point — a teardown that ran to completion while this connect was suspended MAY have already reset both, in which case connecting MUST return successfully anyway while the state reads disconnected and the client owns no transport.
- **connect-failure-transition**: On failure, connecting MUST stop tracking that operation under the same guard, MUST set the state to failed (carrying the error) only if the state is still connecting, MUST tear down before returning, and MUST rethrow the original error.
- **establish-connection-order**: Establishing a connection MUST, in order: check for cancellation, build the transport and store it, connect the underlying MCP client to that transport, register the tool-list-changed notification handler, then refresh the tool list.
- **disconnect-is-terminal**: Disconnecting MUST mark the client as permanently shut down before doing anything else, MUST never clear that mark, MUST tear down, and MUST leave the state disconnected afterward — a later attempt to connect the same instance MUST throw rather than starting a second server; reconnecting requires constructing a new client.
- **teardown-sequence**: Tearing down MUST perform, in this exact order: (1) cancel the tracked connect operation, if any; (2) disconnect the transport, if one exists; (3) disconnect the underlying MCP client; (4) if the connect operation is still tracked, wait for it to finish under a fixed wall-clock budget, discarding both its own error and a budget-exceeded error, then cancel it again and stop tracking it; (5) disconnect the transport again and release it; (6) disconnect the underlying MCP client again. Each of the two repeated calls MUST run even though the first of its pair may already have been a no-op, because the ordering that makes step 4's wait bounded is exactly the ordering steps 2 and 3 cannot reach.
- **abandoned-connect-budget-value**: The wall-clock budget teardown gives an in-flight connect operation MUST be `1.0` seconds, and it MUST NOT be configurable per instance.
- **teardown-error-suppression**: An error thrown by the awaited connect operation in step 4 of teardown-sequence, or a budget-exceeded error from the budget itself, MUST NOT propagate out of tearing down — both MUST be discarded.
- **transport-selection**: Building the transport MUST produce a subprocess transport for a `.stdio` configuration and an HTTP client transport for a `.http` configuration.
- **secrets-override-environment**: For a `.stdio` transport, the child's environment MUST be the configuration's own environment merged with the client's secrets, with a key present in both resolving to the secret's value.
- **stdio-transport-configuration**: The subprocess transport built for a `.stdio` server MUST configure its channel to merge the child's environment over the host process's own (so the child still inherits `PATH`/`HOME`) and to frame messages as newline-delimited.
- **tool-list-changed-refresh**: The client MUST register a handler for the tool-list-changed notification that refreshes the tool list whenever the server emits that notification.
- **refresh-tools-replaces-cache**: Refreshing the tool list MUST call the underlying MCP client's list-tools operation and MUST replace the cached tool list with the result in full (not merge or append).
- **call-tool-forwards-and-defaults-error-flag**: Calling a tool MUST forward the tool's name and arguments to the underlying MCP client's call-tool operation and MUST return its content plus an error flag — a missing error flag from the server MUST be treated as `false`.
- **client-serializes-operations**: The client MUST serialize every one of its operations onto a single execution context, so its connection state, cached tool list, tracked connect operation, shutdown flag, and transport are never touched concurrently and every external call resolves deterministically; only `id` and `name` are exempt from that serialization, since they never change after construction and are safe to read at any time.
- **connect-suspension-hook-is-nil-in-production**: The connect-suspension test hook MUST default to none and MUST be settable only through a method reserved for test code; with no hook installed, the two checkpoints inside establishing a connection MUST cost exactly one nil check each and MUST NOT suspend.

The server configuration

- **configuration-shape**: The server configuration MUST be persistable, safely shared across concurrent contexts, uniquely identifiable, and comparable for equality, and MUST expose an immutable `id`, a `name`, a `transport`, and an `isEnabled` flag.
- **configuration-transport-shape**: The configuration's transport MUST be one of exactly two shapes — a stdio launch (a command, its arguments, and environment variables) or an HTTP endpoint (a URL and whether it streams) — and MUST be persistable, safely shared across concurrent contexts, and comparable for equality.
- **configuration-default-id**: Constructing a server configuration MUST generate a fresh, unique `id` when the caller does not supply one, and MUST default `isEnabled` to `true`.
- **configuration-id-is-stable**: Changing `name`, `transport`, or `isEnabled` on a value with a given `id` MUST NOT change that value's `id`.
- **configuration-equality-covers-all-fields**: Two server configurations MUST compare equal only when `id`, `name`, `transport`, and `isEnabled` all match, and MUST compare unequal if any one field differs.
- **configuration-secrets-live-elsewhere**: The server configuration MUST carry no secret material of its own — secret environment values for a server MUST be looked up separately, keyed by the configuration's own `id`, from the server-secrets setting.

The settings

- **server-secrets-shape**: The server-secrets setting MUST map a server's `id` to that server's own environment-variable overrides, keyed by variable name.
- **configurations-setting-routing**: The list of server configurations MUST be declared with key `"mcp.serverConfigurations"`, default to an empty list, and MUST NOT be marked as secure, so it routes to the regular (non-secure) settings storage provider.
- **secrets-setting-routing**: The server-secrets setting MUST be declared with key `"mcp.serverSecrets"`, default to empty, and MUST be marked secure, so it routes to the secure storage provider (Keychain in production) and never reaches the regular settings file.

The registry

- **registry-publishes-clients-on-main-thread**: The registry MUST run on the main thread of execution and MUST publish its live map of clients (keyed by server id) reactively, so observers see every add and remove.
- **registry-clients-mirror-enabled-configurations-only**: The live client map MUST contain an entry only for a configuration whose `isEnabled` is `true`; a disabled or absent configuration's `id` MUST NOT appear as a key.
- **registry-subscribes-to-settings-changes**: Constructing the registry MUST observe both the server-configurations setting and the server-secrets setting together, and MUST reconcile the live client set against the latest values on every change to either one.
- **registry-reconcile-removes-first**: Reconciling MUST, for every `id` currently tracked that is not in the newly enabled set, remove that `id` from the live map immediately and begin disconnecting that client independently, without waiting for the disconnect to finish before reconciling itself returns.
- **registry-reconcile-adds-missing**: For every enabled configuration whose `id` is not already tracked, reconciling MUST look up that server's secrets (or none, if absent), create a client for it, store it in the live map under that `id`, and begin connecting it independently, without waiting for the connection to finish before reconciling itself returns.
- **registry-connect-failure-is-logged-not-thrown**: If the connection attempt started in registry-reconcile-adds-missing fails, reconciling MUST catch the error and log it, interpolating the configuration's `name` and the error's description as public log data, and MUST NOT remove the client from the live map or rethrow.
- **registry-default-client-factory**: The client factory MUST default to constructing a real client from a server configuration and its secrets; a caller (test or otherwise) MAY substitute a different factory when constructing the registry.
- **registry-tools-for-ids**: `tools(forIds:)` MUST, for each `id` in the given set, skip any `id` with no entry in the live map, and otherwise await that client's cached tool list and append one (client, tool) pair per cached tool; the result MUST include every cached tool from every matching client and MUST NOT include tools from a client whose `id` is absent from `ids`.

The subprocess transport

- **subprocess-transport-conforms-to-mcp-transport**: The subprocess transport MUST serialize its own operations and MUST conform to MCP's own Transport contract, built over this codebase's shared subprocess-channel abstraction rather than the MCP SDK's own stdio transport.
- **subprocess-transport-default-logger-is-noop**: The subprocess transport MUST default its logger to a no-op logger when the caller supplies none, matching the stock stdio transport's own default, so every JSON-RPC frame of every MCP server is not logged by default.
- **subprocess-transport-three-state**: The subprocess transport MUST track its lifecycle as one of exactly three states — idle, connecting, connected — rather than a simple on/off flag, because there is a window after launching the channel and before connecting resumes in which a live child exists that only terminating can reap.
- **subprocess-connect-is-idempotent**: Connecting MUST be a no-op when called while the state is already connecting or connected; a second, concurrent call MUST return immediately without waiting for the first call and MUST NOT spawn a second child process.
- **subprocess-connect-order**: A connect that proceeds MUST mark itself connecting before doing anything else, then launch the channel; on failure it MUST reset to idle and rethrow without spawning a forwarding operation. On success it MUST re-check that it is still connecting (returning early otherwise) before opening the channel's message stream, and MUST re-check that it is still connecting a second time (returning early otherwise) before marking itself connected and starting the forwarding operation — both re-checks exist because a disconnect may land in either suspension.
- **subprocess-blank-line-filtering**: The forwarding operation MUST discard any frame for which every byte is one of LF (`0x0A`), CR (`0x0D`), space (`0x20`), or tab (`0x09`) — including an empty frame — and MUST NOT yield it into the message stream; every other frame MUST be yielded unmodified, with its trailing delimiter byte intact.
- **subprocess-disconnect-is-idempotent**: Disconnecting MUST be a no-op when already idle; otherwise it MUST mark itself idle, terminate the channel, wait for the forwarding operation's completion, stop tracking that operation, and unconditionally close the message stream once more as a safety net.
- **subprocess-send-requires-connected-state**: Sending MUST throw a "not connected" transport error when the state is not connected — sending before connecting or after disconnecting MUST fail with that specific error, matching the stock stdio transport's contract byte for byte — and otherwise MUST forward the framed data to the channel.
- **subprocess-receive-returns-stable-stream**: Receiving events MUST return the same underlying stream instance on every call, not a new stream per call.

The host MCP server

- **host-server-runs-on-main-thread**: The host MCP server MUST run on the main thread of execution.
- **host-server-wires-in-memory-pair**: Constructing the host MCP server MUST create a connected in-memory transport pair, expose the client side publicly, and retain the server side privately.
- **host-server-declares-no-list-changed**: The underlying MCP server MUST declare that it does not support the tools-list-changed capability — this server MUST NOT claim it will emit `tools/list_changed`.
- **host-server-start-and-stop**: Starting MUST register the tool handlers and then start the underlying MCP server against its own transport; stopping MUST stop that server.
- **host-server-lists-two-tools**: Listing tools MUST return exactly two tools, `host_app_info` and `host_open_chat_window`, each declaring an object input schema with no properties.
- **host-app-info-tool-body**: Calling `host_app_info` MUST return non-error text containing the app's name, its version, and its plugin names joined by `", "`, or the literal `(none)` when there are no plugin names.
- **host-open-chat-window-tool-effect**: Calling `host_open_chat_window` MUST invoke the callback supplied when the host MCP server was constructed and MUST return the fixed non-error text "Opened a new chat window."
- **host-server-unknown-tool-is-not-an-error-throw**: Calling any tool name other than the two declared tools MUST return a result with an error flag set and text "Unknown tool: <name>" — it MUST NOT throw.
- **host-server-ignores-tool-arguments**: Neither tool handler MUST read the call's arguments — both declared input schemas have no properties and no handler inspects the arguments given, so any arguments a caller supplies are accepted and ignored.

## Appearance

Not applicable — this is a Model Context Protocol connection and reconciliation layer, not a visual component.

## States

Not applicable — this is a Model Context Protocol connection and reconciliation layer, not a visual component; its runtime state machines (the client's connection state, and the subprocess transport's idle/connecting/connected states) are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a Model Context Protocol connection and reconciliation layer with no user interface of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| mcp-plumbing-001 | registry-clients-mirror-enabled-configurations-only | A freshly constructed registry with no configurations set | The registry's live client map is empty (`MCPServerRegistryTests.testStartsEmpty`) |
| mcp-plumbing-002 | registry-reconcile-adds-missing | An enabled server configuration is stored in the server-configurations setting | The registry's live client map has exactly one entry, a client exists for that configuration's id, and the test factory's connect-call count reaches `1` (`MCPServerRegistryTests.testCreatesClientForEnabledConfiguration`) |
| mcp-plumbing-003 | registry-clients-mirror-enabled-configurations-only | A disabled server configuration is stored in the server-configurations setting | The registry's live client map is empty (`MCPServerRegistryTests.testIgnoresDisabledConfiguration`) |
| mcp-plumbing-004 | registry-reconcile-removes-first | An enabled configuration is stored, then re-stored with its enabled flag turned off | The registry's live client map is empty and the test factory's disconnect-call count reaches `1` (`MCPServerRegistryTests.testDisablingConfigurationRemovesClient`) |
| mcp-plumbing-005 | registry-reconcile-removes-first | An enabled configuration is stored, then the server-configurations setting is cleared | The registry's live client map is empty and the removed client is eventually disconnected (`MCPServerRegistryTests.testRemovingConfigurationDisconnectsClient`) |
| mcp-plumbing-006 | registry-reconcile-adds-missing | A secret environment value is stored under a server's id in the server-secrets setting, before that server's configuration is stored | The test factory receives that same secret value when it constructs the client (`MCPServerRegistryTests.testPassesSecretsToFactory`) |
| mcp-plumbing-007 | registry-tools-for-ids | Two enabled configurations, A and B, each client given one cached tool (`tool_a`, `tool_b`) | `tools(forIds: [A.id, B.id])` yields both names; `tools(forIds: [A.id])` yields only `tool_a` (`MCPServerRegistryTests.testToolsCollectsFromMatchingClients`) |
| mcp-plumbing-008 | configurations-setting-routing, secrets-setting-routing | Server configurations are stored in the server-configurations setting; secrets are stored in the server-secrets setting | The regular settings provider holds the server-configurations key and the secure provider does not; conversely the secure provider holds the server-secrets key and the regular provider does not (`MCPSettingsTests.testConfigurationsRouteToRegularProvider`, `testSecretsRouteToSecureProvider`) |
| mcp-plumbing-009 | configuration-transport-shape, configuration-equality-covers-all-fields | A stdio and an HTTP server configuration are each round-tripped through encoding and decoding | The decoded value equals the original for both transport kinds (`MCPServerConfigurationTests.testStdioRoundTrip`, `testHttpRoundTrip`) |
| mcp-plumbing-010 | configuration-id-is-stable | A configuration's name and enabled flag are changed after construction | `id` is unchanged (`MCPServerConfigurationTests.testIdentifiableUsesStableId`) |
| mcp-plumbing-011 | connect-guard-is-first | Disconnect is called on a freshly constructed client, then connect is called | Connect throws the client's "already disconnected" error, no server process is ever spawned, and the state remains disconnected (`MCPClientRaceTests.connectAfterDisconnectThrows`) |
| mcp-plumbing-012 | teardown-sequence | Connect is started, without waiting for it, against a child that never answers the MCP initialize handshake, then disconnect is called after the spawn is observed | No matching process survives once disconnect returns (`MCPClientRaceTests.parkedConnectIsStillReapedByDisconnect`) |
| mcp-plumbing-013 | connect-success-transition, teardown-sequence | Connect is started without waiting for it and immediately raced with disconnect, repeated 20 times with fresh clients | No probe process survives across all 20 iterations (`MCPClientRaceTests.disconnectRacingConnectStopsTheChild`) |
| mcp-plumbing-014 | abandoned-connect-budget-value, teardown-error-suppression | A connect is suspended (via the test seam) exactly between publishing the transport and connecting the underlying MCP client to it, then disconnect is called | Disconnect returns within its budget (well under 8s) and no probe process survives (`MCPClientRaceTests.teardownAbandonsAWedgedConnectAndStillReapsTheChild`) |
| mcp-plumbing-015 | teardown-sequence | Same wedged-connect setup as mcp-plumbing-014, with CPU consumption measured for 1 second after disconnect returns | Measured CPU consumption stays under the test's `0.25` CPU-second ceiling, and the abandoned connect operation itself completes (`MCPClientRaceTests.teardownFreesTheAbandonedConnectRatherThanSpinning`) |
| mcp-plumbing-016 | client-serializes-operations, connect-suspension-hook-is-nil-in-production | A connect is suspended (via the test seam) before its cancellation check, then raced with disconnect | The connect operation ends as cancelled (not a spawn), disconnect returns, and no probe process survives (`MCPClientRaceTests.connectCancelledBeforeItBuildsATransportNeverSpawns`) |
| mcp-plumbing-017 | subprocess-blank-line-filtering | A raw frame consisting of the two bytes `0x0D 0x0A` (a CRLF blank line) is produced by the child | The subprocess transport's blank-line check reports true for that frame, and the frame is never yielded into the message stream |
| mcp-plumbing-018 | subprocess-send-requires-connected-state | Sending is attempted on a subprocess transport whose state is idle | The call throws the "not connected" transport error without touching the underlying channel |
| mcp-plumbing-019 | host-app-info-tool-body | The host MCP server, constructed with app name "Demo", version "2.0", and no plugin names, receives a call to `host_app_info` | Returned text reads `Host: Demo\nVersion: 2.0\nPlugins: (none)`, with the error flag false |
| mcp-plumbing-020 | host-server-unknown-tool-is-not-an-error-throw | A tool call is invoked with the tool name `nonexistent_tool` | Returned result has the error flag true and text `Unknown tool: nonexistent_tool`; no error is thrown |

## Edge Cases

- **Null/empty input**: The server configuration's stdio transport with no environment variables MUST leave secrets-override-environment's merge as exactly the secrets (MUST). The host MCP server with no plugin names MUST render the plugin list as the literal `(none)` (MUST). The registry's reconcile step with no secrets recorded for a server MUST treat that server's secrets as empty, not fail (MUST). `tools(forIds: [])` MUST return an empty list (MUST).
- **Boundary values**: The abandoned-connect wall-clock budget is fixed at `1.0` seconds; teardown's step-4 wait MUST NOT exceed that bound regardless of how long the abandoned connect would otherwise take (MUST). The subprocess transport's blank-line check applied to a zero-length frame MUST return true (an empty collection trivially satisfies the check), so an empty frame MUST be filtered exactly as a whitespace-only one is (MUST).
- **Concurrent access**: The client serializes its own connect, disconnect, tool-list-refresh, and call-tool operations onto one execution context; a connect racing a disconnect on the same instance MUST resolve deterministically per teardown-sequence and connect-guard-is-first, never stranding a child process (MUST). The registry's reconcile step begins each client's connect or disconnect independently and does not wait for any of them to finish before reconciling itself returns, so multiple servers' connections and teardowns proceed concurrently and independently of one another (MUST, per registry-reconcile-removes-first and registry-reconcile-adds-missing). A second, concurrent connect call on the subprocess transport while the first is still connecting MUST return immediately without spawning a second child (MUST, per subprocess-connect-is-idempotent).
- **Error states**: A `.stdio` command that cannot be launched surfaces as a thrown error out of launching the channel, which the subprocess transport's connect propagates after resetting its own state to idle, and which the client's connect propagates after marking its state failed (carrying the error) and running teardown (MUST). A connect failure raised inside the registry's independent connect attempt is caught and logged, and the client remains present in the live map with its own state set to failed; reconciling itself never throws or crashes on a connect failure (MUST, per registry-connect-failure-is-logged-not-thrown). Sending on a subprocess transport that is not connected throws the "not connected" transport error rather than whatever the underlying channel would otherwise raise (MUST).
- **Offline/disconnected state**: Disconnecting a subprocess transport that was never connected (still idle) MUST be a no-op — the channel MUST NOT be terminated (MUST, per subprocess-disconnect-is-idempotent). A connect that spawns a child which never answers the MCP initialize handshake (an unresponsive or hung server) is not freed by cancellation alone — cancelling the tracked connect operation cannot unwedge it once it is waiting with no cancellation path of its own — and is only unwedged by a subsequent disconnect's teardown, per abandoned-connect-budget-value and teardown-error-suppression (MUST).
- **Cancellation**: Cancelling a caller's own wrapper around the client's connect before that work reaches its own checkpoints does not, by itself, stop establishing the connection — cancellation is only observed at establish-connection-order's cancellation check, and once a transport has been built and the underlying MCP client has been connected to it, cancellation alone cannot recover the child; only teardown's two transport-disconnect calls and two client-disconnect calls reliably reap it (MUST, per teardown-sequence).
- **tool-list-refresh-failure**: NEEDS REVIEW: Not implemented in source. The tool-list-changed handler discards any error from refreshing the tool list; if refreshing throws when the server emits `tools/list_changed`, the error is discarded with no log entry, no state transition, and no retry, so the cached tool list simply remains whatever it was before the notification. Settling whether that silence is acceptable, or whether a failed refresh should log or mark the state failed, needs a decision from whoever owns the client's error-reporting contract.
- **HTTP transport abandoned connect**: Tearing down runs the same teardown-sequence for an HTTP server as for a stdio one, including the repeated underlying-client disconnect. That repeat is documented and measured only against the subprocess transport's receive returning its finished stream and spinning the underlying MCP client's message loop; how the HTTP transport behaves after an abandoned connect is owned by the MCP SDK package, outside these six sources.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configuration` (parameter to constructing a client) | `MCPServerConfiguration` | none — required | The server this client connects to: its transport, name, and id. |
| `secrets` (parameter to constructing a client) | `[String: String]` | `[:]` | Secret environment values merged over the configuration's own environment for a `.stdio` server, per secrets-override-environment. |
| `clientName` (parameter to constructing a client) | `String` | `"AgenticToolkit"` | The name this client presents to the MCP server during initialization. |
| `clientVersion` (parameter to constructing a client) | `String` | `"1.0.0"` | The version this client presents to the MCP server during initialization. |
| `store` (parameter to constructing the registry) | `SettingsStore` | none — required | Source of the server-configurations and server-secrets settings the registry reconciles against. |
| `clientFactory` (parameter to constructing the registry) | `ClientFactory` (`@MainActor (MCPServerConfiguration, [String: String]) -> any MCPClientProtocol`) | Constructs a real client from a server configuration and its secrets | Lets a caller substitute a test double; production code accepts the default. |
| `mcp.serverConfigurations` (settings key) | `[MCPServerConfiguration]` | `[]` | Non-secret server descriptions, routed to the regular settings provider. |
| `mcp.serverSecrets` (settings key) | `MCPServerSecrets` (`[String: [String: String]]`) | `[:]` | Secret environment values keyed by server id, routed to the secure (Keychain) settings provider. |
| `logger` (parameter to constructing the subprocess transport) | `Logger?` | `nil` (a no-op logger) | Diagnostic logger for the transport's own debug messages; production code does not supply one. |
| `appName`, `appVersion` (parameters to constructing the host MCP server) | `String` | none — required | Reported by the `host_app_info` tool. |
| `pluginNames` (parameter to constructing the host MCP server) | `[String]` | `[]` | Reported by the `host_app_info` tool, joined by `", "` or rendered as `(none)` when empty. |
| `openChatWindow` (parameter to constructing the host MCP server) | `@Sendable () -> Void` | a no-op callback | Invoked when the `host_open_chat_window` tool is called. |
| `abandonedConnectBudgetSeconds` (a fixed constant owned by the client) | `TimeInterval` | `1.0` | Fixed wall-clock bound teardown gives an in-flight connect before abandoning it; not exposed to callers. |

## Deep Linking

Not applicable: none of the six sources define a URL scheme, route, or navigation destination — the server configuration's HTTP transport addresses an MCP server's HTTP endpoint, not an app deep link.

## Localization

The client's errors and the registry's log messages are hardcoded, unlocalized English strings with no string-catalog key, and the host MCP server's tool descriptions and tool-call bodies are likewise hardcoded English:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The MCP server was disabled or removed before its connection finished starting; nothing was launched." | The client's "already disconnected" error description |
| (none — literal, no catalog key) | "Failed to connect MCP server %@: %@" (interpolated with the configuration's name and the error's description) | The registry's reconcile failure log line |
| (none — literal, no catalog key) | "Return the host application's name, version, and configured AI plugins." | `host_app_info`'s tool description |
| (none — literal, no catalog key) | "Open a new AI chat window in the host application." | `host_open_chat_window`'s tool description |
| (none — literal, no catalog key) | "Host: %@\nVersion: %@\nPlugins: %@" | `host_app_info`'s success body |
| (none — literal, no catalog key) | "Opened a new chat window." | `host_open_chat_window`'s success body |
| (none — literal, no catalog key) | "Unknown tool: %@" | The unrecognized-tool-name default case body |

## Accessibility Options

Not applicable: none of the six sources render UI, so none observes Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the six sources reads a feature-flag or settings key beyond the two settings (`mcp.serverConfigurations`, `mcp.serverSecrets`) already documented under Configuration, neither of which gates a feature on or off.

## Analytics

Not applicable: none of the six sources contains an analytics or event-tracking call.

## Privacy

- **Data handled**: The server configuration's stdio environment and the server-secrets setting's per-server secret map MAY each carry credentials (e.g. `"GITHUB_TOKEN"`) that a user supplies when configuring a server; the client forwards the merged environment to the spawned subprocess (secrets-override-environment) or, for an HTTP server, whatever the configuration's endpoint and the underlying HTTP transport send, with no inspection of its own beyond the merge itself.
- **Storage**: Non-secret server descriptions are stored under `"mcp.serverConfigurations"` in the regular settings provider; secret environment values are stored under `"mcp.serverSecrets"`, routed to the secure provider (Keychain in production) and marked secure, per secrets-setting-routing — secrets MUST NOT reach the regular settings file.
- **Transmission**: For a `.stdio` server, secrets are transmitted only as environment variables to a locally spawned child process, never over the network by this component itself; for a `.http` server, whatever headers or body the underlying HTTP transport sends travel to the configured endpoint over HTTPS or HTTP as that URL specifies. The registry's failure log (registry-connect-failure-is-logged-not-thrown) interpolates only the configuration's name and the error's description, never a secret or environment value.
- **Retention**: Secrets persist in the secure provider until the user edits or removes the corresponding server configuration; the source defines no expiry, rotation, or automatic revocation for a stored secret.
- **Token lifecycle**: the component implements no expiry, rotation, or revocation for a stored server secret; a secret stays valid in the secure provider until the user edits or removes the server configuration.

## Logging

Subsystem: `com.mikefullerton.agentictoolkit` | Category: client, registry

| Event | Level | Message |
|-------|-------|---------|
| A client's connect throws during the registry's reconcile step | error | "Failed to connect MCP server \(configuration.name): \(error.localizedDescription)" |
| The subprocess transport's connect completes its forwarding setup | debug | "Transport connected successfully" |
| The subprocess transport's disconnect finishes | debug | "Transport disconnected" |

The client itself has its own logger, but the given source contains no call site that emits through it directly — the capability exists without an observed emission in `MCPClient.swift`.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/MCP/*.swift` (built into the `AgenticToolkitCore` framework target, macOS-only) and `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` (built into the `AgenticToolkitMacOS` target). `MCPServerRegistry`'s `@Published clients` and `MCPClient`'s `state`/`cachedTools` are consumed reactively by SwiftUI views (e.g. the sibling `MCPChipsBarView` recipe) via `ObservableObject`, but nothing in these six files imports `SwiftUI` itself — the layer is UI-framework-agnostic.
- **Compose**: Model `MCPClient` as a class wrapping a `Mutex`-guarded `MutableStateFlow<MCPClientState>` and `MutableStateFlow<List<Tool>>` in place of the actor's isolated `state`/`cachedTools`, with `connect`/`disconnect`/`refreshTools`/`callTool` as `suspend` functions; reproduce `teardown-sequence`'s ordering with `withTimeoutOrNull(1_000L) { connectJob?.join() }` in place of the wall-clock budget, and `connectJob?.cancel()` in place of `connectTask?.cancel()`. Model `MCPServerRegistry` as a class exposing `StateFlow<Map<UUID, MCPClientProtocol>>`, driven by `combine` over two settings `Flow`s in place of Combine's `combineLatest`. Model `SubprocessTransport` with `ProcessBuilder`, reading stdout line-by-line on a background dispatcher to reproduce `.newlineDelimited` framing, and filtering blank lines the same way `subprocess-blank-line-filtering` does. Route secrets through Android's `EncryptedSharedPreferences` in place of Keychain.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive and no OS keychain), model `MCPClient` as an `EventEmitter`-based class or an async class exposing `state`/`cachedTools` getters, with `connect`/`disconnect` as `async` methods; reproduce `teardown-sequence`'s bounded wait with `Promise.race([connectPromise, delay(1000)])` in place of the wall-clock budget. Model `MCPServerRegistry` as a class holding a `Map<string, MCPClientProtocol>` and re-running its reconcile logic on every settings-store change event. Model `SubprocessTransport` with `child_process.spawn`, reading `.stdout` through `readline.createInterface` (or manual `\n`-splitting) for `.newlineDelimited` framing, and filtering blank lines per `subprocess-blank-line-filtering`; route secrets through an OS-keychain wrapper (e.g. `keytar`) in place of Keychain, and support only the `.http` transport in an Electron renderer sandbox that cannot spawn arbitrary executables.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AgenticToolkitCore`/`AgenticToolkitMacOS` differs, never this contract.
- **WinUI 3**: Model the `.http` path of `MCPClient`/`SubprocessTransport` with `System.Net.Http.HttpClient`, and the `.stdio` path with `System.Diagnostics.Process`/`ProcessStartInfo` (`RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` all `true`), reading stdout via a `StreamReader.ReadLineAsync()` loop to reproduce `.newlineDelimited` framing and `subprocess-blank-line-filtering`'s blank-line skip. Reproduce `teardown-sequence`'s bounded wait for an abandoned connect with a `CancellationTokenSource` whose `CancelAfter(TimeSpan.FromSeconds(1))` gates a `Task.WhenAny(connectTask, Task.Delay(Timeout.Infinite, token))`, in place of `withWallClockBudget`. Represent `MCPServerRegistry.clients` as an `ObservableCollection<KeyValuePair<Guid, IMcpClient>>` or a `Dictionary` behind a type implementing `INotifyPropertyChanged`/`INotifyCollectionChanged`, raised from the `reconcile` equivalent the same way `@Published` raises `objectWillChange`. Store `mcp.serverConfigurations` via `Windows.Storage.ApplicationData.LocalSettings` (serialized with `System.Text.Json`) and route `mcp.serverSecrets` through `Windows.Security.Credentials.PasswordVault` in place of Keychain, since `Windows.Storage`'s settings containers are not encrypted at rest the way `mcp.serverSecrets` requires.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/MCP/MCPClient.swift` |
| apple | `packages/apple/AgenticToolkit/Core/MCP/MCPServerConfiguration.swift` |
| apple | `packages/apple/AgenticToolkit/Core/MCP/MCPServerRegistry.swift` |
| apple | `packages/apple/AgenticToolkit/Core/MCP/MCPSettings.swift` |
| apple | `packages/apple/AgenticToolkit/Core/MCP/SubprocessTransport.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` |

## Design Decisions

All four decisions below are specific to the Apple/Swift reference implementation; see Platform Notes for how another platform would reproduce the same guarantees.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/mcp/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
