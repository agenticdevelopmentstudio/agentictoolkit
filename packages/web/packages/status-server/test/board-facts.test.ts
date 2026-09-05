import { describe, it, expect } from "vitest";
import { eq } from "drizzle-orm";
import { freshDb } from "./helpers/db";
import { readBoardFacts } from "../src/board/facts";
import { deriveBoard } from "../src/board/derive";
import { deployments, monitoredEndpoints, monitoredSites, siteGroups } from "../src/libsql/schema";
import { deployProjectMeta, healthChecks, issues, platformHealthState, vercelProdState } from "../src/libsql/schema";
import { PLATFORM_UNREACHABLE_POLLS } from "../src/monitor/issue-sources";
import { latestCheckBySlugSql } from "../src/storage/health-store";
import { ACTIVITY_WINDOW_MS, MAX_ACTIVITY_ROWS } from "../src/board/types";
import { testConfig } from "./helpers/config";

const config = testConfig();

async function seedSite(db: Awaited<ReturnType<typeof freshDb>>) {
  // Every id here is a text uuid, `monitoredSites` keys on `siteGroupId`, and endpoints
  // have no `label` column — the display name comes from the site.
  await db.insert(siteGroups).values({ id: "grp-1", name: "Hub", slug: "hub" });
  await db.insert(monitoredSites).values({ id: "site-1", siteGroupId: "grp-1", name: "Hub Help", slug: "hub-help" });
  await db.insert(monitoredEndpoints).values({
    id: "ep-1", siteId: "site-1", url: "https://testing.help.example.com",
    platform: "vercel", deployProject: "hub-help-testing", environment: "production", isActive: true,
  });
}

describe("readBoardFacts", () => {
  it("returns the latest CONCLUSIVE deploy per target, dropping canceled and unknown", async () => {
    const db = await freshDb();
    await seedSite(db);
    const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
    await db.insert(deployments).values([
      { ...base, id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(1000) },
      { ...base, id: "vc_d2", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(2000) },
      { ...base, id: "vc_d3", buildPhase: "canceled", deployPhase: "none", createdAt: new Date(3000) },
    ]);
    const facts = await readBoardFacts(db, 4000, config);
    expect(facts.deploys).toHaveLength(1);
    expect(facts.deploys[0]).toMatchObject({ buildPhase: "built", createdAtMs: 2000 });
    expect(facts.inFlightDeploys).toEqual([]);
  });

  it("separates a still-BUILDING row from the verdict rows, so a retry cannot clear a failure", async () => {
    const db = await freshDb();
    await seedSite(db);
    const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
    await db.insert(deployments).values([
      { ...base, id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(1000) },
      { ...base, id: "vc_d2", buildPhase: "building", deployPhase: "none", createdAt: new Date(2000) },
    ]);
    const facts = await readBoardFacts(db, 3000, config);
    // The newest row is the retry, but it is NOT the verdict — that stays the failure.
    expect(facts.deploys).toMatchObject([{ buildPhase: "failed", createdAtMs: 1000 }]);
    expect(facts.inFlightDeploys).toMatchObject([{ buildPhase: "building", createdAtMs: 2000 }]);
    const board = deriveBoard(facts, 3000);
    expect(board.problems).toHaveLength(1);
    expect(board.problems[0].state).toBe("failed");
  });

  it("collapses two SPELLINGS of one project to a single problem — SQL groups by name, the fold groups by target", async () => {
    const db = await freshDb();
    await seedSite(db);
    // The endpoint has adopted the provider id; upstream the project was then renamed, so
    // the table holds rows under both names inside the retention window.
    await db.update(monitoredEndpoints).set({ deployProjectId: "prj_abc" });
    await db.insert(deployments).values([
      { platform: "vercel", projectName: "hub-help-testing", providerProjectId: null, environment: "production",
        id: "vc_old", buildPhase: "failed", deployPhase: "none", createdAt: new Date(1000) },
      { platform: "vercel", projectName: "hub-help", providerProjectId: "prj_abc", environment: "production",
        id: "vc_new", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(2000) },
    ]);
    const facts = await readBoardFacts(db, 3000, config);
    // SQL cannot tell they are one target: two rows come back.
    expect(facts.deploys).toHaveLength(2);
    // The fold can, and the newer row — the successful rebuild — wins.
    expect(deriveBoard(facts, 3000).problems).toEqual([]);

    // Flip which spelling is newer: now the failure is current, and it is still ONE row,
    // keyed by the roster entry's identity rather than either project name.
    await db.update(deployments).set({ createdAt: new Date(4000) }).where(eq(deployments.id, "vc_old"));
    const board = deriveBoard(await readBoardFacts(db, 5000, config), 5000);
    expect(board.problems).toHaveLength(1);
    expect(board.problems[0].target).toBe("vercel|prj_abc|");
  });

  it("END TO END: a site whose latest deploy succeeded has no problems", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(2000),
    });
    const board = deriveBoard(await readBoardFacts(db, 3000, config), 3000);
    expect(board.problems).toEqual([]);
    expect(board.indicator).toBe("operational");
  });

  it("END TO END: a site whose latest deploy failed has exactly one problem", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(2000),
    });
    const board = deriveBoard(await readBoardFacts(db, 3000, config), 3000);
    expect(board.problems).toHaveLength(1);
    expect(board.problems[0].target).toBe("vercel|hub-help-testing|");
  });

  it("REQUIREMENT A end to end: flipping isActive off empties the board", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(2000),
    });
    expect(deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems).toHaveLength(1);
    await db.update(monitoredEndpoints).set({ isActive: false });
    expect(deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems).toEqual([]);
  });

  it("an endpoint with no site row contributes no roster entry", async () => {
    const db = await freshDb();
    const facts = await readBoardFacts(db, 1000, config);
    expect(facts.roster).toEqual([]);
  });

  it("carries the operator's ignoreProjectWarning opt-out, so an opted-out endpoint owns no deploy target", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(2000),
    });
    expect(deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems).toHaveLength(1);
    // Reading this column rather than hardcoding false is the whole point: the fold and
    // every deploy surface outside it now share one ownership rule (`board/ownership.ts`),
    // so the operator's opt-out has to reach the roster to be honoured anywhere.
    await db.update(monitoredEndpoints).set({ ignoreProjectWarning: true });
    const facts = await readBoardFacts(db, 3000, config);
    expect(facts.roster[0].ignoreProjectWarning).toBe(true);
    expect(deriveBoard(facts, 3000).problems).toEqual([]);
  });

  // The three facts that were poll-local. Each of these fails today by returning `[]`,
  // which is the quiet kind of wrong: `deriveBoard` would emit no platform-health and no
  // stale-production problems at all, and the suite above would still be green.
  it("reads platform health from the persisted state, not from a poll in flight", async () => {
    const db = await freshDb();
    await db.insert(platformHealthState).values({
      source: "vercel", consecutiveFailures: 3, configured: true, reachable: false, updatedAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    // `sampledAtMs` is `updated_at`, which `recordPlatformObservations` rewrites every cycle
    // whether or not the verdict changed — that is what makes it the monitor's heartbeat and
    // the board's data clock (`dataAsOf`). Reading `nowMs` here instead would make the clock
    // certify its own freshness, which is the wedged-monitor hole it exists to close.
    expect(facts.platforms).toEqual([
      { source: "vercel", configured: true, ok: false, streak: 3, sampledAtMs: 1000 },
    ]);
  });

  it("reads Vercel production staleness from the persisted state", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: true, detail: "live deploy errored",
      sourceUrl: "https://vercel.com/x/y", liveUrl: "https://testing.help.example.com", updatedAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.staleProd).toEqual([{
      platform: "vercel", providerProjectId: null, projectName: "hub-help-testing", environment: null,
      // No `deploy_project_meta` row was seeded, so there is no branch to read. NULL is
      // the honest answer and hands the tier decision back to the project-name rule; the
      // LEFT join below is what stops the missing row deleting the fact instead.
      branch: null,
      detail: "live deploy errored", sourceUrl: "https://vercel.com/x/y", liveUrl: "https://testing.help.example.com",
    }]);
  });

  it("joins each stale project to its CONFIGURED production branch", async () => {
    // The tier evidence for a stale-prod fact. `vercel_prod_state` has no branch column of
    // its own — it is keyed on the project name and says nothing about what the project
    // builds — so `staleProdProblems` can only read the tier off the name unless this join
    // supplies the branch. `hub-help-testing` deploys from `prepared`, and `prepared` is
    // testing.
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployProjectMeta).values({
      platform: "vercel", projectName: "hub-help-testing", gitBranch: "prepared",
    });
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: true, detail: "live deploy errored",
      sourceUrl: null, liveUrl: null, updatedAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.staleProd).toHaveLength(1);
    expect(facts.staleProd[0]!.branch).toBe("prepared");
  });

  it("a stale project with NO meta row at all still contributes its fact", async () => {
    // LEFT, not inner. A project polled before the meta mirror existed has no row there,
    // and an inner join would silently delete its staleness from the board — a monitoring
    // gap dressed as a clean bill of health. Nothing is seeded into `deploy_project_meta`
    // here on purpose: this is the literal empty-mirror case.
    const db = await freshDb();
    await seedSite(db);
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: true, detail: "live deploy errored",
      sourceUrl: null, liveUrl: null, updatedAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.staleProd).toHaveLength(1);
    expect(facts.staleProd[0]!.branch).toBeNull();
  });

  it("a meta row for the SAME name on another platform supplies no branch, and drops nothing", async () => {
    // The join is keyed (platform, project_name), and `vercel_prod_state` is Vercel's
    // mirror — a Railway project that happens to share the name must neither lend its
    // branch (which would badge the tier off an unrelated pipeline) nor, because the join
    // is LEFT, take the stale fact down with it when it fails to match.
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployProjectMeta).values({
      platform: "railway", projectName: "hub-help-testing", gitBranch: "production",
    });
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: true, detail: "live deploy errored",
      sourceUrl: null, liveUrl: null, updatedAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.staleProd).toHaveLength(1);
    expect(facts.staleProd[0]!.branch).toBeNull();
  });

  it("carries a deployment's BRANCH through to the fact", async () => {
    // The column exists and all four ingest paths populate it; the fold could not read the
    // tier off it while the transcription dropped it here.
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", branch: "prepared", buildPhase: "built", deployPhase: "deployed",
      createdAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.deploys[0]!.branch).toBe("prepared");
    expect(facts.deployEvents[0]!.branch).toBe("prepared");
  });

  it("carries a failed deployment's provider errorText through to the fact", async () => {
    // The only text the provider ever gives about WHY a build failed. It reaches the
    // details pane's error block or nowhere; the transcription here is the first link.
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none",
      errorText: '[buildStep] Command "next build" exited with 1',
      createdAt: new Date(1000),
    });
    const facts = await readBoardFacts(db, 2000, config);
    expect(facts.deploys[0]!.errorText).toBe('[buildStep] Command "next build" exited with 1');
    expect(facts.deployEvents[0]!.errorText).toBe('[buildStep] Command "next build" exited with 1');
  });

  it("carries only the STALE projects — a healthy row is not a fact the fold needs", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: false, detail: null, sourceUrl: null, liveUrl: null, updatedAt: new Date(1000),
    });
    expect((await readBoardFacts(db, 2000, config)).staleProd).toEqual([]);
  });

  it("reads the live Vercel project list from the deploy_project_meta mirror", async () => {
    const db = await freshDb();
    await db.insert(deployProjectMeta).values([
      { platform: "vercel", projectName: "hub-help-testing" },
      { platform: "railway", projectName: "adh-backend" },
    ]);
    expect((await readBoardFacts(db, 2000, config)).liveVercelProjects).toEqual(["hub-help-testing"]);
  });

  // `deploys` and `deployEvents` select the same table differently, and the difference IS
  // the fix for Activity-as-a-projection. These two tests are the only place that shows it.
  it("returns EVERY windowed deploy as an event, including the canceled one `deploys` drops", async () => {
    const db = await freshDb();
    await seedSite(db);
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
    await db.insert(deployments).values([
      { ...base, id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(now - 3_000) },
      { ...base, id: "vc_d2", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(now - 2_000) },
      { ...base, id: "vc_d3", buildPhase: "canceled", deployPhase: "none", createdAt: new Date(now - 1_000) },
    ]);
    const facts = await readBoardFacts(db, now, config);
    expect(facts.deploys).toHaveLength(1);
    expect(facts.deployEvents.map((d) => d.buildPhase)).toEqual(["canceled", "built", "failed"]);
  });

  it("spends the activity budget on rows the fold can KEEP — 300 previews cannot bury one real deploy", async () => {
    // The budget used to be spent before the fold's filters, so a fleet-wide push (or a
    // busy PR day) could fill all 300 newest rows with Vercel PREVIEW builds — every one
    // of which `ownedDeployTarget` then dropped, leaving the feed's deploy half empty
    // precisely when the most was happening.
    const db = await freshDb();
    await seedSite(db);
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    const real = {
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_real", buildPhase: "built" as const, deployPhase: "deployed" as const,
      createdAt: new Date(now - 600_000),
    };
    await db.insert(deployments).values(real);
    // NEWER than the real deploy, so under the old order+limit they would displace it.
    await db.insert(deployments).values(
      Array.from({ length: MAX_ACTIVITY_ROWS }, (_, i) => ({
        platform: "vercel", projectName: "hub-help-testing", environment: null,
        id: `vc_preview_${i}`, buildPhase: "built" as const, deployPhase: "deployed" as const,
        createdAt: new Date(now - 1_000 - i),
      })),
    );

    const facts = await readBoardFacts(db, now, config);
    // The previews never reach the fold at all — the budget holds only real deploys.
    expect(facts.deployEvents).toHaveLength(1);
    expect(facts.deployEvents[0]).toMatchObject({ environment: "production", createdAtMs: now - 600_000 });

    const activity = deriveBoard(facts, now).activity;
    expect(activity.filter((r) => r.kind === "deploy").length).toBeGreaterThan(0);
  });

  it("and spends it only on projects a live site MONITORS — 300 unowned deploys cannot bury one", async () => {
    // The other half of the same budget. `sync` upserts a row for every project the tokens
    // can see and the unmonitored ones outnumber the monitored ones ~3:1, so filtering only
    // previews left the newest-300 window still dominated by rows the fold would drop —
    // the same empty deploy feed, reached through projects instead of previews.
    const db = await freshDb();
    await seedSite(db);
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_real", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(now - 600_000),
    });
    await db.insert(deployments).values(
      Array.from({ length: MAX_ACTIVITY_ROWS }, (_, i) => ({
        platform: "vercel", projectName: `somebody-elses-${i}`, environment: "production",
        id: `vc_other_${i}`, buildPhase: "built" as const, deployPhase: "deployed" as const,
        createdAt: new Date(now - 1_000 - i),
      })),
    );

    const facts = await readBoardFacts(db, now, config);
    expect(facts.deployEvents.map((d) => d.projectName)).toEqual(["hub-help-testing"]);
  });

  it("keeps a CRUNCHY cluster in the activity budget — nobody owns one, everybody watches it", async () => {
    // The pre-filter is the SQL spelling of `ownsDeployProject`, whose crunchy carve-out is
    // load-bearing: narrowing to the roster alone would drop every cluster event, and no
    // roster entry can ever be wired to a database with no HTTP host.
    const db = await freshDb();
    await seedSite(db);
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(deployments).values({
      platform: "crunchy", projectName: "prod-cluster", environment: null,
      id: "cr_1", buildPhase: null, deployPhase: "failed", createdAt: new Date(now - 60_000),
    });
    const facts = await readBoardFacts(db, now, config);
    expect(facts.deployEvents.map((d) => d.projectName)).toEqual(["prod-cluster"]);
  });

  it("drops deploy events older than the activity window", async () => {
    const db = await freshDb();
    await seedSite(db);
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_old", buildPhase: "built", deployPhase: "deployed",
      createdAt: new Date(now - ACTIVITY_WINDOW_MS - 1),
    });
    const facts = await readBoardFacts(db, now, config);
    expect(facts.deployEvents).toEqual([]);
    // Still the current state, though — Problems are not windowed.
    expect(facts.deploys).toHaveLength(1);
  });

  it("returns issues opened OR resolved in the window, carrying the resolve reason", async () => {
    const db = await freshDb();
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    // No `id` — `issues.id` is `integer primaryKey({ autoIncrement: true })`
    // (`schema.ts:108`), NOT a text uuid like every other table here. Supplying a string
    // throws SQLITE_MISMATCH at insert time rather than failing an assertion.
    await db.insert(issues).values([
      { target: "ep-1", source: "http", name: "Hub Help", state: "down", severity: "critical",
        openedAt: new Date(now - 3600_000), resolvedAt: new Date(now - 60_000), resolvedReason: "recovered" },
      { target: "ep-2", source: "http", name: "Other", state: "down", severity: "critical",
        openedAt: new Date(now - ACTIVITY_WINDOW_MS - 10_000) },
    ]);
    const facts = await readBoardFacts(db, now, config);
    expect(facts.issueEvents.map((e) => e.target)).toEqual(["ep-1"]);
    expect(facts.issueEvents[0]).toMatchObject({ resolvedReason: "recovered", openedAtMs: now - 3600_000 });
  });

  it("reads an unrecognised resolve reason as unknown, so the feed claims nothing", async () => {
    const db = await freshDb();
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(issues).values({
      target: "ep-1", source: "http", name: "Hub Help", state: "down", severity: "critical",
      openedAt: new Date(now - 3600_000), resolvedAt: new Date(now - 60_000), resolvedReason: "something-else",
    });
    expect((await readBoardFacts(db, now, config)).issueEvents[0].resolvedReason).toBeNull();
  });

  it("END TO END: a persisted unreachable provider becomes a platform-health problem", async () => {
    const db = await freshDb();
    await db.insert(platformHealthState).values({
      source: "vercel", consecutiveFailures: PLATFORM_UNREACHABLE_POLLS, configured: true, reachable: false,
      updatedAt: new Date(1000),
    });
    const board = deriveBoard(await readBoardFacts(db, 2000, config), 2000);
    expect(board.problems.map((p) => p.target)).toEqual(["platform-health|vercel"]);
  });

  // The client scales its data-staleness window by the cadence and captions its activity
  // counts with the window boundary. Both used to be the CLIENT's to find — the cadence off
  // a different feed, the boundary off a constant of its own — so both are pinned here as
  // facts that ride on the board itself.
  it("carries the configured probe cadence through to the board", async () => {
    const db = await freshDb();
    const prev = process.env.PROBE_INTERVAL_SECONDS;
    process.env.PROBE_INTERVAL_SECONDS = "3600";
    try {
      expect((await readBoardFacts(db, 2000, config)).probeIntervalMs).toBe(3_600_000);
      expect(deriveBoard(await readBoardFacts(db, 2000, config), 2000).probeIntervalMs).toBe(3_600_000);
    } finally {
      if (prev === undefined) delete process.env.PROBE_INTERVAL_SECONDS;
      else process.env.PROBE_INTERVAL_SECONDS = prev;
    }
  });

  it("publishes the activity window's own lower boundary", async () => {
    const db = await freshDb();
    const nowMs = 9_000_000;
    expect(deriveBoard(await readBoardFacts(db, nowMs, config), nowMs).activityFromMs)
      .toBe(nowMs - ACTIVITY_WINDOW_MS);
  });

  // readEndpointFacts is the only genuinely novel SQL in this file — a healthy-only suite
  // never inserts a health_checks row, so a mutated (or gutted) readEndpointFacts stays
  // green. These pin its actual behaviour.
  describe("readEndpointFacts", () => {
    it("a healthy endpoint's fact has no bad run", async () => {
      const db = await freshDb();
      await seedSite(db);
      await db.insert(healthChecks).values({
        serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(1_000_000),
      });
      const facts = await readBoardFacts(db, 2_000_000, config);
      expect(facts.endpoints).toHaveLength(1);
      expect(facts.endpoints[0]).toMatchObject({ endpointId: "ep-1", status: "healthy", badSinceMs: null });
    });

    it("a down endpoint's badSince is the onset of the CURRENT bad run, not an older one", async () => {
      const db = await freshDb();
      await seedSite(db);
      const t0 = Date.UTC(2026, 7, 2, 12, 0, 0);
      await db.insert(healthChecks).values([
        // An OLDER bad run — must not leak into the current onset.
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0) },
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0 + 60_000) },
        // The healthy check that closes the older bad run and resets the boundary.
        { serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(t0 + 120_000) },
        // The CURRENT bad run — badSince must land HERE, not at the older run's onset.
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0 + 180_000) },
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0 + 240_000) },
      ]);
      const facts = await readBoardFacts(db, t0 + 300_000, config);
      expect(facts.endpoints).toHaveLength(1);
      expect(facts.endpoints[0]).toMatchObject({ status: "down", badSinceMs: t0 + 180_000 });
    });

    it("resolves EACH bad endpoint's own onset — the batched read must not share one run", async () => {
      // The onset used to be one query per bad endpoint, sequentially awaited; it is now a
      // single grouped statement for all of them. The way a batch gets that wrong is by
      // collapsing the slugs — one `min` over the union, or one slug's healthy check
      // resetting another's boundary — which is invisible with only one endpoint down, and
      // every other case in this block has exactly one.
      const db = await freshDb();
      await seedSite(db);
      await db.insert(monitoredEndpoints).values({
        id: "ep-2", siteId: "site-1", url: "https://two.example.com",
        platform: "vercel", deployProject: "hub-two", environment: "production", isActive: true,
      });
      const t0 = Date.UTC(2026, 7, 2, 12, 0, 0);
      await db.insert(healthChecks).values([
        // ep-1: bad from t0+60s onward, with an EARLIER run that a healthy check closed.
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0 - 120_000) },
        { serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(t0) },
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0 + 60_000) },
        // ep-2: bad from t0+180s, and it has NEVER been healthy — the coalesce(...,0) floor.
        { serviceSlug: "ep-2", status: "down", statusCode: 503, dnsOk: true, checkedAt: new Date(t0 + 180_000) },
        { serviceSlug: "ep-2", status: "down", statusCode: 503, dnsOk: true, checkedAt: new Date(t0 + 240_000) },
      ]);
      const facts = await readBoardFacts(db, t0 + 300_000, config);
      const bySlug = new Map(facts.endpoints.map((e) => [e.endpointId, e]));
      expect(bySlug.get("ep-1")).toMatchObject({ status: "down", badSinceMs: t0 + 60_000 });
      expect(bySlug.get("ep-2")).toMatchObject({ status: "down", badSinceMs: t0 + 180_000 });
    });

    it("a HEALTHY endpoint alongside bad ones still reports no bad run", async () => {
      // The batch asks only about the bad slugs; a healthy row must not pick up a
      // neighbour's onset through the join.
      const db = await freshDb();
      await seedSite(db);
      await db.insert(monitoredEndpoints).values({
        id: "ep-2", siteId: "site-1", url: "https://two.example.com",
        platform: "vercel", deployProject: "hub-two", environment: "production", isActive: true,
      });
      const t0 = Date.UTC(2026, 7, 2, 12, 0, 0);
      await db.insert(healthChecks).values([
        { serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(t0) },
        { serviceSlug: "ep-2", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(t0) },
      ]);
      const facts = await readBoardFacts(db, t0 + 60_000, config);
      const bySlug = new Map(facts.endpoints.map((e) => [e.endpointId, e]));
      expect(bySlug.get("ep-1")).toMatchObject({ badSinceMs: t0 });
      expect(bySlug.get("ep-2")).toMatchObject({ status: "healthy", badSinceMs: null });
    });

    it("dnsOk: false on the latest check survives the read", async () => {
      const db = await freshDb();
      await seedSite(db);
      await db.insert(healthChecks).values({
        serviceSlug: "ep-1", status: "down", statusCode: null, dnsOk: false, checkedAt: new Date(1_000_000),
      });
      const facts = await readBoardFacts(db, 2_000_000, config);
      expect(facts.endpoints[0]).toMatchObject({ dnsOk: false });
    });

    it("converts the persisted epoch SECONDS back to milliseconds exactly", async () => {
      const db = await freshDb();
      await seedSite(db);
      // A timestamp with non-trivial digits in both directions, so a truncation or
      // off-by-one-second bug in the seconds<->ms conversion cannot hide behind a round number.
      const checkedAtMs = Date.UTC(2026, 7, 2, 13, 47, 23) + 0; // whole-second boundary (storage precision)
      await db.insert(healthChecks).values({
        serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(checkedAtMs),
      });
      const facts = await readBoardFacts(db, checkedAtMs + 1000, config);
      expect(facts.endpoints[0].checkedAtMs).toBe(checkedAtMs);
    });

    it("reads only the ACTIVE roster's slugs — a retired endpoint's history is never fetched", async () => {
      // The read used to be an unpredicated `group by service_slug` over the whole table:
      // every retained row of every endpoint that ever existed, fetched on every board
      // read, only for the roster gate downstream to throw the extras away.
      const db = await freshDb();
      await seedSite(db);
      await db.insert(monitoredEndpoints).values({
        id: "ep-retired", siteId: "site-1", url: "https://gone.example.com",
        platform: "vercel", deployProject: "gone", environment: "production", isActive: false,
      });
      await db.insert(healthChecks).values([
        { serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: new Date(1_000_000) },
        { serviceSlug: "ep-retired", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(1_000_000) },
        // History for an endpoint row that is gone from config entirely.
        { serviceSlug: "ep-deleted", status: "down", statusCode: 500, dnsOk: true, checkedAt: new Date(1_000_000) },
      ]);
      const facts = await readBoardFacts(db, 2_000_000, config);
      expect(facts.endpoints.map((e) => e.endpointId)).toEqual(["ep-1"]);
    });

    it("breaks a SAME-SECOND tie the same way /live does — the later insert wins", async () => {
      // `checked_at` is whole seconds, so a manual re-probe overlapping a cycle is a real
      // tie. The board used to resolve it with SQLite's bare-column rule under
      // `max(checked_at)`, which is documented as ARBITRARY among tied rows — so /live
      // could report `healthy` from one row while the board derived `down` from the other
      // and opened a Problem, in the same request. Both now read one statement.
      const db = await freshDb();
      await seedSite(db);
      const t = new Date(1_000_000);
      await db.insert(healthChecks).values({
        serviceSlug: "ep-1", status: "down", statusCode: 500, dnsOk: true, checkedAt: t,
      });
      await db.insert(healthChecks).values({
        serviceSlug: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAt: t,
      });

      const facts = await readBoardFacts(db, 2_000_000, config);
      const live = await db.all<{ service_slug: string; status: string }>(latestCheckBySlugSql(["ep-1"]));
      expect(facts.endpoints[0].status).toBe("healthy"); // the later INSERT, deterministically
      expect(facts.endpoints[0].status).toBe(live[0]!.status);
      expect(deriveBoard(facts, 2_000_000).problems).toEqual([]);
    });
  });

  it("carries an issue that opened OUTSIDE the window but resolved INSIDE it", async () => {
    const db = await freshDb();
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(issues).values({
      target: "ep-1", source: "http", name: "Hub Help", state: "down", severity: "critical",
      // Opened 3 days ago — well outside ACTIVITY_WINDOW_MS (24h) — but resolved 5 minutes
      // ago. This is every long-outage "[down] resolved" Activity row, and it is exactly
      // the case the `openedAt OR resolvedAt` clause exists for: dropping the resolvedAt
      // half of that `or` makes this issue silently vanish from the feed.
      openedAt: new Date(now - 3 * 24 * 3600_000), resolvedAt: new Date(now - 5 * 60_000), resolvedReason: "recovered",
    });
    const facts = await readBoardFacts(db, now, config);
    expect(facts.issueEvents.map((e) => e.target)).toEqual(["ep-1"]);
  });

  it("the ledger carries only STILL-OPEN issues — a resolved row must not leak in as an onset", async () => {
    const db = await freshDb();
    const now = Date.UTC(2026, 7, 2, 12, 0, 0);
    await db.insert(issues).values([
      { target: "ep-1", source: "http", name: "Hub Help", state: "down", severity: "critical",
        openedAt: new Date(now - 60_000) }, // still open
      { target: "ep-2", source: "http", name: "Other", state: "down", severity: "critical",
        openedAt: new Date(now - 3600_000), resolvedAt: new Date(now - 60_000), resolvedReason: "recovered" },
    ]);
    const facts = await readBoardFacts(db, now, config);
    expect(facts.ledger.map((l) => l.target)).toEqual(["ep-1"]);
  });
});

describe("per-signal monitoring switches", () => {
  it("monitorHttp=false drops only the HTTP problem", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(healthChecks).values({
      serviceSlug: "ep-1", status: "down", statusCode: 503, dnsOk: true, checkedAt: new Date(2000),
    });
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(2000),
    });
    expect(deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems).toHaveLength(2);

    await db.update(monitoredEndpoints).set({ monitorHttp: false });
    const p = deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems;
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("failed");
  });

  it("monitorDeploys=false drops only the deploy problem", async () => {
    const db = await freshDb();
    await seedSite(db);
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(2000),
    });
    await db.update(monitoredEndpoints).set({ monitorDeploys: false });
    expect(deriveBoard(await readBoardFacts(db, 3000, config), 3000).problems).toEqual([]);
  });

  it("both switches default to ON so existing rows keep monitoring", async () => {
    const db = await freshDb();
    await seedSite(db);
    const [ep] = await db.select().from(monitoredEndpoints);
    expect(ep.monitorHttp).toBe(true);
    expect(ep.monitorDeploys).toBe(true);
  });
});
