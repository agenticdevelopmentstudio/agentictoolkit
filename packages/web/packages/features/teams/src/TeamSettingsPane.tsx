"use client";

import type { ReactElement, ReactNode } from "react";

import { teamsApi, type Team, type TeamInput } from "@agentic-toolkit/data/teams";
import {
  useMasterDetailForm,
  RecordSettingsPane,
  useRecordAffordance,
} from "@agentic-toolkit/resource";
import { DeleteEntitySection } from "@agentic-toolkit/adh-ui/blocks";
import { TeamDetail, teamBlank, teamToInput, teamValidate } from "./TeamDetail";

function differs(a: TeamInput, b: TeamInput): boolean {
  return (Object.keys(a) as (keyof TeamInput)[]).some(
    (k) => a[k].trim() !== b[k].trim(),
  );
}

function normalize(d: TeamInput): TeamInput {
  return { displayName: d.displayName.trim(), identifier: d.identifier.trim() };
}

/** Settings editor for the active team (Display name / Identifier) + Danger zone. */
export function TeamSettingsPane({
  teamId,
  items,
  ecosystemId,
  refresh,
  loadError,
  title,
  onDelete,
}: {
  teamId?: string;
  /** The teams list, owned by the parent tab (shared with the selector). */
  items: Team[] | null;
  /** The workspace's ecosystem — a team created from this pane is stamped into it
   *  (its owner), so it lands in the workspace it was created under. */
  ecosystemId?: string;
  /** Re-read the list after a mutation (the parent tab's reload). */
  refresh: () => void | Promise<void>;
  loadError?: string | null;
  title?: ReactNode;
  /** Delete the active team (and navigate away). Renders the Danger section. */
  onDelete?: () => Promise<void>;
}): ReactElement {
  // The host-injected per-record affordance (the hub's api-explorer button); null on
  // a standalone feature site → the trailing slot renders nothing.
  const renderRecordAffordance = useRecordAffordance();
  const form = useMasterDetailForm<Team, TeamInput>({
    items,
    getId: (t) => t.id,
    blank: teamBlank,
    toInput: teamToInput,
    validate: (draft, others, base) =>
      teamValidate(draft, others.map((o) => o.identifier), base?.identifier),
    differs,
    normalize,
    // Guarded for safety — the pane only renders once the list (hence the ecosystem)
    // has resolved, so this rejection is effectively unreachable.
    create: (input) =>
      ecosystemId
        ? teamsApi.create(input, ecosystemId)
        : Promise.reject(new Error("Workspace is still loading.")),
    update: (id, input) => teamsApi.update(id, input),
    // Delete is owned by the Danger-zone DeleteEntitySection (onDelete), not the hook.
    refresh,
    createLabel: "New team",
  });

  const active = items?.find((t) => t.id === teamId);

  return (
    <RecordSettingsPane
      form={form}
      activeId={teamId}
      items={items}
      getId={(t) => t.id}
      title={title}
      trailing={renderRecordAffordance?.({
        path: "/team/teams/{id}",
        pathValues: { id: teamId },
        title: "Team API",
      })}
      loadError={loadError}
      emptyLabel={
        items === null ? "Loading…" : "Select a team in the sidebar, or create a new one."
      }
      renderDetail={(draft) => (
        <div className="flex flex-col gap-6">
          <TeamDetail
            key={form.detailKey}
            title={form.creating ? "New team" : "Team"}
            draft={draft}
            onChange={form.onChange}
            error={form.error}
          />
          {!form.creating && active && onDelete && (
            <DeleteEntitySection
              entityNoun="Team"
              confirmValue={active.identifier}
              childEntities="its members and permission grants"
              onConfirm={onDelete}
            />
          )}
        </div>
      )}
    />
  );
}
