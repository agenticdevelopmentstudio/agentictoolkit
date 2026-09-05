import { describe, it, expect } from "vitest";
import { sql } from "drizzle-orm";
import { freshDb } from "./helpers/db";
import { readActivityPage } from "../src/board/facts";
import { deriveBoard, readBoardFacts } from "../src/board";
import { deployments, issues, monitoredEndpoints, monitoredSites, siteGroups } from "../src/libsql/schema";
import { testConfig } from "./helpers/config";

/**
 * One active roster entry, wired to deploy project "hub-help-testing" so the deployment
 * rows below are all OWNED (see `ownedDeploysWhere`/`rosterDeployProjects`) and none of
 * them is a Vercel preview (all carry a real `environment`). Deployment rows land at
 * ~10 minutes, ~2 hours, ~30 hours and ~40 days old — the last one's primary key is
 * `vc_ancient`, which the derived row id carries as its middle segment, and
 * `ancientAtMs` is returned so the walk-back test can assert the instant too. One issue opened ~41
 * days ago and resolved ~39 days ago with `resolved_reason = 'recovered'`, so the feed has
 * an event whose OPEN half is outside any reasonable page but whose CLOSE half survives.
 */
async function seedActivityFixture() {
  const db = await freshDb();
  await db.insert(siteGroups).values({ id: "grp-1", name: "Hub", slug: "hub" });
  await db.insert(monitoredSites).values({ id: "site-1", siteGroupId: "grp-1", name: "Hub Help", slug: "hub-help" });
  await db.insert(monitoredEndpoints).values({
    id: "ep-1", siteId: "site-1", url: "https://testing.help.example.com",
    platform: "vercel", deployProject: "hub-help-testing", environment: "production",
    isActive: true, monitorHttp: true, monitorDeploys: true,
  });

  // Floored to whole seconds: `deployments.createdAt`/`issues.openedAt`/`resolvedAt` are
  // stored as integer unix-seconds (`schema.ts:6-9`), so a sub-second `Date.now()` would
  // round-trip through SQLite to a DIFFERENT ms than what's asserted against below.
  const now = Math.floor(Date.now() / 1000) * 1000;
  const day = 24 * 3600_000;
  const ancientAtMs = now - 40 * day;
  const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
  await db.insert(deployments).values([
    { ...base, id: "vc_10m", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(now - 10 * 60_000) },
    { ...base, id: "vc_2h", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(now - 2 * 3600_000) },
    { ...base, id: "vc_30h", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(now - 30 * 3600_000) },
    { ...base, id: "vc_ancient", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(ancientAtMs) },
  ]);

  await db.insert(issues).values({
    target: "ep-1", source: "http", name: "Hub Help", state: "down", severity: "critical",
    openedAt: new Date(now - 41 * day), resolvedAt: new Date(now - 39 * day), resolvedReason: "recovered",
  });

  return { db, ancientAtMs };
}

describe("issues indexes", () => {
  it("seeks an index for an opened_at-ordered read instead of scanning", async () => {
    const db = await freshDb();
    const plan = await db.all<{ detail: unknown }>(
      sql`explain query plan select * from issues where opened_at <= 1 order by opened_at desc limit 10`,
    );
    const detail = plan.map((r) => String(r.detail)).join(" ");
    expect(detail).toContain("idx_issue_opened");
    expect(detail).not.toContain("SCAN issues");
  });

  it("seeks an index for a resolved_at-ordered read", async () => {
    const db = await freshDb();
    const plan = await db.all<{ detail: unknown }>(
      sql`explain query plan select * from issues where resolved_at <= 1 order by resolved_at desc limit 10`,
    );
    expect(plan.map((r) => String(r.detail)).join(" ")).toContain("idx_issue_resolved");
  });
});

describe("readActivityPage", () => {
  it("with no cursor serves the newest page, whose tail is exactly board.activity", async () => {
    const { db } = await seedActivityFixture();
    const nowMs = Date.now();
    const board = deriveBoard(await readBoardFacts(db, nowMs, testConfig()), nowMs);
    const page = await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 300 });

    // Both lists read oldest-first, so the live board is the page's newest TAIL. They are
    // deliberately not equal: the page has no 24h floor, which is the feature — it also
    // carries the older rows the board's window drops. Asserting equality here would
    // demand the 19-hour bug back.
    expect(page.rows.slice(-board.activity.length).map((r) => r.id)).toEqual(
      board.activity.map((r) => r.id),
    );
    expect(page.rows.length).toBeGreaterThan(board.activity.length);
  });

  it("returns rows from 40 days ago — the reported bug", async () => {
    const { db, ancientAtMs } = await seedActivityFixture();
    const nowMs = Date.now();
    const first = await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 5 });
    expect(first.nextCursor).not.toBeNull();

    // Walk back until the 40-day-old row appears, or the facts run out. Both halves are
    // asserted: the row's `at` (the reported bug is about REACH) and its id's
    // `deployments.id` segment (the fixture's `vc_ancient`), which is what makes the id a
    // total order with the timestamp — see `derive-activity.ts`'s `deployRowId`.
    let cursor = first.nextCursor;
    const seen: string[] = [];
    const seenIds: string[] = [];
    for (let i = 0; i < 50 && cursor != null; i++) {
      const page = await readActivityPage(db, nowMs, testConfig(), { cursor, limit: 5 });
      seen.push(...page.rows.map((r) => r.at));
      seenIds.push(...page.rows.map((r) => r.id));
      cursor = page.nextCursor;
    }
    expect(seen).toContain(new Date(ancientAtMs).toISOString());
    expect(seenIds.some((id) => id.startsWith("deploy:vc_ancient:"))).toBe(true);
  });

  it("reports exhaustion when the facts run out", async () => {
    const { db } = await seedActivityFixture();
    const nowMs = Date.now();
    let cursor = (await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 5 })).nextCursor;
    let last: Awaited<ReturnType<typeof readActivityPage>> | null = null;
    for (let i = 0; i < 100 && cursor != null; i++) {
      last = await readActivityPage(db, nowMs, testConfig(), { cursor, limit: 5 });
      cursor = last.nextCursor;
    }
    expect(last?.nextCursor).toBeNull();
  });

  it("does not shed the oldest candidates to the LIVE feed's cap", async () => {
    // One deployment folds into TWO rows, so 200 owned deployments derive 400 — past
    // MAX_ACTIVITY_ROWS (300) — while each SQL source returns 200 and is therefore
    // EXHAUSTED. With the live feed's cap applied to a history page, the fold's
    // `slice(-300)` throws away the oldest 100 before the pager ever sees them: the pager
    // then keeps all 300 it was handed, reads `trimmed` as false, and reports the end of
    // history with no cursor left to reach the rows it dropped. This is the shape of the
    // reported bug, one cap down.
    const { db } = await seedActivityFixture();
    const now = Math.floor(Date.now() / 1000) * 1000;
    const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
    await db.insert(deployments).values(
      // Minutes apart so SQLite's whole-second columns can't collide these rows with each
      // other, and offset half a minute so none of them can land on the same second as a
      // fixture row (`vc_10m` sits at exactly now-10min, which the i=9 row would otherwise
      // share). Rows sharing an instant are legal — the id half of the cursor exists for
      // exactly that — but a fixture that creates one silently weakens the disjointness
      // assertion below into a test of the collision instead of the pager.
      Array.from({ length: 200 }, (_, i) => ({
        ...base, id: `vc_bulk_${i}`, buildPhase: "built", deployPhase: "deployed",
        createdAt: new Date(now - (i + 1) * 60_000 - 30_000),
      })),
    );

    const nowMs = Date.now();
    const first = await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 300 });
    expect(first.rows).toHaveLength(300);
    // The page filled, so there is provably more behind it whatever the sources said.
    expect(first.nextCursor).not.toBeNull();

    const second = await readActivityPage(db, nowMs, testConfig(), { cursor: first.nextCursor, limit: 300 });
    expect(second.rows.length).toBeGreaterThan(0);
    const firstIds = new Set(first.rows.map((r) => r.id));
    expect(second.rows.every((r) => !firstIds.has(r.id))).toBe(true);
  });

  // `ORDER BY ts DESC LIMIT n` over a whole-SECOND column routinely stops in the middle of
  // a tie group, in whatever order the planner emits. Reporting that second as the page's
  // floor would strand its unread remainder: older than this page's own next cursor and
  // newer than every cursor after it, so nothing would ever ask for it again.
  // `readSourcePage` re-reads the boundary instant in full, which is what makes the floor
  // mean "read COMPLETELY".
  it("never cuts through a tie group — 8 rows in one second, read 3 at a time", async () => {
    const { db } = await seedActivityFixture();
    const now = Math.floor(Date.now() / 1000) * 1000;
    const tieAtMs = now - 5 * 60_000;
    const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
    await db.insert(deployments).values(
      Array.from({ length: 8 }, (_, i) => ({
        ...base, id: `vc_tie_${i}`, buildPhase: "built", deployPhase: "deployed",
        createdAt: new Date(tieAtMs),
      })),
    );

    const nowMs = Date.now();
    const seen = new Map<string, string>();
    const readIds: string[] = [];
    let page = await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 3 });
    const absorb = (rows: { id: string; at: string }[]) => {
      for (const r of rows) {
        readIds.push(r.id);
        seen.set(r.id, r.at);
      }
    };
    absorb(page.rows);
    let cursor = page.nextCursor;
    for (let i = 0; i < 60 && cursor != null; i++) {
      page = await readActivityPage(db, nowMs, testConfig(), { cursor, limit: 3 });
      absorb(page.rows);
      cursor = page.nextCursor;
    }

    expect(cursor).toBeNull();
    // No row read twice, and every member of the tie group reached — the two ways a
    // half-read instant fails. Each tie row's `at` is asserted too: with the deployment id
    // no longer carrying its timestamp, an id alone can no longer vouch for WHICH instant
    // the row was read at, and a walk that quietly served the tie group from some other
    // second would satisfy the id checks unnoticed.
    expect(new Set(readIds).size).toBe(readIds.length);
    const tieIso = new Date(tieAtMs).toISOString();
    for (let i = 0; i < 8; i++) {
      expect(seen.get(`deploy:vc_tie_${i}:build`)).toBe(tieIso);
    }
  });

  // `issues` is a LEDGER: it keeps rows for targets the roster no longer watches, and
  // `deriveActivity` drops every one of them. Without the same ownership narrowing the
  // deploy read carries, a stretch of history dominated by them fills the limit, derives
  // nothing, and costs the reader a round trip per page-floor of crawling.
  it("does not let ledger rows for unwatched targets starve a page", async () => {
    const { db } = await seedActivityFixture();
    const now = Math.floor(Date.now() / 1000) * 1000;
    await db.insert(issues).values(
      // Newer than every deploy row, so an unnarrowed read fills its whole limit with them.
      // One target EACH: `uniq_open_issue_per_target` is a partial unique index over
      // `resolved_at is null`, so a ledger physically cannot hold forty OPEN rows for one
      // target — forty unwatched targets is both the only legal shape and the one the
      // starvation case actually describes.
      Array.from({ length: 40 }, (_, i) => ({
        target: `ep-gone-${i}`, source: "http", name: "Removed site", state: "down",
        severity: "critical", openedAt: new Date(now - (i + 1) * 1000),
      })),
    );

    const page = await readActivityPage(db, Date.now(), testConfig(), { cursor: null, limit: 5 });
    expect(page.rows.length).toBeGreaterThan(0);
    expect(page.rows.every((r) => !r.target.startsWith("ep-gone"))).toBe(true);
  });

  it("finds an issue that opened before the window and resolved inside it", async () => {
    const { db } = await seedActivityFixture();
    const nowMs = Date.now();
    const page = await readActivityPage(db, nowMs, testConfig(), { cursor: null, limit: 300 });
    expect(page.rows.some((r) => r.id.startsWith("issue:") && r.verb.endsWith("resolved"))).toBe(true);
  });
});
