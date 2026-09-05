"use client";
import { type ReactElement, useState } from "react";
import { ResizableSplit } from "@agentic-toolkit/ui/components/resizable-split";
import { useStatus } from "../hooks/use-status";
import { useUptime } from "../hooks/use-uptime";
import { useLiveSnapshot } from "../hooks/use-live-snapshot";
import { useBoard } from "../hooks/use-board";
import { useIntegrations } from "../hooks/use-integrations";
import { computeSelfCheck } from "../lib/self-check";
import type { UptimeDay } from "../types";
import { summarizeByPlatform } from "../lib/deploy-view";
import { timeAgo } from "../lib/time-ago";
import { useNow } from "../hooks/use-now";
import { KpiStrip } from "./KpiStrip";
import { SelfCheckBanner } from "./SelfCheckBanner";
import { StatusMatrix } from "./StatusMatrix";
import { DetailPanel } from "./DetailPanel";
import { GlobalPanel } from "./GlobalPanel";
import { StatusDot } from "./StatusDot";
import { hostOf } from "../lib/url";

import { COLORS, PALETTE, envBadgeLabel, envColor } from "../lib/colors";
const SPLIT_KEY = "adh-status-split";
const DEFAULT_RATIO = 0.56;
const MIN_RATIO = 0.2;
const MAX_RATIO = 0.85;

export function Dashboard(): ReactElement {
  const status = useStatus();
  const uptime = useUptime(90);
  // Deploys come from the live transport (no DB) — the same singleton the
  // Overview reads. Problem count comes from the board, the same read the
  // Overview and the header pill use.
  const store = useLiveSnapshot();
  const { board } = useBoard();
  const integrationsQuery = useIntegrations();

  // Selection by endpoint slug (one row = one env endpoint)
  const [selectedSlug, setSelectedSlug] = useState<string | null>(null);

  // Loading / error states
  const isLoading = status.isLoading;
  const hasError = status.error || !status.data;

  const services = status.data?.services ?? [];
  const deploys = store.snapshot?.deployments ?? [];
  // Backend probe cadence — threaded to the deploy panels so they demote a stale
  // in-flight deploy on the same cadence-scaled clock the activity list uses.
  const probeIntervalMs = store.snapshot?.probeIntervalMs;

  // "All clear": the BOARD says the portfolio is operational → show a big faint green
  // ✓ behind the matrix. This used to be re-derived from /api/status services + live
  // deploys, which made the watermark a SECOND producer of "everything is fine": a
  // board problem with no matching monitored endpoint — a platform-unreachable
  // provider, a Crunchy cluster (which by design owns no roster entry), a project with
  // no probe — left the ✓ painted while the Problems list beside it was non-empty.
  // `board === null` — for any reason `BoardUnavailableReason` lists — paints NOTHING:
  // unknown is not clear, and a ✓ from an absence of data is exactly the forbidden
  // claim. One producer, one verdict.
  const allClear = board?.indicator === "operational";

  // ENDPOINT counts, from /api/status. Deliberately NOT the strip's headline verdict:
  // /api/status sees endpoint health only, while the board also raises
  // platform-unreachable, Crunchy and stale-prod problems, so these can legitimately all
  // read "up" during a real incident. They are labelled as endpoint counts in the strip
  // for exactly that reason.
  const up = services.filter((s) => s.status === "healthy").length;
  const degraded = services.filter((s) => s.status === "degraded").length;
  const down = services.filter((s) => s.status === "down" || s.status === "unknown").length;
  const total = services.length;

  const nowMs = useNow();
  const platforms = summarizeByPlatform(deploys, nowMs, probeIntervalMs);
  // The strip's TWO board-derived facts, both from `board` and both null together —
  // Fix Round 2 item C7: the headline verdict used to come from /api/status while the
  // incident count came from the board, so the most prominent element on the page could
  // print "OPERATIONAL" beside "⚠ 3 incidents". One producer, one verdict, one null.
  // `useBoard` already folds every unavailability cause into that one null board (see
  // `BoardUnavailableReason`), so this is the whole test. Null is NOT 0 and NOT
  // operational — see KpiStripProps.
  const portfolioVerdict = board ? board.indicator : null;
  const activeIncidentCount = board ? board.problems.length : null;
  const updatedLabel = status.data?.checkedAt ? `updated ${timeAgo(status.data.checkedAt, nowMs)} ago` : "—";

  const integrationsData = integrationsQuery.data;
  // Count issues the SAME way the SelfCheckBanner does (reachability chips + missing-env
  // vars, minus the internal cron check) so the pill and the bar never disagree.
  const selfCheckView = computeSelfCheck(integrationsData);
  const selfCheck = integrationsData
    ? {
        overall: integrationsData.overall,
        issues: selfCheckView ? selfCheckView.issues.length + selfCheckView.missingEnv.length : 0,
      }
    : undefined;

  // Build uptimeBySlug map (keyed by slug, covers all env endpoints)
  const uptimeBySlug = new Map<string, UptimeDay[]>(
    (uptime.data?.services ?? []).map((s) => [s.slug, s.daily]),
  );

  // Toggle selection: clicking a selected row again deselects
  function handleSelect(slug: string) {
    setSelectedSlug((prev) => (prev === slug ? null : slug));
  }

  // Resolve selected endpoint data
  const selectedSvc = selectedSlug
    ? services.find((s) => s.slug === selectedSlug)
    : undefined;

  // Uptime for the selected endpoint slug
  const selectedUptime = selectedSlug
    ? uptime.data?.services.find((s) => s.slug === selectedSlug)
    : undefined;

  return (
    <div style={{
      display: "flex",
      flexDirection: "column",
      flex: 1,
      minHeight: 0,
      width: "100%",
      background: PALETTE.bg,
      color: PALETTE.text,
      fontFamily: "var(--mono,ui-monospace,monospace)",
      fontSize: 13,
      lineHeight: 1.2,
    }}>
      {/* KPI strip — always rendered */}
      <KpiStrip
        overall={portfolioVerdict}
        up={up}
        degraded={degraded}
        down={down}
        total={total}
        platforms={platforms}
        incidents={activeIncidentCount}
        updatedLabel={updatedLabel}
        selfCheck={selfCheck}
      />

      {/* Self-check banner — only visible when there are integration issues */}
      <SelfCheckBanner data={integrationsData} />

      {/* Loading / error body */}
      {isLoading && (
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", color: PALETTE.muted, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 13 }}>
          Loading…
        </div>
      )}
      {!isLoading && hasError && (
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", color: PALETTE.red, fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 13, padding: "0 16px", textAlign: "center" }}>
          {status.error?.message ? `Failed to load status — ${status.error.message}` : "Failed to load status."}
        </div>
      )}

      {/* Split region: matrix top + detail bottom — the shared ResizableSplit,
          with the divider as the detail pane's header bar (identity when a row
          is selected, "All providers" otherwise). */}
      {!isLoading && !hasError && (
        <ResizableSplit
          className="min-h-0 flex-1"
          storageKey={SPLIT_KEY}
          defaultRatio={DEFAULT_RATIO}
          minRatio={MIN_RATIO}
          maxRatio={MAX_RATIO}
          bottomLabel="Endpoint details"
          header={
            selectedSlug ? (
              <span style={{ display: "inline-flex", alignItems: "center", gap: 8, minWidth: 0 }}>
                {selectedSvc && <StatusDot status={selectedSvc.status === "unknown" ? "down" : selectedSvc.status} size={8} />}
                <span style={{ color: PALETTE.text, fontWeight: 600, fontSize: 12 }}>
                  {selectedSvc ? hostOf(selectedSvc.url) : selectedSlug}
                </span>
                {selectedSvc?.environment && (
                  <span
                    style={{
                      fontSize: 10,
                      color: envColor(selectedSvc.environment),
                      border: `1px solid color-mix(in srgb, ${envColor(selectedSvc.environment)} 33%, transparent)`,
                      borderRadius: 4,
                      padding: "0 6px",
                    }}
                  >
                    {envBadgeLabel(selectedSvc.environment)}
                  </span>
                )}
              </span>
            ) : (
              <span style={{ color: PALETTE.text, fontWeight: 600, fontSize: 12 }}>All providers</span>
            )
          }
          headerActions={
            selectedSvc ? (
              <a
                href={selectedSvc.url.replace(/\/health$/, "")}
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: PALETTE.blue, textDecoration: "none", fontSize: "10.5px", whiteSpace: "nowrap" }}
              >
                open ↗
              </a>
            ) : undefined
          }
          top={
            /* relative + overflow:hidden so the all-clear watermark stays fixed
               in the visible viewport while the table scrolls over it. */
            <div style={{ position: "relative", height: "100%", overflow: "hidden" }}>
              {allClear && (
                <div
                  aria-hidden
                  style={{
                    position: "absolute",
                    inset: 0,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    pointerEvents: "none",
                    zIndex: 0,
                  }}
                >
                  <span style={{ fontSize: 300, lineHeight: 1, color: PALETTE.green, opacity: 0.1, fontWeight: 700 }}>✓</span>
                </div>
              )}
              <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: "2px 8px 0", zIndex: 1 }}>
                <StatusMatrix
                  services={services}
                  uptimeBySlug={uptimeBySlug}
                  deploys={deploys}
                  selectedSlug={selectedSlug}
                  onSelect={handleSelect}
                />
              </div>
            </div>
          }
          bottom={
            <div style={{ height: "100%", background: COLORS.surfaceDeep, display: "flex", flexDirection: "column" }}>
              {selectedSlug ? (
                <DetailPanel
                  selectedSlug={selectedSlug}
                  svc={selectedSvc}
                  uptime={selectedUptime}
                  deploys={deploys}
                  probeIntervalMs={probeIntervalMs}
                />
              ) : (
                <GlobalPanel platforms={platforms} />
              )}
            </div>
          }
        />
      )}

      {/* Legend footer */}
      <div style={{
        flex: "0 0 auto", display: "flex", gap: 16, alignItems: "center",
        padding: "6px 16px", borderTop: `1px solid ${COLORS.border}`,
        fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, color: PALETTE.dim,
        background: COLORS.surfaceDeep,
      }}>
        <span><span style={{ display: "inline-block", width: 9, height: 9, borderRadius: "50%", background: PALETTE.green, marginRight: 5, verticalAlign: "middle" }} />healthy</span>
        <span><span style={{ display: "inline-block", width: 9, height: 9, borderRadius: "50%", background: PALETTE.amber, marginRight: 5, verticalAlign: "middle" }} />degraded</span>
        <span><span style={{ display: "inline-block", width: 9, height: 9, borderRadius: "50%", background: PALETTE.red, marginRight: 5, verticalAlign: "middle" }} />down</span>
        <span>click any row → detail below · click again to deselect · drag divider to resize</span>
        <span style={{ marginLeft: "auto" }}>▲ Vercel ☁ Cloudflare ⬢ Railway</span>
      </div>
    </div>
  );
}
