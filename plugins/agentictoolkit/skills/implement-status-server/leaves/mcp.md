<!-- leaf: implement-status-server/mcp · source: status-server-mcp.md -->

# Status Server MCP

## Overview

This is the status backend's MCP (Model Context Protocol) tool surface:
three files under `src/mcp/` that expose the same monitoring/config data and
mutations the REST API exposes, as 32 callable tools an AI agent client can
invoke over Streamable HTTP. `route.ts` mounts the stateless `/mcp` transport
(`mountMcp`) behind the app-wide auth seam, with DNS-rebinding host
allowlisting. `server.ts` builds a per-request `McpServer` (`buildMcpServer`)
and registers each tool with a handler that re-checks authorization before
running (`registerTool`). `tools.ts` is the tool catalog itself: 18 read
tools and 14 write tools, each a thin wrapper that calls the exact same
store or service function its REST twin calls — never re-implementing that
logic and never making an HTTP hop — plus the two-axis access-control model
(`readOnly` for the tool's nature, `isAdminTool`/`adminOnly` for who may call
it) and `selectTools(tier)`, which resolves that model into the tool set a
given caller's tier may use.

The Hono app, the `requireAuth` middleware that resolves `c.get('tier')`
before `mountMcp`'s handler runs, and every store/service function a tool
delegates to (`buildSnapshot`, `boardProblems`, `buildUptime`, `queryHistory`,
`performAutoConfigure`, `refreshAndEnumerateDeployProjects`, the `Storage`
port's `config`/`auth`/`telemetry` namespaces, `reconcileBoardLedger`,
`collectTelemetry`, `assembleFleet`, `siteLinks`, `redactPeer`,
`isSelfPeerUrl`/`isDuplicatePeerError`) are external to these three files;
this recipe documents what each tool passes to and returns from them, never
their internals.

