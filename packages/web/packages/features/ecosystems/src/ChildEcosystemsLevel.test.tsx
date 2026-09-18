// @vitest-environment jsdom
//
// THE `busy` FLAG ON THE CHILD ECOSYSTEMS RAIL. `ChildEcosystemsLevel` (an internal, non-exported
// component of EcosystemsFeature.tsx) hands `busy={childrenQuery.isFetching}` to `useStackLevel`,
// which is the one signal `levelsKey` (rail-host.tsx) watches to decide the merged rail should
// re-register and paint the spinner — see rail-host-busy.test.tsx for that mechanism in isolation.
// Nothing checks the OTHER half here: that the ecosystems feature actually threads the real
// react-query `isFetching` bit into that prop, rather than a constant or a stale snapshot. A typo
// that hands `busy` a value which happens to be falsy at every render this suite already covers
// (e.g. `busy={false}`, or `busy={!!children}` — truthy exactly when rows exist, which is also
// exactly when the read is done) would slip past every other test in this package and still
// typecheck, still render, still pass a screenshot. Only holding the query open and watching the
// spinner track it proves the wiring.
//
// Mocking style matches EcosystemSettingsPane.test.tsx: only `@agentic-toolkit/data/ecosystems`'s
// TRANSPORT is replaced (`importOriginal` spread), so `Ecosystem`, `toEcosystem`, and every other
// mapper/type stay real — the fixtures below are genuine `Ecosystem` values, not stand-ins for the
// shape the feature happens to read today.
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup, within, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { Ecosystem } from "@agentic-toolkit/data/ecosystems";

// EcosystemsFeature, ChildEcosystemsLevel, and ResourceExplorer all call next/navigation's
// useRouter() directly (never through a router prop), so the App Router context that provides it
// has to be stubbed for a bare vitest/jsdom render. `prefetch` is here because ResourceExplorer
// warms the row's route on hover/focus dwell — it calls it as `router.prefetch?.()` precisely so a
// shim may omit it, so this is the stub matching the real router rather than a load-bearing one.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

// Only the transport is replaced; the mappers and types stay real (same idiom as
// EcosystemSettingsPane.test.tsx's `vi.mock("./EcosystemForm", ...)` neighbour). `list` seeds the
// scoped ecosystem the feature opens on; `listChildren` is the one this test holds open by hand.
// `useWorkspaceDefaultEcosystemId` is stubbed rather than left real: it reaches `ecosystemsApi`
// through the MODULE'S OWN relative import (`./ecosystems`), a path this mock never intercepts
// (vi.mock only rewrites the "@agentic-toolkit/data/ecosystems" specifier), so left alone it would
// hit the genuine, un-mocked transport. This feature never opens the create dialog the resolved
// value feeds, so a fixed "no infrastructure ecosystem, already settled" answer is enough to keep
// that corner inert.
vi.mock("@agentic-toolkit/data/ecosystems", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/ecosystems")>()),
  ecosystemsApi: {
    list: vi.fn(),
    listChildren: vi.fn(),
    get: vi.fn(),
    ecosystemIdForSlug: vi.fn(),
    listForWorkspace: vi.fn(),
    delete: vi.fn(),
    update: vi.fn(),
  },
  useWorkspaceDefaultEcosystemId: vi.fn(() => ({
    ecosystemId: undefined,
    canManage: true,
    isPending: false,
    isError: false,
  })),
}));

import { EcosystemsFeature, IN_PACKAGE_TOPICS } from "./EcosystemsFeature";
import { ecosystemsApi } from "@agentic-toolkit/data/ecosystems";

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

// The scoped ecosystem the feature opens on. Must appear in `list()`'s answer — the feature treats
// a scoped id ABSENT from the list as a hidden default and takes a side quest to fetch it directly
// (`scopedMissing`/`scopedEcoQuery`), which this test has no need to exercise.
const ACME: Ecosystem = {
  id: "ecosystem.acme",
  identifier: "ecosystem.acme",
  slug: "acme",
  name: "Acme",
  description: "",
  region: "",
  domain: "",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

// The one child ecosystem the held-open read eventually lands, so the test also confirms the rail
// repaints with real rows once the busy read settles, not just that the spinner goes away.
const WIDGETS: Ecosystem = {
  id: "ecosystem.acme.widgets",
  identifier: "ecosystem.acme.widgets",
  slug: "widgets",
  name: "Widgets",
  description: "",
  region: "",
  domain: "",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

describe("the Child Ecosystems rail's busy flag tracks the children query's isFetching", () => {
  it("shows the rail spinner while listChildren is in flight, then clears it once the read lands", async () => {
    vi.mocked(ecosystemsApi.list).mockResolvedValue([ACME]);
    // Held open by hand: `land` is captured from inside the executor, so the test decides exactly
    // when the read settles instead of racing a pre-resolved promise against the first paint.
    let land: (rows: Ecosystem[]) => void = () => {
      throw new Error("listChildren was never called");
    };
    vi.mocked(ecosystemsApi.listChildren).mockImplementation(
      () =>
        new Promise<Ecosystem[]>((resolve) => {
          land = resolve;
        }),
    );

    // A FRESH client per test: EcosystemsFeature reads react-query through CONTEXT (raw
    // `useQuery`, unlike `useResourceList`'s module-scope client), so a shared client would leak
    // this test's in-flight `listChildren` query into whatever test runs next.
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <EcosystemsFeature
          basePath="/ecosystems"
          topics={IN_PACKAGE_TOPICS}
          activeEcoId={ACME.id}
          activeTopic="child-ecosystems"
        />
      </QueryClientProvider>,
    );

    // With no ancestor RailHostContext, ResourceExplorer's RailHostBoundary stands up its own
    // StandaloneRailHost — so BOTH the promoted topics rail (rows: Features / Settings / Child
    // Ecosystems, scoped to entity "Acme") and the Child-Ecosystems-list rail ChildEcosystemsLevel
    // publishes land on screen as sibling `<aside aria-label="Topic list">` columns. The topics rail's own
    // ROW text is "Child Ecosystems" too (it names the topic), so text alone can't tell the two
    // apart — but only the topics rail carries a "Settings" row, so that's the stable discriminator
    // used below, in both the busy and the settled state.
    await screen.findAllByRole("complementary", { name: "Topic list" });
    const childRail = (): HTMLElement => {
      const rails = screen.getAllByRole("complementary", { name: "Topic list" });
      const found = rails.find((r) => !within(r).queryByText("Settings"));
      if (!found) throw new Error("the Child Ecosystems rail is not on screen");
      return found;
    };

    // BUSY: the read is still the held-open promise, so the rail's title-bar spinner is up and its
    // list is still in the "nothing has ever landed" empty state.
    // The read is announced by ONE always-mounted live region whose TEXT changes, so the
    // assertion is on what that region CONTAINS: a region inserted at the same instant it fills
    // announces nothing, since assistive tech reads a live region's mutations and not its arrival.
    // `role="status"` also takes its name from the author and never from its content, so there is
    // no accessible name to match on either.
    expect(within(childRail()).getByRole("status").textContent).toBe("Loading");
    expect(within(childRail()).getByText("Loading…")).not.toBeNull();

    land([WIDGETS]);

    // SETTLED: the spinner clears and the real row paints, in the same rail.
    await waitFor(() => {
      expect(within(childRail()).getByRole("status").textContent).toBe("");
    });
    expect(within(childRail()).getByText("Widgets")).not.toBeNull();
  });
});
