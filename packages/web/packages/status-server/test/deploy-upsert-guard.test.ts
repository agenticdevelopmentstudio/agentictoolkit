import { describe, it, expect } from "vitest";
import { createClient } from "@libsql/client";
import { drizzle } from "drizzle-orm/libsql";
import { migrate } from "drizzle-orm/libsql/migrator";
import { eq } from "drizzle-orm";
import * as schema from "../src/libsql/schema";
import { deployments } from "../src/libsql/schema";
import type { Db } from "../src/libsql/client";
import { upsertDeployments } from "../src/monitor/sync";
import type { ProviderDeploy } from "../src/monitor/provider-deploy";
import type { BuildPhase, DeployPhase } from "../src/monitor/deploy-status";
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

async function bootDb(): Promise<Db> {
  const db: Db = drizzle(createClient({ url: ":memory:" }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

const ID = "vc_dpl_1";

function deploy(buildPhase: BuildPhase, deployPhase: DeployPhase = "none"): ProviderDeploy {
  return {
    id: ID,
    platform: "vercel",
    projectName: "recipes-testing",
    providerProjectId: "prj_1",
    buildPhase,
    deployPhase,
    environment: "production",
    commitHash: "abc1234",
    commitMessage: "a commit",
    branch: "main",
    commitRepo: "agenticdevelopmentstudio/agenticdeveloperhub-deployment",
    url: "https://recipes-testing.vercel.app",
    createdAt: new Date("2026-08-09T14:00:00.000Z"),
  };
}

async function phasesOf(db: Db): Promise<{ buildPhase: string | null; deployPhase: string }> {
  const [r] = await db.select().from(deployments).where(eq(deployments.id, ID));
  return { buildPhase: r!.buildPhase, deployPhase: r!.deployPhase };
}

/**
 * The webhook regression guard, over the pair of events that spell "left the queue".
 *
 * Vercel announces a build twice: `deployment.created` when it ENTERS the queue and
 * `deployment.build-requested` when a concurrency slot frees and it actually starts. Both
 * now map (they did not always — `build-requested` was dropped), and both are IN FLIGHT.
 * That is what makes ordering load-bearing here: the guard's older rule only refuses an
 * in-flight event that would overwrite a real VERDICT, so it has nothing to say about one
 * in-flight phase overwriting another.
 */
describe("upsertDeployments — webhook build-phase ordering", () => {
  it("lets a build-requested webhook move a queued row to building", async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy("queued")], { source: "webhook" });
    await upsertDeployments(db, [deploy("building")], { source: "webhook" });
    expect(await phasesOf(db)).toEqual({ buildPhase: "building", deployPhase: "none" });
  });

  /** THE REGRESSION. Two independent POSTs can land in either order, and a 503 from the
   *  ownership check makes Vercel redeliver — so a `created` arriving after its own
   *  `build-requested` is ordinary, not exotic. Without an ordering rule it drags the
   *  board backwards: a site that visibly started building reverts to "queued". */
  it("refuses a late deployment.created that would drag building back to queued", async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy("building")], { source: "webhook" });
    await upsertDeployments(db, [deploy("queued")], { source: "webhook" });
    expect(await phasesOf(db)).toEqual({ buildPhase: "building", deployPhase: "none" });
  });

  it("still refuses an in-flight webhook that would overwrite a settled verdict", async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy("built", "deployed")], { source: "webhook" });
    await upsertDeployments(db, [deploy("queued")], { source: "webhook" });
    expect(await phasesOf(db)).toEqual({ buildPhase: "built", deployPhase: "deployed" });
  });

  /** A terminal event is current truth whichever in-flight phase it lands on. */
  it.each(["queued", "building"] as const)("lets a terminal webhook settle a %s row", async (from) => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy(from)], { source: "webhook" });
    await upsertDeployments(db, [deploy("failed")], { source: "webhook" });
    expect((await phasesOf(db)).buildPhase).toBe("failed");
  });

  /** The POLL is unguarded on purpose — its by-id read is current provider truth, so it
   *  must be able to correct the row in EITHER direction. The ordering rule is a webhook
   *  rule and must not have leaked into it. */
  it("leaves the poll free to move a row backwards", async () => {
    const db = await bootDb();
    await upsertDeployments(db, [deploy("building")], { source: "webhook" });
    await upsertDeployments(db, [deploy("queued")], { source: "poll" });
    expect((await phasesOf(db)).buildPhase).toBe("queued");
  });
});
