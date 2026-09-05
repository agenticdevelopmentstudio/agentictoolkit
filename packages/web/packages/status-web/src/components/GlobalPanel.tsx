"use client";
import { useMemo, type ReactElement } from "react";
import type { PlatformSummary } from "../lib/deploy-view";
import type { Problem } from "../lib/board-types";
import { useBoard } from "../hooks/use-board";
import { problemToRow, type Row } from "../lib/row-model";
import { SOURCE_LABEL, type IssueSource } from "../lib/issue-sources";
import { platformGlyph } from "../lib/deploy-display";
import { timeAgo } from "../lib/time-ago";
import { useNow } from "../hooks/use-now";
import { paneStyle } from "./panel-styles";
import { sectionLabelClass } from "@agentic-toolkit/ui/components/section-label";

import { COLORS, PALETTE } from "../lib/colors";
export interface GlobalPanelProps {
  platforms: PlatformSummary[];
}

interface ProblemGroup {
  source: IssueSource;
  rows: Row[];
  /** Rows the board calls a problem outright (tone "bad"); the rest read as degraded. */
  criticalCount: number;
}

/**
 * Group the board's open problems by source (dns/http/vercel/cloudflare-pages/railway/
 * crunchy), sorted by group size desc. Replaces the old buildFailureGroups, which
 * filtered raw `DeploymentDTO[]` by projectName with no roster or orphan awareness at
 * all — a deploy provider going unreachable, or an endpoint down, never showed up here.
 * This reads the SAME `board.problems` the Overview tab's Problems panel renders, just
 * grouped by source for a fleet-wide view instead of a per-endpoint one.
 *
 * Groups ROWS, not problems: `problemToRow` runs exactly once per problem, so the group
 * header's critical count and the line rendered under it are two readings of one row
 * rather than two spellings of one problem. The counts are computed here, once, for the
 * same reason — the render body should do no derivation at all, because it re-runs on
 * every `useNow` tick while the grouping only changes when the board does.
 */
function groupProblemsBySource(problems: Problem[]): ProblemGroup[] {
  const map = new Map<IssueSource, Row[]>();
  for (const p of problems) {
    const row = problemToRow(p);
    const g = map.get(p.source);
    if (g) g.push(row);
    else map.set(p.source, [row]);
  }
  return [...map.entries()]
    .map(([source, rows]) => ({
      source,
      rows,
      // ASK the row rather than re-deriving `severity !== "minor"`. This used to be a
      // hand-copy of that rule with a comment promising it "mirrors" the original — two
      // derivations of one fact, where the copy stops agreeing the day the rule grows a
      // third case.
      criticalCount: rows.filter((r) => r.tone === "bad").length,
    }))
    .sort((a, b) => b.rows.length - a.rows.length);
}

export function GlobalPanel({ platforms }: GlobalPanelProps): ReactElement {
  const nowMs = useNow();
  const { board } = useBoard();
  // `board === null` means "the board hasn't come back yet (or never did)", never
  // "zero problems" — same distinction `usePortfolioIndicator` draws. Rendering the
  // green all-clear off a null board would be exactly C1's forbidden claim: a health
  // verdict from having NO data, not from having checked anything.
  // Keyed on the board alone: `useNow` re-renders this component every second, and the
  // grouping is a function of the board, not of the clock.
  const groups = useMemo(() => (board ? groupProblemsBySource(board.problems) : []), [board]);

  return (
    // The pane's identity ("All providers") lives on the split's header bar
    // (Dashboard passes it) — this is just the body.
    <div style={{ flex: 1, minHeight: 0, overflow: "hidden", display: "flex", flexDirection: "column" }}>
      {/* Body: 2-pane grid (issue lists are gone — problems live in the Overview
          activity list now; resolved history returns with the stats/DB rework) */}
      <div style={{
        flex: "1 1 auto", overflow: "hidden", display: "grid",
        gridTemplateColumns: "1.4fr 1fr", gap: 0,
      }}>
        {/* Pane 1: Problems by source */}
        <div style={paneStyle}>
          <h4 className={sectionLabelClass}>Problems by source</h4>
          {board === null ? (
            <div style={{ color: PALETTE.amber, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 12 }}>
              status unknown — board unavailable
            </div>
          ) : groups.length === 0 ? (
            <div style={{ color: PALETTE.green, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 12 }}>
              no problems ✓
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 10, overflowY: "auto", flex: 1 }}>
              {groups.map((g) => {
                const criticalCount = g.criticalCount;
                const minorCount = g.rows.length - criticalCount;
                const parts: string[] = [];
                if (criticalCount > 0) parts.push(`${criticalCount} problem${criticalCount === 1 ? "" : "s"}`);
                if (minorCount > 0) parts.push(`${minorCount} degraded`);
                return (
                  <div key={g.source}>
                    {/* Group header */}
                    <div style={{
                      fontFamily: "var(--mono,ui-monospace,monospace)",
                      fontSize: 11,
                      fontWeight: 700,
                      color: criticalCount > 0 ? PALETTE.red : PALETTE.amber,
                      marginBottom: 4,
                    }}>
                      {platformGlyph(g.source)} {SOURCE_LABEL[g.source]} — {parts.join(" · ")}
                    </div>
                    {/* Individual problems */}
                    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                      {g.rows.map((row) => {
                        const link = row.liveUrl ?? row.sourceUrl;
                        return (
                          <div key={row.key} style={{
                            display: "flex",
                            alignItems: "center",
                            gap: 6,
                            fontFamily: "var(--mono,ui-monospace,monospace)",
                            fontSize: 10.5,
                            color: PALETTE.muted,
                            paddingLeft: 8,
                          }}>
                            <span style={{
                              width: 6, height: 6, borderRadius: "50%",
                              background: row.tone === "bad" ? PALETTE.red : PALETTE.amber,
                              flexShrink: 0, display: "inline-block",
                            }} />
                            <span style={{ color: COLORS.textSoft, flexShrink: 0, maxWidth: "14ch", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                              {row.name}
                            </span>
                            {row.sha && (
                              <span style={{ color: PALETTE.dim, flexShrink: 0 }}>{row.sha}</span>
                            )}
                            <span style={{
                              flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                            }}>
                              {row.message ?? row.statusWord}
                            </span>
                            <span style={{ flexShrink: 0 }}>{timeAgo(row.at, nowMs)}</span>
                            {link && (
                              <a
                                href={link}
                                target="_blank"
                                rel="noopener noreferrer"
                                style={{ color: PALETTE.blue, textDecoration: "none", flexShrink: 0 }}
                              >
                                ↗
                              </a>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Pane 2: Build pipeline */}
        <div style={{ ...paneStyle, borderRight: "none" }}>
          <h4 className={sectionLabelClass}>Build pipeline</h4>
          <div style={{ display: "flex", gap: 16, alignItems: "baseline", flexWrap: "wrap" }}>
            {platforms.map((p) => (
              <span key={p.platform} style={{ display: "flex", gap: 8, alignItems: "baseline" }}>
                {p.ready > 0 && (
                  <>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 20, color: PALETTE.green }}>{p.ready}</span>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 10, color: PALETTE.dim }}>
                      {platformGlyph(p.platform)} ready
                    </span>
                  </>
                )}
                {p.building > 0 && (
                  <>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 20, color: PALETTE.blue }}>{p.building}</span>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 10, color: PALETTE.dim }}>building</span>
                  </>
                )}
                {p.failed > 0 && (
                  <>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 20, color: PALETTE.red }}>{p.failed}</span>
                    <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 10, color: PALETTE.dim }}>failed</span>
                  </>
                )}
              </span>
            ))}
            {platforms.length === 0 && (
              <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 12, color: PALETTE.dim }}>no deploy data</span>
            )}
          </div>

        </div>
      </div>
    </div>
  );
}
