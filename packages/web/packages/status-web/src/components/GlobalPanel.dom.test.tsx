// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { GlobalPanel } from "./GlobalPanel";

// Fix Round 2 item 2: GlobalPanel must not render the green "no problems ✓" all-clear
// off a board it never successfully read — that is the same forbidden claim C1 was
// about (a health verdict from an ABSENCE of data), just on the Details tab's pane
// instead of the Overview tab. `board === null` (fetch rejected, or a non-ok response)
// must read as "unknown", and only a board that genuinely came back with zero problems
// may show the green check.

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderWithBoardFetch(fetchImpl: () => Promise<Response>) {
  vi.stubGlobal("fetch", vi.fn(fetchImpl));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <GlobalPanel platforms={[]} />
    </QueryClientProvider>,
  );
}

describe("GlobalPanel — problems-by-source pane never claims health off a null board", () => {
  it("a rejected board fetch shows 'status unknown', never 'no problems'", async () => {
    renderWithBoardFetch(async () => {
      throw new Error("network down");
    });

    expect(await screen.findByText(/status unknown/i)).toBeTruthy();
    expect(screen.queryByText(/no problems/i)).toBeNull();
  });

  it("a 500 board fetch shows 'status unknown', never 'no problems'", async () => {
    renderWithBoardFetch(async () => new Response("", { status: 500 }));

    expect(await screen.findByText(/status unknown/i)).toBeTruthy();
    expect(screen.queryByText(/no problems/i)).toBeNull();
  });

  it("a board that genuinely has zero problems still shows the green all-clear", async () => {
    renderWithBoardFetch(async () =>
      new Response(
        JSON.stringify({
          generatedAt: new Date().toISOString(),
          dataAsOfMs: Date.now(),
          problems: [],
          activity: [],
          indicator: "operational",
          monitoredTargets: [],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    expect(await screen.findByText(/no problems/i)).toBeTruthy();
    expect(screen.queryByText(/status unknown/i)).toBeNull();
  });
});
