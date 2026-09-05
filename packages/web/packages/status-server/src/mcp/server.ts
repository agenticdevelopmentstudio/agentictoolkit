import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Tier } from '../middleware/auth';
import { isAdminTool, selectTools, type McpTool } from './tools';

/** Wrap a tool result in the JSON text envelope every tool shares: a success carries
 *  `{ ok: true, data }`; a thrown execute() (a 404-ish "not found", a guard rejection)
 *  carries `{ ok: false, error, code }` with `isError` so the client sees a failure
 *  without the transport erroring. */
function ok(data: unknown): CallToolResult {
  return { content: [{ type: 'text', text: JSON.stringify({ ok: true, data }) }] };
}
function fail(error: string, code: string): CallToolResult {
  return { content: [{ type: 'text', text: JSON.stringify({ ok: false, error, code }) }], isError: true };
}

/**
 * Build a stateless MCP server exposing exactly the tools the caller's tier may use.
 *
 * Two fail-closed layers guard writes:
 *  1. Registration — only `selectTools(tier)` is registered, so a `'view'` caller's
 *     tools/list (and every callable tool) is the viewer-visible set.
 *  2. Handler re-check — every admin-gated handler re-asserts `tier === 'admin'` before
 *     it runs, so even a mis-selected admin tool refuses under `'view'` (returns isError)
 *     rather than executing.
 */
export function buildMcpServer(db: Db, tier: Tier, config: StatusConfig): McpServer {
  const server = new McpServer({ name: 'status-backend', version: '1.0.0' });

  for (const tool of selectTools(tier)) {
    registerTool(server, db, tier, tool, config);
  }

  return server;
}

function registerTool(server: McpServer, db: Db, tier: Tier, tool: McpTool, config: StatusConfig): void {
  server.registerTool(
    tool.name,
    {
      description: tool.description,
      inputSchema: tool.inputSchema,
      annotations: {
        readOnlyHint: tool.readOnly,
        destructiveHint: !tool.readOnly,
        idempotentHint: tool.readOnly,
        openWorldHint: false,
      },
    },
    async (args: Record<string, unknown>): Promise<CallToolResult> => {
      // Layer 2: an admin-gated tool (any write, or an admin-only read) must never execute
      // under the view tier, even if it were registered by mistake. Viewer reads pass.
      if (isAdminTool(tool) && tier !== 'admin') {
        return fail('admin tier required', 'forbidden_tier');
      }
      try {
        return ok(await tool.execute(db, args ?? {}, config));
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e), 'execution_error');
      }
    },
  );
}
