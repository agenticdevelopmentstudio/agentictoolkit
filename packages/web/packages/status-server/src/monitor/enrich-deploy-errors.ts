import { and, or, eq, gt, isNull, inArray, desc } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { deployments } from "../libsql/schema";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import { fetchVercelDeployError } from "./fetch-vercel";
import { fetchRailwayBuildLogTail } from "./fetch-railway";
import { pollableByIdPlatforms, type ProviderConn } from "@agentic-toolkit/deploy-platform/conn";
import { rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";

// Only RECENT failures are worth explaining (bounds the scan), and only a few are
// enriched per cycle. Enrichment is idempotent — error_text is written once and
// then the row is skipped forever — so any backlog drains over successive cycles
// without a single cycle ever fetching enough to threaten the watchdog budget.
const ENRICH_WINDOW_DAYS = 14;
const ENRICH_MAX_PER_CYCLE = 8;
const ENRICH_CONCURRENCY = 4;
const ENRICH_CALL_TIMEOUT_MS = 8_000;

interface FailedRow {
  id: string; // 'vc_<uid>' | 'ry_<id>'
  platform: string;
}

/** The provider failure reason for ONE failed deploy — dispatched by platform.
 *  Vercel has a clean single `errorMessage`; Railway's reason lives in the build
 *  log tail. Returns null for a platform we can't fetch (no token / no reason). */
async function fetchErrorFor(row: FailedRow, conn: ProviderConn, signal: AbortSignal): Promise<string | null> {
  if (row.platform === "vercel" && conn.vercel.token) {
    return fetchVercelDeployError(
      row.id.replace(/^vc_/, ""),
      { VERCEL_API_TOKEN: conn.vercel.token, VERCEL_TEAM_ID: conn.vercel.teamId },
      signal,
    );
  }
  if (row.platform === "railway" && conn.railway.token) {
    return fetchRailwayBuildLogTail(row.id.replace(/^ry_/, ""), conn.railway.token, signal);
  }
  return null;
}

/**
 * Fill in `error_text` for FAILED Vercel/Railway deploys that don't have it yet —
 * the provider's failure reason (Vercel `errorMessage`, Railway build-log tail),
 * fetched ONCE per deploy and persisted so the details pane (and its copy button)
 * can show WHY a build failed without opening the provider dashboard.
 *
 * Runs after upsertDeployments each cycle. Best-effort and fail-soft: the whole
 * function is bounded (recent window, per-cycle cap, bounded concurrency, per-call
 * timeout) and every fetch is wrapped so one failure never aborts the cycle — a
 * failed fetch just leaves `error_text` null, to retry next cycle.
 */
export async function enrichDeployErrors(db: Db, conn: ProviderConn): Promise<void> {
  // Honor the shared cooldown (same rule as the reconcile): a throttled provider's rows
  // wait for a later cycle rather than spending requests that extend the throttle.
  // pollableByIdPlatforms is typed ProviderName[], so no `as` cast can slip a non-slot
  // name into the cooldown's Atomics index.
  const polled = pollableByIdPlatforms(conn).filter((p) => !rateLimitedUntil(p));
  if (polled.length === 0) return; // no token, or both cooling down

  let candidates: FailedRow[];
  try {
    candidates = await db
      .select({ id: deployments.id, platform: deployments.platform })
      .from(deployments)
      .where(
        and(
          isNull(deployments.errorText),
          inArray(deployments.platform, polled),
          or(eq(deployments.buildPhase, "failed"), eq(deployments.deployPhase, "failed")),
          gt(deployments.createdAt, new Date(Date.now() - ENRICH_WINDOW_DAYS * 86_400_000)),
        ),
      )
      .orderBy(desc(deployments.createdAt))
      .limit(ENRICH_MAX_PER_CYCLE);
  } catch (err) {
    console.error("[enrich] failed-deploy query failed:", err);
    return;
  }
  if (candidates.length === 0) return;

  await mapLimit(candidates, ENRICH_CONCURRENCY, async (row) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ENRICH_CALL_TIMEOUT_MS);
    try {
      const text = await fetchErrorFor(row, conn, controller.signal);
      if (text) await db.update(deployments).set({ errorText: text }).where(eq(deployments.id, row.id));
    } catch (err) {
      console.error(`[enrich] ${row.id} error fetch/store failed:`, err);
    } finally {
      clearTimeout(timer);
    }
  });
}
