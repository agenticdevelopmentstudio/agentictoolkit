"use client"

import type { Dispatch, SetStateAction } from "react"

import {
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu"

/**
 * The two axes a markdown list's gear narrows on, each an exact name or `""` for no narrowing.
 * Both are FILTERS over whatever the rail is already showing: `category` is not the rail's
 * category selection (see `resolveListCategory`). A list's filter state carries more than these
 * two — its search query at least — which is why everything below is generic over it.
 */
export interface CategoryTagFilters {
  category: string
  tag: string
}

/**
 * Whether a gear is narrowing its list. A filter chosen in a gear is otherwise invisible once the
 * menu closes, and a list that silently hides rows reads as a list that lost them — so the gear
 * turns gold while this holds, and says so in its name ({@link filteringGearLabel}).
 */
export function isCategoryTagFiltering(filters: CategoryTagFilters): boolean {
  return filters.category !== "" || filters.tag !== ""
}

/**
 * A filter gear's accessible name: `label`, marked while the gear narrows. One mark for every
 * list, so the notes gear and the documents gear say the same word — the two hand-kept copies
 * this replaced had already drifted, one to "(filtered)" and the other to "(active)".
 */
export function filteringGearLabel(label: string, filtering: boolean): string {
  return filtering ? `${label} (filtered)` : label
}

const AXES = [
  { name: "category", title: "Category", allLabel: "All categories" },
  { name: "tag", title: "Tag", allLabel: "All tags" },
] as const

/**
 * The category and tag submenus of a markdown list's gear: one radio group per axis, its
 * all-pass choice first. The caller places them inside its own `DropdownMenuContent`, beside
 * whatever else its gear offers. The notes list and the Research documents list each carried a
 * copy of this loop, and the two had drifted (axis keys, option types, the gear's name) before
 * either had shipped.
 *
 * The option sets are the caller's, taken from its UNFILTERED universe, so narrowing the list can
 * never empty the menus that got it there.
 */
export function CategoryTagFilterItems<F extends CategoryTagFilters>({
  filters,
  onChange,
  categories,
  tags,
}: {
  filters: F
  /** The list's state SETTER, not a value callback: a choice is written through the updater form,
   *  so it lands on the filters as they are NOW. A gear is drawn from the rail host's REGISTERED
   *  level, whose `filters` can be a render behind the list's — spreading that snapshot put back a
   *  filter the user had just cleared. */
  onChange: Dispatch<SetStateAction<F>>
  /** Category names to offer. */
  categories: readonly string[]
  /** Tag labels to offer. */
  tags: readonly string[]
}) {
  const options = { category: categories, tag: tags }
  return (
    <>
      {AXES.map((axis) => (
        <DropdownMenuSub key={axis.name}>
          <DropdownMenuSubTrigger>
            {axis.title}: {filters[axis.name] || axis.allLabel.toLowerCase()}
          </DropdownMenuSubTrigger>
          {/* No <DropdownMenuPortal> wrapper: this engine's SubContent portals itself. */}
          <DropdownMenuSubContent>
            <DropdownMenuRadioGroup
              value={filters[axis.name]}
              onValueChange={(value) => onChange((prev) => ({ ...prev, [axis.name]: value }))}
            >
              <DropdownMenuRadioItem value="">{axis.allLabel}</DropdownMenuRadioItem>
              {options[axis.name].map((opt) => (
                <DropdownMenuRadioItem key={opt} value={opt}>
                  {opt}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
          </DropdownMenuSubContent>
        </DropdownMenuSub>
      ))}
    </>
  )
}
