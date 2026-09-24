"use client";

import {
  Fragment,
  useCallback,
  useEffect,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import {
  HierarchicalTopicDetail,
  TopicSelectHint,
  type TopicDetailItem,
  type TopicLevel,
  type TopicSelectOptions,
} from "@agenticdevelopertoolkit/ui/blocks";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Plus, Search } from "lucide-react";
import { StackLevels } from "./rail-host";
import { RailHostBoundary } from "./standalone-rail-host";
import { HomeBar, HomeBarPortal, HomeBarTaken } from "./home-bar";

/** The deep-linkable LEAF inside a topic (e.g. the selected application within the
 *  Applications topic): the id lives in the URL, and `onSelect` re-routes to it. Topics
 *  whose pane is a master/detail thread this into `useMasterDetailForm({ urlSelection })`;
 *  single-record topics ignore it. */
export interface TopicLeaf {
  leafId: string | null;
  /** `opts` mirrors a level's own `onSelect` (see `TopicSelectOptions`): the stack passes
   *  `{ replace: true }` when IT applied a default rather than the user picking the leaf. */
  onSelect: (leafId: string | null, opts?: TopicSelectOptions) => void;
}

export interface ResourceTopic {
  id: string;
  label: string;
  icon: ReactNode;
  /** What this topic is for. Carried on the row, rendered nowhere: the card grid it used to feed at
   *  an unselected frontier is gone (docs/ui/fleet-ui-audit.md §1.5). See `TopicDetailItem`. */
  description?: string;
  dividerAfter?: boolean;
  /** Declare `"list"` for a topic whose pane publishes a deeper rail (a master/detail list, a
   *  grouping topic), so the cascading view treats choosing it as an INTERMEDIATE select (the
   *  detail holds). Default `"detail"`: choosing the topic IS the final choice. */
  leadsTo?: "list" | "detail";
  /** Render the topic's pane for the active resource id (undefined while "All"). `leaf`
   *  carries the deep-linkable leaf selection for master/detail topics; `subLeafFor` builds the
   *  deeper leaf for a grouping topic's member (…/<topic>/<member>/<entity>), so the member's own
   *  inner entity is deep-linkable too. Non-grouping topics ignore `subLeafFor`. */
  render: (
    scopedId: string | undefined,
    titleFor: (label: string) => string,
    leaf: TopicLeaf,
    subLeafFor: (memberId: string) => TopicLeaf,
  ) => ReactNode;
}

/** The resource RAIL's naming — its header, its empty label, and the blurb the frame
 *  prints under the select nudge while nothing is selected. There is no card landing:
 *  an HTDV's unselected pane is the select hint and nothing else (docs/ui/fleet-ui-audit.md
 *  §1.5), so the rail beside it is the only place the entities are listed. */
export interface ResourceRailConfig<T> {
  title: string;
  help: string;
  emptyLabel: string;
  /** The row's second line — the value that DISAMBIGUATES two rows sharing a display name
   *  (an org's slug, a team's reverse-domain identifier, a project's status). The card
   *  landing showed it and searched it; §1.5 took the LANDING, not the FACT, so the rail
   *  carries it as `TopicDetailItem.sublabel` and the rail filter matches it alongside the
   *  label — a user pasting an identifier out of a URL still finds the row. Omit for a list
   *  whose labels are already unique and self-explaining. */
  getSublabel?: (item: T) => string;
  /** The list's load failure, in the HOST's words. Shown as the rail's empty label instead
   *  of "Loading…": `items` stays `null` after a failed fetch (see `useResourceList`), which
   *  is indistinguishable from "still loading" from here, so without this the rail claims to
   *  be loading forever — the eternal spinner that reads as an outage. */
  loadError?: string | null;
}

/**
 * The shared orchestrator for a selectable-resource feature (Ecosystems / Persona
 * Services / Teams), as a HIERARCHICAL topic/detail (HierarchicalTopicDetail):
 *
 *   [ breadcrumbs · New… ]
 *   [ resource rail ] | [ topics rail ] | [ topic pane ]
 *
 * Level 0 is the resource list itself (no popup — the entity is a first-class rail
 * level); selecting one scopes the topics in level 1. With nothing selected ("All"),
 * the pane is the frame's select hint and nothing else; the entity-first model means New
 * lives in the top bar and Delete lives in the entity pane's Danger zone. URL-driven:
 * `<basePath>/all` or `<basePath>/<id>/<topic>`. All the selection/fallback/
 * default-topic wiring is owned here.
 *
 * (History: this was the hub's misnamed `ResourceTab` — never a tab, always the
 * feature orchestrator — renamed `ResourceExplorer` when it moved into the toolkit.)
 */
export function ResourceExplorer<T>({
  all,
  promoteTopics,
  defaultId,
  activeId,
  activeTopic,
  activeLeafId,
  activeMemberEntityId,
  basePath,
  items,
  getId,
  getLabel,
  itemIcon,
  nameSuffix,
  topics,
  rail,
  newLabel,
  renderDialog,
  reload,
  prefetchItem,
  topicAliases,
  homeBarRight,
  renderNewControl,
  topicsTitle,
  topicsTitleActions,
}: {
  all?: boolean;
  /** Promote the TOPICS to the first (and only) rail: no resource list, no "All" state. The
   *  scoped resource is `activeId ?? defaultId`, so the feature opens straight on the default
   *  resource's topics. The Ecosystem feature uses this — its resource list moves into a topic
   *  ("Child Ecosystems") instead of being the top-level rail. Persona Services / Teams leave it
   *  unset and keep the classic list-first arrangement. */
  promoteTopics?: boolean;
  /** The resource to scope to when the URL names none — only consulted in `promoteTopics`. */
  defaultId?: string;
  activeId?: string;
  activeTopic?: string;
  /** The 4th URL segment: a deep-linkable leaf inside the active topic's pane. For a grouping
   *  topic this selects the group MEMBER; its inner entity rides `activeMemberEntityId` below. */
  activeLeafId?: string;
  /** The 5th URL segment: for a grouping topic, the deep-linkable inner entity of the open member
   *  (…/<topic>/<member>/<entity>) — a persona, a bucket, a user. Non-grouping topics ignore it. */
  activeMemberEntityId?: string;
  basePath: string;
  items: T[] | null;
  getId: (item: T) => string;
  getLabel: (item: T) => string;
  /** Leading icon for each resource rail row (e.g. <Network/>); a neutral ring
   *  fills in when omitted so the collapsed icon strip is never blank. */
  itemIcon?: ReactNode;
  /** Suffix in feature titles, e.g. "Ecosystem" → "Applications (Core Ecosystem)". */
  nameSuffix: string;
  topics: ResourceTopic[];
  /** Topic ids the URL may still name from BEFORE they became members of a grouping topic:
   *  member id → the group that now holds it.
   *
   *  A group's members keep their old ids precisely so the links people already hold keep
   *  working — but `topics` is the top-level list, so an id that moved INTO a group stops
   *  matching it and the pane silently falls back to "Select a topic to view.": no 404, no
   *  redirect, nothing to notice. This is what actually makes the ids-are-unchanged promise
   *  true: the old address redirects (replace, not push, so Back still leaves) to the same
   *  pane at its current address, carrying the leaf and inner-entity segments with it. */
  topicAliases?: Record<string, string>;
  /** The resource rail's naming — required for the classic list-first arrangement; omit in
   *  `promoteTopics` mode, which has no resource rail (the resource list moves into a topic). */
  rail?: ResourceRailConfig<T>;
  /** The "New …" affordance label. Omit to SUPPRESS creation entirely (rail `+` and
   *  dialog) — for a host state where a create could never succeed (e.g. an unscoped
   *  feature-site mount awaiting the platform scoping decision). */
  newLabel?: string;
  /** The "New …" dialog; call onCreated(newId) to switch to the created resource. Optional in
   *  `promoteTopics` mode, where the "New" affordance lives on the promoted resource-list topic
   *  (which owns its own dialog) rather than on a top-level rail. */
  renderDialog?: (onClose: () => void, onCreated: (id: string) => void) => ReactNode;
  /** Re-fetch the resource list. Awaited after a CREATE, before routing to the new id: the list is
   *  fetched once per mount, so without this the new row isn't in `items`, `knownId` is false, and
   *  the fallback below would drop the user back on the unselected "All" state — the resource they
   *  just created would look like it had vanished. */
  reload?: () => Promise<void>;
  /** Warm the ROW'S OWN RECORD as the pointer rests on it, beside the route this already warms.
   *  The two halves of one click: the route prefetch fetches the segment, and this fetches what
   *  the pane inside it will read. Only the host knows which read that is — the explorer sees a
   *  list of `T` and never touches an item endpoint — so it hands one in, typically
   *  `useResourceItemPrefetch`'s function. Omit it and the route alone is warmed, which is right
   *  for an entity whose pane reads nothing per item.
   *
   *  Write-only, like the route half: it must return nothing and never throw, or resting on a
   *  row becomes a user-visible event. */
  prefetchItem?: (id: string) => void;
  /** The host's OWN control for the home bar's right side, for a host that creates by
   *  NAVIGATION rather than through `newLabel`/`renderDialog` (e.g. games' Create Game link,
   *  which pushes a reserved URL segment and opens the host's own dialog off it, never this
   *  component's `newOpen`). Takes over the bar's right slot instead of a `newLabel` button —
   *  see the render below for why passing both would be asking for two create controls in the
   *  same slot — and, unlike `newLabel`, keeps the bar published even while `items` is empty or
   *  still loading, since a host publishing this way has no OTHER way to show the control. Also
   *  bypasses the `!promoteTopics` guard that gates the filter field below: that guard exists
   *  because the filter narrows `resourceLevel`, which a promoteTopics host never renders, but a
   *  host's own right-side action has nothing to do with `resourceLevel` — so a promoteTopics
   *  host passing this prop still gets a bar, on purpose. A falsy value (`false`, `null`,
   *  `undefined`) counts as "not given" everywhere below, the same as omitting the prop, so a
   *  host writing `homeBarRight={condition && <X/>}` does not publish an empty bar. */
  homeBarRight?: ReactNode;
  /** The host's own SHAPE for the create affordance, where `homeBarRight` above is the host's
   *  own create MECHANISM. The explorer still owns `newLabel`, `renderDialog`, `newOpen` and
   *  the reload-then-route it does on success — it hands the host only the trigger, so a host
   *  that wants the create verb inside a gear menu (rather than as a standalone `+` button)
   *  gets it without re-implementing the create flow the way a `homeBarRight` host must.
   *
   *  IT RENDERS IN THE RESOURCE RAIL'S OWN TITLE ROW (`TopicLevel.titleActions`), not in the
   *  home bar — which is the whole reason a host reaches for it. The default `newLabel` button
   *  is page chrome: it sits in the strip above every rail, so it reads as belonging to the
   *  page rather than to the list it creates into, and a second one appears the moment a
   *  nested feature publishes its own. A gear beside the rail's heading is attached to the
   *  list it acts on, and stays attached when the page grows another bar.
   *
   *  Gated by `canCreate` exactly like the default button, so a host cannot accidentally
   *  publish a create control in promoteTopics mode — which has no resource rail to hang it
   *  on at all. Unlike the default button it is NOT displaced by `homeBarRight`: the two now
   *  render in different places, so a host may pass both without them colliding. */
  renderNewControl?: (onNew: () => void) => ReactNode;
  /** The topics level's heading, for a host whose topics ARE something with a name of its own
   *  (a product's topics are the features it holds, so it heads them "Features"). Omit and the
   *  level is named after the selected entity, as always. The breadcrumb is unaffected either
   *  way: it is built from the selected rows' labels, not from level titles, so the entity's
   *  name still reads there. */
  topicsTitle?: string;
  /** Controls for the topics level's own title row (`TopicLevel.titleActions`), handed the
   *  scoped resource's id — e.g. a tool menu that acts on THAT entity. Rendered only once a
   *  resource is scoped, since there is nothing for such a control to act on before. */
  topicsTitleActions?: (scopedId: string) => ReactNode;
}): ReactElement {
  const router = useRouter();
  // Every SELECT in this explorer routes through here, so `{ replace: true }` — which the stack
  // hands to a level's auto-applied `defaultSelectedId` — is honoured on all of them, not just the
  // one level that declares a default today. A pushed auto-default costs the user a Back press on
  // a URL they never chose and never saw.
  const select = useCallback(
    (href: string, opts?: TopicSelectOptions) => {
      if (opts?.replace) router.replace(href, { scroll: false });
      else router.push(href, { scroll: false });
    },
    [router],
  );
  // Warm the ROUTE a row would open, once the pointer or keyboard focus has rested on it. Every
  // select in this explorer is a navigation, and Next fetches the destination segment's payload on
  // every one — so caching the DATA alone would leave half the delay in place. This is the one
  // place in the package that can do it: `TopicRail` supplies the intent signal but owns no router,
  // and here `router` is already in hand for `select` above.
  //
  // Strictly write-only, and it must stay that way: it reads the row id, warms a route, returns
  // nothing. It reads no geometry and touches nothing the cascade's placement logic reads.
  const prefetch = useCallback(
    (href: string) => {
      // `prefetch` is absent from some router shims (test doubles, non-App-Router hosts). Warming is
      // an optimisation with no correct fallback, so a missing one is simply skipped.
      router.prefetch?.(href);
    },
    [router],
  );
  const [newOpen, setNewOpen] = useState(false);
  // The resource rail's filter. The removed card landing carried the only search over this
  // list (docs/ui/fleet-ui-audit.md §1.5 took the landing, not the FUNCTION), so the field
  // moved on to the rail's own `headerSlot` — and from there into the home bar (below), a
  // page-level strip above every rail. The state itself never moved: it is still read by
  // `query`/`entityItems` below, exactly as before either move.
  const [filter, setFilter] = useState("");

  const validTopics = new Set(topics.map((t) => t.id));

  // In `promoteTopics` mode a bare/unknown path scopes to the DEFAULT resource (there is no
  // "All" state — the feature opens straight on the default's topics). Otherwise the classic
  // list-first behaviour applies: an unknown/deleted id (or a topic word mistaken for an id)
  // falls back to the unselected "All" state once the list has loaded, rather than a phantom-
  // scoped pane.
  const requestedId = activeId ?? (promoteTopics ? defaultId : undefined);
  const explicitAll = !promoteTopics && all === true;
  const loaded = items !== null;
  const knownId = requestedId !== undefined && (items ?? []).some((i) => getId(i) === requestedId);
  // Bare base path (no id, not explicit /all): the unselected "All" state. There is no
  // resume / last-id tracking (see below) — the user picks an entity. Never "All" in promoteTopics.
  const bare = !explicitAll && requestedId === undefined;
  const isAll =
    !promoteTopics &&
    (explicitAll || bare || (loaded && requestedId !== undefined && !knownId));

  // The active resource scopes the topics: the URL id (or, in promoteTopics, the default).
  const scopedId = isAll ? undefined : requestedId;
  // No auto-select: an absent/unknown topic is "nothing selected" (the topics list shows with no
  // focus), NOT a coerced first topic.
  const topic = !isAll && activeTopic && validTopics.has(activeTopic) ? activeTopic : null;

  // An id that used to be a top-level topic and is now a group member — `/…/<id>/tokens` for
  // `/…/<id>/authentication/tokens`. The old segments slide one place right: what was the leaf
  // (a sign-in app, a bucket) becomes the member's inner entity.
  const aliasGroup =
    activeTopic && !validTopics.has(activeTopic) ? topicAliases?.[activeTopic] : undefined;
  useEffect(() => {
    if (!aliasGroup || !activeTopic || !scopedId) return;
    const tail = [activeLeafId, activeMemberEntityId].filter(Boolean).join("/");
    router.replace(
      `${basePath}/${scopedId}/${aliasGroup}/${activeTopic}${tail ? `/${tail}` : ""}`,
      { scroll: false },
    );
  }, [
    aliasGroup,
    activeTopic,
    scopedId,
    activeLeafId,
    activeMemberEntityId,
    basePath,
    router,
  ]);

  const active = items?.find((i) => getId(i) === scopedId);
  // "Members (Core Platform Ecosystem)" — but the entity topic's label already IS the
  // nameSuffix, so don't double it ("Ecosystem (Core Platform)", not "… Ecosystem)").
  const titleFor = (label: string) =>
    !active
      ? label
      : label === nameSuffix
        ? `${label} (${getLabel(active)})`
        : `${label} (${getLabel(active)} ${nameSuffix})`;

  const newButtonLabel = newLabel?.replace(/…+$/, "").trim();

  // No resume / no last-id tracking: nothing is auto-selected. A bare base path shows the rail
  // with nothing selected; the user picks an entity (and then a topic) themselves.

  // Level 0 = the resource list; level 1 = the topics scoped to the selection.
  // The rail shows just the name (one line) — the reverse-domain id / sublabel is the
  // entity pane's to show, so the list stays uncluttered.
  const query = filter.trim().toLowerCase();
  const allEntityItems: TopicDetailItem[] = (items ?? []).map((it) => ({
    id: getId(it),
    label: getLabel(it),
    sublabel: rail?.getSublabel?.(it),
    icon: itemIcon,
  }));
  // Filtering narrows the ROWS only — `active`/`titleFor` above still read the unfiltered
  // `items`, so filtering away the selected entity never blanks its pane or its breadcrumb.
  //
  // Two things the match deliberately does NOT do. It never drops the OPEN entity: a level whose
  // `selectedId` names no row it renders is a selection the pointer cannot reach, and every
  // consumer that resolves the selection by lookup — the breadcrumb (`items.find(...)?.label ??
  // selectedId`, which would print a raw uuid), the row highlight, the scroll-into-view — reads
  // the filtered array. And it matches the SUBLABEL as well as the label, because the identifier
  // is the string users actually paste in (the card landing's search matched both).
  const entityItems = query
    ? allEntityItems.filter(
        (i) =>
          i.id === scopedId ||
          i.label.toLowerCase().includes(query) ||
          (i.sublabel ?? "").toLowerCase().includes(query),
      )
    : allEntityItems;
  const topicItems: TopicDetailItem[] = topics.map((t) => ({
    id: t.id,
    label: t.label,
    icon: t.icon,
    description: t.description,
    dividerAfter: t.dividerAfter,
    leadsTo: t.leadsTo,
  }));

  // The create affordance's own condition, and deliberately NOT `hasEntities`: this is the exact
  // condition the pre-bar code used — `resourceLevel.onNew` was set whenever `newLabel != null`,
  // and `resourceLevel` was spliced into `levels` only when `!promoteTopics` (see `levels`
  // below). An empty list is precisely when a first create matters most, and a still-loading one
  // resolves to a button that works; tying this to `hasEntities` left a brand-new tenant with no
  // way to create anything at all. `!promoteTopics` stays for a second reason: in that mode the
  // "New …" affordance lives on the promoted resource-list topic, which owns its own dialog (see
  // the `renderDialog` prop doc above), so a second one here would be a duplicate — and there is
  // no resource rail in that mode for `titleActions` to render into either.
  //
  // Declared HERE, above `resourceLevel`, because both readers need it: the rail's own title row
  // (`titleActions`, just below) and the home bar's fallback button (in the return).
  const canCreate = !promoteTopics && newLabel != null;

  const resourceLevel: TopicLevel = {
    id: "resource",
    title: rail?.title ?? "",
    // Choosing an entity always discloses its TOPICS list — every row is an intermediate select
    // for the cascading view's detail hold (must-hold-the-detail-until-the-final-choice).
    leadsTo: "list",
    items: entityItems,
    // The unselected pane is the frame's select hint and nothing else — the rail beside it
    // already lists every entity, so a card landing would only be a second copy of it in a
    // wider format (docs/ui/fleet-ui-audit.md §1.5). The host's blurb rides under that nudge,
    // but only while there is something to pick: `overviewHelp` also FORCES the hint onto an
    // EMPTY list, and "Select a team" beside a rail reading "No teams yet." is a dead end.
    //
    // Gated on the UNFILTERED list, like the home bar's filter/New pair (in the component's
    // return, below): "there is nothing to pick" is a fact about the tenant's data, not about the
    // box the user just typed in. Reading the filtered count here suppressed the blurb — and with
    // it the whole nudge, since the frame's gate is `items.length > 0 || overviewHelp != null` —
    // the moment a query matched nothing, and this pane's other branch is `null`, so a mistyped
    // filter blanked the entire detail pane.
    itemNoun: nameSuffix.toLowerCase(),
    overviewHelp: allEntityItems.length > 0 ? rail?.help : undefined,
    selectedId: isAll ? null : (scopedId ?? null),
    // No default topic appended — selecting an entity shows its topics list with nothing focused.
    onSelect: (id, opts) => select(`${basePath}/${id}`, opts),
    // The exact href `onSelect` would push — the two must never drift, which is why both build it
    // from the same pieces on adjacent lines. The host's record warm rides along: the route and
    // the record are the two halves of the same click, and warming one without the other leaves
    // the click as slow as its slower half.
    onPrefetch: (id) => {
      prefetch(`${basePath}/${id}`);
      prefetchItem?.(id);
    },
    onClear: () => router.push(basePath, { scroll: false }),
    // The host's own create control, beside this rail's heading — see `renderNewControl`'s doc.
    // The trigger is all the host supplies; the dialog, the reload and the route-to-the-new-row
    // stay here, which is what separates this seam from `homeBarRight`. A host that passes
    // neither gets no control here at all: the DEFAULT create affordance is still the home bar's
    // button, because it is page chrome and every other feature's sits there.
    titleActions:
      canCreate && renderNewControl ? renderNewControl(() => setNewOpen(true)) : undefined,
    // FOUR different reasons for an empty rail, and they must not be spoken as one. An un-loaded
    // list is `items === null`, which maps to zero rows exactly like a genuinely empty one — so
    // without this the rail asserts "No teams yet." at a host that has teams, for as long as the
    // fetch takes. (The card landing used to own this distinction; §1.5 took the landing, so the
    // rail states it now.) A FAILED load also leaves `items === null` and is indistinguishable
    // from a pending one from here, so the host names it: `rail.loadError` wins over "Loading…",
    // which would otherwise sit there forever and read as an outage.
    emptyLabel: !loaded
      ? (rail?.loadError ?? "Loading…")
      : query
        ? `No matches for “${filter.trim()}”.`
        : (rail?.emptyLabel ?? ""),
    // The filter field and the "New …" button are NOT on this level any more — both are page-level
    // controls over the whole list, so both are published into the home bar (below) rather than
    // drawn inside the rail this level renders. Both stay on TopicLevel, but not for the same
    // reason: `onNew` stays IN USE — 20+ deeper levels a feature publishes still call it (e.g. a
    // topic's own master/detail list), and those are contextual to their level in a way the
    // top-level pair never was. `headerSlot` stays on the type too, as a supported seam, but this
    // was its last producer in the repo — nothing currently sets it.
  };
  const topicLevel: TopicLevel = {
    id: "topic",
    // The topics list belongs to the selected entity — name it after that entity (falling back to
    // the entity noun in promoteTopics, where a rail header reads "Ecosystem" until the name loads).
    // The UNFILTERED rows, for the same reason `active`/`titleFor` read the unfiltered `items`:
    // a rail filter narrows what is listed, never what is open, and reading the filtered array
    // here flipped this header (and the breadcrumb tail derived from it) from the entity's name
    // to the literal "Topics" while its pane was still on screen showing that entity's data.
    title:
      topicsTitle ??
      allEntityItems.find((e) => e.id === scopedId)?.label ??
      (promoteTopics ? nameSuffix : "Topics"),
    titleActions: scopedId && topicsTitleActions ? topicsTitleActions(scopedId) : undefined,
    // The frontier's select nudge: name the rows and say what choosing one does.
    itemNoun: "topic",
    overviewHelp: `Each topic is one working area of this ${nameSuffix.toLowerCase()} — its apps, users, settings, and so on. Picking one opens that area's list or pane here.`,
    items: topicItems,
    selectedId: topic,
    onSelect: (id, opts) => {
      if (scopedId) select(`${basePath}/${scopedId}/${id}`, opts);
    },
    onPrefetch: (id) => {
      if (scopedId) prefetch(`${basePath}/${scopedId}/${id}`);
    },
    onClear: () => {
      if (scopedId) router.push(`${basePath}/${scopedId}`, { scroll: false });
    },
  };
  // promoteTopics (Ecosystem): the topics ARE the first rail — no resource list, no "All".
  const levels: TopicLevel[] = promoteTopics ? [topicLevel] : [resourceLevel, topicLevel];

  // DUAL MODE: inside a rail host (the hub's one-rail workspace shell), PUBLISH the resource + topic
  // levels into the host's one merged HierarchicalTopicDetail (the breadcrumb tail — workspace ▸
  // feature ▸ entity ▸ topic — is derived from these levels). Standalone (no host — e.g. a feature
  // site's /home, or /home/persona-services), render an own HTD below.

  // The deep-linkable leaf inside the active topic (the 5th level): its id lives in the
  // URL after `<id>/<topic>`, and selecting one re-routes there. A master/detail topic
  // threads this through `useMasterDetailForm({ urlSelection })`; others ignore it.
  const leaf: TopicLeaf = {
    leafId: activeLeafId ?? null,
    onSelect: (leafId, opts) => {
      if (!scopedId || !topic) return;
      select(
        leafId
          ? `${basePath}/${scopedId}/${topic}/${leafId}`
          : `${basePath}/${scopedId}/${topic}`,
        opts,
      );
    },
  };

  // One level deeper: for a GROUPING topic, the open member (the leaf) is itself a rail, so its own
  // inner entity rides a 5th segment (…/<topic>/<member>/<entity>). This builds that entity leaf for
  // a given member, so a grouped persona / bucket / user deep-links exactly like its standalone route.
  const subLeafFor = (memberId: string): TopicLeaf => ({
    leafId: activeMemberEntityId ?? null,
    onSelect: (entityId, opts) => {
      if (!scopedId || !topic) return;
      select(
        entityId
          ? `${basePath}/${scopedId}/${topic}/${memberId}/${entityId}`
          : `${basePath}/${scopedId}/${topic}/${memberId}`,
        opts,
      );
    },
  });

  // `children` land in the frontier pane: nothing while the resource rail is the unselected
  // frontier (the frame's own select hint owns that pane — §1.5), a "pick a topic" placeholder
  // once an entity is selected but no topic is, else the topic's pane (keyed by scopedId so a
  // resource switch remounts it).
  const content =
    promoteTopics && !scopedId ? (
      // Default resource still resolving (or the tenant has none): hold the frontier.
      <EmptyState title="Loading…" />
    ) : isAll ? null : topic == null ? (
      // Fallback only — the frame's automatic frontier nudge replaces this whenever the
      // topics level is the unselected frontier of the merged stack.
      <TopicSelectHint title="Select a topic to view." />
    ) : (
      <Fragment key={scopedId}>
        {topics.find((t) => t.id === topic)?.render(scopedId, titleFor, leaf, subLeafFor)}
      </Fragment>
    );

  const dialog =
    newOpen &&
    renderDialog?.(
      () => setNewOpen(false),
      async (id) => {
        setNewOpen(false);
        // Pull the created row into the list BEFORE routing to it. `items` is fetched once per
        // mount, so it does not yet contain `id`; routing first would make `knownId` false and the
        // fallback above would show the unselected "All" state instead of the new resource — it would look
        // like the create silently failed. A failed refresh still routes: the id is real, and the
        // list reconciles on its next load.
        try {
          await reload?.();
        } catch {
          // swallowed — the route below is still correct; the rail catches up on the next load
        }
        router.push(`${basePath}/${id}`, { scroll: false });
      },
    );

  // Inside the host: publish the levels and render the leaf content as its detail — the host owns
  // the one merged HTD. StackLevels advances the depth so a deeper view (a group member, a
  // master/detail list) lands after these. Standalone: become our OWN host (RailHostBoundary)
  // and publish through the SAME StackLevels path, so a topic pane's publishers — the master/detail
  // list level AND, crucially, its leaf editor's unsaved-work guard — reach the HTD exactly as they
  // do in the hub shell (without a host they silently no-op and edits are discarded unprompted).
  // The filter field's own condition, separate from the bar's: a filter over nothing to filter
  // is noise, and over a list that has not loaded it is a control that cannot work yet — the
  // same reasons the rail header applied before the field moved here. `!promoteTopics` preserves
  // an invariant the OLD code got for free: `resourceLevel` — the object this field used to live
  // on — was only ever spliced into `levels` when `!promoteTopics` (see the `levels` array built
  // ABOVE, `promoteTopics ? [topicLevel] : [resourceLevel, topicLevel]`), so its `headerSlot`
  // never rendered in promoteTopics mode regardless of this condition. A filter field
  // wired to `filter`/`setFilter` narrows a `resourceLevel` no promoteTopics host ever renders.
  const hasEntities = !promoteTopics && loaded && allEntityItems.length > 0;
  // Whether the create affordance lands in the BAR. A host that supplied `renderNewControl` has
  // already had it rendered into the rail's title row (see `resourceLevel.titleActions` above),
  // so the bar must not draw a second one — and must not be published at all on its account,
  // which is what would otherwise put an empty strip above a rail whose only tenant had moved.
  const createInBar = canCreate && !renderNewControl;
  const published = (
    <>
      {/* Three INDEPENDENT reasons to publish the bar, each gating its own slot: there is
          something to filter (`hasEntities` → the field on the left), there is a create
          affordance (`canCreate` → the button on the right), or the host handed us its own
          right-side control (`homeBarRight`, which takes that same slot). None of the three
          implies another, and that is the point: a brand-new tenant's list is empty and is
          exactly when the first create matters most, and a host that creates by navigation, like
          games, has no OTHER place to put its control, so its bar must appear with zero items or
          before the list has loaded. `hasEntities` gates ONLY the filter field: an empty or
          still-loading list has nothing to filter, whatever the other two say.

          `Boolean(homeBarRight)`, not `homeBarRight != null`: a host writing the natural
          `homeBarRight={condition && <X/>}` hands this `false` when `condition` is false, and
          `false != null` is true — with `hasEntities` and `canCreate` both false that would
          publish a bar with nothing whatsoever in it. (`HomeBar` skips a slot whose content is
          falsy, so the empty-SLOT half of this hazard is handled there now, once for every
          caller; what these operators still buy is not publishing an empty BAR at all.)
          Truthiness treats a falsy `homeBarRight` exactly like the prop being omitted. */}
      {(hasEntities || createInBar || Boolean(homeBarRight)) && (
        <HomeBarPortal>
          <HomeBar
            left={
              hasEntities ? (
                // A bare field, NOT `ListHeader`: that block IS a `ButtonBar` — the same recessed
                // strip (border-y + bg + px-6/py-2) every rail toolbar uses — and `HomeBar` already
                // draws that exact strip. Nesting one inside the other doubled the border and the
                // padding on every site whose home feature runs through `ResourceExplorer`.
                // `NoteButtonBar`'s search field (the fleet's other bare field in a strip shaped
                // like this one) is the precedent this mirrors: a plain positioning div around
                // the field and nothing else. The `Input` keeps its own border and padding —
                // those are the FIELD's, and always were; what goes away is the second toolbar
                // strip around it, which the bar already draws.
                //
                // The width is deliberate, not incidental: `ListHeader`'s own field wrapper is
                // `flex-1 max-w-xs`, which read predictably inside the rail's fixed-width header but
                // has nothing to grow against inside `HomeBar`'s `left` slot (a shrink-to-fit flex
                // item, not a sized column) — the field would collapse to its intrinsic min-content
                // width instead. `w-64 min-w-40 shrink`, copied from `NoteButtonBar`, is the fleet's
                // existing answer to sizing a field in this exact kind of strip.
                //
                // `role="search"` is a LANDMARK, and an unnamed landmark is announced as bare
                // "search" — indistinguishable from any other on the page, and this page can hold
                // more than one (an explorer standing down under `HomeBarTaken` renders its field
                // inline below the outer one's). The name is the resource, so the two announce as
                // "Organizations search" and "Teams search" rather than twice as "search". It sits
                // on the landmark, not the field: the `Input`'s own `aria-label` names the CONTROL
                // and is what every test queries by.
                <div
                  role="search"
                  aria-label={rail?.title ?? nameSuffix}
                  className="relative w-64 min-w-40 shrink"
                >
                  <Search
                    aria-hidden
                    className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-apt-text-muted"
                  />
                  <Input
                    type="search"
                    value={filter}
                    aria-label={`Filter ${(rail?.title ?? nameSuffix).toLowerCase()}`}
                    placeholder="Filter…"
                    className="pl-8"
                    onChange={(e) => setFilter(e.target.value)}
                  />
                </div>
              ) : undefined
            }
            right={
              // `homeBarRight` wins outright rather than sitting beside `newLabel`'s button: a
              // host that passed both would be asking for two create controls in the same slot,
              // the exact hazard `homeBarRight` exists to avoid (see its doc above). NO host
              // passes `homeBarRight` at all today: games was the only one, and its Create Game
              // control left with the games-owned create dialog when a game stopped being
              // something you create. The seam and the precedence rule are kept — and pinned by
              // `__tests__/resource-explorer.homeBar.test.tsx` — because the next host that
              // creates through its own control needs exactly this, and re-deriving it is how
              // the two-`HomeBar`s bug got written the first time.
              //
              // `||`, not `??`: mirrors the gate above — a falsy `homeBarRight` (most likely
              // `false`, from a host's own `condition && <X/>`) falls through to `newLabel`'s
              // button instead of suppressing it, which `??` would do for `false`.
              homeBarRight ||
              (createInBar ? (
                <Button variant="outline" size="sm" onClick={() => setNewOpen(true)}>
                  {/* `data-icon="inline-start"`, and no `size`: `Button` sizes its own icons
                      (`[&_svg:not([class*='size-'])]:size-3.5`) and tightens the padding on the
                      side the icon sits (`has-data-[icon=inline-start]:pl-1.5`). A `size={16}`
                      here was already dead — the class wins over lucide's width/height attributes
                      — while the missing `data-icon` left this button wearing symmetric padding,
                      so it did not match the fleet's other icon buttons. (This used to cite games'
                      `CreateGameAction` as the pattern; that component went with the create-game
                      dialog in `product-gaming-modes`, and the pattern is now just the two
                      attributes above.) */}
                  <Plus data-icon="inline-start" aria-hidden />
                  {newButtonLabel}
                </Button>
              ) : undefined)
            }
          />
        </HomeBarPortal>
      )}
      {/* Everything below the bar stands under this explorer's claim. Organizations renders a whole
          TeamsFeature inside its teams topic, and the hub's Products list mounts ProjectsFeature the
          same way — each with its own `ResourceExplorer` and its own bar. Two publishers, one strip:
          the controls interleave and the outer `ml-auto` shoves the inner filter against the right
          edge. `HomeBarTaken` makes the nested one render its controls inline instead, where the
          nested feature actually is.

          `taken` mirrors the publish gate exactly, so an explorer that publishes NOTHING (no items,
          no create, no host control) leaves the bar for whatever it hosts rather than blocking it. */}
      <HomeBarTaken taken={hasEntities || createInBar || Boolean(homeBarRight)}>
        <StackLevels levels={levels}>{content}</StackLevels>
        {dialog}
      </HomeBarTaken>
    </>
  );
  return <RailHostBoundary>{published}</RailHostBoundary>;
}
