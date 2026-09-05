import { describe, it, expect } from "vitest";
import type { DeploymentDTO } from "../types";
import { isRealEnvDeploy, isRealEnvDeployRow, activityWindowLabel } from "./overview";

function deploy(overrides: Partial<DeploymentDTO>): DeploymentDTO {
  return {
    id: "vc_1",
    platform: "vercel",
    projectName: "adh",
    status: "success",
    buildPhase: "built",
    deployPhase: "none",
    environment: "production",
    tier: "production",
    commitHash: "abc1234def",
    commitMessage: "test commit\nsecond line",
    branch: "main",
    commitRepo: null,
    url: "https://x.vercel.app",
    errorText: null,
    liveHost: null,
    createdAt: "2026-06-04T18:00:00.000Z",
    ...overrides,
  };
}

// `envFromProject` moved to @agentic-toolkit/deploy-platform/canon and is tested there
// (src/canon/canon.test.ts) — both name shapes and the production default.

describe("isRealEnvDeploy", () => {
  it("drops Vercel preview builds (environment=null) but keeps real env deploys", () => {
    const preview = deploy({ id: "p", platform: "vercel", environment: null, status: "failed" });
    const prod = deploy({ id: "r", platform: "vercel", environment: "production", status: "failed" });
    expect(isRealEnvDeploy(preview)).toBe(false);
    expect(isRealEnvDeploy(prod)).toBe(true);
  });

  it("keeps non-Vercel deploys even with a null environment", () => {
    const cf = deploy({ id: "cf", platform: "cloudflare-pages", environment: null, status: "success" });
    expect(isRealEnvDeploy(cf)).toBe(true);
  });

  it("isRealEnvDeployRow (raw form) drops Vercel preview rows incl. empty-string env", () => {
    expect(isRealEnvDeployRow("vercel", null)).toBe(false);
    expect(isRealEnvDeployRow("vercel", "")).toBe(false);
    expect(isRealEnvDeployRow("vercel", "production")).toBe(true);
    expect(isRealEnvDeployRow("railway", null)).toBe(true);
    expect(isRealEnvDeployRow("cloudflare-pages", null)).toBe(true);
  });
});

describe("activityWindowLabel — the caption for the window the SERVER chose", () => {
  const HOUR = 3_600_000;

  it("names the default 24h window", () => {
    expect(activityWindowLabel(0, 24 * HOUR)).toBe("24h");
  });

  it("switches to days once the window is at least two of them", () => {
    expect(activityWindowLabel(0, 7 * 24 * HOUR)).toBe("7d");
    // 47h is not a whole number of days, so it stays in hours rather than rounding to "2d"
    // and captioning the counts with a window nobody configured.
    expect(activityWindowLabel(0, 47 * HOUR)).toBe("47h");
  });

  it("never captions a sub-hour window as 0h", () => {
    expect(activityWindowLabel(0, 60_000)).toBe("1h");
  });
});
