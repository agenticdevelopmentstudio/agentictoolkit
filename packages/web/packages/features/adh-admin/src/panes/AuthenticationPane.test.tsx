// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { confirmNavigation } from "@agenticdevelopertoolkit/ui/lib/navigation-guard";

// The page's UnsavedChangesGuard mount passes onNavigate={(href) => router.push(href)} so a
// Discard after a link click stays client-side instead of falling back to
// window.location.assign — the same idiom the site's four pre-existing mounts
// (feature-flags/page.tsx, server-bags/page.tsx, usage/page.tsx, llm-providers/page.tsx) use.
// `push` is stable across renders (vi.hoisted) so the nav test can assert on the exact mock
// the page calls; the other two tests never navigate, so `push` is simply never invoked there.
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

vi.mock("../api/http", () => ({ authedJson: vi.fn(async () => ({})) }));

vi.mock("../api/auth-config", () => {
  const empty = { data: [], isLoading: false, error: null };
  const mutation = () => ({ mutateAsync: vi.fn(async () => ({})), isPending: false });
  return {
    useProviders: () => empty,
    useClients: () => empty,
    useProviderTemplates: () => empty,
    useAuthMethods: () => empty,
    useCreateClient: mutation,
    useUpdateClient: mutation,
    useDeleteClient: mutation,
    useCreateProvider: mutation,
    useUpdateProvider: mutation,
    useDeleteProvider: mutation,
    useLinkProvider: mutation,
    useUnlinkProvider: mutation,
    useUpdateAuthMethod: mutation,
  };
});

import { AuthenticationPane } from "./AuthenticationPane";

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <AuthenticationPane />
    </QueryClientProvider>,
  );
}

/** Same as {@link renderPage}, plus a sibling anchor: UnsavedChangesGuard intercepts real
 *  anchor clicks via a document-level capture listener, so a raw <a> anywhere in the
 *  document exercises the browser-level (link-click) exit path — a next/link would route
 *  through the router instead and never reach the interception path. */
function renderPageWithLink() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <AuthenticationPane />
      <a href="/elsewhere">Elsewhere</a>
    </QueryClientProvider>,
  );
}

// The admin/hub vitest configs have no global afterEach; tear each render down
// explicitly (mirrors NewFlagDialog.test.tsx) so the second test's identical
// button query doesn't match a copy left over from the first test's render.
afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("authentication page unsaved-changes guard", () => {
  it("lets a programmatic navigation through while clean", async () => {
    renderPage();
    await screen.findByRole("button", { name: /add entry point/i });
    await expect(confirmNavigation()).resolves.toBe(true);
  });

  it("raises the shared alert on a programmatic navigation while dirty", async () => {
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: /add entry point/i }));

    let settled: boolean | undefined;
    void confirmNavigation().then((ok) => {
      settled = ok;
    });

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy();
      expect(screen.getByRole("button", { name: "Stay" })).toBeTruthy();
    });
    expect(settled).toBeUndefined();
  });

  it("navigates with the app router (not a full reload) when Discard follows a link click", async () => {
    // jsdom's Location.assign is non-configurable, so it can't be vi.spyOn'd in place (mirrors
    // hub's login.test.tsx cross-site-return test) — swap the whole `location` for a stub built
    // from the real one's current values, restored after.
    const realLocation = window.location;
    const { href, origin, pathname, search } = realLocation;
    const assign = vi.fn();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: { href, origin, pathname, search, assign },
    });

    try {
      renderPageWithLink();
      fireEvent.click(await screen.findByRole("button", { name: /add entry point/i }));

      fireEvent.click(screen.getByText("Elsewhere"));
      await waitFor(() => expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy());

      fireEvent.click(screen.getByRole("button", { name: "Discard" }));

      await waitFor(() => expect(push).toHaveBeenCalledWith("/elsewhere"));
      expect(assign).not.toHaveBeenCalled();
    } finally {
      Object.defineProperty(window, "location", { configurable: true, value: realLocation });
    }
  });
});
