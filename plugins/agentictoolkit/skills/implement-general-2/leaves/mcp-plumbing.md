<!-- leaf: implement-general-2/mcp-plumbing · source: mcp-plumbing.md -->

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

