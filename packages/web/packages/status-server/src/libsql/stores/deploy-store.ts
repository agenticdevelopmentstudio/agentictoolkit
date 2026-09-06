import { sql, eq, and, or, gt, lt, isNull, inArray, notInArray, desc } from "drizzle-orm";
import type { Db } from "../client";
import { deployments, monitoredEndpoints, deployProjectMeta } from "../schema";
import { platformCanon } from "@agentic-toolkit/deploy-platform";
import {
  webhookKeepsStoredSql,
  inFlightSql,
  collapseInFlightBuildSql,
  collapseInFlightDeploySql,
} from "../../monitor/deploy-status";
import { ownedDeploysWhere } from "./owned-deploys";
import type {
  DeployStore,
  DeployUpsertInput,
  DeployHostRow,
  DeployPhases,
  DeployIdPlatformRow,
  DeployLogRow,
  DeploymentRow,
  OwnedProjects,
  ProjectMetaInput,
  ProjectMetaRow,
} from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `DeployStore`. Bodies moved verbatim from
// `monitor/sync.ts`, `monitor/reconcile-stuck-deploys.ts`, `monitor/enrich-deploy-errors.ts`
// and `monitor/refresh-project-meta.ts` — the query halves only; the business-logic
// halves (dedup rules, backoff, retry policy, fail-soft wrapping) stay in those files
// and call these methods.
// ---------------------------------------------------------------------------

/** Projects per INSERT (7 bound parameters each) and names per DELETE (1 each). A
 *  statement's parameter count is capped by the driver (SQLite's default is ~32k binds)
 *  and a large team is hundreds of projects, so both statements are chunked rather than
 *  sized by the account. These sit far under any cap while keeping round-trips low. */
const UPSERT_CHUNK_PROJECTS = 200;
const DELETE_CHUNK_NAMES = 500;

/** Build the `DeployStore` port over one connection. */
export function createDeployStore(db: Db): DeployStore {
  return {
    /** Upsert fetched/webhook deploys by id (phases win the update so a re-fetched
     *  build moves to its latest state). Exported for the webhook routes: a
     *  provider-pushed terminal state persists even when the deploy has already
     *  left the recent-deploys poll window. */
    async upsertDeployments(
      deploys: DeployUpsertInput[],
      opts: { source?: "poll" | "webhook" } = {},
    ): Promise<void> {
      // Dedup by id within this batch (the projects fetch + recent fetch overlap) —
      // recent rows are appended after prod, so last-write-wins on identical data.
      const byId = new Map<string, DeployUpsertInput>();
      for (const d of deploys) {
        // LAST LINE OF DEFENCE for the timestamp. Every fetcher validates at its own
        // boundary, but that is a convention each one must remember; this is the choke
        // point EVERY deploy crosses before the DB. An Invalid Date reaching the insert
        // fails the whole batch — and since the deploy stays in the provider's window,
        // it fails it again every cycle: /health goes stale and the container
        // restart-loops. One bad row must cost that row, never the cycle.
        if (!Number.isFinite(d.createdAt?.getTime?.())) {
          console.error(`[sync] deploy ${d.id} has an invalid createdAt — dropping it (fetcher should have caught this)`);
          continue;
        }
        byId.set(d.id, d);
      }
      const rows = [...byId.values()];
      if (rows.length === 0) return;

      // Webhooks arrive OUT OF ORDER — relative to the poll (a delayed deployment.created
      // after the poll already recorded READY) and relative to EACH OTHER (a redelivered
      // `created` after its own `build-requested`). Either way a webhook upsert must never
      // walk a row backwards. `webhookKeepsStoredSql` is the whole rule and states its own
      // reasoning; it lives beside the phase vocabulary so no query can drift from it.
      //
      // The POLL takes no guard: its by-id state is current truth, and a genuine
      // terminal→in-flight transition (Vercel re-promotion → ROLLING) must go through.
      const guardRegression = opts.source === "webhook";
      const phase = (col: "build_phase" | "deploy_phase"): ReturnType<typeof sql.raw> =>
        guardRegression
          ? sql.raw(`CASE WHEN ${webhookKeepsStoredSql(col)} THEN ${col} ELSE excluded.${col} END`)
          : sql.raw(`excluded.${col}`);

      await db
        .insert(deployments)
        .values(
          rows.map((d) => ({
            id: d.id,
            platform: d.platform,
            projectName: d.projectName,
            providerProjectId: d.providerProjectId ?? null,
            buildPhase: d.buildPhase,
            deployPhase: d.deployPhase,
            environment: d.environment,
            commitHash: d.commitHash,
            commitMessage: d.commitMessage,
            branch: d.branch,
            commitRepo: d.commitRepo,
            url: d.url,
            createdAt: d.createdAt,
          })),
        )
        .onConflictDoUpdate({
          target: deployments.id,
          set: {
            buildPhase: phase("build_phase"),
            deployPhase: phase("deploy_phase"),
            // NOT COALESCE and not omitted: a project renamed upstream keeps re-reporting
            // its existing deploys under the NEW name, and a row frozen at the old name
            // would sit in the table for the full 90-day retention minting a second group
            // for a single target. `platform` is deliberately absent — it is part of the
            // identity, not a description of it.
            projectName: sql`excluded.project_name`,
            // Descriptive fields COALESCE so a sparser source (a webhook event
            // without commit meta) can update the PHASES without erasing what a
            // richer fetch already recorded.
            // COALESCE, like the other descriptive columns: a webhook carries no project id,
            // and a sparser source must never erase what a richer fetch already recorded.
            providerProjectId: sql`COALESCE(excluded.provider_project_id, provider_project_id)`,
            environment: sql`COALESCE(excluded.environment, environment)`,
            commitHash: sql`COALESCE(excluded.commit_hash, commit_hash)`,
            commitMessage: sql`COALESCE(excluded.commit_message, commit_message)`,
            branch: sql`COALESCE(excluded.branch, branch)`,
            commitRepo: sql`COALESCE(excluded.commit_repo, commit_repo)`,
            url: sql`COALESCE(excluded.url, url)`,
            // Keep the EARLIEST creation time seen: webhook rows carry event-emission
            // time (later than true creation), so letting them overwrite would skew
            // ordering, the reconcile window, and stuck-deploy detection.
            createdAt: sql`min(excluded.created_at, created_at)`,
            fetchedAt: sql`(unixepoch())`,
          },
        });
    },

    /** Learn each endpoint's provider project id from the deploys we just fetched, keyed by
     *  the NAME that already matches. One poll arms every already-wired endpoint; from then
     *  on a rename upstream resolves by id even though `deploy_project` still holds the OLD
     *  name, which is the entire point of adopting ids.
     *
     *  Idempotent and null-only: it never overwrites an id, so an operator's hand-entered
     *  value always wins and a re-run is free. */
    async learnProjectIds(
      deploys: { platform: string; projectName: string; providerProjectId?: string | null }[],
    ): Promise<void> {
      const idByPlatform = new Map<string, Map<string, string>>();
      for (const d of deploys) {
        if (!d.providerProjectId) continue;
        const platform = platformCanon(d.platform);
        const byName = idByPlatform.get(platform) ?? new Map<string, string>();
        if (!byName.has(d.projectName)) byName.set(d.projectName, d.providerProjectId);
        idByPlatform.set(platform, byName);
      }
      if (idByPlatform.size === 0) return;

      const rows = await db
        .select({
          id: monitoredEndpoints.id,
          platform: monitoredEndpoints.platform,
          deployProject: monitoredEndpoints.deployProject,
        })
        .from(monitoredEndpoints)
        .where(isNull(monitoredEndpoints.deployProjectId));

      for (const r of rows) {
        if (!r.platform || !r.deployProject) continue;
        const hit = idByPlatform.get(platformCanon(r.platform))?.get(r.deployProject);
        if (!hit) continue;
        await db
          .update(monitoredEndpoints)
          .set({ deployProjectId: hit, updatedAt: new Date() })
          .where(eq(monitoredEndpoints.id, r.id));
      }
    },

    async pruneOlderThanDays(days: number): Promise<void> {
      await db.delete(deployments).where(sql`${deployments.createdAt} < unixepoch() - ${days} * 86400`);
    },

    async listForLiveHostStamp(): Promise<DeployHostRow[]> {
      return db
        .select({
          id: deployments.id,
          platform: deployments.platform,
          providerProjectId: deployments.providerProjectId,
          projectName: deployments.projectName,
          environment: deployments.environment,
          liveHost: deployments.liveHost,
        })
        .from(deployments);
    },

    async setLiveHost(id: string, host: string | null): Promise<void> {
      await db.update(deployments).set({ liveHost: host }).where(eq(deployments.id, id));
    },

    async listInFlightCandidates(input: {
      platforms: string[];
      excludeIds: string[];
      createdAfterMs: number;
      fetchedBeforeMs: number;
      limit: number;
    }): Promise<DeployIdPlatformRow[]> {
      return db
        .select({ id: deployments.id, platform: deployments.platform })
        .from(deployments)
        .where(
          and(
            inArray(deployments.platform, input.platforms),
            // Literal in-flight predicate (shared vocabulary) — matches idx_deploy_inflight's
            // partial WHERE textually, so this per-tick query seeks the index, not a full scan.
            sql.raw(inFlightSql("")),
            gt(deployments.createdAt, new Date(input.createdAfterMs)),
            lt(deployments.fetchedAt, new Date(input.fetchedBeforeMs)),
            input.excludeIds.length > 0 ? notInArray(deployments.id, input.excludeIds) : undefined,
          ),
        )
        .orderBy(desc(deployments.createdAt))
        .limit(input.limit);
    },

    async markDeployGone(id: string): Promise<void> {
      // Provider says the deployment no longer exists → terminalize the IN-FLIGHT
      // lifecycle(s) only (build→canceled, deploy→none), the same mapping as Vercel
      // DELETED / Railway REMOVED. A per-lifecycle CASE over the row's CURRENT state
      // (not a blanket overwrite) preserves a settled verdict the other lifecycle
      // already reached, and is race-safe against a concurrent write between the
      // select and this update.
      await db
        .update(deployments)
        .set({
          buildPhase: sql.raw(collapseInFlightBuildSql("canceled")),
          deployPhase: sql.raw(collapseInFlightDeploySql("none")),
          fetchedAt: new Date(),
        })
        .where(eq(deployments.id, id));
    },

    async markDeployPhases(id: string, phases: DeployPhases): Promise<void> {
      // Fresh by-id provider truth — authoritative, so it overwrites both phases.
      await db
        .update(deployments)
        .set({ buildPhase: phases.buildPhase, deployPhase: phases.deployPhase, fetchedAt: new Date() })
        .where(eq(deployments.id, id));
    },

    async expireStaleInFlight(olderThanMs: number): Promise<number> {
      const res = await db
        .update(deployments)
        // Same per-lifecycle collapse markDeployGone uses, to `unknown` — a settled
        // lifecycle keeps its verdict; only the in-flight one(s) expire.
        .set({
          buildPhase: sql.raw(collapseInFlightBuildSql("unknown")),
          deployPhase: sql.raw(collapseInFlightDeploySql("unknown")),
        })
        .where(
          and(
            // Same shared in-flight predicate the reconcile uses → also seeks idx_deploy_inflight.
            sql.raw(inFlightSql("")),
            lt(deployments.fetchedAt, new Date(Date.now() - olderThanMs)),
          ),
        );
      return Number(res.rowsAffected ?? 0);
    },

    async listFailedWithoutError(input: {
      platforms: string[];
      createdAfterMs: number;
      limit: number;
    }): Promise<DeployIdPlatformRow[]> {
      return db
        .select({ id: deployments.id, platform: deployments.platform })
        .from(deployments)
        .where(
          and(
            isNull(deployments.errorText),
            inArray(deployments.platform, input.platforms),
            or(eq(deployments.buildPhase, "failed"), eq(deployments.deployPhase, "failed")),
            gt(deployments.createdAt, new Date(input.createdAfterMs)),
          ),
        )
        .orderBy(desc(deployments.createdAt))
        .limit(input.limit);
    },

    async setErrorText(id: string, text: string): Promise<void> {
      await db.update(deployments).set({ errorText: text }).where(eq(deployments.id, id));
    },

    /** Chunked upsert — see {@link UPSERT_CHUNK_PROJECTS}. */
    async upsertProjectMeta(rows: ProjectMetaInput[]): Promise<void> {
      for (let i = 0; i < rows.length; i += UPSERT_CHUNK_PROJECTS) {
        await db
          .insert(deployProjectMeta)
          .values(
            rows.slice(i, i + UPSERT_CHUNK_PROJECTS).map((m) => ({
              platform: m.platform,
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
    },

    async listProjectMetaNames(platform: string): Promise<string[]> {
      const rows = await db
        .select({ projectName: deployProjectMeta.projectName })
        .from(deployProjectMeta)
        .where(eq(deployProjectMeta.platform, platform));
      return rows.map((r) => r.projectName);
    },

    async listProjectMeta(): Promise<ProjectMetaRow[]> {
      const rows = await db
        .select({
          platform: deployProjectMeta.platform,
          projectName: deployProjectMeta.projectName,
          domain: deployProjectMeta.domain,
          gitRepo: deployProjectMeta.gitRepo,
          gitBranch: deployProjectMeta.gitBranch,
          rootDirectory: deployProjectMeta.rootDirectory,
          framework: deployProjectMeta.framework,
        })
        .from(deployProjectMeta);
      return rows;
    },

    /** Chunked delete — see {@link DELETE_CHUNK_NAMES}. */
    async deleteProjectMeta(platform: string, names: string[]): Promise<void> {
      const isPlatform = eq(deployProjectMeta.platform, platform);
      for (let i = 0; i < names.length; i += DELETE_CHUNK_NAMES) {
        await db
          .delete(deployProjectMeta)
          .where(and(isPlatform, inArray(deployProjectMeta.projectName, names.slice(i, i + DELETE_CHUNK_NAMES))));
      }
    },

    /** The most recent `limit` deploys some live site monitors (see `ownedDeploysWhere`),
     *  newest-created first — the Deployments-tab feed. */
    async listRecentOwned(owned: OwnedProjects, limit: number): Promise<DeploymentRow[]> {
      return db
        .select()
        .from(deployments)
        .where(ownedDeploysWhere(owned))
        .orderBy(desc(deployments.createdAt))
        .limit(limit);
    },

    async findById(id: string): Promise<DeployLogRow | null> {
      const [row] = await db
        .select({
          id: deployments.id,
          platform: deployments.platform,
          projectName: deployments.projectName,
          environment: deployments.environment,
          errorText: deployments.errorText,
        })
        .from(deployments)
        .where(eq(deployments.id, id))
        .limit(1);
      return row ?? null;
    },
  };
}
