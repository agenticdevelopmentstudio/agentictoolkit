"use client";
import type { ReactElement } from "react";
import type { ServiceStatusDTO, UptimeService, DeploymentDTO } from "../types";
import { deploysForEndpoint } from "../lib/deploy-view";
import { COLORS, PALETTE } from "../lib/colors";
import { useHistory } from "../hooks/use-history";
import { ResponseChart } from "./ResponseChart";
import { ChecksStrip } from "./ChecksStrip";
import { DeployList } from "./DeployList";
import { paneStyle } from "./panel-styles";
import { sectionLabelClass } from "@agentic-toolkit/ui/components/section-label";

export interface DetailPanelProps {
  /** Slug of the selected endpoint (single env). */
  selectedSlug: string;
  /** The one ServiceStatusDTO for this endpoint. */
  svc: ServiceStatusDTO | undefined;
  uptime?: UptimeService;
  deploys: DeploymentDTO[];
  /** Backend probe cadence (snapshot.probeIntervalMs) — forwarded to DeployList so a
   *  stale in-flight deploy greys out on the same clock as the rest of the board. */
  probeIntervalMs?: number;
}

export function DetailPanel({
  selectedSlug,
  svc,
  uptime,
  deploys,
  probeIntervalMs,
}: DetailPanelProps): ReactElement {
  const history = useHistory(selectedSlug);

  // Deploy list for this specific endpoint — correlated by its url host (liveHost).
  const endpointDeploys = svc ? deploysForEndpoint(deploys, svc) : [];

  // Response chart data from history
  const checks = history.data?.checks ?? [];
  const respPoints = checks.map((c) => c.responseTimeMs);
  const stripStatuses = checks.map((c): "healthy" | "degraded" | "down" =>
    c.status === "healthy" ? "healthy" : c.status === "degraded" ? "degraded" : "down",
  );

  // Chart color from current status
  const isDown = svc?.status === "down" || svc?.status === "unknown";
  const isDeg = svc?.status === "degraded";
  const chartColor = isDown ? PALETTE.red : isDeg ? PALETTE.amber : PALETTE.blue;

  const uptimePct = uptime?.uptimePercent;
  const uptimeLabel = uptimePct != null ? `${uptimePct.toFixed(2)}%` : "—";
  const uptimeColor =
    uptimePct != null && uptimePct < 99
      ? uptimePct < 95
        ? PALETTE.red
        : PALETTE.amber
      : PALETTE.green;

  return (
    // The pane's identity (host, env badge, open link) lives on the split's
    // header bar (Dashboard passes it) — this is just the body.
    <div style={{ flex: 1, minHeight: 0, overflow: "hidden", display: "flex", flexDirection: "column" }}>
      {/* Body: 3-pane grid */}
      <div style={{
        flex: "1 1 auto", overflow: "hidden", display: "grid",
        gridTemplateColumns: "1.4fr 1fr 1.1fr", gap: 0,
      }}>
        {/* Pane 1: Response time chart + uptime */}
        <div style={paneStyle}>
          <h4 className={sectionLabelClass}>Response time · 24h</h4>
          {history.isLoading ? (
            <div style={{ color: PALETTE.dim, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11 }}>loading…</div>
          ) : (
            <ResponseChart points={respPoints} color={chartColor} />
          )}
          <div style={{ display: "flex", gap: 16, alignItems: "baseline" }}>
            <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 20, color: uptimeColor }}>{uptimeLabel}</span>
            <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 10, color: PALETTE.dim }}>uptime 90d</span>
          </div>
        </div>

        {/* Pane 2: Recent checks + incidents */}
        <div style={{ ...paneStyle, borderRight: `1px solid ${COLORS.border}` }}>
          <h4 className={sectionLabelClass}>Recent checks · last {stripStatuses.length || 40}</h4>
          {stripStatuses.length > 0 ? (
            <ChecksStrip statuses={stripStatuses} />
          ) : (
            <div style={{ color: PALETTE.dim, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11 }}>no check data</div>
          )}
        </div>

        {/* Pane 3: Deploys for this env endpoint */}
        <div style={{ ...paneStyle, borderRight: "none" }}>
          <h4 className={sectionLabelClass}>Deploys for this endpoint</h4>
          <div style={{ flex: 1, overflow: "hidden" }}>
            <DeployList deploys={endpointDeploys} emptyLabel="no deploys (token not set?)" probeIntervalMs={probeIntervalMs} />
          </div>
        </div>
      </div>
    </div>
  );
}
