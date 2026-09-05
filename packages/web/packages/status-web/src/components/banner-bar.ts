import type { CSSProperties } from "react";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { PALETTE, TINT } from "../lib/colors";

// Shared shell for the top-of-page attention banners (Unconfigured projects, Retire
// stale monitors). One place owns the bar layout + the popover-trigger button style so
// the banners can't drift apart; `tone` swaps the palette (amber = needs config, red =
// down/cleanup).

export const BANNER_MONO = "var(--mono,ui-monospace,monospace)";

export type BannerTone = "amber" | "red";

const TONE: Record<BannerTone, { bg: string; border: string; fg: string }> = {
  amber: { bg: TINT.amberBg, border: TINT.amberBorder, fg: PALETTE.amber },
  red: { bg: TINT.redBg, border: TINT.redBorder, fg: PALETTE.red },
};

/** The banner's accent (headline + trigger) color for a tone. */
export const bannerColor = (tone: BannerTone): string => TONE[tone].fg;

/** The full-width tinted strip. */
export function bannerBarStyle(tone: BannerTone): CSSProperties {
  return {
    flex: "0 0 auto",
    display: "flex",
    alignItems: "center",
    gap: 10,
    padding: "6px 16px",
    background: TONE[tone].bg,
    borderBottom: `1px solid ${TONE[tone].border}`,
    flexWrap: "wrap",
  };
}

// Tone accent + the open-state highlight, which now rides the shared trigger's
// `[data-popup-open]` hook (Base UI sets it while the popover is open) instead of a
// render callback — so the whole trigger style is one static, tokens-only class string.
const TRIGGER_TONE: Record<BannerTone, string> = {
  amber: "text-apt-gold data-[popup-open]:bg-apt-gold/[0.18]",
  red: "text-apt-red data-[popup-open]:bg-apt-red/[0.16]",
};

/** Classes for a banner's popover trigger (a shared `PopoverTrigger` button). */
export function bannerTriggerClass(tone: BannerTone): string {
  return cn(
    "inline-flex cursor-pointer items-center gap-2 whitespace-nowrap rounded-md border border-transparent px-1.5 py-0.5 font-mono text-[11px] font-bold tracking-[0.05em] outline-none",
    TRIGGER_TONE[tone],
  );
}
