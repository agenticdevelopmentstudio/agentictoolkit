import { describe, it, expect } from "vitest";
import { eq } from "drizzle-orm";
import { freshDb } from "./helpers/db";
import { learnDeployProjectIds } from "../src/monitor/sync";
import { siteGroups, monitoredSites, monitoredEndpoints } from "../src/libsql/schema";
import type { ProviderDeploy } from "../src/monitor/provider-deploy";

const deploy = (over: Partial<ProviderDeploy> = {}): ProviderDeploy => ({
  id: "vc_d1", platform: "vercel", projectName: "hub-help-testing",
  buildPhase: "built", deployPhase: "deployed", environment: "production",
  commitHash: null, commitMessage: null, branch: null, commitRepo: null, url: null,
  createdAt: new Date("2026-08-02T10:00:00.000Z"),
  ...over,
});

async function seedEndpoint(
  db: Awaited<ReturnType<typeof freshDb>>,
  ep: { platform: string | null; deployProject: string | null; deployProjectId?: string | null },
) {
  const [g] = await db.insert(siteGroups).values({ slug: "g", name: "G" }).returning();
  const [s] = await db.insert(monitoredSites).values({ siteGroupId: g.id, slug: "s", name: "S" }).returning();
  const [e] = await db
    .insert(monitoredEndpoints)
    .values({ siteId: s.id, url: "https://example.test", ...ep })
    .returning();
  return e.id;
}

const idOf = async (db: Awaited<ReturnType<typeof freshDb>>, id: string) =>
  (await db.select().from(monitoredEndpoints).where(eq(monitoredEndpoints.id, id)))[0].deployProjectId;

describe("learnDeployProjectIds", () => {
  it("fills a null id from the deploy whose name already matches", async () => {
    const db = await freshDb();
    const id = await seedEndpoint(db, { platform: "vercel", deployProject: "hub-help-testing" });
    await learnDeployProjectIds(db, [deploy({ providerProjectId: "prj_abc" })]);
    expect(await idOf(db, id)).toBe("prj_abc");
  });

  it("never overwrites an id already recorded — the operator's value wins", async () => {
    const db = await freshDb();
    const id = await seedEndpoint(db, {
      platform: "vercel", deployProject: "hub-help-testing", deployProjectId: "prj_operator",
    });
    await learnDeployProjectIds(db, [deploy({ providerProjectId: "prj_abc" })]);
    expect(await idOf(db, id)).toBe("prj_operator");
  });

  it("matches per PLATFORM, so a same-named project elsewhere cannot claim the endpoint", async () => {
    const db = await freshDb();
    const id = await seedEndpoint(db, { platform: "railway", deployProject: "hub-help-testing" });
    await learnDeployProjectIds(db, [deploy({ providerProjectId: "prj_abc" })]);
    expect(await idOf(db, id)).toBeNull();
  });

  it("canonicalises the platform, so a `cloudflare-pages` deploy matches a `cloudflare` endpoint", async () => {
    const db = await freshDb();
    const id = await seedEndpoint(db, { platform: "cloudflare", deployProject: "docs" });
    await learnDeployProjectIds(db, [
      deploy({ platform: "cloudflare-pages", projectName: "docs", providerProjectId: "cf_1" }),
    ]);
    expect(await idOf(db, id)).toBe("cf_1");
  });

  it("writes nothing when no deploy carries an id", async () => {
    const db = await freshDb();
    const id = await seedEndpoint(db, { platform: "vercel", deployProject: "hub-help-testing" });
    await learnDeployProjectIds(db, [deploy()]);
    expect(await idOf(db, id)).toBeNull();
  });
});
