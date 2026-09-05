// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { useActivityHistory } from "./use-activity-history";
import type { ActivityRow } from "../lib/board-types";

function row(atMs: number, id: string): ActivityRow {
  return {
    id, kind: "deploy", step: "build", source: "vercel", tone: "good", verb: "built",
    target: "vercel|p|", name: "p", environment: "testing", detail: null, sourceUrl: null,
    liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null, branch: null,
    errorText: null, at: new Date(atMs).toISOString(),
  };
}
/** Same row, still asserting progress — what an unfinished build looks like on the wire. */
function building(atMs: number, id: string): ActivityRow {
  return { ...row(atMs, id), tone: "progress", verb: "building" };
}
const T = Date.UTC(2026, 7, 17, 12, 0, 0);
const liveOldest = row(T, "live-oldest");
// The live page the hook pages back FROM. Hoisted to module scope on purpose: the hook's
// absorb effect is keyed on this array's IDENTITY, so an inline `[liveOldest]` literal
// would re-run it on every render and make these tests measure re-render churn instead of
// the behaviour they name. Tests that mean to exercise absorption pass a NEW array.
const LIVE = [liveOldest];

beforeEach(() => vi.restoreAllMocks());

function stubPages(pages: { rows: ActivityRow[]; nextCursor: unknown }[]) {
  let i = 0;
  vi.stubGlobal("fetch", vi.fn(async () => ({
    ok: true, status: 200, json: async () => pages[Math.min(i++, pages.length - 1)],
  })));
}

describe("useActivityHistory", () => {
  it("fetches nothing while disabled", async () => {
    const f = vi.fn();
    vi.stubGlobal("fetch", f);
    const { result } = renderHook(() => useActivityHistory({ enabled: false, live: LIVE }));
    act(() => result.current.loadOlder());
    expect(f).not.toHaveBeenCalled();
  });

  it("pages back from the live page's oldest row and accumulates oldest-first", async () => {
    stubPages([
      { rows: [row(T - 2000, "b"), row(T - 1000, "a")], nextCursor: { atMs: T - 2000, id: "b" } },
      { rows: [row(T - 4000, "d"), row(T - 3000, "c")], nextCursor: null },
    ]);
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["b", "a"]));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["d", "c", "b", "a"]));
    expect(result.current.exhausted).toBe(true);
  });

  it("sends the cursor pair as before + beforeId", async () => {
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: null }]);
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    const url = String((globalThis.fetch as unknown as { mock: { calls: string[][] } }).mock.calls[0]![0]);
    expect(url).toContain(`before=${T}`);
    expect(url).toContain("beforeId=live-oldest");
  });

  it("dedupes a row already present in loaded history", async () => {
    stubPages([
      { rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } },
      { rows: [row(T - 1000, "a"), row(T - 2000, "b")], nextCursor: null },
    ]);
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["b", "a"]));
  });

  it("stops after MAX_AUTOPAGE_FETCHES and reports the budget spent", async () => {
    stubPages([{ rows: [row(T - 1000, "x")], nextCursor: { atMs: T - 1000, id: "x" } }]);
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    for (let i = 0; i < 8; i++) {
      act(() => result.current.loadOlder());
      await waitFor(() => expect(result.current.loading).toBe(false));
    }
    expect((globalThis.fetch as unknown as { mock: { calls: unknown[] } }).mock.calls.length).toBe(5);
    expect(result.current.autoBudgetSpent).toBe(true);
    act(() => result.current.resetAutoBudget());
    expect(result.current.autoBudgetSpent).toBe(false);
  });

  it("drops loaded history when disabled again", async () => {
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: null }]);
    const { result, rerender } = renderHook(
      ({ enabled }) => useActivityHistory({ enabled, live: LIVE }),
      { initialProps: { enabled: true } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    rerender({ enabled: false });
    expect(result.current.rows).toEqual([]);
  });

  it("drops a page that lands after history was discarded", async () => {
    // The fetch is held open across the disable, which is the only way this races.
    let release!: (v: unknown) => void;
    const held = new Promise((r) => {
      release = r;
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        await held;
        return { ok: true, status: 200, json: async () => ({ rows: [row(T - 1000, "a")], nextCursor: null }) };
      }),
    );
    const { result, rerender } = renderHook(
      ({ enabled }) => useActivityHistory({ enabled, live: LIVE }),
      { initialProps: { enabled: true } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.loading).toBe(true));
    rerender({ enabled: false });
    await act(async () => {
      release(null);
      // A plain `await held` returns one microtask too early — the fetch continuation
      // still has `res.json()` to await. A timer drains the whole queue behind it.
      await new Promise((r) => setTimeout(r, 0));
    });
    // Without the epoch guard this is ["a"] — history the reset had already thrown away.
    expect(result.current.rows).toEqual([]);
  });

  it("reports a failed page without claiming history is exhausted", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500, json: async () => ({}) })));
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.error).toBe(true));
    // A 500 says nothing about what lies behind the window. Reporting it as `exhausted`
    // would put "beginning of recorded activity" under a feed that simply failed to load.
    expect(result.current.exhausted).toBe(false);
    expect(result.current.rows).toEqual([]);
  });

  it("clears the error flag when the next attempt starts", async () => {
    let fail = true;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        fail
          ? { ok: false, status: 500, json: async () => ({}) }
          : { ok: true, status: 200, json: async () => ({ rows: [row(T - 1000, "a")], nextCursor: null }) },
      ),
    );
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.error).toBe(true));
    fail = false;
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    expect(result.current.error).toBe(false);
  });

  it("keeps the cursor after a failure so the next scroll retries the same window", async () => {
    let fail = true;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        fail
          ? { ok: false, status: 500, json: async () => ({}) }
          : { ok: true, status: 200, json: async () => ({ rows: [row(T - 1000, "a")], nextCursor: null }) },
      ),
    );
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.error).toBe(true));
    fail = false;
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    const calls = (globalThis.fetch as unknown as { mock: { calls: string[][] } }).mock.calls;
    // Both attempts asked for the SAME window: a failed page must not advance past rows
    // nobody has seen.
    expect(String(calls[1]![0])).toBe(String(calls[0]![0]));
  });

  it("keeps a row the live window sheds, once paging has started", async () => {
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } }]);
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: LIVE } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a"]));
    // The live window slides and drops `live-oldest`. History was paged from BELOW that
    // row, so nothing else holds it: without this it becomes a hole between history and
    // the live page, one that grows for as long as the tab stays open.
    rerender({ live: [row(T + 1000, "newer")] });
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a", "live-oldest"]));
  });

  it("keeps only what LEFT the window, never the window itself", async () => {
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } }]);
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: LIVE } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a"]));
    // `live-oldest` is still live and a new row joined it. Copying either into history
    // would double it on screen — the pane concatenates history with `board.activity`.
    rerender({ live: [liveOldest, row(T + 1000, "newer")] });
    expect(result.current.rows.map((r) => r.id)).toEqual(["a"]);
  });

  it("lets shed rows go while the reader has not paged back", async () => {
    vi.stubGlobal("fetch", vi.fn());
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: LIVE } },
    );
    rerender({ live: [row(T + 1000, "newer")] });
    // There is no history to hole yet, and the next page will start from wherever the
    // window's oldest row has moved to. Keeping them would grow an idle tab's memory for
    // a scroll nobody performed.
    expect(result.current.rows).toEqual([]);
  });

  it("never freezes a row that left the window while still building", async () => {
    // A `deploying`/`building` row leaves `board.activity` for reasons that have nothing
    // to do with age — the provider re-maps a superseded deployment to phase `none`, the
    // reconcile collapses one it can no longer find, an endpoint is disabled, the 300-row
    // cap evicts under a burst. Frozen here it becomes a permanent "building" for a
    // deployment that has long finished, unreachable by any refetch because it no longer
    // lives in `board.activity`. That IS the bug this feature keeps re-growing.
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } }]);
    const wip = building(T, "wip");
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: [wip] } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a"]));
    rerender({ live: [row(T + 1000, "newer")] });
    expect(result.current.rows.map((r) => r.id)).toEqual(["a"]);
  });

  it("keeps only what fell off the OLD end, not a row that vanished mid-window", async () => {
    // `gone` sorts ABOVE the window's new oldest row, so it did not age out — something
    // stopped deriving it. Freezing it would strand a row the server has deliberately
    // withdrawn, in a slot the live page can never mask because the id will not return.
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } }]);
    const keepOldest = row(T, "keep-oldest");
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: [keepOldest, row(T + 1000, "gone")] } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a"]));
    rerender({ live: [keepOldest, row(T + 2000, "newer")] });
    expect(result.current.rows.map((r) => r.id)).toEqual(["a"]);
  });

  it("reads an empty live window as an outage, not as the whole window shedding", async () => {
    // `use-board.ts` nulls the board while a read is stale or the monitor's data is
    // frozen, and OverviewTab passes `board?.activity ?? []`. Absorbing that would freeze
    // every row in the window — including every in-flight one — on an ordinary API blip.
    // The pre-blip window must also SURVIVE, so a row that genuinely ages out during the
    // outage is still caught when the board comes back.
    stubPages([{ rows: [row(T - 1000, "a")], nextCursor: { atMs: T - 1000, id: "a" } }]);
    const { result, rerender } = renderHook(
      ({ live }) => useActivityHistory({ enabled: true, live }),
      { initialProps: { live: LIVE } },
    );
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a"]));
    rerender({ live: [] });
    expect(result.current.rows.map((r) => r.id)).toEqual(["a"]);
    rerender({ live: [row(T + 1000, "newer")] });
    await waitFor(() => expect(result.current.rows.map((r) => r.id)).toEqual(["a", "live-oldest"]));
  });

  it("lets a later copy of a held row replace it", async () => {
    // Row ids are stable now, so a second copy of an id is a NEWER READING of the same
    // fact, not a different row. Keeping the first would make a stale account permanent:
    // cursors only move backward, so no later page can repair it.
    const stale = { ...building(T - 1000, "a"), detail: "building on vercel" };
    const settled = { ...row(T - 1000, "a"), detail: "built on vercel" };
    stubPages([
      { rows: [stale], nextCursor: { atMs: T - 1000, id: "a" } },
      { rows: [settled], nextCursor: null },
    ]);
    const { result } = renderHook(() => useActivityHistory({ enabled: true, live: LIVE }));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows[0]?.tone).toBe("progress"));
    act(() => result.current.loadOlder());
    await waitFor(() => expect(result.current.rows[0]?.tone).toBe("good"));
    expect(result.current.rows).toHaveLength(1);
    expect(result.current.rows[0]?.detail).toBe("built on vercel");
  });
});
