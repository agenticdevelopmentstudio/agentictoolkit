// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { OverviewTab } from "./OverviewTab";
import { BOARD_STALE_MS, boardDataStaleMs } from "../lib/board-staleness";

// Everything below mocks a DATA-FETCHING dependency OverviewTab pulls in besides the
// board — the point of this file is the board-unreadable branch (CRITICAL 1), not
// useUptime/useIntegrations/useConfigStatus/useTelemetry's own fetch chains, so those
// are stubbed out wholesale (mirrors StaleMonitorsBanner.dom.test.tsx's pattern of
// mocking a whole hook/component module rather than satisfying its real network calls).

const mobile = vi.hoisted(() => ({ current: false }));
// The live snapshot's `blind` — "the last snapshot monitored NOTHING". A ref rather
// than a literal so the C3 cases below can pose the empty roster this whole branch is
// about, without a second mock factory. Reset in afterEach beside `mobile`.
const blind = vi.hoisted(() => ({ current: false }));

vi.mock("../hooks/use-live-snapshot", () => ({
  useLiveSnapshot: () => ({
    snapshot: { services: [], monitorVersion: null, configDegraded: false, configReason: null },
    offline: false,
    disconnected: false,
    blind: blind.current,
    offlineDetail: null,
    polling: false,
    nextPollAt: null,
    refresh: vi.fn(),
    reconnect: vi.fn(),
  }),
  // useBoard (unmocked, real) imports this to refetch on a live frame; a no-op
  // subscription is all it needs here. The cadence it scales its data-staleness window by
  // now rides on the board itself, so this mock no longer has a say in it.
  subscribeLiveFrames: () => () => {},
}));
vi.mock("../hooks/use-uptime", () => ({ useUptime: () => ({ data: undefined, isLoading: false }) }));
vi.mock("../hooks/use-integrations", () => ({ useIntegrations: () => ({ data: undefined, isLoading: false }) }));
vi.mock("./UnconfiguredProjectsBanner", () => ({ UnconfiguredProjectsBanner: () => null }));
vi.mock("./StaleMonitorsBanner", () => ({ StaleMonitorsBanner: () => null }));
vi.mock("./TelemetrySections", () => ({ ErrorsCard: () => null, TrafficCard: () => null }));

// jsdom has no matchMedia; useMediaQuery calls it directly with no defensive guard.
// `mobile.current` lets a test force the mobile layout (BigIndicator's headline) on
// top of the desktop layout (ActivityPanel's "No problems" empty state) so a single
// pass over both scenarios below covers both of C1's forbidden renders. Re-stubbed in
// beforeEach because afterEach's vi.unstubAllGlobals() clears it after every test.
beforeEach(() => {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: mobile.current,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }));
});

afterEach(() => {
  cleanup();
  mobile.current = false;
  blind.current = false;
  vi.unstubAllGlobals();
});

function renderWithBoardFetch(fetchImpl: () => Promise<Response>) {
  vi.stubGlobal("fetch", vi.fn(fetchImpl));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <OverviewTab />
    </QueryClientProvider>,
  );
}

// CRITICAL 1: board === null (fetch rejected, or a non-ok response) must never render
// as "operational" or an empty, all-clear Problems list — that would be a false claim
// of health from having NO data, not from having checked anything. It must instead
// surface the fetch failure visibly. Pinned here against BOTH failure shapes the
// review called out (a rejected fetch, and a non-2xx response).
describe("OverviewTab — board unreadable (C1)", () => {
  it("a rejected board fetch never claims 'No problems' (desktop), and surfaces the error", async () => {
    mobile.current = false;
    renderWithBoardFetch(async () => {
      throw new Error("network down");
    });

    // Fix Round 2 item 5: useBoard now sets its own `retry: 1` (matching
    // useLiveSnapshot's sibling choice), which — being the query's own explicit
    // option — wins over this file's client-level `retry: false` default. So the
    // real hook genuinely retries once (~1s backoff) before erroring; the extended
    // timeout accounts for that real delay rather than racing it.
    expect(await screen.findByText(/board unavailable/i, {}, { timeout: 3000 })).toBeTruthy();
    expect(screen.getByText(/network down/i)).toBeTruthy();
    expect(screen.queryByText(/No problems/i)).toBeNull();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
  });

  it("a 500 board fetch never claims ALL SYSTEMS OPERATIONAL (mobile hero), and surfaces the error", async () => {
    mobile.current = true;
    renderWithBoardFetch(async () => new Response("", { status: 500 }));

    // See the timeout comment above — same reason.
    expect(await screen.findByText(/board unavailable/i, {}, { timeout: 3000 })).toBeTruthy();
    expect(screen.getByText(/board fetch failed: 500/i)).toBeTruthy();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
    expect(screen.queryByText(/No problems/i)).toBeNull();
  });
});

// Fix Round 2 item 3: a board that HAS successfully loaded but stopped refreshing
// (a permanently-500ing /api/board after one good read — React Query keeps the last
// good `data` forever, use-board.ts) must degrade to the same "unknown" panel as a
// board that never loaded at all — not keep rendering its last (green) verdict.
// Fix Round 3 item 1: the staleness check itself now lives inside `useBoard` (it
// folds a stale board into `board: null` with `reason: "stale"`) rather than
// OverviewTab computing its own `isBoardStale` term — these tests are unchanged in
// what they assert because OverviewTab's `!board` branch already covered this panel;
// only the mechanism producing `board === null` moved.
describe("OverviewTab — board frozen by a persistent failure (Fix Round 2 item 3, folded into useBoard in Round 3)", () => {
  it("a board whose generatedAt is past the stale window renders unknown, not its last verdict", async () => {
    mobile.current = false;
    const staleBoard = {
      generatedAt: new Date(Date.now() - BOARD_STALE_MS - 5_000).toISOString(),
      // Its DATA was current as of its own derivation — the read itself is what stopped
      // arriving, so this exercises `stale` and not group 6's `frozen`.
      dataAsOfMs: Date.now() - BOARD_STALE_MS - 5_000,
      indicator: "operational",
      problems: [],
      activity: [],
      monitoredTargets: [],
    };
    renderWithBoardFetch(async () => new Response(JSON.stringify(staleBoard), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/has not refreshed/i)).toBeTruthy();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
    expect(screen.queryByText(/^No problems$/i)).toBeNull();
  });

  it("a board that just refreshed renders the normal panels, not the unknown panel", async () => {
    mobile.current = false;
    const freshBoard = {
      generatedAt: new Date().toISOString(),
      dataAsOfMs: Date.now(),
      indicator: "operational",
      problems: [],
      activity: [],
      monitoredTargets: [],
    };
    renderWithBoardFetch(async () => new Response(JSON.stringify(freshBoard), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/No problems/i)).toBeTruthy();
    expect(screen.queryByText(/has not refreshed/i)).toBeNull();
  });
});

// Fix Round 4 group 6: the monitor process wedges while /api/board keeps answering.
// The facts freeze at last-known-healthy, `problems` stays empty and `indicator` stays
// "operational" — and `generatedAt` is re-stamped on every read, so the Round 2/3
// staleness rule above is structurally blind to it. This is the same false claim of
// health from an absence of data as C1, arriving through a different door.
describe("OverviewTab — the monitor is wedged (Fix Round 4 group 6)", () => {
  function wedged(dataAsOfMs: number | null) {
    return {
      generatedAt: new Date().toISOString(), // brand new — the READ is perfectly healthy
      dataAsOfMs,
      indicator: "operational",
      problems: [],
      activity: [],
      monitoredTargets: [],
    };
  }

  it("a fresh board over data older than the window renders unknown, not ALL SYSTEMS OPERATIONAL", async () => {
    mobile.current = true; // the mobile hero is where "ALL SYSTEMS OPERATIONAL" is shouted
    renderWithBoardFetch(async () => new Response(JSON.stringify(wedged(Date.now() - boardDataStaleMs() - 5_000)), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/board unavailable/i)).toBeTruthy();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
    expect(screen.queryByText(/No problems/i)).toBeNull();
    // And it must not blame the API, which is answering fine — the words a reader gets
    // have to point at the thing that is actually broken.
    expect(screen.queryByText(/has not refreshed/i)).toBeNull();
    expect(screen.getByText(/nothing behind it is/i)).toBeTruthy();
  });

  it("a board resting on NO observations at all, with endpoints to watch, renders unknown", async () => {
    mobile.current = false; // desktop: the empty Problems list is where the lie would be
    renderWithBoardFetch(async () => new Response(JSON.stringify(wedged(null)), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/board unavailable/i)).toBeTruthy();
    expect(screen.queryByText(/^No problems$/i)).toBeNull();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
    // The words point at the monitor, because there IS something it should have looked
    // at and hasn't — the opposite case is the C3 describe below.
    expect(screen.getByText(/has not recorded a single observation yet/i)).toBeTruthy();
  });

  it("a board whose data is current renders the normal panels — the guard is not a blanket veto", async () => {
    mobile.current = false;
    renderWithBoardFetch(async () => new Response(JSON.stringify(wedged(Date.now() - 1_000)), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/No problems/i)).toBeTruthy();
    expect(screen.queryByText(/board unavailable/i)).toBeNull();
  });
});

// Fix Round 2 item C3. The group-6 guard above, applied to an EMPTY ROSTER, diagnosed a
// perfectly healthy monitor as a broken one: nothing configured to observe means nothing
// observed, means `dataAsOfMs === null`, means a null board — and the `!board` branch ran
// first, so the actionable "no endpoints configured" panel became unreachable for exactly
// the roster it was written for. The two states must render differently.
describe("OverviewTab — an empty roster is a config fault, not a wedged monitor (C3)", () => {
  function board(dataAsOfMs: number | null) {
    return {
      generatedAt: new Date().toISOString(),
      dataAsOfMs,
      indicator: "operational",
      problems: [],
      activity: [],
      monitoredTargets: [],
    };
  }

  it("no endpoints AND no observations reaches the actionable blind panel", async () => {
    mobile.current = false;
    blind.current = true; // the live snapshot monitored NOTHING
    renderWithBoardFetch(async () => new Response(JSON.stringify(board(null)), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/no endpoints configured/i)).toBeTruthy();
    // NOT the monitor-process panel: the monitor is doing exactly what it was told to.
    expect(screen.queryByText(/board unavailable/i)).toBeNull();
    expect(screen.queryByText(/check the monitor process/i)).toBeNull();
    // …and still never a health claim.
    expect(screen.queryByText(/^No problems$/i)).toBeNull();
    expect(screen.queryByText(/ALL SYSTEMS OPERATIONAL/i)).toBeNull();
  });

  it("an empty roster whose observations went STALE still reaches the frozen panel", async () => {
    mobile.current = false;
    blind.current = true;
    // Platform samples exist (a fleet can have integrations and no HTTP endpoints) and
    // have stopped moving. `blind` must NOT mask that: a wedged monitor is a stronger
    // "we don't know" than a config message, and the config message would be a lie here.
    renderWithBoardFetch(async () => new Response(JSON.stringify(board(Date.now() - boardDataStaleMs() - 5_000)), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/board unavailable/i)).toBeTruthy();
    expect(screen.getByText(/nothing behind it is/i)).toBeTruthy();
    expect(screen.queryByText(/no endpoints configured/i)).toBeNull();
  });

  it("an empty roster with a READ that stopped arriving still reaches the stale panel", async () => {
    mobile.current = false;
    blind.current = true;
    const stale = { ...board(Date.now() - BOARD_STALE_MS - 5_000),
                    generatedAt: new Date(Date.now() - BOARD_STALE_MS - 5_000).toISOString() };
    renderWithBoardFetch(async () => new Response(JSON.stringify(stale), {
      status: 200, headers: { "content-type": "application/json" },
    }));

    expect(await screen.findByText(/has not refreshed/i)).toBeTruthy();
    expect(screen.queryByText(/no endpoints configured/i)).toBeNull();
  });
});
