"use client";

import { useState } from "react";
import { Globe } from "lucide-react";
import type { SiteGroupView, SiteView } from "@agentic-toolkit/data/monitored-sites";
import { createSite, deleteSite, updateSite } from "@agentic-toolkit/data/monitored-sites";
import {
  CreateResourceDialog,
  MasterDetailLeaf,
  useMasterDetailForm,
  useMasterDetailLevel,
  useRecordAffordance,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import {
  SiteDetail,
  SiteFields,
  siteBlank,
  siteToInput,
  siteValidate,
  type SiteDraft,
} from "./SiteDetail";

function siteDiffers(a: SiteDraft, b: SiteDraft): boolean {
  return (
    a.name.trim() !== b.name.trim() ||
    a.slug.trim() !== b.slug.trim() ||
    a.groupId !== b.groupId
  );
}

function siteNormalize(d: SiteDraft): SiteDraft {
  return { name: d.name.trim(), slug: d.slug.trim(), groupId: d.groupId };
}

/**
 * Sites, dismantled into the one-stack model: the sites list is PUBLISHED as a deeper rail level
 * (via {@link useMasterDetailLevel}); this component renders only the editor leaf (a site's fields,
 * group, endpoints). Selection is URL-driven + deep-linkable when a `leaf` is threaded (the
 * Dashboards route, `…/dashboards/sites/<siteId>`), else local. Each site belongs to one group.
 */
export function SitesSection({
  sites,
  groups,
  busy = false,
  onChanged,
  leaf,
  reservedSlugs,
  workspaceSlug,
}: {
  sites: SiteView[] | null;
  groups: SiteGroupView[];
  /** A read of the sites is in flight — drives the spinner in this level's title. Note the rows
   *  stay LIVE while it spins: the list on screen is the previous answer, not a lie, and
   *  disabling it would make every revalidation feel like a load. */
  busy?: boolean;
  onChanged: () => Promise<void>;
  /** Deep-linkable site selection (`…/dashboards/sites/<siteId>`); omit for internal. */
  leaf?: TopicLeaf;
  /** The HOST's reserved slug words (its URL-namespace protection) — rejected on save. */
  reservedSlugs?: ReadonlySet<string>;
  /** Pins every op to the WORKSPACE'S owning principal (backend `?workspace=`). */
  workspaceSlug?: string;
}) {
  const ws = { workspace: workspaceSlug };
  const renderRecordAffordance = useRecordAffordance();
  const urlSelection = leaf ? { selectedId: leaf.leafId, onSelect: leaf.onSelect } : undefined;
  // "New site" is a POPUP (like New Ecosystem), not an inline blank form: the dialog enables Save on
  // any input and surfaces the precise validation reason on click — so a missing group reads as
  // "Select a group…" instead of a silently-disabled Save (the Image #8 bug).
  const [newOpen, setNewOpen] = useState(false);

  const form = useMasterDetailForm<SiteView, SiteDraft>({
    items: sites,
    getId: (s) => s.id,
    urlSelection,
    blank: siteBlank,
    toInput: siteToInput,
    // Slug is unique per GROUP server-side (uq_sites_group_slug), so only the
    // slugs in the draft's own group can collide — checking globally would
    // wrongly reject a slug that's free within this group but used in another.
    validate: (draft, others, base) =>
      siteValidate(
        draft,
        others.filter((o) => o.groupId === draft.groupId).map((o) => o.slug),
        reservedSlugs,
        base?.slug,
      ),
    differs: siteDiffers,
    normalize: siteNormalize,
    create: (input) =>
      createSite({ name: input.name, slug: input.slug, groupId: input.groupId }, ws),
    update: (id, input) =>
      updateSite(id, { name: input.name, slug: input.slug, groupId: input.groupId }, ws),
    remove: (s) => deleteSite(s.id, ws),
    confirmDelete: (s) => `Delete site "${s.name}" and all its endpoints?`,
    refresh: onChanged,
    createLabel: "New site",
  });

  function groupLabel(id: string): string {
    return groups.find((g) => g.id === id)?.name ?? "";
  }

  // PUBLISH the sites as a deeper stack level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "monitor-sites-list",
    title: "Sites",
    form,
    items: sites,
    getId: (s) => s.id,
    getLabel: (s) => s.name,
    getSublabel: (s) => groupLabel(s.groupId) || "No group",
    itemIcon: <Globe size={16} aria-hidden />,
    newLabel: "New site",
    leaf,
    busy,
    emptyLabel: sites === null ? "Loading…" : "No sites yet.",
    onNew: () => setNewOpen(true),
  });

  return (
    <>
      <MasterDetailLeaf
        form={form}
        trailing={renderRecordAffordance?.({
          path: "/monitoring/sites/{id}",
          pathValues: { id: form.selectedId },
          title: "Monitored site API",
        })}
        emptyTitle={sites === null ? "Loading…" : "Select a site to edit, or create a new one."}
        renderDetail={(draft) => (
          <SiteDetail
            key={form.detailKey}
            title="Site"
            draft={draft}
            onChange={form.onChange}
            groups={groups}
            siteId={form.selected?.id ?? null}
            workspaceSlug={workspaceSlug}
            error={form.error}
          />
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New site"
          heading="New site"
          blank={siteBlank}
          // Slug is unique per GROUP (uq_sites_group_slug), so only slugs in the draft's own group
          // can collide. A missing group returns a visible "Select a group…" (never a silent disable).
          validate={(d) =>
            siteValidate(
              d,
              (sites ?? []).filter((s) => s.groupId === d.groupId).map((s) => s.slug),
              reservedSlugs,
            )
          }
          create={(d) => createSite({ name: d.name, slug: d.slug, groupId: d.groupId }, ws)}
          onClose={() => setNewOpen(false)}
          onCreated={(site) => {
            setNewOpen(false);
            void onChanged();
            leaf?.onSelect(site.id);
          }}
          renderForm={(draft, onChange, error) => (
            <SiteFields draft={draft} onChange={onChange} groups={groups} error={error} />
          )}
        />
      )}
    </>
  );
}
