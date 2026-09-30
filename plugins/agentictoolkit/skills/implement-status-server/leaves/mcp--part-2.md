<!-- leaf: implement-status-server/mcp--part-2 · source: status-server-mcp.md -->

# Status Server MCP — continued (part 2)

**Rules** (cite as `implement-status-server/mcp--part-2#<slug>`):

- `mcp-fixed-path` MUST
- `mcp-methods` MUST
- `mcp-mounted-after-auth` MUST
- `mcp-per-request-server` MUST
- `mcp-stateless-transport` MUST
- `mcp-dns-rebinding-enabled` MUST
- `mcp-allowed-hosts-composition` MUST
- `mcp-body-preparsed-passthrough` MUST
- `mcp-response-already-sent` MUST
- `mcp-server-identity` MUST
- `mcp-registers-tier-set-only` MUST
- `mcp-tool-annotations` MUST
- `mcp-handler-recheck` MUST
- `mcp-success-envelope` MUST
- `mcp-execute-errors-caught` MUST
- `mcp-args-default-empty` MUST
- `mcp-tool-catalog-fixed` MUST
- `is-admin-tool-predicate` MUST
- `select-tools-admin` MUST
- `select-tools-view` MUST
- `rest-parity-no-reimplementation` MUST
- `write-schema-reuse` MUST
- `get-status-summary-delegates` MUST
- `get-problems-delegates` MUST
- `get-issue-filters-by-target` MUST
- `get-uptime-clamps-days` MUST
- `query-history-clamps-hours` MUST
- `telemetry-read-trio` MUST
- `get-fleet-composes-snapshot-and-fleet` MUST
- `admin-only-config-reads` MUST
- `get-site-composes-and-guards` MUST
- `list-users-admin-only` MUST
- `list-peers-redacts-token` MUST
- `deploy-project-reads-reverify` MUST
- `get-links-composes-endpoint-links` MUST

## Behavioral Requirements

### Route Mounting (route.ts)

- **mcp-fixed-path**: `mountMcp` MUST register its handler at the single
  fixed path `/mcp` (`MCP_PATH`).
- **mcp-methods**: `mountMcp` MUST handle exactly the HTTP methods `POST`,
  `GET`, and `DELETE` on that path (`app.on(['POST', 'GET', 'DELETE'], ...)`).
- **mcp-mounted-after-auth**: `mountMcp` MUST be registered after the
  app-wide `requireAuth` seam, so `c.get('tier')` is already resolved (from
  the session cookie or an `sts_` bearer, per `status-server-auth`) before
  the handler runs.
- **mcp-per-request-server**: the handler MUST call `buildMcpServer(storage,
  c.get('tier'), config)` and construct a fresh `StreamableHTTPServerTransport`
  inside every request; it MUST NOT cache or reuse a server or transport
  instance across requests.
- **mcp-stateless-transport**: the constructed transport MUST set
  `sessionIdGenerator: undefined`, so the MCP session is stateless — no
  session id is minted or tracked across requests.
- **mcp-dns-rebinding-enabled**: the constructed transport MUST set
  `enableDnsRebindingProtection: true`.
- **mcp-allowed-hosts-composition**: `allowedHosts(config)` MUST return
  `['localhost', '127.0.0.1', ...config.mcpAllowedHosts]` — the two dev
  hostnames are always present in addition to whatever
  `config.mcpAllowedHosts` supplies.
- **mcp-body-preparsed-passthrough**: the handler MUST parse the request
  body itself via `c.req.json().catch(() => undefined)` (yielding `undefined`
  on a missing body or a JSON parse failure) and pass that value as
  `transport.handleRequest`'s third argument, per the source comment,
  because Hono's own body-parsing has already consumed the request stream
  by the time the SDK transport would otherwise try to read it.
- **mcp-response-already-sent**: after `transport.handleRequest` completes
  (having written directly to the raw Node `req`/`res` exposed as `c.env`
  `HttpBindings`), the handler MUST return `RESPONSE_ALREADY_SENT` so Hono
  does not attempt to write a second response.

### Server Construction and the Fail-Closed Gate (server.ts)

- **mcp-server-identity**: `buildMcpServer` MUST construct the `McpServer`
  with `{ name: 'status-backend', version: '1.0.0' }`.
- **mcp-registers-tier-set-only**: `buildMcpServer` MUST register only the
  tools `selectTools(tier)` returns for the given tier — layer 1 of the
  fail-closed model: a `'view'` caller's server never has a write or
  admin-only-read tool registered on it at all, so it cannot appear in
  `tools/list` or be called by name.
- **mcp-tool-annotations**: `registerTool` MUST set the registered tool's
  MCP annotations to `{ readOnlyHint: tool.readOnly, destructiveHint:
  !tool.readOnly, idempotentHint: tool.readOnly, openWorldHint: false }` —
  derived entirely from the tool's own `readOnly` flag, never from
  `adminOnly`.
- **mcp-handler-recheck**: every registered tool's handler MUST re-evaluate
  `isAdminTool(tool) && tier !== 'admin'` before calling `tool.execute`, and
  MUST return `fail('admin tier required', 'forbidden_tier')` without
  calling `execute` when that condition is true — layer 2 of the fail-closed
  model, so a tool mis-registered for the wrong tier (a defect in
  `selectTools`) still cannot execute under `'view'`.
- **mcp-success-envelope**: on a successful `tool.execute`, the handler MUST
  return `ok(data)` — `{ content: [{ type: 'text', text: JSON.stringify({ ok:
  true, data }) }] }` — with no `isError` field.
- **mcp-execute-errors-caught**: the handler MUST wrap `tool.execute` in a
  `try`/`catch`; a thrown error MUST be converted to `fail(message, 'execution_error')`
  — `{ content: [...], isError: true }` with `{ ok: false, error, code:
  'execution_error' }` where `error` is `e.message` when `e instanceof Error`,
  else `String(e)` — and MUST NOT propagate out of the handler to the
  transport.
- **mcp-args-default-empty**: the handler MUST pass `args ?? {}` to
  `tool.execute`, so a tool with an empty `inputSchema` called with no
  `arguments` field receives `{}`, not `undefined`.

### Tool Selection and Authorization (tools.ts)

- **mcp-tool-catalog-fixed**: `ALL_TOOLS` MUST be exactly `[...READ_TOOLS,
  ...WRITE_TOOLS]` — 18 read tools followed by 14 write tools, 32 tools
  total, each with a unique `name`.
- **is-admin-tool-predicate**: `isAdminTool(tool)` MUST return `true` when
  `tool.readOnly` is `false`, or when `tool.adminOnly` is `true`; MUST
  return `false` for every other tool (a read whose `adminOnly` is absent
  or `false`). This is the single predicate both fail-closed layers key off.
- **select-tools-admin**: `selectTools('admin')` MUST return `ALL_TOOLS`
  unfiltered — all 32 tools.
- **select-tools-view**: `selectTools('view')` MUST return exactly the 12
  tools for which `isAdminTool` is `false`; it MUST exclude all 14 write
  tools and all 6 admin-only reads (`list_sites`, `get_site`, `list_groups`,
  `list_platforms`, `list_users`, `list_peers`).
- **rest-parity-no-reimplementation**: every tool's `execute` MUST call an
  existing store/service function the corresponding REST route already
  calls (or, for the six tools with no direct REST twin — `get_issue`,
  `get_telemetry_summary`, `list_errors`, `get_analytics`, `list_platforms`,
  `list_peers` — the same `storage`/`config` read a REST route uses for
  equivalent data); a tool MUST NOT re-implement that logic inline and MUST
  NOT issue an HTTP request to reach it.
- **write-schema-reuse**: every write tool's `inputSchema` MUST be the
  `.shape` of a zod schema also used, unmodified, to validate the
  corresponding REST route's request body (`siteGroupInsert`/`Patch`,
  `monitoredSiteInsert`/`Patch`, `deployIntegrationInsert`/`Patch`,
  `peerInsert`, `autoConfigureBody`, `roleBody`), so the wire schema and the
  REST body validator can never disagree.

### Read Tools

- **get-status-summary-delegates**: `get_status_summary` MUST call
  `buildSnapshot(storage, config)` with no arguments and return its result
  unchanged.
- **get-problems-delegates**: `get_problems` MUST call `boardProblems(storage,
  config)` with no arguments and return its result unchanged.
- **get-issue-filters-by-target**: `get_issue` MUST call `boardProblems(storage,
  config)` and return the first `Problem` whose `target` equals the
  caller's `target` argument, or `null` when no entry matches — including
  when `target` names a row a stale ledger table still carries but
  `boardProblems` no longer derives.
- **get-uptime-clamps-days**: `get_uptime` MUST clamp its optional `days`
  argument via `clampInt` to the closed integer range 1–365, defaulting to
  `90` when `days` is omitted, before calling `buildUptime(storage, days)`.
- **query-history-clamps-hours**: `query_history` MUST clamp its optional
  `hours` argument via `clampInt` to the closed integer range 1–168,
  defaulting to `24` when omitted, before calling `queryHistory(storage,
  slug, hours)`; a `slug` naming no active endpoint MUST NOT raise an
  error — `queryHistory` performs no existence check and simply returns
  its result for that slug with no matching samples.
- **telemetry-read-trio**: `get_telemetry_summary`, `list_errors`, and
  `get_analytics` MUST each read only from `storage.telemetry.errors.load()`
  and/or `storage.telemetry.analytics.load()` — the last persisted
  `collectTelemetry` pass — with no arguments and no re-collection;
  `get_telemetry_summary` MUST return `{ errors, analytics }` combining
  both loads, `list_errors` MUST return only the errors load, and
  `get_analytics` MUST return only the analytics load.
- **get-fleet-composes-snapshot-and-fleet**: `get_fleet` MUST call
  `buildSnapshot(storage, config)`, then call `assembleFleet(storage, {
  label: config.monitorLabel, snapshot, overall: snapshot.overall })` using
  that same snapshot, and return the `assembleFleet` result.
- **admin-only-config-reads**: `list_sites`, `list_groups`, and
  `list_platforms` MUST each carry `adminOnly: true` and MUST return,
  respectively, `storage.config.listSites()`, `storage.config.listSiteGroups()`,
  and `storage.config.listIntegrations()` unmodified.
- **get-site-composes-and-guards**: `get_site` MUST carry `adminOnly: true`,
  MUST find the site whose `id` matches the caller's `id` argument in
  `storage.config.listSites()`, MUST throw `Error('site not found')` when
  none matches, and on a match MUST return `{ site, endpoints }` where
  `endpoints` is `storage.config.listEndpoints(id)`.
- **list-users-admin-only**: `list_users` MUST carry `adminOnly: true` and
  MUST return `storage.auth.listUsers()` unmodified (no secrets, per its
  description).
- **list-peers-redacts-token**: `list_peers` MUST carry `adminOnly: true`
  and MUST map every row of `storage.config.listPeers()` through
  `redactPeer`, so no response ever includes a peer's raw `token` field —
  only the derived `hasToken` boolean.
- **deploy-project-reads-reverify**: `list_platform_projects` and
  `find_unconfigured_sites` MUST each call `refreshAndEnumerateDeployProjects(storage,
  config)` — re-verifying the live platform (Vercel) project list, never a
  possibly-stale DB mirror — before deriving their result via
  `buildDeployProjects`/`findUnconfiguredSites` on the refreshed
  `enumerated` list.
- **get-links-composes-endpoint-links**: `get_links` MUST read
  `storage.config.listActiveEndpoints()` and, for each endpoint, return
  `{ slug, name, group, environment, url, links }` where `links` is
  `siteLinks({ platform, projectName: deployProject }, [{ url, environment }],
  platformMetaFromConfig(config))`.

