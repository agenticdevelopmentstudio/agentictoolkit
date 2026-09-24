"use client";

import { useCallback, useEffect, useState, type ReactElement, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import {
  Settings, Table2, Users, KeyRound, Network, Boxes, Plus, Inbox, Send, Database,
  ShieldCheck, LogIn, MailPlus,
} from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { isRdid } from "@agentic-toolkit/adh-ui/rdid";
import {
  ResourceExplorer,
  ResourceLanding,
  CreateResourceDialog,
  StackGroupDetail,
  useStackLevel,
  type ResourceTopic,
  type TopicLeaf,
  type GroupTopicItem,
} from "@agentic-toolkit/resource";
import { useResourceList, makeEntityDeleteHandler, writeLastId } from "@agentic-toolkit/data";
import {
  ecosystemsApi,
  useProvisionedFeatures,
  useWorkspaceDefaultEcosystemId,
  type Ecosystem,
} from "@agentic-toolkit/data/ecosystems";
import { heldTopics } from "./heldTopics";
import { EcosystemSettingsPane } from "./EcosystemSettingsPane";
import { ManageFeaturesButton } from "./ManageFeaturesButton";
import {
  EcosystemDetail,
  ecoBlank,
  ecoValidate,
  ecoNormalize,
  rehangIdentifier,
} from "./EcosystemDetail";
import {
  EcosystemCreateForm,
  ecoCreateBlank,
  ecoCreatePrefix,
  ecoCreateReady,
  ecoCreateToInput,
  ecoCreateValidate,
  type EcosystemParentRdid,
} from "./EcosystemForm";
import { EcoRequestsPane, EcoPendingUsersPane, EcoInvitesPane } from "./EcosystemInvitationPanes";
import { an } from "./lib/an";

/** The host's ecosystem-scoped topic rail config (the hub's `ECOSYSTEM_TOPICS` SSoT),
 *  with the icon already resolved by the host from its own icon registry (FEATURE_META
 *  for the workspace-feature topics, a host-local icon map for the rest) — the package
 *  never needs to know where an icon comes from, only how to render it. */
export interface EcosystemsTopicConfig {
  id: string;
  label: string;
  icon: ReactNode;
  /** What this topic is for. Carried on the row, rendered nowhere: the card grid it used to feed at
   *  an unselected frontier is gone (docs/ui/fleet-ui-audit.md §1.5). See `TopicDetailItem`. */
  description?: string;
  dividerAfter?: boolean;
  /** The catalog feature keys behind this row. When set, the row is drawn only while the scoped
   *  ecosystem holds at least one of them (see `heldTopics`), so the Features list and the Manage
   *  features dialog read the same set. Omit for a row that is not a catalog feature (Settings,
   *  Child Ecosystems, a feature site's own rows) — it is always drawn. */
  features?: readonly string[];
}

/** What `renderTopicPane` needs to reconstruct a host-owned config pane's exact call
 *  (mirrors the hub's Applications/Integrations/Schemas/Access/Users panes' shared
 *  `{ ecosystemId, title, help, leaf }` shape, minus `help` — the host's own renderer
 *  closure already has `helpFor` in scope, so it resolves its own help key per pane). */
export interface RenderTopicPaneCtx {
  ecosystemId?: string;
  title?: ReactNode;
  leaf?: TopicLeaf;
  /** Cedes the NEXT url segment to a group member, for a host that renders its OWN
   *  `StackGroupDetail` rather than using this package's `GROUP_IDS` (products' Gaming group
   *  does — its member list depends on the product's gaming mode, which is data, and
   *  `groupMembers` below is static).
   *
   *  Without this a host group could publish members but never deep-link INTO one, because
   *  `subLeafFor` reached only the in-package groups — the host got `leaf` and stopped there.
   *  That asymmetry had no reason behind it; a group is a group wherever it is rendered. */
  subLeafFor?: (memberId: string) => TopicLeaf;
}

/**
 * The topic rows for the topics this package renders ENTIRELY in-package (the entity
 * Settings pane and the Child Ecosystems rail). What an ecosystem is provisioned with is not
 * a topic: the topics list IS its features, so managing them lives in that list's own title
 * row (`ManageFeaturesButton`) rather than as one more row inside it. The package is the SSoT
 * for what it renders:
 * a host composing only these (a feature-site mount) spreads them instead of hand-copying
 * ids/labels/icons that would silently drift; the hub builds its fuller rail from its own
 * ECOSYSTEM_TOPICS catalog, where these two ids appear with the same meaning.
 */
export const IN_PACKAGE_TOPICS: EcosystemsTopicConfig[] = [
  {
    id: "settings",
    label: "Settings",
    icon: <Settings size={16} aria-hidden />,
    description: "The ecosystem's own record — name, identifier, and description.",
    dividerAfter: false,
  },
  {
    id: "child-ecosystems",
    label: "Child Ecosystems",
    icon: <Boxes size={16} aria-hidden />,
    description: "The ecosystems this one owns.",
    dividerAfter: false,
  },
];

export interface EcosystemsFeatureProps {
  basePath: string;
  /** The workspace slug whose (primary) ecosystem the feature opens on when the URL names
   *  none — the hub passes its route slug. Like basePath, supplied by the host rather than
   *  read from useParams here, so a host without a [slug] route (a feature site) fails
   *  visibly at the prop seam instead of silently deriving undefined. Absent ⇒ default-
   *  ecosystem resolution is disabled (the platform-wide ecosystem-scoping decision for
   *  site mounts — feature-platform-phase2 §2 — is still open) and a bare path renders the
   *  ecosystem card landing instead; deep-linked /<ecoId> paths never consult it. */
  workspaceSlug?: string;
  /** The ecosystem-scoped topic rail (host SSoT: settings/topics.ts's ECOSYSTEM_TOPICS). */
  topics: EcosystemsTopicConfig[];
  /** Render a non-ecosystems workspace feature's own content for a topic/group-member this
   *  feature reuses verbatim (Communities / Messaging / Research / Dashboards / All Data) —
   *  the host's `renderFeaturePanel` from feature-panels.tsx. */
  renderFeaturePanel?: (feature: string, opts?: { subLeaf?: TopicLeaf }) => ReactNode;
  /** Render a host-owned settings pane this feature composes but doesn't own: the topic ids
   *  "applications" | "integrations", and the group-member ids "buckets" | "access" | "users". */
  renderTopicPane?: (topicId: string, ctx: RenderTopicPaneCtx) => ReactNode;
  /** Contextual help lookup (the hub's helpFor), keyed `ecosystems/<topic>`. Only consulted for
   *  this feature's OWN pane (Settings) — renderTopicPane resolves help for host-owned panes
   *  itself. Omit to render no help. */
  helpFor?: (key: string) => string | undefined;
  activeTopic?: string;
  activeEcoId?: string;
  activeLeafId?: string;
  /** The 5th URL segment: the deep-linkable inner entity of an open GROUP member. */
  activeMemberEntityId?: string;
  /** The entity NOUN this feature presents (capitalized) — a host that surfaces
   *  ecosystems under its own concept (the hub's Products feature passes
   *  { singular: "Product", plural: "Products" }) renames every affordance (landing
   *  title, create dialog, empty states, breadcrumb name suffix) while this package
   *  keeps owning the ecosystem machinery. Defaults to Ecosystem / Ecosystems. */
  labels?: { singular?: string; plural?: string };
  /** LIST-FIRST presentation (the hub's Products feature). Requires `workspaceSlug`.
   *  Two coupled changes from the default arrangement:
   *  - The items are the ecosystems the WORKSPACE directly OWNS
   *    (ecosystemsApi.listForWorkspace — ownership, never the admin-widened
   *    manageable set), not the caller-manageable list.
   *  - The list is rail level 0 of ONE hierarchical topic-detail stack (classic
   *    ResourceExplorer, like Teams/Projects) — topics of the selected entity are the
   *    next level — instead of opening on the workspace default's topics with the
   *    list tucked into a Child Ecosystems topic. Creation is TOP-LEVEL (owner = the
   *    caller) from the list header's "+". */
  listFirst?: boolean;
  /** Host-injected Transfer Ownership section for the settings topic. Threaded straight through
   *  to EcosystemSettingsPane — this feature neither owns the workspace list nor the mutation. */
  renderTransferOwnership?: (ecosystem: { id: string; identifier: string }) => ReactNode;
}

/** The topic groups whose detail pane is a nested topic→detail sub-rail — the single source for
 *  both the membership check and the per-group members map below. */
const GROUP_IDS = ["storage", "invitations", "authentication"] as const;
type GroupId = (typeof GROUP_IDS)[number];
const isGroupId = (id: string): id is GroupId => (GROUP_IDS as readonly string[]).includes(id);

/**
 * The Child Ecosystems topic as a hierarchical topic-detail RAIL published into the merged stack
 * (like every sibling topic), not a card landing: the ecosystems this one owns are the rows, the
 * header `+` opens the New Ecosystem dialog, and selecting a child RE-SCOPES the whole Ecosystem
 * rail to it (its topics take column 3) — the same navigation the old cards did via `cardHref`.
 * Nothing is "selected within" this list (a pick drills out to the child), so `selectedId` is null.
 */
function ChildEcosystemsLevel({
  items,
  busy,
  basePath,
  onNew,
}: {
  items: Ecosystem[] | null;
  /** The children read is in flight. Drives the spinner ahead of "Child Ecosystems". */
  busy: boolean;
  basePath: string;
  onNew: () => void;
}): ReactElement {
  const router = useRouter();
  useStackLevel({
    id: "child-ecosystems-list",
    title: "Child Ecosystems",
    items: (items ?? []).map((e) => ({
      id: e.id,
      label: e.name,
      icon: <Boxes size={16} aria-hidden />,
    })),
    selectedId: null,
    onSelect: (id) => router.push(`${basePath}/${id}`, { scroll: false }),
    onClear: () => {},
    onNew,
    newLabel: "New Ecosystem",
    // The spinner in front of "Child Ecosystems". Nothing is selected WITHIN this list — a pick
    // drills out to the child and re-scopes the whole rail — so its own rows are the only read it
    // can report, and this is the one that matters: the query re-fetches every time the rail
    // re-scopes, and the rows on screen until it lands are the previous ecosystem's children.
    busy,
    emptyLabel: items === null ? "Loading…" : "No child ecosystems yet.",
  });
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <TopicSelectHint title="Select a child ecosystem to open it, or create a new one." />
    </div>
  );
}

// The members of each grouping topic, as nested topic→detail sub-rails. Ecosystem-scoped
// config panes (Buckets/Access/Users) take the selected ecosystem id + a scoped title, via
// the host-injected renderTopicPane; the feature members (All Data) reuse the feature's own
// content via renderFeaturePanel. `titleFor` scopes the pane title to the ecosystem.
function groupMembers(
  ecoId: string | undefined,
  titleFor: (label: string) => string,
  renderTopicPane: (topicId: string, ctx: RenderTopicPaneCtx) => ReactNode,
  renderFeaturePanel: (feature: string, opts?: { subLeaf?: TopicLeaf }) => ReactNode,
): Record<GroupId, GroupTopicItem[]> {
  // Each member render receives a `subLeaf` — the deep-linkable inner-entity selection ceded by the
  // group (the URL segment AFTER this member). Host-owned config panes take it as their `leaf`;
  // the feature panels take it (via renderFeaturePanel) as their `urlSelection`; members with no
  // inner URL-selection (All Data / Requests / Pending users / Invites) ignore it.
  return {
    storage: [
      { id: "buckets", label: "Buckets", icon: <Table2 size={16} aria-hidden />,
        description: "Reusable, composable collections of tables — applications grant permissions on these.",
        render: (subLeaf) => renderTopicPane("buckets", { ecosystemId: ecoId, title: titleFor("Buckets"), leaf: subLeaf }) },
      { id: "access", label: "Access", icon: <KeyRound size={16} aria-hidden />,
        description: "Access lists for the buckets: who can read or write each bucket, type, or row.",
        render: (subLeaf) => renderTopicPane("access", { ecosystemId: ecoId, title: titleFor("Access"), leaf: subLeaf }) },
      { id: "all-data", label: "All Data", icon: <Database size={16} aria-hidden />,
        description: "Browse and edit the raw rows behind every bucket.",
        render: () => renderFeaturePanel("all-data") },
    ],
    // Users (topic id "invitations", kept for deep-link stability): the ecosystem's people —
    // the Users master/detail (host-owned) followed by Requests / Pending users / Invites, each a
    // prop-driven shared pane wired to the ecosystem-scoped /auth/ecosystems/<rdid>/* routes. A
    // group only renders once an ecosystem is selected, but guard `ecoId` rather than asserting it
    // (`ecoId!`): the Users config pane accepts `undefined` and degrades gracefully, whereas the
    // invitation panes require a string and would otherwise build a GET
    // /auth/ecosystems/undefined/... → 404 "Failed to load".
    invitations: [
      { id: "users", label: "Users", icon: <Users size={16} aria-hidden />,
        description: "End-users who authenticate here (its customer identities).",
        render: (subLeaf) => renderTopicPane("users", { ecosystemId: ecoId, title: titleFor("Users"), leaf: subLeaf }) },
      { id: "requests", label: "Requests", icon: <Inbox size={16} aria-hidden />,
        description: "People asking to join — approve or decline.",
        render: () => (ecoId ? <EcoRequestsPane ecosystemRdid={ecoId} /> : null) },
      { id: "pending-users", label: "Pending users", icon: <Users size={16} aria-hidden />,
        description: "Approved sign-ups that haven't completed registration yet.",
        render: () => (ecoId ? <EcoPendingUsersPane ecosystemRdid={ecoId} /> : null) },
      { id: "invites", label: "Invites", icon: <Send size={16} aria-hidden />,
        description: "Invitations you've sent and their status.",
        render: () => (ecoId ? <EcoInvitesPane ecosystemRdid={ecoId} /> : null) },
    ],
    // Authentication: everything about how someone (or something) gets in. Three of these were
    // top-level rows on this rail — `auth`, `signin-apps`, `tokens` — and their MEMBER ids are
    // those same ids, so the host's topic-pane switch answers them with no new cases and every
    // existing deep link still resolves. Email Signup is the fourth and the odd one: no host-owned
    // config pane exists for it in-package, so it goes through `renderFeaturePanel` like All Data.
    authentication: [
      { id: "auth", label: "User Auth", icon: <ShieldCheck size={16} aria-hidden />,
        description: "Signup mode and login policy for the people who authenticate here.",
        render: () => renderTopicPane("auth", { ecosystemId: ecoId, title: titleFor("User Auth") }) },
      { id: "signin-apps", label: "Sign-in apps", icon: <LogIn size={16} aria-hidden />,
        description: "The apps you've registered to sign your own users in.",
        render: (subLeaf) => renderTopicPane("signin-apps", { ecosystemId: ecoId, title: titleFor("Sign-in apps"), leaf: subLeaf }) },
      { id: "tokens", label: "Storage Access Tokens", icon: <KeyRound size={16} aria-hidden />,
        description: "Long-lived tokens that read and write this ecosystem's buckets.",
        render: () => renderTopicPane("tokens", { ecosystemId: ecoId, title: titleFor("Storage Access Tokens") }) },
      { id: "email-signup", label: "Email Signup", icon: <MailPlus size={16} aria-hidden />,
        description: "Waitlists and campaigns for people signing up before they can get in.",
        render: () => renderFeaturePanel("email-signup") },
    ],
  };
}

/**
 * Every group MEMBER id → the group that holds it, derived from {@link groupMembers} itself so
 * it can never fall behind it (the renders are never called here; only the ids are read).
 *
 * Three of these ids — `auth`, `signin-apps`, `tokens` — were top-level rows of this rail before
 * they became members of Authentication, and `buckets`/`access`/`all-data` were the same for
 * Storage. Keeping their ids is only half of "the deep links still resolve": ResourceExplorer
 * matches the URL's topic segment against the TOP-LEVEL list, so without this map the old address
 * matches nothing and renders "Select a topic to view." — an apparently empty product, with no
 * 404 and nothing in the console. With it, the old address redirects into the group.
 */
const GROUP_MEMBER_GROUP: Record<string, string> = Object.fromEntries(
  Object.entries(groupMembers(undefined, (label) => label, () => null, () => null)).flatMap(
    ([group, members]) => members.map((member) => [member.id, group]),
  ),
);

/**
 * An ecosystem id, as a create's PARENT — i.e. as the thing a derived address hangs off.
 *
 * Only an rdid can play that part: an address is `<parent address>.<slug>`, so a parent known
 * only by its uuid supplies no prefix, and gluing the uuid on would preview an identifier that
 * exists nowhere. That case is UNRESOLVED (`undefined`), not a root — the three-state distinction
 * {@link EcosystemParentRdid} exists for. `null` passes through untouched: it is the genuine
 * verdict "no parent", which is a different answer from "not known yet".
 */
function parentRdidOf(id: string | null | undefined): EcosystemParentRdid {
  if (id == null) return id;
  return isRdid(id) ? id : undefined;
}

/**
 * The Ecosystems feature. It opens on the workspace's DEFAULT (primary) ecosystem and shows
 * ITS topics as the first rail (Settings / Storage / AI / … / Child Ecosystems) — the ecosystem
 * list is not a top-level rail; it lives inside the Child Ecosystems topic, which drills into
 * a child by re-scoping the whole rail to it. All the selection/fallback/default-topic wiring
 * lives in ResourceExplorer (`promoteTopics`).
 *
 * Host-composed: `topics`, `renderFeaturePanel`, `renderTopicPane`, and `helpFor` are supplied
 * by the host (the hub route + its EcosystemsTab shim) from its own registries — see each prop's
 * doc comment. This lets a host reuse its existing feature panels + config panes unchanged while
 * this package owns the ecosystem selection/scoping/create/delete orchestration.
 */
export function EcosystemsFeature({
  basePath,
  workspaceSlug,
  topics: topicsConfig,
  // A minimal host (a feature-site mount whose topics are only the in-package rows)
  // injects neither renderer; the no-op defaults keep those topic ids unrenderable
  // rather than crashing, exactly like a host passing explicit stubs.
  renderFeaturePanel = () => null,
  renderTopicPane = () => null,
  helpFor,
  activeTopic,
  activeEcoId,
  activeLeafId,
  activeMemberEntityId,
  labels,
  listFirst = false,
  renderTransferOwnership,
}: EcosystemsFeatureProps): ReactElement {
  const router = useRouter();
  // The presented noun (see the `labels` prop doc) — every user-facing string below
  // derives from these four forms so a renaming host can't miss a surface.
  const singular = labels?.singular ?? "Ecosystem";
  const plural = labels?.plural ?? "Ecosystems";
  const lowerSingular = singular.toLowerCase();
  const lowerPlural = plural.toLowerCase();
  // Feature links are workspace-relative: <basePath>/... The host-supplied slug stays
  // constant while navigating within this workspace (so the FTD cache/last-id keys stay
  // stable and don't re-flash), and switching workspaces re-scopes the whole rail.
  const slug = workspaceSlug;
  // listFirst: OWNERSHIP scope (the workspace's own ecosystems) — else the caller's
  // manageable set. useCallback keeps the fetcher referentially stable per scope
  // (useResourceList refetches on identity change).
  const load = useCallback(
    () =>
      listFirst && slug != null ? ecosystemsApi.listForWorkspace(slug) : ecosystemsApi.list(),
    [listFirst, slug],
  );
  const { items: ecosystems, reload, error } = useResourceList(basePath, load);

  // The HOME (account-infrastructure) ecosystem a new product hangs under, so its identifier is
  // `<home rdid>.<slug>`. Resolved from the server rather than assembled from the workspace slug:
  // an org's home ecosystem is a root (`ecosystem.fishlamp`) but a PERSONAL workspace's is itself
  // a child (`ecosystem.<realm>.<user>`), so there is no string the client can build that is right
  // for both. Same resolver the backend's create uses (`infrastructure=true` ⇒
  // findOwnInfrastructureEcosystemId), which is what makes the previewed and probed identifier the
  // one actually minted — the WORKSPACE principal's row when this mount has a slug, the CALLER's
  // own when it does not, exactly matching which create scope each mount uses. Shared react-query
  // cache entry — this costs no extra fetch on a page that already resolves it.
  const home = useWorkspaceDefaultEcosystemId(slug);
  const createParentRdid: EcosystemParentRdid = home.isPending || home.isError
    ? // Unresolved, not "no parent": previewing a root address for a home ecosystem that has not
      // answered (or whose one-shot lookup FAILED) would show — and probe — an identifier the
      // create is not going to use. A failed resolution is the sharper case, because collapsing it
      // to `null` reads as a confident verdict about the root.
      undefined
    : parentRdidOf(home.ecosystemId ?? null);

  // Ecosystems opens on the workspace's DEFAULT (primary) ecosystem when the URL names none —
  // its topics, not a list. Resolve that id from the workspace slug (the same resolver the
  // standalone /messaging route uses); react-query dedupes concurrent readers. listFirst
  // never opens on the default — its bare path is the list — so the lookup is disabled there.
  const defaultIdQuery = useQuery({
    queryKey: ["ecosystem-id-for-slug", slug],
    // enabled gates on slug != null, so the assertion can't be reached with undefined.
    queryFn: () => ecosystemsApi.ecosystemIdForSlug(slug as string),
    enabled: slug != null && activeEcoId == null && !listFirst,
    retry: false,
  });
  const defaultId = defaultIdQuery.data ?? undefined;
  // The scoped ecosystem: the URL id, else the resolved workspace default. listFirst NEVER
  // falls back to the default — its bare path is the list. Guarded on the VALUE (not just the
  // query's `enabled`): any other reader of the ["ecosystem-id-for-slug", slug] key would warm
  // the same cache entry, so a DISABLED query here can still read back their resolution — which
  // then merges the workspace default into the owned list as a phantom row (hit on hub-testing,
  // 2026-07-10, via the since-removed useEcosystemCapabilities). This feature is currently the
  // key's only react-query reader; keep the value guard so re-adding one can't reopen the bug.
  const scopedId = activeEcoId ?? (listFirst ? undefined : defaultId);

  // The scoped ecosystem's row may be a hidden default — `list()` omits isDefault ecosystems, so
  // the id the feature opens on (via the isDefault fallback) can be absent from `ecosystems`. Fetch
  // it directly ONLY when it's missing, and merge it in; otherwise EcosystemSettingsPane can't bind
  // (Settings shows its empty state), the Delete section vanishes, and the topic titles lose the
  // ecosystem name. Existing deep-links whose id IS in the list skip this fetch entirely.
  // NEVER in listFirst: its list is the workspace's OWNED set, and merging a deep-linked id the
  // caller merely manages (their personal ecosystem, another org's) would render a foreign row in
  // the workspace's Products rail — the ownership invariant. An unknown id there simply bounces
  // to the landing (ResourceExplorer's behavior for ids outside `items`).
  const scopedMissing =
    !listFirst && scopedId != null && ecosystems !== null && !ecosystems.some((e) => e.id === scopedId);
  const scopedEcoQuery = useQuery({
    queryKey: ["ecosystem", scopedId],
    queryFn: () => ecosystemsApi.get(scopedId as string),
    enabled: scopedMissing,
    retry: false,
  });
  const scopedEco = scopedEcoQuery.data ?? null;
  // Items for scoping/binding/title (topics rail + Settings pane): the list plus the scoped default
  // when list() hid it. The Child Ecosystems list keeps using the raw `ecosystems`, so the default
  // the feature is scoped to stays OUT of its own child list.
  const scopedItems =
    scopedMissing && scopedEco ? [...(ecosystems ?? []), scopedEco] : ecosystems;

  // The CHILD ecosystems of the scoped ecosystem — fetched server-scoped to owner_id = scopedId
  // (the ecosystems in the namespace it owns), NOT the caller's whole manageable set. This is what
  // the Child Ecosystems topic lists; it re-fetches when the rail re-scopes to a different ecosystem.
  const hasChildTopic = topicsConfig.some((t) => t.id === "child-ecosystems");
  const childrenQuery = useQuery({
    queryKey: ["ecosystem-children", scopedId],
    queryFn: () => ecosystemsApi.listChildren(scopedId as string),
    // Only fetched when a Child Ecosystems topic will actually render the result.
    enabled: scopedId != null && hasChildTopic,
    retry: false,
  });
  const children = childrenQuery.data ?? null;

  // A deep-link to an ecosystem id that no longer exists (deleted row, stale bookmark/shared link):
  // bounce to the bare feature path, which re-resolves to the workspace default. Only on a CONFIRMED
  // 404 — `get` rethrows transient errors, so the query settling with `null` means "does not exist",
  // never "a request blipped". Guarded on `activeEcoId` so the default's own resolution never loops.
  const scopedDeleted =
    activeEcoId != null &&
    scopedMissing &&
    scopedEcoQuery.isSuccess &&
    scopedEcoQuery.data === null;
  useEffect(() => {
    if (scopedDeleted) router.replace(basePath, { scroll: false });
  }, [scopedDeleted, router, basePath]);

  // A tenant with genuinely NO ecosystems — not even a hidden default (the resolver settled with no
  // id AND the list loaded empty). Offer a first-run create instead of a perpetual "Loading…".
  // listFirst has a real empty state on its landing, so the takeover never applies there.
  const noEcosystems =
    !listFirst &&
    activeEcoId == null &&
    defaultIdQuery.isSuccess &&
    defaultId == null &&
    ecosystems !== null &&
    ecosystems.length === 0;

  // "New Ecosystem" lives on the Child Ecosystems list (there is no top-level resource rail now),
  // so this feature owns the create dialog rather than ResourceExplorer's promoted resource level.
  const [newOpen, setNewOpen] = useState(false);
  // Opt-in escape hatch: create a TOP-LEVEL ecosystem (owner = the caller/principal) instead of a
  // child of the scoped one. Lives outside the create draft so toggling it never marks the form
  // dirty; reset every time the dialog opens so the default (child-of-scoped) is never sticky.
  const [createTopLevel, setCreateTopLevel] = useState(false);

  // The ONE way the create dialog opens — the explicit flag makes each site's intent
  // (top-level vs child-of-scoped) true by construction instead of relying on scopedId
  // happening to be undefined on some paths (the drift a review round caught).
  const openCreateDialog = (topLevel: boolean) => {
    setCreateTopLevel(topLevel);
    setNewOpen(true);
  };

  // Workspace-scoped lists are MEMBERSHIP-gated, but managing an ecosystem's contents is
  // owner-level control (the org-admin bar) — so a plain org member can see an org product
  // they may not open. `canManage === false` (only ever set in `?workspace=` mode) turns
  // every topic pane into one honest notice instead of a wall of per-pane 403s.
  const canManageScoped = (ecoId: string | undefined): boolean =>
    ecoId == null || scopedItems?.find((e) => e.id === ecoId)?.canManage !== false;
  const notManageablePane = (
    <div className="flex min-h-0 flex-1 items-center justify-center p-6">
      <EmptyState
        title={`You don't have admin access to this ${lowerSingular}`}
        description={`Viewing ${an(lowerSingular)}'s contents needs organization admin access — ask one of the organization's admins.`}
      />
    </div>
  );

  // The topics list's Manage features button, scoped to the ecosystem those topics belong to.
  // Withheld where the pane would be the not-manageable notice: a button whose one action would
  // fail is worse than no button.
  const manageFeaturesButton = (ecoId: string): ReactNode =>
    canManageScoped(ecoId) ? (
      <ManageFeaturesButton
        ecosystemId={ecoId}
        label={`Manage ${singular.toLowerCase()} features`}
      />
    ) : null;

  // Only the topics the scoped ecosystem holds. Read only when some row is feature-keyed, so a
  // host whose rows name no features (a feature site's own rail) never pays for the request.
  const featureKeyed = topicsConfig.some((t) => t.features != null);
  const provisionedQuery = useProvisionedFeatures(featureKeyed ? scopedId : undefined);
  const shownTopics = heldTopics(
    topicsConfig,
    provisionedQuery.isError ? null : provisionedQuery.data,
  );

  const topics: ResourceTopic[] = shownTopics.map((t) => ({
    id: t.id,
    label: t.label,
    icon: t.icon,
    description: t.description,
    dividerAfter: t.dividerAfter,
    render: (ecoId, titleFor, leaf, subLeafFor) => {
      if (!canManageScoped(ecoId)) return notManageablePane;
      // FIRST refusal goes to the host, for EVERY topic id — including the ones this package
      // can render itself. A host mounting this feature under its own concept may legitimately
      // put its OWN pane behind a reserved-looking id: the gamification site's rail is
      // Catalog / Levels / Custom Events / Settings, where "settings" means the realm config,
      // not the ecosystem record. Reserving ids here would have forced that site to misname a
      // topic in its URL to dodge a collision the toolkit invented. Everything a host declines
      // (returns null for) still lands on the in-package panes below, so the hub — whose
      // renderProductTopicPane claims none of these ids — behaves exactly as before.
      const hostPane = renderTopicPane(t.id, {
        ecosystemId: ecoId,
        title: titleFor(t.label),
        leaf,
        subLeafFor,
      });
      if (hostPane) return hostPane;
      if (t.id === "settings") {
        return (
          <EcosystemSettingsPane
            noun={singular}
            ecosystemId={ecoId}
            items={scopedItems}
            refresh={reload}
            loadError={error}
            title={titleFor(t.label)}
            help={helpFor?.(`ecosystems/${t.id}`)}
            renderTransferOwnership={renderTransferOwnership}
            onDelete={
              ecoId
                ? makeEntityDeleteHandler({
                    basePath,
                    id: ecoId,
                    router,
                    del: ecosystemsApi.delete,
                    reload,
                  })
                : undefined
            }
            onRenamed={async (newId) => {
              // Point the resume key at the new rdid up front, so it never lingers
              // on the old (now-freed) id during the navigation that follows.
              writeLastId(basePath, newId);
              await reload();
              router.replace(
                `${basePath}/${newId}/${shownTopics[0]?.id}`,
                { scroll: false },
              );
            }}
          />
        );
      }
      if (t.id === "child-ecosystems") {
        // The ecosystems THIS one owns — `children` is server-scoped to owner_id = the scoped
        // ecosystem (its child namespace), so it shows only genuine children, not the tenant-wide
        // set. Published as a topic-detail rail (not a card landing): selecting a child re-scopes the
        // whole Ecosystem rail to it; the header "+" creates a child of the current ecosystem.
        return (
          <ChildEcosystemsLevel
            items={children}
            busy={childrenQuery.isFetching}
            basePath={basePath}
            onNew={() => openCreateDialog(false)}
          />
        );
      }
      // Storage / Users are grouping topics → a nested topic→detail sub-rail of their members;
      // keyed by group id so switching groups resets the sub-selection. The chosen member
      // (Buckets / Access / …) is URL-driven + deep-linkable: it rides the leaf segment
      // (…/ecosystems/<id>/<group>/<member>) via the L1 group's urlSelection, exactly as the
      // top-level applications/integrations topics thread their leaf. `renderSubLeaf` cedes the NEXT
      // segment to the open member, so the member's inner entity (a bucket, a user) is itself
      // deep-linkable (…/ecosystems/<id>/<group>/<member>/<entity>).
      if (isGroupId(t.id)) {
        return (
          <StackGroupDetail
            key={t.id}
            levelId={`ecosystem-${t.id}`}
            title={t.label}
            items={groupMembers(ecoId, titleFor, renderTopicPane, renderFeaturePanel)[t.id]}
            urlSelection={{ selectedId: leaf.leafId, onSelect: leaf.onSelect }}
            renderSubLeaf={subLeafFor}
          />
        );
      }
      // Everything left is host-owned and NOT claimed by renderTopicPane above (which already
      // had its chance, with the URL leaf threaded so a selected entity deep-links
      // /ecosystems/<id>/<topic>/<entityId>): the host's workspace features — Billing /
      // Communities / Messaging / Research / Dashboards → renderFeaturePanel. Dispatching on
      // the host's answer instead of a topic-id list means the host can add a config topic
      // without a toolkit change (and can't have one silently fall through, the Phase-2 port
      // bug that blanked Auth / Sign-in apps).
      return renderFeaturePanel(t.id);
    },
  }));

  // The CHILD-ecosystem create-dialog identity (label/heading/blank/validate). The listFirst
  // header-"+" dialog no longer shares it: that flow is the workspace New Product form
  // (derived owner-scoped identifier + availability probe), a different draft shape.
  // The parent this dialog's create will actually hang the new row off — the scoped ecosystem by
  // default, the caller's own home ecosystem when the top-level toggle opts out of it (or when
  // there is no scoped ecosystem to opt out of). `scopedId` is normally the parent's rdid (a row's
  // public id IS its address), but the route also accepts the bare uuid, which is no basis for a
  // preview: the fetch that case already triggers carries the real rdid, and until it lands the
  // parent is UNRESOLVED (undefined) — the same three-state gate the workspace form uses, because
  // previewing a root address for a child create is a different, wrong answer, not a placeholder.
  const scopedParentRdid: EcosystemParentRdid =
    scopedId == null || isRdid(scopedId) ? scopedId : parentRdidOf(scopedEco?.identifier);
  const prefixForMode = (topLevel: boolean): string =>
    ecoCreatePrefix(topLevel || scopedId == null ? createParentRdid : scopedParentRdid);
  // ONE value feeds the field's static prefix and the validator: they answer about the same
  // address, and a create whose preview and taken-check disagreed is the defect this replaced.
  const childCreatePrefix = prefixForMode(createTopLevel);
  // The addresses this create can actually COLLIDE with: the siblings under the parent it hangs
  // off — which the toggle moves along with the prefix, so the taken set has to move with it too.
  // In child mode that is `children` (server-scoped to owner_id = scopedId). The caller's whole
  // manageable set is a DIFFERENT namespace: since 0160 a slug is unique only within its parent,
  // so checking a child address against it matches nothing by construction — every duplicate slid
  // past the local check and came back as a server 409. Top-level mode keeps the manageable list,
  // the nearest thing loaded here to the home ecosystem's children.
  const takenIdentifiers = ((createTopLevel || scopedId == null ? ecosystems : children) ?? []).map(
    (e) => e.identifier,
  );
  const dialogCommon = {
    ariaLabel: `New ${lowerSingular}`,
    heading: `New ${lowerSingular}`,
    blank: ecoBlank,
    validate: (d: Parameters<typeof ecoValidate>[0]) =>
      ecoValidate(d, takenIdentifiers, childCreatePrefix),
  };

  // The create dialog is owned here (not by ResourceExplorer's promoted level) and shared by both
  // the Child Ecosystems "New Ecosystem" affordance and the first-run empty state below.
  const createDialog = newOpen && (
    <CreateResourceDialog
      {...dialogCommon}
      // Parent = the scoped ecosystem, so "New Ecosystem" from Child Ecosystems creates a CHILD of
      // it (owner = it) by default. The toggle (below) opts out → the ecosystem is owned by the
      // WORKSPACE principal on a slugged mount and by the caller on a slug-less one, and the server
      // hangs it under that principal's own ecosystem (not the global root — no create has landed
      // there since address derivation moved to the parent chain). On first-run (no scoped
      // ecosystem) `scopedId` is undefined → always that shape, and the toggle is hidden (there is
      // no parent to opt out of).
      //
      // `{ workspace: slug }` is what makes the top-level path land where the dialog PREVIEWED it:
      // the prefix comes from useWorkspaceDefaultEcosystemId(slug), i.e. the workspace principal's
      // home ecosystem, so omitting the scope sent the create to the CALLER's own instead — on an
      // org workspace a member's personal ecosystem, a different parent from the address on screen.
      create={(d) =>
        ecosystemsApi.create(
          ecoNormalize(d),
          createTopLevel || scopedId == null
            ? slug != null
              ? { workspace: slug }
              : undefined
            : { parent: scopedId },
        )
      }
      onClose={() => setNewOpen(false)}
      onCreated={(eco) => {
        setNewOpen(false);
        // Re-scope the rail to the created ecosystem (its topics take column 3).
        router.push(`${basePath}/${eco.id}`, { scroll: false });
      }}
      renderForm={(draft, onChange, error) => (
        <>
          <EcosystemDetail
            draft={draft}
            onChange={onChange}
            error={error}
            identifierPrefix={childCreatePrefix}
          />
          {scopedId != null && (
            <div className="flex items-center gap-2">
              <Checkbox
                id="new-eco-toplevel"
                checked={createTopLevel}
                onCheckedChange={(v) => {
                  // The toggle moves the PARENT, so it moves the prefix — and the draft holds a
                  // finished identifier, not a leaf. Re-hang what the user typed off the new
                  // prefix; leaving the old one there would show (and validate) an address under
                  // a parent this create no longer uses. Done HERE, synchronously, so the field
                  // never paints a stale leaf; EcosystemDetail's own re-hang then sees an
                  // identifier already under the new prefix and stands down.
                  const topLevel = v === true;
                  setCreateTopLevel(topLevel);
                  onChange({
                    ...draft,
                    identifier: rehangIdentifier(
                      draft.identifier,
                      childCreatePrefix,
                      prefixForMode(topLevel),
                    ),
                  });
                }}
              />
              <label
                htmlFor="new-eco-toplevel"
                className="min-w-0 flex-1 text-sm text-apt-text-muted"
              >
                Create this {lowerSingular} under your own account, not as a child of the current one
              </label>
            </div>
          )}
        </>
      )}
    />
  );

  // A slugged host whose ONE default-resolution request failed (retry: false): without a
  // defined surface the promoted rail holds "Loading…" forever with dead topic clicks. A
  // reload retries the lookup; deep-linked /<ecoId> paths never hit this (slug unused).
  if (!listFirst && workspaceSlug != null && activeEcoId == null && defaultIdQuery.isError) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center p-6">
        <EmptyState
          title="Couldn't load this workspace"
          description="The workspace's default ecosystem didn't resolve — reload the page to retry."
        />
      </div>
    );
  }

  // A slug-less host (a feature-site mount): default resolution is disabled (§2), so a bare
  // path renders a DEFINED unscoped state — the ecosystem card landing — never
  // ResourceExplorer's promoted "Loading…" hold. Cards route to <basePath>/<id>, the
  // slug-independent deep-link path; New creates top-level (scopedId is undefined here).
  // list() hides a hidden default ecosystem, so a tenant whose only ecosystem is that
  // default sees the empty label — accepted until §2 decides site-mount scoping.
  if (workspaceSlug == null && activeEcoId == null) {
    if (error != null && ecosystems == null) {
      // The list failed before anything arrived: a bare landing would sit on "Loading…"
      // forever — the exact dead surface this unscoped state exists to prevent.
      return (
        <div className="flex min-h-0 flex-1 items-center justify-center p-6">
          <EmptyState title={`Couldn't load ${lowerPlural}`} description={error} />
        </div>
      );
    }
    return (
      <>
        <ResourceLanding
          items={ecosystems}
          title={plural}
          help={`Open ${an(lowerSingular)} to manage it, or create a new one.`}
          emptyLabel={`No ${lowerPlural} yet.`}
          basePath={basePath}
          getId={(e) => e.id}
          getLabel={(e) => e.name}
          getSublabel={(e) => e.identifier}
          cardHref={(e) => `${basePath}/${e.id}`}
          renderMeta={() => null}
          onNew={() => openCreateDialog(true)}
          newLabel={`New ${singular}`}
        />
        {createDialog}
      </>
    );
  }

  // First run: no ecosystems at all. Offer a create instead of ResourceExplorer's perpetual "Loading…".
  if (noEcosystems) {
    return (
      <>
        <div className="flex min-h-0 flex-1 items-center justify-center p-6">
          <EmptyState
            title={`No ${lowerPlural} yet`}
            description={`Create your first ${lowerSingular} to get started.`}
            action={
              <Button variant="outline" size="sm" onClick={() => openCreateDialog(true)}>
                <Plus size={16} aria-hidden />
                New {singular}
              </Button>
            }
          />
        </div>
        {createDialog}
      </>
    );
  }

  // LIST-FIRST (the hub's Products): the OWNED list is rail level 0 of the ONE
  // hierarchical topic-detail stack (classic ResourceExplorer, like Teams/Projects);
  // the selected entity's topics are the next level. Creation lives on the list
  // header's "+" via renderDialog and stamps the WORKSPACE's principal as owner
  // (`?workspace=` — the org for an org workspace, so the product lands in THIS list;
  // never child-of-scoped, which is a Child Ecosystems affordance).
  if (listFirst) {
    if (error != null && ecosystems == null) {
      // The list failed before anything arrived: the landing would sit on "Loading…"
      // forever (nothing in this branch reads `error` otherwise) — surface it instead.
      return (
        <div className="flex min-h-0 flex-1 items-center justify-center p-6">
          <EmptyState title={`Couldn't load ${lowerPlural}`} description={error} />
        </div>
      );
    }
    return (
      <>
        <ResourceExplorer
          activeId={activeEcoId}
          activeTopic={activeTopic}
          activeLeafId={activeLeafId}
          activeMemberEntityId={activeMemberEntityId}
          basePath={basePath}
          items={scopedItems}
          getId={(e) => e.id}
          getLabel={(e) => e.name}
          nameSuffix={singular}
          itemIcon={<Network size={16} aria-hidden />}
          topics={topics}
          topicAliases={GROUP_MEMBER_GROUP}
          newLabel={`New ${singular}…`}
          rail={{
            title: plural,
            help: `Open ${an(lowerSingular)} to manage it, or create a new one.`,
            emptyLabel: `No ${lowerPlural} yet.`,
          }}
          // The selected entity's topics are the features it holds, so the list is headed
          // "Features" — the entity's own name still reads in the breadcrumb.
          topicsTitle="Features"
          topicsTitleActions={manageFeaturesButton}
          renderDialog={(onClose, onCreated) => (
            // The workspace New Product form: Display Name + Slug are typed; the
            // identifier is READ-ONLY, derived as <the workspace's home ecosystem>.<slug>
            // and live-probed for system-wide availability. Save stays disabled until
            // name + slug are filled AND the probe reports available. The slug is ONE
            // segment: the server derives the address from (this workspace's parent chain,
            // slug), so the identifier below is an assertion about that derivation, not a
            // choice — see ecosystemsApi.create.
            <CreateResourceDialog
              ariaLabel={`New ${lowerSingular}`}
              heading={`New ${singular}`}
              blank={ecoCreateBlank}
              validate={(d) => ecoCreateValidate(d, createParentRdid)}
              saveEnabled={ecoCreateReady}
              create={(d) =>
                ecosystemsApi.create(
                  ecoCreateToInput(d, createParentRdid),
                  slug != null ? { workspace: slug } : undefined,
                )
              }
              onClose={onClose}
              onCreated={async (eco) => {
                // Refresh BEFORE navigating so the created id is a known row (an unknown
                // id would bounce the explorer back to the landing).
                await reload();
                onCreated(eco.id);
              }}
              renderForm={(draft, onChange, error) => (
                <EcosystemCreateForm
                  draft={draft}
                  onChange={onChange}
                  error={error}
                  parentRdid={createParentRdid}
                  noun={lowerSingular}
                />
              )}
            />
          )}
        />
        {/* The Child Ecosystems topic's "New" opens the feature-owned dialog — render it
            here too so that affordance works if a host's topic rail includes the topic. */}
        {createDialog}
      </>
    );
  }

  return (
    <>
      <ResourceExplorer
        promoteTopics
        defaultId={defaultId ?? undefined}
        activeId={activeEcoId}
        activeTopic={activeTopic}
        activeLeafId={activeLeafId}
        activeMemberEntityId={activeMemberEntityId}
        basePath={basePath}
        items={scopedItems}
        getId={(e) => e.id}
        getLabel={(e) => e.name}
        nameSuffix={singular}
        itemIcon={<Network size={16} aria-hidden />}
        topics={topics}
        topicAliases={GROUP_MEMBER_GROUP}
        newLabel={`New ${singular}…`}
        topicsTitleActions={manageFeaturesButton}
      />
      {createDialog}
    </>
  );
}
