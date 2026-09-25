"use client";

import type { Dispatch, SetStateAction } from "react";

import {
  CategoryTagFilterItems,
  filteringGearLabel,
  isCategoryTagFiltering,
} from "@agentic-toolkit/categories";
import {
  DropdownMenu,
  DropdownMenuContent,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { GearMenuTrigger } from "@agenticdevelopertoolkit/ui/blocks";

/** Controlled list filters. Empty string means "no filter" for that axis. */
export interface FilterState {
  q: string;
  category: string;
  tag: string;
}

/**
 * The category/tag filters for the research document list: the gear on the Documents list's own
 * toolbar. They were a row of selects in the page-wide home bar until that strip was removed as
 * clunky (Mike, 2026-09-24); a rail is too narrow to hold two selects open, so they fold into
 * the gear that is the fleet's sign for "options on this list". The `q` axis is NOT here — it is
 * the list's own pop-over search (`TopicLevel.search`), which every filterable list shares.
 *
 * Every axis is still wired to the backend list endpoint (`category`, `tag`); the option sets come
 * from the caller's full document universe so a narrowed list never empties its own menu.
 */
export function ResearchFilters({
  filters,
  onChange,
  categories,
  tags,
}: {
  filters: FilterState;
  /** The pane's state SETTER, not a value callback: a choice is written through the updater form,
   *  so it lands on the filters as they are NOW. This gear is drawn from the rail host's REGISTERED
   *  level, whose `filters` can be a render behind the pane's — spreading that snapshot put back a
   *  filter the user had just cleared. */
  onChange: Dispatch<SetStateAction<FilterState>>;
  categories: string[];
  tags: string[];
}) {
  // The gear says whether it is narrowing anything: gold, and marked in its name. The reason
  // lives on `isCategoryTagFiltering`, which the notes gear shares.
  const active = isCategoryTagFiltering(filters);
  return (
    <DropdownMenu>
      <GearMenuTrigger
        label={filteringGearLabel("Document filters", active)}
        className={active ? "text-apt-gold" : undefined}
      />
      <DropdownMenuContent align="end">
        <CategoryTagFilterItems
          filters={filters}
          onChange={onChange}
          categories={categories}
          tags={tags}
        />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
