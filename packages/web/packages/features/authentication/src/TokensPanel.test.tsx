// @vitest-environment jsdom
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import { tokensApi, type ApiToken } from "@agentic-toolkit/data/security";
import { TokensPanel } from "./TokensPanel";

// The panel calls useQuery/useMutation on `tokensApi` directly, so only the network is stubbed.
vi.mock("@agentic-toolkit/data/security", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@agentic-toolkit/data/security")>();
  return {
    ...actual,
    tokensApi: {
      list: vi.fn(),
      scopes: vi.fn(),
      mint: vi.fn(),
      revoke: vi.fn(),
    },
  };
});

const api = vi.mocked(tokensApi);

function token(id: string, name: string): ApiToken {
  return {
    id,
    name,
    prefix: `adh_${id}`,
    createdAt: "2026-01-01T00:00:00Z",
    expiresAt: null,
    lastUsedAt: null,
    scope: null,
  };
}

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderPanel(rows: ApiToken[]) {
  api.list.mockResolvedValue(rows);
  api.scopes.mockResolvedValue(["/content/markdown"]);
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={qc}>
      <TokensPanel />
    </QueryClientProvider>,
  );
}

describe("TokensPanel", () => {
  it("revokes every ticked token through the bar, after a confirm naming them", async () => {
    api.revoke.mockResolvedValue(undefined);
    renderPanel([token("a", "research-agent"), token("b", "ci-bot"), token("c", "keep-me")]);

    const revoke = await screen.findByRole("button", { name: "Revoke" });
    // Revoke is a selection verb: nothing ticked, nothing to revoke.
    expect((revoke as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(await screen.findByRole("checkbox", { name: "Select research-agent" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "Select ci-bot" }));
    fireEvent.click(screen.getByRole("button", { name: "Revoke" }));

    expect(await screen.findByText("Revoke 2 tokens?")).toBeTruthy();
    expect(screen.getByText(/research-agent, ci-bot/)).toBeTruthy();
    // No revoke has happened yet — the bar button only asks.
    expect(api.revoke).not.toHaveBeenCalled();

    // Two "Revoke" buttons now: the bar's and the confirm's, which is drawn last (portalled).
    const confirms = screen.getAllByRole("button", { name: "Revoke" });
    fireEvent.click(confirms[confirms.length - 1]);
    await waitFor(() => expect(api.revoke).toHaveBeenCalledTimes(2));
    expect(api.revoke.mock.calls.map((c) => c[0]).sort()).toEqual(["a", "b"]);
  });

  it("creates a token from the New dialog and reveals the secret once", async () => {
    api.mint.mockResolvedValue({ ...token("n", "new-agent"), token: "adh_secret_value" });
    renderPanel([]);

    fireEvent.click(await screen.findByRole("button", { name: "New token" }));
    const nameBox = await screen.findByPlaceholderText("e.g. research-agent");
    fireEvent.change(nameBox, { target: { value: "new-agent" } });

    const create = await screen.findByRole("button", { name: "Create token" });
    await waitFor(() => expect((create as HTMLButtonElement).disabled).toBe(false));
    fireEvent.click(create);

    // react-query hands a mutationFn a second (context) argument; only the body is ours.
    await waitFor(() => expect(api.mint).toHaveBeenCalledTimes(1));
    expect(api.mint.mock.calls[0][0]).toEqual({ name: "new-agent", scope: undefined });
    expect(await screen.findByText("adh_secret_value")).toBeTruthy();
  });
});
