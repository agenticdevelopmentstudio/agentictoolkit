import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { freshDb } from "./helpers/db";
import { boardRoutes } from "../src/routes/board";
import { readsRoutes, type CompactSnapshot } from "../src/routes/reads";
import { deriveBoard, readBoardFacts, type Board, type Problem } from "../src/board";
import type { Tier } from "../src/middleware/auth";
import type { LiveSnapshot } from "../src/monitor/live-types";
import { ALL_TOOLS } from "../src/mcp/tools";
import {
  deployProjectMeta, deployments, healthChecks, issues, monitoredEndpoints, monitoredSites,
  platformHealthState, siteGroups, vercelProdState,
} from "../src/libsql/schema";
import { testConfig } from "./helpers/config";

// The reconcile response shape (src/routes/board.ts) — not exported elsewhere, so the
// test types it locally to read the counts/`targets`/`checkedAt`/`skipped` off the parsed
// JSON body.
type ReconcileResult = {
  opened: number;
  updated: number;
  resolved: number;
  targets: string[];
  checkedAt: string | null;
  skipped: boolean;
};

// `requireAdmin` reads the tier that `requireAuth` puts on the context in `createApp`
// (`middleware/auth.ts:85`). These tests mount `boardRoutes` on a bare Hono, so nothing
// sets it — this shim stands in for the seam, and `tier` is a parameter so one test can
// prove a non-admin caller is refused.
async function appWithSeed(tier: Tier = "admin") {
  const db = await freshDb();
  // Every id here is a text uuid, `monitoredSites` keys on `siteGroupId`, and endpoints
  // have no `label` column — the display name comes from the site.
  await db.insert(siteGroups).values({ id: "grp-1", name: "Hub", slug: "hub" });
  await db.insert(monitoredSites).values({ id: "site-1", siteGroupId: "grp-1", name: "Hub Help", slug: "hub-help" });
  await db.insert(monitoredEndpoints).values({
    id: "ep-1", siteId: "site-1", url: "https://testing.help.example.com",
    platform: "vercel", deployProject: "hub-help-testing", environment: "production", isActive: true,
  });
  const app = new Hono<{ Variables: { tier: Tier } }>();
  app.use("*", async (c, next) => { c.set("tier", tier); return next(); });
  app.route("/", boardRoutes(db, testConfig()));
  app.route("/", readsRoutes(db, testConfig()));
  return { db, app };
}

// A roster-less DB: no group, no site, no endpoint. `appWithSeed`'s fleet is what makes
// the sweep safe, so its absence is what the fail-closed guard is about.
async function appWithoutRoster() {
  const db = await freshDb();
  const app = new Hono<{ Variables: { tier: Tier } }>();
  app.use("*", async (c, next) => { c.set("tier", "admin"); return next(); });
  app.route("/", boardRoutes(db, testConfig()));
  return { db, app };
}

describe("GET /board", () => {
  it("serves an empty board for a healthy fleet", async () => {
    const { app } = await appWithSeed();
    const res = await app.request("/board");
    expect(res.status).toBe(200);
    const body = (await res.json()) as Board;
    expect(body.problems).toEqual([]);
    expect(body.indicator).toBe("operational");
    expect(typeof body.generatedAt).toBe("string");
  });

  it("serves the failed deploy as a problem", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.problems).toHaveLength(1);
    expect(body.problems[0].target).toBe("vercel|hub-help-testing|");
  });

  // THE REPORTED BUG, end to end through the real route: `hub-help-testing` deployed green
  // and the board badged every row PROD. The seeded `environment` is Vercel's promotion
  // target and is "production" for EVERY Vercel project, testing ones included; the badge
  // has to read the tier off the project name instead. Asserted here and not only at
  // `deriveActivity`, because the whole defect was one layer handing another a field that
  // type-checks perfectly and means something else.
  it("badges a testing project's rows with its TIER, not Vercel's production target", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d2", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.activity).toHaveLength(2);
    expect(body.activity.map((a) => a.environment)).toEqual(["testing", "testing"]);
  });

  it("badges a FAILED testing deploy's problem with the tier too, so both panes agree", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d3", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.problems[0]?.environment).toBe("testing");
    expect(body.activity.every((a) => a.environment === "testing")).toBe(true);
  });

  // The two tests above only get the right answer because the fixture project is SPELLED
  // `hub-help-testing`. The name is a convention, and its default is "production" — so a
  // testing project named plainly still badges PROD, which is the same wrong badge one
  // rung further out. The BRANCH is the signal that cannot default: `prepared` is what
  // builds testing, whatever the project is called. Asserted end to end because the whole
  // defect class here is one layer handing another a field that type-checks perfectly and
  // means something else.
  it("badges rows from the BRANCH, for a testing project whose name says nothing", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(monitoredEndpoints).values({
      id: "ep-hub", siteId: "site-1", url: "https://hub.example.com",
      platform: "vercel", deployProject: "hub", environment: "production", isActive: true,
    });
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub", environment: "production",
      id: "vc_d4", branch: "prepared", buildPhase: "built", deployPhase: "deployed",
      createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.activity).toHaveLength(2);
    expect(body.activity.map((a) => a.environment)).toEqual(["testing", "testing"]);
  });

  it("and a genuine production deploy off the production branch still reads PROD", async () => {
    // The other side of the same rule — a branch-derived env must not label everything
    // testing. Without this the test above passes for a fold that ignores its input.
    const { db, app } = await appWithSeed();
    await db.insert(monitoredEndpoints).values({
      id: "ep-hub", siteId: "site-1", url: "https://hub.example.com",
      platform: "vercel", deployProject: "hub", environment: "production", isActive: true,
    });
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub", environment: "production",
      id: "vc_d5", branch: "production", buildPhase: "built", deployPhase: "deployed",
      createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.activity.map((a) => a.environment)).toEqual(["production", "production"]);
  });

  // The details pane's Git tab and its provider-error block read `branch` and `errorText`
  // off the row and render nothing without them. Both live in the deployments table and
  // both used to stop at the server boundary, so the panes were unreachable for every row
  // on the board. Asserted through the real route because the gap was the WIRE.
  it("puts the deploy's branch and provider errorText on the wire, for problems and activity alike", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d6", branch: "prepared", buildPhase: "failed", deployPhase: "none",
      errorText: '[buildStep] Command "next build" exited with 1', createdAt: new Date(),
    });
    const body = (await (await app.request("/board")).json()) as Board;
    expect(body.problems[0]).toMatchObject({
      branch: "prepared", errorText: '[buildStep] Command "next build" exited with 1',
    });
    expect(body.activity).not.toHaveLength(0);
    for (const row of body.activity) {
      expect(row).toMatchObject({
        branch: "prepared", errorText: '[buildStep] Command "next build" exited with 1',
      });
    }
  });

  // The one WIRING test. Everything else in this suite tests the fold through the
  // route; this pins that the route is a pass-through — no reshaping, no filtering,
  // no second derivation. A route that quietly narrowed the board would recreate the
  // exact defect this design removes, one layer up.
  it("serves EXACTLY deriveBoard of the same facts", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const nowMs = Date.now();
    const expected = deriveBoard(await readBoardFacts(db, nowMs, testConfig()), nowMs);
    const body = (await (await app.request("/board")).json()) as Board;
    // The two CLOCK-DERIVED fields are the only ones that legitimately differ — two clock
    // reads, ms apart. `activityFromMs` is `nowMs` minus a constant, so it carries the same
    // skew as `generatedAt` and is blanked alongside it rather than compared.
    const atNow = (b: Board): Board => ({ ...b, generatedAt: "", activityFromMs: 0 });
    expect(atNow(body)).toEqual(atNow(expected));
  });
});

describe("POST /board/reconcile — REQUIREMENT B", () => {
  it("resolves a ledger row whose target no site monitors any more", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|deleted-site|", source: "vercel", name: "deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const res = await app.request("/board/reconcile", { method: "POST" });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ resolved: 1 });
    const open = await db.select().from(issues);
    expect(open[0].resolvedAt).not.toBeNull();
    // SILENT: no site watches this target, so we never observed a recovery. Half of the
    // pair the "closes a still-monitored healthy target" case below completes.
    expect(open[0].resolvedReason).toBe("unmonitored");
  });

  it("resolves a ledger row whose site had its monitoring switched off", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|hub-help-testing|", source: "vercel", name: "hub-help-testing",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    await db.update(monitoredEndpoints).set({ isActive: false });
    expect(await (await app.request("/board/reconcile", { method: "POST" })).json()).toMatchObject({ resolved: 1 });
  });

  it("leaves a ledger row alone when the problem is still real", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    await db.insert(issues).values({
      target: "vercel|hub-help-testing|", source: "vercel", name: "hub-help-testing",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    // "Left alone" is `updated`, not untouched: a live row's links and commit are refreshed
    // every run. Nothing opens (the row exists) and nothing resolves (the problem is real).
    expect(await (await app.request("/board/reconcile", { method: "POST" })).json())
      .toMatchObject({ opened: 0, updated: 1, resolved: 0 });
  });

  // This route runs the cycle's FULL ledger write, not an orphan sweep — so the response
  // has to say what it wrote. Reporting only `resolved` hid the half that pages on-call:
  // opening a row alerts, and this endpoint flushes on the API thread.
  it("reports what it OPENED, not just what it resolved — the opening half is the half that alerts", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    // No ledger row for the failing deploy yet — the fold derives the Problem, so this
    // call is what creates it.
    const body = (await (await app.request("/board/reconcile", { method: "POST" })).json()) as ReconcileResult;
    expect(body).toMatchObject({ opened: 1, updated: 0, resolved: 0 });
    const [row] = await db.select().from(issues);
    expect(row.target).toBe("vercel|hub-help-testing|");
    expect(row.resolvedAt).toBeNull();
  });

  it("closes a still-monitored healthy target as a RECOVERY, never as an orphan", async () => {
    const { db, app } = await appWithSeed();
    // The seeded site is monitored and has no failing deployment — so it is MONITORED but
    // not a PROBLEM. That gap is the whole test.
    //
    // Under Task 9 this route ran a NARROW orphan-only sweep alongside the per-source
    // recorders, and closing here would have stolen the recovery from the monitor cycle:
    // silently, with no alert and no "[down] resolved" Activity line. Task 12 deleted
    // those recorders, so the route now runs the cycle's OWN verb (reconcileBoardLedger)
    // and there is no longer a second path to steal from. What the old `resolved: 0`
    // protected is still pinned, but by the REASON rather than the count: a watched target
    // closes `recovered` — which alerts, and may become an Activity "[state] resolved" row
    // — while an unwatched one closes `unmonitored` and stays silent (first case above).
    await db.insert(issues).values({
      target: "vercel|hub-help-testing|", source: "vercel", name: "hub-help-testing",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    expect(await (await app.request("/board/reconcile", { method: "POST" })).json()).toMatchObject({ resolved: 1 });
    const [row] = await db.select().from(issues);
    expect(row.resolvedAt).not.toBeNull();
    expect(row.resolvedReason).toBe("recovered");
  });

  it("is idempotent — a second run resolves nothing", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|deleted-site|", source: "vercel", name: "deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    await app.request("/board/reconcile", { method: "POST" });
    expect(await (await app.request("/board/reconcile", { method: "POST" })).json()).toMatchObject({ resolved: 0 });
  });

  it("names the targets it retired and stamps the board's clock", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|deleted-site|", source: "vercel", name: "deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const body = (await (await app.request("/board/reconcile", { method: "POST" })).json()) as ReconcileResult;
    // `resolved: 1` alone would pass with an empty `targets` and a null `checkedAt`; an
    // operator reading the response needs to know WHICH rows went.
    expect(body.targets).toEqual(["vercel|deleted-site|"]);
    expect(typeof body.checkedAt).toBe("string");
    expect(body.skipped).toBe(false);
  });

  it("FAILS CLOSED on an empty roster — a blipped read must not retire the whole ledger", async () => {
    const { db, app } = await appWithoutRoster();
    // Three unrelated open rows, spanning all three target spellings. With no guard, one
    // POST closes every one of them, because an empty roster derives no monitored target.
    await db.insert(issues).values([
      { target: "vercel|a|", source: "vercel", name: "a", severity: "major", state: "failed", openedAt: new Date() },
      { target: "ep-9", source: "http", name: "ep-9", severity: "critical", state: "down", openedAt: new Date() },
      { target: "platform-health|vercel", source: "vercel", name: "Vercel", severity: "minor", state: "unreachable", openedAt: new Date() },
    ]);
    const body = await (await app.request("/board/reconcile", { method: "POST" })).json();
    // Every count zero, not just `resolved` — the skip path returns BEFORE the ledger
    // write, so it must not claim to have opened or refreshed anything either.
    expect(body).toMatchObject({ opened: 0, updated: 0, resolved: 0, targets: [], skipped: true });
    expect((await db.select().from(issues)).every((r) => r.resolvedAt === null)).toBe(true);
  });

  it("refuses a non-admin caller — it mutates the ledger", async () => {
    const { db, app } = await appWithSeed("view");
    await db.insert(issues).values({
      target: "vercel|deleted-site|", source: "vercel", name: "deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    expect((await app.request("/board/reconcile", { method: "POST" })).status).toBe(403);
    // And the row it would have swept is untouched.
    const [row] = await db.select().from(issues);
    expect(row.resolvedAt).toBeNull();
  });

  it("leaves GET /board reachable to a non-admin — it is the client's only read", async () => {
    const { app } = await appWithSeed("view");
    expect((await app.request("/board")).status).toBe(200);
  });
});

describe("/snapshot.openIssues agrees with /board.problems", () => {
  it("serves the same targets from both surfaces", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const board = (await (await app.request("/board")).json()) as Board;
    const snap = (await (await app.request("/snapshot")).json()) as CompactSnapshot;
    expect(snap.openIssues.map((i) => i.target).sort())
      .toEqual(board.problems.map((p) => p.target).sort());
  });

  it("a stale LEDGER row never reaches /snapshot when the board does not derive it", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|long-deleted-site|", source: "vercel", name: "long-deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const snap = (await (await app.request("/snapshot")).json()) as CompactSnapshot;
    expect(snap.openIssues).toEqual([]);
  });
});

// The other two issues-table readers in reads.ts. Both used to match on a target string
// that Task 12 stops writing, so both would go quietly wrong — an empty pane and a green
// pill — with the whole suite still passing. These are the tests that catch that.
describe("/live derives staleProd and provider health from the board", () => {
  // The seeded detail and the asserted detail DIFFER, and that is the point. `hub-help-testing`
  // ends in `-testing`, so `envFromProject` (vendor/@agentic-toolkit/deploy-platform/src/canon,
  // via `deployEnv`) calls its logical environment "testing" even though Vercel's own target for
  // it is "production" — the promotion-vs-tier distinction this whole branch exists to get right.
  // `staleProdProblems` (derive-problems.ts:347-349) therefore rewrites the word `production` out
  // of the detail. Assert the DERIVED values; asserting the seeded ones fails at Step 4 and sends
  // the implementer hunting a bug that is not there.
  it("serves a stale deploy on /live.staleProd, in the project's LOGICAL environment", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployProjectMeta).values({ platform: "vercel", projectName: "hub-help-testing" });
    await db.insert(vercelProdState).values({
      projectName: "hub-help-testing", stale: true,
      detail: "production is 3 builds behind", sourceUrl: "https://vercel.com/x", liveUrl: "https://help.example.com",
    });
    const live = (await (await app.request("/live")).json()) as LiveSnapshot;
    expect(live.staleProd).toEqual([{
      projectName: "hub-help-testing", environment: "testing",
      detail: "testing is 3 builds behind", sourceUrl: "https://vercel.com/x", liveUrl: "https://help.example.com",
    }]);
  });

  // The same fold against a project whose name carries no tier suffix — proving the rewrite
  // above is the canon rule firing, not staleProdFromBoard mangling every detail it touches.
  it("leaves a true production project's environment and detail alone", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(monitoredEndpoints).values({
      id: "ep-adh", siteId: "site-1", url: "https://adh.example.com",
      platform: "vercel", deployProject: "adh", isActive: true,
    });
    await db.insert(deployProjectMeta).values({ platform: "vercel", projectName: "adh" });
    await db.insert(vercelProdState).values({
      projectName: "adh", stale: true,
      detail: "production is 3 builds behind", sourceUrl: null, liveUrl: null,
    });
    const live = (await (await app.request("/live")).json()) as LiveSnapshot;
    expect(live.staleProd).toContainEqual(expect.objectContaining({
      projectName: "adh", environment: "production", detail: "production is 3 builds behind",
    }));
  });

  it("reports a provider as NOT ok once the board derives its platform-health problem", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(platformHealthState).values({
      source: "vercel", configured: true, reachable: false, consecutiveFailures: 2,
    });
    const live = (await (await app.request("/live")).json()) as LiveSnapshot;
    expect(live.providers.vercel.ok).toBe(false);
  });

  it("keeps the debounce — ONE failed poll is not an unreachable provider", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(platformHealthState).values({
      source: "vercel", configured: true, reachable: false, consecutiveFailures: 1,
    });
    const live = (await (await app.request("/live")).json()) as LiveSnapshot;
    expect(live.providers.vercel.ok).toBe(true);
  });

  // Fix Round 1, item 4: monitorHttp:false takes the endpoint out of endpointProblems
  // entirely (Requirement A — an unmonitored endpoint has no opinion to contribute), so
  // `problems` never carries a `dns` row for it. Before the fallback, /live's dnsOk for
  // such an endpoint was hardcoded true regardless of what the last real probe saw — a
  // health claim from an absence of data. `healthChecks.dnsOk` IS still written every
  // cycle for this endpoint (the probe itself isn't gated on monitorHttp, only the fold
  // is), so /live has a real, honest answer available and should serve it.
  it("still reports dnsOk:false for a monitorHttp:false endpoint whose latest probe failed DNS", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(monitoredEndpoints).values({
      id: "ep-2", siteId: "site-1", url: "https://ghost.help.example.com",
      isActive: true, monitorHttp: false,
    });
    await db.insert(healthChecks).values({ serviceSlug: "ep-2", status: "down", statusCode: null, dnsOk: false });

    const board = (await (await app.request("/board")).json()) as Board;
    // The fold genuinely has no opinion — confirms the gap this test is about is real,
    // not a fixture mistake.
    expect(board.problems.find((p) => p.target === "ep-2")).toBeUndefined();

    const live = (await (await app.request("/live")).json()) as LiveSnapshot;
    expect(live.services.find((s) => s.slug === "ep-2")?.dnsOk).toBe(false);
  });
});

// The MCP surface's own tests, ADDED here per Fix Round 1 item 1: `get_problems`/
// `get_issue` are asserted only on SHAPE elsewhere (test/mcp.int.test.ts:102, and
// get_issue isn't touched there at all) — an *.int.test.ts file that never runs this
// session. Written here, in the unit suite `pnpm test` actually executes, so the drift
// this pair suffered before Task 14 (silently serving the ledger table) can't recur
// unnoticed again.
describe("MCP get_problems/get_issue read the SAME board GET /board does", () => {
  const tool = (name: string) => {
    const t = ALL_TOOLS.find((x) => x.name === name);
    if (!t) throw new Error(`no such tool: ${name}`);
    return t;
  };

  it("get_problems returns exactly GET /board's problem targets, for the same seeded db", async () => {
    const { db, app } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const board = (await (await app.request("/board")).json()) as Board;
    const out = (await tool("get_problems").execute(db, {}, testConfig())) as Problem[];
    expect(out.map((p) => p.target).sort()).toEqual(board.problems.map((p) => p.target).sort());
  });

  it("get_issue returns the Problem the board derives for a target it recognizes", async () => {
    const { db } = await appWithSeed();
    await db.insert(deployments).values({
      platform: "vercel", projectName: "hub-help-testing", environment: "production",
      id: "vc_d1", buildPhase: "failed", deployPhase: "none", createdAt: new Date(),
    });
    const out = (await tool("get_issue").execute(db, { target: "vercel|hub-help-testing|" }, testConfig())) as Problem | null;
    expect(out?.target).toBe("vercel|hub-help-testing|");
  });

  // THE regression test — the exact case that was broken before Task 14. get_issue used
  // to read the ledger table directly (openByTarget), so a stale row the board no longer
  // derives still answered non-null, forever, for a target nothing monitors any more.
  it("get_issue returns null for a target only a stale LEDGER row carries", async () => {
    const { db } = await appWithSeed();
    await db.insert(issues).values({
      target: "vercel|long-deleted-site|", source: "vercel", name: "long-deleted-site",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const out = await tool("get_issue").execute(db, { target: "vercel|long-deleted-site|" }, testConfig());
    expect(out).toBeNull();
  });
});
