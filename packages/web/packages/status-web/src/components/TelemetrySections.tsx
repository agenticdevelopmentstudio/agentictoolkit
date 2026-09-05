"use client";
import type { ReactElement } from "react";
import { Bug, TrendingUp } from "lucide-react";
import { StatCard } from "@agentic-toolkit/ui/blocks/stat-card";
import { StatList, StatListRow } from "@agentic-toolkit/ui/blocks/stat-list";
import { ExternalLink } from "@agentic-toolkit/ui/components/external-link";
import { type StatusDotTone } from "@agentic-toolkit/ui/components/status-dot";
import { useTelemetry } from "../hooks/use-telemetry";
import { useStatusHost } from "./StatusHost";
import type { AnalyticsMetricDTO } from "../telemetry/types";

// Errors (GlitchTip) and Traffic (PostHog) cards for the Overview rail, stacked
// under the Stats card. Always rendered, including a healthy/empty state, so the
// dashboard is never silent about production. Each deep-links into the full tool.
// The card itself is the shared StatCard (InfoPanel + StatRows + ExternalLink);
// this file owns only the telemetry wiring and the Errors top-issue list.

// Deep-dive targets come from the HOST (StatusHostProvider) — this package knows no
// hostname. Without one, a card renders its data and simply carries no deep link.

function levelTone(level: string | null): StatusDotTone {
  switch (level) {
    case "fatal":
    case "error":
      return "error";
    case "warning":
      return "accent";
    default:
      return "blue";
  }
}

/** The per-issue deep link: the issue's own permalink, else the host's GlitchTip,
 *  else nothing — never a dead `#`. */
function IssueLink({ href, title }: { href: string | undefined; title: string }): ReactElement | null {
  if (!href) return null;
  return <ExternalLink href={href} aria-label={`Open issue "${title}" in GlitchTip`} />;
}

/**
 * Errors card — top GlitchTip issues by event volume; healthy-green when none.
 *
 * THIS CARD AND THE PROBLEMS PANE COUNT DIFFERENT THINGS, on purpose, and the labels
 * have to say so or the two read as a contradiction. This is the raw `is:unresolved`
 * feed: every level, no age limit, so a `warning` from March is in it. `errorProblems`
 * judges only `error`/`fatal` seen in the last 24h, because a status board reports what
 * is happening now and GlitchTip's unresolved set is a backlog nobody clears. So "5
 * unresolved" here with nothing in Problems is the NORMAL healthy state, not a missed
 * alert — the labels below carry the qualifiers that make that legible.
 */
export function ErrorsCard(): ReactElement {
  const { errors } = useTelemetry();
  const totalEvents = errors.reduce((s, e) => s + (e.count || 0), 0);
  const { glitchtipUrl } = useStatusHost();
  const totalUsers = errors.reduce((s, e) => s + (e.userCount || 0), 0);
  // Sort by event count desc so the shown "top 5" actually matches the prominent
  // {count}× label — the feed arrives in GlitchTip's last-seen order, not by volume.
  const top = [...errors].sort((a, b) => b.count - a.count).slice(0, 5);

  return (
    <StatCard
      title="Errors"
      icon={<Bug size={15} className={errors.length > 0 ? "text-apt-red" : "text-apt-text-muted"} />}
      link={glitchtipUrl ? { href: glitchtipUrl, label: "GlitchTip" } : undefined}
      stats={
        errors.length > 0
          ? [
              // "unresolved · all levels" rather than "open issues": these are GlitchTip's
              // own unresolved rows at every severity, not the board's Problems.
              { label: "unresolved · all levels", value: String(errors.length), tone: "error" },
              { label: "events", value: String(totalEvents) },
              { label: "users affected", value: String(totalUsers) },
            ]
          : undefined
      }
    >
      {errors.length === 0 ? (
        // No unresolved issues — a single quiet all-clear line (no subtitle).
        <div className="font-mono text-[13px] font-semibold text-apt-green">✓ Nothing unresolved in GlitchTip</div>
      ) : (
        // Something IS unresolved in GlitchTip — the top issues by volume,
        // each deep-linking to its GlitchTip page (the shared status-list block).
        <StatList divided>
          {top.map((e) => (
            <StatListRow
              key={e.id}
              tone={levelTone(e.level)}
              label={e.title}
              labelTitle={e.title}
              trailing={
                <>
                  <span className="font-bold text-apt-red">{e.count}×</span>
                  <IssueLink href={e.permalink ?? glitchtipUrl} title={e.title} />
                </>
              }
            />
          ))}
        </StatList>
      )}
    </StatCard>
  );
}

// Compact number formatter — handles k/M/B with correct rounding (e.g. 999_999 → "1M",
// 1_240 → "1.2K"), unlike a hand-rolled /1000 that breaks above 'k'.
const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });

function kpi(metrics: AnalyticsMetricDTO[], metric: string, window: string): number | null {
  const m = metrics.find((x) => x.metric === metric && x.window === window && x.scope === "all");
  return m ? m.value : null;
}
function fmt(n: number | null): string {
  return n === null ? "—" : COMPACT.format(n);
}

/** Traffic card — anonymous, cookieless headline KPIs from PostHog. */
export function TrafficCard(): ReactElement {
  const { analytics } = useTelemetry();
  const figures = [
    { label: "pageviews · 24h", value: kpi(analytics, "pageviews", "24h") },
    { label: "visitors · 24h", value: kpi(analytics, "visitors", "24h") },
    { label: "pageviews · 7d", value: kpi(analytics, "pageviews", "7d") },
    { label: "visitors · 7d", value: kpi(analytics, "visitors", "7d") },
  ];
  // "Not configured / no data" (every window null) vs a genuine measured 0 — only
  // the former gets the onboarding note; a real 0 shows as 0.
  const unconfigured = figures.every((f) => f.value === null);
  const { posthogUrl } = useStatusHost();

  return (
    <StatCard
      title="Traffic"
      icon={<TrendingUp size={15} className="text-apt-blue" />}
      link={posthogUrl ? { href: posthogUrl, label: "PostHog" } : undefined}
      stats={figures.map((f) => ({ label: f.label, value: fmt(f.value) }))}
      footnote={
        unconfigured
          ? "No traffic yet — anonymous, cookieless pageviews from the shared chrome land here."
          : // Visitors is session-scoped under cookieless capture (no cross-session id),
            // so it approximates unique sessions, not unique people — flag it honestly.
            "anonymous · cookieless · approximate"
      }
    />
  );
}
