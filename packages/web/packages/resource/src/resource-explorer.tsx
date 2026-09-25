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
  filterTopicItems,
  HierarchicalTopicDetail,
  TopicSelectHint,
  type TopicDetailItem,
  type TopicLevel,
  type TopicSelectOptions,
} from "@agenticdevelopertoolkit/ui/blocks";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { StackLevels } from "./rail-host";
import { RailHostBoundary } from "./standalone-rail-host";

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
   *  whose labels are already unique and self-explaining; a value the filter should FIND but
   *  the row should not SHOW is `getSearchText`'s job. */
  getSublabel?: (item: T) => string;
  /** Text the rail filter matches but the row never shows — the identifier behind a list kept to
   *  one line per row. While the sublabel was the only searchable extra, one accessor drove both,
   *  so the Products rail dropping the ecosystem identifier's second line quietly took identifier
   *  search with it, though the identifier is still the string users paste in. Matched the way
   *  the rail matches the label and sublabel (trimmed, case-folded substring), and ORed with
   *  them: a row is found by any of the three. */
  getSearchText?: (item: T) => string;
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
  /** The host's own SHAPE for the create affordance. The explorer still owns `newLabel`,
   *  `renderDialog`, `newOpen` and the reload-then-route it does on success — it hands the host
   *  only the trigger, so a host that wants the create verb inside a gear menu (rather than as the
   *  rail toolbar's `+`) gets it without re-implementing the create flow.
   *
   *  It renders among the resource rail's own tools (`TopicLevel.titleActions`) IN PLACE OF the
   *  `+`, never beside it — two create controls on one list is the bug this replaces. Gated by
   *  `canCreate` exactly like the `+`, so promoteTopics mode, which has no resource rail to hang
   *  it on, never gets one. */
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
  // list (docs/ui/fleet-ui-audit.md §1.5 took the landing, not the FUNCTION), so the field moved
  // to the rail's `headerSlot`, then to the page-wide home bar — and, once that strip was judged
  // clunky (Mike, 2026-09-24), back onto the rail as its toolbar's pop-over search. The rows are
  // matched as the rail would match them itself (`filterTopicItems`, below), but the query is held
  // HERE and handed to the rail controlled (`resourceLevel.search`): HierarchicalTopicDetail's
  // narrow, minimized and covered stacks are three different component types, so a window
  // crossing the narrow breakpoint (or a disclosure-style change) remounts the TopicRail, and a
  // query the rail held itself would be wiped out from under the user mid-search.
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
  const allEntityItems: TopicDetailItem[] = (items ?? []).map((it) => ({
    id: getId(it),
    label: getLabel(it),
    sublabel: rail?.getSublabel?.(it),
    icon: itemIcon,
  }));
  // A query over a list that has loaded EMPTY has nothing left to narrow and no field left to
  // clear it from — the magnifier below goes with the last row. Kept, it would narrow whatever
  // rows arrive next (a refetch that picks up another session's creates) by a query typed against
  // a list that no longer exists. Dropped during render, React's adjust-state-while-rendering
  // pattern, so no frame commits with it; the `filter !== ""` guard makes it fire once.
  if (loaded && allEntityItems.length === 0 && filter !== "") setFilter("");
  // Filtering narrows the ROWS only — `active`/`titleFor` above still read the unfiltered
  // `items`, so filtering away the selected entity never blanks its pane or its breadcrumb.
  //
  // The match is the rail's own (`filterTopicItems`), so a host-held query narrows exactly as a
  // rail-held one would, and it brings two things with it. It never drops the OPEN entity (it is
  // handed the level's own `selectedId`): a level whose `selectedId` names no row it renders is a
  // selection the pointer cannot reach, and every consumer that resolves the selection by lookup
  // — the breadcrumb (`items.find(...)?.label ?? selectedId`, which would print a raw uuid), the
  // row highlight, the scroll-into-view — reads the filtered array. And it matches the SUBLABEL
  // as well as the label, because the identifier is the string users actually paste in (the card
  // landing's search matched both). A list that keeps the identifier OFF its rows still has it
  // matched through `rail.getSearchText`, whose hits are added to the rail's; either way the rows
  // keep their list order.
  const railRows = filterTopicItems(allEntityItems, filter, isAll ? null : (scopedId ?? null));
  const getSearchText = rail?.getSearchText;
  const needle = filter.trim().toLowerCase();
  const matchedIds =
    getSearchText && needle
      ? new Set([
          ...railRows.map((row) => row.id),
          ...(items ?? [])
            .filter((it) => getSearchText(it).toLowerCase().includes(needle))
            .map(getId),
        ])
      : null;
  const entityItems = matchedIds
    ? allEntityItems.filter((row) => matchedIds.has(row.id))
    : railRows;
  const topicItems: TopicDetailItem[] = topics.map((t) => ({
    id: t.id,
    label: t.label,
    icon: t.icon,
    description: t.description,
    dividerAfter: t.dividerAfter,
    leadsTo: t.leadsTo,
  }));

  // Whether this explorer offers a create at all: whenever the host names one (`newLabel`), and
  // deliberately NOT gated on the list having rows. An empty list is precisely when a first
  // create matters most, and a still-loading one resolves to a button that works; gating create
  // on the row count once left a brand-new tenant with no way to create anything at all.
  // `!promoteTopics` because that mode has no resource rail (see `levels` below) for the `+` or
  // `titleActions` to render into, and its "New …" affordance lives on the promoted
  // resource-list topic, which owns its own dialog (see the `renderDialog` prop doc above) — a
  // second one here would be a duplicate.
  //
  // Declared HERE, above `resourceLevel`, which is its only reader: the rail's `+`, or the host's
  // own control in its place (`titleActions`).
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
    // Gated on the UNFILTERED list, like the rail's search: "there is nothing to pick" is a fact
    // about the tenant's data, not about the box the user just typed in. Reading the filtered
    // count here suppressed the blurb — and with it the whole nudge, since the frame's gate is
    // `items.length > 0 || overviewHelp != null` — the moment a query matched nothing, and this
    // pane's other branch is `null`, so a mistyped filter blanked the entire detail pane.
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
    // Create, in the rail's toolbar: the default `+`, or the host's own control in its place —
    // see `renderNewControl`'s doc. The trigger is all the host supplies; the dialog, the reload
    // and the route-to-the-new-row stay here.
    onNew: canCreate && !renderNewControl ? () => setNewOpen(true) : undefined,
    newLabel: newButtonLabel,
    newActive: newOpen,
    titleActions:
      canCreate && renderNewControl ? renderNewControl(() => setNewOpen(true)) : undefined,
    // A filter over nothing is noise, and over a list that has not loaded is a control that cannot
    // work yet — so the magnifier appears once there are rows to narrow. Gated on the UNFILTERED
    // list, or a query matching nothing would take away the very field that could clear it.
    search:
      loaded && allEntityItems.length > 0
        ? {
            query: filter,
            onQueryChange: setFilter,
            placeholder: `Filter ${(rail?.title ?? nameSuffix).toLowerCase()}`,
          }
        : undefined,
    // FOUR different reasons for an empty rail, and they must not be spoken as one. An un-loaded
    // list is `items === null`, which maps to zero rows exactly like a genuinely empty one — so
    // without this the rail asserts "No teams yet." at a host that has teams, for as long as the
    // fetch takes. (The card landing used to own this distinction; §1.5 took the landing, so the
    // rail states it now.) A FAILED load also leaves `items === null` and is indistinguishable
    // from a pending one from here, so the host names it: `rail.loadError` wins over "Loading…",
    // which would otherwise sit there forever and read as an outage. The fourth, a query that
    // matches nothing, is named HERE, in the rail's own words: the query is controlled, and a rail
    // names a no-match only over rows it filtered itself (a controlled host's empty list may still
    // be loading the query's read, which only the host can know). Only while the UNFILTERED list
    // has rows: this label once outlived the field, so a list that emptied under a query read as
    // a failed search with nothing to clear it from (the magnifier goes with the last row, and
    // the stale query is dropped above).
    emptyLabel: !loaded
      ? (rail?.loadError ?? "Loading…")
      : needle && allEntityItems.length > 0
        ? `Nothing matches “${filter.trim()}”.`
        : (rail?.emptyLabel ?? ""),
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
  const published = (
    <>
      <StackLevels levels={levels}>{content}</StackLevels>
      {dialog}
    </>
  );
  return <RailHostBoundary>{published}</RailHostBoundary>;
}
