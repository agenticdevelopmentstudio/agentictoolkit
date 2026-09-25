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
  DropdownMenuItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { GearMenuTrigger } from "@agenticdevelopertoolkit/ui/blocks";

import {
  PREVIEW_LINES_MAX,
  PREVIEW_LINES_MIN,
  setPreviewLines,
  usePreviewLines,
} from "./preview-lines";

/**
 * The three axes the notes list narrows on. All three are FILTERS over whatever the rail is
 * already showing — `category` in particular is NOT the rail's category selection: the rail
 * scopes (which part of the notebook you are standing in) and this narrows within it. Naming
 * two different categories therefore yields nothing, which is the honest answer to what was
 * asked; see `resolveListCategory` in note-model.ts.
 */
export interface FilterState {
  /** Free-text search over the note bodies — the list's own pop-over search, not this menu. */
  q: string;
  /** Exact category name, or `""` for no narrowing. */
  category: string;
  /** Exact tag label, or `""` for no narrowing. */
  tag: string;
}

const CHOICES = Array.from(
  { length: PREVIEW_LINES_MAX - PREVIEW_LINES_MIN + 1 },
  (_, i) => PREVIEW_LINES_MIN + i,
);

function choiceLabel(n: number): string {
  if (n === 0) return "No preview";
  return n === 1 ? "1 line" : `${n} lines`;
}

/**
 * The notes list's gear, on its own toolbar: the category/tag filters, the two taxonomy
 * editors, and how much of each note's body a row shows.
 *
 * The filters and editors were a button bar in the page-wide home bar until that strip was
 * removed as clunky (Mike, 2026-09-24). A rail is too narrow to hold two selects open, so they
 * fold in here beside the appearance setting that was already the gear's; search became the
 * toolbar's pop-over and Create Note its `+`. The option sets are the caller's, taken from the
 * UNFILTERED note universe, so narrowing the list can never empty the menus that got it there.
 *
 * The preview value lives in `preview-lines.ts` — every list in the tab follows a change here
 * immediately, and it survives a reload.
 */
export function NoteListOptions({
  filters,
  onChange,
  categories,
  tags,
  onEditCategories,
  onEditTags,
  label = "Notes list options",
}: {
  filters: FilterState;
  /** The pane's state SETTER, not a value callback: a choice is written through the updater form,
   *  so it lands on the filters as they are NOW. This gear is drawn from the rail host's REGISTERED
   *  level, whose `filters` can be a render behind the pane's — spreading that snapshot put back a
   *  filter the user had just cleared. */
  onChange: Dispatch<SetStateAction<FilterState>>;
  /** Category names to offer. */
  categories: readonly string[];
  /** Tag labels to offer. */
  tags: readonly string[];
  onEditCategories: () => void;
  onEditTags: () => void;
  /** The gear's accessible name; the corpus names its own list. */
  label?: string;
}) {
  const lines = usePreviewLines();
  // The gear says whether it is narrowing anything: gold, and marked in its name. The reason
  // lives on `isCategoryTagFiltering`, which the Research documents gear shares.
  const active = isCategoryTagFiltering(filters);
  return (
    <DropdownMenu>
      <GearMenuTrigger
        label={filteringGearLabel(label, active)}
        className={active ? "text-apt-gold" : undefined}
      />
      <DropdownMenuContent align="end">
        <CategoryTagFilterItems
          filters={filters}
          onChange={onChange}
          categories={categories}
          tags={tags}
        />
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={onEditCategories}>Edit categories…</DropdownMenuItem>
        <DropdownMenuItem onClick={onEditTags}>Edit tags…</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuSub>
          <DropdownMenuSubTrigger>Preview: {choiceLabel(lines).toLowerCase()}</DropdownMenuSubTrigger>
          <DropdownMenuSubContent>
            <DropdownMenuRadioGroup
              value={String(lines)}
              onValueChange={(next) => setPreviewLines(Number(next))}
            >
              {CHOICES.map((n) => (
                <DropdownMenuRadioItem key={n} value={String(n)}>
                  {choiceLabel(n)}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
          </DropdownMenuSubContent>
        </DropdownMenuSub>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
