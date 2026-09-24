// @vitest-environment jsdom
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { render, screen, waitFor, cleanup, fireEvent } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ArchivedWorkspace } from "../api/archived-workspaces";

// Stub only the transport boundary: the fetcher `useArchivedWorkspaces` calls under the hood
// (`authedJson`, imported straight from `@agentic-toolkit/auth/client` — hub's `@/api/http`
// re-export shim isn't part of this package) and `organizationsApi.restore`. The hook itself
// keeps its real `useQuery`, run against a real `QueryClientProvider` below — this is what
// proves the panel's states (error → loading → empty → table) against a REAL query
// lifecycle, not a hand-rolled stand-in for react-query.
const { authedJson } = vi.hoisted(() => ({ authedJson: vi.fn() }));
vi.mock("@agentic-toolkit/auth/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/auth/client")>()),
  authedJson,
}));

const { restore } = vi.hoisted(() => ({ restore: vi.fn() }));
vi.mock("../api/organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/organizations")>();
  return { ...actual, organizationsApi: { ...actual.organizationsApi, restore } };
});

import { ArchivedPanel } from "./ArchivedPanel";

// This package's vitest config has no global afterEach; tear each render down explicitly.
afterEach(cleanup);
// Braces are load-bearing: vitest treats a value RETURNED from a hook as that hook's teardown,
// and `mockReset()` returns the mock — so the concise-body form would CALL the mock after every
// test, rejecting into nobody's hands on the error cases.
beforeEach(() => {
  authedJson.mockReset();
  restore.mockReset();
});

function row(over: Partial<ArchivedWorkspace> = {}): ArchivedWorkspace {
  return {
    id: over.id ?? "org_1",
    slug: over.slug ?? "acme",
    name: over.name ?? "Acme Inc",
    type: "organization",
    archivedAt: over.archivedAt ?? "2026-07-15 12:34:56.789012",
    handleAvailable: over.handleAvailable ?? true,
    canRestore: over.canRestore ?? true,
  };
}

function renderPanel() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ArchivedPanel />
    </QueryClientProvider>,
  );
}

/** Tick a row's checkbox — the bar's verbs act on the selection, never on a row's own button. */
function tick(name: string) {
  fireEvent.click(screen.getByRole("checkbox", { name: `Select ${name}` }));
}

function restoreButton(): HTMLButtonElement {
  return screen.getByRole("button", { name: /^(Restore|Restoring…)$/ }) as HTMLButtonElement;
}

describe("ArchivedPanel", () => {
  it("shows the empty state when nothing is archived", async () => {
    authedJson.mockResolvedValue([]);
    renderPanel();
    await waitFor(() => expect(screen.getByText(/Nothing archived\./)).toBeTruthy());
  });

  it("reports a failed load as a failure, never as an empty list", async () => {
    authedJson.mockRejectedValue(new Error("boom"));
    renderPanel();
    await waitFor(() =>
      expect(screen.getByText("Couldn't load your archived items")).toBeTruthy(),
    );
    expect(screen.queryByText(/Nothing archived\./)).toBeNull();
  });

  it("renders a row's name, handle, and the archived date sliced to YYYY-MM-DD", async () => {
    authedJson.mockResolvedValue([
      row({ name: "Acme Inc", slug: "acme", archivedAt: "2026-07-15 12:34:56.789012" }),
    ]);
    renderPanel();

    await waitFor(() => expect(screen.getByText("Acme Inc")).toBeTruthy());
    expect(screen.getByText("org.acme")).toBeTruthy();
    expect(screen.getByText("2026-07-15")).toBeTruthy();
  });

  it("keeps the bar's Restore disabled until a row is ticked", async () => {
    authedJson.mockResolvedValue([row({ name: "Acme Inc" })]);
    renderPanel();
    await screen.findByText("Acme Inc");
    expect(restoreButton().disabled).toBe(true);
    tick("Acme Inc");
    expect(restoreButton().disabled).toBe(false);
  });

  it("restores by the row's id, never its slug — a slug here 404s for every archived org", async () => {
    authedJson.mockResolvedValue([row({ id: "org_123", slug: "acme", name: "Acme Inc" })]);
    restore.mockResolvedValue(row({ id: "org_123" }));
    renderPanel();

    await screen.findByText("Acme Inc");
    tick("Acme Inc");
    fireEvent.click(restoreButton());

    await waitFor(() => expect(restore).toHaveBeenCalledWith("org_123"));
    expect(restore).not.toHaveBeenCalledWith("acme");
  });

  it("restores every ticked row in one press", async () => {
    authedJson.mockResolvedValue([
      row({ id: "org_1", slug: "acme", name: "Acme Inc" }),
      row({ id: "org_2", slug: "globex", name: "Globex" }),
    ]);
    restore.mockResolvedValue(row({}));
    renderPanel();

    await screen.findByText("Globex");
    tick("Acme Inc");
    tick("Globex");
    fireEvent.click(restoreButton());

    await waitFor(() => expect(restore).toHaveBeenCalledTimes(2));
    expect(restore).toHaveBeenCalledWith("org_1");
    expect(restore).toHaveBeenCalledWith("org_2");
  });

  it("keeps Restore disabled and shows visible 'Handle taken' text when the handle isn't available", async () => {
    authedJson.mockResolvedValue([row({ name: "Acme Inc", handleAvailable: false })]);
    renderPanel();

    await screen.findByText("Acme Inc");
    tick("Acme Inc");
    expect(restoreButton().disabled).toBe(true);
    expect(screen.getByText("Handle taken")).toBeTruthy();
  });

  it("keeps Restore disabled, shows visible 'Admins only' text, and never calls restore, when canRestore is false", async () => {
    authedJson.mockResolvedValue([row({ name: "Acme Inc", canRestore: false })]);
    renderPanel();

    await screen.findByText("Acme Inc");
    tick("Acme Inc");
    const button = restoreButton();
    expect(button.disabled).toBe(true);
    expect(screen.getByText("Admins only")).toBeTruthy();

    fireEvent.click(button);
    expect(restore).not.toHaveBeenCalled();
  });

  it("skips a ticked row that can't come back and restores the ones that can", async () => {
    authedJson.mockResolvedValue([
      row({ id: "org_1", name: "Acme Inc" }),
      row({ id: "org_2", slug: "globex", name: "Globex", handleAvailable: false }),
    ]);
    restore.mockResolvedValue(row({}));
    renderPanel();

    await screen.findByText("Globex");
    tick("Acme Inc");
    tick("Globex");
    fireEvent.click(restoreButton());

    await waitFor(() => expect(restore).toHaveBeenCalledWith("org_1"));
    expect(restore).not.toHaveBeenCalledWith("org_2");
  });

  it("surfaces a rejected restore's message and leaves the row restorable", async () => {
    authedJson.mockResolvedValue([row({ id: "org_1", name: "Acme Inc" })]);
    restore.mockRejectedValue(
      new Error("That organization's handle has been taken, so it can't be restored."),
    );
    renderPanel();

    await screen.findByText("Acme Inc");
    tick("Acme Inc");
    fireEvent.click(restoreButton());

    await waitFor(() =>
      expect(
        screen.getByText("That organization's handle has been taken, so it can't be restored."),
      ).toBeTruthy(),
    );
    // The `finally` cleared busy state and the failed row stayed ticked — a second press retries
    // it, rather than the button sitting stuck mid-request.
    await waitFor(() => expect(restoreButton().disabled).toBe(false));
    expect(restoreButton().textContent).toBe("Restore");
  });
});
