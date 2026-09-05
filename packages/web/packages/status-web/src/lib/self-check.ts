import type { IntegrationCheck, IntegrationsResponse } from "../types";

/** What the self-check error bar renders, derived from the /integrations report. */
export interface SelfCheckView {
  /** Expected env vars found unset, deduped (insertion-ordered by check order). */
  missingEnv: string[];
  /** A missing-env check is error-severity (e.g. the account couldn't auto-discover) —
   *  the env chip goes red rather than amber. */
  missingEnvError: boolean;
  /** Reachability/freshness issues to chip out — excludes the missing-env checks (shown
   *  in the env chip), the internal "cron" check (wallboard noise), and `correlated`
   *  provider failures (collapsed into the backend's single Connectivity chip). */
  issues: IntegrationCheck[];
  /** Any errored check (a reachability error OR a missing-env that's genuinely broken)
   *  → render the bar in its red (error) state. A merely-recoverable missing env (a
   *  "warn") keeps the bar amber so it doesn't cry wolf. */
  hasError: boolean;
}

/**
 * Pure view-model for SelfCheckBanner. Returns null when there is nothing to show, so
 * the bar can render exactly when `computeSelfCheck(...) !== null`. Kept separate from
 * the component so the (slightly fiddly) filtering rules are unit-tested without a DOM.
 */
export function computeSelfCheck(data: IntegrationsResponse | undefined): SelfCheckView | null {
  if (!data) return null;

  const missingEnvChecks = data.checks.filter((c) => c.missingEnv?.length);
  const missingEnv = [...new Set(missingEnvChecks.flatMap((c) => c.missingEnv!))];
  const missingEnvError = missingEnvChecks.some((c) => c.state === "error");
  const issues = data.checks.filter(
    (c) => c.state !== "ok" && c.id !== "cron" && !c.missingEnv?.length && !c.correlated,
  );

  if (missingEnv.length === 0 && issues.length === 0) return null;

  // Severity follows actual check state — never forced red just because a var is unset.
  const hasError = missingEnvError || issues.some((c) => c.state === "error");
  return { missingEnv, missingEnvError, issues, hasError };
}
