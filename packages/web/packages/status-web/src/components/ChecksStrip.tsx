import type { ReactElement } from "react";
import { COLORS, HEALTH_COLORS } from "../lib/colors";
const STATUS_COLOR = HEALTH_COLORS;

export interface ChecksStripProps {
  statuses: ("healthy" | "degraded" | "down")[];
}

/**
 * A row of small colored tick marks, one per check result.
 * Matches the mockup's .checks strip.
 */
export function ChecksStrip({ statuses }: ChecksStripProps): ReactElement {
  return (
    <div style={{ display: "flex", gap: 2, flexWrap: "wrap" }}>
      {statuses.map((s, i) => (
        <span
          key={i}
          title={s}
          style={{
            width: 9,
            height: 14,
            borderRadius: 1,
            background: STATUS_COLOR[s] ?? COLORS.border,
            display: "inline-block",
          }}
        />
      ))}
    </div>
  );
}
