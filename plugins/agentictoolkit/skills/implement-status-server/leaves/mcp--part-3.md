<!-- leaf: implement-status-server/mcp--part-3 · source: status-server-mcp.md -->

# Status Server MCP — continued (part 3)

**Rules** (cite as `implement-status-server/mcp--part-3#<slug>`):

- `create-tools-parse-then-insert` MUST
- `update-tools-require-id` MUST
- `delete-tools-reconcile-board` MUST
- `run-auto-configure-delegates` MUST
- `configure-telemetry-collects-then-reads` MUST
- `update-user-role-guard` MUST
- `add-peer-self-guard` MUST
- `add-peer-duplicate-mapping` MUST
- `add-peer-redacts-result` MUST
- `remove-peer-delegates` MUST
- `readonly-and-adminonly-independent` MUST
- `rest-is-the-access-authority` MUST
- `peer-token-never-returned` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `config.mcpAllowedHosts` | `readonly string[]` (`StatusConfig` field) | host-supplied | Additional hostnames the `/mcp` transport's DNS-rebinding guard accepts, appended to the always-present `'localhost'`/`'127.0.0.1'`. |
| `config.monitorLabel` | `string` (`StatusConfig` field) | host-supplied | This monitor's own label, passed to `assembleFleet` by `get_fleet` so the fleet view can identify which member is "self." |
| `config.credentials` / `config.secrets` | `Readonly<Record<string, string \| undefined>>` (`StatusConfig` fields) | host-supplied | Platform provider credentials `run_auto_configure`/`configure_telemetry` pass through to `performAutoConfigure`/`collectTelemetry`; never the caller's own MCP bearer. |
| `MCP_PATH` | module constant (`route.ts`) | `'/mcp'` | The one fixed path `mountMcp` registers; not configurable per call. |
| `tier` | `Tier` (`'view' \| 'admin'`), read from `c.get('tier')` | resolved upstream by `requireAuth` | Determines `selectTools(tier)`'s registration set and every handler's layer-2 re-check; these three files never resolve it themselves. |
| `storage` | injected `Storage` port | required | Every tool's `execute` reads or writes through this port; its implementation is external to these three files. |

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

