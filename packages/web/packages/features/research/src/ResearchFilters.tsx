"use client";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
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
  onChange: (next: FilterState) => void;
  categories: string[];
  tags: string[];
}) {
  const axes = [
    { name: "category", label: "Category", allLabel: "All categories", options: categories },
    { name: "tag", label: "Tag", allLabel: "All tags", options: tags },
  ] as const;
  // The gear says whether it is narrowing anything: a filter chosen here is otherwise invisible
  // once the menu closes, and a list that silently hides rows reads as a list that lost them.
  const active = filters.category !== "" || filters.tag !== "";
  return (
    <DropdownMenu>
      <GearMenuTrigger
        label={active ? "Document filters (active)" : "Document filters"}
        className={active ? "text-apt-gold" : undefined}
      />
      <DropdownMenuContent align="end">
        {axes.map((axis) => (
          <DropdownMenuSub key={axis.name}>
            <DropdownMenuSubTrigger>
              {axis.label}: {filters[axis.name] || axis.allLabel.toLowerCase()}
            </DropdownMenuSubTrigger>
            {/* No <DropdownMenuPortal> wrapper: this engine's SubContent portals itself. */}
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup
                value={filters[axis.name]}
                onValueChange={(value) => onChange({ ...filters, [axis.name]: value })}
              >
                <DropdownMenuRadioItem value="">{axis.allLabel}</DropdownMenuRadioItem>
                {axis.options.map((opt) => (
                  <DropdownMenuRadioItem key={opt} value={opt}>
                    {opt}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuSub>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
