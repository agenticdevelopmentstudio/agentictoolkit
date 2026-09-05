import { sql } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { healthChecks } from "../libsql/schema";
import { withTimeout } from "@agentic-toolkit/deploy-platform/util";
import { timeAgo } from "./time-ago";
import { resolveCfAccountId, listWorkerScripts } from "@agentic-toolkit/deploy-platform/providers";
import { createSelfCheckStabilizer } from "./self-check-stability";
import type { CheckState, IntegrationCheck, IntegrationsResponse } from "./types";
import type { StatusConfig } from "../config/port";

export type { IntegrationCheck };

const TIMEOUT_MS = 6_000;
const CRON_STALE_MS = 180_000; // 3 × 60s intervals
const PROBE_RETRIES = 1; // one extra attempt on a transient blip before going red
const RETRY_BACKOFF_MS = 300; // brief pause so the retry doesn't re-hit the same burst

const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** A momentary failure worth retrying rather than reporting as a hard outage: our
 *  6s AbortController timeout (AbortError "This operation was aborted") or an undici
 *  connection failure (TypeError "fetch failed", usually with an ECONN-family or DNS cause).
 *  A real HTTP response (401/403/5xx) is NOT a throw — it never reaches here — so
 *  token-invalid and the like still surface immediately without a retry. */
function isTransient(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  if (err.name === "AbortError" || err.name === "TimeoutError") return true;
  const cause = (err as { cause?: { code?: string } }).cause?.code ?? "";
  return /fetch failed|network|socket|ECONN|EAI_AGAIN|ENOTFOUND|ETIMEDOUT|UND_ERR/i.test(
    `${err.message} ${cause}`,
  );
}

/**
 * Run an outbound probe with a FRESH per-attempt timeout, retrying ONCE on a
 * transient blip so a single momentary stall (cron-burst event-loop pressure, a GC
 * pause, a restart cold-start, a brief egress hiccup) doesn't flip the whole status
 * page red. Two failure shapes are handled: a throw (Vercel/Railway fetch) is retried
 * only when `isTransient`; a returned value flagged by `isRetryableValue` (Cloudflare's
 * `listWorkerScripts`, which reports failure as a `null` return rather than a throw) is
 * retried too. Non-transient throws and non-flagged values pass through immediately.
 */
async function probe<T>(
  fn: (signal: AbortSignal) => Promise<T>,
  isRetryableValue: (value: T) => boolean = () => false,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const t = withTimeout(TIMEOUT_MS);
    try {
      const value = await fn(t.signal);
      if (attempt >= PROBE_RETRIES || !isRetryableValue(value)) return value;
    } catch (err) {
      if (attempt >= PROBE_RETRIES || !isTransient(err)) throw err;
    } finally {
      t.done();
    }
    await delay(RETRY_BACKOFF_MS);
  }
}

/**
 * Per-check state:
 *   not configured → "warn" (missing token is a warning, not a hard failure)
 *   configured but not ok → "error"
 *   configured & ok → "ok"
 */
export function checkState(configured: boolean, ok: boolean): CheckState {
  if (!configured) return "warn";
  return ok ? "ok" : "error";
}

/**
 * Overall state: any "error" wins; else any "warn" wins; else "ok".
 * Empty list → "ok".
 */
export function overallState(checks: { state: CheckState }[]): CheckState {
  if (checks.some((c) => c.state === "error")) return "error";
  if (checks.some((c) => c.state === "warn")) return "warn";
  return "ok";
}

/** Aggregate stats over the persisted health checks — total samples + distinct
 *  services (mirrors the old statsStore.summary()). The new backend's stats are
 *  DB-backed (persistent), unlike the status site's interim in-memory store. */
async function statsSummary(db: Db): Promise<{ samples: number; services: number }> {
  const [row] = await db
    .select({
      samples: sql<number>`count(*)`,
      services: sql<number>`count(distinct ${healthChecks.serviceSlug})`,
    })
    .from(healthChecks);
  return { samples: Number(row?.samples ?? 0), services: Number(row?.services ?? 0) };
}

/** Most recent health-check time in ms, or null when no checks have run yet
 *  (mirrors the old statsStore.lastCheckedAt()). */
async function lastCheckedAtMs(db: Db): Promise<number | null> {
  const [row] = await db
    .select({ last: sql<number | null>`max(${healthChecks.checkedAt})` })
    .from(healthChecks);
  // checkedAt is stored as unix-seconds — scale to ms.
  return row?.last == null ? null : Number(row.last) * 1000;
}

async function checkStatsStore(db: Db): Promise<IntegrationCheck> {
  const id = "stats";
  const label = "Stats store";
  const s = await statsSummary(db);
  const detail = `persistent · ${s.samples} samples across ${s.services} services`;
  return { id, label, configured: true, ok: true, state: "ok", detail };
}

async function checkStatsFreshness(db: Db): Promise<IntegrationCheck> {
  const id = "cron";
  const label = "Stats freshness";
  const last = await lastCheckedAtMs(db);
  if (last === null) {
    // Right after a (re)start there are no samples until the first poll/cron
    // tick — that's expected, not a failure, so warn rather than error.
    return { id, label, configured: true, ok: false, state: "warn", detail: "first poll pending — no checks yet" };
  }
  const nowMs = Date.now();
  const ageMs = nowMs - last;
  const ageLabel = timeAgo(new Date(last).toISOString(), nowMs);
  const stale = ageMs > CRON_STALE_MS;
  const detail = stale ? `stale — last ${ageLabel} ago` : `last check ${ageLabel} ago`;
  return { id, label, configured: true, ok: !stale, state: checkState(true, !stale), detail };
}

async function checkVercel(config: StatusConfig): Promise<IntegrationCheck> {
  const id = "vercel";
  const label = "Vercel";
  const token = config.credentials.VERCEL_API_TOKEN;
  const configured = !!token;
  if (!configured) {
    return { id, label, configured, ok: false, state: checkState(false, false), detail: "VERCEL_API_TOKEN not set", missingEnv: ["VERCEL_API_TOKEN"] };
  }
  const hasTeam = !!config.credentials.VERCEL_TEAM_ID;
  try {
    const res = await probe((signal) =>
      fetch("https://api.vercel.com/v2/user", {
        headers: { Authorization: `Bearer ${token}` },
        signal,
      }),
    );
    const ok = res.ok;
    const teamNote = hasTeam ? "" : " (VERCEL_TEAM_ID not set — team-scoped ops may fail)";
    const detail = ok
      ? `reachable${teamNote}`
      : `HTTP ${res.status} — ${res.status === 401 ? "token invalid" : "unexpected error"}${teamNote}`;
    return { id, label, configured, ok, state: checkState(true, ok), detail };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return { id, label, configured, ok: false, state: "error", detail, unreachable: true };
  }
}

async function checkCloudflare(config: StatusConfig): Promise<IntegrationCheck> {
  const id = "cloudflare";
  const label = "Cloudflare";
  const token = config.credentials.CLOUDFLARE_API_TOKEN;
  if (!token) {
    return { id, label, configured: false, ok: false, state: "warn", detail: "CLOUDFLARE_API_TOKEN not set", missingEnv: ["CLOUDFLARE_API_TOKEN"] };
  }
  const configuredAccountId = config.credentials.CLOUDFLARE_ACCOUNT_ID;

  // Resolve the account the SAME way auto-wire does (configured → env → token discovery)
  // so the self-check reflects what wiring actually uses, not just whether the env var is
  // set. Discovery and the scripts probe each get their OWN window so a slow /accounts
  // call can't eat the scripts call's budget and false-alarm "unreachable".
  const acctTimer = withTimeout(TIMEOUT_MS);
  const accountId = await resolveCfAccountId(configuredAccountId, token, acctTimer.signal);
  acctTimer.done();
  if (!accountId) {
    // Token present but the account is neither set nor auto-discoverable (the token sees
    // zero or several accounts) — genuinely broken; the var must be set. Red.
    return {
      id, label, configured: false, ok: false, state: "error",
      detail: "CLOUDFLARE_ACCOUNT_ID not set and could not auto-discover",
      missingEnv: ["CLOUDFLARE_ACCOUNT_ID"],
    };
  }

  try {
    // listWorkerScripts swallows failures into an error result (not a throw), so retry
    // on error — a transient blip recovers, a real outage stays failed and goes red.
    const result = await probe(
      (signal) => listWorkerScripts(accountId, token, signal),
      (v) => "error" in v,
    );
    if ("error" in result) {
      // Only a NO-RESPONSE failure is "unreachable" (debounced as transient). A
      // definitive HTTP/API error (401 revoked token, 403 missing scope) is an
      // immediate, actionable error — not a network blip.
      return result.unreachable
        ? { id, label, configured: true, ok: false, state: "error", detail: `workers/scripts unreachable (${result.error})`, unreachable: true }
        : { id, label, configured: true, ok: false, state: "error", detail: `workers/scripts ${result.error}` };
    }
    const scripts = result.scripts;
    // Account auto-discovered from the token: wiring works, so this is NOT an error — but
    // the var is still expected, so surface it as a (non-red) warning to pin it.
    const discovered = !configuredAccountId?.trim();
    return {
      id, label, configured: true, ok: true,
      state: discovered ? "warn" : "ok",
      detail: discovered
        ? `reachable (${scripts.length} scripts; account auto-discovered — set CLOUDFLARE_ACCOUNT_ID to pin it)`
        : `reachable (${scripts.length} scripts)`,
      missingEnv: discovered ? ["CLOUDFLARE_ACCOUNT_ID"] : undefined,
    };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return { id, label, configured: true, ok: false, state: "error", detail, unreachable: true };
  }
}

async function checkRailway(config: StatusConfig): Promise<IntegrationCheck> {
  const id = "railway";
  const label = "Railway";
  const token = config.credentials.RAILWAY_API_TOKEN;
  const configured = !!token;
  if (!configured) {
    return { id, label, configured, ok: false, state: checkState(false, false), detail: "RAILWAY_API_TOKEN not set", missingEnv: ["RAILWAY_API_TOKEN"] };
  }
  let res: Response;
  try {
    res = await probe((signal) =>
      fetch("https://backboard.railway.app/graphql/v2", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ query: "{ projects(first: 1) { edges { node { id } } } }" }),
        signal,
      }),
    );
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return { id, label, configured, ok: false, state: "error", detail, unreachable: true };
  }
  // Past here the API RESPONDED — a bad status or unparseable body is a definitive
  // error, not "unreachable", so it must not get the transient-network debounce.
  try {
    if (!res.ok) {
      return { id, label, configured, ok: false, state: "error", detail: `HTTP ${res.status}` };
    }
    const body = (await res.json()) as { data?: { projects?: { edges?: unknown[] } }; errors?: { message: string }[] };
    const ok = res.ok && !!body.data?.projects;
    const errMsg = body.errors?.[0]?.message;
    // "Not Authorized" means the token can't enumerate over `Authorization: Bearer` —
    // either it's revoked/invalid, or it's a project-scoped token (those authorize only via
    // the `Project-Access-Token` header, never Bearer, so this poller can't use them at all).
    // Either way the fix is a valid account/team token. Spell that out instead of the bare
    // API message, so the integrations panel is actionable rather than cryptic.
    const detail = ok
      ? "reachable"
      : errMsg === "Not Authorized"
        ? "token unauthorized — it's revoked/invalid or project-scoped; set a valid account/team RAILWAY_API_TOKEN (project tokens don't work here)"
        : (errMsg ?? "token invalid or no projects returned");
    return { id, label, configured, ok, state: checkState(true, ok), detail };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return { id, label, configured, ok: false, state: "error", detail };
  }
}

// Reachability of a telemetry provider the backend polls (GlitchTip / PostHog).
// Missing env → warn (the stream just no-ops); a real HTTP error (401/403/5xx) →
// error. This is what turns the repeating "GlitchTip fetch timed out" log line
// into a first-class health signal on the integrations panel. Each provider probes
// the SAME API surface the telemetry band actually uses, so a green check means
// the band works (and a red one is a real, actionable outage).

function missingWarn(id: string, label: string, missing: string[]): IntegrationCheck {
  return { id, label, configured: false, ok: false, state: "warn", detail: `${missing.join(", ")} not set`, missingEnv: missing };
}

/** Map a reachability probe response to a check; 401/403 → the token/key is invalid. */
function reachability(id: string, label: string, res: Response, invalidWord: string): IntegrationCheck {
  const ok = res.ok;
  const detail = ok ? "reachable" : `HTTP ${res.status}${res.status === 401 || res.status === 403 ? ` — ${invalidWord} invalid` : ""}`;
  return { id, label, configured: true, ok, state: checkState(true, ok), detail };
}

async function checkGlitchtip(config: StatusConfig): Promise<IntegrationCheck> {
  const id = "glitchtip";
  const label = "GlitchTip";
  const { GLITCHTIP_URL, GLITCHTIP_API_TOKEN, GLITCHTIP_ORG } = config.credentials;
  const missing = (["GLITCHTIP_URL", "GLITCHTIP_API_TOKEN", "GLITCHTIP_ORG"] as const).filter(
    (n) => !config.credentials[n],
  );
  if (missing.length) return missingWarn(id, label, missing);
  const base = GLITCHTIP_URL!.replace(/\/+$/, "");
  // Cheap org-metadata GET (NOT the heavy issues query the errors band uses) —
  // reachability + token without the slow source-map/grouping fan-out.
  try {
    const res = await probe((signal) =>
      fetch(`${base}/api/0/organizations/${GLITCHTIP_ORG}/`, {
        headers: { Authorization: `Bearer ${GLITCHTIP_API_TOKEN}` },
        signal,
      }),
    );
    return reachability(id, label, res, "token");
  } catch (err) {
    return { id, label, configured: true, ok: false, state: "error", detail: err instanceof Error ? err.message : String(err), unreachable: true };
  }
}

async function checkPosthog(config: StatusConfig): Promise<IntegrationCheck> {
  const id = "posthog";
  const label = "PostHog";
  const { POSTHOG_HOST, POSTHOG_API_KEY, POSTHOG_PROJECT_ID } = config.credentials;
  const missing = (["POSTHOG_HOST", "POSTHOG_API_KEY", "POSTHOG_PROJECT_ID"] as const).filter(
    (n) => !config.credentials[n],
  );
  if (missing.length) return missingWarn(id, label, missing);
  const base = POSTHOG_HOST!.replace(/\/+$/, "");
  // Probe the SAME HogQL query API the analytics band uses (a trivial `SELECT 1`),
  // NOT the project-metadata endpoint: the personal API key is scoped for the query
  // API and 403s on project-read, so a metadata probe would false-alarm a healthy
  // PostHog. Mirroring real usage means a green check = the analytics band works.
  try {
    const res = await probe((signal) =>
      fetch(`${base}/api/projects/${POSTHOG_PROJECT_ID}/query/`, {
        method: "POST",
        headers: { Authorization: `Bearer ${POSTHOG_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ query: { kind: "HogQLQuery", query: "SELECT 1" } }),
        signal,
      }),
    );
    return reachability(id, label, res, "key");
  } catch (err) {
    return { id, label, configured: true, ok: false, state: "error", detail: err instanceof Error ? err.message : String(err), unreachable: true };
  }
}

// Cross-run debounce/correlation state for the reachability checks. Module-level:
// the check runs per /integrations request and the streaks must survive between
// them. Process-restart resets it, which only re-arms the (short) confirmation
// window — fail-soft.
const selfCheckStability = createSelfCheckStabilizer();

/** Test hook — clear the cross-run failure streaks (mirrors _resetCfAccountCache). */
export function _resetSelfCheckStability(): void {
  selfCheckStability.reset();
}

/**
 * The integrations self-check: stats store + freshness (DB-backed) and provider
 * reachability (Vercel/Cloudflare/Railway deploy providers + GlitchTip/PostHog
 * telemetry providers, env-token based). Each check is isolated with
 * Promise.allSettled so one thrown check never crashes the report; the overall
 * state is the worst of all checks. Unreachable-kind failures (no HTTP response)
 * are stabilized across runs — debounced before surfacing, and correlated
 * multi-provider failures downgrade to a monitor-side Connectivity warning
 * (see self-check-stability).
 */
export async function runIntegrationsCheck(
  db: Db,
  config: StatusConfig,
  nowMs: number = Date.now(),
): Promise<IntegrationsResponse> {
  const results = await Promise.allSettled([
    checkStatsStore(db),
    checkStatsFreshness(db),
    checkVercel(config),
    checkCloudflare(config),
    checkRailway(config),
    checkGlitchtip(config),
    checkPosthog(config),
  ]);

  const checks: IntegrationCheck[] = results.map((r, i) => {
    if (r.status === "fulfilled") return r.value;
    // A check threw unexpectedly — surface as error, never crash the route.
    // Order must match the Promise.allSettled array above.
    const ids = ["stats", "cron", "vercel", "cloudflare", "railway", "glitchtip", "posthog"] as const;
    const labels = ["Stats store", "Stats freshness", "Vercel", "Cloudflare", "Railway", "GlitchTip", "PostHog"] as const;
    return {
      id: ids[i] ?? "unknown",
      label: labels[i] ?? "Unknown",
      configured: false,
      ok: false,
      state: "error" as const,
      detail: r.reason instanceof Error ? r.reason.message : String(r.reason),
    };
  });

  const stabilized = selfCheckStability.stabilize(checks, nowMs);
  return {
    generatedAt: new Date(nowMs).toISOString(),
    overall: overallState(stabilized),
    checks: stabilized,
  };
}
