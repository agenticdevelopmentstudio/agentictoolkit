import { timeAgo } from "./time-ago";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import { vercelPhases } from "./deploy-status";
import { shortSha, commitFullMessage } from "./format";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";
import { noteRateLimited, rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";

/** Per-request cap on a projects/teams call. These fetches used to carry NO timeout at
 *  all, so one hung socket could stall the poll indefinitely. */
const PROJECTS_CALL_TIMEOUT_MS = 6_000;

/** Attempts per page — see the retry rationale at the fetch itself. Two, not more: a
 *  page that loses twice is a real stall, and each attempt re-downloads a multi-MB body. */
const PROJECTS_CALL_ATTEMPTS = 2;

/** Say which of the three truncation causes fired, so the deploy log names the actual
 *  fault instead of always blaming the budget. Silent on a clean enumeration. */
function reportTruncation(reason: "budget" | "page-error" | "page-timeout" | null): void {
  if (!reason) return;
  const why = {
    budget: "overall budget exceeded",
    "page-error": "a page was refused by the API",
    "page-timeout": `a page timed out ${PROJECTS_CALL_ATTEMPTS}x`,
  }[reason];
  console.error(`[vercel-projects] ${why} — returning partial`);
}

/** Overall budget for the whole poll — under sync's 20s `guard`, so we return a partial
 *  ourselves rather than being abandoned by it (an abandoned poll is never cancelled and
 *  keeps running behind the next cycle). Matches the Railway/Cloudflare fetchers. */
const PROJECTS_OVERALL_BUDGET_MS = 18_000;

// ---------------------------------------------------------------------------
// Vercel production "staleness" — the live production deployment vs the latest
// build.
//
// The fold (`deployProblems`) judges the LATEST deploy per target, so a project
// whose newest build is READY reads as "all good" — even when the deployment
// actually SERVING production is an old, errored one that was never promoted.
// That's a real, invisible outage: the site is frozen on a stale (or broken)
// build while newer builds pile up unpromoted.
//
// `targets.production` is Vercel's authoritative "what is live on production
// right now". We compare it to the newest READY production build and flag the
// project when the live one errored or is behind.
// ---------------------------------------------------------------------------

export interface VercelDeploymentSummary {
  id?: string;
  createdAt?: number;
  readyState?: string;
  readySubstate?: string | null;
  target?: string | null;
  url?: string;
  alias?: string[];
  meta?: {
    githubCommitSha?: string;
    githubCommitMessage?: string;
    githubCommitRef?: string;
    githubCommitOrg?: string;
    githubCommitRepo?: string;
  };
}

interface VercelProject {
  id?: string;
  name: string;
  targets?: { production?: VercelDeploymentSummary | null } | null;
  latestDeployments?: VercelDeploymentSummary[] | null;
  rootDirectory?: string | null;
  framework?: string | null;
  link?: { type?: string; org?: string; repo?: string; productionBranch?: string | null } | null;
}

/** Descriptive per-project config for the project browser (not the correlation key). */
export interface VercelProjectMeta {
  projectName: string;
  domain: string | null;
  gitRepo: string | null;
  gitBranch: string | null;
  rootDirectory: string | null;
  framework: string | null;
}

/** A project's production-promotion state. `stale` drives the issue; the rest are the issue's fields. */
export interface VercelProdState {
  projectName: string;
  stale: boolean;
  detail: string | null; // why it's stale (null when healthy)
  sourceUrl: string | null; // Vercel project deployments page
  liveUrl: string | null; // the live production url, if resolvable
}

/**
 * Is the live production deployment stale? Stale = its build ERRORED, or a newer
 * READY production build exists that was never promoted to be the live one.
 * (Pure — the heart of the check, kept separate from the network fetch.)
 *
 * `targets.production` is NOT reliably "what is live": Vercel points it at the newest
 * production-targeted deployment whatever its outcome, and the Ignored Build Step cancels
 * one for every site a commit didn't touch — so for a low-churn site it is usually a SKIP
 * that never served a byte. Judging that skip disarms BOTH signals at once: `errored` is
 * false (a skip is not an ERROR) and the skip's timestamp out-dates every READY build, so
 * `behind` is false too — the check silently reports healthy however broken production is.
 * A skip leaves the PREVIOUS deployment serving, so the live one is the newest CONCLUSIVE
 * production deployment. `liveCreated` is returned so the caller's detail line and
 * inspector link point at the deployment actually judged, not the skip.
 */
export function evaluateProdStaleness(
  live: VercelDeploymentSummary,
  latestDeployments: VercelDeploymentSummary[],
): { stale: boolean; errored: boolean; behind: boolean; live: VercelDeploymentSummary; liveCreated: number } {
  const prod = latestDeployments.filter((d) => d.target === "production");
  const newestOf = (list: VercelDeploymentSummary[]): VercelDeploymentSummary | null =>
    list.reduce<VercelDeploymentSummary | null>((max, d) => (!max || (d.createdAt ?? 0) > (max.createdAt ?? 0) ? d : max), null);

  // When `live` is conclusive it IS the answer to both questions — this is the untouched
  // pre-skip behaviour. Only a skip forces us to reconstruct, and the two signals need
  // DIFFERENT reconstructions:
  //   - `errored` asks "did the last real attempt on production fail?" → newest CONCLUSIVE.
  //   - `behind` asks "is a newer READY build sitting unpromoted?" → it must measure against
  //     what is actually SERVING, i.e. the newest PROMOTED deployment. Measuring against the
  //     newest conclusive would compare that unpromoted build to itself and report healthy —
  //     killing the very signal this check exists for.
  const attempt = isConclusive(live) ? live : newestOf(prod.filter(isConclusive));
  const promoted = newestOf(prod.filter((d) => d.readySubstate === "PROMOTED"));
  const serving = isConclusive(live) ? live : (promoted ?? attempt ?? live);

  const liveCreated = serving.createdAt ?? 0;
  const errored = attempt?.readyState === "ERROR";
  const newestReady = prod
    .filter((d) => d.readyState === "READY")
    .reduce((max, d) => Math.max(max, d.createdAt ?? 0), 0);
  const behind = newestReady > liveCreated;
  return { stale: errored || behind, errored, behind, live: serving, liveCreated };
}

/** The human detail line for a stale production project. */
export function staleDetail(errored: boolean, behind: boolean, liveCreated: number, nowMs: number): string {
  const reason = errored
    ? behind
      ? "live production build errored; newer build not promoted"
      : "live production build errored"
    : "production not updated to the latest build";
  const liveDate = toValidDate(liveCreated || null); // 0 = "unknown", not epoch
  const age = liveDate ? timeAgo(liveDate.toISOString(), nowMs) : null;
  return age ? `${reason} · live build ${age} old` : reason;
}

/**
 * The team's URL slug — needed to build human Vercel dashboard links
 * (`vercel.com/<slug>/<project>`). Resolved defensively so the project links
 * don't silently disappear: prefer the configured team, but fall back to listing
 * the token's teams. A team-scoped token returns its deployments WITHOUT a
 * `VERCEL_TEAM_ID` (which is why deploy rows still link), yet the dashboard URL
 * still needs the slug — so an unset/failed team id must not strand us at null.
 *
 * `deadlineMs` is the poll's OVERALL deadline (an absolute epoch ms, deliberately not a
 * "budget left" delta — a delta computed by the caller and immediately re-added to
 * `Date.now()` here silently gifts back whatever time passed in between). The slug is
 * decoration on top of the enumeration, so it may only ever spend what the enumeration
 * didn't need: on 2026-07-26 production logged `Vercel team lookup /v2/teams/team_…
 * failed: aborted due to timeout`, and because the lookup ran FIRST and off the same
 * deadline, two 6s timeouts could take 12s of the 18s budget and truncate the page walk
 * behind it. A truncated walk is `ok:false`, which makes the caller skip the
 * `deploy_project_meta` prune AND skip narrowing the owned target set — so a project
 * deleted at Vercel keeps its unclearable Problem. Never let the link outrank the data.
 *
 * A team's slug changes ~never, so it is memoized module-scope for an hour exactly like
 * `fetchProjectDomainList`. That is what makes the budget discipline safe: the common
 * cycle spends NOTHING here, and a cycle that has no budget left keeps serving the
 * last-known slug instead of dropping every project's dashboard link to null.
 */
const TEAM_SLUG_CACHE_TTL_MS = 60 * 60 * 1000;
/** Minimum window worth starting a slug call in. Below this the request is certain to
 *  abort before the server can answer — issuing it only burns a connection and logs a
 *  self-inflicted "aborted due to timeout" that reads like a Vercel outage. */
const MIN_SLUG_CALL_MS = 500;
let teamSlugCache: { key: string; slug: string; at: number } | null = null;

async function fetchTeamSlug(token: string, teamId: string | undefined, deadlineMs: number): Promise<string | null> {
  const cacheKey = teamId ?? "";
  const hit = teamSlugCache;
  if (hit && hit.key === cacheKey && Date.now() - hit.at < TEAM_SLUG_CACHE_TTL_MS) return hit.slug;
  const remember = (slug: string | null): string | null => {
    if (slug) teamSlugCache = { key: cacheKey, slug, at: Date.now() };
    // A failed lookup must not erase a good slug — see the `updateIssue` guard in issues.ts,
    // which likewise refuses to overwrite a live link with this cycle's null.
    return slug ?? (hit && hit.key === cacheKey ? hit.slug : null);
  };

  const get = async (path: string): Promise<unknown> => {
    const remaining = deadlineMs - Date.now();
    if (remaining < MIN_SLUG_CALL_MS) return null;
    try {
      const res = await fetch(`https://api.vercel.com${path}`, {
        headers: { Authorization: `Bearer ${token}` },
        // Untimed, this fetch could hang for as long as the socket stayed open — and the
        // caller's `guard()` only stops AWAITING a slow poll, it never cancels it.
        signal: AbortSignal.timeout(Math.min(PROJECTS_CALL_TIMEOUT_MS, remaining)),
      });
      return res.ok ? await res.json() : null;
    } catch (err) {
      console.error(`Vercel team lookup ${path} failed: ${err instanceof Error ? err.message : String(err)}`);
      return null;
    }
  };

  // 1) Direct team lookup when we have an id.
  if (teamId) {
    const body = (await get(`/v2/teams/${teamId}`)) as { slug?: string } | null;
    if (typeof body?.slug === "string") return remember(body.slug);
  }

  // 2) Fall back to listing the token's teams — match the configured id if set,
  //    otherwise take the first (a single-team token has exactly one).
  const list = (await get(`/v2/teams`)) as { teams?: { id?: string; slug?: string }[] } | null;
  const teams = list?.teams ?? [];
  if (teams.length === 0) return remember(null);
  const match = teamId ? teams.find((t) => t.id === teamId) : null;
  return remember((match ?? teams[0])?.slug ?? null);
}

/** Test seam: drop the memoized team slug so a case can exercise a cold lookup. */
export function __resetTeamSlugCache(): void {
  teamSlugCache = null;
}

export interface VercelProjectsResult {
  ok: boolean;
  states: VercelProdState[];
  meta: VercelProjectMeta[];
  /** The newest real (env-targeted) deployment of EVERY project, AND its newest
   *  CONCLUSIVE one — guarantees the latest outcome of each project is in the snapshot
   *  even when it's older than the team-wide recent-deployments window (see
   *  latestDeploysOf). */
  deploys: ProviderDeploy[];
}

/** A deployment that reached a verdict. CANCELED is not one: Vercel's Ignored Build Step
 *  cancels a deployment for every site a commit didn't touch, so a skip says nothing about
 *  the site — see `HAS_OUTCOME` in `board/facts.ts`, which drops the same rows from the
 *  fold's own selections. */
function isConclusive(d: VercelDeploymentSummary): boolean {
  return d.readyState !== "CANCELED" && d.readyState !== "DELETED";
}

/** Shape one Vercel deployment summary as a ProviderDeploy, with the SAME id namespace
 *  the recent-deployments fetch uses — so the two sources dedup by id when merged. */
function toProviderDeploy(
  projectName: string,
  d: VercelDeploymentSummary,
  providerProjectId: string | null = null,
): ProviderDeploy | null {
  // Boundary validation — an unparseable createdAt must never leave this module: an
  // Invalid Date poisons the deployments upsert and fails the WHOLE cycle, repeatedly,
  // while the deploy sits in the provider's window. Drop the one deploy, keep the rest.
  // (upsertDeployments enforces this again at the DB choke point.)
  const createdAt = toValidDate(d.createdAt);
  if (!createdAt) {
    console.error(`Vercel project ${projectName} deploy ${d.id} has unparseable createdAt ${JSON.stringify(d.createdAt)} — skipping`);
    return null;
  }
  return {
    id: `vc_${d.id}`,
    platform: "vercel",
    projectName,
    providerProjectId,
    ...vercelPhases(d.readyState ?? "", d.readySubstate ?? null, d.target ?? null),
    environment: d.target ?? null,
    commitHash: shortSha(d.meta?.githubCommitSha),
    commitMessage: commitFullMessage(d.meta?.githubCommitMessage),
    branch: d.meta?.githubCommitRef ?? null,
    commitRepo:
      d.meta?.githubCommitOrg && d.meta?.githubCommitRepo ? `${d.meta.githubCommitOrg}/${d.meta.githubCommitRepo}` : null,
    url: d.url ? `https://${d.url}` : null,
    createdAt,
  };
}

/**
 * One project's newest deployment that targets a real environment (previews have
 * target=null and aren't deployments of anything live), PLUS its newest CONCLUSIVE one
 * when that is a different deployment. Empty when the project has never deployed to an
 * env target (or the API omitted ids). Pure — exported for tests.
 *
 * Both are needed, and the second is the point. The newest deployment alone is what the
 * board shows, but for a low-churn site it is almost always a CANCELED skip — and a skip
 * is not an outcome. Supplying only that lets the last REAL outcome age out of the
 * team-wide recent-deployments window and vanish from the DB, leaving the recorders with
 * nothing conclusive to judge: a fixed build can then never resolve its open issue, and a
 * failed one can never open. So we always re-supply the newest deployment that actually
 * reached a verdict, however old it is.
 */
export function latestDeploysOf(
  projectName: string,
  latestDeployments: VercelDeploymentSummary[],
  providerProjectId: string | null = null,
): ProviderDeploy[] {
  // readyState is required: an absent state would map to "building" and
  // manufacture a phantom stuck-build for a healthy project.
  const real = latestDeployments.filter((d) => d.id && d.readyState && d.target != null && d.createdAt != null);
  const newestOf = (list: VercelDeploymentSummary[]): VercelDeploymentSummary | null =>
    list.reduce<VercelDeploymentSummary | null>((max, d) => (!max || d.createdAt! > max.createdAt! ? d : max), null);

  const newest = newestOf(real);
  if (!newest) return [];
  const conclusive = newestOf(real.filter(isConclusive));
  const out = [toProviderDeploy(projectName, newest, providerProjectId)];
  if (conclusive && conclusive.id !== newest.id) out.push(toProviderDeploy(projectName, conclusive, providerProjectId));
  return out.filter((d): d is ProviderDeploy => d !== null);
}

/**
 * How many deployments the projects poll asks for per project. Vercel defaults to 2, and
 * EVERY commit to main creates a deployment on EVERY project (canceled by the Ignored Build
 * Step for the sites it didn't touch) — so at the default a project's last real verdict
 * falls out of the window after just TWO commits, and 36 of our 145 projects were already
 * past it. 10 (the API's max) is the cheap depth win: same call, no extra requests, and it
 * currently covers every project. It is a WINDOW, not a guarantee — a site untouched for 10
 * straight commits still falls out — which is what `fetchNewestConclusiveDeploy` backstops.
 */
const LATEST_DEPLOYMENTS_DEPTH = 10;

/** Per-project backfill cap — a bounded, self-timing-out call like the domains lookup. */
const CONCLUSIVE_CALL_TIMEOUT_MS = 5_000;

/**
 * The project's newest deployment that actually reached a verdict, read straight from the
 * deployments API (`state=READY,ERROR`) — authoritative however many skips are stacked on
 * top, with no window to age out of.
 *
 * This is the backstop that makes the "a skip is not a verdict" fix unconditional. The
 * recorders judge the newest CONCLUSIVE deploy; if a project's last real build has aged out
 * of the poll's window AND the DB never recorded it (the monitor was down when it landed —
 * exactly the crash-loop that started this), they would be left with no verdict at all: a
 * failed build could never resolve and a real failure could never open. Called ONLY for
 * projects whose window holds no verdict, so it is normally zero calls per cycle.
 */
async function fetchNewestConclusiveDeploy(
  token: string,
  teamId: string | undefined,
  projectName: string,
): Promise<ProviderDeploy | null> {
  try {
    const url = new URL("https://api.vercel.com/v6/deployments");
    url.searchParams.set("app", projectName);
    url.searchParams.set("state", "READY,ERROR");
    url.searchParams.set("limit", "5"); // a few, so we can skip any preview (target=null)
    if (teamId) url.searchParams.set("teamId", teamId);
    const res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(CONCLUSIVE_CALL_TIMEOUT_MS),
    });
    if (!res.ok) return null;
    const body = (await res.json()) as { deployments?: VercelDeploymentSummary[] };
    // The list API omits readySubstate; a READY build still maps to `success` via
    // buildPhase, which is all the recorders need to resolve an issue.
    const newest = (body.deployments ?? [])
      .filter((d) => d.id && d.readyState && d.target != null && d.createdAt != null)
      .reduce<VercelDeploymentSummary | null>((max, d) => (!max || d.createdAt! > max.createdAt! ? d : max), null);
    return newest ? toProviderDeploy(projectName, newest) : null;
  } catch {
    return null; // best-effort: a blind spot stays a blind spot, it never fails the poll
  }
}

/** Pick the configured custom domain (skip the *.vercel.app aliases), or null. */
function pickDomain(alias: string[] | undefined): string | null {
  return (alias ?? []).find((a) => !a.endsWith(".vercel.app")) ?? null;
}

interface VercelDomain {
  name: string;
  verified?: boolean;
  redirect?: string | null;
}

// Custom domains change ~never, but the lookup fan-out used to rerun on every
// fresh snapshot build (≥ every 30s with viewers) — hundreds of needless Vercel
// API calls. Cache the project's verified domain list for an hour (module-scope);
// BOTH the canonical-domain pick and the full-domain list derive from it, so a
// project is queried at most once an hour however many callers ask.
const DOMAIN_CACHE_TTL_MS = 60 * 60 * 1000;
const domainListCache = new Map<string, { domains: VercelDomain[]; at: number }>();

/**
 * The project's verified custom domains (apex + redirect aliases, minus
 * `*.vercel.app`), from the authoritative project domains API. Cached per project.
 * On any failure (token lacks scope, network) returns the last-known list, or [].
 */
async function fetchProjectDomainList(token: string, teamId: string | undefined, projectName: string): Promise<VercelDomain[]> {
  const hit = domainListCache.get(projectName);
  if (hit && Date.now() - hit.at < DOMAIN_CACHE_TTL_MS) return hit.domains;
  try {
    const url = new URL(`https://api.vercel.com/v9/projects/${encodeURIComponent(projectName)}/domains`);
    if (teamId) url.searchParams.set("teamId", teamId);
    // Self-bounded so a stalled connection can't hang a caller (e.g. the
    // deploy-projects enumeration that resolves every project's domains).
    const res = await fetch(url.toString(), { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5_000) });
    if (!res.ok) return hit?.domains ?? [];
    const body = (await res.json()) as { domains?: VercelDomain[] };
    const domains = (body.domains ?? []).filter((d) => d.verified && !d.name.endsWith(".vercel.app"));
    domainListCache.set(projectName, { domains, at: Date.now() });
    return domains;
  } catch {
    return hit?.domains ?? [];
  }
}

/**
 * The project's canonical custom domain: the verified, NON-redirect apex (the
 * production deployment's `alias` often omits it, so we read the authoritative
 * list). Null on any failure.
 */
async function fetchProjectDomain(token: string, teamId: string | undefined, projectName: string): Promise<string | null> {
  const list = await fetchProjectDomainList(token, teamId, projectName);
  return list.find((d) => !d.redirect)?.name ?? null;
}

export async function fetchVercelProductionStates(env: {
  VERCEL_API_TOKEN?: string;
  VERCEL_TEAM_ID?: string;
  /** Overall poll budget (ms): stop paginating past this and return a partial. Defaults to
   *  18s (under sync's 20s `guard`); overridable for tests/tuning. */
  overallBudgetMs?: number;
  /** Fetch ONLY the project list (`meta`), for callers reconciling `deploy_project_meta`
   *  rather than deriving issues. Drops the per-project deployment window from the page
   *  request and skips the blind-project backfill's extra API calls; `states` and `deploys`
   *  come back EMPTY (not partial) so a wrong consumer fails visibly instead of judging a
   *  deliberately shallow read. Domains are still resolved — `meta.domain` is what Auto
   *  Configure matches a monitored host against. */
  metaOnly?: boolean;
  /** Per-call time box (ms). Defaults to {@link PROJECTS_CALL_TIMEOUT_MS}; overridable so a
   *  test can exercise the page retry in milliseconds instead of waiting out a 6s box. */
  callTimeoutMs?: number;
}): Promise<VercelProjectsResult> {
  if (!env.VERCEL_API_TOKEN) return { ok: true, states: [], meta: [], deploys: [] };
  // Shares the "vercel" cooldown with the deployments fetch — same API quota.
  if (rateLimitedUntil("vercel")) return { ok: false, states: [], meta: [], deploys: [] };
  const token = env.VERCEL_API_TOKEN;
  const callTimeoutMs = env.callTimeoutMs ?? PROJECTS_CALL_TIMEOUT_MS;
  const deadline = Date.now() + (env.overallBudgetMs ?? PROJECTS_OVERALL_BUDGET_MS);

  try {
    // Enumerate ALL projects (paginate via pagination.next) — not just the first 100.
    // This loop is SERIAL, so a large team plus a slow API is unbounded work: it is what
    // blew sync's 20s guard every cycle, and because the guard cannot cancel it, the
    // abandoned poll kept paginating behind the next cycle. Self-bound to the budget and
    // return what we have (ok:false, so the caller upserts the partial and skips the
    // prune) — the same contract as the Railway and Cloudflare fetchers.
    const projects: VercelProject[] = [];
    let until: number | undefined;
    // WHY the enumeration was truncated, not merely THAT it was. The three causes —
    // the overall budget running out between pages, a page the API refused, and a page
    // that timed out — are diagnosed and fixed differently, and reporting all three with
    // one "overall budget exceeded" string made the prod logs unreadable: the budget was
    // never the cause, but the message named it 65 times a day.
    let truncated: "budget" | "page-error" | "page-timeout" | null = null;
    for (let page = 0; page < 50; page++) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        truncated = "budget";
        break;
      }
      const url = new URL("https://api.vercel.com/v9/projects");
      url.searchParams.set("limit", "100");
      // The deployment window is issue-derivation input; a meta-only read doesn't judge
      // anything, so it asks for the minimum rather than N per project across the account.
      url.searchParams.set("latestDeployments", String(env.metaOnly ? 1 : LATEST_DEPLOYMENTS_DEPTH));
      if (env.VERCEL_TEAM_ID) url.searchParams.set("teamId", env.VERCEL_TEAM_ID);
      if (until) url.searchParams.set("until", String(until));
      let body: { projects?: VercelProject[]; pagination?: { next: number | null } } | null = null;
      // Fetch this page, and fetch it ONCE MORE if our own box cut it off.
      //
      // The walk itself is not slow: measured from inside the prod container it is 2 pages
      // and ~1.5s wall for 163 projects, nowhere near the 18s budget. What loses is a
      // single page — page 0 carries a 4MB body, and every poll starts on a COLD
      // connection because the deploy poll runs every 5 minutes, far longer than any
      // keep-alive survives. A cold TLS setup plus a 4MB transfer is what crosses the 6s
      // per-call box, and prod logged this ~65 times a day. The retry runs on the
      // connection the first attempt just established, so it is the warm case.
      for (let attempt = 1; attempt <= PROJECTS_CALL_ATTEMPTS && body === null; attempt++) {
        const attemptRemaining = deadline - Date.now();
        if (attemptRemaining <= 0) break;
        try {
          const res = await fetch(url.toString(), {
            headers: { Authorization: `Bearer ${token}` },
            signal: AbortSignal.timeout(Math.min(callTimeoutMs, attemptRemaining)),
          });
          if (!res.ok) {
            if (res.status === 429) noteRateLimited("vercel", res.headers.get("retry-after"));
            console.error(`Vercel projects API ${res.status}`);
            // Page 0 failing is a definitive API failure (nothing fetched). A later
            // page failing (a transient 429/5xx on a large team) must NOT wipe the
            // pages already fetched — keep them and hand back a partial, exactly
            // like the stall path below. Either way the API ANSWERED, so this is a
            // verdict and not something a second identical request would improve.
            if (page === 0) return { ok: false, states: [], meta: [], deploys: [] };
            truncated = "page-error";
            break;
          }
          body = (await res.json()) as { projects?: VercelProject[]; pagination?: { next: number | null } };
        } catch {
          // This page stalled/aborted — a transient, not a definitive API error. Once the
          // attempts are spent, keep the pages already fetched and hand back a partial,
          // matching the Railway contract.
          if (attempt === PROJECTS_CALL_ATTEMPTS) truncated = "page-timeout";
        }
      }
      if (body === null) {
        // Never silently clean: a page we could not read makes the enumeration partial.
        truncated ??= "budget";
        break;
      }
      projects.push(...(body.projects ?? []));
      const next = body.pagination?.next;
      if (!next) break;
      until = next;
    }

    const now = Date.now();
    const states: VercelProdState[] = [];
    // Domain: try the cheap source (the deployment alias) first; for projects whose
    // alias omits the custom domain, look it up via the project domains API (capped
    // concurrency so a large team doesn't fan out hundreds of calls at once).
    // Only projects whose deployment alias omits a custom domain need the (cached)
    // domains-API lookup; fetchProjectDomain memoizes per project for an hour.
    // Past the budget, skip the backfill entirely rather than fan out more calls: the
    // domain is cosmetic (a link label), and every project keeps its alias-derived domain.
    const domainByName = new Map<string, string | null>();
    const missing = Date.now() < deadline ? projects.filter((pr) => !pickDomain(pr.targets?.production?.alias)) : [];
    if (missing.length > 0) {
      const looked = await mapLimit(missing, 8, (p) => fetchProjectDomain(token, env.VERCEL_TEAM_ID, p.name));
      missing.forEach((p, i) => domainByName.set(p.name, looked[i] ?? null));
    }
    // Descriptive config for EVERY project (the browser shows all of them).
    const meta: VercelProjectMeta[] = projects.map((p) => ({
      projectName: p.name,
      domain: pickDomain(p.targets?.production?.alias) ?? domainByName.get(p.name) ?? null,
      gitRepo: p.link?.org && p.link?.repo ? `${p.link.org}/${p.link.repo}` : null,
      gitBranch: p.link?.productionBranch ?? null,
      rootDirectory: p.rootDirectory ?? null,
      framework: p.framework ?? null,
    }));
    // Meta-only: the project list IS the whole answer, so stop here — before the staleness
    // evaluation and, more importantly, before the blind-project backfill's extra calls.
    if (env.metaOnly) {
      reportTruncation(truncated);
      return { ok: !truncated, states: [], meta, deploys: [] };
    }
    const deploys = projects.flatMap((p) => latestDeploysOf(p.name, p.latestDeployments ?? [], p.id ?? null));

    // A project whose whole window is skips has NO verdict in this snapshot. If the DB never
    // recorded its last real build either, the recorders would have nothing to judge and its
    // issue could never open OR resolve — so read the verdict authoritatively. Bounded: only
    // the blind projects (normally none), capped concurrency, each call self-timing-out, and
    // skipped entirely once past the poll budget.
    const blind = deploys.length > 0 && Date.now() < deadline
      ? [...new Set(deploys.filter((d) => d.buildPhase === "canceled").map((d) => d.projectName))].filter(
          (name) => !deploys.some((d) => d.projectName === name && d.buildPhase !== "canceled"),
        )
      : [];
    if (blind.length > 0) {
      console.log(`[vercel-projects] ${blind.length} project(s) have no verdict in the poll window — reading it directly`);
      const found = await mapLimit(blind, 8, (name) => fetchNewestConclusiveDeploy(token, env.VERCEL_TEAM_ID, name));
      deploys.push(...found.filter((d): d is ProviderDeploy => d !== null));
    }

    // The dashboard slug is needed ONLY to label the states below, so it is resolved LAST:
    // after the metaOnly return, after the page walk, and after the blind-project backfill,
    // off whatever budget those didn't need. Ordering it ahead of the backfill made a slow
    // team lookup eat the `Date.now() < deadline` check above and silently drop a project's
    // only chance at a verdict — the same "link outranks the data" bug the page walk already
    // suffered, one step further down. Memoized, so this is normally free.
    const slug = await fetchTeamSlug(token, env.VERCEL_TEAM_ID, deadline);

    for (const p of projects) {
      const live = p.targets?.production;
      // No production target → the project has never deployed to production; nothing to judge.
      if (!live) continue;

      // `serving` is the deployment actually judged — the newest CONCLUSIVE one, which is
      // NOT `live` whenever an Ignored-Build-Step skip is the newest production deploy.
      // The detail line and inspector link must point at it, never at the skip.
      const { stale, errored, behind, live: serving, liveCreated } = evaluateProdStaleness(live, p.latestDeployments ?? []);
      // Link straight to the offending production deployment's inspector page (the
      // error log) — the dashboard URL is `…/<project>/<id>` with the `dpl_` prefix
      // stripped — falling back to the deployments list if the id is missing. Encode
      // the project segment (as the domains call below does) so an exotic name can't
      // break the URL; the deployId is already alphanumeric.
      const deployId = (serving.id ?? "").replace(/^dpl_/, "");
      states.push({
        projectName: p.name,
        stale,
        detail: stale ? staleDetail(errored, behind, liveCreated, now) : null,
        sourceUrl: slug ? `https://vercel.com/${slug}/${encodeURIComponent(p.name)}/${deployId || "deployments"}` : null,
        liveUrl: null, // resolved from the matched endpoint in sync (explicit config)
      });
    }
    // A budget-truncated enumeration is a PARTIAL, not a clean read: `ok:false` makes the
    // caller upsert what we did get (so a real build failure still lands) while skipping
    // the prune and the stale-issue pass, which would otherwise judge absent projects.
    reportTruncation(truncated);
    return { ok: !truncated, states, meta, deploys };
  } catch (err) {
    // Concise, no stack: a transient provider stall is expected noise, not a crash.
    console.error(`Vercel projects fetch failed: ${err instanceof Error ? err.message : String(err)}`);
    return { ok: false, states: [], meta: [], deploys: [] };
  }
}
