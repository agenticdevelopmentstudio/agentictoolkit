import type { ReactElement } from "react";
import { Separator } from "@agentic-toolkit/ui/components/separator";
import type { CheckState } from "../types";
import type { Indicator } from "../lib/board-types";
import type { PlatformSummary } from "../lib/deploy-view";
import { StatusDot } from "./StatusDot";
import { platformGlyph, platformLabelShort } from "../lib/deploy-display";
import { SelfCheckPill } from "./SelfCheckPill";

/**
 * The board's indicator as this strip says it, in the words and the dot the rest of the
 * site already uses. `null` — the board could not back a claim — is UNKNOWN, never
 * operational. The dot word is `StatusDot`'s vocabulary, not the board's: the board says
 * `outage` where the dot's tone table says `major_outage`, and an unmapped word falls
 * through to the amber default, which would paint a total outage as a warning.
 */
const VERDICT: Record<Indicator | "unknown", { label: string; dot: string }> = {
  operational: { label: "OPERATIONAL", dot: "operational" },
  degraded: { label: "DEGRADED", dot: "degraded" },
  outage: { label: "MAJOR OUTAGE", dot: "major_outage" },
  unknown: { label: "UNKNOWN", dot: "unknown" },
};

export interface KpiStripProps {
  /**
   * ENDPOINT counts from `/api/status` — deliberately still that producer, and labelled
   * as endpoints on screen so they cannot be read as a portfolio verdict. A platform
   * being unreachable is a real incident with every endpoint still up, so these numbers
   * do not contradict {@link overall}; they answer a narrower question.
   */
  up: number;
  degraded: number;
  down: number;
  total: number;
  platforms: PlatformSummary[];
  /**
   * The board's own portfolio verdict, or NULL when the board could not back a current
   * claim — `useBoard` folds every cause (`BoardUnavailableReason` is the list; this
   * comment used to re-spell it and went stale twice doing so) into `board === null`.
   *
   * Fix Round 2 item C7: this is the headline verdict the strip prints, and it comes
   * from the SAME producer as {@link incidents} beside it. It used to come from
   * `/api/status`, which sees endpoint health only, while the board also raises
   * platform-unreachable, Crunchy and stale-prod problems — so the strip could print
   * "OPERATIONAL" next to "⚠ 3 incidents", one surface contradicting another about
   * portfolio health on the most prominent element of the page. Null renders UNKNOWN,
   * never operational: an absence of a verdict is not a green one.
   */
  overall: Indicator | null;
  /**
   * Open problems on the board, or NULL under exactly the same condition as
   * {@link overall} — same producer, same null, so the two can never disagree. Null is
   * NOT zero: collapsing it to 0 would render this strip byte-identically to a genuinely
   * problem-free portfolio, which is a health claim made from an ABSENCE of data. The
   * unknown state is representable here precisely so that render can never happen.
   */
  incidents: number | null;
  updatedLabel: string;
  selfCheck?: { overall: CheckState; issues: number };
}

export function KpiStrip({ overall, up, degraded, down, total, platforms, incidents, updatedLabel, selfCheck }: KpiStripProps): ReactElement {
  const verdict = VERDICT[overall ?? "unknown"];

  return (
    <div className="flex flex-none flex-wrap items-center gap-[22px] border-b border-apt-border bg-[linear-gradient(180deg,var(--color-apt-surface),var(--color-apt-bg))] px-4 py-[9px]">
      {/* Portfolio verdict — the board's, the same producer as the incident count on the
          right. Two producers here let the strip read "OPERATIONAL ⚠ 3 incidents". */}
      <div className="flex items-center gap-2 font-semibold tracking-[0.04em]">
        <StatusDot status={verdict.dot} size={11} decorative />
        {verdict.label}
      </div>

      {/* Endpoint count summary — explicitly labelled "endpoints" because it is a
          NARROWER question than the verdict beside it and must not be mistaken for a
          second answer to the same one. */}
      <div className="font-mono text-xs text-apt-text-muted">
        <span className="font-semibold text-apt-text">{up}</span>/{total} endpoints up
        {degraded > 0 && <> · <span className="text-apt-gold">{degraded} degraded</span></>}
        {down > 0 && <> · <span className="text-apt-red">{down} down</span></>}
      </div>

      <Separator orientation="vertical" className="h-[22px] shrink-0" />

      {/* Per-platform summary */}
      {platforms.map((p) => (
        <div key={p.platform} className="flex items-center gap-[7px] font-mono text-xs text-apt-text-muted">
          <span className="font-semibold text-apt-text">
            {platformGlyph(p.platform)} {platformLabelShort(p.platform)}
          </span>
          {p.ready > 0 && <span className="text-apt-green">●{p.ready}</span>}
          {p.building > 0 && <span className="text-apt-blue">▴{p.building}</span>}
          {p.failed > 0 && <span className="font-bold text-apt-red">✕{p.failed}</span>}
        </div>
      ))}

      {/* Right side: incidents + self-check pill + updated */}
      <div className="ml-auto flex items-center gap-4">
        {/* Three distinct renders, never two: a count, nothing (a board that really
            said zero), and the muted unknown affordance. The glyph is the same
            `StatusDot status="unknown"` OverviewTab's UnknownBoardPanel and BoardHome
            use for an unreadable board, and the wording matches GlobalPanel's
            "status unknown — board unavailable" so one vocabulary covers the case
            across every pane. */}
        {incidents === null ? (
          <div
            className="flex items-center gap-[6px] font-mono text-xs text-apt-text-muted"
            title="the status board could not be read — the incident count is unknown"
          >
            <StatusDot status="unknown" size={9} decorative />
            incidents unknown — board unavailable
          </div>
        ) : incidents > 0 ? (
          <div className="font-mono text-xs text-apt-gold">
            ⚠ {incidents} incident{incidents !== 1 ? "s" : ""}
          </div>
        ) : null}
        {selfCheck && <SelfCheckPill overall={selfCheck.overall} issues={selfCheck.issues} />}
        <div className="font-mono text-[11px] text-apt-text-dim">{updatedLabel}</div>
      </div>
    </div>
  );
}
