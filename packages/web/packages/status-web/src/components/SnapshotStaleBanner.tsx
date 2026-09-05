"use client";
import type { ReactElement } from "react";
import { useLiveSnapshot } from "../hooks/use-live-snapshot";
import { snapshotFreshness } from "../lib/snapshot-staleness";
import { timeAgo } from "../lib/time-ago";
import { BANNER_MONO, bannerBarStyle, bannerColor, type BannerTone } from "./banner-bar";

/**
 * Board-wide "the monitor stopped recording new checks" banner. `generatedAt` is
 * stamped at READ time so a frozen snapshot always looks fresh; `lastCycleAt` (newest
 * persisted probe) is the REAL freshness clock. When it lags `generatedAt` (measured
 * SERVER-side via {@link snapshotFreshness}, so the verdict is immune to client clock
 * skew and to tab-sleep throttling), the rows on screen are a frozen snapshot — e.g.
 * deploys stuck at "building" that actually finished — so we say so plainly instead of
 * letting stale data pose as live. Uses the shared `banner-bar` shell and the shared
 * staleness rule (which also drives the header/home status sign via
 * usePortfolioIndicator), so the banner and the sign can't disagree. Inert until a
 * probe exists (a zero-endpoint monitor, or an older backend that predates the field).
 */
export function SnapshotStaleBanner(): ReactElement | null {
  const { snapshot } = useLiveSnapshot();
  const lastCycleAt = snapshot?.lastCycleAt;
  if (!snapshot || !lastCycleAt) return null;
  const freshness = snapshotFreshness(lastCycleAt, snapshot.generatedAt, snapshot.probeIntervalMs);
  if (freshness === "fresh") return null;

  const tone: BannerTone = freshness === "very-stale" ? "red" : "amber";
  const color = bannerColor(tone);
  return (
    <div role="status" style={bannerBarStyle(tone)}>
      <span
        style={{
          fontFamily: BANNER_MONO,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: "0.06em",
          whiteSpace: "nowrap",
          color,
        }}
      >
        ⚠ MONITORING PAUSED
      </span>
      <span style={{ fontFamily: BANNER_MONO, fontSize: 11.5, color }}>
        status data last refreshed {timeAgo(lastCycleAt, Date.parse(snapshot.generatedAt))} — the
        monitor stopped recording new checks (a redeploy/restart resumes it); states below may be out
        of date.
      </span>
    </div>
  );
}
