<!-- leaf: implement-status-server/mcp--edge-cases · source: status-server-mcp.md -->

# Status Server MCP

## Edge Cases

- **Null and empty input**: a `target` argument to `get_issue` that matches
  no open problem resolves `null`, not an error (`get-issue-filters-by-target`).
  A `slug` argument to `query_history` that names no active endpoint
  resolves normally with no matching samples, not an error
  (`query-history-clamps-hours`) — neither tool validates the referenced
  resource exists before reading.
- **Boundary values**: `get_uptime`'s `days` and `query_history`'s `hours`
  are clamped via `clampInt` (`Math.min(Math.max(Math.trunc(v), lo), hi)`)
  to 1–365 and 1–168 respectively; a caller-supplied `0`, a negative
  number, or a value above the ceiling is silently clamped into range
  rather than rejected. Both are optional zod `z.number().int()` fields, so
  a non-integer or non-finite value fails the schema's own parse before
  `clampInt` ever runs — `clampInt` itself only ever receives a value zod
  has already confirmed is a finite integer or the tool's own numeric
  default.
- **Concurrent access**: because `mcp-per-request-server` builds a fresh
  `McpServer`/`StreamableHTTPServerTransport` pair for every HTTP request
  and `mcp-stateless-transport` mints no session id, no MCP-layer state is
  shared across concurrent requests — two overlapping `/mcp` calls register
  and execute their tools entirely independently at this layer. Any
  ordering or last-writer-wins outcome for two concurrent write-tool calls
  targeting the same row is the underlying `Storage` implementation's
  contract, external to these three files.
- **Concurrent access — duplicate writes**: two concurrent `add_peer` calls
  for the same `baseUrl` are resolved by `add-peer-duplicate-mapping` — the
  loser's constraint violation is caught and mapped to
  `DUPLICATE_PEER_MESSAGE`. `create_group`/`create_site`/`create_platform`
  have no equivalent duplicate-slug mapping; a concurrent duplicate-slug
  write surfaces whatever error the store's constraint violation raises,
  through the ordinary `mcp-execute-errors-caught` path (`execution_error`
  with the store's own message), not a friendly mapped sentence — a real
  asymmetry with `add_peer` in the source, recorded here as fact.
- **Error states — thrown execute()**: every `Error` thrown by a tool's
  `execute` (a "not found" guard, `add_peer`'s self/duplicate guards,
  `update_user`'s role guards) is caught by `mcp-execute-errors-caught` and
  converted to an `isError` envelope with `code: 'execution_error'`; none
  propagates to the transport as an uncaught exception.
- **Error states — malformed JSON body**: a `POST /mcp` whose body is
  present but fails to parse as JSON is caught by
  `mcp-body-preparsed-passthrough`'s `.catch(() => undefined)` and passed
  to `transport.handleRequest` as `undefined` — the identical value a
  bodyless `GET`/`DELETE` request produces. These three files cannot
  distinguish "malformed JSON" from "no body sent" at this point; the
  resulting JSON-RPC-level response for that `undefined` body is
  `StreamableHTTPServerTransport.handleRequest`'s behavior, external to
  these three files.
- **Error states — unregistered or unauthorized tool name**: calling a
  tool name the caller's tier never had registered (a write, or an
  admin-only read, under `'view'`) resolves an `isError` result from the
  MCP SDK's own "tool not found" handling — external to these three files,
  which never see the call at all (layer 1). Calling a registered tool the
  handler's own re-check rejects resolves the `forbidden_tier` envelope
  instead (layer 2) — the two failure shapes are distinguishable by
  `code`/error text, not conflated.
- **Offline / disconnected state**: these three files implement the server
  side of the connection; they have no client-side connectivity to lose.
  The nearest analogue — an MCP client's connection dropping mid-request,
  or one of `run_auto_configure`/`configure_telemetry`'s outbound provider
  calls (Vercel/Railway/GlitchTip/PostHog) becoming unreachable — is
  handled by the transport layer and by `performAutoConfigure`/`collectTelemetry`
  themselves, both external to these three files; neither of these three
  files implements its own retry or reconnection logic.
