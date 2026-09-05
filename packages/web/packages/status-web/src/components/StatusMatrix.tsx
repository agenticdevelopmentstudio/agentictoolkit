"use client";
import { Fragment, useMemo, type ReactElement } from "react";
import type { ServiceStatusDTO, UptimeDay, DeploymentDTO } from "../types";
import {
  latestTerminalForEndpoint,
  failuresForEndpoint,
} from "../lib/deploy-view";
import { hostOf } from "../lib/url";
import { platformGlyph, deployStatusColor } from "../lib/deploy-display";
import { COLORS, PALETTE, TINT, envBadgeLabel, envColor } from "../lib/colors";
import { timeAgo } from "../lib/time-ago";
import { useNow } from "../hooks/use-now";
import { StatusDot } from "./StatusDot";
import { UptimeBar } from "./UptimeBar";

export interface StatusMatrixProps {
  services: ServiceStatusDTO[];
  uptimeBySlug: Map<string, UptimeDay[]>;
  deploys: DeploymentDTO[];
  selectedSlug: string | null;
  onSelect(slug: string): void;
}

interface GroupedRows {
  group: string;
  rows: ServiceStatusDTO[];
}

/** Group the services by their own `group`, preserving first-seen order. */
function groupServices(services: ServiceStatusDTO[]): GroupedRows[] {
  const order: string[] = [];
  const byGroup = new Map<string, ServiceStatusDTO[]>();
  for (const svc of services) {
    let bucket = byGroup.get(svc.group);
    if (!bucket) {
      bucket = [];
      byGroup.set(svc.group, bucket);
      order.push(svc.group);
    }
    bucket.push(svc);
  }
  return order.map((group) => ({ group, rows: byGroup.get(group)! }));
}

/** Short env tag label */
export function StatusMatrix({
  services,
  uptimeBySlug,
  deploys,
  selectedSlug,
  onSelect,
}: StatusMatrixProps): ReactElement {
  const grouped = useMemo(() => groupServices(services), [services]);
  const nowMs = useNow();

  return (
    <table style={{ width: "100%", borderCollapse: "collapse", tableLayout: "fixed", position: "relative", zIndex: 1, background: "transparent" }}>
      <thead>
        <tr>
          <th style={thStyle}>Host</th>
          <th style={{ ...thStyle, width: 40 }}>Env</th>
          <th style={{ ...thStyle, ...respStyle }}>Resp</th>
          <th style={{ ...thStyle, width: 108 }}>Uptime 90d</th>
          <th style={{ ...thStyle, width: 100 }}>Deploy</th>
          <th style={{ ...thStyle, width: 46 }}>Fails</th>
        </tr>
      </thead>
      <tbody>
        {grouped.map(({ group, rows }) => (
          <Fragment key={group}>
            <tr style={grpRowStyle}>
              <td colSpan={6} style={{ padding: "8px 8px 0", height: 21, borderBottom: `1px solid ${COLORS.border}` }}>
                <span style={{
                  fontFamily: "var(--mono,ui-monospace,monospace)",
                  fontSize: "9.5px",
                  letterSpacing: "0.14em",
                  textTransform: "uppercase",
                  color: PALETTE.dim,
                }}>
                  {group}
                </span>
              </td>
            </tr>
            {rows.map((svc) => {
              const isSelected = selectedSlug === svc.slug;
              const isDown = svc.status === "down" || svc.status === "unknown";
              const isDeg = svc.status === "degraded";

              // Correlate deploys to this endpoint by its url host (liveHost).
              const latestDeploy = latestTerminalForEndpoint(deploys, svc);
              const failures = failuresForEndpoint(deploys, svc);

              // Row accent — selected wins; down/degraded; failures-only (up but failed builds)
              let rowBg = "transparent";
              let rowShadow = "none";
              if (isSelected) {
                rowBg = TINT.blueBgMed;
                rowShadow = `inset 3px 0 0 ${PALETTE.blue}`;
              } else if (isDown) {
                rowBg = TINT.redBgMed;
                rowShadow = `inset 3px 0 0 ${PALETTE.red}`;
              } else if (isDeg) {
                rowBg = TINT.amberTint;
                rowShadow = `inset 3px 0 0 ${PALETTE.amber}`;
              } else if (failures > 0) {
                // Up but build failures — red left edge, no tint
                rowShadow = `inset 3px 0 0 ${PALETTE.red}`;
              }

              const rowStyle: React.CSSProperties = {
                ...svcRowStyle,
                background: rowBg,
                boxShadow: rowShadow,
              };

              const hostColor = isSelected ? COLORS.white : (isDeg || isDown) ? PALETTE.text : COLORS.textSoft;
              const hostWeight = (isDeg || isDown || isSelected) ? 600 : undefined;

              // Response time
              const respMs = svc.responseTimeMs;
              const respLabel = respMs != null ? `${respMs}ms` : "—";
              const isSlow = respMs != null && respMs > 1000;

              // Uptime bar data
              const daily = uptimeBySlug.get(svc.slug) ?? [];

              return (
                <tr
                  key={svc.slug}
                  style={rowStyle}
                  onClick={() => onSelect(svc.slug)}
                >
                  {/* StatusDot + Host */}
                  <td style={{ ...tdStyle, display: "flex", alignItems: "center", gap: 7 }}>
                    <StatusDot status={svc.status} size={9} />
                    <span style={{
                      fontFamily: "var(--mono,ui-monospace,monospace)",
                      fontSize: 12,
                      color: hostColor,
                      fontWeight: hostWeight,
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}>
                      {hostOf(svc.url)}
                    </span>
                  </td>

                  {/* ENV tag */}
                  <td style={{ ...tdStyle, width: 62, overflow: "visible", whiteSpace: "nowrap" }}>
                    <span style={{
                      display: "inline-block",
                      fontFamily: "var(--mono,ui-monospace,monospace)",
                      fontSize: 9,
                      letterSpacing: "0.04em",
                      border: "1px solid",
                      borderRadius: 3,
                      padding: "1px 5px",
                      color: envColor(svc.environment),
                      borderColor: `color-mix(in srgb, ${envColor(svc.environment)} 33%, transparent)`,
                    }}>
                      {envBadgeLabel(svc.environment)}
                    </span>
                  </td>

                  {/* Response time */}
                  <td style={{ ...tdStyle, ...respStyle, color: isSlow ? PALETTE.amber : PALETTE.muted, fontSize: 11 }}>
                    {respLabel}
                  </td>

                  {/* Uptime bar */}
                  <td style={{ ...tdStyle, width: 108, paddingTop: 4, paddingBottom: 4 }}>
                    {daily.length > 0 ? (
                      <UptimeBar daily={daily} />
                    ) : (
                      <span style={{ color: PALETTE.dim, fontSize: 10, fontFamily: "var(--mono,ui-monospace,monospace)" }}>—</span>
                    )}
                  </td>

                  {/* Deploy: [fixed glyph slot] [status dot] [age] — every project gets a dot,
                       dot sits at a fixed column so they line up. Status = latest terminal
                       (success/failed), canceled/building ignored; yellow when none. */}
                  <td style={{ ...tdStyle, width: 100, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, color: PALETTE.muted }}>
                    <span style={{ display: "inline-block", width: 12, textAlign: "center", color: PALETTE.dim, marginRight: 5 }}>
                      {latestDeploy ? platformGlyph(latestDeploy.platform) : ""}
                    </span>
                    <span style={{
                      display: "inline-block", width: 7, height: 7, borderRadius: "50%",
                      background: latestDeploy ? deployStatusColor(latestDeploy.status) : PALETTE.amber,
                      marginRight: 5, verticalAlign: "middle",
                    }} />
                    {latestDeploy ? timeAgo(latestDeploy.createdAt, nowMs) : "—"}
                  </td>

                  {/* Failures badge */}
                  <td style={{ ...tdStyle, width: 46, textAlign: "center" }}>
                    {failures > 0 ? (
                      <span style={{
                        fontFamily: "var(--mono,ui-monospace,monospace)",
                        fontSize: 10,
                        fontWeight: 700,
                        color: PALETTE.red,
                        background: TINT.redBgStrong,
                        border: `1px solid ${TINT.redBorder}`,
                        borderRadius: 4,
                        padding: "1px 5px",
                        whiteSpace: "nowrap",
                      }}>
                        {failures}✕
                      </span>
                    ) : (
                      <span style={{ color: COLORS.dimBlue, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 10 }}>—</span>
                    )}
                  </td>
                </tr>
              );
            })}
          </Fragment>
        ))}
      </tbody>
    </table>
  );
}

// --- shared cell styles ---
const thStyle: React.CSSProperties = {
  fontFamily: "var(--mono,ui-monospace,monospace)",
  fontSize: 10,
  letterSpacing: "0.06em",
  textTransform: "uppercase",
  color: PALETTE.dim,
  fontWeight: 500,
  textAlign: "left",
  padding: "5px 8px",
  borderBottom: `1px solid ${COLORS.border}`,
  position: "sticky",
  top: 0,
  background: PALETTE.bg,
};

const respStyle: React.CSSProperties = { width: 64, textAlign: "right", fontFamily: "var(--mono,ui-monospace,monospace)" };

const tdStyle: React.CSSProperties = {
  padding: "0 8px",
  height: 24,
  borderBottom: `1px solid ${COLORS.surfacePane}`,
  whiteSpace: "nowrap",
  overflow: "hidden",
  textOverflow: "ellipsis",
};

const svcRowStyle: React.CSSProperties = { cursor: "pointer" };
const grpRowStyle: React.CSSProperties = {};
