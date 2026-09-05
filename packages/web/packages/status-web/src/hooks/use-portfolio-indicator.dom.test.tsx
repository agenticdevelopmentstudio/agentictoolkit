// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { renderHook, cleanup } from "@testing-library/react";
import { usePortfolioIndicator } from "./use-portfolio-indicator";

// Fix Round 3 item 1: `useBoard` itself now folds "never arrived", "fetch failed",
// AND "gone stale" into a single `board: null` — this hook no longer computes its
// own `isBoardStale` term (that was the second of three instances of one bug: a
// consumer re-deriving a check the hook can just never let it skip). So this file
// mocks `useBoard` at the boundary and only proves `usePortfolioIndicator` treats
// whatever `board` it's handed literally: null renders "unknown" regardless of WHY
// it's null, non-null backs its own indicator. The "why does a stale board become
// null" rule itself is exercised against the REAL `useBoard` in
// `use-board.dom.test.tsx`, alongside a test that this hook and `GlobalPanel` agree.

const mockState = vi.hoisted(() => ({
  snapshot: null as { lastCycleAt: string | null; generatedAt: string; probeIntervalMs?: number } | null,
  offline: false,
  blind: false,
  board: null as { generatedAt: string; indicator: "operational" | "degraded" | "outage"; problems: unknown[] } | null,
}));

vi.mock("./use-live-snapshot", () => ({
  useLiveSnapshot: () => ({ snapshot: mockState.snapshot, offline: mockState.offline, blind: mockState.blind }),
}));
vi.mock("./use-board", () => ({ useBoard: () => ({ board: mockState.board }) }));

afterEach(() => {
  cleanup();
  mockState.snapshot = null;
  mockState.offline = false;
  mockState.blind = false;
  mockState.board = null;
});

describe("usePortfolioIndicator — trusts useBoard's null fold, doesn't re-derive it", () => {
  it("a present board backs its own verdict", () => {
    mockState.board = {
      generatedAt: new Date().toISOString(),
      indicator: "operational",
      problems: [],
    };

    const { result } = renderHook(() => usePortfolioIndicator());
    expect(result.current.pillKey).toBe("ok");
  });

  it("board === null renders unknown, never the last verdict — whatever null means this time", () => {
    // Deliberately not constructing a stale board with an old `generatedAt` here:
    // this hook no longer has an `isBoardStale` term to exercise (Fix Round 3 item
    // 1 removed it), so a board object could only ever demonstrate the mock is
    // wired, not that the hook does anything. `board === null` is the one signal
    // this hook still reads directly, and it's the same signal for all three
    // reasons `useBoard` can produce it.
    mockState.board = null;

    const { result } = renderHook(() => usePortfolioIndicator());
    expect(result.current.pillKey).toBe("unknown");
  });
});
