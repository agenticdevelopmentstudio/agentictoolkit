/// <reference types="@testing-library/jest-dom/vitest" />
/**
 * G39: the blocked-reason caption row under the button bar must not mount/unmount as
 * `blockedReason` flips between a string and null — that shifted the whole detail pane below by a
 * full line on every reason-appears/reason-clears edit, and unmounting a `role="status"` live
 * region is exactly the thing that stops a screen reader tracking it. The fix keys the row's
 * MOUNTED LIFETIME on whether `actions.blockedReason` was set AT ALL (present, even as `null`) —
 * never on its truthiness — and swaps only the text inside, falling back to a non-breaking space
 * so the line keeps its height with nothing to say (Mike, 2026-09-25).
 */
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ButtonBar, type MasterDetailActions } from "../master-detail/MasterDetailLayout";

/** The bar's required plumbing, held fixed across every test — only `blockedReason` (and its
 *  presence) varies. */
function baseActions(overrides: Partial<MasterDetailActions> = {}): MasterDetailActions {
  return {
    onCreate: () => {},
    onCancel: () => {},
    canCancel: false,
    onSave: () => {},
    canSave: false,
    onDelete: () => {},
    canDelete: false,
    ...overrides,
  };
}

describe("ButtonBar — the blocked-reason row's mounted lifetime", () => {
  it("renders the row (holding the line with a non-breaking space) when the channel is open but empty", () => {
    render(<ButtonBar actions={baseActions({ blockedReason: null })} hoist={false} />);
    const row = screen.getByRole("status");
    // A plain space would collapse in the DOM/JSDOM's text normalization; the literal NBSP
    // character is what actually holds the block's height in a browser.
    expect(row.textContent).toBe(" ");
  });

  it("swaps the TEXT without unmounting the row when a reason appears", () => {
    const { rerender } = render(
      <ButtonBar actions={baseActions({ blockedReason: null })} hoist={false} />,
    );
    const before = screen.getByRole("status");

    rerender(<ButtonBar actions={baseActions({ blockedReason: "Name is required." })} hoist={false} />);
    const after = screen.getByRole("status");

    // Same DOM node — proof the row never unmounted, just re-rendered its text.
    expect(after).toBe(before);
    expect(after.textContent).toBe("Name is required.");
  });

  it("swaps back to the non-breaking space without unmounting when the reason clears", () => {
    const { rerender } = render(
      <ButtonBar actions={baseActions({ blockedReason: "Name is required." })} hoist={false} />,
    );
    const before = screen.getByRole("status");

    rerender(<ButtonBar actions={baseActions({ blockedReason: null })} hoist={false} />);
    const after = screen.getByRole("status");

    expect(after).toBe(before);
    expect(after.textContent).toBe(" ");
  });

  it("renders no row at all when the bar never sets `blockedReason` (a hand-built bar with no channel)", () => {
    // `blockedReason` is omitted entirely here, not set to null — the fact this test exists to
    // distinguish. `NotebookPane`/`ResearchPane` build their `MasterDetailActions` this way.
    render(<ButtonBar actions={baseActions()} hoist={false} />);
    expect(screen.queryByRole("status")).toBeNull();
  });

  it("puts the full reason in `title` so a truncated caption is still readable on hover/focus", () => {
    const long =
      "This is a deliberately long blocked-reason message that would overflow a narrow row and " +
      "should be clamped with `truncate`, while still being available in full via the title attribute.";
    render(<ButtonBar actions={baseActions({ blockedReason: long })} hoist={false} />);
    const row = screen.getByRole("status");
    expect(row).toHaveAttribute("title", long);
    expect(row.className).toContain("truncate");
  });

  it("omits `title` when there is nothing to say, rather than an empty attribute", () => {
    render(<ButtonBar actions={baseActions({ blockedReason: null })} hoist={false} />);
    expect(screen.getByRole("status")).not.toHaveAttribute("title");
  });
});
