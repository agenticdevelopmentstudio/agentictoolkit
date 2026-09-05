import { vercelPhases } from "./deploy-status";
import { shortSha, commitFullMessage } from "./format";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";
import { noteRateLimited, rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";

interface VercelDeployment {
  uid: string;
  name: string;
  projectId?: string;
  url?: string;
  created: number;
  state: string;
  readySubstate?: string | null;
  target?: string | null;
  inspectorUrl?: string | null;
  meta?: {
    githubCommitSha?: string;
    githubCommitMessage?: string;
    githubCommitRef?: string;
    githubCommitOrg?: string;
    githubCommitRepo?: string;
  };
}

/** Per-page call timeout. Vercel's `fetch` has NO default timeout — without this an
 *  unresponsive API hangs the poll indefinitely. `guard` in sync.ts caps the poll, but
 *  only an AbortSignal actually releases the socket instead of leaking it each cycle. */
const DEPLOYS_CALL_TIMEOUT_MS = 8_000;

/** Total wall-clock budget across ALL pages, self-bound like the projects poll:
 *  sync's `guard` abandons a provider at 20s WITHOUT cancelling it, so an unbounded
 *  loop keeps paginating behind the next cycle. Observed cost is ~0.75s for 3 pages. */
const DEPLOYS_OVERALL_BUDGET_MS = 12_000;

/** How far back the poll must see. ONE page is only the newest 100 deployments
 *  TEAM-WIDE, which during a burst is a matter of SECONDS: a push touching a shared
 *  path rebuilds ~90 sites at once (135 projects exist), and a measured 225-deploy
 *  burst had its newest 100 spanning just 74 SECONDS. Every older deploy was then
 *  invisible to the poll — permanently, because nothing newer ever pushes it back
 *  into view — so those rows stayed `building` until the by-id reconcile picked them
 *  off at 10 per 60s tick: ~9 minutes of the board asserting "building" for sites
 *  that had long finished. 30 minutes spans any burst this repo can produce. */
const DEPLOYS_LOOKBACK_MS = 30 * 60_000;

/** Hard page cap (500 deploys) so a pathological history can't spin. */
const MAX_PAGES = 5;

export async function fetchVercelDeployments(env: {
  VERCEL_API_TOKEN?: string;
  VERCEL_TEAM_ID?: string;
  overallBudgetMs?: number;
}): Promise<{ ok: boolean; deploys: ProviderDeploy[] }> {
  if (!env.VERCEL_API_TOKEN) return { ok: true, deploys: [] };
  if (rateLimitedUntil("vercel")) return { ok: false, deploys: [] }; // cooling down after a 429

  const deadline = Date.now() + (env.overallBudgetMs ?? DEPLOYS_OVERALL_BUDGET_MS);
  const list: VercelDeployment[] = [];
  let until: number | undefined;
  let skipped = false;

  // Paginate via pagination.next until the lookback window is covered — the same
  // shape (and partial contract) as fetchVercelProductionStates and the Railway /
  // Cloudflare fetchers: hand back what we managed with ok:false, so the caller
  // upserts the partial and skips the prune rather than treating gaps as verdicts.
  for (let page = 0; page < MAX_PAGES; page++) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      skipped = true;
      break;
    }
    const url = new URL("https://api.vercel.com/v6/deployments");
    url.searchParams.set("limit", "100");
    if (env.VERCEL_TEAM_ID) url.searchParams.set("teamId", env.VERCEL_TEAM_ID);
    if (until) url.searchParams.set("until", String(until));

    let body: { deployments?: VercelDeployment[]; pagination?: { next: number | null } };
    try {
      const res = await fetch(url.toString(), {
        headers: { Authorization: `Bearer ${env.VERCEL_API_TOKEN}` },
        signal: AbortSignal.timeout(Math.min(DEPLOYS_CALL_TIMEOUT_MS, remaining)),
      });
      if (!res.ok) {
        if (res.status === 429) noteRateLimited("vercel", res.headers.get("retry-after"));
        console.error(`Vercel API ${res.status}`);
        // Page 0 failing is definitive (nothing fetched). A later page failing must
        // NOT wipe the pages already fetched — keep them and hand back a partial.
        if (page === 0) return { ok: false, deploys: [] };
        skipped = true;
        break;
      }
      body = (await res.json()) as { deployments?: VercelDeployment[]; pagination?: { next: number | null } };
    } catch (err) {
      // Concise, no stack: an aborted/stalled poll is expected transient noise — the
      // cycle degrades to ok:false and the next full sync retries.
      console.error(`Vercel deployments fetch failed: ${err instanceof Error ? err.message : String(err)}`);
      if (page === 0) return { ok: false, deploys: [] };
      skipped = true;
      break;
    }

    const got = body.deployments ?? [];
    list.push(...got);
    // Stop as soon as the window is covered — the poll only needs to see deploys new
    // enough to still be in flight; older history is the reconcile's problem.
    const oldest = got.length > 0 ? Math.min(...got.map((d) => d.created)) : undefined;
    if (oldest !== undefined && Number.isFinite(oldest) && oldest <= Date.now() - DEPLOYS_LOOKBACK_MS) break;
    const next = body.pagination?.next;
    if (!next) break; // history exhausted
    until = next;
  }

  {
    const deploys: ProviderDeploy[] = [];
    for (const d of list) {
      // Boundary validation: a deploy whose `created` doesn't parse can't be
      // ordered or reconciled, and an Invalid Date poisons the upsert (failing
      // the whole cycle). Drop THAT deploy, keep the rest — the poll repeats.
      const createdAt = toValidDate(d.created);
      if (!createdAt) {
        console.error(`Vercel deployment ${d.uid} has unparseable created ${JSON.stringify(d.created)} — skipping`);
        continue;
      }
      deploys.push({
        id: `vc_${d.uid}`,
        platform: "vercel",
        projectName: d.name,
        providerProjectId: d.projectId ?? null,
        ...vercelPhases(d.state, d.readySubstate, d.target ?? null),
        environment: d.target ?? null,
        commitHash: shortSha(d.meta?.githubCommitSha),
        commitMessage: commitFullMessage(d.meta?.githubCommitMessage),
        branch: d.meta?.githubCommitRef ?? null,
        commitRepo:
          d.meta?.githubCommitOrg && d.meta?.githubCommitRepo
            ? `${d.meta.githubCommitOrg}/${d.meta.githubCommitRepo}`
            : null,
        url: d.inspectorUrl ?? (d.url ? `https://${d.url}` : null),
        createdAt,
      });
    }
    // `ok:false` on a partial: the rows we DID fetch are still upserted, but the
    // caller must not read absence as a verdict (skips the prune) — the contract the
    // projects/Railway/Cloudflare fetchers already carry.
    return { ok: !skipped, deploys };
  }
}

interface VercelDeploymentDetail {
  errorMessage?: string | null;
  errorStep?: string | null;
  readyStateReason?: string | null;
}

/** Compose the one-line failure reason from a Vercel deployment detail: the
 *  `errorMessage` (falling back to `readyStateReason`), prefixed with the failing
 *  build step when Vercel names one. Null when there's no reason at all. Pure —
 *  the network-free half of {@link fetchVercelDeployError}, unit-tested directly. */
export function composeVercelDeployError(d: VercelDeploymentDetail): string | null {
  const reason = d.errorMessage?.trim() || d.readyStateReason?.trim() || null;
  if (!reason) return null;
  const step = d.errorStep?.trim();
  return step ? `[${step}] ${reason}` : reason;
}

/**
 * The human-readable failure reason for ONE failed Vercel deployment, from the
 * per-deployment endpoint (the list endpoint omits it). `uid` is the raw Vercel
 * deployment id (no `vc_` prefix). Returns null when the deployment carries no
 * error text or the fetch fails — enrichment simply retries next cycle.
 */
export async function fetchVercelDeployError(
  uid: string,
  env: { VERCEL_API_TOKEN?: string; VERCEL_TEAM_ID?: string },
  signal?: AbortSignal,
): Promise<string | null> {
  if (!env.VERCEL_API_TOKEN) return null;
  if (rateLimitedUntil("vercel")) return null; // cooling down — retry a later cycle
  const url = new URL(`https://api.vercel.com/v13/deployments/${encodeURIComponent(uid)}`);
  if (env.VERCEL_TEAM_ID) url.searchParams.set("teamId", env.VERCEL_TEAM_ID);
  try {
    const res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${env.VERCEL_API_TOKEN}` },
      signal: signal ?? AbortSignal.timeout(8_000),
    });
    if (res.status === 429) {
      noteRateLimited("vercel", res.headers.get("retry-after"));
      return null;
    }
    if (!res.ok) {
      console.error(`Vercel deployment ${uid} detail ${res.status}`);
      return null;
    }
    return composeVercelDeployError((await res.json()) as VercelDeploymentDetail);
  } catch (err) {
    console.error(`Vercel deployment ${uid} detail fetch failed: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

/** One entry from `GET /v3/deployments/:id/events`. Build output arrives as
 *  `stdout`/`stderr`/`command` events whose text is on `payload.text`; the other
 *  types (deployment-state, metric, …) carry none and are dropped. */
interface VercelBuildEvent {
  type?: string;
  created?: number;
  payload?: { text?: string | null } | null;
}

/** The WHOLE build log as one string: every event's text, in the order the API
 *  returned it, trailing whitespace trimmed per event so the join doesn't
 *  double-space. Null when the deployment emitted no output at all. Pure — the
 *  network-free half of {@link fetchVercelBuildLog}, unit-tested directly.
 *
 *  Deliberately NOT truncated (unlike the Railway tail used for enrichment): this
 *  feeds an on-demand read, and a build failure's cause is often hundreds of lines
 *  above the final "exited with 1" — the reason the one-line `error_text` is not
 *  enough to diagnose a failure from. */
export function composeVercelBuildLog(events: VercelBuildEvent[]): string | null {
  const lines = events
    .map((e) => e?.payload?.text)
    .filter((t): t is string => typeof t === "string" && t.trim().length > 0)
    .map((t) => t.replace(/\s+$/, ""));
  return lines.length > 0 ? lines.join("\n") : null;
}

/** A full build log is far bigger than the single-field reads, and is fetched on
 *  demand by a human waiting on the answer — give it more room than the 8s poll
 *  timeout without letting it hang. */
const BUILD_LOG_CALL_TIMEOUT_MS = 20_000;

/**
 * The COMPLETE build log for ONE Vercel deployment. `uid` is the raw Vercel
 * deployment id (no `vc_` prefix). `limit=-1` asks for every available line and
 * `direction=forward` returns them oldest-first, so the output reads like a
 * terminal transcript. Omitting `follow` keeps the response a plain JSON array
 * rather than an infinite stream.
 *
 * Returns null when the deployment has no log, the token is missing, Vercel is in
 * cooldown, or the fetch fails — every one of which the caller renders as "no log
 * available" rather than an error, since a log is supplementary to the issue.
 */
export async function fetchVercelBuildLog(
  uid: string,
  env: { VERCEL_API_TOKEN?: string; VERCEL_TEAM_ID?: string },
  signal?: AbortSignal,
): Promise<string | null> {
  if (!env.VERCEL_API_TOKEN) return null;
  if (rateLimitedUntil("vercel")) return null;
  const url = new URL(`https://api.vercel.com/v3/deployments/${encodeURIComponent(uid)}/events`);
  url.searchParams.set("builds", "1");
  url.searchParams.set("direction", "forward");
  url.searchParams.set("limit", "-1");
  if (env.VERCEL_TEAM_ID) url.searchParams.set("teamId", env.VERCEL_TEAM_ID);
  try {
    const res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${env.VERCEL_API_TOKEN}` },
      signal: signal ?? AbortSignal.timeout(BUILD_LOG_CALL_TIMEOUT_MS),
    });
    if (res.status === 429) {
      noteRateLimited("vercel", res.headers.get("retry-after"));
      return null;
    }
    if (!res.ok) {
      console.error(`Vercel deployment ${uid} events ${res.status}`);
      return null;
    }
    const body = await res.json();
    return composeVercelBuildLog(Array.isArray(body) ? (body as VercelBuildEvent[]) : []);
  } catch (err) {
    console.error(`Vercel deployment ${uid} events fetch failed: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}
