import { describe, it, expect } from "vitest";
import { computeSelfCheck } from "./self-check";
import type { IntegrationCheck, IntegrationsResponse } from "../types";

const check = (c: Partial<IntegrationCheck> & { id: string }): IntegrationCheck => ({
  label: c.id,
  configured: true,
  ok: true,
  state: "ok",
  detail: "",
  ...c,
});
const report = (checks: IntegrationCheck[]): IntegrationsResponse => ({
  generatedAt: "T0",
  overall: "warn",
  checks,
});

describe("computeSelfCheck", () => {
  it("returns null when data is undefined (loading)", () => {
    expect(computeSelfCheck(undefined)).toBeNull();
  });

  it("returns null when everything is ok", () => {
    expect(computeSelfCheck(report([check({ id: "stats" }), check({ id: "vercel" })]))).toBeNull();
  });

  it("surfaces missing env (deduped) as a NON-error warning — recoverable, no cry-wolf", () => {
    const view = computeSelfCheck(
      report([
        check({ id: "cloudflare", state: "warn", configured: false, ok: false, missingEnv: ["CLOUDFLARE_ACCOUNT_ID"] }),
        check({ id: "vercel", state: "warn", configured: false, ok: false, missingEnv: ["VERCEL_API_TOKEN"] }),
        check({ id: "railway", state: "warn", configured: false, ok: false, missingEnv: ["VERCEL_API_TOKEN"] }), // dup
      ]),
    );
    expect(view).not.toBeNull();
    expect(view!.missingEnv).toEqual(["CLOUDFLARE_ACCOUNT_ID", "VERCEL_API_TOKEN"]);
    expect(view!.missingEnvError).toBe(false);
    expect(view!.hasError).toBe(false); // warn-level missing env stays amber
    // Missing-env checks are NOT also chipped as issues (they're shown in the env chip).
    expect(view!.issues).toHaveLength(0);
  });

  it("an error-severity missing env (couldn't auto-discover) goes red and counts as an error", () => {
    const view = computeSelfCheck(
      report([check({ id: "cloudflare", state: "error", configured: false, ok: false, missingEnv: ["CLOUDFLARE_ACCOUNT_ID"] })]),
    );
    expect(view!.missingEnv).toEqual(["CLOUDFLARE_ACCOUNT_ID"]);
    expect(view!.missingEnvError).toBe(true);
    expect(view!.hasError).toBe(true);
    expect(view!.issues).toHaveLength(0); // still shown via the env chip, not duplicated
  });

  it("keeps reachability issues as chips but excludes the internal cron check", () => {
    const view = computeSelfCheck(
      report([
        check({ id: "cron", state: "warn", ok: false, detail: "first poll pending" }),
        check({ id: "railway", state: "error", configured: true, ok: false, detail: "HTTP 500" }),
      ]),
    );
    expect(view).not.toBeNull();
    expect(view!.missingEnv).toEqual([]);
    expect(view!.issues.map((c) => c.id)).toEqual(["railway"]); // cron filtered out
    expect(view!.hasError).toBe(true); // an errored issue
  });

  it("collapses correlated provider failures into the backend's Connectivity chip only", () => {
    const view = computeSelfCheck(
      report([
        check({ id: "cloudflare", state: "warn", ok: false, detail: "workers/scripts unreachable", correlated: true }),
        check({ id: "posthog", state: "warn", ok: false, detail: "This operation was aborted", correlated: true }),
        check({ id: "connectivity", state: "warn", ok: false, detail: "2 providers unreachable at once — likely monitor-side connectivity" }),
      ]),
    );
    expect(view!.issues.map((c) => c.id)).toEqual(["connectivity"]);
    expect(view!.hasError).toBe(false); // monitor-side stays amber, never red
  });

  it("a non-errored reachability warning alone is not a red error", () => {
    // id is a real reachability check (not "cron", which would be filtered out).
    const view = computeSelfCheck(
      report([check({ id: "railway", state: "warn", ok: false, detail: "slow" })]),
    );
    expect(view!.issues.map((c) => c.id)).toEqual(["railway"]);
    expect(view!.hasError).toBe(false);
  });
});
