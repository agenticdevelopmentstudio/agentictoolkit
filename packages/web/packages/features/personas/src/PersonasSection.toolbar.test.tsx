// @vitest-environment jsdom
//
// Pins where PersonasSection's "New Persona" lives: the persona list's own toolbar `+`, beside its
// search. It was published into the page-wide home bar until that strip was removed as clunky
// (Mike, 2026-09-24). EVERY query is scoped `within` the toolbar, so a create drawn anywhere else
// on the page cannot satisfy it.
//
// The component is DUAL-MODE, and both modes are covered here: under a rail host it publishes its
// level and renders only the leaf; with no host above it renders its own HierarchicalDetailView.
// The two sites that mount it reach the first branch — `PersonasFeature` wraps it in
// `RailHostBoundary`, which self-hosts a `StandaloneRailHost` when nothing above it does — while
// an embedded launcher takes the second. A `+` on only one branch is a missing create button on
// whichever set of callers takes the other, and nothing else in the suite would say so.
//
// Mocks are the module boundaries only: the personas data client, auth's error reporter, and the
// two heavy children this file is not about (`PersonaEditor`, whose module pulls in the CRUD
// catalog, and `useUserServices`, which would otherwise spend a real services read on every mount).
// The rail itself runs for real.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";

vi.mock("@agentic-toolkit/auth", () => ({
  reportUnexpectedAuthError: vi.fn(),
}));

vi.mock("@agentic-toolkit/data/personas", () => ({
  api: {
    personas: {
      list: vi.fn(),
      create: vi.fn(),
    },
  },
}));

// Not the subject, and its module resolves the CRUD table catalog at load — stub it the way
// PersonaEditor.test.tsx stubs its own leaf panels. Nothing here opens a persona anyway.
vi.mock("./PersonaEditor", () => ({
  PersonaEditor: () => <div data-testid="persona-editor" />,
}));

// The services list is a second, unrelated read (and its own suite's business). The stub keeps the
// exported cache key intact because PersonasSection's `reload` revalidates by that exact string.
vi.mock("./useUserServices", () => ({
  PERSONA_SERVICES_CACHE_KEY: "persona-services",
  useUserServices: () => ({ items: [], error: null, reload: vi.fn() }),
}));

import { RailHostBoundary } from "@agentic-toolkit/resource";
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";
import { PersonasSection } from "./PersonasSection";
import { api, type Persona } from "@agentic-toolkit/data/personas";

const listPersonas = vi.mocked(api.personas.list);

const PERSONA = {
  id: "p1",
  name: "Bob",
  slug: "bob",
  description: "A dog namer.",
  model: "",
  modelPrompt: "",
  visibility: "private",
} as unknown as Persona;

beforeEach(() => {
  vi.clearAllMocks();
  listPersonas.mockResolvedValue([PERSONA]);
});

afterEach(cleanup);

/** The page chrome the two sites put above this feature: the toolkit's own react-query provider
 *  (PersonasSection reads the toolkit's QueryClient, not a host's).
 *  `railHost` picks the branch: `true` adds the `RailHostBoundary` `PersonasFeature` supplies,
 *  which self-hosts a rail host, so the component takes its published-level branch. */
function Chrome({ children, railHost }: { children: ReactNode; railHost: boolean }) {
  return (
    <ToolkitQueryProvider>
      {railHost ? <RailHostBoundary>{children}</RailHostBoundary> : children}
    </ToolkitQueryProvider>
  );
}

/** The persona list's toolbar — the row under its title. Found by its marker, not a role, because
 *  the query is what makes every assertion below capable of failing. */
async function toolbar() {
  const el = await waitFor(() => {
    const found = document.querySelector("[data-htd-toolbar]") as HTMLElement | null;
    expect(found).not.toBeNull();
    return found!;
  });
  return within(el);
}

describe("PersonasSection puts New Persona on the list's toolbar", () => {
  // The branch the personas and personabuilder sites actually take.
  it("draws the + on the toolbar under a rail host", async () => {
    render(
      <Chrome railHost>
        <PersonasSection />
      </Chrome>,
    );

    const bar = await toolbar();
    expect(bar.getByRole("button", { name: "New Persona" })).not.toBeNull();
    expect(bar.getByRole("button", { name: "Search personas" })).not.toBeNull();
    // And ONLY there: one create affordance for the list.
    expect(screen.getAllByRole("button", { name: "New Persona" })).toHaveLength(1);
  });

  // The other branch: no host above, so PersonasSection renders its own HierarchicalDetailView.
  it("draws the + on the toolbar with no rail host above", async () => {
    render(
      <Chrome railHost={false}>
        <PersonasSection />
      </Chrome>,
    );

    const bar = await toolbar();
    expect(bar.getByRole("button", { name: "New Persona" })).not.toBeNull();
    expect(screen.getAllByRole("button", { name: "New Persona" })).toHaveLength(1);
  });

  it("opens the create modal from the toolbar's +", async () => {
    // A `+` that rendered on the toolbar but no longer reached `setNewOpen` would pass both
    // placement tests above.
    render(
      <Chrome railHost>
        <PersonasSection />
      </Chrome>,
    );

    const bar = await toolbar();
    expect(screen.queryByRole("dialog", { name: "New persona" })).toBeNull();
    fireEvent.click(bar.getByRole("button", { name: "New Persona" }));
    expect(await screen.findByRole("dialog", { name: "New persona" })).not.toBeNull();
  });

  it("keeps the + with an EMPTY persona list", async () => {
    // Unconditional: no personas is precisely when the first create matters most, so gating the
    // `+` on a loaded or non-empty list would strand a new tenant with no way to create anything.
    // Under a host this sees the level as it was REGISTERED, and no plain field of it moves when
    // the list lands (its empty label reads the same loading or loaded), so it cannot tell the two
    // apart. The no-host case below is the one that waits for the load.
    listPersonas.mockResolvedValue([]);
    render(
      <Chrome railHost>
        <PersonasSection />
      </Chrome>,
    );

    const bar = await toolbar();
    expect(bar.getByRole("button", { name: "New Persona" })).not.toBeNull();
  });

  // The toolbar is drawn before the list resolves, so an assertion that does not wait for the load
  // only ever sees the LOADING state, where a `+` gated on a loaded-but-empty list is still there.
  // With no host the section draws its own rail from the level it renders now, so the load that
  // lands is what the toolbar shows.
  it("keeps the + once an EMPTY persona list has loaded, with no rail host above", async () => {
    listPersonas.mockResolvedValue([]);
    render(
      <Chrome railHost={false}>
        <PersonasSection />
      </Chrome>,
    );

    expect(screen.getByText("Loading…")).not.toBeNull();
    await waitFor(() => expect(screen.queryByText("Loading…")).toBeNull());
    const bar = await toolbar();
    expect(bar.getByRole("button", { name: "New Persona" })).not.toBeNull();
    expect(bar.getByRole("button", { name: "Search personas" })).not.toBeNull();
  });
});
