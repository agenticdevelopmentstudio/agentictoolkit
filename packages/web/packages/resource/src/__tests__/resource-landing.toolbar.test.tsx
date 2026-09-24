/// <reference types="@testing-library/jest-dom/vitest" />
//
// The Ecosystems card landing's toolbar — its "New …" button, filter field, and Cards/List toggle
// — renders in the landing's own pane: filters left, the primary action right. It was published
// into the page-wide home bar until that strip was removed as clunky (Mike, 2026-09-24); a landing
// is a WIDE pane, so its field has room to sit open where a narrow rail's could not.
import { describe, it, expect, afterEach, beforeEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { ResourceLanding } from "../resource-landing";

afterEach(cleanup);
// `chooseView` persists the chosen view mode to `localStorage` keyed by `basePath`
// (`ftd-storage.ts`), and every test in this file shares the same basePath. Without clearing it,
// the last test's click on "View as list" would leak into whichever test runs after it and break
// the assumption that "cards" is the default view.
beforeEach(() => localStorage.clear());

interface Row {
  id: string;
  label: string;
}

function renderLanding({
  items,
  onNew,
  newLabel,
}: {
  items: Row[] | null;
  onNew?: () => void;
  newLabel?: string;
}) {
  return render(
      <ResourceLanding<Row>
        items={items}
        title="Child Ecosystems"
        help="help"
        emptyLabel="No ecosystems yet."
        basePath="/home/ecosystems"
        getId={(i) => i.id}
        getLabel={(i) => i.label}
        getSublabel={() => "sub"}
        cardHref={(i) => `/ecosystems/${i.id}`}
        renderMeta={() => null}
        onNew={onNew}
        newLabel={newLabel}
      />,
  );
}

describe("ResourceLanding's toolbar", () => {
  it("renders its New button, filter, and view toggle", async () => {
    renderLanding({
      onNew: () => {},
      newLabel: "New Ecosystem",
      items: [{ id: "a", label: "Alpha" }],
    });
    expect(await screen.findByRole("button", { name: /New Ecosystem/ })).toBeInTheDocument();
    expect(screen.getByRole("searchbox")).toBeInTheDocument();
    expect(screen.getByLabelText("Filter")).toBeInTheDocument();
    expect(screen.getByLabelText("View as")).toBeInTheDocument();
  });

  it("puts the search and the toggle left of the New button", async () => {
    renderLanding({
      onNew: () => {},
      newLabel: "New Ecosystem",
      items: [{ id: "a", label: "Alpha" }],
    });
    const filter = await screen.findByLabelText("Filter");
    const add = screen.getByRole("button", { name: /New Ecosystem/ });
    // MASKED, not `toBe`: `compareDocumentPosition` returns a bitmask, and a strict compare
    // against `DOCUMENT_POSITION_FOLLOWING` holds only while neither node contains the other.
    // The day the toolbar nests one side inside the other, `toBe` would fail reporting "order
    // wrong" for what is actually a containment change.
    expect(
      filter.compareDocumentPosition(add) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("omits the filter and toggle when there are no items yet", async () => {
    renderLanding({ onNew: () => {}, newLabel: "New Ecosystem", items: [] });
    expect(await screen.findByRole("button", { name: /New Ecosystem/ })).toBeInTheDocument();
    expect(screen.queryByRole("searchbox")).toBeNull();
  });

  it("draws no controls before the list has loaded and there is no onNew", () => {
    renderLanding({ items: null });
    expect(screen.queryByRole("searchbox")).toBeNull();
    expect(screen.queryByRole("button", { name: /New/ })).toBeNull();
  });

  // Guards the class of bug flagged for this task: if `hasItems` read the FILTERED list instead
  // of the raw one, the moment a query matched nothing the search box the user just typed into
  // would unmount, and there would be no control left to clear the query with. `hasItems` is
  // unaffected by `query`, so the field survives a query that matches nothing.
  it("keeps the filter field mounted when the query matches nothing", async () => {
    renderLanding({
      items: [
        { id: "a", label: "Alpha" },
        { id: "b", label: "Beta" },
      ],
    });
    const field = await screen.findByRole("searchbox");
    fireEvent.change(field, { target: { value: "zzz-no-match" } });
    expect(screen.getByText(/No matches for/)).toBeInTheDocument();
    expect(screen.getByRole("searchbox")).toBeInTheDocument();
  });

  it("filters the landing's rows from its field", async () => {
    renderLanding({
      items: [
        { id: "a", label: "Alpha" },
        { id: "b", label: "Beta" },
      ],
    });
    const field = await screen.findByRole("searchbox");
    fireEvent.change(field, { target: { value: "Alph" } });
    expect(screen.getByText("Alpha")).toBeInTheDocument();
    expect(screen.queryByText("Beta")).toBeNull();
  });

  it("switches between the cards and list views from its toggle", async () => {
    renderLanding({
      items: [{ id: "a", label: "Alpha" }],
    });
    await screen.findByLabelText("View as");
    // The card view renders the label inside a card `<div>`; the list view renders a
    // plain `<ul>`. Cards is the default, so asserting the list markup appears after the click is
    // enough to prove the toggle still drives this component's own `view` state. The
    // toggle item's accessible name is its `aria-label` ("View as list"), not its `title`
    // ("List") — `aria-label` wins the accessible-name computation, so that is what the query
    // below has to match.
    expect(screen.queryByRole("list")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "View as list" }));
    expect(screen.getByRole("list")).toBeInTheDocument();
  });
});
