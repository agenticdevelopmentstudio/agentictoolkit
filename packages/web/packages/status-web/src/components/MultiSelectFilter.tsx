"use client";
import type { ReactElement } from "react";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuCheckboxItem,
  DropdownMenuSeparator,
} from "@agentic-toolkit/ui/components/dropdown-menu";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { menuTriggerPillClass } from "./menu-pill";

export interface MultiSelectOption {
  key: string;
  label: string;
}

export interface MultiSelectFilterProps {
  /** Popover `label` (a11y name for the trigger), e.g. "Source filter". */
  popoverLabel: string;
  /** Muted leading word in the trigger, e.g. "sources" or "show". */
  triggerNoun: string;
  /** The selectable options — already narrowed by the caller (e.g. to a pane's
   *  present sources). The denominator for the "n/total" trigger. */
  options: MultiSelectOption[];
  isSelected: (key: string) => boolean;
  onToggle: (key: string) => void;
  /** Per-row aria-label (e.g. `source Vercel`), kept caller-defined so existing
   *  selectors don't shift. */
  optionAriaLabel: (label: string) => string;
  /** When provided, renders a leading "all" toggle row + divider. */
  onSetAll?: (all: boolean) => void;
  /** aria-label for the "all" row (required-in-practice when `onSetAll` is set). */
  allAriaLabel?: string;
  menuMinWidth?: number;
  /** Greyed + inert (nothing to filter) — the trigger stays visible, never opens. */
  disabled?: boolean;
}

/**
 * A compact multi-select filter: a trigger reading "{noun} all" or "{noun} n/total",
 * and a checkbox list. Built on the shared @agentic-toolkit/ui DropdownMenu (Base UI
 * engine) — each row is a `DropdownMenuCheckboxItem` with `closeOnClick={false}` so
 * the menu stays open across toggles (multi-select), and the menuitemcheckbox role +
 * keyboard navigation come free from the engine. Shared by the issue panes' source
 * filter and the platform config's project-status filter so the trigger, menu, and
 * row styling live in one place.
 */
export function MultiSelectFilter({
  popoverLabel,
  triggerNoun,
  options,
  isSelected,
  onToggle,
  optionAriaLabel,
  onSetAll,
  allAriaLabel,
  menuMinWidth = 150,
  disabled = false,
}: MultiSelectFilterProps): ReactElement {
  const total = options.length;
  const count = options.filter((o) => isSelected(o.key)).length;
  const allOn = count === total;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        aria-label={popoverLabel}
        disabled={disabled}
        className={cn(menuTriggerPillClass, "disabled:cursor-not-allowed disabled:opacity-50")}
      >
        <span className="text-apt-text-dim">{triggerNoun}</span>
        {allOn ? "all" : `${count}/${total}`}
        <span aria-hidden className="text-apt-text-dim">▾</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" style={{ minWidth: menuMinWidth }}>
        {onSetAll && (
          <>
            <DropdownMenuCheckboxItem
              checked={allOn}
              closeOnClick={false}
              onCheckedChange={() => onSetAll(!allOn)}
              aria-label={allAriaLabel}
            >
              all
            </DropdownMenuCheckboxItem>
            <DropdownMenuSeparator />
          </>
        )}
        {options.map((o) => (
          <DropdownMenuCheckboxItem
            key={o.key}
            checked={isSelected(o.key)}
            closeOnClick={false}
            onCheckedChange={() => onToggle(o.key)}
            aria-label={optionAriaLabel(o.label)}
          >
            {o.label}
          </DropdownMenuCheckboxItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
