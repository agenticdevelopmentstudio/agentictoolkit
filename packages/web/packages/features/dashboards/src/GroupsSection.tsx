"use client";

import { useState, type ReactNode } from "react";
import { Layers } from "lucide-react";
import type { SiteGroupView } from "@agentic-toolkit/data/monitored-sites";
import { createGroup, deleteGroup, updateGroup } from "@agentic-toolkit/data/monitored-sites";
import {
  CreateResourceDialog,
  MasterDetailLeaf,
  useMasterDetailForm,
  useMasterDetailLevel,
  useRecordAffordance,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import {
  GroupDetail,
  groupBlank,
  groupToInput,
  groupValidate,
  type GroupDraft,
} from "./GroupDetail";

function groupDiffers(a: GroupDraft, b: GroupDraft): boolean {
  return (Object.keys(a) as (keyof GroupDraft)[]).some((k) => a[k].trim() !== b[k].trim());
}

function groupNormalize(d: GroupDraft): GroupDraft {
  // retentionDays stays the string input; the create/update adapters parse it.
  return { name: d.name.trim(), slug: d.slug.trim(), retentionDays: d.retentionDays };
}

/**
 * Groups, dismantled into the one-stack model: the groups list is PUBLISHED as a deeper rail level
 * (via {@link useMasterDetailLevel}); this component renders only the editor leaf (a group's name /
 * slug / retention). Selection is URL-driven + deep-linkable when a `leaf` is threaded (the
 * Dashboards route, `…/dashboards/groups/<groupId>`), else local. Sites reference these groups.
 */
export function GroupsSection({
  groups,
  busy = false,
  onChanged,
  leaf,
  reservedSlugs,
  workspaceSlug,
  renderTransferOwnership,
}: {
  groups: SiteGroupView[] | null;
  /** A read of the groups is in flight — drives the spinner in this level's title. Note the
   *  rows stay LIVE while it spins: the list on screen is the previous answer, not a lie, and
   *  disabling it would make every revalidation feel like a load. */
  busy?: boolean;
  onChanged: () => Promise<void>;
  /** Deep-linkable group selection (`…/dashboards/groups/<groupId>`); omit for internal. */
  leaf?: TopicLeaf;
  /** The HOST's reserved slug words (its URL-namespace protection) — rejected on save. */
  reservedSlugs?: ReadonlySet<string>;
  /** Pins every op to the WORKSPACE'S owning principal (backend `?workspace=`). */
  workspaceSlug?: string;
  /**
   * Host-injected Transfer Ownership section for the open group, rendered under the INLINE editor
   * below. Absent on a standalone feature site (`frontend/src/marketing/dashboards` mounts
   * `DashboardsFeature` without it) — the host owns the workspace list and the mutation.
   *
   * A group, not a site: `SitesSection` has no equivalent seam, because `SiteView.groupId`
   * (@agentic-toolkit/data/monitored-sites) is a required field — "the single group this site
   * belongs to" — so a site moved on its own would still be a member of a group in the workspace
   * it just left.
   */
  renderTransferOwnership?: (group: { id: string; name: string }) => ReactNode;
}) {
  const ws = { workspace: workspaceSlug };
  const renderRecordAffordance = useRecordAffordance();
  const urlSelection = leaf ? { selectedId: leaf.leafId, onSelect: leaf.onSelect } : undefined;
  // "New group" is a POPUP (like New Ecosystem / New site), not an inline blank form.
  const [newOpen, setNewOpen] = useState(false);

  const form = useMasterDetailForm<SiteGroupView, GroupDraft>({
    items: groups,
    getId: (g) => g.id,
    urlSelection,
    blank: groupBlank,
    toInput: groupToInput,
    validate: (draft, others, base) =>
      groupValidate(draft, others.map((o) => o.slug), reservedSlugs, base?.slug),
    differs: groupDiffers,
    normalize: groupNormalize,
    create: (input) =>
      createGroup(
        {
          name: input.name,
          slug: input.slug,
          retentionDays: parseInt(input.retentionDays, 10),
        },
        ws,
      ),
    update: (id, input) =>
      updateGroup(
        id,
        {
          name: input.name,
          slug: input.slug,
          retentionDays: parseInt(input.retentionDays, 10),
        },
        ws,
      ),
    remove: (g) => deleteGroup(g.id, ws),
    confirmDelete: (g) =>
      `Delete group "${g.name}"? Its sites and their endpoints will be deleted too.`,
    refresh: onChanged,
    createLabel: "New group",
  });

  // PUBLISH the groups as a deeper stack level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "monitor-groups-list",
    title: "Groups",
    form,
    items: groups,
    getId: (g) => g.id,
    getLabel: (g) => g.name,
    getSublabel: (g) => `${g.slug} · ${g.retentionDays}d`,
    itemIcon: <Layers size={16} aria-hidden />,
    newLabel: "New group",
    leaf,
    busy,
    emptyLabel: groups === null ? "Loading…" : "No groups yet.",
    onNew: () => setNewOpen(true),
  });

  return (
    <>
      <MasterDetailLeaf
        form={form}
        trailing={renderRecordAffordance?.({
          path: "/monitoring/site-groups/{id}",
          pathValues: { id: form.selectedId },
          title: "Site group API",
        })}
        emptyTitle={groups === null ? "Loading…" : "Select a group to edit, or create a new one."}
        // The transfer section belongs to the INLINE editor and only to it. `renderDetail` is
        // called by MasterDetailLeaf alone; the "New group" popup below builds its own GroupDetail
        // through CreateResourceDialog's `renderForm`, so a section placed inside GroupDetail
        // itself would appear in the creation popup and offer to move a group that does not exist
        // yet. `form.selected` (the SAVED row, resolved from `groups` by the selected id) is what
        // it is handed for the same reason the id alone would not do: the name in the fields above
        // is a draft until Save, and the dialog must name the group the server knows.
        renderDetail={(draft) => (
          <div key={form.detailKey} className="flex flex-col gap-6">
            <GroupDetail
              title="Group"
              draft={draft}
              onChange={form.onChange}
              error={form.error}
            />
            {form.selected && renderTransferOwnership && renderTransferOwnership(form.selected)}
          </div>
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New group"
          heading="New group"
          blank={groupBlank}
          validate={(d) => groupValidate(d, (groups ?? []).map((g) => g.slug), reservedSlugs)}
          create={(d) =>
            createGroup(
              {
                name: d.name,
                slug: d.slug,
                retentionDays: parseInt(d.retentionDays, 10),
              },
              ws,
            )
          }
          onClose={() => setNewOpen(false)}
          onCreated={(group) => {
            setNewOpen(false);
            void onChanged();
            leaf?.onSelect(group.id);
          }}
          renderForm={(draft, onChange, error) => (
            <GroupDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      )}
    </>
  );
}
