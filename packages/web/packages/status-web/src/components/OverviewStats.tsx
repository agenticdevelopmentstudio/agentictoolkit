"use client";
import { type ReactElement, useMemo } from "react";
import { Stat, StatRow, type StatTone } from "@agentic-toolkit/ui/components/stat";
import { sectionLabelClass } from "@agentic-toolkit/ui/components/section-label";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from "@agentic-toolkit/ui/components/dropdown-menu";
import { menuTriggerPillClass } from "./menu-pill";
import { useResponseHistory } from "../hooks/use-response-history";
import { useBoard } from "../hooks/use-board";
import { activityWindowLabel, deployCounts } from "../lib/overview";
import { ResponseChart } from "./ResponseChart";
import { OptionsGear, OptionSection, optionRow } from "./OptionsGear";

export interface Span {
  key: string;
  label: string;
  hours: number;
}
export const SPANS: Span[] = [
  { key: "24h", label: "24h", hours: 24 },
  { key: "7d", label: "7d", hours: 24 * 7 },
  { key: "30d", label: "30d", hours: 24 * 30 },
  { key: "90d", label: "90d", hours: 24 * 90 },
];
export const DEFAULT_SPAN = SPANS[1]!; // 7d

export interface OverviewStatsProps {
  /** Portfolio uptime % over the uptime window, or null until loaded. */
  uptimePercent: number | null;
  /** "strip" = horizontal row (mobile hero); "card" = vertical stack (the
   *  desktop stats pane beside the activity list). */
  layout?: "strip" | "card";
  /** Controlled time span (owned by the parent so the Stats gear can edit it). */
  span: Span;
  onSpanChange: (s: Span) => void;
}

/** Uptime figure tone — green ≥99, amber ≥95, red below; dim when unknown. */
function uptimeTone(pct: number | null): StatTone {
  if (pct == null) return "muted";
  if (pct >= 99) return "success";
  if (pct >= 95) return "accent";
  return "error";
}

/** The Stats panel's options gear — a single "Range" radio group (last X days). */
export function StatsGear({ span, onSpanChange }: { span: Span; onSpanChange: (s: Span) => void }): ReactElement {
  const changed = span.key !== DEFAULT_SPAN.key ? 1 : 0;
  return (
    <OptionsGear changedCount={changed} summary={`Range: last ${span.label}`} label="Stats options" menuWidth={140}>
      {(close) => (
        <OptionSection title="Range">
          {SPANS.map((s) => (
            <label key={s.key} style={optionRow(s.key === span.key)}>
              <input
                className="adh-check"
                type="radio"
                name="stats-span"
                checked={s.key === span.key}
                onChange={() => {
                  onSpanChange(s);
                  close();
                }}
                aria-label={`last ${s.label}`}
              />
              last {s.label}
            </label>
          ))}
        </OptionSection>
      )}
    </OptionsGear>
  );
}

/** Compact "last {span} ▾" menu — kept for the mobile hero strip. The shared
 *  menu engine supplies the menuitemradio semantics + keyboard nav. */
function SpanMenu({ value, onChange }: { value: Span; onChange: (s: Span) => void }): ReactElement {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger aria-label="stats time span" className={menuTriggerPillClass}>
        <span className="text-apt-text-dim">last</span>
        {value.label}
        <span aria-hidden className="text-apt-text-dim">
          ▾
        </span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[90px]">
        <DropdownMenuRadioGroup
          value={value.key}
          onValueChange={(key) => {
            const s = SPANS.find((x) => x.key === key);
            if (s) onChange(s);
          }}
        >
          {SPANS.map((s) => (
            <DropdownMenuRadioItem key={s.key} value={s.key}>
              last {s.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** The "avg response · {span}" caption + sparkline, shared by both layouts. */
function AverageResponse({ spanLabel, points, height }: { spanLabel: string; points: (number | null)[]; height: number }): ReactElement {
  return (
    <>
      <span className={sectionLabelClass}>avg response · {spanLabel}</span>
      <ResponseChart points={points} height={height} />
    </>
  );
}

/**
 * The overview stats — portfolio uptime %, build/deploy/failure counts, and a
 * portfolio response-time graph over the selected span. The span is controlled
 * by the parent: on desktop it's set from the Stats panel's gear ({@link
 * StatsGear}); the mobile hero strip carries its own compact menu. The figures
 * themselves are the shared Stat/StatRow grammar.
 */
export function OverviewStats({ uptimePercent, layout = "strip", span, onSpanChange }: OverviewStatsProps): ReactElement {
  const history = useResponseHistory(span.hours);
  // Deploy counts come from the board's activity feed (the server's record of what
  // happened), so the WINDOW is the server's too — `activityFromMs`, not a constant of our
  // own — and it is independent of the span menu (which drives uptime% and the chart).
  const { board } = useBoard();
  const stats = useMemo(
    () => (board == null ? null : deployCounts(board.activity, board.activityFromMs)),
    [board],
  );
  const window = board == null ? null : activityWindowLabel(board.activityFromMs, Date.parse(board.generatedAt));
  const points = history.data?.points ?? [];

  // One em dash rather than a zero when there is no board: a count of 0 over a window we
  // cannot name is a claim that nothing deployed, which we have no standing to make.
  const count = (n: number | undefined): string => (n == null ? "—" : String(n));
  const figures: { label: string; value: string; tone: StatTone }[] = [
    { label: "uptime", value: uptimePercent != null ? `${uptimePercent}%` : "—", tone: uptimeTone(uptimePercent) },
    { label: `builds · ${window ?? "—"}`, value: count(stats?.builds), tone: "neutral" },
    { label: `deploys · ${window ?? "—"}`, value: count(stats?.deploys), tone: "neutral" },
    {
      label: `failures · ${window ?? "—"}`,
      value: count(stats?.failures),
      tone: stats != null && stats.failures > 0 ? "error" : "muted",
    },
  ];

  // Card: vertical stack for the stats pane beside the activity list. The span
  // control now lives in the panel header's gear, so no inline menu here.
  if (layout === "card") {
    // Need ≥2 real samples to draw a line — anything less is a near-empty box
    // that just reads as dead bottom padding, so drop the whole section then.
    const hasSeries = points.filter((p) => p != null).length >= 2;
    return (
      <div className="flex flex-col gap-3 font-mono">
        <div className="flex flex-col gap-2.5">
          {figures.map((f) => (
            <StatRow key={f.label} label={f.label} value={f.value} tone={f.tone} />
          ))}
        </div>
        {hasSeries && (
          <div className="flex flex-col gap-1">
            <AverageResponse spanLabel={span.label} points={points} height={32} />
          </div>
        )}
      </div>
    );
  }

  // Strip: horizontal row for the mobile hero.
  return (
    <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
      <SpanMenu value={span} onChange={onSpanChange} />
      {figures.map((f) => (
        <Stat key={f.label} label={f.label} value={f.value} tone={f.tone} />
      ))}
      <div className="flex min-w-[170px] max-w-[340px] flex-[1_1_170px] flex-col gap-0.5">
        <AverageResponse spanLabel={span.label} points={points} height={38} />
      </div>
    </div>
  );
}
