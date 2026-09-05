import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { freshDb } from "./helpers/db";
import { activityRoutes } from "../src/routes/activity";
import { boardRoutes } from "../src/routes/board";
import type { ActivityPage, Board } from "../src/board";
import { deployments, monitoredEndpoints, monitoredSites, siteGroups } from "../src/libsql/schema";
import { testConfig } from "./helpers/config";

/**
 * `activityRoutes` and `boardRoutes` on one bare Hono, no auth seam — same shape as
 * `test/board-route.test.ts`'s `appWithSeed`, since `GET /board` and `GET /activity` are
 * both view-tier and neither route in this file needs a tier on the context.
 *
 * The roster is the same single Vercel endpoint `board-route.test.ts` seeds, so a
 * deployment against `hub-help-testing` is OWNED and turns into two activity rows (a
 * build row and a deploy row — `derive-activity.ts:164-186`). Two deployments, a minute
 * apart, gives the feed four rows and two DEPLOYMENTS to page across — enough for
 * `limit=2` to split the feed at a deployment boundary rather than merely truncate one.
 * Both timestamps are minutes apart so SQLite's whole-second storage
 * (`deployments.createdAt` is an integer-seconds column) can't collide them.
 */
async function seedApp() {
  const db = await freshDb();
  await db.insert(siteGroups).values({ id: "grp-1", name: "Hub", slug: "hub" });
  await db.insert(monitoredSites).values({ id: "site-1", siteGroupId: "grp-1", name: "Hub Help", slug: "hub-help" });
  await db.insert(monitoredEndpoints).values({
    id: "ep-1", siteId: "site-1", url: "https://testing.help.example.com",
    platform: "vercel", deployProject: "hub-help-testing", environment: "production", isActive: true,
  });
  const nowMs = Date.now();
  const base = { platform: "vercel", projectName: "hub-help-testing", environment: "production" };
  await db.insert(deployments).values([
    { ...base, id: "vc_d1", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(nowMs - 2 * 60_000) },
    { ...base, id: "vc_d2", buildPhase: "built", deployPhase: "deployed", createdAt: new Date(nowMs - 60_000) },
  ]);
  const app = new Hono();
  // Stands in for the seam these routes run behind in `createApp` (`src/app.ts`), the same
  // way `board-route.test.ts` shims the tier: the route reports bad input by THROWING an
  // HTTPException, and `onError` is what turns that into the `{ error: { message } }` body
  // every client in this service reads. Without it Hono's default handler answers in plain
  // text and the body assertion below would be measuring the default, not the contract.
  app.onError((err, c) => {
    const isHttp = err instanceof HTTPException;
    return c.json({ error: { message: isHttp ? err.message : "Internal Server Error" } }, isHttp ? err.status : 500);
  });
  app.route("/", activityRoutes(db, testConfig()));
  app.route("/", boardRoutes(db, testConfig()));
  return { app, db, nowMs };
}

describe("GET /activity", () => {
  it("with no cursor equals board.activity over the same DB", async () => {
    const { app, db, nowMs } = await seedApp();
    const board = (await (await app.request("/board")).json()) as Board;
    const page = (await (await app.request("/activity")).json()) as ActivityPage;
    expect(page.rows.map((r: { id: string }) => r.id)).toEqual(board.activity.map((r: { id: string }) => r.id));
    void db; void nowMs;
  });

  it("clamps limit into [1, MAX_ACTIVITY_ROWS] and truncates to it", async () => {
    const { app } = await seedApp();

    // The upper clamp cannot be observed with a small fixture — an over-large limit and an
    // uncapped one return the same rows — so what is pinned here is that an absurd limit is
    // served rather than rejected or NaN'd into an empty page.
    const huge = await app.request("/activity?limit=99999");
    expect(huge.status).toBe(200);
    const hugeBody = (await huge.json()) as ActivityPage;
    const all = (await (await app.request("/activity")).json()) as ActivityPage;
    expect(hugeBody.rows.map((r) => r.id)).toEqual(all.rows.map((r) => r.id));

    // The LOWER clamp is observable, and it is the half that can silently return nothing:
    // without `Math.max(..., 1)` these become limit 0 and limit -5, and `slice(-0)` returns
    // the WHOLE array while a negative limit returns garbage.
    for (const bad of ["0", "-5"]) {
      const res = await app.request(`/activity?limit=${bad}`);
      expect(res.status).toBe(200);
      expect(((await res.json()) as ActivityPage).rows).toHaveLength(1);
    }

    // A non-numeric limit falls back to the default rather than NaN-ing the page away.
    const junk = await app.request("/activity?limit=abc");
    expect(junk.status).toBe(200);
    expect(((await junk.json()) as ActivityPage).rows.length).toBe(all.rows.length);
  });

  it("rejects a malformed cursor rather than silently serving the newest page", async () => {
    const { app } = await seedApp();
    expect((await app.request("/activity?before=not-a-number&beforeId=x")).status).toBe(400);
    // A `before` with no `beforeId` is incomplete — the pair IS the cursor.
    expect((await app.request("/activity?before=123")).status).toBe(400);
    // `{atMs, id: ""}` is a cursor the SERVER mints (pageActivity's stall escape), so
    // rejecting it would 400 our own next page.
    expect((await app.request("/activity?before=123&beforeId=")).status).toBe(200);
  });

  it("rejects a cursor instant outside the range a Date can hold", async () => {
    const { app } = await seedApp();
    // `new Date(n)` for these is an Invalid Date, and every comparison against one is
    // false — the page would read as empty-and-exhausted rather than as the bad input it is.
    for (const bad of ["-1", "8640000000000001", "99999999999999999", "1e400"]) {
      expect((await app.request(`/activity?before=${bad}&beforeId=x`)).status).toBe(400);
    }
    // 8.64e15 itself is the LAST representable instant, not an error — the bound is
    // inclusive, so the check rejects nothing a `Date` can hold.
    expect((await app.request("/activity?before=8640000000000000&beforeId=x")).status).toBe(200);
    // A whitespace-only `before` is not the server's own empty-id cursor — `Number("")` is
    // 0, which would silently serve the oldest page.
    expect((await app.request("/activity?before=%20&beforeId=x")).status).toBe(400);
  });

  it("renders a rejected cursor through the app's own error shape", async () => {
    const { app } = await seedApp();
    const res = await app.request("/activity?before=not-a-number&beforeId=x");
    // Every other route reports failure as `{ error: { message } }` via `app.onError`. A
    // hand-rolled `c.json({ error: "..." }, 400)` here gave this one route a second shape
    // the client's error handling does not read.
    expect(await res.json()).toEqual({ error: { message: "malformed cursor" } });
  });

  it("serves an older page when given the first page's cursor", async () => {
    const { app } = await seedApp();
    const first = (await (await app.request("/activity?limit=2")).json()) as ActivityPage;
    expect(first.nextCursor).not.toBeNull();
    const q = `before=${first.nextCursor!.atMs}&beforeId=${encodeURIComponent(first.nextCursor!.id)}&limit=2`;
    const second = (await (await app.request(`/activity?${q}`)).json()) as ActivityPage;
    const firstIds = new Set(first.rows.map((r: { id: string }) => r.id));
    expect(second.rows.every((r: { id: string }) => !firstIds.has(r.id))).toBe(true);
  });
});
