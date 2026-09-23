"use client";

import { useCallback, useEffect, useMemo, useState, type ReactElement } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Building2, Gauge, MapPin, Share2 } from "lucide-react";
import { ErrorText, useAction } from "@agentic-toolkit/crud";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { DeleteEntitySection } from "@agentic-toolkit/adh-ui/blocks";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";
import { RdidEditor } from "@agentic-toolkit/adh-ui/components/rdid-editor";
import { validateLeaf } from "@agentic-toolkit/adh-ui/rdid";
import { approveNavigation } from "@agenticdevelopertoolkit/ui/lib/navigation-guard";
import {
  checkWorkspaceSlugAvailable,
  useResourceItemWriter,
  WORKSPACES_QUERY_KEY,
} from "@agentic-toolkit/data";
import {
  organizationsApi,
  ORGANIZATIONS_QUERY_KEY,
  type Organization,
} from "@agentic-toolkit/data/organizations";
import {
  StackGroupDetail,
  useReportSettingsDirty,
  useResourceItem,
  type GroupTopicItem,
  type ResourceItem,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import { SocialLinksPanel, AddressesPanel, UsagePanel } from "@agentic-toolkit/profile";

/**
 * The item-cache key the organization's own record is filed under, keyed by SLUG.
 *
 * Exported because warming an entry and reading one are done by different components — the feature
 * prefetches on hover, this group reads on open — and two matching string literals in two files
 * agree only by luck. A prefetch onto a key nothing reads costs a request and leaves the click
 * exactly as slow as before, while every prop typechecks and every test of either half passes.
 */
export const ORG_RECORD_CACHE_KEY = "workspace-org";

/**
 * Where a save that changes the org's identity should land the browser.
 *
 * Both are the HOST's to decide, with no default, and deliberately so: the hub addresses an
 * organization as a workspace (`/<slug>/settings`) while the organizations site addresses it as
 * an item inside one (`/<workspace>/<slug>/settings`). A default written here would be one
 * host's URL space, and it would keep looking correct on that host forever — the defect would
 * only surface on the second one.
 */
export interface OrgSettingsHrefs {
  /** After a rename: the same pane under the org's NEW handle. */
  renamed: (newSlug: string) => string;
  /** After an archive: somewhere that still resolves once this org stops existing. */
  archived: string;
}

/**
 * The organization Settings group: Social links + Addresses + Usage + Settings (the org's own
 * record), as levels of the ONE hierarchical stack.
 *
 * No Members row. An organization's people are answered by its Teams, which group them and the
 * permissions they share; a roster here was a second door onto the same people. The ROUTE it used
 * to lead to is untouched: `/<slug>/members` still resolves.
 *
 * Social links and Addresses are ORG-owned here (`workspaceSlug` = the org slug) and carry NO
 * per-item privacy tiers — an org has no public card, so `hidePrivacy`. Usage is listed for every
 * member but admin-gated server-side: a non-admin gets a 403 the panel renders as "workspace-admin
 * only" rather than as an error.
 */
export function OrgSettingsGroup({
  slug,
  hrefs,
  leaf,
}: {
  /** The organization being edited. Optional because a resource rail hands its topics the
   *  selected id, and nothing is selected until one is picked. */
  slug: string | undefined;
  hrefs: OrgSettingsHrefs;
  /** The group's own row selection (`…/settings/<row>`). */
  leaf?: TopicLeaf;
}): ReactElement {
  // The org's own record — the body behind the Profile row, and the ONE read this group makes.
  //
  // Held HERE rather than inside the pane for two reasons. It is the only way the topic list can
  // report the read: a member pane cannot reach the level its group publishes. And it starts the
  // read when the group opens rather than when Profile is picked, so the record is usually already
  // in hand by the time the row is clicked — the same head start the explorer's hover prefetch
  // gives, taken one step later for anyone who arrives without hovering.
  //
  // `useResourceItem`, not a bare query: it paints the previously-read copy on the first frame and
  // revalidates behind it, and it tells the host when the org has been archived out from under the
  // stack — which is a real event here, because archiving is offered by this very pane, on another
  // device or another tab.
  const org = useResourceItem<Organization>(
    ORG_RECORD_CACHE_KEY,
    slug ?? null,
    organizationsApi.resolve,
  );
  // Write the save's own answer back into the entry it came from, rather than invalidating: the
  // caller is holding the server's copy, so a re-read would spend a request to arrive back at it.
  // Keyed by `slug` — the id the read used — because a rename hands back a record that no longer
  // carries it, and the saved copy would otherwise be filed under a slug nobody will look up.
  const writeOrg = useResourceItemWriter<Organization>(ORG_RECORD_CACHE_KEY);
  const onSaved = useCallback(
    (next: Organization) => {
      if (slug) writeOrg(slug, next);
    },
    [writeOrg, slug],
  );
  const items: GroupTopicItem[] = useMemo(
    () => [
      {
        id: "social",
        label: "Social links",
        icon: <Share2 size={16} aria-hidden />,
        render: () => <SocialLinksPanel workspaceSlug={slug} hidePrivacy />,
      },
      {
        id: "addresses",
        label: "Addresses",
        icon: <MapPin size={16} aria-hidden />,
        render: () => <AddressesPanel workspaceSlug={slug} hidePrivacy />,
      },
      {
        id: "usage",
        label: "Usage",
        icon: <Gauge size={16} aria-hidden />,
        render: () => <UsagePanel workspaceSlug={slug} />,
      },
      // Last: the org's editable fields. It used to be Settings ▸ Profile, which named a public
      // page the org does not have. The id stays `profile` so every existing deep link still
      // resolves.
      {
        id: "profile",
        label: "Settings",
        icon: <Building2 size={16} aria-hidden />,
        render: () => <OrgSettingsPane org={org} hrefs={hrefs} onSaved={onSaved} />,
      },
    ],
    [slug, hrefs, org, onSaved],
  );
  return (
    <StackGroupDetail
      levelId="org-settings"
      title="Settings"
      items={items}
      // The spinner in front of "Settings", for the ONE read this group holds itself: the
      // Settings member's.
      // Social links, Addresses and Usage each read inside their own pane, a component below this
      // level and unable to reach it — so they call `useReportBusy` and the host raises the same
      // flag on their behalf. Hoisting those three here instead would fire all four requests the
      // moment the group opens, to report whichever one the user actually asked for.
      busy={org.isFetching}
      urlSelection={leaf ? { selectedId: leaf.leafId, onSelect: leaf.onSelect } : undefined}
    />
  );
}

/** The group's blurb — the rail's topic overview and the breadcrumb help popover both read it. */
export const ORG_SETTINGS_DESCRIPTION =
  "This organization's own record — its name and handle, the links and addresses it " +
  "publishes, and what its people have used.";

/** Edit an organization's own fields. Save PATCHes only the changed fields, so a name/description
 *  edit never trips the slug's site-admin gate.
 *
 *  The record arrives already read — {@link OrgSettingsGroup} holds it, so the topic list can spin
 *  while it lands. This turns the three states it can be in into the three things to render. */
export function OrgSettingsPane({
  org,
  hrefs,
  onSaved,
}: {
  org: ResourceItem<Organization>;
  hrefs: OrgSettingsHrefs;
  /** Record what the save returned. Owned by {@link OrgSettingsGroup}, which is where the id this
   *  record is cached under lives — after a rename the saved copy no longer carries it. */
  onSaved: (org: Organization) => void;
}): ReactElement {
  if (org.error) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center p-6">
        <EmptyState
          title="Couldn't load this organization"
          description="Reload the page to retry."
        />
      </div>
    );
  }
  if (!org.item) return loading();
  return (
    <OrgSettingsForm
      org={org.item}
      hrefs={hrefs}
      // Locked until the server's answer for THIS org is on screen. A cached copy paints first and
      // is revalidated behind it, so without the lock an edit could be typed into last week's name
      // and then PATCHed over whatever the server has now. On the normal path the copy is fresh,
      // nothing is in flight, and the form is live on the first frame.
      readOnly={!org.isSettled}
      onSaved={onSaved}
    />
  );
}

/** Exported for the dirty-reporting tests, which mount the form directly rather than
 *  standing up the whole workspace route around it. */
export function OrgSettingsForm({
  org,
  hrefs,
  onSaved,
  readOnly = false,
}: {
  org: Organization;
  hrefs: OrgSettingsHrefs;
  onSaved: (org: Organization) => void;
  /** The copy on screen has not been confirmed by the server yet — a cached record is painting
   *  while its re-read is in flight. Locks the fields and Save, so nothing is typed into a stale
   *  name and then written over what the server actually has. Defaults to false: a caller holding
   *  a record it read itself has nothing to wait for. */
  readOnly?: boolean;
}): ReactElement {
  const [name, setName] = useState(org.name);
  const [slug, setSlug] = useState(org.slug);
  const [description, setDescription] = useState(org.description ?? "");
  const { busy, error, run } = useAction();
  const qc = useQueryClient();

  // Re-sync the form whenever the loaded org changes — after a save that renamed the workspace's
  // URL space, and now also when a background revalidation lands behind the instant paint. NEVER
  // over an unsaved edit: caching is what makes that distinction necessary, because a re-read can
  // arrive mid-edit where the pre-cache code read once per org and could not, and `readOnly` is no
  // defence (it follows `isSettled`, which stays true for exactly these background reads). While
  // the user has typing on screen, Save or Discard is their call, not a refetch's.
  //
  // "Edited" is measured against the copy the fields were SEEDED from, not the one that just
  // arrived. Diffing against the new copy would read a change made ELSEWHERE as the user's own
  // typing and then refuse to ever re-sync again, pinning the form to a value nobody entered.
  //
  // Done during the render that first sees the new record (React's own idiom for state that must
  // reset on a prop change) rather than in an effect, so no frame paints the previous org's values.
  const [seeded, setSeeded] = useState(org);
  if (seeded !== org) {
    const edited =
      name !== seeded.name || slug !== seeded.slug || description !== (seeded.description ?? "");
    setSeeded(org);
    if (!edited) {
      setName(org.name);
      setSlug(org.slug);
      setDescription(org.description ?? "");
    }
  }

  const dirty =
    name !== org.name || slug !== org.slug || description !== (org.description ?? "");
  // The same fact the Save button is gated on, published to the exit guard — otherwise the
  // draft is only defended by a disabled button, and leaving the pane drops it silently.
  // Keyed by org id: the rail can hold one of these per workspace.
  useReportSettingsDirty(`org-settings:${org.id}`, dirty);

  // ── Slug availability (debounced) ─────────────────────────────────────────
  // The same probe the personal ProfilePanel uses, and deliberately so:
  // `/auth/slug-available/:slug` answers for the ONE workspace URL namespace that users and orgs
  // share, so it is the only endpoint that can tell this form the truth. Renaming an org into a
  // customer's handle is refused by the PATCH route too (409 'slug already in use by a user');
  // checking here turns that into an answer before the user commits rather than after.
  const [debouncedSlug, setDebouncedSlug] = useState(slug);
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSlug(slug), 350);
    return () => clearTimeout(timer);
  }, [slug]);

  const clientSlugError = validateLeaf(slug);
  // Never probe the org's own current handle: the endpoint excludes only the CALLER's user id,
  // so this org's live row would come back 'taken' and the form would refuse its own slug.
  const shouldCheckAvailability =
    Boolean(debouncedSlug) && !validateLeaf(debouncedSlug) && debouncedSlug !== org.slug;

  const slugAvailQuery = useQuery({
    queryKey: ["auth", "slug-available", debouncedSlug],
    queryFn: () => checkWorkspaceSlugAvailable(debouncedSlug),
    enabled: shouldCheckAvailability,
    retry: false,
    staleTime: 30_000,
  });

  type SlugStatus = "idle" | "checking" | "available" | "unavailable" | "avail-error";
  // THE QUERY ANSWERS ABOUT `debouncedSlug`, so its verdict means nothing until the draft has
  // caught up — that is the first thing this decides, before any branch reads the query.
  //
  // Reading it while the two disagree showed the user a verdict about a slug they had already
  // moved on from. Type a taken handle, then correct it back to the org's own: `debouncedSlug`
  // still held the taken one for another 350ms, and only the "the draft differs from the stored
  // slug" arm suppressed the stale answer — which is exactly the arm that goes false when you
  // return to your own slug. The pane then told you your CURRENT handle was already taken.
  //
  // Unsettled falls to "checking", except on the org's own stored slug: the post-rename re-seed
  // above sets `slug` while `debouncedSlug` trails, and "Checking…" over a slug nobody touched is
  // the same lie in the other direction.
  const slugSettled = debouncedSlug === slug;
  const slugStatus: SlugStatus = !slug
    ? "idle"
    : !slugSettled
      ? slug === org.slug
        ? "idle"
        : "checking"
      : !shouldCheckAvailability
        ? "idle"
        : slugAvailQuery.isFetching
          ? "checking"
          : slugAvailQuery.data?.available
            ? "available"
            : slugAvailQuery.data
              ? "unavailable"
              : slugAvailQuery.isError
                ? "avail-error"
                : "idle";

  // The client grammar error wins (it is about what was typed); otherwise the probe's verdict.
  const slugError =
    slug !== org.slug && clientSlugError
      ? clientSlugError
      : slugStatus === "unavailable"
        ? "That handle is already taken."
        : slugStatus === "avail-error"
          ? "Couldn't check availability — try again"
          : undefined;

  const slugHint =
    slugStatus === "checking"
      ? "Checking…"
      : slugStatus === "available"
        ? "Available."
        : "Site-admin only — renames the org's global identifiers";

  // A rename known to be refused must not be submittable: the PATCH would 409 and the pane would
  // report a failure the form could already see coming.
  //
  // AN ALLOW-LIST, matching ProfilePanel's `slugClearToSave` — a rename is submittable only on a
  // status that positively clears it. The deny-list this replaces named three bad statuses and let
  // everything else through, so every state it had not thought of defaulted to SUBMITTABLE. "idle"
  // is exactly such a state and it is reachable with an unverified slug: the tick after the debounce
  // lands, `enabled` has just flipped true but `isFetching` is still false and there is no data and
  // no error yet — a real window in which Save was live on a handle nobody had checked.
  //
  // "avail-error" is deliberately IN the allow-list, for the reason ProfilePanel already documents:
  // when the probe itself fails we cannot say the handle is taken, and the PATCH route re-checks
  // anyway — leaving Save silently dead because a background query errored is the worse failure.
  const slugBlocked =
    slug !== org.slug &&
    (Boolean(clientSlugError) ||
      !(slugStatus === "available" || slugStatus === "avail-error"));

  function save(): void {
    void run(async () => {
      const renamed = await organizationsApi.rename(org.id, {
        ...(name !== org.name ? { name } : {}),
        ...(slug !== org.slug ? { slug } : {}),
        ...(description !== (org.description ?? "") ? { description } : {}),
      });
      onSaved({ ...org, ...renamed });
      // This pane is not the only place the org's name and handle are shown: the workspace
      // bar, the switcher and every rail reading the workspace list are fed by
      // WORKSPACES_QUERY_KEY, which this save has just made stale. Without this the rename
      // is visible only in the form the user typed it into.
      void qc.invalidateQueries({ queryKey: WORKSPACES_QUERY_KEY });
      // BOTH lists, because they are two caches over two endpoints since organizations grew an
      // owning workspace: the switcher's membership list above, and the orgs rail's
      // owner-scoped list here. The rail is where a renamed org is most visibly the same row.
      void qc.invalidateQueries({ queryKey: ORGANIZATIONS_QUERY_KEY });
      // A slug change moves the whole workspace URL space; land on the renamed
      // organization's settings rather than a dead slug.
      if (renamed.slug !== org.slug) {
        // The draft still reads dirty here — it is measured against the `org` prop, and the
        // re-render carrying the saved one never arrives on a page that is leaving. So the
        // exit guard is armed, and would veto this unload as if the edits were being
        // abandoned; the browser would then keep a URL whose slug no longer resolves.
        approveNavigation();
        window.location.assign(hrefs.renamed(renamed.slug));
      }
    });
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-6">
        <FieldGroup title="Organization">
          <Field label="name">
            <Input
              value={name}
              disabled={readOnly}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>
          {/* The same control the New Organization dialog uses: `org.` is minted server-side and
              is never the user's to edit, so it is static text beside the editable leaf. */}
          <RdidEditor
            label="slug"
            prefix="org."
            value={slug}
            placeholder={org.slug}
            hint={slugHint}
            error={slugError}
            disabled={readOnly}
            onChange={setSlug}
          />
          <Field label="description">
            <Textarea
              value={description}
              disabled={readOnly}
              onChange={(e) => setDescription(e.target.value)}
              rows={4}
              placeholder="What this organization is about"
            />
          </Field>
          <ErrorText error={error} />
          <div className="flex justify-end">
            <Button size="sm" disabled={busy || !dirty || slugBlocked || readOnly} onClick={save}>
              {busy ? "Saving…" : "Save"}
            </Button>
          </div>
        </FieldGroup>
        {/* Archive, not delete: the org's data is kept and the action is reversible from Archived
            in personal settings. The type-to-confirm ceremony is unchanged, because releasing
            `org.<slug>` for anyone to claim is not something to do by mis-click. */}
        <DeleteEntitySection
          entityNoun="Organization"
          confirmValue={org.slug}
          childEntities="its handle, which is released for anyone to claim"
          actionVerb={{ imperative: "Archive", gerund: "Archiving", reversible: true }}
          description={
            <>
              Archiving removes this organization from your workspaces and releases its{" "}
              <span className="font-mono">org.{org.slug}</span> handle for reuse. Its data is kept,
              and you can restore it from Archived in your personal settings — but only while
              nobody else has taken the handle.
            </>
          }
          onConfirm={async () => {
            await organizationsApi.archive(org.id);
            // This workspace has just stopped resolving; staying on its URL would 404.
            window.location.assign(hrefs.archived);
          }}
        />
      </div>
    </div>
  );
}

/** The stack's loading placeholder. A local copy of the hub's one-liner rather than an import:
 *  it is a styled `Loading…`, not a piece of knowledge, and importing it would point this
 *  package at the host it was extracted from. */
function loading(): ReactElement {
  return <p className="p-4 text-sm text-apt-text-muted">Loading…</p>;
}
