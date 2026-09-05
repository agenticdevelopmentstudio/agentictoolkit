"use client";
import type { ReactElement } from "react";
import type { CheckState } from "../types";
import { PALETTE } from "../lib/colors";

export interface SelfCheckPillProps {
  overall: CheckState;
  issues: number;
}

export function SelfCheckPill({ overall, issues }: SelfCheckPillProps): ReactElement {
  const isOk = overall === "ok";
  const color = isOk ? PALETTE.green : overall === "error" ? PALETTE.red : PALETTE.amber;
  const label = isOk ? "✓ checks" : `⚠ ${issues} issue${issues !== 1 ? "s" : ""}`;

  return (
    <span style={{
      fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11,
      color,
      fontWeight: isOk ? 400 : 700,
    }}>
      {label}
    </span>
  );
}
