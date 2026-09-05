import { type CSSProperties, type ReactElement, type ReactNode } from "react";
import { COLORS, PALETTE, envBadgeLabel, envColor } from "../lib/colors";
import { platformLabel, platformColor } from "../lib/deploy-display";
import { hostOf } from "../lib/url";
import { CopyButton } from "@agentic-toolkit/ui/components/copy-button";
import { ProjLink } from "./ProjLink";

// Line layout: [glyph] [ENV] [title→link] …flex… [copy?] [status "<word> on <platform>"] [time slot].
// The time sits in a fixed-width column at the FAR RIGHT (after the status), and the
// optional per-row copy button (Problems only) sits just BEFORE the status word.
const ENV_BADGE_WIDTH = 25;
const BADGE_GAP = 6;
const TIME_SLOT_WIDTH = 68;

const GOOD = PALETTE.green;
const BAD = PALETTE.red;

/** The leading status indicator: green check when good, red stop sign when failed,
 * a small amber dot for in-progress/degraded/canceled. */
function StatusGlyph({ color }: { color: string }): ReactElement {
  const common = { flexShrink: 0, marginRight: 8, display: "block" as const };
  if (color === GOOD) {
    return (
      <svg width="15" height="15" viewBox="0 0 100 100" aria-hidden style={common}>
        <circle cx="50" cy="50" r="46" fill={GOOD} />
        <path d="M29 51 L44 67 L73 32" fill="none" stroke={COLORS.signRim} strokeWidth="11" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (color === BAD) {
    return (
      <svg width="15" height="15" viewBox="0 0 100 100" aria-hidden style={common}>
        <polygon points="30.96,4 69.04,4 96,30.96 96,69.04 69.04,96 30.96,96 4,69.04 4,30.96" fill={BAD} />
        <rect x="26" y="43" width="48" height="13" rx="3" fill={COLORS.signRim} />
      </svg>
    );
  }
  return <span aria-hidden style={{ width: 8, height: 8, borderRadius: "50%", background: color, boxShadow: `0 0 6px color-mix(in srgb, ${color} 40%, transparent)`, marginRight: 11, marginLeft: 3, flexShrink: 0, display: "inline-block" }} />;
}

export interface StatusRowProps {
  /** Hosting platform — drives the "on <platform>" suffix + its colour. */
  platform?: string;
  /** Rendered as a colored ENV badge after the glyph. */
  environment?: string | null;
  /** Project / endpoint title. */
  name: string;
  /** What's happening ("deploy failed", "deployed", "down"). */
  statusWord: string;
  statusColor: string;
  statusBold?: boolean;
  /** Relative time (precomputed by the caller) — fixed slot at the far right. */
  timeLabel?: string | null;
  /** When provided, a copy button is rendered just before the status word — used by
   *  the Problems list so each problem's full diagnostics (logs, links, commit) can
   *  be copied without opening the details pane. Absent → no per-row copy button. */
  copyGetText?: () => string;
  /** Deployment page link target. */
  sourceUrl?: string | null;
  /** Live deployed/checked url. */
  liveUrl?: string | null;
  /** Selected → highlighted; a click anywhere not on a link calls onSelect. */
  selected?: boolean;
  onSelect?: () => void;
  /** DOM id — lets the owning listbox target the row for aria-activedescendant + scroll. */
  id?: string;
}

export function StatusRow({
  platform,
  environment,
  name,
  statusWord,
  statusColor,
  statusBold = false,
  timeLabel,
  copyGetText,
  sourceUrl,
  liveUrl,
  selected = false,
  onSelect,
  id,
}: StatusRowProps): ReactElement {
  const envHue = envColor(environment);
  const badgeText = environment ? envBadgeLabel(environment) : null;
  const isEndpoint = platform === "http" || platform === "dns";
  const titleUrl = liveUrl ?? sourceUrl ?? null;
  const urlTitle = isEndpoint && titleUrl ? hostOf(titleUrl) : null;
  const envLink = isEndpoint ? titleUrl : liveUrl ?? null;
  const deployTitleHref = sourceUrl ?? liveUrl ?? null;
  const isResolved = statusWord.startsWith("[");
  const platformName = !isEndpoint && platform && !isResolved ? platformLabel(platform).toLowerCase() : null;
  const platformHue = platform ? platformColor(platform) : PALETTE.muted;
  const statusInner: ReactNode = platformName ? (
    <>
      {statusWord} on <span style={{ color: platformHue }}>{platformName}</span>
    </>
  ) : (
    statusWord
  );
  const linkStatus = !isEndpoint && Boolean(sourceUrl);

  // The name is the only elastic item in the row, so on a narrow panel it absorbs the
  // whole shortfall — and with `min-width: 0` it absorbed it all the way to ZERO,
  // leaving a problem row that never says WHICH project is broken (a long status like
  // "build failed on railway" was enough to do it inside a half-width Problems panel).
  // A floor keeps the identity legible-or-ellipsized but never gone; the status message
  // gives up the rest, since the glyph's colour already carries good-vs-failed.
  const nameStyle: CSSProperties = {
    color: PALETTE.text, flex: "0 1 auto", minWidth: "6ch", marginLeft: BADGE_GAP, marginRight: "auto",
    overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  };
  const statusStyle: CSSProperties = {
    color: statusColor, fontWeight: statusBold ? 700 : 500, flexShrink: 1, minWidth: 0,
    overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  };

  return (
    <div
      id={id}
      role="option"
      aria-selected={selected}
      onClick={onSelect}
      style={{
        display: "flex", alignItems: "center", padding: "5px 8px", cursor: "pointer",
        // Selected → a LIGHTER raised surface (apt-surface-2) than the panel's
        // apt-surface bg, not a darker one.
        background: selected ? COLORS.surfaceHover : "transparent",
        borderBottom: `1px solid ${COLORS.border}`,
        borderLeft: `2px solid ${selected ? statusColor : "transparent"}`,
        fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 12.5,
      }}
    >
      <StatusGlyph color={statusColor} />
      {badgeText ? (
        (() => {
          const envBadgeStyle: CSSProperties = {
            flexShrink: 0, width: ENV_BADGE_WIDTH, boxSizing: "border-box", textAlign: "left",
            padding: "1px 0", fontSize: "9.5px", fontWeight: 700, letterSpacing: "0.05em", color: envHue,
          };
          return envLink ? (
            <ProjLink title={`open the ${environment} site`} href={envLink} style={{ ...envBadgeStyle, cursor: "pointer" }}>{badgeText}</ProjLink>
          ) : (
            <span style={envBadgeStyle}>{badgeText}</span>
          );
        })()
      ) : (
        <span style={{ flexShrink: 0, width: ENV_BADGE_WIDTH }} />
      )}
      {urlTitle && titleUrl ? (
        <ProjLink href={titleUrl} title={titleUrl} style={nameStyle}>{urlTitle}</ProjLink>
      ) : deployTitleHref ? (
        <ProjLink title={sourceUrl ? "view deployment" : "open the live site"} href={deployTitleHref} style={{ ...nameStyle, cursor: "pointer" }}>{name}</ProjLink>
      ) : (
        <span title={name} style={nameStyle}>{name}</span>
      )}
      {copyGetText && (
        <span
          style={{ flexShrink: 0, marginRight: 6, display: "inline-flex" }}
          // Row click selects; the copy button must not also trigger selection.
          onClick={(e) => e.stopPropagation()}
        >
          <CopyButton getText={copyGetText} label="copy problem details" />
        </span>
      )}
      {linkStatus && sourceUrl ? (
        <ProjLink href={sourceUrl} title="open the deployment" style={{ ...statusStyle, cursor: "pointer" }}>{statusInner}</ProjLink>
      ) : (
        <span style={statusStyle}>{statusInner}</span>
      )}
      {timeLabel && (
        <span style={{ width: TIME_SLOT_WIDTH, maxWidth: TIME_SLOT_WIDTH, flexShrink: 0, textAlign: "right", paddingLeft: 10, color: PALETTE.dim, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", fontSize: 11.5 }}>{timeLabel}</span>
      )}
    </div>
  );
}
