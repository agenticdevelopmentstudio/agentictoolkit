"use client";
import { type CSSProperties, type ReactElement, type ReactNode, useState } from "react";
import { Settings } from "lucide-react";
import { Popover, PopoverTrigger, PopoverContent } from "@agentic-toolkit/ui/components/popover";
import { cn } from "@agentic-toolkit/ui/lib/utils";

import { COLORS, PALETTE } from "../lib/colors";
const mono = "var(--mono,ui-monospace,monospace)";

/** One checkbox/radio row inside an options popover — shared by every gear so the
 *  sources/environments/age-out/range lists can't drift. Spread + override (e.g.
 *  a per-env label color) as needed. */
export const optionRow = (on: boolean): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  gap: 8,
  padding: "5px 4px",
  cursor: "pointer",
  fontFamily: mono,
  fontSize: 12,
  color: on ? PALETTE.text : PALETTE.muted,
});

export interface OptionsGearProps {
  /** How many options differ from their defaults → a yellow badge (0 hides it). */
  changedCount: number;
  /** Plain-text synopsis of the current settings, shown on hover (native title;
   *  use "\n" for multiple lines). */
  summary: string;
  /** aria-label for the trigger. */
  label?: string;
  /** Popover content — the panel's option controls; receives `close()`. */
  children: (close: () => void) => ReactNode;
  /** Min width of the popover menu. */
  menuWidth?: number;
}

/**
 * The standardized per-panel options control: a right-justified gear button that
 * opens a popover of that panel's filters/settings. A yellow count badge marks
 * how many options are off-default, and hovering the gear shows a one-glance
 * synopsis. The popover body is supplied by each panel (sources, environments,
 * etc.) so the trigger, badge, and tooltip stay identical everywhere.
 *
 * Built on the shared @agentic-toolkit/ui Popover (Base UI engine) rather than a bespoke
 * portal: the gear body is arbitrary consumer JSX (native checkbox/radio rows), not
 * menu items, so a non-menu popup is the right primitive. `open` is controlled here
 * so the render-prop `close()` still dismisses after a single-select pick.
 */
export function OptionsGear({ changedCount, summary, label = "options", children, menuWidth = 210 }: OptionsGearProps): ReactElement {
  const [open, setOpen] = useState(false);
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        aria-label={label}
        title={summary}
        className={cn(
          "relative inline-flex h-6 w-[26px] shrink-0 cursor-pointer items-center justify-center rounded-md border bg-apt-bg p-0 text-apt-text-muted outline-none data-[popup-open]:text-apt-text",
          changedCount > 0 ? "border-apt-gold/40 text-apt-text" : "border-apt-border",
        )}
      >
        <Settings size={14} aria-hidden />
        {changedCount > 0 && (
          <span
            aria-hidden
            className="absolute -right-1.5 -top-1.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-apt-gold px-[3px] font-mono text-[9px] font-bold leading-none text-apt-bg"
          >
            {changedCount}
          </span>
        )}
      </PopoverTrigger>
      <PopoverContent align="end" sideOffset={6} className="w-auto p-2" style={{ minWidth: menuWidth }}>
        {children(() => setOpen(false))}
      </PopoverContent>
    </Popover>
  );
}

const mutedLabel = {
  display: "block",
  fontFamily: mono,
  fontSize: "9.5px",
  letterSpacing: "0.07em",
  textTransform: "uppercase",
  color: PALETTE.dim,
  padding: "2px 4px 4px",
} as const;

/** A titled group inside an options popover (a small uppercase caption + body). */
export function OptionSection({ title, children }: { title: string; children: ReactNode }): ReactElement {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <span style={mutedLabel}>{title}</span>
      {children}
    </div>
  );
}

/** A thin divider between option sections. */
export function OptionDivider(): ReactElement {
  return <div style={{ height: 1, margin: "6px 4px", background: COLORS.border }} />;
}
