import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

vi.mock("@agentic-toolkit/auth", async (orig) => ({
  ...(await orig<Record<string, unknown>>()),
  useAuth: () => ({ user: { email: "mike@example.com" }, isAuthenticated: true }),
}));

// SecurityWorkspace queries MFA status via useQuery, which throws "No QueryClient set" without a
// real QueryClientProvider ancestor. Stub the transport boundary the account-security calls go
// through (`authedJson` / `authedRequest`, imported straight from `@agentic-toolkit/auth/client`)
// and wrap in a real `QueryClientProvider`, the same seam `ArchivedPanel.test.tsx` in this
// package already established for the identical reason.
const { authedJson, authedRequest } = vi.hoisted(() => ({
  authedJson: vi.fn(),
  authedRequest: vi.fn(),
}));
vi.mock("@agentic-toolkit/auth/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/auth/client")>()),
  authedJson,
  authedRequest,
}));

import { SecurityWorkspace } from "./SecurityWorkspace";

const STATUS = {
  sms: false,
  totp: false,
  webauthn: true,
  totpPending: false,
  recoveryRemaining: 0,
  preferredMethod: null,
};

const CREDS = [
  { id: "c1", name: "MacBook", kind: "passkey", createdAt: "2026-01-02T00:00:00Z", lastUsedAt: null },
  { id: "c2", name: "YubiKey", kind: "security_key", createdAt: "2026-02-03T00:00:00Z", lastUsedAt: null },
];

function routeJson(creds = CREDS) {
  authedJson.mockImplementation((path: string) => {
    if (path === "/api/account/mfa") return Promise.resolve(STATUS);
    if (path === "/api/account/mfa/webauthn") return Promise.resolve({ items: creds });
    return Promise.reject(new Error(`unexpected ${path}`));
  });
}

function renderWorkspace() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <SecurityWorkspace />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  authedJson.mockReset();
  authedRequest.mockReset();
  authedRequest.mockResolvedValue(new Response(null, { status: 204 }));
});
afterEach(cleanup);

describe("SecurityWorkspace", () => {
  it("draws its sections under the registry's title — no page heading or API button of its own", async () => {
    routeJson();
    renderWorkspace();
    expect(
      await screen.findByRole("heading", { name: "Two-factor authentication" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Passkeys & security keys" })).toBeInTheDocument();
    // The topic title "Security" is the registry's FeatureTitle; a second one here duplicated it.
    expect(screen.queryByRole("heading", { name: /^security$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /api/i })).toBeNull();
  });

  it("lists passkeys in a table with Add and Remove on the bar, not per row", async () => {
    routeJson();
    renderWorkspace();
    expect(await screen.findByText("MacBook")).toBeInTheDocument();
    expect(screen.getByText("YubiKey")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Add passkey" })).toBeInTheDocument();
    // One Remove, on the bar, disabled until a row is ticked.
    const remove = screen.getAllByRole("button", { name: "Remove" });
    expect(remove).toHaveLength(1);
    expect(remove[0]).toBeDisabled();
  });

  it("removes every ticked credential after confirming", async () => {
    routeJson();
    renderWorkspace();
    await screen.findByText("MacBook");
    fireEvent.click(screen.getByRole("checkbox", { name: "Select MacBook" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "Select YubiKey" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove" }));

    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText(/MacBook, YubiKey/)).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(authedRequest).toHaveBeenCalledTimes(2));
    expect(authedRequest).toHaveBeenCalledWith("/api/account/mfa/webauthn/c1", { method: "DELETE" });
    expect(authedRequest).toHaveBeenCalledWith("/api/account/mfa/webauthn/c2", { method: "DELETE" });
  });

  it("opens the register dialog from the bar's Add", async () => {
    routeJson([]);
    renderWorkspace();
    expect(
      await screen.findByText(/No passkeys or security keys yet/),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add passkey" }));
    expect(await screen.findByLabelText("Device name")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Add security key" })).toBeInTheDocument();
  });
});
