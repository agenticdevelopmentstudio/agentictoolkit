import { describe, it, expect } from "vitest";
import { freshDb } from "./helpers/db";
import { recordPlatformObservations } from "../src/monitor/observations";
import type { PlatformObservation } from "../src/monitor/observations";
import { recordVercelProdStates } from "../src/monitor/observations";
import { deriveBoard, readBoardFacts } from "../src/board";
import { platformHealthState, vercelProdState } from "../src/libsql/schema";
import { testConfig } from "./helpers/config";

// `recordPlatformObservations` is now the SINGLE writer of `consecutive_failures`: the
// second writer (`applyPlatformIssues`) is gone, and with it the double-advance this file
// exists to prevent. Every test below therefore drives the recorder ALONE — a second call
// per poll is exactly the shape of regressions f21284e26 / 9fe25b304, so the helper that
// used to pair them has been removed rather than repointed.
//
// The other half — whether a streak becomes a Problem — is `deriveBoard`'s, and is
// asserted through the fold, which reads `platform_health_state` as a fact.
async function problemsFrom(db: Awaited<ReturnType<typeof freshDb>>) {
  const nowMs = Date.now();
  return deriveBoard(await readBoardFacts(db, nowMs, testConfig()), nowMs).problems;
}

describe("recordPlatformObservations", () => {
  it("records what the poll saw AND advances the streak — one call, one writer", async () => {
    const db = await freshDb();
    // Annotated because a bare `const` loses the contextual typing that narrows "vercel"
    // to IssueSource; the inline literals below need no annotation.
    const obs: PlatformObservation[] = [{ source: "vercel", configured: true, reachable: false }];
    await recordPlatformObservations(db, obs);
    const [row] = await db.select().from(platformHealthState);
    expect(row).toMatchObject({ consecutiveFailures: 1, configured: true, reachable: false });
  });

  it("REGRESSION f21284e26/9fe25b304: one failed poll advances the streak by ONE, not two", async () => {
    const db = await freshDb();
    await recordPlatformObservations(db, [{ source: "vercel", configured: true, reachable: false }]);
    const [row] = await db.select().from(platformHealthState);
    expect(row.consecutiveFailures).toBe(1);
    // PLATFORM_UNREACHABLE_POLLS is 2, so ONE failure must not be enough to derive a
    // Problem. A second writer would land here at 2 and surface on the spot — a transient
    // 429 becomes a page, then vanishes on the next good poll.
    expect(await problemsFrom(db)).toHaveLength(0);
  });

  it("surfaces only on the SECOND consecutive failure, and the streak still reads 2", async () => {
    const db = await freshDb();
    const obs: PlatformObservation[] = [{ source: "vercel", configured: true, reachable: false }];
    await recordPlatformObservations(db, obs);
    await recordPlatformObservations(db, obs);
    const [row] = await db.select().from(platformHealthState);
    expect(row.consecutiveFailures).toBe(2);
    const problems = await problemsFrom(db);
    expect(problems).toHaveLength(1);
    expect(problems[0]).toMatchObject({ target: "platform-health|vercel", state: "unreachable" });
  });

  it("resets the streak and flips `reachable` the moment a poll succeeds", async () => {
    const db = await freshDb();
    await recordPlatformObservations(db, [{ source: "vercel", configured: true, reachable: false }]);
    await recordPlatformObservations(db, [{ source: "vercel", configured: true, reachable: true }]);
    const [row] = await db.select().from(platformHealthState);
    expect(row).toMatchObject({ consecutiveFailures: 0, reachable: true });
  });

  it("records an UNCONFIGURED platform without ever accruing a streak", async () => {
    const db = await freshDb();
    await recordPlatformObservations(db, [{ source: "crunchy", configured: false, reachable: false }]);
    const [row] = await db.select().from(platformHealthState);
    expect(row).toMatchObject({ consecutiveFailures: 0, configured: false });
    expect(await problemsFrom(db)).toHaveLength(0);
  });
});

describe("recordVercelProdStates", () => {
  it("upserts one row per project", async () => {
    const db = await freshDb();
    await recordVercelProdStates(db, [
      { projectName: "a", stale: true, detail: "live deploy errored", sourceUrl: "s", liveUrl: "l" },
    ]);
    await recordVercelProdStates(db, [
      { projectName: "a", stale: false, detail: null, sourceUrl: "s", liveUrl: "l" },
    ]);
    const rows = await db.select().from(vercelProdState);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ stale: false, detail: null });
  });

  it("drops a project the read no longer mentions — a deleted project cannot stay stale", async () => {
    const db = await freshDb();
    await recordVercelProdStates(db, [
      { projectName: "a", stale: true, detail: "x", sourceUrl: null, liveUrl: null },
      { projectName: "b", stale: true, detail: "x", sourceUrl: null, liveUrl: null },
    ]);
    await recordVercelProdStates(db, [
      { projectName: "a", stale: true, detail: "x", sourceUrl: null, liveUrl: null },
    ]);
    expect((await db.select().from(vercelProdState)).map((r) => r.projectName)).toEqual(["a"]);
  });

  it("an EMPTY read deletes nothing — a failed fetch is not mass recovery", async () => {
    const db = await freshDb();
    await recordVercelProdStates(db, [
      { projectName: "a", stale: true, detail: "x", sourceUrl: null, liveUrl: null },
    ]);
    await recordVercelProdStates(db, []);
    expect(await db.select().from(vercelProdState)).toHaveLength(1);
  });
});
