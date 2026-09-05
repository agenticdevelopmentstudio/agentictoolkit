import type { DeployStatus } from "./deploy-status";
import type { HealthStatus } from "./health";
import { platformCanon } from "./overview";

/**
 * Where an issue came from — DNS resolution, the HTTP probe, the error tracker, or a deploy
 * provider.
 *
 * `glitchtip` is the odd one out and deliberately so: the other sources answer "is the thing
 * reachable", it answers "is the thing THROWING". A site can be up on every probe and still
 * have an error Problem open, which is the whole point of carrying it here rather than
 * folding it into `http`.
 *
 * MIRRORED CLIENT-SIDE in `web/src/lib/issue-sources.ts` — same union, same labels, same
 * order. The client indexes `SOURCE_LABEL[row.source]`, so a source the server can emit and
 * the client has never heard of renders `undefined` in the filter and the badge.
 */
export type IssueSource = "dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy";

/** Display labels for the source filter + badges. */
export const SOURCE_LABEL: Record<IssueSource, string> = {
  dns: "DNS",
  http: "HTTP",
  glitchtip: "GlitchTip",
  vercel: "Vercel",
  "cloudflare-pages": "Cloudflare",
  railway: "Railway",
  crunchy: "Crunchy Bridge",
};

/** Canonical order for the source filter UI. */
export const ISSUE_SOURCES: IssueSource[] = ["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"];

/**
 * A `deploy_integrations.platform` string → the `platform_health_state.source` (and
 * `IssueSource`) that speaks for it, or null for a platform we do not poll.
 *
 * THE TWO VOCABULARIES DISAGREE ABOUT EXACTLY ONE WORD, which is the whole reason this is
 * a lookup and not a cast. `providerConnFromConfig` matches the Cloudflare integration row
 * on `"cloudflare"` (vendored `conn/index.js`), while the health row and `IssueSource`
 * spell it `"cloudflare-pages"` — so `gone.platform as IssueSource` would compile, run,
 * and quietly do nothing for the one platform whose two names differ (constraint 7).
 * `platformCanon` is not the inverse either: it folds the OTHER way,
 * `cloudflare-pages` → `cloudflare`.
 *
 * Both Cloudflare spellings are accepted because `createIntegration` takes the platform as
 * a free string, so an operator (or an MCP client) can store either one.
 */
const INTEGRATION_PLATFORM_SOURCE: Record<string, IssueSource> = {
  vercel: "vercel",
  cloudflare: "cloudflare-pages",
  "cloudflare-pages": "cloudflare-pages",
  railway: "railway",
  crunchy: "crunchy",
};

export function platformHealthSource(integrationPlatform: string | null): IssueSource | null {
  return INTEGRATION_PLATFORM_SOURCE[(integrationPlatform ?? "").trim().toLowerCase()] ?? null;
}

/** HTTP probe states that count as an open problem. */
export function httpIsBad(status: HealthStatus): boolean {
  return status === "down" || status === "degraded";
}

/**
 * Deploy states that count as an open problem. `failed` only — building/queued are
 * still in flight.
 *
 * `canceled` is NOT judged here at all, and must not be: a skipped build is the absence
 * of a verdict, not a good one (Vercel's Ignored Build Step cancels a deployment for
 * every site a commit didn't touch, so it's the ordinary NEWEST state of a low-churn
 * site). Callers must feed this the newest deploy that reached a verdict — see
 * `HAS_OUTCOME` in `board/facts.ts`, which drops canceled (and expired-to-`unknown`) rows
 * from both selections before `collapseByTarget` picks the newest. Judging a
 * canceled row would both pin an open issue open forever and hide a real failure under
 * the next commit's skip.
 */
export function deployIsBad(status: DeployStatus): boolean {
  return status === "failed";
}

/** How long a build may sit BUILDING before it counts as stuck. */
export const STUCK_DEPLOY_MS = 30 * 60 * 1000; // 30 minutes

/**
 * A deploy stuck mid-flight: still BUILDING well past when a healthy build lands.
 * A wedged build never transitions to failed/success on its own, so the
 * failed-only signal misses it entirely — this catches "started but never landed".
 *
 * We deliberately do NOT flag `queued`: a long-queued deploy is almost always an
 * INTENTIONAL hold (a Railway deploy awaiting approval, a Vercel build gated by
 * the Ignored Build Step / concurrency) — not a wedge. Flagging those paged us
 * for deploys that were working as designed, so stuck = actively building only.
 */
export function deployIsStuck(status: DeployStatus, ageMs: number): boolean {
  return status === "building" && ageMs >= STUCK_DEPLOY_MS;
}

/** A deploy state that resolves an open deploy issue. `success` only. */
export function deployIsResolving(status: DeployStatus): boolean {
  return status === "success";
}

/**
 * Consecutive failed provider polls before a `platform-health|<source>` issue
 * opens. Debounces a one-off transient API blip (429/timeout) that would
 * otherwise open + auto-resolve an "unreachable" issue within a single cycle.
 */
export const PLATFORM_UNREACHABLE_POLLS = 2;

export interface PlatformStreak {
  /** The new consecutive-failure count to persist. */
  streak: number;
  /** Whether the `platform-health` issue should be OPEN this cycle. */
  bad: boolean;
}

/**
 * Advance a platform's consecutive-failure streak by one poll and decide whether
 * its `platform-health` issue should be open. `bad` only flips true once a
 * failure has persisted `threshold` consecutive polls — so a single transient
 * blip never surfaces an issue. A reachable poll (`failing === false`) resets the
 * streak to 0; recovery is therefore NOT debounced (one good poll clears it).
 */
export function nextPlatformStreak(
  prevStreak: number,
  failing: boolean,
  threshold: number = PLATFORM_UNREACHABLE_POLLS,
): PlatformStreak {
  const streak = failing ? prevStreak + 1 : 0;
  return { streak, bad: failing && streak >= threshold };
}

/**
 * The deploy projects OWNED BY A SITE — i.e. the platform projects that some live
 * monitored endpoint is explicitly wired to. This is the single gate for "may this
 * be a Problem": a deploy/stale issue is only legitimate when a site owns its
 * project. A project that no site monitors is invisible — never enumerated, never
 * a Problem — so a non-site platform project (an ignored infra worker, a project we
 * don't track) can't manufacture a phantom. Per-platform sets, keyed by the
 * CANONICAL platform (cloudflare-pages → cloudflare).
 */
export interface ConfiguredDeployTargets {
  vercel: ReadonlySet<string>;
  railway: ReadonlySet<string>;
  cloudflare: ReadonlySet<string>;
}

/**
 * Narrow the site-owned targets to the Vercel projects that STILL EXIST upstream, and
 * report the ones that don't. A project deleted at Vercel leaves its site wired to a
 * target that can never build again — and whose last failed build the recorders would
 * otherwise keep reopening as an unclearable Problem.
 *
 * Dropping it from the owned set is all it takes to stop that: an unowned target is not in
 * `monitoredTargets`, so `applyBoardToLedger` closes its open row as "unmonitored"
 * (silent, and it can never reopen). Removing the MONITOR is a separate decision, made by
 * `endpointsClaimedByNothing` off the full platform inventory — this function narrows
 * Problems only, and `vanished` is reported for the log rather than acted on here.
 *
 * Vercel only. Railway and Cloudflare are polled live on every enumeration, so they have
 * no equivalent staleness — and callers must pass a set from a COMPLETE Vercel read
 * (`prod.ok`), or a truncated page walk would read as mass deletion.
 *
 * TWO emptiness guards, both load-bearing rather than merely cautious, because a bad read
 * would otherwise silence the deploy Problems of the entire Vercel fleet in one cycle —
 * exactly the alarms that say something is wrong:
 *
 *  1. An EMPTY live set narrows nothing. "Every project in the account was deleted" and
 *     "the token was rescoped / the read came back empty" are indistinguishable from here.
 *  2. Neither does a set that names EVERY owned project as vanished. A non-empty read is
 *     not proof of the right SCOPE: a re-issued token, a changed `VERCEL_TEAM_ID`, or a
 *     project transfer returns a perfectly complete list — of somebody else's projects —
 *     and every monitored name is missing from it. A real mass deletion is
 *     indistinguishable from a scope change, and losing every monitor costs vastly more
 *     than leaving the deploy Problems visible for a human to read.
 *
 * Both decline the NARROWING too, not just the deletion, so the deploy Problems of the
 * projects in question stay on the board — the operator can still see what the cycle
 * refused to act on. The genuinely-emptied account still gets its `deploy_project_meta`
 * rows pruned (that is a repairable cache); its monitors just outlive it.
 *
 * The cost of guard 2 is a board whose ONLY Vercel project really was deleted: its deploy
 * Problems stay visible. That is the same trade `endpointsClaimedByNothing` makes with its
 * own all-vanished guard, deliberately — an all-or-nothing observation is never evidence.
 */
export function dropVanishedVercelProjects(
  configured: ConfiguredDeployTargets,
  liveVercelProjects: ReadonlySet<string>,
): { configured: ConfiguredDeployTargets; vanished: string[] } {
  if (liveVercelProjects.size === 0) return { configured, vanished: [] };
  const vanished = [...configured.vercel].filter((p) => !liveVercelProjects.has(p));
  if (vanished.length === 0) return { configured, vanished };
  if (vanished.length === configured.vercel.size) return { configured, vanished: [] };
  return {
    configured: { ...configured, vercel: new Set([...configured.vercel].filter((p) => liveVercelProjects.has(p))) },
    vanished,
  };
}

