"use client";

import { useQuery } from "@tanstack/react-query";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import {
  EditableList,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { Progress } from "@agenticdevelopertoolkit/ui/components/progress";
import { Stat } from "@agenticdevelopertoolkit/ui/components/stat";

import { getUsageSummary, usageSummaryKey, type UsageRow } from "@agentic-toolkit/data/profile";
import { isForbidden } from "@agentic-toolkit/data";
import { DetailSection, SettingsBody, useReportBusy } from "@agentic-toolkit/resource";
import {
  capFor,
  capPercent,
  capsFor,
  formatBytes,
  formatCost,
  formatCount,
  groupUsage,
  type CapKey,
  type UsageCap,
} from "./usage/format";

/**
 * Usage — the current period's metered traffic and spend, per principal.
 *
 * Rendered in both User Settings (no `workspaceSlug` → the caller's own principals) and an org
 * workspace's Settings (`workspaceSlug` → that org's member roster + org-owned personas). The
 * subject list is decided server-side, so this component never asks for a subject; the only thing
 * it passes is the workspace it is mounted in.
 *
 * The one thing the layout is load-bearing about is what may be ADDED UP. See `groupUsage`: the
 * people and token rows partition the traffic, personas overlap it, and the ecosystem row is a
 * different axis entirely — so each gets its own section and only the first two feed the total.
 *
 * Every section is the same read-only `EditableList` the rest of User Settings draws — sortable,
 * searchable, no selection and no verbs, because there is nothing here to act on.
 */
export function UsagePanel({ workspaceSlug }: { workspaceSlug?: string } = {}) {
  const usageQuery = useQuery({
    queryKey: usageSummaryKey(workspaceSlug),
    queryFn: () => getUsageSummary(workspaceSlug ? { workspace: workspaceSlug } : undefined),
    retry: false,
  });

  // Publishes no topic list of its own: the settings list one component up owns the spinner. Above
  // the early returns below, because a hook may not sit behind a branch — and because the error
  // return is exactly where a pane would otherwise leave a report standing. See `useReportBusy`.
  useReportBusy(usageQuery.isFetching);

  if (usageQuery.isError) {
    // An org's Settings rail is open to every member, but the usage of an org's PEOPLE is
    // workspace-admin only — so a 403 here is an ordinary outcome, not a failure to report.
    // Hence a plain note for it, and the list's own error alert only for a real failure.
    return (
      <SettingsBody width="full">
        {isForbidden(usageQuery.error) ? (
          <div className="flex flex-col gap-1">
            <p className="text-sm font-medium text-apt-text">Usage is workspace-admin only</p>
            <p className="max-w-prose text-sm text-apt-text-muted">
              Ask a workspace admin for this organization&apos;s usage. Your own usage is in User
              Settings.
            </p>
          </div>
        ) : (
          <UsageTable
            ariaLabel="Usage"
            rows={undefined}
            error={usageQuery.error}
            errorTitle="Couldn't load usage"
          />
        )}
      </SettingsBody>
    );
  }

  if (usageQuery.isPending) {
    return (
      <SettingsBody width="full">
        <UsageTable ariaLabel="Usage" rows={undefined} loading />
      </SettingsBody>
    );
  }

  const view = groupUsage(usageQuery.data);

  if (view.sections.length === 0 && !view.ecosystem) {
    return (
      <SettingsBody width="full">
        <UsageTable
          ariaLabel="Usage"
          rows={[]}
          emptyLabel="Nothing metered yet. Usage appears here once this workspace makes its first API call or chat turn."
        />
      </SettingsBody>
    );
  }

  return (
    <SettingsBody width="full">
      <header className="flex flex-col gap-3">
        {view.period && (
          <p className="text-xs text-apt-text-dim">
            Current period — since {view.period.start}, on a {view.period.days}-day window.
          </p>
        )}
        <div className="flex flex-wrap items-end justify-between gap-6 rounded-lg border border-apt-border px-4 py-3">
          <Stat label="Calls" value={formatCount(view.totals.requests)} className="items-start" />
          <Stat label="Data" value={formatBytes(view.totals.bytes)} className="items-start" />
          <Stat label="Tokens" value={formatCount(view.totals.tokens)} className="items-start" />
          <Stat label="Cost" value={formatCost(view.totals.costMicros)} className="items-start" />
        </div>
        {observingOnly(usageQuery.data) && (
          <p className="text-xs text-apt-text-dim">
            Limits are being recorded, not enforced — nothing is refused for going over yet.
          </p>
        )}
      </header>

      {view.sections.map((section) => (
        <DetailSection key={section.id} title={section.title}>
          <SectionDescription text={section.description} />
          <UsageTable ariaLabel={section.title} rows={section.rows} />
        </DetailSection>
      ))}

      {view.ecosystem && (
        <DetailSection title="Platform">
          <SectionDescription text="The ecosystem's billing key — every tenant in this realm, and the one key whose token and spend caps can actually refuse a turn. Platform admins only." />
          <UsageTable ariaLabel="Platform usage" rows={[view.ecosystem]} />
        </DetailSection>
      )}
    </SettingsBody>
  );
}

// ── Pieces ─────────────────────────────────────────────────────────────────────

/** `DetailSection` carries a title only; a section's "why this is counted apart" note sits under it. */
function SectionDescription({ text }: { text?: string }) {
  if (!text) return null;
  return <p className="-mt-2 max-w-prose text-xs text-apt-text-dim">{text}</p>;
}

/**
 * One section's rows as a read-only list. A component of its own because each section needs its
 * own `useEditableList` (its own sort and search), and a hook may not be called inside the map.
 */
function UsageTable({
  ariaLabel,
  rows,
  loading = false,
  error,
  errorTitle,
  emptyLabel,
}: {
  ariaLabel: string;
  rows: UsageRow[] | undefined;
  loading?: boolean;
  error?: unknown;
  errorTitle?: string;
  emptyLabel?: string;
}) {
  const list = useEditableList<UsageRow>({ rows, getRowId: rowId, columns: COLUMNS });
  return (
    <EditableList
      list={list}
      ariaLabel={ariaLabel}
      selectable={false}
      loading={loading}
      error={error}
      errorTitle={errorTitle}
      emptyLabel={emptyLabel}
      emptyFilteredLabel="No principals match this search."
      searchPlaceholder="Principal or tier"
      // One key for every section, so a column resized in one lines up with the others below it.
      columnWidthsKey="settings-usage"
    />
  );
}

const rowId = (row: UsageRow): string => `${row.scope}:${row.principalId}`;

/** What a row's `kind` is called on the page. `self` needs no chip — the section says "You". */
const KIND_LABEL: Partial<Record<UsageRow["kind"], string>> = {
  token: "token",
  persona: "persona",
  application: "application",
  ecosystem: "ecosystem",
};

/**
 * One quantity cell. When a cap on this quantity can actually refuse something for this row it
 * becomes `used / cap` plus a bar; otherwise it is the bare number — an uncapped quantity has no
 * meaningful fill, and a cap that never fires for this key would be a lie drawn as a bar.
 */
function Quantity({
  row,
  capKey,
  value,
  format,
}: {
  row: UsageRow;
  capKey: CapKey;
  value: number;
  format: (n: number) => string;
}) {
  const cap = capFor(row, capKey);
  if (!cap) return <span className="font-mono text-sm text-apt-text">{format(value)}</span>;
  return (
    <div className="flex w-full flex-col items-end gap-1">
      <span className="font-mono text-sm text-apt-text">
        {format(cap.used)} / {format(cap.cap)}
      </span>
      <Progress value={capPercent(cap)} indicatorClassName={capTone(cap)} />
    </div>
  );
}

/** Amber once a cap is close, red once it is spent — the same thresholds a bar elsewhere uses. */
function capTone(cap: UsageCap): string | undefined {
  const pct = capPercent(cap);
  if (pct >= 100) return "bg-apt-red";
  if (pct >= 80) return "bg-apt-orange";
  return undefined;
}

// Each column's `value` is the raw number, not the formatted string: sorting "1.2 MB" against
// "900 KB" as text would put them in the wrong order.
const COLUMNS: EditableListColumn<UsageRow>[] = [
  {
    key: "label",
    header: "Principal",
    width: "16rem",
    value: (row) => row.label,
    render: (row) => (
      <div className="flex min-w-0 items-center gap-2">
        <span className="truncate text-sm text-apt-text" title={row.label}>
          {row.label}
        </span>
        {KIND_LABEL[row.kind] && <Badge>{KIND_LABEL[row.kind]}</Badge>}
      </div>
    ),
  },
  {
    key: "tier",
    header: "Tier",
    width: "7rem",
    value: (row) => row.tier,
    render: (row) => (
      <Badge variant={row.limits.enforced ? "accent" : "neutral"}>{row.tier}</Badge>
    ),
  },
  {
    key: "requests",
    header: "Calls",
    align: "end",
    value: (row) => row.requests,
    searchable: false,
    render: (row) => (
      <Quantity row={row} capKey="requests" value={row.requests} format={formatCount} />
    ),
  },
  {
    key: "bytes",
    header: "Data",
    align: "end",
    value: (row) => row.bytes,
    searchable: false,
    render: (row) => <Quantity row={row} capKey="bytes" value={row.bytes} format={formatBytes} />,
  },
  {
    key: "tokens",
    header: "Tokens",
    align: "end",
    value: (row) => row.tokens,
    searchable: false,
    render: (row) => <Quantity row={row} capKey="tokens" value={row.tokens} format={formatCount} />,
  },
  {
    key: "costMicros",
    header: "Cost",
    align: "end",
    value: (row) => row.costMicros,
    searchable: false,
    render: (row) => (
      <Quantity row={row} capKey="cost" value={row.costMicros} format={formatCost} />
    ),
  },
];

/**
 * True when some row carries a cap and NOTHING is enforced — the observe-then-enforce rollout,
 * which the page has to say out loud or a bar sitting at 100% reads as a wall that isn't there.
 * A page with no caps at all says nothing.
 */
function observingOnly(rows: UsageRow[]): boolean {
  const capped = rows.filter((r) => capsFor(r).length > 0);
  return capped.length > 0 && capped.every((r) => !r.limits.enforced);
}
