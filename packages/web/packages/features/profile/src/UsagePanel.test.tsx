// @vitest-environment jsdom
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { render, screen, waitFor, cleanup } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { UsageRow } from "@agentic-toolkit/data/profile";

// Stub the read path — the panel's whole job is arranging rows it is handed, and the numbers
// themselves are the ledger's (covered by the backend's usage-ledger tests).
const { getUsageSummary } = vi.hoisted(() => ({ getUsageSummary: vi.fn() }));
vi.mock("@agentic-toolkit/data/profile", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/profile")>()),
  getUsageSummary,
}));

import { UsagePanel } from "./UsagePanel";

// The hub vitest config has no global afterEach; tear each render down explicitly.
afterEach(cleanup);
// Braces are load-bearing: vitest treats a value RETURNED from a hook as that hook's teardown,
// and `mockReset()` returns the mock — so the concise-body form would CALL the mock after every
// test, rejecting into nobody's hands on the error cases.
beforeEach(() => {
  getUsageSummary.mockReset();
});

const UNCAPPED = {
  quotaRequests: null,
  quotaBytes: null,
  quotaTokens: null,
  quotaCostMicros: null,
  enforced: false,
};

function row(over: Partial<UsageRow> & Pick<UsageRow, "kind">): UsageRow {
  return {
    kind: over.kind,
    scope: over.scope ?? "user",
    principalId: over.principalId ?? "p1",
    label: over.label ?? "Someone",
    periodStart: over.periodStart ?? "2026-07-01",
    periodDays: over.periodDays ?? 30,
    tier: over.tier ?? "free",
    limits: over.limits ?? UNCAPPED,
    requests: over.requests ?? 0,
    bytes: over.bytes ?? 0,
    tokens: over.tokens ?? 0,
    costMicros: over.costMicros ?? 0,
  };
}

function renderPanel(props: { workspaceSlug?: string } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <UsagePanel {...props} />
    </QueryClientProvider>,
  );
}

describe("UsagePanel — the self view", () => {
  const SELF: UsageRow[] = [
    row({ kind: "self", principalId: "u1", label: "Me", requests: 10, tokens: 100, costMicros: 5 }),
    row({ kind: "token", scope: "token", principalId: "t1", label: "CI token", requests: 7 }),
    row({
      kind: "persona",
      scope: "persona",
      principalId: "pa1",
      label: "Ada",
      requests: 1000,
      tokens: 9999,
    }),
  ];

  it("asks for the caller's own principals when mounted outside a workspace", async () => {
    getUsageSummary.mockResolvedValue(SELF);
    renderPanel();
    await waitFor(() => expect(screen.getByText("Me")).toBeTruthy());
    expect(getUsageSummary).toHaveBeenCalledWith(undefined);
  });

  it("gives personas their own section and keeps them OUT of the total", async () => {
    getUsageSummary.mockResolvedValue(SELF);
    renderPanel();

    await waitFor(() => expect(screen.getByText("Ada")).toBeTruthy());
    expect(screen.getByText("Personas")).toBeTruthy();
    // Acting rows only: 10 + 7. Folding the persona's 1,000 in would read 1,017.
    expect(screen.getByText("17")).toBeTruthy();
    expect(screen.queryByText("1,017")).toBeNull();
  });

  it("says out loud that limits are only being observed", async () => {
    getUsageSummary.mockResolvedValue([
      row({ kind: "self", limits: { ...UNCAPPED, quotaRequests: 200 }, requests: 199 }),
    ]);
    renderPanel();
    await waitFor(() => expect(screen.getByText(/being recorded, not enforced/)).toBeTruthy());
    // A cap that CAN refuse this key is drawn as used/limit.
    expect(screen.getByText("199 / 200")).toBeTruthy();
  });

  it("draws no bar for a cap that never fires for this key's role", async () => {
    getUsageSummary.mockResolvedValue([
      row({ kind: "self", limits: { ...UNCAPPED, quotaTokens: 1000 }, tokens: 500 }),
    ]);
    renderPanel();
    // The token cap bites on the BILLING key, not on an acting one — so it is a bare number.
    await waitFor(() => expect(screen.getAllByText("500").length).toBeGreaterThan(0));
    expect(screen.queryByText("500 / 1,000")).toBeNull();
  });

  it("shows an empty state when nothing has been metered", async () => {
    getUsageSummary.mockResolvedValue([]);
    renderPanel();
    await waitFor(() => expect(screen.getByText(/^Nothing metered yet\./)).toBeTruthy());
  });
});

describe("UsagePanel — the workspace view", () => {
  it("scopes the request to the workspace it is mounted in", async () => {
    getUsageSummary.mockResolvedValue([
      row({ kind: "member", principalId: "u2", label: "Teammate", requests: 4 }),
    ]);
    renderPanel({ workspaceSlug: "acme" });
    await waitFor(() => expect(screen.getByText("Teammate")).toBeTruthy());
    expect(getUsageSummary).toHaveBeenCalledWith({ workspace: "acme" });
  });

  it("reads a 403 as an ordinary outcome, not a failure", async () => {
    // Every org member can open the Settings rail; only a workspace admin may read the roster.
    getUsageSummary.mockImplementation(() =>
      Promise.reject(Object.assign(new Error("forbidden"), { status: 403 })),
    );
    renderPanel({ workspaceSlug: "acme" });
    await waitFor(() => expect(screen.getByText("Usage is workspace-admin only")).toBeTruthy());
  });

  it("still reports a real failure as one", async () => {
    getUsageSummary.mockImplementation(() =>
      Promise.reject(Object.assign(new Error("boom"), { status: 500 })),
    );
    renderPanel({ workspaceSlug: "acme" });
    await waitFor(() => expect(screen.getByText("Couldn't load usage")).toBeTruthy());
  });
});

describe("UsagePanel — the ecosystem billing row", () => {
  it("renders it in its own Platform section when the server sends one", async () => {
    getUsageSummary.mockResolvedValue([
      row({ kind: "self", principalId: "u1", label: "Me", requests: 2 }),
      row({
        kind: "ecosystem",
        scope: "ecosystem",
        principalId: "eco",
        label: "hub",
        tokens: 50_000,
        limits: { ...UNCAPPED, quotaTokens: 1_000_000 },
      }),
    ]);
    renderPanel();

    await waitFor(() => expect(screen.getByText("Platform")).toBeTruthy());
    expect(screen.getByText("50,000 / 1,000,000")).toBeTruthy();
    // It spans every tenant in the realm, so it is never part of the caller's own total.
    expect(screen.queryByText("50,002")).toBeNull();
  });
});
