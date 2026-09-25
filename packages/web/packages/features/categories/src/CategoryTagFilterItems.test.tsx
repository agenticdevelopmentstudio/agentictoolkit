/// <reference types="@testing-library/jest-dom/vitest" />
//
// The category/tag items a markdown list's gear shares — the notes list's and the Research
// documents list's, which each carried a hand-kept copy until the copies drifted. Pinned here, where
// the loop now lives: what each submenu names, the one mark the gear's name takes while it narrows,
// and how a pick is WRITTEN.
import { describe, expect, it, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import type { Dispatch, SetStateAction } from "react";
import {
  DropdownMenu,
  DropdownMenuContent,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { GearMenuTrigger } from "@agenticdevelopertoolkit/ui/blocks";

import {
  CategoryTagFilterItems,
  filteringGearLabel,
  isCategoryTagFiltering,
  type CategoryTagFilters,
} from "./CategoryTagFilterItems";

/** A list's filter state carries more than the two axes — its search query at least. */
interface Filters extends CategoryTagFilters {
  q: string;
}

/** A gear the way both lists compose one: their own trigger and content, the shared items. */
function Gear({
  filters,
  onChange,
}: {
  filters: Filters;
  onChange: Dispatch<SetStateAction<Filters>>;
}) {
  return (
    <DropdownMenu>
      <GearMenuTrigger label={filteringGearLabel("List options", isCategoryTagFiltering(filters))} />
      <DropdownMenuContent>
        <CategoryTagFilterItems
          filters={filters}
          onChange={onChange}
          categories={["Work", "Home"]}
          tags={["meeting"]}
        />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

describe("CategoryTagFilterItems", () => {
  it("names each axis by what it narrows to, and offers the all-pass choice first", async () => {
    render(<Gear filters={{ q: "", category: "Work", tag: "" }} onChange={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "List options (filtered)" }));
    expect(await screen.findByRole("menuitem", { name: "Category: Work" })).toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "Tag: all tags" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("menuitem", { name: "Category: Work" }));
    const choices = await screen.findAllByRole("menuitemradio");
    expect(choices.map((c) => c.textContent)).toEqual(["All categories", "Work", "Home"]);
  });

  // Both lists draw their gear from the rail host's REGISTERED level, which can be a render behind
  // the list's own state: spreading the drawn snapshot put back a category the user had just
  // cleared. So a pick is an UPDATER, applied to whatever the state is when it lands.
  it("writes a pick onto the filters as they are when it lands, not the ones it was drawn from", async () => {
    const onChange = vi.fn();
    render(<Gear filters={{ q: "", category: "Work", tag: "" }} onChange={onChange} />);
    fireEvent.click(screen.getByRole("button", { name: "List options (filtered)" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Tag:/ }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "meeting" }));

    expect(onChange).toHaveBeenCalledTimes(1);
    const update = onChange.mock.calls[0]?.[0] as SetStateAction<Filters>;
    expect(typeof update).toBe("function");
    const now: Filters = { q: "notes", category: "", tag: "" };
    expect(typeof update === "function" ? update(now) : update).toEqual({
      q: "notes",
      category: "",
      tag: "meeting",
    });
  });
});

describe("a filter gear's state and name", () => {
  it("narrows while either axis names something", () => {
    expect(isCategoryTagFiltering({ category: "", tag: "" })).toBe(false);
    expect(isCategoryTagFiltering({ category: "Work", tag: "" })).toBe(true);
    expect(isCategoryTagFiltering({ category: "", tag: "meeting" })).toBe(true);
  });

  it("takes one mark while it narrows, whichever list it names", () => {
    expect(filteringGearLabel("Document filters", false)).toBe("Document filters");
    expect(filteringGearLabel("Document filters", true)).toBe("Document filters (filtered)");
    expect(filteringGearLabel("Notes list options", true)).toBe("Notes list options (filtered)");
  });
});
