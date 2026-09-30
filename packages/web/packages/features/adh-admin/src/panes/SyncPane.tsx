"use client";

import { useMemo, useState, type ReactNode } from "react";
import { RotateCcw, Wifi, WifiOff } from "lucide-react";
import { FeatureTitle } from "@agentic-toolkit/resource";
import {
  useAdminEcosystems,
  useSyncTables,
  useSetSyncOverride,
  useClearSyncOverride,
  schemaOf,
  type EnrollmentRow,
} from "../api/sync-tables";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import {
  EditableList,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
  type EditableListFacet,
} from "../components/editable-list";

/**
 * Per-ecosystem offline-sync table enrollment — the admin console's window onto the backend's
 * `/admin/sync/tables/:id` routes (platform-only; a developer does NOT tune this for their own
 * ecosystem). Pick an ecosystem, then decide which catalog resources it syncs; each decision
 * overrides the resource's code default, and "Reset to default" drops the override.
 *
 * Enrollment is a bulk verb — "sync everything under `content`" is the actual request, and it
 * used to be one switch per row across as many little per-schema tables as the catalog had
 * schemas. Now it is one list: the schema is a facet, and Sync / Don't sync / Reset to default
 * act on the selection. Sorting and counting work across the whole catalog for the first time,
 * which the per-schema split made impossible.
 *
 * Every mutation returns the full refreshed catalog, so the list always shows the server's
 * authoritative state rather than a hand-patched row.
 */
export function SyncPane({ help }: { help?: ReactNode } = {}) {
  const [ecosystemId, setEcosystemId] = useState("");
  const ecosystems = useAdminEcosystems();
  const { data, isLoading, error } = useSyncTables(ecosystemId || undefined);
  const setOverride = useSetSyncOverride(ecosystemId || undefined);
  const clearOverride = useClearSyncOverride(ecosystemId || undefined);
  const rows = useMemo(() => data ?? [], [data]);

  const run = useBatchRun({ successMessage: "saved" });

  const columns = useMemo<EditableListColumn<EnrollmentRow>[]>(
    () => [
      {
        key: "resource",
        header: "Table",
        width: "minmax(0,1fr)",
        value: (row) => row.resource,
        render: (row) => (
          <span className="flex items-center gap-2">
            <span className="truncate font-mono text-sm text-apt-text">{row.resource}</span>
            {row.overridden && (
              <Badge
                variant="accent"
                title={`Default: ${row.defaultEnabled ? "synced" : "not synced"}`}
              >
                overridden
              </Badge>
            )}
          </span>
        ),
      },
      { key: "schema", header: "Schema", width: "11rem", value: schemaOf },
      { key: "scope", header: "Scope", width: "9rem", value: (row) => row.scope },
      { key: "pushMode", header: "Push", width: "7rem", value: (row) => row.pushMode },
      {
        key: "enabled",
        header: "Synced",
        width: "8rem",
        // Sorted and searched by the WORD, so the facet's ticks and a typed "not synced" find the
        // same rows the badge shows. A boolean would sort as "false" and "true".
        value: (row) => syncedLabel(row.enabled),
        render: (row) => (
          <Badge variant={row.enabled ? "success" : "neutral"}>{syncedLabel(row.enabled)}</Badge>
        ),
      },
      {
        key: "defaultEnabled",
        header: "Default",
        width: "8rem",
        value: (row) => syncedLabel(row.defaultEnabled),
        render: (row) => (
          <span className="text-xs text-apt-text-dim">{syncedLabel(row.defaultEnabled)}</span>
        ),
      },
    ],
    [],
  );

  const facets = useMemo<EditableListFacet<EnrollmentRow>[]>(
    () => [
      { id: "schema", label: "Schema", valuesOf: (row) => [schemaOf(row)] },
      { id: "synced", label: "Synced", valuesOf: (row) => [syncedLabel(row.enabled)] },
      {
        id: "overridden",
        label: "Override",
        valuesOf: (row) => [row.overridden ? "overridden" : "default"],
      },
    ],
    [],
  );

  const list = useEditableList<EnrollmentRow>({
    rows,
    getRowId: (row) => row.resource,
    columns,
    facets,
    initialSort: { key: "resource", dir: "asc" },
  });

  const selected = list.selectedRows;

  /**
   * Enrol (or un-enrol) the selection, skipping every row already in that state.
   *
   * A no-op PUT writes a real override row: a resource that merely INHERITS "synced" would come
   * back marked `overridden`, pinning it against a later change to the code default. That is a
   * silent, lasting difference, which is why the skip is not just about the count.
   */
  const setSynced = (enabled: boolean) => {
    const changing = selected.filter((row) => row.enabled !== enabled);
    void run.run(
      changing.map((row) => ({ id: row.resource, label: row.resource })),
      (item) => setOverride.mutateAsync({ resource: item.id, enabled }),
    );
  };

  const resetToDefault = () => {
    const overridden = selected.filter((row) => row.overridden);
    void run.run(
      overridden.map((row) => ({ id: row.resource, label: row.resource })),
      (item) => clearOverride.mutateAsync(item.id),
    );
  };

  const wouldSet = (enabled: boolean) => selected.some((row) => row.enabled !== enabled);
  const anyOverridden = selected.some((row) => row.overridden);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title="Sync Tables" help={help} />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
        <p className="mb-6 max-w-2xl text-sm text-apt-text-muted">
          Choose which catalog tables each ecosystem syncs to offline clients. Syncing a table
          overrides the resource&apos;s platform default for this ecosystem;
          &ldquo;Reset to default&rdquo; removes the override.
        </p>

        {/* Not a list filter: this picks WHAT IS FETCHED, so it sits above the bar rather than in
            it. A control inside the bar reads as one more way to narrow rows already on screen. */}
        <div className="mb-6 w-80">
          <Select
            aria-label="Ecosystem"
            value={ecosystemId}
            onChange={(e) => {
              setEcosystemId(e.target.value);
              // The selection goes with the ecosystem. Resource ids are the same catalog everywhere,
              // so ticks would SURVIVE the switch — and a bar button pressed afterwards would write
              // to an ecosystem whose state the operator never looked at.
              list.clearSelection();
            }}
          >
            <option value="">Select an ecosystem…</option>
            {(ecosystems.data ?? []).map((eco) => (
              <option key={eco.id} value={eco.id}>
                {eco.name} ({eco.slug})
              </option>
            ))}
          </Select>
        </div>

        {!ecosystemId && (
          <p className="text-apt-text-dim">Select an ecosystem to view its sync tables.</p>
        )}

        {ecosystemId && (
          <EditableList<EnrollmentRow>
            list={list}
            ariaLabel="Sync tables"
            loading={isLoading}
            // Distinct from the list's own empty state — a failed load must NOT read as
            // "No catalog tables."
            error={error}
            errorTitle="Couldn't load sync tables"
            columnWidthsKey="admin-sync-tables"
            // The resource IS the row id, so the table's own guess skips it and lands on `scope` —
            // where every row says "customer" or "ecosystem" and no two checkboxes can be told apart.
            describeRow={(row) => row.resource}
            searchPlaceholder="Table or schema"
            emptyLabel="No catalog tables."
            emptyFilteredLabel="No tables match these filters."
            actions={
              <>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!wouldSet(true)}
                  onClick={() => setSynced(true)}
                >
                  <Wifi data-icon="inline-start" />
                  Sync
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!wouldSet(false)}
                  onClick={() => setSynced(false)}
                >
                  <WifiOff data-icon="inline-start" />
                  Don&apos;t sync
                </Button>
                {/* Only overridden rows have anything to clear; a selection of pure defaults leaves
                    this dead rather than firing DELETEs that would each 404 or no-op. */}
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!anyOverridden}
                  onClick={resetToDefault}
                >
                  <RotateCcw data-icon="inline-start" />
                  Reset to default
                </Button>
              </>
            }
          />
        )}

        <ProgressModal
          open={run.state.running || run.state.finished}
          title="Saving sync enrollment"
          description="Each table is saved on its own; a failure leaves the earlier saves in place."
          total={run.state.total}
          done={run.state.done}
          currentLabel={run.state.currentLabel}
          error={run.state.error}
          results={run.state.results}
          finished={run.state.finished}
          onContinue={run.continueRun}
          onStop={run.stop}
          onClose={() => {
            run.reset();
            list.clearSelection();
          }}
        />
      </div>
    </div>
  );
}

/** "synced" / "not synced" — the words the badge, the facet and the search box all share. */
function syncedLabel(enabled: boolean): string {
  return enabled ? "synced" : "not synced";
}
