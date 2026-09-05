import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { RESPONSE_ALREADY_SENT } from '@hono/node-server/utils/response';
import type { HttpBindings } from '@hono/node-server';
import type { OpenAPIHono } from '@hono/zod-openapi';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { AuthVars } from '../middleware/auth';
import { buildMcpServer } from './server';

const MCP_PATH = '/mcp';

/**
 * Hostnames the MCP transport accepts (DNS-rebinding defense). localhost/127.0.0.1
 * for dev; production hosts come from `config.mcpAllowedHosts` (comma-separated,
 * `host:port`, already parsed by the config port).
 */
function allowedHosts(config: StatusConfig): string[] {
  return ['localhost', '127.0.0.1', ...config.mcpAllowedHosts];
}

/**
 * Mount the stateless Streamable-HTTP MCP transport at `/mcp`. Registered AFTER the
 * app-wide requireAuth seam, so `c.get('tier')` is already resolved (from the session
 * cookie OR an `sts_` bearer) — the tool set the caller sees is `selectTools(tier)`
 * (view → read-only, admin → all), with a fail-closed re-check in every write handler.
 *
 * The SDK's transport writes straight to the raw Node req/res exposed by
 * @hono/node-server as `c.env` HttpBindings, so the handler returns
 * RESPONSE_ALREADY_SENT to tell Hono the response is handled. Hono has already
 * consumed the request stream, so the pre-parsed body is passed through.
 */
export function mountMcp(app: OpenAPIHono<{ Variables: AuthVars }>, db: Db, config: StatusConfig): void {
  app.on(['POST', 'GET', 'DELETE'], MCP_PATH, async (c) => {
    const { incoming, outgoing } = c.env as unknown as HttpBindings;
    const body = await c.req.json().catch(() => undefined);
    const server = buildMcpServer(db, c.get('tier'), config);
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableDnsRebindingProtection: true,
      allowedHosts: allowedHosts(config),
    });
    await server.connect(transport);
    await transport.handleRequest(incoming, outgoing, body);
    return RESPONSE_ALREADY_SENT;
  });
}
