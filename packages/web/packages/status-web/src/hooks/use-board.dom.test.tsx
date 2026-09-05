// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import type { Board } from "../lib/board-types";
import { BOARD_STALE_MS, boardDataStaleMs } from "../lib/board-staleness";
import { useBoard } from "./use-board";
import { usePortfolioIndicator } from "./use-portfolio-indicator";
import { GlobalPanel } from "../components/GlobalPanel";

// vi.mock calls are hoisted above all imports by vitest's transform, so useBoard
// (imported above) sees this mocked subscribeLiveFrames rather than the real transport's.
// `useLiveSnapshot` itself is also stubbed inert (rather than left real) purely so
// `usePortfolioIndicator` — exercised below alongside GlobalPanel to prove the two
// AGREE on a stale board — doesn't open a real EventSource in this hook-level test.
const frameSubscribers = new Set<() => void>();
vi.mock("./use-live-snapshot", () => ({
  subscribeLiveFrames: (cb: () => void) => {
    frameSubscribers.add(cb);
    return () => frameSubscribers.delete(cb);
  },
  useLiveSnapshot: () => ({ snapshot: null, offline: false, blind: false }),
}));

// `generatedAt` is computed fresh (not a fixed literal) because Fix Round 3 item 1
// made `useBoard` itself judge every board against the real wall clock
// (`isBoardStale`, via `useNow`) — a hardcoded past date would go stale by
// construction and no test below would ever see a real (non-null) board.
const board: Board = {
  generatedAt: new Date().toISOString(),
  // Same reasoning for the DATA clock: a fixed literal would read as a wedged monitor.
  dataAsOfMs: Date.now(),
  // The default 60s cadence, whose window (`snapshotStaleMs` = max(5 × cadence, floor))
  // is exactly the FLOOR — the same widest-window value every threshold below is written
  // against. A board that silently carried a different cadence than the tests compute
  // would be exactly the pass-for-the-wrong-reason this file exists to remove.
  probeIntervalMs: 60_000,
  activityFromMs: Date.now() - 24 * 60 * 60 * 1000,
  indicator: "degraded",
  monitoredTargets: ["vercel|hub-help-testing|"],
  problems: [{
    target: "vercel|hub-help-testing|", source: "vercel", name: "hub-help-testing",
    environment: "production", severity: "major", state: "failed", statusCode: null,
    detail: "wip", sourceUrl: null, liveUrl: null, commitHash: "a", commitMessage: "wip",
    commitRepo: "adh", branch: null, errorText: null, since: "2026-08-02T11:00:00.000Z",
  }],
  activity: [],
};

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(board), {
    status: 200, headers: { "content-type": "application/json" },
  })));
  // jsdom's localStorage may be shadowed by Node's own inert global under this
  // runtime (same tolerance-of-absence pattern used elsewhere in this hook's tests).
  window.localStorage?.clear();
});

// RTL has no global auto-cleanup configured for this project (no setupFiles), so
// an un-unmounted renderHook leaves its subscribeLiveFrames subscription live —
// the module-level frameSubscribers mock is shared across every test in the file.
afterEach(() => {
  cleanup();
});

describe("useBoard", () => {
  it("renders the server's board verbatim", async () => {
    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.board).not.toBeNull());
    expect(result.current.board).toEqual(board);
  });

  it("writes NOTHING to localStorage — the client holds no durable state", async () => {
    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.board).not.toBeNull());
    expect(window.localStorage?.length ?? 0).toBe(0);
  });

  it("a problem that disappears server-side disappears client-side on the next read", async () => {
    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.board?.problems).toHaveLength(1));

    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      JSON.stringify({ ...board, problems: [], indicator: "operational" }),
      { status: 200, headers: { "content-type": "application/json" } })));
    result.current.refetch();
    await waitFor(() => expect(result.current.board?.problems).toEqual([]));
  });

  it("refetches when the live transport delivers a frame, not just on the poll", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify(board), {
      status: 200, headers: { "content-type": "application/json" },
    }));
    vi.stubGlobal("fetch", fetchMock);

    renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    expect(frameSubscribers.size).toBeGreaterThan(0);
    for (const cb of frameSubscribers) cb();

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  });
});

describe("useBoard — folding staleness into null (Fix Round 3 item 1)", () => {
  it("a stale-but-present board reads as null, with reason \"stale\" — a successful fetch is not the same as a current one", async () => {
    const staleBoard: Board = {
      ...board,
      generatedAt: new Date(Date.now() - BOARD_STALE_MS - 5_000).toISOString(),
    };
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(staleBoard), {
      status: 200, headers: { "content-type": "application/json" },
    })));

    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.reason).not.toBe("loading"));

    // The fetch DID succeed (no `error`) — this isn't "unavailable" — but the board
    // it returned is too old to back a current claim, so `board` reads null exactly
    // like a fetch that never landed, and `reason` is the only thing that tells the
    // two cases apart.
    expect(result.current.board).toBeNull();
    expect(result.current.reason).toBe("stale");
    expect(result.current.error).toBeNull();
  });

  it("the pill (usePortfolioIndicator) and GlobalPanel agree a stale board is unknown, not its last verdict", async () => {
    const staleBoard: Board = {
      ...board,
      // Green indicator + zero problems, so the only way either consumer could land
      // on "unknown" is by noticing the board itself is stale — not by the board
      // separately looking unhealthy. This is the exact scenario fix3 names: two
      // components reading the same frozen "operational, no problems" board must
      // NOT let one of them render it as current health.
      indicator: "operational",
      problems: [],
      generatedAt: new Date(Date.now() - BOARD_STALE_MS - 5_000).toISOString(),
    };
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(staleBoard), {
      status: 200, headers: { "content-type": "application/json" },
    })));

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    function sharedWrapper({ children }: { children: ReactNode }) {
      return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
    }

    const { result } = renderHook(() => usePortfolioIndicator(), { wrapper: sharedWrapper });
    render(<GlobalPanel platforms={[]} />, { wrapper: sharedWrapper });

    await waitFor(() => expect(result.current.pillKey).toBe("unknown"));
    expect(await screen.findByText(/status unknown/i)).toBeTruthy();
    expect(screen.queryByText(/no problems/i)).toBeNull();
  });
});

// Fix Round 4 group 6: the monitor can wedge while `/api/board` keeps answering
// perfectly. Every board below has a BRAND-NEW `generatedAt`, so `isBoardStale` says
// "fresh" and only the data clock can catch it.
describe("useBoard — folding a WEDGED MONITOR into null (Fix Round 4 group 6)", () => {
  function frozenBoard(over: Partial<Board>): Board {
    return {
      ...board,
      // Green + empty, so nothing about the board's CONTENT could produce "unknown".
      indicator: "operational",
      problems: [],
      generatedAt: new Date().toISOString(),
      ...over,
    };
  }

  function stubFetch(b: Board): void {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(b), {
      status: 200, headers: { "content-type": "application/json" },
    })));
  }

  it("a fresh board over FROZEN data reads as null, with reason \"frozen\"", async () => {
    stubFetch(frozenBoard({ dataAsOfMs: Date.now() - boardDataStaleMs() - 5_000 }));

    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.reason).not.toBe("loading"));

    expect(result.current.board).toBeNull();
    expect(result.current.error).toBeNull();
    // NOT "stale": the read is arriving on time. The distinction is the whole point —
    // "stale" sends a human to the API, "frozen" sends them to the monitor process.
    expect(result.current.reason).toBe("frozen");
  });

  it("a board resting on NO observations reads as null — an empty problems list is not health", async () => {
    stubFetch(frozenBoard({ dataAsOfMs: null }));

    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.reason).not.toBe("loading"));

    expect(result.current.board).toBeNull();
    // Fix Round 2 item C3: still null — nothing observed is never green — but a DIFFERENT
    // reason from "frozen", because the causes and the fixes are different. A roster with
    // nothing to observe lands here on a perfectly healthy monitor.
    expect(result.current.reason).toBe("no-data");
  });

  it("a fresh board over fresh data is handed through untouched — the new rule is not a blanket veto", async () => {
    const good = frozenBoard({ dataAsOfMs: Date.now() - 1_000 });
    stubFetch(good);

    const { result } = renderHook(() => useBoard(), { wrapper });
    await waitFor(() => expect(result.current.board).not.toBeNull());

    expect(result.current.reason).toBeNull();
    expect(result.current.board?.indicator).toBe("operational");
  });

  it("the pill agrees a wedged monitor is unknown, not its last verdict", async () => {
    stubFetch(frozenBoard({ dataAsOfMs: Date.now() - boardDataStaleMs() - 5_000 }));

    const { result } = renderHook(() => usePortfolioIndicator(), { wrapper });
    await waitFor(() => expect(result.current.pillKey).toBe("unknown"));
  });
});
