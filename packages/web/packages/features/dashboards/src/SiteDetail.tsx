"use client";

import type { SiteGroupView, SiteView } from "@agentic-toolkit/data/monitored-sites";
import { validateSlug } from "@agenticdevelopertoolkit/ui/lib/slug";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { DetailSection, unchangedFromStored } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { EndpointsEditor } from "./EndpointsEditor";

export interface SiteDraft {
  name: string;
  slug: string;
  /** The single group this site belongs to (required). */
  groupId: string;
}

export function siteBlank(): SiteDraft {
  return { name: "", slug: "", groupId: "" };
}

export function siteToInput(s: SiteView): SiteDraft {
  return { name: s.name, slug: s.slug, groupId: s.groupId };
}

/** Returns an error message, or null when the draft is valid. `storedSlug` is the slug already on
 *  the site being edited (absent on a create) — exempts the slug's FORMAT rule only, the same
 *  pattern (and the same reasoning) as `groupValidate` next door in `GroupDetail.tsx`: a site the
 *  backend already accepted need not satisfy a client-side format rule added later. Uniqueness and
 *  the required-ness rules stay unconditional (Mike, 2026-09-25). */
export function siteValidate(
  draft: SiteDraft,
  takenSlugs: string[],
  reserved?: ReadonlySet<string>,
  storedSlug?: string,
): string | null {
  if (!draft.name.trim()) return "Site name is required.";
  const slug = draft.slug.trim();
  // Required-ness is unconditional: `unchangedFromStored("", "")` is true, so exempting BEFORE this
  // check would let an empty slug through whenever the stored one was empty too.
  if (!slug) return "Slug is required.";
  if (!unchangedFromStored(slug, storedSlug)) {
    const slugError = validateSlug(slug, reserved);
    if (slugError) return slugError;
  }
  if (takenSlugs.includes(slug)) return `Slug "${slug}" is already in use.`;
  if (!draft.groupId) return "Select a group for this site.";
  return null;
}

/**
 * The site FIELDS (name, slug, group) — no button bar, no endpoints. Shared by the inline editor
 * ({@link SiteDetail}) and the "New site" popup (CreateResourceDialog), so both surfaces validate
 * and present the group requirement identically. When no groups exist, the group field guides the
 * user to create one first (and `siteValidate` blocks Save with a visible reason, not a silent
 * disable).
 */
export function SiteFields({
  draft,
  onChange,
  groups,
  error,
}: {
  draft: SiteDraft;
  onChange: (next: SiteDraft) => void;
  groups: SiteGroupView[];
  error?: string | null;
}) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <div className="flex flex-col gap-2">
          <Label htmlFor="site-name">Name</Label>
          <Input
            id="site-name"
            placeholder="Marketing Site"
            value={draft.name}
            onChange={(e) => onChange({ ...draft, name: e.target.value })}
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor="site-slug">Slug</Label>
          <Input
            id="site-slug"
            placeholder="marketing-site"
            value={draft.slug}
            onChange={(e) => onChange({ ...draft, slug: e.target.value.toLowerCase() })}
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
          />
        </div>

        <div className="flex flex-col gap-2">
          <Label htmlFor="site-group">Group</Label>
          {groups.length === 0 ? (
            <p className="text-xs text-apt-text-muted">
              No groups defined yet. Add a group first, then assign this site.
            </p>
          ) : (
            <Select
              id="site-group"
              value={draft.groupId}
              onChange={(e) => onChange({ ...draft, groupId: e.target.value })}
            >
              <option value="">Select a group…</option>
              {groups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </Select>
          )}
        </div>

        <ErrorText error={error} />
      </CardContent>
    </Card>
  );
}

/**
 * Controlled site editor for an EXISTING site — the fields ({@link SiteFields}) plus the endpoints
 * sub-section (its own CRUD, not part of the site save). Save/Cancel/Delete live in the
 * MasterDetailLayout button bar. New sites are created through the "New site" popup instead.
 */
export function SiteDetail({
  title,
  draft,
  onChange,
  groups,
  siteId,
  workspaceSlug,
  error,
}: {
  title: string;
  draft: SiteDraft;
  onChange: (next: SiteDraft) => void;
  groups: SiteGroupView[];
  /** Persisted site id, or null when creating (endpoints unavailable until saved). */
  siteId: string | null;
  /** Pins the endpoints sub-CRUD to the WORKSPACE'S owning principal (backend `?workspace=`). */
  workspaceSlug?: string;
  error?: string | null;
}) {
  return (
    <>
      <DetailSection title={title}>
        <SiteFields draft={draft} onChange={onChange} groups={groups} error={error} />
      </DetailSection>

      <DetailSection title="Endpoints">
        {siteId ? (
          <EndpointsEditor siteId={siteId} workspaceSlug={workspaceSlug} />
        ) : (
          <EmptyState className="min-h-0 px-4 py-6" title="Save the site first, then add endpoints to probe." />
        )}
      </DetailSection>
    </>
  );
}
