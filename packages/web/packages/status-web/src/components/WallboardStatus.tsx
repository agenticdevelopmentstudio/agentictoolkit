"use client";
import { type ReactElement } from "react";
import { useMediaQuery } from "../hooks/use-media-query";
import { usePortfolioIndicator } from "../hooks/use-portfolio-indicator";
import { type IndicatorState, headlineFor } from "../lib/overview";
import { StatusDot } from "./StatusDot";
import { StatusSign } from "./StatusSign";

const mono = "var(--mono,ui-monospace,monospace)";

// Pill copy per state — mirrors the live indicator (incl. failed deploys), so it
// never reads "Operational" while problems are open.
const PILL: Record<IndicatorState | "unknown", string> = {
  ok: "OPERATIONAL",
  warn: "DEGRADED",
  down: "PROBLEMS",
  unknown: "UNKNOWN",
};

/** The road-sign glyph (or a plain dot for UNKNOWN) at a fixed box so the bar
 *  height never shifts between states; carries the spoken status via role=status. */
function PillGlyph({ pillKey, count, size, label }: { pillKey: IndicatorState | "unknown"; count: number; size: number; label: string }): ReactElement {
  return (
    <span role="status" aria-label={label} style={{ width: size, height: size, display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      {pillKey === "unknown" ? <StatusDot status="unknown" size={Math.round(size * 0.5)} decorative /> : <StatusSign state={pillKey} count={count} size={size} />}
    </span>
  );
}

/**
 * The wallboard's live status, centred in the host's header: just the indicator sign
 * (with its problem count) + the state word (PROBLEMS / OPERATIONAL / …).
 *
 * This pill is GLOBAL — it counts problems across every environment, on purpose:
 * it's the always-on portfolio headline, shown on Overview/Details/Config alike
 * and independent of the Overview tab's env filter. So it can legitimately read
 * "PROBLEMS" while an env-filtered Overview board reads "OPERATIONAL" (the board
 * is scoped to the chosen envs; the header is the whole-portfolio truth). Both
 * derive from the same usePortfolioIndicator hook — they differ only by scope.
 */
function WallboardStatusLive(): ReactElement {
  // Shared with the /home landing sign so the "unknown" rule + count never diverge.
  const { pillKey, count } = usePortfolioIndicator();
  const statusHeadline = pillKey === "unknown" ? "UNKNOWN" : headlineFor(pillKey, count);

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 14, color: "var(--color-apt-text)", whiteSpace: "nowrap" }}>
      <PillGlyph pillKey={pillKey} count={count} size={30} label={statusHeadline} />
      <span style={{ fontFamily: mono, fontWeight: 600, letterSpacing: "0.04em", fontSize: 13 }}>{PILL[pillKey]}</span>
    </div>
  );
}

/**
 * The live status pill the host mounts in its header's centre slot on the board
 * routes (`isBoardPath` in ./board-views says which). The host's header CSS hides
 * that slot at phone width, so don't MOUNT the live inner there — that keeps phones
 * from running the 30s clock + indicator recompute for an element no one can see.
 * Only the cheap media-query hook runs when narrow.
 *
 * The gate is `(min-width: 761px)`, the exact complement of the host's hide rule, so
 * a TABLET gets the pill: it is the only portfolio headline outside phone width (the
 * BigIndicator hero renders only on the mobile layout), and it is the board's single
 * role="status" announcer. Anything narrower falls to that hero.
 */
export function WallboardStatus(): ReactElement | null {
  const wide = useMediaQuery("(min-width: 761px)");
  return wide ? <WallboardStatusLive /> : null;
}
