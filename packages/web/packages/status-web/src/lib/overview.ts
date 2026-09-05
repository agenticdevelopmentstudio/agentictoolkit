import type { DeploymentDTO } from "../types";
import type { ActivityRow, Indicator as BoardIndicator, Problem } from "./board-types";

// ---------------------------------------------------------------------------
// Deploy predicates and the Indicator shape the sign / pill render. Row CONSTRUCTION
// lives in `row-model.ts`; problem DERIVATION (which rows are problems, indicator state)
// is the SERVER's (`Board`) — `indicatorFromProblems`/`deployCounts` below are rendering
// projections of it.
//
// The client does not derive a row's ENVIRONMENT at all: the tier is the server's, decided
// branch-first by `src/monitor/deploy-view.ts`'s `deployEnv` and stamped on the row before
// it ships. The project-name convention this file used to also carry is the deploy
// engine's (`envFromProject`, @agentic-toolkit/deploy-platform/canon), where the planner
// that reads it lives.
// ---------------------------------------------------------------------------

export type IndicatorState = "ok" | "warn" | "down";

export interface Indicator {
  state: IndicatorState;
  count: number;
}

/**
 * Sign state + count over the problems a pane is SHOWING. This is a rendering projection of
 * severities the server already assigned — not a second opinion about what a problem is.
 * The rule is the server's, transcribed once: `indicatorFor` (`src/board/derive-activity.ts:220`).
 * `board-types-parity.test.ts` pins the two together on the unfiltered set.
 */
export function indicatorFromProblems(problems: Problem[]): Indicator {
  const count = problems.length;
  if (count === 0) return { state: "ok", count: 0 };
  if (problems.some((p) => p.severity === "critical")) return { state: "down", count };
  return { state: "warn", count };
}

/** The wire indicator → the sign's vocabulary. The ONLY translation between the two. */
export const INDICATOR_STATE: Record<BoardIndicator, IndicatorState> = {
  operational: "ok",
  degraded: "warn",
  outage: "down",
};

/** Build/deploy/failure counts for the stats strip — a tally of rows the server already
 *  judged, which is why it may live on the client. `step` and `tone` arrive on the wire.
 *  `sinceMs` is the board's own `activityFromMs`; the client never picks the window. */
export function deployCounts(
  activity: ActivityRow[],
  sinceMs: number,
): { builds: number; deploys: number; failures: number } {
  let builds = 0;
  let deploys = 0;
  let failures = 0;
  for (const a of activity) {
    if (a.kind !== "deploy" || Date.parse(a.at) < sinceMs) continue;
    if (a.step === "build") builds++;
    else if (a.step === "deploy") deploys++;
    if (a.tone === "bad") failures++;
  }
  return { builds, deploys, failures };
}

/**
 * The caption for the activity window the SERVER chose — "24h", "7d" — in the same
 * vocabulary as the span menu's labels.
 *
 * Derived from the board's own boundary rather than written out beside the counts,
 * because a hardcoded "· 24h" beside a count taken over a different window is a label
 * that lies without anything failing: the server owns `ACTIVITY_WINDOW_MS`, and changing
 * it there would have left this caption stating the old figure forever.
 */
export function activityWindowLabel(fromMs: number, toMs: number): string {
  const hours = Math.max(1, Math.round((toMs - fromMs) / 3_600_000));
  return hours >= 48 && hours % 24 === 0 ? `${hours / 24}d` : `${hours}h`;
}

/** The headline the status sign / pill announces, e.g. "4 PROBLEMS" or
 *  "ALL SYSTEMS OPERATIONAL". Shared by the mobile hero sign and the desktop
 *  top-bar pill (as its accessible name) so they can never word it differently. */
export function headlineFor(state: IndicatorState, count: number): string {
  if (state === "ok") return "ALL SYSTEMS OPERATIONAL";
  if (state === "warn") return count === 1 ? "1 SERVICE NEEDS ATTENTION" : `${count} SERVICES NEED ATTENTION`;
  return count === 1 ? "1 PROBLEM" : `${count} PROBLEMS`;
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
