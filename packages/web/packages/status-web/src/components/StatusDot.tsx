import type { ReactElement } from "react";
import {
  StatusDot as SharedStatusDot,
  type StatusDotTone,
} from "@agentic-toolkit/ui/components/status-dot";

// Domain adapter only: maps the monitor's health/overall status WORDS onto the
// family tone scale. The rendering (fill + glow driven by one tone) is the
// shared StatusDot — this file owns no visual knowledge.
const TONES: Record<string, StatusDotTone> = {
  healthy: "success",
  operational: "success",
  degraded: "accent",
  unknown: "accent",
  down: "error",
  major_outage: "error",
};

export function StatusDot({
  status,
  size = 10,
  decorative = false,
}: {
  status: string;
  size?: number;
  /** Set when the status word is ALREADY shown as adjacent visible text (or the
   *  dot sits inside a labeled `role="status"` region) — the dot is then purely
   *  decorative and MUST NOT re-announce the status a second time. */
  decorative?: boolean;
}): ReactElement {
  return (
    <SharedStatusDot
      tone={TONES[status] ?? "accent"}
      size={size}
      label={decorative ? undefined : status}
    />
  );
}
