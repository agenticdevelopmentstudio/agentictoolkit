"use client";
import type { ReactElement } from "react";
import type { DeploymentDTO, DeployStatus } from "../types";
import { platformGlyph, deployStatusColor, deployStatusLabel } from "../lib/deploy-display";
import { deployDtoUnconfirmed } from "../lib/row-model";
import { shortSha } from "../lib/format";
import { timeAgo } from "../lib/time-ago";
import { useNow } from "../hooks/use-now";

import { COLORS, PALETTE, TINT } from "../lib/colors";
export interface DeployListProps {
  deploys: DeploymentDTO[];
  emptyLabel?: string;
  /** Backend probe cadence (snapshot.probeIntervalMs) — scales the demotion window so
   *  a stale in-flight deploy greys to "outcome unknown" in lockstep with the activity list. */
  probeIntervalMs?: number;
}

export function DeployList({ deploys, emptyLabel = "no recent deploys", probeIntervalMs }: DeployListProps): ReactElement {
  const nowMs = useNow();
  if (deploys.length === 0) {
    return (
      <div style={{ color: PALETTE.dim, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 12 }}>
        {emptyLabel}
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 0, overflow: "hidden" }}>
      {deploys.map((d) => {
        // An in-flight deploy nothing has re-confirmed demotes to a muted "outcome
        // unknown" — same rule the activity list applies — instead of asserting building.
        const status: DeployStatus = deployDtoUnconfirmed(d, nowMs, probeIntervalMs) ? "unknown" : d.status;
        const isIssue = status === "failed" || status === "building";
        const color = deployStatusColor(status);
        const label = deployStatusLabel(status);
        const glyph = platformGlyph(d.platform);
        const age = timeAgo(d.createdAt, nowMs);
        const sha = shortSha(d.commitHash) ?? "";

        return (
          <a
            key={d.id}
            href={d.url ?? "#"}
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: "flex", alignItems: "center", gap: 8, padding: "4px 0",
              borderBottom: `1px solid ${COLORS.border}`,
              fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11,
              textDecoration: "none", color: PALETTE.text,
              background: isIssue ? (status === "failed" ? TINT.redBg : TINT.blueBg) : "transparent",
            }}
          >
            {/* Status dot */}
            <span style={{
              width: 8, height: 8, borderRadius: "50%", flexShrink: 0,
              background: color, boxShadow: `0 0 4px color-mix(in srgb, ${color} 53%, transparent)`,
            }} />
            {/* Platform glyph */}
            <span style={{ color: PALETTE.dim, width: 12, textAlign: "center", flexShrink: 0 }}>{glyph}</span>
            {/* Project name */}
            <span style={{ color: PALETTE.text, flex: 1, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
              {d.projectName}
            </span>
            {/* Environment — the server-derived TIER, never `d.environment`: that is the
                provider's promotion target, "production" for every Vercel project, and
                rendering it here badged the entire testing fleet PROD. Null for a preview
                build, which belongs to no tier and so shows nothing, exactly as an empty
                `environment` did before. */}
            {d.tier && (
              <span style={{ color: PALETTE.dim, fontSize: 10 }}>{d.tier}</span>
            )}
            {/* Status */}
            <span style={{ color, fontWeight: status === "failed" ? 700 : undefined, fontSize: 10 }}>{label}</span>
            {/* Age */}
            <span style={{ color: PALETTE.dim, fontSize: 10 }}>{age}</span>
            {/* Short SHA */}
            {sha && <span style={{ color: PALETTE.dim, fontSize: 10 }}>{sha}</span>}
          </a>
        );
      })}
    </div>
  );
}
