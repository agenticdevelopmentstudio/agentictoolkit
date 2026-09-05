import type { DeploymentDTO } from "./types";
import { projectPageUrl } from "./url";
import { envFromProject } from "@agentic-toolkit/deploy-platform/canon";

// ---------------------------------------------------------------------------
// Deploy/env derivation + link derivation, and the Indicator shape the sign /
// pill render. Row CONSTRUCTION lives in `row-model.ts` (the web client); problem
// DERIVATION (which rows are problems, indicator state) is the SERVER's, in the
// board deriver (`src/board/derive-activity.ts`).
// ---------------------------------------------------------------------------

export type IndicatorState = "ok" | "warn" | "down";

export interface Indicator {
  state: IndicatorState;
  count: number;
}

// envFromProject now lives in @agentic-toolkit/deploy-platform/canon. Imported above
// for use in this module; re-exported so existing `./deploy-view` importers keep
// their path.
export { envFromProject };

/**
 * THE DEPLOYING BRANCHES, and the tier each one builds. This mapping is the deployment
 * process itself — a push to `prepared` is what makes a testing deploy happen — so it is
 * the one env signal on a deploy row that cannot be wrong about a project it describes.
 *
 * `main` is deliberately ABSENT: it deploys nothing, so a row built from it has no branch
 * evidence and must fall through to the older signals rather than be badged from a ref
 * that means nothing to the pipeline.
 */
const BRANCH_ENV: ReadonlyMap<string, string> = new Map([
  ["prepared", "testing"],
  ["staging", "staging"],
  ["production", "production"],
]);

/**
 * The tier a branch builds, or null when the branch is absent or is not one of the three
 * that deploy. Null means "no evidence", which is what hands the decision to
 * {@link deployEnv}'s fallback — never a guess of its own, because guessing here would
 * reintroduce exactly the fallible default this function exists to outrank.
 *
 * A Map rather than an object literal because the key is an arbitrary git ref. Indexing an
 * object literal reaches `Object.prototype`, so a branch legitimately named `toString` or
 * `__proto__` would return a truthy FUNCTION (or the prototype), `?? null` would never
 * fire, and the `Record<string, string>` annotation would swear the result was a string
 * all the way to the badge.
 */
export function envFromBranch(branch: string | null | undefined): string | null {
  if (!branch) return null;
  return BRANCH_ENV.get(branch) ?? null;
}

/**
 * Display environment for a deploy row: the LOGICAL TIER it belongs to, which is a
 * different question from the provider's promotion target.
 *
 * Three signals, in order of how easily each can lie:
 *
 *  1. THE BRANCH decides whenever it can. It is the pipeline's own input, so it is right
 *     by construction for any project, named however it likes, on any platform.
 *  2. Failing that, VERCEL reads the tier off the project name (`staging.adh`,
 *     `docs-testing`), because its `environment` column is a promotion target and every
 *     Vercel project's is "production" — passing it through badges every testing site
 *     PROD.
 *  3. Failing that, RAILWAY/CLOUDFLARE trust the stored value: they report a REAL
 *     environment name, so a Railway testing build must read TESTING rather than be
 *     collapsed to PROD by a name with no `staging.`/`testing.` prefix.
 *
 * Steps 2 and 3 are the pre-branch rule, unchanged, and they still cover every row whose
 * branch is null (written before the column was populated, or a platform that reported
 * none) or outside the map. What the branch adds is the case neither of them can reach:
 * a project whose NAME carries no tier suffix but which does not serve production. Their
 * shared default is "production", the most dangerous of the three tiers to be wrong
 * about, which is why a signal that can't default is worth ranking above them.
 *
 * Step 1 outranks step 3 as well as step 2 — the ordering is about which SIGNAL can lie,
 * not about which platform reported it. A Railway environment named "production" that
 * builds `prepared` is serving testing, and it reads testing here
 * (`test/deploy-env.test.ts` pins that case explicitly). So "trust the stored value" in
 * step 3 means "when no branch decided", not "always for these platforms".
 *
 * `branch` is REQUIRED, with no default. It is the signal the other two exist to be
 * fallbacks for, so a caller that has not got one has to say so by passing null — a
 * default would let a new call site silently take the fallible path and badge a testing
 * project PROD, which is the exact regression this parameter was added to close.
 */
export function deployEnv(
  platform: string,
  projectName: string,
  storedEnv: string | null,
  branch: string | null,
): string {
  const byBranch = envFromBranch(branch);
  if (byBranch) return byBranch;
  if (platform === "vercel") return envFromProject(projectName);
  return storedEnv && storedEnv.length > 0 ? storedEnv : envFromProject(projectName);
}

/**
 * A "real environment" deploy — one that targets prod/staging/testing, NOT a
 * Vercel preview/feature-branch build. Vercel previews report `environment=null`;
 * they are CI artifacts, not deployments of anything live, so the monitor
 * ignores them. (Counting a failed preview as "deploy failed" — and labelling it
 * with the project's prod/staging env — is exactly the false-positive we hit.)
 */
export function isRealEnvDeploy(d: DeploymentDTO): boolean {
  return isRealEnvDeployRow(d.platform, d.environment);
}

/**
 * Row-level form of {@link isRealEnvDeploy} for the recorder, which works with raw
 * DB rows (platform + nullable environment) rather than DeploymentDTOs. A Vercel
 * deploy with no env target is a preview/branch build. Shared so the issue
 * recorder and the UI can never disagree about what counts as a real deploy.
 */
export function isRealEnvDeployRow(platform: string, environment: string | null): boolean {
  return !(platform === "vercel" && (environment == null || environment === ""));
}

/**
 * Source + live links for a deploy row. The SINGLE source of truth for both
 * links, used by all three panes (active problems, resolved, activity) and the
 * issue recorder — so every row everywhere renders the same clickable links.
 *
 *  - `sourceUrl` → where you go to debug the deploy on its platform. Vercel
 *    inspector URLs collapse to the project page; Railway stores its
 *    project-dashboard URL (set in fetch-railway); anything else passes through.
 *  - `liveUrl` → the deploy's live custom-domain host (`liveHost`, resolved at
 *    fetch time from the platform's attached domains), or null. We deliberately
 *    do NOT fall back to the deploy/inspector URL: a link rendered as a host must
 *    point at the real site, never the build page.
 */
export function deployLinks(
  url: string | null,
  liveHost: string | null,
): { sourceUrl: string | null; liveUrl: string | null } {
  return { sourceUrl: projectPageUrl(url), liveUrl: liveHost ? `https://${liveHost}` : null };
}
