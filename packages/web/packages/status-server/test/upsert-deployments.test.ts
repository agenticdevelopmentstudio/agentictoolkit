import { describe, it, expect } from "vitest";
import { eq } from "drizzle-orm";
import { freshDb } from "./helpers/db";
import { upsertDeployments } from "../src/monitor/sync";
import { deployments } from "../src/libsql/schema";
import type { ProviderDeploy } from "../src/monitor/provider-deploy";

const deploy = (over: Partial<ProviderDeploy> = {}): ProviderDeploy => ({
  id: "vc_d1", platform: "vercel", projectName: "hub-help-testing",
  buildPhase: "built", deployPhase: "deployed", environment: "production",
  commitHash: null, commitMessage: null, branch: null, commitRepo: null, url: null,
  createdAt: new Date("2026-08-02T10:00:00.000Z"),
  ...over,
});

const rowOf = async (db: Awaited<ReturnType<typeof freshDb>>) =>
  (await db.select().from(deployments).where(eq(deployments.id, "vc_d1")))[0];

describe("upsertDeployments", () => {
  it("sets provider_project_id on insert and refreshes it on conflict", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [deploy({ providerProjectId: "prj_abc" })]);
    expect((await rowOf(db)).providerProjectId).toBe("prj_abc");

    // A sparser source (a webhook with no id) must not ERASE it.
    await upsertDeployments(db, [deploy({ providerProjectId: null })], { source: "webhook" });
    expect((await rowOf(db)).providerProjectId).toBe("prj_abc");

    // A richer source with a NEW id wins — this is how a backfill lands.
    await upsertDeployments(db, [deploy({ providerProjectId: "prj_xyz" })]);
    expect((await rowOf(db)).providerProjectId).toBe("prj_xyz");
  });

  it("follows an upstream RENAME — projectName is refreshed, not frozen at insert", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [deploy({ providerProjectId: "prj_abc" })]);
    expect((await rowOf(db)).projectName).toBe("hub-help-testing");

    // Same deployment id, new project name. Leaving the row at the old name would keep it
    // in a second `groupBy(platform, projectName, environment)` bucket for the whole 90-day
    // retention — one target reported twice, permanently.
    await upsertDeployments(db, [deploy({ projectName: "hub-help", providerProjectId: "prj_abc" })]);
    expect((await rowOf(db)).projectName).toBe("hub-help");
  });

  it("a stale in-flight WEBHOOK does not regress a stored verdict", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [deploy({ buildPhase: "failed", deployPhase: "none" })]);
    await upsertDeployments(db, [deploy({ buildPhase: "building", deployPhase: "none" })], { source: "webhook" });
    expect((await rowOf(db)).buildPhase).toBe("failed");
  });

  it("a POLL may move a row back to in-flight — its by-id state is current truth", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [deploy({ buildPhase: "built", deployPhase: "deployed" })]);
    await upsertDeployments(db, [deploy({ buildPhase: "built", deployPhase: "deploying" })]);
    expect((await rowOf(db)).deployPhase).toBe("deploying");
  });

  it("createdAt takes the MINIMUM and fetchedAt advances", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [deploy({ createdAt: new Date("2026-08-02T10:00:00.000Z") })]);
    const first = await rowOf(db);
    // A webhook carries EVENT-EMISSION time, always later than true creation.
    await upsertDeployments(db, [deploy({ createdAt: new Date("2026-08-02T11:00:00.000Z") })], { source: "webhook" });
    const second = await rowOf(db);
    expect(second.createdAt.toISOString()).toBe("2026-08-02T10:00:00.000Z");
    expect(second.fetchedAt.getTime()).toBeGreaterThanOrEqual(first.fetchedAt.getTime());
  });

  it("drops a row with an invalid createdAt instead of failing the batch", async () => {
    const db = await freshDb();
    await upsertDeployments(db, [
      deploy({ id: "vc_bad", createdAt: new Date("nonsense") }),
      deploy(),
    ]);
    const rows = await db.select().from(deployments);
    expect(rows.map((r) => r.id)).toEqual(["vc_d1"]);
  });
});
