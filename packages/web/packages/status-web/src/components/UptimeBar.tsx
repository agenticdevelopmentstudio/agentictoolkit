import type { ReactElement } from "react";
import type { UptimeDay } from "../types";
import { COLORS, HEALTH_COLORS } from "../lib/colors";
const COLOR = HEALTH_COLORS;

export function UptimeBar({ daily }: { daily: UptimeDay[] }): ReactElement {
  return (
    <div className="flex gap-[2px] items-end" style={{ height: 28 }}>
      {daily.map((d) => (
        <span key={d.day} title={`${d.day}: ${d.uptimePercent ?? "?"}%`} style={{ flex: 1, height: "100%", background: COLOR[d.status] ?? COLORS.border, borderRadius: 1, minWidth: 2 }} />
      ))}
    </div>
  );
}
