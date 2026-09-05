// @vitest-environment jsdom
import { describe, it, expect } from "vitest";
import { act, render } from "@testing-library/react";
import { useDraftForSelection } from "./use-draft-for-selection";

interface Row {
  id: string;
  name: string;
}

/** Render the hook against a controllable selection/row and expose its returns. */
function harness() {
  const out: {
    draft?: { name: string };
    setDraft?: (d: { name: string }) => void;
    discardDraft?: () => void;
  } = {};
  function Probe({ selectedId, current }: { selectedId: string | null; current: Row | null }) {
    const r = useDraftForSelection<Row, { name: string }>({
      selectedId,
      current,
      initial: () => ({ name: "" }),
      load: (row) => ({ name: row.name }),
    });
    out.draft = r.draft;
    out.setDraft = r.setDraft;
    out.discardDraft = r.discardDraft;
    return null;
  }
  return { out, Probe };
}

describe("useDraftForSelection", () => {
  it("hydrates when the selection's row arrives (deep-link: selection before data)", () => {
    const { out, Probe } = harness();
    const view = render(<Probe selectedId="a" current={null} />);
    expect(out.draft).toEqual({ name: "" }); // row not loaded yet — no hydration
    view.rerender(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    expect(out.draft).toEqual({ name: "Alpha" }); // waited for the row, then loaded
  });

  it("preserves an unsaved draft across a selection→null round trip (leaving Settings)", () => {
    const { out, Probe } = harness();
    const view = render(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    act(() => out.setDraft!({ name: "Alpha EDITED" }));
    // The board clears the entity segment (topic switch) — draft must survive.
    view.rerender(<Probe selectedId={null} current={null} />);
    view.rerender(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    expect(out.draft).toEqual({ name: "Alpha EDITED" });
  });

  it("a background refetch (new row identity, same id) never clobbers edits", () => {
    const { out, Probe } = harness();
    const view = render(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    act(() => out.setDraft!({ name: "Alpha EDITED" }));
    view.rerender(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    expect(out.draft).toEqual({ name: "Alpha EDITED" });
  });

  it("discardDraft() makes the next selection of the SAME id rehydrate fresh (Cancel)", () => {
    const { out, Probe } = harness();
    const view = render(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    act(() => out.setDraft!({ name: "Alpha EDITED" }));
    act(() => out.discardDraft!());
    view.rerender(<Probe selectedId={null} current={null} />);
    view.rerender(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    expect(out.draft).toEqual({ name: "Alpha" }); // discarded, reloaded from the row
  });

  it("selecting a DIFFERENT row always reloads from it", () => {
    const { out, Probe } = harness();
    const view = render(<Probe selectedId="a" current={{ id: "a", name: "Alpha" }} />);
    act(() => out.setDraft!({ name: "Alpha EDITED" }));
    view.rerender(<Probe selectedId="b" current={{ id: "b", name: "Beta" }} />);
    expect(out.draft).toEqual({ name: "Beta" });
  });
});
