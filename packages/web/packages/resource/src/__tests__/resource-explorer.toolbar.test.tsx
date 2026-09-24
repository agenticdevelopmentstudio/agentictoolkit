/// <reference types="@testing-library/jest-dom/vitest" />
//
// The resource rail's create and filter live on the rail's own toolbar — the row under its title
// — after the page-wide home bar they used to be published into was removed as clunky (Mike,
// 2026-09-24). Every assertion is scoped `within(toolbar)` so a control drawn anywhere else on the
// page cannot satisfy it.
import type { ReactNode } from "react";
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, cleanup, within, fireEvent } from "@testing-library/react";
import { ResourceExplorer, type ResourceTopic } from "../resource-explorer";

// ResourceExplorer calls next/navigation's useRouter unconditionally; its select/prefetch wiring
// isn't under test here — mirrors resource-explorer-standalone.test.tsx.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

afterEach(cleanup);

interface Row {
  id: string;
  label: string;
}

const NO_TOPICS: ResourceTopic[] = [];

function renderExplorer({
  items,
  newLabel,
  promoteTopics = false,
  renderNewControl,
}: {
  items: Row[] | null;
  newLabel?: string;
  promoteTopics?: boolean;
  renderNewControl?: (onNew: () => void) => ReactNode;
}) {
  return render(
    <ResourceExplorer<Row>
      promoteTopics={promoteTopics}
      basePath="/home"
      items={items}
      getId={(i) => i.id}
      getLabel={(i) => i.label}
      nameSuffix="Project"
      topics={NO_TOPICS}
      newLabel={newLabel}
      renderNewControl={renderNewControl}
      rail={{ title: "All", help: "help", emptyLabel: "None yet." }}
    />,
  );
}

const toolbar = () => document.querySelector("[data-htd-toolbar]") as HTMLElement | null;

describe("ResourceExplorer's rail toolbar", () => {
  it("carries the + and the search icon once there are rows", () => {
    renderExplorer({ newLabel: "New Project…", items: [{ id: "a", label: "Alpha" }] });
    const bar = toolbar()!;
    // `newButtonLabel` strips the trailing ellipsis — an exact-string query pins that too.
    expect(within(bar).getByRole("button", { name: "New Project" })).toBeInTheDocument();
    expect(within(bar).getByRole("button", { name: "Filter all" })).toBeInTheDocument();
  });

  // An empty list is precisely when a first create matters most — a brand-new tenant lands on
  // `/home` with nothing — so the `+` is gated on `canCreate`, never on there being rows. The
  // search is: there is nothing to narrow yet.
  it("keeps the + on a loaded but EMPTY list, with no search", () => {
    renderExplorer({ items: [], newLabel: "New Project…" });
    const bar = toolbar()!;
    expect(within(bar).getByRole("button", { name: "New Project" })).toBeInTheDocument();
    expect(within(bar).queryByRole("button", { name: "Filter all" })).toBeNull();
  });

  it("keeps the + while the list is still LOADING, with no search", () => {
    renderExplorer({ items: null, newLabel: "New Project…" });
    const bar = toolbar()!;
    expect(within(bar).getByRole("button", { name: "New Project" })).toBeInTheDocument();
    expect(within(bar).queryByRole("button", { name: "Filter all" })).toBeNull();
  });

  it("draws no toolbar with nothing to create and nothing to filter", () => {
    renderExplorer({ items: [] });
    expect(toolbar()).toBeNull();
  });

  // promoteTopics has no resource rail at all, so no `+` anywhere — EcosystemsFeature's own
  // promoteTopics mount passes a `newLabel` with no `renderDialog`, and a button there would open
  // nothing.
  it("offers no create in promoteTopics mode, even with items and a newLabel", () => {
    renderExplorer({ promoteTopics: true, newLabel: "New Ecosystem…", items: [{ id: "a", label: "Alpha" }] });
    expect(screen.queryByRole("button", { name: "New Ecosystem" })).toBeNull();
  });

  it("filters the rail's rows from the pop-over search", () => {
    renderExplorer({
      items: [
        { id: "a", label: "Alpha" },
        { id: "b", label: "Beta" },
      ],
    });
    fireEvent.click(within(toolbar()!).getByRole("button", { name: "Filter all" }));
    fireEvent.change(screen.getByRole("searchbox", { name: "Filter all" }), { target: { value: "Alph" } });
    expect(screen.getByText("Alpha")).toBeInTheDocument();
    expect(screen.queryByText("Beta")).toBeNull();
  });
});

// `renderNewControl` is a host's own SHAPE for the create trigger — the registries feature puts
// the verb behind a gear. It renders among the rail's tools IN PLACE of the `+`, never beside it.
describe("ResourceExplorer's renderNewControl", () => {
  it("replaces the + on the toolbar, and still opens the dialog", () => {
    let opened = 0;
    renderExplorer({
      items: [{ id: "a", label: "Alpha" }],
      newLabel: "New Project…",
      renderNewControl: (onNew) => (
        <button
          type="button"
          onClick={() => {
            opened += 1;
            onNew();
          }}
        >
          Registry actions
        </button>
      ),
    });
    const bar = toolbar()!;
    const gear = within(bar).getByRole("button", { name: "Registry actions" });
    expect(screen.queryByRole("button", { name: "New Project" })).toBeNull();
    fireEvent.click(gear);
    expect(opened).toBe(1);
  });

  it("is gated by canCreate: none in promoteTopics mode, and none without a newLabel", () => {
    renderExplorer({
      promoteTopics: true,
      newLabel: "New Ecosystem…",
      items: [{ id: "a", label: "Alpha" }],
      renderNewControl: () => <button type="button">Registry actions</button>,
    });
    expect(screen.queryByRole("button", { name: "Registry actions" })).toBeNull();
    cleanup();

    renderExplorer({
      items: [{ id: "a", label: "Alpha" }],
      renderNewControl: () => <button type="button">Registry actions</button>,
    });
    expect(screen.queryByRole("button", { name: "Registry actions" })).toBeNull();
  });
});
