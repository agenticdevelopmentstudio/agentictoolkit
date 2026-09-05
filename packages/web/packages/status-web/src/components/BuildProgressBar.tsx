"use client";
import type { ReactElement } from "react";
import { Progress } from "@agentic-toolkit/ui/components/progress";
import type { BuildProgress } from "../hooks/use-build-progress";

import { PALETTE } from "../lib/colors";
const mono = "var(--mono,ui-monospace,monospace)";

/**
 * The build-activity progress bar shown in the Recent Activity header while
 * projects are building. Reports completed/total of the current build cohort and
 * the percentage; turns green and holds for a beat when the burst finishes
 * (driven by {@link useBuildProgress}, which also hides it afterwards).
 */
export function BuildProgressBar({ progress }: { progress: BuildProgress }): ReactElement | null {
  if (!progress.visible) return null;
  const { completed, total, pct, complete } = progress;
  // Compact (this lives in a half-width panel header): the amber/green bar color
  // carries "building" vs "built", so the label is just the counts + percent.
  return (
    <div
      role="group"
      aria-label="build progress"
      title={`${complete ? "built" : "building"} ${completed} of ${total} (${pct}%)`}
      // .adh-panel-progress carries display + max-width in CSS rather than inline, so
      // the header's container query can NARROW the bar on a half-width panel (the
      // counts and percent keep their size; the track gives up the difference). It
      // shrinks rather than hides because an in-flight build is the one thing this
      // header exists to report — unlike the countdown and monitor sha beside it,
      // which stand down entirely.
      className="adh-panel-progress"
      style={{ gap: 6, width: "100%", minWidth: 0, fontFamily: mono }}
    >
      <span style={{ fontSize: 11, color: complete ? PALETTE.green : PALETTE.amber, whiteSpace: "nowrap" }}>{completed}/{total}</span>
      <Progress value={pct} className="h-1.5 flex-1 min-w-[24px]" indicatorClassName={complete ? "bg-apt-green" : "bg-apt-gold"} />
      <span style={{ fontSize: 11, color: PALETTE.muted, whiteSpace: "nowrap" }}>{pct}%</span>
    </div>
  );
}
