<!-- leaf: implement-status-server/mcp--part-4 · source: status-server-mcp.md -->

# Status Server MCP — continued (part 4)

## Platform Notes

- **React/Web** (source platform): the three files live under
  `packages/web/packages/status-server/src/mcp/`, on top of
  `@modelcontextprotocol/sdk` (`McpServer`, `StreamableHTTPServerTransport`),
  Hono (`OpenAPIHono`, `HttpBindings`), `@hono/node-server`'s
  `RESPONSE_ALREADY_SENT` response-passthrough utility, and `zod` for every
  tool's `inputSchema`/parse pair. The `Storage` port and the
  `buildSnapshot`/`boardProblems`/etc. read-service functions these tools
  delegate to live in sibling directories and are not part of this
  recipe's sources.
- **SwiftUI / AppKit / UIKit**: an Apple client of this backend is a
  consumer, not a re-implementer, of this MCP surface — an MCP-capable
  agent host (not this product's own UI layer) would speak Streamable HTTP
  to `/mcp` via an MCP client SDK, attaching the same session cookie or
  `sts_` bearer `status-server-auth` documents. A future Apple-side
  re-implementation of this SERVER logic (a companion Swift backend, e.g.
  Vapor or Hummingbird) would model each `McpTool` as a Swift `struct`
  conforming to a small protocol (`name`, `description`, `readOnly`,
  `adminOnly`, and an `execute(_:_:_:) async throws -> Any`), with the
  tool catalog built once at startup and `selectTools(tier:)` filtering it
  per request exactly as `tools.ts` does.
- **Compose**: same client relationship as SwiftUI/AppKit/UIKit — an
  Android agent host would speak the same Streamable-HTTP protocol
  (OkHttp/Retrofit for the transport); it has no server-side tool surface
  to port.
- **WinUI 3**: a WinUI 3 desktop app is likewise a client, not a
  reimplementer. If a future product needed to reimplement this MCP
  tool-surface pattern on a .NET backend (ASP.NET Core Minimal API), the
  mapping is concrete: the `ModelContextProtocol` NuGet package's
  `McpServerTool`-attributed methods (or its builder API) replace the
  `McpTool` array and `registerTool` loop; each tool's zod `inputSchema`
  maps to a `System.Text.Json`-serializable request record validated with
  `FluentValidation` or `DataAnnotations` in place of `.parse()`; the
  two-layer fail-closed gate maps to an ASP.NET Core authorization filter
  reading a `Tier` claim off `HttpContext.User` for layer 1 (tool
  registration/`Endpoint` filtering per tier) and an explicit
  `if (tier != Tier.Admin) return Forbid(...)` re-check inside each
  admin-gated tool's handler body for layer 2, mirroring
  `mcp-registers-tier-set-only`/`mcp-handler-recheck` exactly; the
  success/failure JSON envelope (`ok`/`fail`) is a small `record` type
  serialized the same way for every tool response.

## Design Decisions

- **Decision**: keep `readOnly` (the tool's nature, driving MCP safety
  annotations) and `adminOnly`/`isAdminTool` (who may call it) as two
  independent fields rather than one combined flag.
  **Rationale**: `tools.ts`'s own header comment states this directly —
  conflating the two is what let an earlier version of this surface widen
  access, because a tool's annotation-facing "this is just a read" nature
  was mistaken for "any tier may call it," when several reads have an
  admin-only REST twin and must stay admin-gated regardless of their
  read-only nature.
  **Approved**: pending
- **Decision**: enforce authorization at two independent layers
  (registration-time filtering via `selectTools`, and a per-handler
  re-check via `isAdminTool` inside every registered tool's callback)
  rather than trusting registration filtering alone.
  **Rationale**: stated directly in `server.ts`'s doc comment — the
  re-check guards against a `selectTools` defect that mis-registers an
  admin-gated tool for `'view'`; defense in depth rather than a single
  point of failure for the entire write/admin-read surface.
  **Approved**: pending
- **Decision**: have `list_platform_projects`/`find_unconfigured_sites`
  re-verify the live platform project list on every call rather than
  trusting the DB mirror the REST routes may have already cached.
  **Rationale**: `mcp-deploy-tools.int.test.ts`'s header comment states
  this directly — before this fix, an agent could act on a project the
  platform had already deleted, including re-creating a site the operator
  had just removed; the fix accepts an uncached round-trip on every call
  because "a tool call is rare and always deliberate" (per `tools.ts`'s
  own comment), unlike the REST route's higher-frequency traffic.
  **Approved**: pending
- **Decision**: derive `get_issue` from `boardProblems` (the same function
  `GET /board` calls) rather than reading the ledger table
  (`openByTarget`) directly.
  **Rationale**: the Task-14 regression fix, documented in
  `board-route.test.ts`'s header comment — a stale ledger row for a target
  the board no longer derives (for example, a long-deleted site) used to
  answer non-null forever; deriving from the same function the board uses
  guarantees `get_issue` can never drift from what `get_problems`/`GET
  /board` consider open.
  **Approved**: pending
- **Decision**: construct a fresh `McpServer`/transport per HTTP request
  with `sessionIdGenerator: undefined`, rather than a long-lived server
  with stateful MCP sessions.
  **Rationale**: not stated in source as a tradeoff; this is a plain fact
  about the code's actual shape. It keeps the tool set registered on any
  given server instance always current with the caller's just-resolved
  tier (no session-lifetime tier caching to invalidate), at the cost of
  rebuilding the tool registry on every call.
  **Approved**: pending
