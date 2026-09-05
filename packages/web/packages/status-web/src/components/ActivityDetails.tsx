import type { CSSProperties, ReactElement, ReactNode } from "react";
import { Tabs, TabsList, TabsTab, TabsPanel } from "@agentic-toolkit/ui/components/tabs";
import { CopyButton } from "@agentic-toolkit/ui/components/copy-button";
import { PALETTE, COLORS, envColor, envBadgeLabel } from "../lib/colors";
import { rowDetailToText, type RowDetail } from "../lib/row-detail";
import { ProjLink } from "./ProjLink";

const mono = "var(--mono,ui-monospace,monospace)";
const labelStyle: CSSProperties = { color: PALETTE.dim, textAlign: "right", whiteSpace: "nowrap", fontSize: 11.5 };
const valueStyle: CSSProperties = { color: PALETTE.text, minWidth: 0, overflowWrap: "anywhere" };
const metaStyle: CSSProperties = { whiteSpace: "nowrap", justifySelf: "end" };

/** One card line: right-aligned label · value · optional right-pinned meta.
 *  The meta column is the spec's "flexible space" slot (timestamp, env badge,
 *  copy button). */
function Line({ label, meta, children }: { label: string; meta?: ReactNode; children: ReactNode }): ReactElement {
  return (
    <>
      <span style={labelStyle}>{label}</span>
      <span style={valueStyle}>{children}</span>
      <span style={metaStyle}>{meta ?? null}</span>
    </>
  );
}

/** The three-column line grid every card section shares, tightened (rowGap 4). */
function LineGrid({ children, style }: { children: ReactNode; style?: CSSProperties }): ReactElement {
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "max-content minmax(0,1fr) max-content",
        columnGap: 10,
        rowGap: 4,
        fontFamily: mono,
        fontSize: 12.5,
        alignItems: "baseline",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** Absolute local time for the details pane (the list only shows relative time).
 *  Client-only: the board's data never renders on the server, so no SSR/locale
 *  hydration mismatch. Returns null for an absent/invalid ISO. */
function fmtTime(iso: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? null
    : d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

/** "Copy everything an LLM needs" button — the whole labeled problem text. */
function CopyDiagnostics({ detail }: { detail: RowDetail }): ReactElement {
  return <CopyButton getText={() => rowDetailToText(detail)} label="copy problem details" />;
}

/** Shared top area rendered above the tabs (identical on every tab):
 *  endpoint · timestamp / platform · env badge / git commit line. */
function SharedTop({ detail }: { detail: RowDetail }): ReactElement {
  const when = fmtTime(detail.since ?? detail.lastChecked);
  return (
    <LineGrid>
      <Line
        label="endpoint"
        meta={when ? <span style={{ color: PALETTE.dim, fontSize: 11.5 }}>{when}</span> : undefined}
      >
        {detail.titleUrl ? <ProjLink href={detail.titleUrl} title={detail.titleUrl}>{detail.title}</ProjLink> : detail.title}
      </Line>
      {(detail.platformText || detail.environment) && (
        <Line
          label="platform"
          meta={
            detail.environment ? (
              <span style={{ color: envColor(detail.environment), fontWeight: 700, letterSpacing: "0.04em", fontSize: 11.5 }}>
                {envBadgeLabel(detail.environment)}
              </span>
            ) : undefined
          }
        >
          {detail.platformText ? (
            detail.platformLink ? (
              <ProjLink href={detail.platformLink} title="view deployment">{detail.platformText}</ProjLink>
            ) : (
              detail.platformText
            )
          ) : (
            <span style={{ color: PALETTE.dim }}>—</span>
          )}
        </Line>
      )}
      {(detail.sha || detail.commitSubject) && (
        <Line label="git commit">
          {detail.commitUrl ? (
            <ProjLink href={detail.commitUrl} title="view commit on GitHub">
              {detail.sha && <span style={{ color: COLORS.dimBlue }}>{detail.sha}</span>}
              {detail.commitSubject && <span style={{ color: PALETTE.muted, marginLeft: detail.sha ? 8 : 0 }}>{detail.commitSubject}</span>}
            </ProjLink>
          ) : (
            <>
              {detail.sha && <span style={{ color: COLORS.dimBlue }}>{detail.sha} </span>}
              {detail.commitSubject}
            </>
          )}
        </Line>
      )}
    </LineGrid>
  );
}

/** Overview tab: build/deploy outcome headline (FAILED links to the platform's
 *  error page), the failure reason with the copy-diagnostics button, scrollable
 *  logs, and the endpoint-problem diagnostics. */
function OverviewTab({ detail }: { detail: RowDetail }): ReactElement {
  const errorLink = detail.platformLink ?? detail.problemLink ?? detail.titleUrl;
  // The short human reason: the issue detail when present, else the first log line.
  const reason = detail.problem ?? detail.errorText?.split("\n", 1)[0] ?? null;
  const rows: ReactNode[] = [];

  if (detail.deployOutcome === "failed") {
    rows.push(
      <div key="headline" style={{ gridColumn: "1 / -1", fontWeight: 700, color: PALETTE.red }}>
        {errorLink ? (
          <ProjLink href={errorLink} title="view the error on the platform">✕ build / deploy FAILED</ProjLink>
        ) : (
          <>✕ build / deploy FAILED</>
        )}
      </div>,
      <Line key="reason" label="reason" meta={<CopyDiagnostics detail={detail} />}>
        {reason ?? <span style={{ color: PALETTE.dim }}>see logs</span>}
      </Line>,
    );
  } else if (detail.deployOutcome === "success") {
    rows.push(
      <div key="headline" style={{ gridColumn: "1 / -1", fontWeight: 600, color: PALETTE.green }}>
        ✓ build / deploy successful
      </div>,
    );
  } else if (detail.problem) {
    // Endpoint problems (down/degraded): the issue summary, copyable like a failure.
    rows.push(
      <Line key="problem" label="problem" meta={<CopyDiagnostics detail={detail} />}>
        {detail.problemLink ? <ProjLink href={detail.problemLink} title="view problem">{detail.problem}</ProjLink> : detail.problem}
      </Line>,
    );
  }

  if (detail.errorText) {
    rows.push(
      <Line key="logs" label="logs">
        {/* The provider's real failure log — verbatim, scrollable so a long
            build-log tail can't blow out the pane. */}
        <pre
          style={{
            margin: 0,
            maxHeight: 240,
            overflow: "auto",
            whiteSpace: "pre-wrap",
            overflowWrap: "anywhere",
            fontFamily: mono,
            fontSize: 11.5,
            lineHeight: 1.45,
            color: PALETTE.text,
            background: COLORS.surfaceDeep,
            border: `1px solid var(--color-apt-red, ${COLORS.border})`,
            borderRadius: 6,
            padding: "6px 8px",
          }}
        >
          {detail.errorText}
        </pre>
      </Line>,
    );
  }

  if (detail.statusCode != null) {
    rows.push(
      <Line key="status" label="http status">
        <span style={{ color: PALETTE.text }}>{detail.statusCode}</span>
      </Line>,
    );
  }
  if (detail.responseTime) {
    rows.push(
      <Line key="response" label="response">
        <span style={{ color: PALETTE.muted }}>{detail.responseTime}</span>
      </Line>,
    );
  }
  if (fmtTime(detail.lastChecked)) {
    rows.push(
      <Line key="checked" label="last check">
        <span style={{ color: PALETTE.muted }}>{fmtTime(detail.lastChecked)}</span>
      </Line>,
    );
  }

  if (rows.length === 0) {
    return <div style={{ fontFamily: mono, fontSize: 12, color: PALETTE.dim }}>no further details</div>;
  }
  return <LineGrid>{rows}</LineGrid>;
}

/** Git tab: branch + the full commit message body (the subject line lives in the
 *  shared top area). */
function GitTab({ detail }: { detail: RowDetail }): ReactElement {
  return (
    <LineGrid>
      {detail.branch && (
        <Line label="branch">
          <span style={{ color: PALETTE.muted }}>{detail.branch}</span>
        </Line>
      )}
      {detail.commitBody && (
        <Line label="git info">
          <span style={{ whiteSpace: "pre-wrap", color: PALETTE.muted }}>{detail.commitBody}</span>
        </Line>
      )}
    </LineGrid>
  );
}

/** The details card for a selected row: a shared top area (endpoint / platform /
 *  commit) over [overview] [git info] tabs. Rows without any git detail skip the
 *  tab chrome and render the overview content directly. */
export function ActivityDetails({ detail }: { detail: RowDetail }): ReactElement {
  const hasGitTab = !!(detail.commitBody || detail.branch);
  return (
    <div style={{ fontFamily: mono, fontSize: 12.5 }}>
      <SharedTop detail={detail} />
      {hasGitTab ? (
        <Tabs defaultValue="overview" className="mt-2 gap-2">
          <TabsList>
            <TabsTab value="overview">overview</TabsTab>
            <TabsTab value="git">git info</TabsTab>
          </TabsList>
          <TabsPanel value="overview">
            <OverviewTab detail={detail} />
          </TabsPanel>
          <TabsPanel value="git">
            <GitTab detail={detail} />
          </TabsPanel>
        </Tabs>
      ) : (
        <div style={{ marginTop: 8 }}>
          <OverviewTab detail={detail} />
        </div>
      )}
    </div>
  );
}
