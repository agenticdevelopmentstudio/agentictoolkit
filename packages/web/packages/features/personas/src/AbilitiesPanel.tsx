"use client";

import { useId, useMemo } from "react";
import { useAction } from "@agentic-toolkit/crud";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";
import { personaToolsApi, type ToolCatalogItem } from "@agentic-toolkit/data/personas";
import { groupBySource } from "./agent-tool-source";
import { useOptimisticRowActions } from "./useOptimisticRowActions";

/**
 * The persona editor's Abilities facet — what tools THIS persona HAS. Grant/revoke each tool in
 * its self-context catalog (a ticked box = granted) and, for a granted tool, flip its per-tool
 * autonomy opt-out (an autonomous tool skips the human decision queue — see PermissionsPanel,
 * which owns that queue plus the may_act context grants for WHERE/AS-WHAT the persona may use
 * these tools). Carved from the old workspace AgentToolsPanel's tool-list half, scoped to a
 * `personaId` prop instead of an agent-picker dropdown.
 *
 * Grant and autonomy mutations are optimistic: the row flips instantly and reverts if the
 * request rejects, reconciling from the server's response on success. The cached load + per-row
 * busy-tracking + optimistic-mutate/revert machine is the shared `useOptimisticRowActions` hook
 * (#11) — see its doc comment for the race-safety guarantees on a persona switch. The catalog is
 * cached per persona, so clicking back to a persona shows its tools on the first frame and
 * re-reads behind them. Owner/admin-only usage is enforced by the backend (403); the panel just
 * surfaces the error.
 */
export function AbilitiesPanel({ personaId }: { personaId: string }) {
  // Base id for the per-tool rows (checkbox ↔ its tool-name label).
  const rowIdPrefix = useId();
  const { error, run } = useAction();
  const {
    rows: tools,
    loadError,
    busy: busyTools,
    runRowMutation,
  } = useOptimisticRowActions<ToolCatalogItem>(
    "persona-tools",
    personaId,
    (id) => personaToolsApi.list(id),
    (t) => t.toolName,
  );

  // Optimistically flip `granted` (clearing autonomy on revoke, since an ungranted tool can't be
  // autonomous), fire the grant/revoke, and restore the prior row on failure.
  function toggleGrant(item: ToolCatalogItem, granted: boolean) {
    runRowMutation(
      item,
      { ...item, granted, autonomous: granted ? item.autonomous : false },
      async () => {
        if (granted) await personaToolsApi.grant(personaId, item.toolName);
        else await personaToolsApi.revoke(personaId, item.toolName);
      },
      run,
    );
  }

  // Optimistically flip the per-tool autonomy opt-out; reconcile from the returned grant, or
  // restore the prior row on failure.
  function toggleAutonomy(item: ToolCatalogItem, autonomous: boolean) {
    runRowMutation(
      item,
      { ...item, autonomous },
      async () => {
        const grant = await personaToolsApi.setAutonomy(personaId, item.toolName, autonomous);
        return { ...item, autonomous: grant.autonomous };
      },
      run,
    );
  }

  // Group the catalog by source so built-ins and each external source read as their own section.
  const groups = useMemo(() => groupBySource(tools ?? [], (t) => t.source), [tools]);

  return (
    <FieldGroup title="Abilities">
      {/* The API affordance for this persona lives in PersonaEditor's leafHeader (the persisted
          persona's ButtonBar `api`), one button per header — not here. */}
      <ErrorText error={loadError ?? error} />
      {tools === null ? (
        // A failed read leaves the catalog null too, and the banner above already says why — so
        // this must neither go on claiming the list is on its way nor call the catalog empty.
        loadError === null && <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : tools.length === 0 ? (
        <p className="text-sm text-apt-text-muted">No tools available.</p>
      ) : (
        <div className="flex flex-col gap-4">
          {groups.map(([label, rows]) => (
            <div key={label} className="flex flex-col gap-2">
              <h4 className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted">
                {label}
              </h4>
              <ul className="flex flex-col gap-2">
                {rows.map((tool) => {
                  const rowId = `${rowIdPrefix}-${tool.toolName}`;
                  // Disable only the row that's mid-mutation, so its box can't be
                  // re-clicked while its grant/revoke is in flight; other rows stay live.
                  const rowBusy = busyTools.has(tool.toolName);
                  return (
                    <li
                      key={tool.toolName}
                      className="flex items-start justify-between gap-3 rounded-lg border border-apt-border p-3"
                    >
                      <div className="flex min-w-0 flex-1 items-start gap-2">
                        <Checkbox
                          id={rowId}
                          checked={tool.granted}
                          disabled={rowBusy}
                          onCheckedChange={(checked) => toggleGrant(tool, checked)}
                          aria-label={`grant ${tool.displayName || tool.toolName}`}
                        />
                        {/* Human-readable label leads (the checkbox's accessible name); the
                            description + raw mono tool name are demoted siblings OUTSIDE the label
                            so the row reads as product copy, not an identifier. displayName falls
                            back to toolName for an uncataloged tool. */}
                        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                          <label htmlFor={rowId} className="text-sm text-apt-text">
                            {tool.displayName || tool.toolName}
                          </label>
                          {tool.description && (
                            <span className="text-[0.75rem] text-apt-text-muted">
                              {tool.description}
                            </span>
                          )}
                          <span
                            className="font-mono text-[0.7rem] text-apt-text-dim"
                            title={tool.toolName}
                          >
                            {tool.toolName}
                          </span>
                        </div>
                      </div>
                      {tool.granted && (
                        <div className="flex shrink-0 items-center gap-2">
                          <span className="text-[0.7rem] text-apt-text-dim">
                            {tool.autonomous ? "autonomous" : "requires approval"}
                          </span>
                          <Switch
                            checked={tool.autonomous}
                            disabled={rowBusy}
                            onCheckedChange={(checked) => toggleAutonomy(tool, checked)}
                            aria-label={`autonomy for ${tool.toolName}`}
                          />
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      )}
    </FieldGroup>
  );
}
