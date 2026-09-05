import { describe, it, expect } from "vitest";
import { pageActivity } from "../src/board/derive-activity";
import type { ActivityCursor, ActivityRow } from "../src/board/types";

const T = Date.UTC(2026, 7, 17, 12, 0, 0);

function row(atMs: number, id: string): ActivityRow {
  return {
    id, kind: "deploy", step: "build", source: "vercel", tone: "good", verb: "built",
    target: "vercel|p|", name: "p", environment: "testing", detail: null, sourceUrl: null,
    liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null, branch: null,
    errorText: null, at: new Date(atMs).toISOString(),
  };
}

describe("pageActivity", () => {
  it("returns the newest `limit` rows, oldest-first, when there is no cursor", () => {
    const rows = [row(T - 3000, "c"), row(T - 2000, "b"), row(T - 1000, "a")];
    const page = pageActivity(rows, null, 2, true);
    expect(page.rows.map((r) => r.id)).toEqual(["b", "a"]);
  });

  it("sets nextCursor to the OLDEST row KEPT, not the oldest fetched", () => {
    const rows = [row(T - 3000, "c"), row(T - 2000, "b"), row(T - 1000, "a")];
    const page = pageActivity(rows, null, 2, false);
    expect(page.nextCursor).toEqual({ atMs: T - 2000, id: "b" });
  });

  it("excludes rows at or after the cursor, comparing (atMs, id) as a pair", () => {
    const rows = [row(T, "deploy:vc_x:build"), row(T, "deploy:vc_x:deploy"), row(T - 1, "older")];
    const cursor: ActivityCursor = { atMs: T, id: "deploy:vc_x:deploy" };
    const page = pageActivity(rows, cursor, 10, true);
    expect(page.rows.map((r) => r.id)).toEqual(["older", "deploy:vc_x:build"]);
  });

  it("splits one deployment's two rows across a page boundary without losing either", () => {
    const build = row(T - 1000, "deploy:vc_x:build");
    const deployRow = row(T - 1000, "deploy:vc_x:deploy");
    const first = pageActivity([build, deployRow], null, 1, false);
    expect(first.rows.map((r) => r.id)).toEqual(["deploy:vc_x:deploy"]);
    const second = pageActivity([build, deployRow], first.nextCursor, 1, true);
    expect(second.rows.map((r) => r.id)).toEqual(["deploy:vc_x:build"]);
  });

  it("re-serves a tie group rather than cut it, when the cursor id is from the RETIRED grammar", () => {
    // A tab open across the deploy that renamed deploy rows keeps its cursor, so the next
    // page it asks for carries `deploy:<target>:<step>:<atMs>:<id>`. That string cannot be
    // ordered against `deploy:<deploymentId>:<step>` — which way the tie group falls comes
    // down to which platform prefix happens to sort where — and cutting through it loses
    // those rows permanently, because the cursor only moves backward. Serving them again
    // is the recoverable direction: the client merges by id.
    const rows = [row(T, "deploy:vc_x:build"), row(T, "deploy:vc_x:deploy"), row(T - 1, "older")];
    const legacy: ActivityCursor = { atMs: T, id: "deploy:vercel|p|:deploy:1786000000000:vc_x" };
    const page = pageActivity(rows, legacy, 10, true);
    expect(page.rows.map((r) => r.id)).toEqual(["older", "deploy:vc_x:build", "deploy:vc_x:deploy"]);
  });

  it("reports exhaustion only when the sources were exhausted AND nothing was trimmed", () => {
    const rows = [row(T - 2000, "b"), row(T - 1000, "a")];
    expect(pageActivity(rows, null, 10, true).nextCursor).toBeNull();
    expect(pageActivity(rows, null, 10, false).nextCursor).toEqual({ atMs: T - 2000, id: "b" });
  });

  it("advances past a full page of identical timestamps rather than stalling", () => {
    // Every row shares one timestamp and all sort at/after the cursor: nothing is
    // keepable, and no (atMs, id) pair among them is older than the cursor — so the
    // cursor must step back in TIME or the reader is pinned on one page forever.
    const rows = [row(T, "a"), row(T, "b")];
    const cursor: ActivityCursor = { atMs: T, id: "a" };
    const page = pageActivity(rows, cursor, 10, false);
    expect(page.rows).toEqual([]);
    expect(page.nextCursor).toEqual({ atMs: T - 1, id: "" });
    // The property that matters: the next cursor is STRICTLY older than the one in.
    expect(page.nextCursor!.atMs).toBeLessThan(cursor.atMs);
  });

  it("does not report the end of history when the FOLD dropped everything", () => {
    // `issues` is a ledger: it keeps rows for targets the roster no longer watches, and
    // the fold drops those. So a page whose SQL returned a full limit can still derive
    // ZERO rows — which says nothing at all about what lies behind the window. This used
    // to short-circuit to `nextCursor: null` and end the scroll on the spot.
    const cursor: ActivityCursor = { atMs: T, id: "z" };
    const page = pageActivity([], cursor, 10, false, T - 60_000);
    expect(page.rows).toEqual([]);
    expect(page.nextCursor).not.toBeNull();
  });

  it("steps an empty page back to the page floor, not one tick", () => {
    // The floor is the oldest instant the SQL read COMPLETELY, so everything between it
    // and the cursor has already been seen and rejected. Stepping to `cursor.atMs - 1`
    // instead would re-read that whole span one millisecond per round trip.
    const cursor: ActivityCursor = { atMs: T, id: "z" };
    const floorMs = T - 60_000;
    const page = pageActivity([], cursor, 10, false, floorMs);
    // The floor itself, with the empty-id SENTINEL: that instant was read completely and
    // kept nothing, so it is consumed, and `r.id < ""` is false for every real row in it.
    // (`readSourcePage` is what makes "completely" true — it re-reads the boundary instant
    // in full, so the floor can never name a second the LIMIT cut through.)
    expect(page.nextCursor).toEqual({ atMs: floorMs, id: "" });
  });

  it("narrows to the sentinel when the floor IS the cursor's own instant", () => {
    // A whole page inside one second. The floor cannot go back in time, but the cursor
    // still carried a real id, so swapping it for the sentinel drops the remainder of that
    // instant — a strictly narrower cursor, which is all progress requires.
    const cursor: ActivityCursor = { atMs: T, id: "z" };
    // `zz` sorts AFTER the cursor's `z` at the same instant, so nothing is eligible.
    const page = pageActivity([row(T, "zz")], cursor, 10, false, T);
    expect(page.nextCursor).toEqual({ atMs: T, id: "" });
  });

  it("falls back to one tick when the floor cannot make progress", () => {
    // No usable floor: null (a caller that reports none), a floor NEWER than the cursor
    // (impossible from `readActivityPage`, whose reads are bounded by the cursor, but the
    // pure function must not hand back a cursor that moves forward), and a floor on the
    // cursor's instant when the cursor is ALREADY the sentinel — which would hand back the
    // cursor we came in with. All step off the instant instead.
    for (const [cursor, floorMs] of [
      [{ atMs: T, id: "z" }, null],
      [{ atMs: T, id: "z" }, T + 5000],
      [{ atMs: T, id: "" }, T],
    ] as [ActivityCursor, number | null][]) {
      const page = pageActivity([row(T, "zz")], cursor, 10, false, floorMs);
      expect(page.nextCursor).toEqual({ atMs: T - 1, id: "" });
    }
  });

  it("still reports the end of history when the sources ran dry", () => {
    // An empty page whose SQL under-filled every source IS the end — the floor is null
    // precisely because no source hit its limit.
    const cursor: ActivityCursor = { atMs: T, id: "z" };
    expect(pageActivity([], cursor, 10, true, null).nextCursor).toBeNull();
  });

  it("concatenating every page equals one unpaged derivation", () => {
    const all = Array.from({ length: 25 }, (_, i) => row(T - i * 1000, `id-${String(i).padStart(2, "0")}`));
    const collected: string[] = [];
    let cursor: ActivityCursor | null = null;
    for (let guard = 0; guard < 20; guard++) {
      const page: ReturnType<typeof pageActivity> = pageActivity(all, cursor, 4, true);
      collected.unshift(...page.rows.map((r) => r.id));
      if (page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    const unpaged = [...all].sort((a, b) => (a.at === b.at ? (a.id < b.id ? -1 : 1) : a.at < b.at ? -1 : 1));
    expect(collected).toEqual(unpaged.map((r) => r.id));
  });
});
