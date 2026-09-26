"use client";

import { useMemo } from "react";
import { useAccessAudit, type AccessAuditEvent } from "../api/admin";
import {
  EditableList,
  WindowFooter,
  useEditableList,
  type EditableListColumn,
} from "../components/editable-list";
import { formatDateTime } from "../lib/timestamps";

// Raw action enums → plain language: a reader shouldn't need to know the backend's
// enum values (labels must never be internal jargon).
const ACTION_LABEL: Record<string, string> = {
  "role.create": "Created role",
  "role.update": "Updated role",
  "role.delete": "Deleted role",
  "role.grant.revoke": "Removed a feature from a role",
  "assignment.grant": "Granted access",
  "assignment.revoke": "Revoked access",
  "item.restrict": "Restricted item",
  "item.restore": "Restored item",
};

function actionLabel(action: string): string {
  return ACTION_LABEL[action] ?? action;
}

function shortId(id: string): string {
  return id ? id.slice(0, 8) : "";
}

/** Who did it — their email where the id resolved to one, a short id where it did not. */
function actor(e: AccessAuditEvent): string {
  return e.actorEmail ?? shortId(e.actorId);
}

/** A compact, human-readable summary of what changed (the audit's before/after strings). */
function details(e: AccessAuditEvent): string {
  const before = e.before.trim();
  const after = e.after.trim();
  if (before && after) return `${before} → ${after}`;
  return after || before || "";
}

export function AuditPane() {
  const trail = useAccessAudit();

  const columns = useMemo<EditableListColumn<AccessAuditEvent>[]>(
    () => [
      {
        key: "at",
        header: "When",
        width: "12rem",
        // Sorted by the RAW timestamp, displayed formatted. Sorting by the formatted string would
        // order "Aug 3" before "Jul 9" — the one column on this page an operator sorts by.
        value: (e) => e.at,
        render: (e) => (
          <span className="whitespace-nowrap text-sm text-apt-text-muted">
            {formatDateTime(e.at)}
          </span>
        ),
      },
      {
        key: "action",
        header: "Action",
        width: "14rem",
        value: (e) => actionLabel(e.action),
      },
      { key: "targetFeature", header: "Area", width: "9rem", value: (e) => e.targetFeature },
      {
        key: "actor",
        header: "Actor",
        width: "16rem",
        value: actor,
        render: (e) => (
          <span className="block truncate text-sm text-apt-text" title={actor(e)}>
            {e.actorEmail ?? (
              <span className="font-mono text-xs text-apt-text-muted">{shortId(e.actorId)}</span>
            )}
          </span>
        ),
      },
      {
        key: "details",
        header: "Details",
        // minmax(0,1fr): flex to the remaining width but allow shrinking so the summary truncates.
        width: "minmax(0,1fr)",
        value: details,
        render: (e) => {
          const text = details(e);
          return (
            <span className="block truncate text-sm text-apt-text-muted" title={text}>
              {text || "—"}
            </span>
          );
        },
      },
    ],
    [],
  );

  const facets = useMemo(
    () => [
      {
        id: "action",
        label: "Action",
        valuesOf: (e: AccessAuditEvent) => [e.action],
        labelOf: actionLabel,
      },
      {
        id: "area",
        label: "Area",
        valuesOf: (e: AccessAuditEvent) => (e.targetFeature ? [e.targetFeature] : []),
      },
    ],
    [],
  );

  const list = useEditableList<AccessAuditEvent>({
    rows: trail.rows,
    getRowId: (e) => e.id,
    columns,
    facets,
    initialSort: { key: "at", dir: "desc" },
  });

  return (
    <div>
      <h1 className="mb-4 text-2xl font-bold text-apt-text">Audit</h1>

      <p className="mb-6 max-w-2xl text-sm text-apt-text-muted">
        The authorization audit trail — every role and access-assignment change across all
        workspaces, newest first. Most other platform actions are not audited yet; this covers
        the access-control changes written by the roles &amp; permissions system.
      </p>

      {/* The one admin list with NO actions, and deliberately so: the trail is append-only
          everywhere, including in the backend, so a selection here could only ever act on rows
          nothing is allowed to change. The checkboxes come with the shared list and cost the
          operator nothing; a button bar with buttons that lied about what they could do would. */}
      <EditableList<AccessAuditEvent>
        list={list}
        ariaLabel="Access audit events"
        searchPlaceholder="Search the trail"
        emptyLabel="No audit events recorded yet."
        emptyFilteredLabel="Nothing in the loaded window matches — load older events, or widen the filters."
        loading={trail.isLoading}
        error={trail.error}
        errorTitle="Couldn't load the audit trail"
        columnWidthsKey="admin.audit"
        // An event has no name of its own, so the checkbox borrows the three columns that tell two
        // events apart. Left to the table's guess it would read the first string field — the
        // action — and every grant on the page would be "Select role granted".
        describeRow={(e) => `${actionLabel(e.action)} by ${actor(e)}, ${formatDateTime(e.at)}`}
        footer={
          <WindowFooter
            noun="events"
            loaded={trail.rows.length}
            showing={list.rows.length}
            total={trail.total}
            hasMore={trail.hasMore}
            busy={trail.isFetchingMore}
            onLoadMore={trail.loadMore}
          />
        }
      />
    </div>
  );
}
