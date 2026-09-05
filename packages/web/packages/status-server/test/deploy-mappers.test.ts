import { describe, it, expect } from "vitest";
import { mapRailwayDeployEvent, mapVercelDeployEvent } from "../src/monitor/webhook-events";

const vercelEvent = (over: Record<string, unknown> = {}) => ({
  type: "deployment.succeeded",
  createdAt: "2026-08-02T10:00:00.000Z",
  payload: {
    target: "production",
    project: { id: "prj_abc123" },
    deployment: { id: "dpl_1", name: "hub-help-testing", url: "hub-help-testing.vercel.app", meta: {} },
  },
  ...over,
});

const railwayEvent = (over: Record<string, unknown> = {}) => ({
  id: "dep-1",
  status: "SUCCESS",
  project: { id: "proj-uuid-1234", name: "adh-backend" },
  environment: { name: "scratch1" },
  timestamp: "2026-08-02T10:00:00.000Z",
  ...over,
});

describe("mapVercelDeployEvent", () => {
  it.each([
    // `created` is the deployment ENTERING the queue, not starting — with a build
    // slot busy it can sit here for hours. `build-requested` is the transition out.
    ["deployment.created",         "queued",   "none"],
    ["deployment.build-requested", "building", "none"],
    ["deployment.succeeded",       "built",    "none"],
    ["deployment.ready",           "built",    "none"],
    ["deployment.promoted",        "built",    "deployed"],
    ["deployment.error",           "failed",   "none"],
    ["deployment.canceled",        "canceled", "none"],
  ])("%s maps to %s/%s", (type, buildPhase, deployPhase) => {
    const out = mapVercelDeployEvent(vercelEvent({ type }));
    expect(out).toMatchObject({ id: "vc_dpl_1", platform: "vercel", buildPhase, deployPhase });
  });

  /** The board's whole complaint: a queued deploy that starts building must SAY so.
   *  Both events must map, and to DIFFERENT build phases, or the transition is
   *  invisible however promptly the event arrives. */
  it("distinguishes entering the queue from leaving it", () => {
    const queued = mapVercelDeployEvent(vercelEvent({ type: "deployment.created" }));
    const started = mapVercelDeployEvent(vercelEvent({ type: "deployment.build-requested" }));
    expect(queued?.buildPhase).toBe("queued");
    expect(started?.buildPhase).toBe("building");
    expect(queued?.id).toBe(started?.id); // same deployment row, two phases
  });

  it("returns null for an event type we do not ingest", () => {
    expect(mapVercelDeployEvent(vercelEvent({ type: "project.created" }))).toBeNull();
    expect(mapVercelDeployEvent({})).toBeNull();
  });

  it("returns null when the deployment id or name is missing", () => {
    expect(mapVercelDeployEvent(vercelEvent({
      payload: { target: "production", deployment: { name: "hub-help-testing" } },
    }))).toBeNull();
    expect(mapVercelDeployEvent(vercelEvent({
      payload: { target: "production", deployment: { id: "dpl_1" } },
    }))).toBeNull();
  });

  it("carries the environment from `target`, and null for a preview", () => {
    expect(mapVercelDeployEvent(vercelEvent())?.environment).toBe("production");
    expect(mapVercelDeployEvent(vercelEvent({
      payload: { target: null, deployment: { id: "dpl_1", name: "hub-help-testing", meta: {} } },
    }))?.environment).toBeNull();
  });

  it.each([
    ["absent", undefined],
    ["garbage", "not-a-date"],
  ])("falls back to receipt time for a %s timestamp — never Invalid Date", (_label, createdAt) => {
    const before = Date.now();
    const out = mapVercelDeployEvent(vercelEvent({ createdAt }));
    expect(Number.isFinite(out?.createdAt.getTime())).toBe(true);
    expect(out!.createdAt.getTime()).toBeGreaterThanOrEqual(before);
  });

  it("carries providerProjectId from payload.project — the identity the board keys on", () => {
    // The old assertion here claimed "the Vercel webhook payload carries no project id"
    // and pinned null. It does carry one, and without it a webhook-created row is
    // matchable only by NAME — so a renamed project's push arrives, gets written, and
    // still owns no board target until the next full poll rewrites the row.
    expect(mapVercelDeployEvent(vercelEvent())?.providerProjectId).toBe("prj_abc123");
  });

  it("falls back to null when the payload omits the project — never undefined-by-accident", () => {
    const out = mapVercelDeployEvent(vercelEvent({
      payload: { target: "production", deployment: { id: "dpl_1", name: "hub-help-testing", meta: {} } },
    }));
    // `upsertDeployments` COALESCEs the column, so a null here cannot erase an id an
    // earlier poll already learned for the same deployment.
    expect(out?.providerProjectId).toBeNull();
  });
});

describe("mapRailwayDeployEvent", () => {
  it.each([
    ["SUCCESS",  "built",    "deployed"],
    ["CRASHED",  "built",    "deployed"],
    ["FAILED",   "failed",   "none"],
    ["BUILDING", "building", "none"],
    ["WAITING",  "queued",   "none"],
    ["REMOVED",  "canceled", "none"],
  ])("%s maps to %s/%s", (status, buildPhase, deployPhase) => {
    const out = mapRailwayDeployEvent(railwayEvent({ status }));
    expect(out).toMatchObject({ id: "ry_dep-1", platform: "railway", buildPhase, deployPhase });
  });

  it("derives the status from a dotted `type` when `status` is absent", () => {
    const out = mapRailwayDeployEvent(railwayEvent({ status: undefined, type: "Deployment.crashed" }));
    expect(out).toMatchObject({ buildPhase: "built", deployPhase: "deployed" });
  });

  it("returns null when the id, the status, or the project name is missing", () => {
    expect(mapRailwayDeployEvent(railwayEvent({ id: undefined }))).toBeNull();
    expect(mapRailwayDeployEvent(railwayEvent({ status: undefined, type: undefined }))).toBeNull();
    expect(mapRailwayDeployEvent(railwayEvent({ project: { id: "proj-uuid-1234" } }))).toBeNull();
  });

  it.each([
    ["absent", undefined],
    ["garbage", "whenever"],
  ])("falls back to receipt time for a %s timestamp — never Invalid Date", (_label, timestamp) => {
    const before = Date.now();
    const out = mapRailwayDeployEvent(railwayEvent({ timestamp }));
    expect(Number.isFinite(out?.createdAt.getTime())).toBe(true);
    expect(out!.createdAt.getTime()).toBeGreaterThanOrEqual(before);
  });

  // THE NEW BEHAVIOUR. `project.id` was already parsed here (`:68`) and used to build
  // the console URL (`:100`) — and then thrown away. Identity keyed on the name alone
  // is what makes a renamed project mint a second, permanent phantom target.
  it("carries the project id through instead of discarding it", () => {
    const out = mapRailwayDeployEvent(railwayEvent());
    expect(out?.providerProjectId).toBe("proj-uuid-1234");
    expect(out?.projectName).toBe("adh-backend");
  });

  it("still maps when no project id is present", () => {
    const out = mapRailwayDeployEvent(railwayEvent({ project: { name: "adh-backend" } }));
    expect(out?.providerProjectId ?? null).toBeNull();
    expect(out?.projectName).toBe("adh-backend");
  });
});
