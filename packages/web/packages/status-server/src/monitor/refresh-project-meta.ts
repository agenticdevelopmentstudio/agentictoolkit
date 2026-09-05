import { and, eq, inArray, sql } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { deployProjectMeta } from "../libsql/schema";
import { providerConnFromConfig } from "@agentic-toolkit/deploy-platform/conn";
import { fetchVercelProductionStates, type VercelProjectMeta } from "./fetch-vercel-projects";

// ---------------------------------------------------------------------------
// `deploy_project_meta` is the ONLY source of "which VERCEL projects exist":
// enumerateDeployProjects seeds its Vercel pairs straight from this table (Railway
// and Cloudflare are polled live on every enumeration, so neither has an equivalent).
// The table was upsert-only — nothing ever deleted a row — so a project deleted at
// Vercel enumerated forever: Auto Configure kept offering it, and once accepted its
// new site legitimately OWNED a dead deploy target, whose last failed build reopened
// a Problem that deleting the site could never clear.
//
// This module makes the table a MIRROR of the account rather than an append-only log.
// It is deliberately the only writer, so the prune can never drift from the upsert.
// ---------------------------------------------------------------------------

/** Projects per INSERT (7 bound parameters each) and names per DELETE (1 each). A
 *  statement's parameter count is capped by the driver (SQLite's default is ~32k binds)
 *  and a large team is hundreds of projects, so both statements are chunked rather than
 *  sized by the account. These sit far under any cap while keeping round-trips low. */
const UPSERT_CHUNK_PROJECTS = 200;
const DELETE_CHUNK_NAMES = 500;

/** A Vercel project enumeration, tagged with the two facts a prune needs. */
export interface VercelMetaSnapshot {
  /** Descriptive config for every project the fetch returned. */
  meta: VercelProjectMeta[];
  /** The enumeration was COMPLETE. `fetchVercelProductionStates` already returns exactly
   *  this as `ok` (`ok: !skipped`): false for a budget-truncated page walk or an API
   *  failure. Only a complete read may evict — a partial one is missing projects that
   *  still exist. */
  ok: boolean;
  /** A `VERCEL_API_TOKEN` was present, so `meta` is a real account read. LOAD-BEARING:
   *  the fetcher returns `{ ok: true, meta: [] }` when the token is absent, which without
   *  this gate would wipe every project the moment the token went missing. Deliberately
   *  NOT inferred from `meta.length > 0` — an account whose LAST project was just deleted
   *  must still prune. */
  configured: boolean;
}

/** What one reconcile established. `live` is the AUTHORITATIVE set of Vercel projects that
 *  still exist — non-null only when the snapshot was complete and authenticated, so a caller
 *  may act on an absence. Null means "this read proves nothing about what's gone", and its
 *  callers must then narrow nothing. Handing it back is what stops the monitor re-deriving
 *  (and re-deciding) the same predicate from the same snapshot. */
export interface VercelMetaSyncResult {
  pruned: string[];
  live: Set<string> | null;
}

/** Chunked upsert — see {@link UPSERT_CHUNK_PROJECTS}. */
async function upsertMeta(db: Db, meta: VercelProjectMeta[]): Promise<void> {
  for (let i = 0; i < meta.length; i += UPSERT_CHUNK_PROJECTS) {
    await db
      .insert(deployProjectMeta)
      .values(
        meta.slice(i, i + UPSERT_CHUNK_PROJECTS).map((m) => ({
          platform: "vercel",
          projectName: m.projectName,
          domain: m.domain,
          gitRepo: m.gitRepo,
          gitBranch: m.gitBranch,
          rootDirectory: m.rootDirectory,
          framework: m.framework,
        })),
      )
      .onConflictDoUpdate({
        target: [deployProjectMeta.platform, deployProjectMeta.projectName],
        set: {
          domain: sql`excluded.domain`,
          gitRepo: sql`excluded.git_repo`,
          gitBranch: sql`excluded.git_branch`,
          rootDirectory: sql`excluded.root_directory`,
          framework: sql`excluded.framework`,
          updatedAt: sql`(unixepoch())`,
        },
      });
  }
}

/**
 * Reconcile `deploy_project_meta` with one Vercel enumeration: upsert every project the
 * fetch returned, then evict the `vercel` rows it did NOT return — but only when the read
 * was both complete and authenticated.
 *
 * The upsert runs unconditionally (even on a partial read) because it is also how a real
 * build failure's descriptive config lands; only the EVICTION needs a clean read.
 *
 * No grace window, and none is needed: the table is a derived cache, so an erroneous
 * eviction is repaired by the next cycle's upsert (5 minutes) rather than needing a
 * `last_seen_at` column and a TTL to get right.
 *
 * The prune diffs stored-against-live in JS and deletes by explicit name (chunked) instead
 * of one `notInArray` over the whole account, so the delete is bounded by what actually
 * changed rather than by team size.
 */
export async function syncVercelProjectMeta(db: Db, snapshot: VercelMetaSnapshot): Promise<VercelMetaSyncResult> {
  const { meta, ok, configured } = snapshot;

  if (meta.length > 0) await upsertMeta(db, meta);

  // A partial or tokenless read says nothing about what no longer exists.
  if (!ok || !configured) return { pruned: [], live: null };

  const live = new Set(meta.map((m) => m.projectName));
  const isVercel = eq(deployProjectMeta.platform, "vercel");
  const stored = await db.select({ projectName: deployProjectMeta.projectName }).from(deployProjectMeta).where(isVercel);
  const pruned = stored.map((r) => r.projectName).filter((name) => !live.has(name));

  for (let i = 0; i < pruned.length; i += DELETE_CHUNK_NAMES) {
    await db
      .delete(deployProjectMeta)
      .where(and(isVercel, inArray(deployProjectMeta.projectName, pruned.slice(i, i + DELETE_CHUNK_NAMES))));
  }

  if (pruned.length > 0) console.log(`[project-meta] evicted ${pruned.length} deleted Vercel project(s): ${pruned.join(", ")}`);
  return { pruned, live };
}

/** What a standalone refresh established. `configured` separates the two ways `ok` can be
 *  false: "Vercel isn't set up here" (a permanent, unremarkable steady state) from "we
 *  couldn't verify it this time" (transient, and worth telling the operator about). */
export interface VercelRefreshResult {
  ok: boolean;
  configured: boolean;
  pruned: string[];
}

/**
 * Fetch Vercel's project list and reconcile the table against it — the standalone refresh
 * for callers that don't already hold an enumeration (Auto Configure and the deploy-project
 * reads). The monitor cycle does NOT use this: it already fetched, so it hands its result to
 * {@link syncVercelProjectMeta} instead of paying for a second call.
 *
 * `metaOnly`: this path consumes ONLY the project list, so it opts out of the parts of the
 * fetch that exist for issue derivation (the per-project deployment window and the blind-
 * project backfill's extra API calls). Domain resolution stays — `meta.domain` is what Auto
 * Configure matches a monitored host against.
 *
 * `ok` means "the table now reflects a complete live read" — false with no token, on a
 * partial page walk, or on an API failure. Callers that must not suggest a project that
 * may no longer exist fail CLOSED on it.
 */
export async function refreshVercelProjectMeta(
  db: Db,
  env: { VERCEL_API_TOKEN?: string; VERCEL_TEAM_ID?: string },
): Promise<VercelRefreshResult> {
  const configured = !!env.VERCEL_API_TOKEN;
  // Nothing to verify against: skip the call rather than let the tokenless
  // `{ ok: true, meta: [] }` shape travel any further.
  if (!configured) return { ok: false, configured, pruned: [] };
  const res = await fetchVercelProductionStates({ ...env, metaOnly: true });
  const { pruned } = await syncVercelProjectMeta(db, { meta: res.meta, ok: res.ok, configured });
  return { ok: res.ok, configured, pruned };
}

/** {@link refreshVercelProjectMeta} with the credentials taken from the DB integration
 *  config (non-secret config there, token from env by name) — what the request-path
 *  callers want, since only the monitor cycle already holds a resolved connection. */
export async function refreshVercelProjectMetaFromConfig(db: Db): Promise<VercelRefreshResult> {
  const conn = await providerConnFromConfig(db);
  return refreshVercelProjectMeta(db, { VERCEL_API_TOKEN: conn.vercel.token, VERCEL_TEAM_ID: conn.vercel.teamId });
}

/** The Vercel projects the mirror currently says exist. For a path that must narrow a site's
 *  owned targets but holds no enumeration of its own (the webhook ingest): the table IS the
 *  account mirror, so reading it costs one indexed query instead of a provider round-trip on
 *  a latency-sensitive hook. */
export async function liveVercelProjectNames(db: Db): Promise<Set<string>> {
  const rows = await db
    .select({ projectName: deployProjectMeta.projectName })
    .from(deployProjectMeta)
    .where(eq(deployProjectMeta.platform, "vercel"));
  return new Set(rows.map((r) => r.projectName));
}
