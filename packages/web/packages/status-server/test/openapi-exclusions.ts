/**
 * Routes that are intentionally NEVER part of the OpenAPI surface, excluded from the
 * drift guard (test/openapi.test.ts). Keep this list SHORT and justified — there is
 * NO backlog fixture, so every route not listed here must be documented from day one.
 */
export const PERMANENTLY_UNDOCUMENTED = new Set<string>([
  // The bare index (only present if a health/landing GET / is ever added) and the
  // spec endpoint itself — the OpenAPI document doesn't document its own URL.
  'GET /',
  'GET /doc',
  // The MCP transport (GET/POST/DELETE /mcp) is a JSON-RPC-over-Streamable-HTTP
  // transport, not a REST surface — deliberately never part of the OpenAPI document.
  'GET /mcp',
  'POST /mcp',
  'DELETE /mcp',
]);
