import type { ReactElement, ReactNode } from "react";
import { type IndicatorState, headlineFor } from "../lib/overview";
import { StatusSign } from "./StatusSign";

import { COLORS, PALETTE } from "../lib/colors";
export interface BigIndicatorProps {
  state: IndicatorState;
  count: number;
  /** Small line under the headline, e.g. "12/12 endpoints healthy". */
  sublabel?: string;
  size?: number;
  /** Content rendered below the headline (e.g. the stats strip). */
  extra?: ReactNode;
}

function headlineColor(state: IndicatorState): string {
  if (state === "ok") return PALETTE.green;
  if (state === "warn") return COLORS.amberLight;
  return PALETTE.red;
}

/**
 * The mobile hero status block: the big road-sign over the headline + sublabel,
 * with optional `extra` (stats) below. NOT a live region — the top-bar pill is
 * the single role="status" announcer; this is the visible hero presentation.
 */
export function BigIndicator({ state, count, sublabel, size = 96, extra }: BigIndicatorProps): ReactElement {
  const headline = headlineFor(state, count);
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", gap: 20, width: "100%" }}>
      <StatusSign state={state} count={count} size={size} />
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
        <div style={{ fontSize: 26, fontWeight: 700, letterSpacing: "0.06em", lineHeight: 1.25, color: headlineColor(state) }}>
          {headline}
        </div>
        {sublabel && (
          <div style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 14, color: PALETTE.muted, maxWidth: "32ch" }}>{sublabel}</div>
        )}
      </div>
      {extra && <div style={{ width: "100%" }}>{extra}</div>}
    </div>
  );
}
