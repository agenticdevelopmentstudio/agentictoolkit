import { describe, it, expect } from "vitest";
import * as web from "./deploy-status";
// The SERVER's vocabulary module, imported by relative path (the two packages share no
// build). This is the whole point of the test — pin the hand-mirror against the original.
import * as server from "@agentic-toolkit/status-server/deploy-status";

// DRIFT GUARD. web/src/lib/deploy-status.ts is a HAND COPY of src/monitor/deploy-status.ts
// (there is no shared package between the backend and its embedded web app). If the two
// drift — a new in-flight phase added server-side but not here, a combinedStatus branch
// that differs — the board silently mislabels deploys with no compile error to catch it.
// This test imports BOTH and asserts they agree across the full phase space.
describe("deploy-status vocabulary parity (web mirrors server)", () => {
  const BUILD_PHASES = [null, "queued", "building", "built", "failed", "canceled", "unknown"] as const;
  const DEPLOY_PHASES = ["none", "deploying", "deployed", "failed", "unknown"] as const;

  it("shares the in-flight phase vocabulary", () => {
    expect([...web.IN_FLIGHT_BUILD_PHASES]).toEqual([...server.IN_FLIGHT_BUILD_PHASES]);
    expect(web.IN_FLIGHT_DEPLOY_PHASE).toBe(server.IN_FLIGHT_DEPLOY_PHASE);
  });

  it("isInFlight agrees for every (build, deploy) phase pair", () => {
    for (const b of BUILD_PHASES) {
      for (const d of DEPLOY_PHASES) {
        expect(web.isInFlight(b, d)).toBe(server.isInFlight(b, d));
      }
    }
  });

  it("combinedStatus agrees for every (build, deploy) phase pair", () => {
    for (const b of BUILD_PHASES) {
      for (const d of DEPLOY_PHASES) {
        const phases = { buildPhase: b, deployPhase: d };
        expect(web.combinedStatus(phases)).toBe(server.combinedStatus(phases));
      }
    }
  });
});
