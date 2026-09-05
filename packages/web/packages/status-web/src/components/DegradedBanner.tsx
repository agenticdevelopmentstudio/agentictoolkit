"use client";
import type { ReactElement } from "react";
import { PALETTE, TINT } from "../lib/colors";
export interface DegradedBannerProps {
  /** The raw DB reason (e.g. "BLOCKED: …"), shown as a chip when present. */
  reason?: string | null;
  /** One line describing what's live vs. cached on this particular view. */
  detail: string;
}

/**
 * The shared "database unavailable — live check only" banner. Amber (deliberately
 * distinct from the red problem signs) so it reads as "degraded mode", not "outage of
 * the monitored sites". Rendered on every view that can fall back to a live probe.
 */
export function DegradedBanner({ reason, detail }: DegradedBannerProps): ReactElement {
  return (
    <div style={{
      flex: "0 0 auto", display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap",
      padding: "8px 16px", background: TINT.amberBg, borderBottom: `1px solid ${TINT.amberBorder}`,
    }}>
      <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, fontWeight: 700, letterSpacing: "0.06em", color: PALETTE.amber, whiteSpace: "nowrap" }}>
        ⚠ DATABASE UNAVAILABLE — LIVE CHECK ONLY
      </span>
      <span style={{ fontSize: 12, color: PALETTE.muted }}>{detail}</span>
      {reason && (
        <span style={{
          fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11.5, color: PALETTE.amber,
          background: TINT.amberBgMed, border: `1px solid ${TINT.amberBorderStrong}`, borderRadius: 5, padding: "2px 8px",
          maxWidth: "60ch", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
        }}>
          {reason}
        </span>
      )}
    </div>
  );
}
