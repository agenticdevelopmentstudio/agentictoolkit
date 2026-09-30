<!-- leaf: implement-general-2/mcp-plumbing--logging · source: mcp-plumbing.md -->

# MCP Plumbing

## Logging

Subsystem: `com.mikefullerton.agentictoolkit` | Category: `MCPClient`, `MCPServerRegistry`

| Event | Level | Message |
|-------|-------|---------|
| A client's `connect()` throws during `MCPServerRegistry.reconcile` | error | "Failed to connect MCP server \(configuration.name): \(error.localizedDescription)" |
| `SubprocessTransport.connect()` completes its pump setup | debug | "Transport connected successfully" |
| `SubprocessTransport.disconnect()` finishes | debug | "Transport disconnected" |

`MCPClient` itself conforms to `Loggable` and exposes a `nonisolated static let logger`, but the given source contains no call site that emits through it directly — the capability exists without an observed emission in `MCPClient.swift`.
