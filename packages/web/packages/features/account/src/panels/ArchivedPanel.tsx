"use client";

import { useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { RotateCcw } from "lucide-react";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  EditableList,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { ErrorText } from "@agentic-toolkit/crud";
import { ListBarActions, SettingsBody } from "@agentic-toolkit/resource";

import {
  useArchivedWorkspaces,
  ARCHIVED_WORKSPACES_QUERY_KEY,
  type ArchivedWorkspace,
} from "../api/archived-workspaces";
import { WORKSPACES_QUERY_KEY } from "../api/workspaces";
import { organizationsApi } from "../api/organizations";
import { ORGANIZATIONS_QUERY_KEY } from "@agentic-toolkit/data/organizations";
import { errMsg } from "@agentic-toolkit/data";

/** A row the caller can actually bring back: its handle is still free AND they may restore it. */
function isRestorable(row: ArchivedWorkspace): boolean {
  return row.handleAvailable && row.canRestore;
}

/**
 * Archived — the things the caller has archived, and the one place they can be brought back.
 *
 * Today that is organizations only; personas and projects become archivable in their own slices
 * and will join this list.
 *
 * It lives in PERSONAL settings rather than the org's own settings for a structural reason: an
 * archived org is invisible from inside itself (its workspace no longer resolves), so the
 * archiving user's personal settings is the only surface that can still list it.
 *
 * The same table every other User Settings list draws: Restore is a verb on the BAR acting on the
 * ticked rows, not a button repeated on every row — a per-row button next to a selection is two
 * competing models of "what am I acting on".
 */
export function ArchivedPanel() {
  const qc = useQueryClient();
  const query = useArchivedWorkspaces();
  // One flag, not a per-row set: the bar's Restore acts on the whole selection at once and is
  // disabled until that batch settles, so there is no second restore to overlap the first.
  const [restoring, setRestoring] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function restore(rows: ArchivedWorkspace[]): Promise<void> {
    // Only the rows that CAN come back. A ticked row with a taken handle or no admin right is
    // skipped rather than sent to fail — its badge already says why.
    const targets = rows.filter(isRestorable);
    if (targets.length === 0) return;
    setRestoring(true);
    setError(null);
    try {
      // Restore is keyed by id, which the list carries. There is deliberately no slug lookup
      // here: GET /organization/organizations/{key} cannot see an archived org.
      //
      // `allSettled`, not `all`: one org whose handle was taken a second ago must not hide that
      // the others DID come back — the invalidations below have to run either way.
      const results = await Promise.allSettled(
        targets.map((row) => organizationsApi.restore(row.id)),
      );
      const failures = results.flatMap((r) =>
        r.status === "rejected" ? [errMsg(r.reason, "Couldn't restore that organization.")] : [],
      );
      // Everything that did come back leaves the selection; a failed row stays ticked so a
      // second press retries exactly it.
      const failedIds = new Set(
        targets.filter((_, i) => results[i]?.status === "rejected").map((r) => r.id),
      );
      list.setSelectedIds(
        new Set([...list.selectedIds].filter((id) => failedIds.has(id))),
      );
      if (failures.length > 0) setError(failures.join(" "));
      // All three invalidations together, not awaited one after another: sequential, each
      // refetch only STARTS once the previous has come back, so between them the row is gone
      // from Archived while the workspace picker still doesn't have it — and if the archived
      // refetch rejects (it is the one whose list just shrank), the others are never
      // invalidated at all and the restored org stays missing until a reload.
      //
      // The third key is the orgs rail. Unlike the hub's create flow — a different Next app, a
      // different QueryClient — this panel is mounted by the settings registry INSIDE every
      // site, the orgs site included, so on that site the rail's `["organizations", <slug>]`
      // entry is in this very cache and a restored org is a row that belongs back in it. The
      // prefix invalidates every workspace's copy, which is right: the restored org may be
      // owned by any of them. On the other sites there is no such entry and this costs nothing.
      if (failures.length < targets.length) {
        await Promise.all([
          qc.invalidateQueries({ queryKey: ARCHIVED_WORKSPACES_QUERY_KEY }),
          qc.invalidateQueries({ queryKey: WORKSPACES_QUERY_KEY }),
          qc.invalidateQueries({ queryKey: ORGANIZATIONS_QUERY_KEY }),
        ]);
      }
    } catch (e) {
      setError(errMsg(e, "Couldn't restore that organization."));
    } finally {
      setRestoring(false);
    }
  }

  const columns: EditableListColumn<ArchivedWorkspace>[] = useMemo(
    () => [
      {
        key: "name",
        header: "Name",
        value: (r) => r.name,
        render: (r) => (
          <span className="inline-flex min-w-0 items-center gap-2">
            <span className="truncate font-medium text-apt-text">{r.name}</span>
            {/* Visible, in the a11y tree, and next to the fact it's about (the caller's own
                permission on this org) — a `title` on a disabled Restore button reaches neither
                screen readers nor touch. */}
            {!r.canRestore && <Badge variant="orange">Admins only</Badge>}
          </span>
        ),
      },
      {
        key: "handle",
        header: "Handle",
        value: (r) => `org.${r.slug}`,
        render: (r) => (
          <span className="inline-flex min-w-0 items-center gap-2">
            <span className="truncate font-mono text-xs text-apt-text-muted">org.{r.slug}</span>
            {/* Visible, in the a11y tree, and next to the handle it is about — a `title` on a
                disabled Restore button reaches neither screen readers nor touch. */}
            {!r.handleAvailable && <Badge variant="orange">Handle taken</Badge>}
          </span>
        ),
      },
      // `archivedAt` is a DB timestamp read back as Postgres text (`YYYY-MM-DD HH:MM:SS.ssssss`),
      // not RFC3339 — hence the slice rather than `new Date(...)`, which parses it inconsistently
      // across browsers. The slice also sorts correctly as a string.
      {
        key: "archivedAt",
        header: "Archived",
        width: "8rem",
        value: (r) => r.archivedAt.slice(0, 10),
      },
    ],
    [],
  );

  const list = useEditableList<ArchivedWorkspace>({
    rows: query.data,
    getRowId: (r) => r.id,
    columns,
  });
  const selected = list.selectedRows;
  const anyRestorable = selected.some(isRestorable);

  return (
    <SettingsBody width="full">
      <ErrorText error={error} />
      <EditableList
        list={list}
        ariaLabel="Archived"
        loading={query.isPending}
        error={query.isError ? query.error : undefined}
        errorTitle="Couldn't load your archived items"
        columnWidthsKey="settings-archived"
        describeRow={(r) => r.name}
        searchPlaceholder="Name or handle"
        emptyLabel="Nothing archived. Organizations you archive appear here, and can be restored while their handle is still free."
        emptyFilteredLabel="Nothing archived matches this search."
        actions={
          <ListBarActions noun="archived item" selectedCount={selected.length}>
            {/* Disabled unless the selection holds at least one row that CAN come back: a press
                that would skip every ticked row does nothing, and a live button that does
                nothing reads as broken. */}
            <Button
              size="sm"
              variant="ghost"
              disabled={!anyRestorable || restoring}
              onClick={() => void restore(selected)}
            >
              <RotateCcw data-icon="inline-start" />
              {restoring ? "Restoring…" : "Restore"}
            </Button>
          </ListBarActions>
        }
      />
    </SettingsBody>
  );
}
