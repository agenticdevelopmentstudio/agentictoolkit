import { eq } from "drizzle-orm";
import type { LibSQLDatabase } from "drizzle-orm/libsql";
import { deployIntegrations } from "../schema/index.js";
import type { RailwayProject } from "../providers/railway.js";
import type { ProviderName } from "../cooldown/provider-cooldown.js";

/** The minimal libSQL/SQLite database handle every core function takes. The schema
 *  generic is intentionally `Record<string, unknown>` (not the caller's full schema)
 *  — the core only uses `.select().from()` builders, which don't need the relational
 *  schema, so this keeps the core decoupled from any one consumer's table set. */
export type DeployDb = LibSQLDatabase<Record<string, unknown>>;

/** Resolved connection details per deploy provider — non-secret config from the
 *  DB integrations table, tokens from env by name (tokenEnvVar). */
export interface ProviderConn {
  vercel: { token?: string; teamId?: string };
  cloudflare: { token?: string; accountId?: string; workerScripts?: string[] };
  railway: { token?: string; projects?: RailwayProject[] };
  crunchy: { token?: string };
}

/**
 * The providers a healer may re-fetch A SINGLE DEPLOY BY ID from — Vercel and
 * Railway — restricted to those with a token. Cloudflare and Crunchy have no
 * by-id deploy lookup, so they're never in this set.
 *
 * Typed `ProviderName[]` on purpose: the reconcile and enrichment healers filter
 * this against the shared provider cooldown, and a raw `platform` string cast to
 * `ProviderName` could smuggle a non-slot name (a DB `platform` is
 * "cloudflare-pages", not a cooldown slot) into the Atomics index and throw a
 * RangeError inside the monitor cycle. Sourcing the list from the fixed slot
 * literals here makes that cast impossible at the call sites.
 */
export function pollableByIdPlatforms(conn: ProviderConn): ProviderName[] {
  const out: ProviderName[] = [];
  if (conn.vercel.token) out.push("vercel");
  if (conn.railway.token) out.push("railway");
  return out;
}

/** Provider connections straight from env — the defensive fallback if the DB is
 *  unavailable. Tokens come from env; non-secret fallback lists are omitted
 *  (the backend has no shipped config file). */
export function connFromEnv(): ProviderConn {
  return {
    vercel: { token: process.env.VERCEL_API_TOKEN, teamId: process.env.VERCEL_TEAM_ID },
    cloudflare: {
      token: process.env.CLOUDFLARE_API_TOKEN,
      accountId: process.env.CLOUDFLARE_ACCOUNT_ID,
    },
    railway: {
      token: process.env.RAILWAY_API_TOKEN,
    },
    crunchy: { token: process.env.CRUNCHY_API_TOKEN },
  };
}

/** The slice of a deploy_integrations row `providerConnFromIntegrations` reads — a plain
 *  shape, so a consumer that keeps its integrations behind its own storage port can hand
 *  them over without this package seeing its database. */
export interface IntegrationLike {
  platform: string;
  config: unknown;
  tokenEnvVar: string | null;
}

/** Provider connections from already-loaded integration rows (the caller passes only the
 *  ACTIVE ones) and a token lookup by credential name. Pure: no database, no env read —
 *  the lookup is where the caller decides whether that name means `process.env` or its
 *  own secret store. */
export function providerConnFromIntegrations(
  integrations: IntegrationLike[],
  token: (envVar: string) => string | undefined,
): ProviderConn {
  const find = (p: string) => integrations.find((i) => i.platform === p);
  const tokenOf = (i: IntegrationLike | undefined): string | undefined =>
    i?.tokenEnvVar ? token(i.tokenEnvVar) : undefined;
  const cfg = (i: { config: unknown } | undefined, key: string): unknown =>
    (i?.config as Record<string, unknown> | undefined)?.[key];

  const vercel = find("vercel");
  const cloudflare = find("cloudflare");
  const railway = find("railway");
  const crunchy = find("crunchy");
  return {
    vercel: { token: tokenOf(vercel), teamId: (cfg(vercel, "teamId") as string | null | undefined) ?? undefined },
    cloudflare: {
      token: tokenOf(cloudflare),
      accountId: (cfg(cloudflare, "accountId") as string | null | undefined) ?? undefined,
      workerScripts: cfg(cloudflare, "workerScripts") as string[] | undefined,
    },
    railway: { token: tokenOf(railway), projects: cfg(railway, "projects") as RailwayProject[] | undefined },
    crunchy: { token: tokenOf(crunchy) },
  };
}

/** Provider connections from the DB's deploy_integrations table (active rows only),
 *  tokens from `process.env` by the row's `tokenEnvVar`. */
export async function providerConnFromConfig(db: DeployDb): Promise<ProviderConn> {
  const integrations = await db
    .select()
    .from(deployIntegrations)
    .where(eq(deployIntegrations.isActive, true));
  return providerConnFromIntegrations(integrations, (envVar) => process.env[envVar]);
}
