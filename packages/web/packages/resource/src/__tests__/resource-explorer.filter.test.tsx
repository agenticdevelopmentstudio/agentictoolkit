/// <reference types="@testing-library/jest-dom/vitest" />
//
// The resource rail's filter: the rail's own match (`filterTopicItems`) run over a query the
// explorer holds, so the query survives a stack flip that remounts the rail. The explorer used to
// run a hand-rolled copy of that match, and a value it searched was lost the moment a list stopped
// SHOWING it (the Products rail's identifier).
//
// Most cases read the level the explorer PUBLISHES into a host — exactly what the rail is handed —
// so no layout decision (a covered rail drawing icons only, say) can hide a row from the assertion.
import type { ReactNode } from "react";
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, cleanup, act, within, fireEvent } from "@testing-library/react";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { ResourceExplorer, type ResourceRailConfig, type ResourceTopic } from "../resource-explorer";
import { RailHostContext, type RailHostRegistry, type RegisteredLevels } from "../rail-host";

// ResourceExplorer calls next/navigation's useRouter unconditionally; its routing isn't under test
// here — mirrors resource-explorer.toolbar.test.tsx.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

// This package's vitest config has no global afterEach, so register cleanup explicitly.
afterEach(cleanup);

interface Row {
  id: string;
  label: string;
  identifier: string;
}

const NO_TOPICS: ResourceTopic[] = [];
const ROWS: Row[] = [
  { id: "a", label: "Alpha", identifier: "com.example.zeta" },
  { id: "b", label: "Beta", identifier: "com.example.omega" },
];

function explorer({
  items,
  rail,
  activeId,
}: {
  items: Row[] | null;
  rail?: Partial<ResourceRailConfig<Row>>;
  activeId?: string;
}) {
  return (
    <ResourceExplorer<Row>
      activeId={activeId}
      basePath="/home"
      items={items}
      getId={(r) => r.id}
      getLabel={(r) => r.label}
      nameSuffix="Project"
      topics={NO_TOPICS}
      rail={{ title: "All", help: "help", emptyLabel: "None yet.", ...rail }}
    />
  );
}

/** A host that keeps the last levels the explorer registered — level 0 is the resource rail. */
function capturingHost() {
  let latest: RegisteredLevels | null = null;
  const host: RailHostRegistry = {
    registerLevels: (_id, entry) => {
      latest = entry;
    },
    unregisterLevels: vi.fn(),
    registerExitGuard: vi.fn(),
    popStack: vi.fn(),
    reportMissing: vi.fn(),
    reportBusy: vi.fn(),
    toolbarSlot: null,
  };
  function Host({ children }: { children: ReactNode }) {
    return <RailHostContext.Provider value={host}>{children}</RailHostContext.Provider>;
  }
  const resourceLevel = (): TopicLevel => {
    const level = latest?.levels[0];
    if (!level) throw new Error("the explorer registered no resource level");
    return level;
  };
  return {
    Host,
    resourceLevel,
    rows: () => resourceLevel().items.map((i) => i.label),
    /** Type into the rail's search the way the rail does: through the level's own callback. */
    query: (q: string) => act(() => resourceLevel().search?.onQueryChange?.(q)),
  };
}

describe("ResourceExplorer's rail filter", () => {
  it("matches the label and the sublabel, trimmed and case-folded", () => {
    const { Host, rows, query } = capturingHost();
    render(<Host>{explorer({ items: ROWS, rail: { getSublabel: (r) => r.identifier } })}</Host>);
    query("  OMEGA ");
    expect(rows()).toEqual(["Beta"]);
    query("alp");
    expect(rows()).toEqual(["Alpha"]);
  });

  // A level whose `selectedId` names no row it renders is a selection the pointer cannot reach,
  // and the breadcrumb resolves it by lookup — it would print the raw id.
  it("never drops the OPEN entity, and keeps the list's order", () => {
    const { Host, rows, query } = capturingHost();
    render(<Host>{explorer({ items: ROWS, activeId: "a" })}</Host>);
    query("bet");
    expect(rows()).toEqual(["Alpha", "Beta"]);
  });

  // The Products rail keeps its rows to one line, so the identifier is not a sublabel — and while
  // the sublabel was the only searchable extra, dropping the line dropped identifier search too.
  it("finds a row by its search-only text without putting that text on the row", () => {
    const { Host, resourceLevel, rows, query } = capturingHost();
    render(<Host>{explorer({ items: ROWS, rail: { getSearchText: (r) => r.identifier } })}</Host>);
    query("ZETA");
    expect(rows()).toEqual(["Alpha"]);
    expect(resourceLevel().items.map((i) => i.sublabel)).toEqual([undefined]);
    // The rail's own label match still holds beside it, and the list's order survives the union.
    query("bet");
    expect(rows()).toEqual(["Beta"]);
    query("com.example");
    expect(rows()).toEqual(["Alpha", "Beta"]);
  });

  // Once the loaded list is empty the magnifier goes with the last row, so nothing is left that
  // could clear the query — and the rows that arrive next must not come back pre-filtered by it.
  it("drops a stale query once the loaded list is empty", () => {
    const { Host, resourceLevel, rows, query } = capturingHost();
    const { rerender } = render(<Host>{explorer({ items: ROWS })}</Host>);
    query("zzz");
    expect(rows()).toEqual([]);

    rerender(<Host>{explorer({ items: [] })}</Host>);
    expect(resourceLevel().search).toBeUndefined();
    expect(resourceLevel().emptyLabel).toBe("None yet.");

    rerender(<Host>{explorer({ items: ROWS })}</Host>);
    expect(resourceLevel().search?.query).toBe("");
    expect(rows()).toEqual(["Alpha", "Beta"]);
  });

  // Through the real rail: a query that matches nothing is named — by the explorer, whose query is
  // controlled, since a rail names a no-match only over rows it filtered itself — and an emptied
  // list says what an empty list says, not that a search failed.
  it("reads as empty, not as a failed search, once the list empties under a query", () => {
    const { rerender } = render(explorer({ items: ROWS }));
    const toolbar = screen.getByRole("toolbar", { name: "All tools" });
    fireEvent.click(within(toolbar).getByRole("button", { name: "Filter all" }));
    fireEvent.change(screen.getByRole("searchbox", { name: "Filter all" }), {
      target: { value: "zzz" },
    });
    expect(screen.getByText("Nothing matches “zzz”.")).toBeInTheDocument();

    rerender(explorer({ items: [] }));
    expect(screen.getByText("None yet.")).toBeInTheDocument();
    expect(screen.queryByText(/matches/)).toBeNull();
  });
});
