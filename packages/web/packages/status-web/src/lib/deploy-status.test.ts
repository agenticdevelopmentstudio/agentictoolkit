import { describe, it, expect } from "vitest";
import { vercelPhases, railwayPhases, combinedStatus } from "./deploy-status";

describe("vercelPhases", () => {
  it("maps build readyState", () => {
    expect(vercelPhases("BUILDING", null, "production").buildPhase).toBe("building");
    expect(vercelPhases("QUEUED", null, null).buildPhase).toBe("queued");
    expect(vercelPhases("ERROR", null, "production").buildPhase).toBe("failed");
    expect(vercelPhases("CANCELED", null, null).buildPhase).toBe("canceled");
    expect(vercelPhases("READY", "PROMOTED", "production").buildPhase).toBe("built");
  });
  it("derives the production deploy phase from readySubstate", () => {
    expect(vercelPhases("READY", "PROMOTED", "production").deployPhase).toBe("deployed");
    expect(vercelPhases("READY", "ROLLING", "production").deployPhase).toBe("deploying");
    // STAGED = built but never promoted → no deploy entry yet.
    expect(vercelPhases("READY", "STAGED", "production").deployPhase).toBe("none");
  });
  it("never shows a deploy phase for non-production targets (build-ready IS go-live)", () => {
    expect(vercelPhases("READY", null, null).deployPhase).toBe("none");
    expect(vercelPhases("READY", "PROMOTED", "staging").deployPhase).toBe("none");
  });
});

describe("railwayPhases", () => {
  it("separates the native build and deploy phases", () => {
    expect(railwayPhases("BUILDING")).toEqual({ buildPhase: "building", deployPhase: "none" });
    expect(railwayPhases("DEPLOYING")).toEqual({ buildPhase: "built", deployPhase: "deploying" });
    expect(railwayPhases("SUCCESS")).toEqual({ buildPhase: "built", deployPhase: "deployed" });
    expect(railwayPhases("FAILED")).toEqual({ buildPhase: "failed", deployPhase: "none" });
    // CRASHED = built+deployed then runtime crash (a health concern, not a deploy failure).
    expect(railwayPhases("CRASHED")).toEqual({ buildPhase: "built", deployPhase: "deployed" });
    expect(railwayPhases("WAITING")).toEqual({ buildPhase: "queued", deployPhase: "none" });
    expect(railwayPhases("REMOVED")).toEqual({ buildPhase: "canceled", deployPhase: "none" });
    expect(railwayPhases("SKIPPED")).toEqual({ buildPhase: "canceled", deployPhase: "none" });
  });
});

describe("combinedStatus", () => {
  it("collapses phases into one status for the Details/KPI views", () => {
    expect(combinedStatus({ buildPhase: "failed", deployPhase: "none" })).toBe("failed");
    expect(combinedStatus({ buildPhase: "built", deployPhase: "failed" })).toBe("failed");
    expect(combinedStatus({ buildPhase: "built", deployPhase: "deployed" })).toBe("success");
    expect(combinedStatus({ buildPhase: "built", deployPhase: "none" })).toBe("success");
    expect(combinedStatus({ buildPhase: "building", deployPhase: "none" })).toBe("building");
    expect(combinedStatus({ buildPhase: "built", deployPhase: "deploying" })).toBe("building");
    // Cloudflare Workers: no build lifecycle, just live.
    expect(combinedStatus({ buildPhase: null, deployPhase: "deployed" })).toBe("success");
    // No data yet (null build, no deploy) falls back to "building".
    expect(combinedStatus({ buildPhase: null, deployPhase: "none" })).toBe("building");
    expect(combinedStatus({ buildPhase: "queued", deployPhase: "none" })).toBe("queued");
  });

  it('"unknown" (expired unconfirmable) is terminal and never re-reads as building', () => {
    expect(combinedStatus({ buildPhase: "unknown", deployPhase: "none" })).toBe("unknown");
    expect(combinedStatus({ buildPhase: "built", deployPhase: "unknown" })).toBe("unknown");
    expect(combinedStatus({ buildPhase: "unknown", deployPhase: "failed" })).toBe("failed");
  });
});
