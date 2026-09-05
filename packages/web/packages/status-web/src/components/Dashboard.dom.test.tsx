// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { Dashboard } from "./Dashboard";

// Fix Round 4 items 3.1 + 3.2. The Details tab had TWO ways to say "everything is
// fine" that could not see the board:
//   3.1 the KPI strip's incident chip was `board?.problems.length ?? 0`, so an
//       unreadable board rendered a strip byte-identical to a clean portfolio;
//   3.2 the big green ✓ watermark was derived from /api/status services + live
//       deploys, so a board problem with no matching monitored endpoint (a
//       platform-unreachable provider, a Crunchy cluster, a project with no probe)
//       left the ✓ on screen while Problems was non-empty.
// Both now read the board, and an unreadable board claims nothing.

// Everything mocked below is a DATA-FETCHING dependency Dashboard pulls in BESIDES the
// board — this file is about what the board does to the strip and the watermark, so the
// sibling feeds are stubbed wholesale (same pattern as OverviewTab.dom.test.tsx).
vi.mock("../hooks/use-live-snapshot", () => ({
  useLiveSnapshot: () => ({ snapshot: { deployments: [], probeIntervalMs: 60_000 } }),
  // useBoard (real, unmocked) subscribes to live frames to refetch; a no-op is enough.
  // The cadence it scales its data-staleness window by rides on the board itself now, so
  // this mock has nothing else to supply.
  subscribeLiveFrames: () => () => {},
}));
vi.mock("../hooks/use-uptime", () => ({ useUptime: () => ({ data: undefined, isLoading: false }) }));
vi.mock("../hooks/use-integrations", () => ({ useIntegrations: () => ({ data: undefined, isLoading: false }) }));
// Every /api/status service is HEALTHY in every case below, so the only thing that can
// change the ✓ is the board — which is the whole point of 3.2.
vi.mock("../hooks/use-status", () => ({
  useStatus: () => ({
    isLoading: false,
    error: null,
    data: {
      overall: "operational",
      checkedAt: new Date().toISOString(),
      services: [
        { slug: "adh-app-production", group: "G", name: "App", url: "https://x.example.com/health", environment: "production", platform: null, deployProject: null, status: "healthy", responseTimeMs: 10, statusCode: 200, error: null, lastCheckedAt: new Date().toISOString(), dnsOk: true },
      ],
    },
  }),
}));
// The split is layout, not behaviour: render both halves inline so the watermark (in
// `top`) and the KPI strip are both in the tree without a real ResizeObserver.
vi.mock("@agentic-toolkit/ui/components/resizable-split", () => ({
  ResizableSplit: ({ top, bottom }: { top: ReactNode; bottom: ReactNode }) => (
    <div>{top}{bottom}</div>
  ),
}));

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});
beforeEach(() => {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: false, media: query, onchange: null,
    addListener: () => {}, removeListener: () => {},
    addEventListener: () => {}, removeEventListener: () => {}, dispatchEvent: () => false,
  }));
});

function renderWithBoardFetch(fetchImpl: () => Promise<Response>) {
  vi.stubGlobal("fetch", vi.fn(fetchImpl));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <Dashboard />
    </QueryClientProvider>,
  );
}

function boardJson(body: Record<string, unknown>) {
  return async () => new Response(JSON.stringify(body), {
    status: 200, headers: { "content-type": "application/json" },
  });
}

const PROBLEM = {
  // A platform-unreachable problem: it owns NO monitored endpoint, so the old
  // services-derived allClear could not see it at all.
  target: "platform-health|vercel", source: "vercel", name: "Vercel", environment: null,
  severity: "critical", state: "unreachable", statusCode: null, detail: "API unreachable",
  sourceUrl: null, liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null,
  since: new Date().toISOString(),
};

function board(overrides: Record<string, unknown> = {}) {
  return {
    generatedAt: new Date().toISOString(),
    dataAsOfMs: Date.now(),
    problems: [],
    activity: [],
    indicator: "operational",
    monitoredTargets: [],
    ...overrides,
  };
}

/** The all-clear watermark — the aria-hidden ✓ painted behind the matrix. */
function watermark(): Element | undefined {
  return Array.from(document.body.querySelectorAll("span")).find((el) => el.textContent === "✓");
}

describe("Dashboard — the KPI strip never claims a clean portfolio off an unreadable board (3.1)", () => {
  it("a rejected board fetch shows the unknown affordance, not a strip with no incident chip", async () => {
    renderWithBoardFetch(async () => {
      throw new Error("network down");
    });

    // useBoard sets its own `retry: 1`, which wins over the client-level default —
    // the real hook genuinely retries once before erroring (see OverviewTab.dom.test.tsx).
    expect(await screen.findByText(/incidents unknown/i, {}, { timeout: 3000 })).toBeTruthy();
    expect(screen.queryByText(/\d+ incident/i)).toBeNull(); // no count chip, clean or otherwise
  });

  it("a 500 board fetch shows the unknown affordance", async () => {
    renderWithBoardFetch(async () => new Response("", { status: 500 }));
    expect(await screen.findByText(/incidents unknown/i, {}, { timeout: 3000 })).toBeTruthy();
  });

  it("a board that genuinely reports zero problems shows NO chip and NO unknown affordance", async () => {
    renderWithBoardFetch(boardJson(board()));
    // Wait for the board to land (the ✓ only paints once it has).
    await screen.findByText("✓");
    expect(screen.queryByText(/incidents unknown/i)).toBeNull();
    expect(screen.queryByText(/\d+ incident/i)).toBeNull();
  });

  it("a board with problems shows the count", async () => {
    renderWithBoardFetch(boardJson(board({ problems: [PROBLEM], indicator: "outage" })));
    expect(await screen.findByText(/1 incident/i)).toBeTruthy();
    expect(screen.queryByText(/incidents unknown/i)).toBeNull();
  });
});

// Fix Round 2 item C7. The strip's headline verdict was `/api/status`'s `overall`,
// printed inches from an incident count read off the board. `/api/status` sees endpoint
// health only; the board also raises platform-unreachable, Crunchy and stale-prod
// problems. Every mocked service above is HEALTHY, so `/api/status` says "operational"
// in every case here — which is exactly the state that used to produce a strip reading
// "OPERATIONAL ⚠ 1 incident".
describe("Dashboard — the headline verdict and the incident count have ONE producer (C7)", () => {
  it("a board reporting an outage never prints OPERATIONAL, though every endpoint is up", async () => {
    renderWithBoardFetch(boardJson(board({ problems: [PROBLEM], indicator: "outage" })));

    expect(await screen.findByText(/1 incident/i)).toBeTruthy();
    expect(screen.getByText("MAJOR OUTAGE")).toBeTruthy();
    expect(screen.queryByText("OPERATIONAL")).toBeNull();
    // The endpoint counts stay on /api/status and stay truthful — they answer a
    // narrower question, and their label says so.
    expect(screen.getByText(/endpoints up/i)).toBeTruthy();
  });

  it("a board reporting degraded prints DEGRADED, not the endpoint-derived verdict", async () => {
    renderWithBoardFetch(boardJson(board({ problems: [PROBLEM], indicator: "degraded" })));

    expect(await screen.findByText(/1 incident/i)).toBeTruthy();
    expect(screen.getByText("DEGRADED")).toBeTruthy();
    expect(screen.queryByText("OPERATIONAL")).toBeNull();
  });

  it("an unreadable board prints UNKNOWN — an absent verdict is not a green one", async () => {
    renderWithBoardFetch(async () => new Response("", { status: 500 }));

    expect(await screen.findByText(/incidents unknown/i, {}, { timeout: 3000 })).toBeTruthy();
    expect(screen.getByText("UNKNOWN")).toBeTruthy();
    expect(screen.queryByText("OPERATIONAL")).toBeNull();
  });

  it("an operational board still prints OPERATIONAL — the change is not a blanket veto", async () => {
    renderWithBoardFetch(boardJson(board()));

    expect(await screen.findByText("OPERATIONAL")).toBeTruthy();
    expect(screen.queryByText(/incidents unknown/i)).toBeNull();
  });
});

describe("Dashboard — the ✓ watermark is the board's verdict, not a second producer (3.2)", () => {
  it("a non-empty board.problems suppresses the ✓ even though every /api/status service is healthy", async () => {
    renderWithBoardFetch(boardJson(board({ problems: [PROBLEM], indicator: "outage" })));
    // The incident chip proves the board landed; the ✓ must be absent anyway.
    expect(await screen.findByText(/1 incident/i)).toBeTruthy();
    expect(watermark()).toBeUndefined();
  });

  it("an unreadable board paints NO ✓ — unknown is not clear", async () => {
    renderWithBoardFetch(async () => new Response("", { status: 500 }));
    expect(await screen.findByText(/incidents unknown/i, {}, { timeout: 3000 })).toBeTruthy();
    expect(watermark()).toBeUndefined();
  });

  it("an operational board paints the ✓", async () => {
    renderWithBoardFetch(boardJson(board()));
    expect(await screen.findByText("✓")).toBeTruthy();
  });
});
