"use client";
import { useMemo, useState, type ReactElement, type ReactNode } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { deleteEndpoint } from "../api/monitored-sites";
import { useLiveSnapshot } from "../hooks/use-live-snapshot";
import { useNow } from "../hooks/use-now";
import { COLORS, PALETTE, TINT } from "../lib/colors";
import { selectStaleMonitors, STALE_MONITOR_MS } from "../lib/stale-monitors";
import { timeAgo } from "../lib/time-ago";
import { hostOf } from "../lib/url";
import { plural } from "../lib/format";
import { Popover, PopoverTrigger, PopoverContent } from "@agentic-toolkit/ui/components/popover";
import { AlertModal } from "@agentic-toolkit/ui/components/alert-modal";
import { BANNER_MONO, bannerBarStyle, bannerColor, bannerTriggerClass } from "./banner-bar";
import { invalidateConfigQueries } from "../hooks/use-config-status";

const THRESHOLD_DAYS = Math.floor(STALE_MONITOR_MS / 86_400_000);

/** One monitor offered for removal. `id` is the endpoint id — both the React key and what
 *  `DELETE /config/endpoints/:id` takes; the rest is this row's copy. */
interface Row {
  id: string;
  title: ReactNode;
  detail: ReactNode;
  buttonTitle: string;
  confirmTitle: string;
  confirmDescription: string;
}

/**
 * Top-of-page surface for the ghosts the board can't settle by itself, and the two-step
 * removal behind them.
 *
 * Everything with conclusive evidence is already gone by the time this renders: the backend
 * cycle deletes a monitor no platform project claims any more, with no banner and nothing to
 * click. What reaches here is a judgement call — something still claimed (or exempt from the
 * rule entirely, like a `health` probe) that has been down for a week: a site nobody turned
 * off, or an outage nobody fixed. `selectStaleMonitors` owns that rule. Whether the host
 * resolves is not part of it; it only words the confirm.
 *
 * Because nothing here is provably dead, removal is never automatic: every row arms the
 * destructive confirm and nothing is deleted without the operator confirming THAT row.
 *
 * Selection is server-truth (each service's `downSince` = its open issue's openedAt),
 * durable across browsers. Silent when there's nothing to retire.
 * Mirrors {@link UnconfiguredProjectsBanner}.
 */
export function StaleMonitorsBanner(): ReactElement | null {
  const store = useLiveSnapshot();
  const nowMs = useNow();
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [pending, setPending] = useState<Row | null>(null);
  const [error, setError] = useState<string | null>(null);

  const services = store.snapshot?.services;
  // The 7-day threshold only changes at day granularity, so key the memo to the day
  // (not the 30s `nowMs` tick); using the day-floored "now" keeps ages stable too.
  const dayMs = Math.floor(nowMs / 86_400_000) * 86_400_000;
  const stale = useMemo(() => selectStaleMonitors(services ?? [], dayMs), [services, dayMs]);

  const rows: Row[] = stale.map((m) => {
    const host = hostOf(m.url) || m.url;
    const age = timeAgo(m.downSince, nowMs);
    const outcome =
      `This deletes the monitor (and its site if it has no other monitors). ` +
      `You can re-add it later from Configure.`;
    return {
      id: m.slug,
      title: (
        <a className="adh-projlink" href={m.url} target="_blank" rel="noopener noreferrer" title={`open ${m.url}`} style={rowTitleStyle}>
          {m.name || host}
        </a>
      ),
      detail: (
        <span style={rowDetailStyle}>
          {host}
          {m.environment ? ` · ${m.environment}` : ""} — down {age} · {m.detail}
        </span>
      ),
      buttonTitle: `Retire the monitor for ${host}`,
      confirmTitle: `Retire the monitor for ${host}?`,
      confirmDescription: m.dnsOk
        ? `It still resolves, but has been down ${age} — ${m.detail}. ${outcome}`
        : `${host} has not resolved for ${age}. That alone isn't proof the deployment is ` +
          `gone — a monitor is only removed automatically once no platform project claims ` +
          `it — so retiring this one is yours to decide. ${outcome}`,
    };
  });

  if (rows.length === 0) return null;

  async function remove(row: Row): Promise<void> {
    if (busy) return;
    setBusy(row.id);
    try {
      // The backend deletes the endpoint and, atomically, its site if that leaves it empty.
      await deleteEndpoint(row.id);
      // Keep the rest of the app (Configure page, banners) consistent, then force a RE-READ
      // of /api/live so the cleared monitor also leaves Problems and this banner. (Not
      // store.refresh() — that asks the backend to run a fresh CHECK, which is debounce-able
      // and overkill; a deletion is reflected by a re-read.)
      await invalidateConfigQueries(queryClient);
      await queryClient.refetchQueries({ queryKey: ["live"] });
    } catch (e) {
      setError(`Retire failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <div style={bannerBarStyle("red")}>
      <Popover>
        <PopoverTrigger
          aria-label="Review monitors that have been down long enough to retire"
          className={bannerTriggerClass("red")}
        >
          {`🗑 RETIRE: ${plural(stale.length, "stale monitor")} down ${THRESHOLD_DAYS}d+`}
          <span aria-hidden style={{ opacity: 0.7 }}>▾</span>
        </PopoverTrigger>
        <PopoverContent align="start" sideOffset={6} className="w-auto p-1.5" style={{ minWidth: 320, maxWidth: 480 }}>
          <div style={{ maxHeight: 360, overflowY: "auto", display: "flex", flexDirection: "column", gap: 4 }}>
            <div style={{ fontFamily: BANNER_MONO, fontSize: 10, fontWeight: 700, letterSpacing: "0.06em", color: bannerColor("red"), padding: "2px 6px" }}>
              {`🗑 DOWN ${THRESHOLD_DAYS}d+`} · {rows.length}
            </div>
            {rows.map((row) => {
              const working = busy === row.id;
              return (
                <div key={row.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 6px", borderRadius: 6 }}>
                  <div style={{ display: "flex", flexDirection: "column", minWidth: 0, flex: 1 }}>{row.title}{row.detail}</div>
                  <button
                    type="button"
                    onClick={() => setPending(row)}
                    disabled={busy !== null}
                    title={row.buttonTitle}
                    style={{
                      appearance: "none",
                      background: COLORS.surfaceDeep,
                      border: `1px solid ${TINT.redBorder}`,
                      borderRadius: 6,
                      color: busy !== null && !working ? PALETTE.dim : PALETTE.red,
                      cursor: busy !== null ? "not-allowed" : "pointer",
                      fontFamily: BANNER_MONO,
                      fontSize: 11,
                      fontWeight: 700,
                      whiteSpace: "nowrap",
                      padding: "4px 10px",
                      flexShrink: 0,
                    }}
                  >
                    {working ? "retiring…" : "Retire"}
                  </button>
                </div>
              );
            })}
          </div>
        </PopoverContent>
      </Popover>
      <span style={{ fontFamily: BANNER_MONO, fontSize: 11.5, color: bannerColor("red") }}>
        {"down for weeks and nothing says it was deleted — only you know if it should still be monitored"}
      </span>
      {pending && (
        <AlertModal
          open
          title={pending.confirmTitle}
          description={pending.confirmDescription}
          tone="error"
          destructive
          confirmLabel="Retire"
          cancelLabel="Cancel"
          onConfirm={() => {
            const row = pending;
            setPending(null);
            void remove(row);
          }}
          onCancel={() => setPending(null)}
        />
      )}
      <AlertModal
        open={error !== null}
        title="Retire failed"
        description={error}
        tone="error"
        onConfirm={() => setError(null)}
      />
    </div>
  );
}

/** The row's primary line, styled like every other banner row. */
const rowTitleStyle = { fontFamily: BANNER_MONO, fontSize: 12, color: PALETTE.text, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } as const;

/** The row's muted second line. */
const rowDetailStyle = { fontFamily: BANNER_MONO, fontSize: 10.5, color: COLORS.textFaint, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } as const;
