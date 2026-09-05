import { z } from 'zod';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Tier } from '../middleware/auth';
import {
  buildSnapshot,
  buildUptime,
  queryHistory,
  findUnconfiguredSites,
  buildDeployProjects,
  refreshAndEnumerateDeployProjects,
  boardProblems,
  platformMetaFromConfig,
} from '../routes/reads';
import {
  siteGroupInsert,
  siteGroupPatch,
  monitoredSiteInsert,
  monitoredSitePatch,
  deployIntegrationInsert,
  deployIntegrationPatch,
  peerInsert,
} from '../routes/config';
import { DUPLICATE_PEER_MESSAGE, isDuplicatePeerError, isSelfPeerUrl } from '../peers/base-url';
import { autoConfigureBody, performAutoConfigure } from '../routes/auto-configure';
import { roleBody } from '../routes/users';
import {
  listSites,
  listSiteGroups,
  listEndpoints,
  listActiveEndpoints,
  listIntegrations,
  listPeers,
  createGroup,
  updateGroup,
  deleteGroup,
  createSite,
  updateSite,
  deleteSite,
  createIntegration,
  updateIntegration,
  deleteIntegration,
  createPeer,
  deletePeer,
  redactPeer,
} from '../storage/config-store';
import { listUsers, setUserRoleGuarded } from '../storage/auth-store';
import { reconcileBoardLedger } from '../board';
import { siteLinks } from '../lib/links';
import { collectTelemetry, errorsStore, analyticsStore } from '../telemetry/server';
import { assembleFleet } from '../peers/fleet';

// ---------------------------------------------------------------------------
// The MCP tool surface: thin wrappers over the SAME store/service functions the
// REST routes call. A tool NEVER re-implements a route's logic and NEVER makes an
// HTTP hop — the shared read-service functions (buildSnapshot, buildUptime,
// queryHistory, findUnconfiguredSites, performAutoConfigure) are the single body
// each pair shares, so a tool and its REST twin can't drift.
//
// Two INDEPENDENT axes (conflating them is what let the first cut widen access):
//  - `readOnly` describes the tool's NATURE — it feeds the MCP annotations
//    (readOnlyHint/destructiveHint) a client uses to judge safety. It does NOT
//    decide who may call the tool.
//  - AUTHORIZATION is `isAdminTool(tool)`: every write is admin-gated, AND a read
//    is admin-gated when its REST route is (`adminOnly: true`). REST is the access
//    authority; MCP must never widen it, so a viewer-invisible read stays admin.
// `selectTools('view')` returns the non-admin tools; `'admin'` returns all.
// server.ts registers exactly that set AND re-checks `isAdminTool` in every handler
// (fail-closed, defense in depth).
// ---------------------------------------------------------------------------

export interface McpTool {
  name: string;
  description: string;
  /** The tool's nature (drives the MCP read/destructive annotations), NOT its gate. */
  readOnly: boolean;
  /** A READ that is nonetheless admin-only because its REST route is (roster PII,
   *  platform config, peer topology). Writes are admin-gated by `!readOnly` already. */
  adminOnly?: boolean;
  inputSchema: z.ZodRawShape;
  execute(db: Db, args: Record<string, unknown>, config: StatusConfig): Promise<unknown>;
}

/** A tool the view tier may NOT use: any write, or a read whose REST route is admin-only.
 *  The single authorization predicate — both the selection filter and the per-handler
 *  re-check key off it, so the two fail-closed layers can never disagree. */
export function isAdminTool(tool: McpTool): boolean {
  return !tool.readOnly || tool.adminOnly === true;
}

const clampInt = (v: number, lo: number, hi: number): number => Math.min(Math.max(Math.trunc(v), lo), hi);

// Write-tool argument schemas defined ONCE — `.shape` feeds the MCP inputSchema and
// `.parse` produces the typed value the store function takes (single source of truth,
// so the wire contract and the store call can't disagree). Patches reuse Task 6's
// drizzle-zod schemas verbatim; an `id` is prepended for the update/delete targets.
const groupUpdateArgs = z.object({ id: z.string(), ...siteGroupPatch.shape });
const siteUpdateArgs = z.object({ id: z.string(), ...monitoredSitePatch.shape });
const platformUpdateArgs = z.object({ id: z.string(), ...deployIntegrationPatch.shape });
const userUpdateArgs = z.object({ id: z.string(), ...roleBody.shape });
const idArgs = z.object({ id: z.string() });

const READ_TOOLS: McpTool[] = [
  {
    name: 'get_status_summary',
    description: 'Overall status rollup plus per-service statuses and the open-issue list (the /snapshot payload).',
    readOnly: true,
    inputSchema: {},
    execute: (db, _args, config) => buildSnapshot(db, config),
  },
  {
    name: 'get_problems',
    description: 'Every currently-open issue (health, deploy, stale-prod, platform), newest-first.',
    readOnly: true,
    inputSchema: {},
    execute: async (db, _args, config) => boardProblems(db, config),
  },
  {
    name: 'get_issue',
    description: 'The single open issue for a target key (endpoint slug or deploy target), or null if none is open.',
    readOnly: true,
    inputSchema: { target: z.string() },
    execute: async (db, args, config) =>
      (await boardProblems(db, config)).find((p) => p.target === (args.target as string)) ?? null,
  },
  {
    name: 'get_uptime',
    description: 'Per-endpoint daily uptime over the last N days (default 90, clamped 1-365).',
    readOnly: true,
    inputSchema: { days: z.number().int().optional() },
    execute: (db, args) => buildUptime(db, clampInt((args.days as number | undefined) ?? 90, 1, 365)),
  },
  {
    name: 'query_history',
    description: "One endpoint's health-check samples over the last N hours (default 24, clamped 1-168).",
    readOnly: true,
    inputSchema: { slug: z.string(), hours: z.number().int().optional() },
    execute: (db, args) => queryHistory(db, args.slug as string, clampInt((args.hours as number | undefined) ?? 24, 1, 168)),
  },
  {
    name: 'get_telemetry_summary',
    description: 'Latest persisted error groups and analytics metrics (the last telemetry-collection pass).',
    readOnly: true,
    inputSchema: {},
    execute: async (db) => ({ errors: await errorsStore.load(db), analytics: await analyticsStore.load(db) }),
  },
  {
    name: 'list_errors',
    description: 'The open error groups from the last telemetry-collection pass.',
    readOnly: true,
    inputSchema: {},
    execute: (db) => errorsStore.load(db),
  },
  {
    name: 'get_analytics',
    description: 'The latest analytics metric per metric/window/scope from the last telemetry-collection pass.',
    readOnly: true,
    inputSchema: {},
    execute: (db) => analyticsStore.load(db),
  },
  {
    name: 'get_fleet',
    description: "This monitor's compact snapshot plus the latest stored snapshot per configured peer, annotated with freshness.",
    readOnly: true,
    inputSchema: {},
    execute: async (db, _args, config) => {
      const snap = await buildSnapshot(db, config);
      return assembleFleet(db, { label: config.monitorLabel, snapshot: snap, overall: snap.overall });
    },
  },
  {
    name: 'list_sites',
    description: 'Every monitored site (name, slug, group).',
    readOnly: true,
    adminOnly: true, // Only REST twin is GET /config/sites (admin) — raw SiteRow config, not the /status DTO.
    inputSchema: {},
    execute: (db) => listSites(db),
  },
  {
    name: 'get_site',
    description: 'One monitored site by id, with its endpoints.',
    readOnly: true,
    adminOnly: true, // Only REST twins are GET /config/sites + /config/endpoints (admin) — raw Site/EndpointRow.
    inputSchema: { id: z.string() },
    execute: async (db, args) => {
      const id = args.id as string;
      const site = (await listSites(db)).find((s) => s.id === id);
      if (!site) throw new Error('site not found');
      return { site, endpoints: await listEndpoints(db, id) };
    },
  },
  {
    name: 'list_groups',
    description: 'Every site group.',
    readOnly: true,
    adminOnly: true, // Only REST twin is GET /config/site-groups (admin) — raw GroupRow (retention, empty groups).
    inputSchema: {},
    execute: (db) => listSiteGroups(db),
  },
  {
    name: 'list_platforms',
    description: 'Every configured deploy-platform integration (Vercel/Railway/Cloudflare/Crunchy).',
    readOnly: true,
    adminOnly: true, // REST /config/integrations is admin-only — infra config, not viewer-visible.
    inputSchema: {},
    execute: (db) => listIntegrations(db),
  },
  {
    name: 'list_platform_projects',
    description: 'The deploy projects enumerated from the configured platforms, enriched with wired/ignored flags.',
    readOnly: true,
    inputSchema: {},
    // Same read as GET /deploy-projects: re-verify the Vercel project table, THEN enumerate.
    // Uncached (a tool call is rare and always deliberate), but the same function, so the
    // twins can't report different project sets.
    execute: async (db) => buildDeployProjects(db, (await refreshAndEnumerateDeployProjects(db)).enumerated),
  },
  {
    name: 'find_unconfigured_sites',
    description: 'The configuration gaps: pending/addable deploy projects and monitored endpoints not wired to a project.',
    readOnly: true,
    inputSchema: {},
    execute: async (db) => findUnconfiguredSites(db, (await refreshAndEnumerateDeployProjects(db)).enumerated),
  },
  {
    name: 'list_users',
    description: 'Every status-console user (no secrets).',
    readOnly: true,
    adminOnly: true, // REST /users is admin-only — roster PII, not viewer-visible.
    inputSchema: {},
    execute: (db) => listUsers(db),
  },
  {
    name: 'get_links',
    description: 'Per active endpoint: its live URL and deploy-platform dashboard link.',
    readOnly: true,
    inputSchema: {},
    execute: async (db, _args, config) => {
      const eps = await listActiveEndpoints(db);
      const platformMeta = platformMetaFromConfig(config);
      return eps.map((e) => ({
        slug: e.slug,
        name: e.name,
        group: e.group,
        environment: e.environment,
        url: e.url,
        links: siteLinks({ platform: e.platform, projectName: e.deployProject }, [{ url: e.url, environment: e.environment }], platformMeta),
      }));
    },
  },
  {
    name: 'list_peers',
    description: 'Every configured fleet peer (label, base URL, active flag, and `hasToken` — whether a peer token is set). The peer token itself is never returned.',
    readOnly: true,
    adminOnly: true, // REST /config/peers is admin-only — peer topology, not viewer-visible.
    inputSchema: {},
    execute: async (db) => (await listPeers(db)).map(redactPeer),
  },
];

const WRITE_TOOLS: McpTool[] = [
  {
    name: 'create_site',
    description: 'Create a monitored site under a group.',
    readOnly: false,
    inputSchema: monitoredSiteInsert.shape,
    execute: (db, args) => createSite(db, monitoredSiteInsert.parse(args)),
  },
  {
    name: 'update_site',
    description: 'Update a monitored site by id.',
    readOnly: false,
    inputSchema: siteUpdateArgs.shape,
    execute: async (db, args) => {
      const { id, ...patch } = siteUpdateArgs.parse(args);
      const row = await updateSite(db, id, patch);
      if (!row) throw new Error('site not found');
      return row;
    },
  },
  {
    name: 'delete_site',
    description: 'Delete a monitored site (purges its endpoints, history, and issues).',
    readOnly: false,
    inputSchema: idArgs.shape,
    execute: async (db, args, config) => {
      await deleteSite(db, idArgs.parse(args).id);
      await reconcileBoardLedger(db, config);
      return { ok: true };
    },
  },
  {
    name: 'create_group',
    description: 'Create a site group.',
    readOnly: false,
    inputSchema: siteGroupInsert.shape,
    execute: (db, args) => createGroup(db, siteGroupInsert.parse(args)),
  },
  {
    name: 'update_group',
    description: 'Update a site group by id.',
    readOnly: false,
    inputSchema: groupUpdateArgs.shape,
    execute: async (db, args) => {
      const { id, ...patch } = groupUpdateArgs.parse(args);
      const row = await updateGroup(db, id, patch);
      if (!row) throw new Error('group not found');
      return row;
    },
  },
  {
    name: 'delete_group',
    description: 'Delete a site group (cascades to its sites/endpoints and purges their history + issues).',
    readOnly: false,
    inputSchema: idArgs.shape,
    execute: async (db, args, config) => {
      await deleteGroup(db, idArgs.parse(args).id);
      await reconcileBoardLedger(db, config);
      return { ok: true };
    },
  },
  {
    name: 'create_platform',
    description: 'Create a deploy-platform integration.',
    readOnly: false,
    inputSchema: deployIntegrationInsert.shape,
    execute: (db, args) => createIntegration(db, deployIntegrationInsert.parse(args)),
  },
  {
    name: 'update_platform',
    description: 'Update a deploy-platform integration by id.',
    readOnly: false,
    inputSchema: platformUpdateArgs.shape,
    execute: async (db, args) => {
      const { id, ...patch } = platformUpdateArgs.parse(args);
      const row = await updateIntegration(db, id, patch);
      if (!row) throw new Error('integration not found');
      return row;
    },
  },
  {
    name: 'delete_platform',
    description: 'Delete a deploy-platform integration by id.',
    readOnly: false,
    inputSchema: idArgs.shape,
    execute: async (db, args, config) => {
      // `deleteIntegration` clears `platform_health_state.configured` for the platform it
      // was the last active integration for, in the same transaction — that is what makes
      // the sweep below true rather than decorative (`platformProblems` reads that column).
      await deleteIntegration(db, idArgs.parse(args).id);
      // Same inline sweep as delete_site / delete_group and DELETE /config/integrations/:id:
      // the platform is no longer configured, so its open ledger rows can no longer be
      // re-derived and would otherwise sit open (and alert-deduped) until the next cycle.
      await reconcileBoardLedger(db, config);
      return { ok: true };
    },
  },
  {
    name: 'run_auto_configure',
    description: 'Run the server-side Auto Configure pass (enumerate → classify → match/create → wire). Optionally ignore projects and create missing sites in a group.',
    readOnly: false,
    inputSchema: autoConfigureBody.shape,
    execute: (db, args) => performAutoConfigure(db, autoConfigureBody.parse(args)),
  },
  {
    name: 'configure_telemetry',
    description: 'Trigger a telemetry-collection pass (poll the configured error/analytics providers and persist their latest summaries), then return the fresh summary.',
    readOnly: false,
    inputSchema: {},
    execute: async (db, _args, config) => {
      await collectTelemetry(db, config);
      return { collected: true, errors: await errorsStore.load(db), analytics: await analyticsStore.load(db) };
    },
  },
  {
    name: 'update_user',
    description: "Set a user's role (pending/viewer/admin). Refuses to demote the last admin.",
    readOnly: false,
    inputSchema: userUpdateArgs.shape,
    execute: async (db, args) => {
      const { id, role } = userUpdateArgs.parse(args);
      const updated = await setUserRoleGuarded(db, id, role);
      if (updated === undefined) throw new Error('user not found');
      if (updated === 'blocked') throw new Error('cannot demote the last admin');
      return updated;
    },
  },
  {
    name: 'add_peer',
    description: 'Register a fleet peer (baseUrl must be an absolute http(s) URL). The created row is returned without its token — only `hasToken`.',
    readOnly: false,
    inputSchema: peerInsert.shape,
    // The same duplicate → readable sentence the HTTP POST maps to a 409. An agent
    // that hits `uniq_peer_base_url` should read why, not a driver's constraint text.
    execute: async (db, args, config) => {
      const data = peerInsert.parse(args);
      if (isSelfPeerUrl(data.baseUrl, config)) {
        throw new Error('baseUrl is this monitor’s own URL — a monitor is already in its own fleet view');
      }
      try {
        return redactPeer(await createPeer(db, data));
      } catch (err) {
        if (isDuplicatePeerError(err)) throw new Error(DUPLICATE_PEER_MESSAGE);
        throw err;
      }
    },
  },
  {
    name: 'remove_peer',
    description: 'Remove a fleet peer by id.',
    readOnly: false,
    inputSchema: idArgs.shape,
    execute: async (db, args) => {
      await deletePeer(db, idArgs.parse(args).id);
      return { ok: true };
    },
  },
];

export const ALL_TOOLS: McpTool[] = [...READ_TOOLS, ...WRITE_TOOLS];

/** The tools a tier may use: every tool for `'admin'`, the non-admin tools for `'view'`
 *  (viewer-visible reads only — writes and admin-gated reads are filtered out). */
export function selectTools(tier: Tier): McpTool[] {
  return tier === 'admin' ? ALL_TOOLS : ALL_TOOLS.filter((t) => !isAdminTool(t));
}
