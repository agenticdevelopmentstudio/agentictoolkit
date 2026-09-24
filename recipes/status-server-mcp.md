---
id: ce157d5a-c145-4348-b58f-6a76c9fda1d6
title: Status Server MCP
domain: agentictoolkit://recipes/status-server-mcp
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Status backend''s MCP tool surface: a stateless Streamable-HTTP /mcp route,
  the two-layer fail-closed admin gate, and 32 tools that thin-wrap the same store/service
  functions their REST twins call.'
platforms:
- typescript
- web
tags:
- mcp
- authorization
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/mcp-server-security
- agenticdevelopercookbook://guidelines/implementing/security/mcp-input-validation
- agenticdevelopercookbook://guidelines/implementing/networking/mcp-server-design
- agenticdevelopercookbook://guidelines/implementing/security/authorization
related:
- agentictoolkit://recipes/status-server-auth
references:
- packages/web/packages/status-server/src/mcp/route.ts (agentictoolkit)
- packages/web/packages/status-server/src/mcp/server.ts (agentictoolkit)
- packages/web/packages/status-server/src/mcp/tools.ts (agentictoolkit)
- packages/web/packages/status-server/test/mcp.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/mcp-deploy-tools.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-route.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

### Write Tools

- **create-tools-parse-then-insert**: `create_site`, `create_group`, and
  `create_platform` MUST each call `.parse(args)` on their schema
  (`monitoredSiteInsert`, `siteGroupInsert`, `deployIntegrationInsert`) and
  pass the parsed value unchanged to `storage.config.createSite`/`createGroup`/`createIntegration`,
  returning the created row.
- **update-tools-require-id**: `update_site`, `update_group`, and
  `update_platform` MUST each accept an `id: string` argument prepended to
  the resource's own zod patch shape (`monitoredSitePatch`, `siteGroupPatch`,
  `deployIntegrationPatch`), call the matching `storage.config.update*(id,
  patch)`, and MUST throw `Error('site not found')` / `Error('group not
  found')` / `Error('integration not found')` respectively when that call
  resolves a falsy row.
- **delete-tools-reconcile-board**: `delete_site`, `delete_group`, and
  `delete_platform` MUST each call the matching `storage.config.delete*(id)`
  and then call `reconcileBoardLedger(storage, config)` before returning
  `{ ok: true }`, so a deleted site's/group's/platform's open board issues
  are swept in the same call rather than left open until the next monitor
  cycle.
- **run-auto-configure-delegates**: `run_auto_configure` MUST call
  `.parse(args)` on `autoConfigureBody` and return
  `performAutoConfigure(storage, config, parsed)` unchanged — the same
  function `POST /auto-configure` calls.
- **configure-telemetry-collects-then-reads**: `configure_telemetry` MUST
  call `collectTelemetry(storage, config)` (poll every configured
  error/analytics provider and persist the result) before returning
  `{ collected: true, errors: await storage.telemetry.errors.load(),
  analytics: await storage.telemetry.analytics.load() }` read fresh from
  storage after that collection completes.
- **update-user-role-guard**: `update_user` MUST call
  `storage.auth.setUserRoleGuarded(id, role)` (parsed via `userUpdateArgs` =
  `{ id } & roleBody.shape`) and MUST throw `Error('user not found')` when
  it resolves `undefined`, and `Error('cannot demote the last admin')` when
  it resolves the literal string `'blocked'`; on any other resolved value it
  MUST return that value unchanged.
- **add-peer-self-guard**: `add_peer` MUST call `.parse(args)` on
  `peerInsert`, then MUST throw `Error('baseUrl is this monitor’s own URL —
  a monitor is already in its own fleet view')` when `isSelfPeerUrl(data.baseUrl,
  config)` is `true`, without attempting a store insert in that case.
- **add-peer-duplicate-mapping**: when `add_peer`'s `storage.config.createPeer(data)`
  call rejects and `isDuplicatePeerError(err)` is `true`, `add_peer` MUST
  re-throw `Error(DUPLICATE_PEER_MESSAGE)` instead of the original driver
  error; MUST re-throw the original error unchanged for any other rejection.
- **add-peer-redacts-result**: on a successful insert, `add_peer` MUST
  return `redactPeer(created)`, never the raw created row (which would
  carry the caller-supplied `token`).
- **remove-peer-delegates**: `remove_peer` MUST call
  `storage.config.deletePeer(id)` and return `{ ok: true }`; unlike
  `delete_site`/`delete_group`/`delete_platform`, it MUST NOT call
  `reconcileBoardLedger` — a peer has no board-ledger issues derived from
  it.

### Security

This module is the single seam where authorization for the entire MCP tool
surface is decided — every write and every roster/config/peer read a
`'view'`-tier caller could otherwise reach is gated here, not in the tools
that follow. It is a security-relevant recipe per this cookbook's Cookbook
Compliance guideline, so the concerns below are addressed explicitly.

- **readonly-and-adminonly-independent**: `readOnly` and `adminOnly` MUST
  remain two independent axes — `readOnly` MUST only ever affect the MCP
  annotations (`mcp-tool-annotations`), never `isAdminTool`'s outcome
  directly (it affects it only through the `!tool.readOnly` half of the
  predicate); conflating a tool's *nature* with its *authorization* is
  documented in `tools.ts`'s own header comment as the defect that "let the
  first cut widen access."
- **rest-is-the-access-authority**: a read tool's admin-gating MUST match
  its REST twin's — `adminOnly-config-reads`/`list-users-admin-only`/`list-peers-redacts-token`/`get-site-composes-and-guards`
  are `adminOnly: true` because their only REST twin (`/config/sites`,
  `/config/site-groups`, `/config/integrations`, `/users`, `/config/peers`)
  is admin-gated; MCP MUST NOT expose a wider read surface than REST does
  for the same data.
- **no-caller-token-passthrough**: none of these three files forwards the
  calling MCP client's own bearer or session credential to any downstream
  system; every write/read acts through `storage`/`config`, and the only
  outbound network calls two write tools make (`run_auto_configure`'s
  `performAutoConfigure`, `configure_telemetry`'s `collectTelemetry`) use
  platform credentials from `config.credentials`/`config.secrets`, never
  the caller's own token.
- **peer-token-never-returned**: `list_peers` and `add_peer` are the only
  two tools that touch a peer's `token` field, and both MUST route their
  result through `redactPeer` before returning, per
  `list-peers-redacts-token` and `add-peer-redacts-result`.

## Appearance

Not applicable — this is a server-side MCP tool surface, not a visual component.

## States

Not applicable — this is a server-side MCP tool surface, not a visual component; its runtime branches are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side MCP tool surface, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-mcp-001 | mcp-mounted-after-auth | `POST /mcp` with no `Authorization` header, a valid `tools/list` JSON-RPC body | `401` — `mcp.int.test.ts` › "rejects a request with no bearer token (401)" |
| status-server-mcp-002 | mcp-registers-tier-set-only, select-tools-admin | An admin-token MCP client calls `listTools()` | Returns all 32 tools, matching `new Set(ALL_TOOLS.map(t => t.name))` — `mcp.int.test.ts` › "admin token lists ALL tools..." |
| status-server-mcp-003 | mcp-registers-tier-set-only, select-tools-view | A view-token MCP client calls `listTools()` | Returns exactly 12 tools, equal to `selectTools('view').length`, including `get_status_summary`, `get_problems`, `get_uptime`, `query_history`, `get_fleet`, `list_platform_projects`, `find_unconfigured_sites`, `get_links` — same test, second assertion |
| status-server-mcp-004 | mcp-success-envelope, get-status-summary-delegates | Admin token calls `get_status_summary` with `{}` | `isError` absent; envelope `{ ok: true, data: { overall: string, services: [...] } }` — `mcp.int.test.ts` › "round-trips a read tool (get_status_summary)..." |
| status-server-mcp-005 | mcp-success-envelope, create-tools-parse-then-insert | Admin token calls `create_group` with `{ name: 'MCP Group', slug: 'mcp-grp' }` | Envelope `{ ok: true, data: { slug: 'mcp-grp', name: 'MCP Group' } }`; the row exists in `storage.config.listSiteGroups()` afterward — `mcp.int.test.ts` › "round-trips a write tool (create_group)..." |
| status-server-mcp-006 | mcp-execute-errors-caught, update-tools-require-id | Admin token calls `update_group` with `{ id: 'does-not-exist', name: 'x' }` | `isError: true`; envelope `{ ok: false, code: 'execution_error' }` — `mcp.int.test.ts` › "surfaces a failed write as an isError envelope..." |
| status-server-mcp-007 | select-tools-view, mcp-registers-tier-set-only | View token calls `create_group` (a tool never registered for `'view'`) | `isError: true` (SDK "tool not found"); the store is never touched — `mcp.int.test.ts` › "refuses a write from a view-tier token..." |
| status-server-mcp-008 | select-tools-view, list-users-admin-only | View token calls `list_users` | `isError: true` (SDK "tool not found") — `mcp.int.test.ts` › "refuses an admin-only READ (list_users)..." |
| status-server-mcp-009 | select-tools-view, admin-only-config-reads | View token calls `list_sites` | `isError: true` (SDK "tool not found") — `mcp.int.test.ts` › "refuses an admin-only config READ (list_sites)..." |
| status-server-mcp-010 | deploy-project-reads-reverify | `list_platform_projects.execute` with a live Vercel project `mcp-live` and a stale `deployProjectMeta` row `mcp-ghost` (deleted at the platform) | Returns projects `['mcp-live']` only; the DB mirror itself is corrected to `['mcp-live']` — `mcp-deploy-tools.int.test.ts` › "list_platform_projects drops a project deleted at the platform" |
| status-server-mcp-011 | deploy-project-reads-reverify | `find_unconfigured_sites.execute` with the same live/stale project setup | `pending` and `addable` both list only `['mcp-live']`, never `mcp-ghost` — `mcp-deploy-tools.int.test.ts` › "find_unconfigured_sites never offers a project deleted at the platform" |
| status-server-mcp-012 | get-problems-delegates | `get_problems.execute` against a seeded DB with a known failed Vercel deployment, compared against `GET /board` on the same DB | The tool's problem `target`s (sorted) exactly equal `GET /board`'s problem targets (sorted) — `board-route.test.ts` › "get_problems returns exactly GET /board's problem targets..." |
| status-server-mcp-013 | get-issue-filters-by-target | `get_issue.execute` with `{ target: 'vercel\|hub-help-testing\|' }` against the same seeded failed-deployment DB | Returns the `Problem` whose `target` is `'vercel\|hub-help-testing\|'` — `board-route.test.ts` › "get_issue returns the Problem the board derives for a target it recognizes" |
| status-server-mcp-014 | get-issue-filters-by-target | `get_issue.execute` with `{ target: 'vercel\|long-deleted-site\|' }` where only a stale `issues` ledger row (not a live board-derived problem) carries that target | Returns `null` — the Task-14 regression test, `board-route.test.ts` › "get_issue returns null for a target only a stale LEDGER row carries" |
| status-server-mcp-015 | mcp-tool-annotations | Inspect `get_status_summary`'s registered annotations (a read tool, `readOnly: true`) | `{ readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }` — derived directly from `registerTool`'s annotation mapping |
| status-server-mcp-016 | mcp-tool-annotations | Inspect `create_group`'s registered annotations (a write tool, `readOnly: false`) | `{ readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false }` |
| status-server-mcp-017 | mcp-handler-recheck | A tool with `isAdminTool(tool) === true` is invoked with `tier` forced to `'view'` at the handler level (bypassing `selectTools` registration filtering, simulating a registration defect) | The handler returns `fail('admin tier required', 'forbidden_tier')` without calling `tool.execute` — traced to `registerTool`'s layer-2 re-check, independent of the layer-1 registration filter `mcp-002`/`mcp-003`/`mcp-007`–`mcp-009` exercise |
| status-server-mcp-018 | query-history-clamps-hours | `query_history.execute(storage, { slug: 'no-such-endpoint', hours: 24 }, config)` | Resolves normally (no thrown error) with an empty/no-match result for that slug — `queryHistory` performs no existence check |
| status-server-mcp-019 | add-peer-self-guard | `add_peer.execute(storage, { baseUrl: <this monitor's own publicBaseUrl>, ... }, config)` | Throws `Error('baseUrl is this monitor’s own URL — a monitor is already in its own fleet view')`; no store insert attempted |
| status-server-mcp-020 | add-peer-duplicate-mapping, add-peer-redacts-result | `add_peer.execute` twice with the same `baseUrl` | Second call throws `Error(DUPLICATE_PEER_MESSAGE)`; a successful first call's returned row carries `hasToken` but never `token` |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `config.mcpAllowedHosts` | `readonly string[]` (`StatusConfig` field) | host-supplied | Additional hostnames the `/mcp` transport's DNS-rebinding guard accepts, appended to the always-present `'localhost'`/`'127.0.0.1'`. |
| `config.monitorLabel` | `string` (`StatusConfig` field) | host-supplied | This monitor's own label, passed to `assembleFleet` by `get_fleet` so the fleet view can identify which member is "self." |
| `config.credentials` / `config.secrets` | `Readonly<Record<string, string \| undefined>>` (`StatusConfig` fields) | host-supplied | Platform provider credentials `run_auto_configure`/`configure_telemetry` pass through to `performAutoConfigure`/`collectTelemetry`; never the caller's own MCP bearer. |
| `MCP_PATH` | module constant (`route.ts`) | `'/mcp'` | The one fixed path `mountMcp` registers; not configurable per call. |
| `tier` | `Tier` (`'view' \| 'admin'`), read from `c.get('tier')` | resolved upstream by `requireAuth` | Determines `selectTools(tier)`'s registration set and every handler's layer-2 re-check; these three files never resolve it themselves. |
| `storage` | injected `Storage` port | required | Every tool's `execute` reads or writes through this port; its implementation is external to these three files. |

## Deep Linking

Not applicable: none of these three files defines an application URL scheme; `/mcp` is a single fixed HTTP path on the status backend's own origin, not a deep-link target.

## Localization

None of these three files uses a localization mechanism; every user-facing
string (tool description, thrown error message) is a hardcoded English
literal. Per this recipe's authoring rules, a hardcoded string is a fact to
record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — `forbidden_tier` | `admin tier required` | `registerTool`'s layer-2 re-check refusing an admin-gated tool under `'view'` |
| n/a — `execution_error` | `site not found` | `get_site`, `update_site` when no row matches the given `id` |
| n/a — `execution_error` | `group not found` | `update_group` when no row matches the given `id` |
| n/a — `execution_error` | `integration not found` | `update_platform` when no row matches the given `id` |
| n/a — `execution_error` | `user not found` | `update_user` when `setUserRoleGuarded` resolves `undefined` |
| n/a — `execution_error` | `cannot demote the last admin` | `update_user` when `setUserRoleGuarded` resolves `'blocked'` |
| n/a — `execution_error` | `baseUrl is this monitor's own URL — a monitor is already in its own fleet view` | `add_peer` when `isSelfPeerUrl` matches |
| n/a — `execution_error` | `DUPLICATE_PEER_MESSAGE` (from `peers/base-url.ts`, external to these three files) | `add_peer` when the store insert fails with a duplicate-base-URL constraint violation |

## Accessibility Options

Not applicable: these three files have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of these three files consults a feature-flag system.

## Analytics

Not applicable: none of these three files emits an analytics or telemetry event of its own; `get_telemetry_summary`/`list_errors`/`get_analytics` READ previously collected telemetry data, they do not emit it.

## Privacy

- **Data collected**: nothing new — every tool reads or writes data the
  REST API already collects through the same `Storage` port. The data in
  scope that these three files specifically handle: a peer's `token`
  (`list_peers`, `add_peer` — always redacted to `hasToken` before
  returning, per `list-peers-redacts-token`/`add-peer-redacts-result`), the
  user roster (`list_users`, `update_user` — "no secrets" per its
  description), and site/group/platform configuration (the `adminOnly`
  reads and the create/update/delete write tools).
- **Storage**: none of these three files writes to persistent storage
  directly — every mutation goes through the `Storage` port's
  `config`/`auth` namespaces, whose implementation (table layout, hashing)
  is external and not specified here.
- **Transmission**: a tool's result crosses back to the MCP client inside
  the JSON text envelope (`ok`/`fail`) over the same Streamable-HTTP
  connection the request arrived on; these three files add no separate
  transmission channel. `run_auto_configure`/`configure_telemetry` are the
  only tools that cause outbound network calls (to configured deploy/error/analytics
  providers), and those calls carry platform credentials from
  `config.credentials`/`config.secrets`, never the caller's own MCP bearer
  (`no-caller-token-passthrough`).
- **Retention**: these three files set no retention policy of their own;
  `delete_site`/`delete_group`/`delete_platform`/`remove_peer` delete rows
  immediately through the `Storage` port, and the board-ledger sweep
  (`delete-tools-reconcile-board`) closes derived issues in the same call
  rather than leaving them to expire later.

## Logging

Not applicable: none of `route.ts`, `server.ts`, or `tools.ts` contains a logging call at any level.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`server-side-authorization` passes: both fail-closed layers
(`mcp-registers-tier-set-only`, `mcp-handler-recheck`) resolve tier
entirely server-side from `c.get('tier')`, upstream of these three files;
no tool trusts a client-supplied role or tier value. `input-sanitization`
passes: every write tool's argument is parsed through its zod schema
before reaching a store call, and no tool interpolates a string argument
into a query, shell command, or rendered markup — arguments flow only into
typed store-function parameters. `secure-log-output` passes trivially — per
Logging, there is no log output in these three files to leak anything
into. `separation-of-concerns` passes: `route.ts` owns transport mounting
and the DNS-rebinding/host-allowlist concern, `server.ts` owns server
construction and the fail-closed authorization gate, and `tools.ts` owns
the tool catalog and its REST-parity delegation, with every actual
store/service operation living in files outside this recipe entirely.
`unit-test-coverage` passes: `mcp.int.test.ts` exercises the transport's
auth boundary, tier-based tool visibility, the success/failure envelope,
and both fail-closed refusal shapes; `mcp-deploy-tools.int.test.ts` covers
the deploy-project re-verification fix; `board-route.test.ts`'s MCP
`describe` block covers `get_problems`/`get_issue` parity with `GET /board`,
including the Task-14 stale-ledger regression. `explicit-error-handling` is
`partial`: every thrown `execute()` error is caught and converted to a
typed `execution_error` envelope, never silently swallowed — but a
malformed JSON `POST` body is caught and discarded
(`.catch(() => undefined)`) with no signal distinguishing it from a
bodyless `GET`/`DELETE` request, so that one specific failure mode
produces no error of its own at this layer (see Edge Cases).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
