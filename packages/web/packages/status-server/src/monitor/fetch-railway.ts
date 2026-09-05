import { railwayPhases } from "./deploy-status";
import { shortSha, commitFullMessage } from "./format";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";
import { rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";
import {
  gqlPost,
  listRailwayProjects,
  type RailwayProject,
} from "@agentic-toolkit/deploy-platform/providers";

interface RailwayMeta {
  branch?: string | null;
  commitHash?: string | null;
  commitMessage?: string | null;
  repo?: string | null;
  commitAuthor?: string | null;
  [key: string]: unknown;
}

interface RailwayDeploymentNode {
  id: string;
  status: string;
  createdAt: string;
  staticUrl: string | null;
  meta: RailwayMeta | null;
  environmentId: string | null;
  serviceId: string | null;
}

interface RailwayEdge {
  node: RailwayDeploymentNode;
}

interface RailwayEnvNode {
  id: string;
  name: string;
}

/** Build an environmentId→name map from a Railway `environments.edges` array — the one
 *  place that shape is flattened on this side. (The domains fetch flattens its own copy
 *  inside the vendored `@agentic-toolkit/deploy-platform` provider, which this package
 *  cannot reach into; an earlier version of this comment claimed the two shared this
 *  function.) */
function buildEnvNameMap(edges: { node: RailwayEnvNode }[] | undefined): Record<string, string> {
  const map: Record<string, string> = {};
  for (const e of edges ?? []) map[e.node.id] = e.node.name;
  return map;
}

/**
 * Page size for the environments query — deliberately far above any real project (Railway's
 * own UI treats environments as a handful per project: production plus a few ephemeral PR
 * envs), because the per-row drop below depends on the map being COMPLETE.
 *
 * Pinned rather than left to the server default: an unpinned connection field is whatever
 * page size Railway happens to apply, so "the map is complete" was a premise the code did
 * not establish. If a project ever exceeded it, every deploy in the unlisted environments
 * would be dropped one row at a time — the stored verdict stays `success`, the FAILED row
 * never lands, and no Problem is derived from what is really missing data (constraint 2).
 */
const RAILWAY_ENV_PAGE_SIZE = 200;

/**
 * Per-call time box, and the ONE retry that makes it survivable.
 *
 * Railway's GraphQL is fast in the median and has a very fat tail: measured from inside
 * the prod container, 200 samples of the per-project query ran p50=83ms / p90=138ms /
 * p95=189ms but p99=2237ms with a 3.4s max, and a call on a COLD connection (every poll
 * is cold — the deploy poll runs every 5 minutes, far longer than any keep-alive) added
 * up to 4.2s of TLS setup on top. A 6s box therefore sits inside the tail rather than
 * outside it, and prod logged ~40 self-inflicted `This operation was aborted` failures a
 * day, in same-millisecond bursts as a whole concurrent wave lost together.
 *
 * The tail is INDEPENDENT per request, not sticky to a slow project (the same project
 * measured slow 2 of 20 times and fast the other 18), so a second attempt lands in the
 * 83ms median. That is why the fix is one retry and NOT a longer box: raising the box
 * would make a genuinely stuck project hold its concurrency slot for that much longer,
 * spending the overall budget on the one project least likely to answer.
 *
 * Bounded, so a retry can never widen the poll: the retry re-derives `remaining` from the
 * same overall deadline and is skipped once that is spent.
 */
const RAILWAY_CALL_TIMEOUT_MS = 6_000;
const RAILWAY_CALL_ATTEMPTS = 2;

export async function fetchRailwayDeployments(env: {
  RAILWAY_API_TOKEN?: string;
  projects?: readonly RailwayProject[];
  /** Overall poll budget (ms): stop starting new projects past this and return a
   *  partial. Defaults to 18s (under sync's 20s `guard`); overridable for tests/tuning. */
  overallBudgetMs?: number;
  /** Per-call time box (ms). Defaults to {@link RAILWAY_CALL_TIMEOUT_MS}; overridable so a
   *  test can exercise the retry in milliseconds instead of waiting out a 6s box. */
  callTimeoutMs?: number;
}): Promise<{ ok: boolean; deploys: ProviderDeploy[] }> {
  if (!env.RAILWAY_API_TOKEN) return { ok: true, deploys: [] };
  if (rateLimitedUntil("railway")) return { ok: false, deploys: [] }; // cooling down after a 429
  const token = env.RAILWAY_API_TOKEN;
  const callTimeoutMs = env.callTimeoutMs ?? RAILWAY_CALL_TIMEOUT_MS;
  // The overall budget starts BEFORE the project listing: the listing call is part of
  // the poll, so its time must count against the deadline. Started after it (as this
  // once was), the real worst case ran ~6s listing + the full budget + a last in-flight
  // wave — past sync's 20s `guard`, which then discarded the whole (mostly successful)
  // poll as unreachable.
  const RAILWAY_OVERALL_BUDGET_MS = env.overallBudgetMs ?? 18_000;
  const deadline = Date.now() + RAILWAY_OVERALL_BUDGET_MS;
  // Enumerate all projects the (account/team) token can see; fall back to the configured
  // list only if enumeration didn't return one (a transient failure — a project-scoped or
  // revoked token can't fetch deployments over Bearer either, so the fallback can't rescue it).
  //
  // Retried like the per-project calls below (see RAILWAY_CALL_TIMEOUT_MS): this is the
  // FIRST call of the poll and therefore always the coldest, and losing it costs the most —
  // enumeration returns null and the poll falls back to the configured list or reports the
  // token as unable to see anything.
  let listed: RailwayProject[] | null = null;
  for (let attempt = 0; attempt < RAILWAY_CALL_ATTEMPTS; attempt++) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    const listController = new AbortController();
    const listTimer = setTimeout(() => listController.abort(), Math.min(callTimeoutMs, remaining));
    try {
      listed = await listRailwayProjects(token, listController.signal);
    } finally {
      clearTimeout(listTimer);
    }
    // Only OUR box firing earns a second try. A listing that answered — including one that
    // answered "not authorized" — is a real verdict, and repeating it just burns budget.
    if (listed !== null || !listController.signal.aborted) break;
  }
  const projects = listed ?? (env.projects ?? []).slice();
  if (projects.length === 0) {
    // `listed === null` means the token couldn't enumerate — it's revoked/invalid or
    // project-scoped (project tokens return "Not Authorized" over Bearer). With no
    // configured fallback projects either, we hold a token yet can see nothing — a
    // misconfiguration, NOT a genuinely empty account. Report ok:false so a platform-health
    // issue fires (matching the integrations self-check, which already flags this token),
    // instead of silently showing zero Railway deploys. `listed === []` is an authorized,
    // genuinely-empty account → legitimately ok.
    return { ok: listed !== null, deploys: [] };
  }
  // Poll projects with BOUNDED concurrency, not serially. A serial `for..of` makes
  // total time N×6s — with enough projects and a degraded Railway API that alone
  // blows the cycle budget and wedges the whole monitor. Capped fan-out keeps it
  // ~⌈N/5⌉×6s so the poll finishes well within `guard`'s cap in sync.ts.
  const RAILWAY_PROJECT_CONCURRENCY = 5;
  // Once the budget (started above, before the listing) is spent, stop starting new
  // projects and RETURN what we already fetched, instead of running past 20s and having
  // `guard` discard the whole poll as "unreachable" — which is why a large/slow Railway
  // account showed ZERO deploys (and never surfaced a build failure) on EVERY cycle.
  // `skipped` marks the poll partial so the caller upserts what we got (the failure
  // lands) but treats the provider as not-fully-ok.
  let skipped = false;
  /**
   * One project's poll under ONE time box. Reports `aborted` separately from `error` so the
   * caller can tell OUR box firing — retryable, see {@link RAILWAY_CALL_TIMEOUT_MS} — from
   * Railway answering with a failure, which is a real verdict and not worth repeating.
   */
  const pollProject = async (
    projectId: string,
    projectName: string,
    boxMs: number,
  ): Promise<{ rows: ProviderDeploy[]; error: boolean; aborted: boolean }> => {
    const controller = new AbortController();
    // Never let a per-project fetch run past the overall budget, so the whole poll
    // stays under `guard`'s cap and returns partial instead of being abandoned.
    const timer = setTimeout(() => controller.abort(), boxMs);
    try {
      // Fetch environment id→name map once per project.
      //
      // A FAILURE HERE IS A PROVIDER FAILURE, not a partial success. Railway is the one
      // platform whose board target carries the environment segment
      // (`railway|<project>|<env>`), so a project polled without its env map produced rows
      // keyed by the raw environmentId UUID: they matched no roster entry in either index,
      // `ownedDeployTarget` returned null, and every Railway deploy went INVISIBLE. A
      // Railway build that failed during an env-map outage yielded no Problem at all and
      // the board went on reporting the last-known state as current — an absence of data
      // rendering as health. Erroring the project instead routes it to the existing
      // platform-unreachable path (`platformHealthState` + PLATFORM_UNREACHABLE_POLLS), so
      // a real outage is reported as one, debounced, exactly like every other provider.
      const envQuery = `query($id: String!, $first: Int!) { environments(projectId: $id, first: $first) { edges { node { id name } } } }`;
      const envRes = await gqlPost(token, envQuery, controller.signal, {
        id: projectId,
        first: RAILWAY_ENV_PAGE_SIZE,
      });
      if (!envRes.ok) {
        console.error(`Railway environments ${projectId} ${envRes.status}`);
        return { rows: [] as ProviderDeploy[], error: true, aborted: false };
      }
      const envBody = (await envRes.json()) as {
        data?: { environments?: { edges?: { node: RailwayEnvNode }[] } };
        errors?: { message: string }[];
      };
      if (envBody.errors?.length || !envBody.data?.environments) {
        // A 200 carrying GraphQL errors, or a body with no `environments` payload at all.
        // `edges: []` is NOT this case: that is an authorized, genuinely env-less project,
        // and it legitimately yields an empty map.
        console.error(
          `Railway environments ${projectId} unusable:`,
          envBody.errors?.map((e) => e.message).join("; ") ?? "no environments payload",
        );
        return { rows: [] as ProviderDeploy[], error: true, aborted: false };
      }
      const envEdges = envBody.data.environments.edges ?? [];
      // A full page is the one shape that could make the map incomplete, and the per-row
      // drop below would then read as "these environments were deleted". Never silent:
      // logged here, at the read, where the truncation is visible — the drop itself cannot
      // tell the two apart. NOT an error for the project: it is reachable and answering, so
      // routing it to the platform-unreachable debounce would report the wrong outage.
      if (envEdges.length >= RAILWAY_ENV_PAGE_SIZE) {
        console.error(
          `Railway environments ${projectId} returned a FULL page (${envEdges.length}) — the env map may be truncated and deploys in unlisted environments will be dropped`,
        );
      }
      const envNameById = buildEnvNameMap(envEdges);

      // Fetch deployments — meta is a JSON scalar; do NOT sub-select fields.
      const deplQuery = `query($id: String!) { deployments(first: 20, input: { projectId: $id }) { edges { node { id status createdAt staticUrl meta environmentId serviceId } } } }`;
      const deplRes = await gqlPost(token, deplQuery, controller.signal, { id: projectId });
      if (!deplRes.ok) {
        console.error(`Railway ${projectId} ${deplRes.status}`);
        return { rows: [] as ProviderDeploy[], error: true, aborted: false };
      }

      const deplBody = (await deplRes.json()) as {
        data?: { deployments?: { edges?: RailwayEdge[] } };
        errors?: { message: string }[];
      };

      if (deplBody.errors?.length) {
        console.error(`Railway ${projectId} GraphQL errors:`, deplBody.errors.map((e) => e.message).join("; "));
        return { rows: [] as ProviderDeploy[], error: true, aborted: false };
      }

      const edges = deplBody.data?.deployments?.edges ?? [];

      const rows: ProviderDeploy[] = edges.flatMap(({ node }) => {
        const meta = node.meta as RailwayMeta | null;
        // Boundary validation: an unparseable createdAt would poison the upsert
        // (failing the whole cycle) — drop that deploy, keep the project's rest.
        const createdAt = toValidDate(node.createdAt);
        if (!createdAt) {
          console.error(`Railway deployment ${node.id} has unparseable createdAt ${JSON.stringify(node.createdAt)} — skipping`);
          return [];
        }
        // The map above is complete for this project BECAUSE the query pins
        // `first: RAILWAY_ENV_PAGE_SIZE` (and a full page is logged as possibly truncated),
        // so an id missing from it names an environment Railway no longer has (deleted
        // after the deploy) rather than one that fell off an unpinned page.
        // Drop the row rather than key it by the raw UUID or by an EMPTY env segment: the
        // first mints a target nothing can ever match, and the second would collide with
        // an environment-less roster entry and hand this orphan deploy to the wrong site.
        const environment = envNameById[node.environmentId ?? ""] ?? null;
        if (environment === null) {
          console.error(`Railway deployment ${node.id} references unknown environment ${JSON.stringify(node.environmentId)} — skipping`);
          return [];
        }
        return {
          id: `ry_${node.id}`,
          platform: "railway",
          // The Railway PROJECT name (from config), not the GitHub repo behind the
          // service — a row is "<project> <environment>", e.g. "adh-backend testing".
          projectName,
          providerProjectId: projectId,
          ...railwayPhases(node.status),
          // The REAL Railway environment name (production/staging/testing) — Railway
          // reports it directly, so it drives the env badge (unlike Vercel, where
          // env is encoded in the project name). Always a resolved NAME, never an id.
          environment,
          commitHash: typeof meta?.commitHash === "string" ? shortSha(meta.commitHash) : null,
          commitMessage: typeof meta?.commitMessage === "string" ? commitFullMessage(meta.commitMessage) : null,
          branch: typeof meta?.branch === "string" ? meta.branch : null,
          // "owner/name" from Railway's git metadata — for the GitHub commit link.
          commitRepo: typeof meta?.repo === "string" && meta.repo.includes("/") ? meta.repo : null,
          // The deploy "url" is the SOURCE link target. For Railway that's the
          // project dashboard (where you debug the deploy), NOT the live static URL —
          // the public/live url is resolved from liveHost (stamped from config in sync).
          url: `https://railway.com/project/${projectId}`,
          createdAt,
        };
      });

      return { rows, error: false, aborted: false };
    } catch (err) {
      // Our own box firing is not news, and it is not reported here: the caller says so
      // once, after the retry has ALSO lost. Logging it at this level printed a ten-line
      // undici stack trace for every transient loss, which is most of what the Railway
      // errors in the deploy log were.
      if (controller.signal.aborted) return { rows: [] as ProviderDeploy[], error: true, aborted: true };
      console.error("Railway fetch", err);
      return { rows: [] as ProviderDeploy[], error: true, aborted: false };
    } finally {
      clearTimeout(timer);
    }
  };

  const perProject = await mapLimit(projects, RAILWAY_PROJECT_CONCURRENCY, async ({ id: projectId, name: projectName }) => {
    for (let attempt = 1; attempt <= RAILWAY_CALL_ATTEMPTS; attempt++) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        // Budget spent. Before the FIRST attempt this project was never polled — a
        // partial, exactly as before. Before a RETRY it WAS polled and timed out, which is
        // the provider failing us rather than a project we chose not to start.
        if (attempt === 1) skipped = true;
        return { rows: [] as ProviderDeploy[], error: attempt > 1 };
      }
      const res = await pollProject(projectId, projectName, Math.min(callTimeoutMs, remaining));
      if (!res.aborted) return { rows: res.rows, error: res.error };
      if (attempt === RAILWAY_CALL_ATTEMPTS) {
        // Timed out on every attempt: report it ONCE, as the provider failing. That routes
        // to the existing platform-unreachable debounce (PLATFORM_UNREACHABLE_POLLS) rather
        // than rendering the project as legitimately deploy-less.
        console.error(`Railway ${projectId} timed out on all ${RAILWAY_CALL_ATTEMPTS} attempts`);
        return { rows: [] as ProviderDeploy[], error: true };
      }
    }
    // Unreachable — every path inside the loop returns.
    return { rows: [] as ProviderDeploy[], error: true };
  });

  const deploys = perProject.flatMap((p) => p.rows);
  const anyError = perProject.some((p) => p.error);
  // A partial poll (some projects skipped for budget) is not fully ok — but the deploys
  // we DID fetch are still upserted by the caller, so a build failure that was reached
  // lands even when the account is too large to poll within one budget.
  return { ok: !anyError && !skipped, deploys };
}

interface RailwayLogLine {
  message: string;
  severity?: string | null;
  timestamp?: string | null;
}

/** How many trailing build-log lines to keep, and the overall char cap — a failed
 *  build's reason is at the END of the log, so we keep the tail. Bounded so a huge
 *  build log can't bloat a stored row or the details pane. */
const RAILWAY_LOG_TAIL_LINES = 40;
const RAILWAY_LOG_MAX_CHARS = 4_000;

/** The trailing slice of a build log as one string — the last
 *  {@link RAILWAY_LOG_TAIL_LINES} non-blank lines, capped to
 *  {@link RAILWAY_LOG_MAX_CHARS} (keeping the END, where a failure lands). Null
 *  when empty. Pure — the network-free half of {@link fetchRailwayBuildLogTail},
 *  unit-tested directly. */
export function buildLogTail(messages: (string | null | undefined)[]): string | null {
  const lines = messages.map((m) => m?.trimEnd()).filter((m): m is string => Boolean(m && m.length));
  if (lines.length === 0) return null;
  const tail = lines.slice(-RAILWAY_LOG_TAIL_LINES).join("\n");
  return tail.length > RAILWAY_LOG_MAX_CHARS ? `…${tail.slice(-RAILWAY_LOG_MAX_CHARS)}` : tail;
}

/** What enrichment stores for a Railway deployment that PERMANENTLY has no build
 *  logs (skipped/removed before building). Writing a real value (instead of
 *  leaving error_text null) takes the row out of the enrichment candidate set —
 *  otherwise it re-fetches, and logs the same GraphQL error, EVERY cycle. */
export const RAILWAY_NO_BUILD_TEXT = "(no build logs — the deployment has no associated build)";

/** How many lines the FULL build-log read asks for. Railway's buildLogs takes a
 *  limit, so "all" has to be a number; 10k lines is past any build we run and
 *  still bounded — the point of the full read is that the cause of a failure is
 *  usually far above the last line, not that the log is literally unbounded. */
const RAILWAY_LOG_FULL_LINES = 10_000;

/** Every build-log line as one string, oldest-first and untruncated. Null when
 *  empty. Pure — the network-free half of {@link fetchRailwayBuildLog}. */
export function buildLogFull(messages: (string | null | undefined)[]): string | null {
  const lines = messages.map((m) => m?.trimEnd()).filter((m): m is string => Boolean(m && m.length));
  return lines.length > 0 ? lines.join("\n") : null;
}

/** The permanent "this deployment never built" answer, distinguished from a
 *  transient failure (null) so each caller can render it in its own shape. */
const NO_BUILD = Symbol("railway-no-build");

/**
 * The raw build-log messages for ONE Railway deployment, oldest-first — the shared
 * network half of {@link fetchRailwayBuildLogTail} and {@link fetchRailwayBuildLog},
 * which differ only in how many lines they ask for and how they shape the result.
 * Returns {@link NO_BUILD} for the permanent no-associated-build condition and null
 * for any transient failure.
 */
async function railwayBuildLogMessages(
  deploymentId: string,
  token: string,
  signal: AbortSignal,
  limit: number,
): Promise<string[] | typeof NO_BUILD | null> {
  try {
    const query = `query($id: String!, $limit: Int) { buildLogs(deploymentId: $id, limit: $limit) { message severity timestamp } }`;
    const res = await gqlPost(token, query, signal, { id: deploymentId, limit });
    if (!res.ok) {
      console.error(`Railway buildLogs ${deploymentId} ${res.status}`);
      return null;
    }
    const body = (await res.json()) as { data?: { buildLogs?: RailwayLogLine[] }; errors?: { message: string }[] };
    if (body.errors?.length) {
      // "Deployment does not have an associated build" is a PERMANENT condition
      // (skipped/removed deploys) — persist a placeholder so this id never
      // re-enriches; retrying it forever only spams this log line every cycle.
      if (body.errors.some((e) => /does not have an associated build/i.test(e.message))) {
        return NO_BUILD;
      }
      console.error(`Railway buildLogs ${deploymentId} GraphQL errors:`, body.errors.map((e) => e.message).join("; "));
      return null;
    }
    return (body.data?.buildLogs ?? []).map((l) => l.message);
  } catch (err) {
    console.error(`Railway buildLogs ${deploymentId} fetch failed`, err);
    return null;
  }
}

/**
 * The tail of ONE failed Railway deployment's build log — Railway has no single
 * error field (unlike Vercel), so the reason lives in the build output. `deploymentId`
 * is the raw Railway deployment id (no `ry_` prefix). buildLogs returns lines in
 * chronological order, so the failure is at the end (see {@link buildLogTail}).
 * Returns null when there are no logs or the fetch fails (enrichment retries next cycle);
 * a deployment Railway says HAS no build gets {@link RAILWAY_NO_BUILD_TEXT} — a permanent
 * answer, not a retry.
 */
export async function fetchRailwayBuildLogTail(
  deploymentId: string,
  token: string,
  signal: AbortSignal,
): Promise<string | null> {
  const messages = await railwayBuildLogMessages(deploymentId, token, signal, 200);
  if (messages === NO_BUILD) return RAILWAY_NO_BUILD_TEXT;
  return messages === null ? null : buildLogTail(messages);
}

/**
 * The COMPLETE build log for ONE Railway deployment — the on-demand read behind
 * `GET /deployments/:id/log`, as opposed to the bounded tail enrichment persists.
 * Null when there are no logs or the fetch fails; a buildless deployment gets the
 * same {@link RAILWAY_NO_BUILD_TEXT} sentence the tail does, so both surfaces say
 * the same thing about the same deployment.
 */
export async function fetchRailwayBuildLog(
  deploymentId: string,
  token: string,
  signal: AbortSignal,
): Promise<string | null> {
  const messages = await railwayBuildLogMessages(deploymentId, token, signal, RAILWAY_LOG_FULL_LINES);
  if (messages === NO_BUILD) return RAILWAY_NO_BUILD_TEXT;
  return messages === null ? null : buildLogFull(messages);
}
