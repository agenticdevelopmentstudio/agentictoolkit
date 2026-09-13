"use client";

import type { ReactNode } from "react";
import type { TopicDetailItem, TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

import { useStackLevel, useRailExitGuard } from "../rail-host";
import type { TopicLeaf } from "../resource-explorer";
import type { MasterDetailForm } from "./useMasterDetailForm";

/**
 * The shared bridge that DISMANTLES an in-pane master/detail into the one-stack model: it
 * PUBLISHES the pane's list as a deeper {@link TopicLevel} (so the rows are a stack level, not a
 * nested list inside the leaf) and REGISTERS the editor's unsaved-work guard so the package's
 * Back / breadcrumb-up / re-click prompts Discard/Stay before discarding.
 *
 *  - the list level's `selectedId` is the URL-driven `form.selectedId`,
 *  - `onSelect` routes to that row (via `form.select` → the leaf URL),
 *  - `onClear` deselects (routes back to the topic URL, no leaf segment),
 *  - the "New …" button is the level's leading `railSlot` (a "+" when the list is collapsed).
 *
 * The pane itself then renders ONLY the editor leaf (a ButtonBar + the detail form, or the
 * "select or create" placeholder). One call covers every converted master/detail topic.
 */
export function useMasterDetailLevel<TItem, TInput>({
  id,
  title,
  form,
  items,
  getId,
  getLabel,
  getSublabel,
  itemIcon,
  getItemIcon,
  newLabel,
  leaf,
  emptyLabel,
  busy,
  onPrefetch,
  onNew,
  showNew = true,
  checkable,
  checkedIds,
  onToggleChecked,
  itemNoun,
  overviewHelp,
}: {
  /** Stable level id (e.g. "applications-list"). */
  id: string;
  /** Left-aligned heading naming the list (e.g. "Applications"), shown above the rows. */
  title?: string;
  form: MasterDetailForm<TItem, TInput>;
  items: TItem[] | null;
  getId: (item: TItem) => string;
  getLabel: (item: TItem) => string;
  getSublabel?: (item: TItem) => string | undefined;
  /** Leading icon for each row (fills the collapsed icon strip). */
  itemIcon?: ReactNode;
  /** PER-ROW icon, when one uniform `itemIcon` can't say what a row is (e.g. an application's
   *  kind, an integration's service type). Wins over `itemIcon` when both are given. */
  getItemIcon?: (item: TItem) => ReactNode;
  /** "New …" affordance label. */
  newLabel: string;
  /** The deep-link leaf (URL selection); its `onSelect(null)` clears the level. */
  leaf?: TopicLeaf;
  /** Empty/loading message for the list. */
  emptyLabel?: string;
  /** A read is in flight for this list — pass the list hook's `isFetching`. Draws a spinner
   *  before the title without moving it. Omit and the header is exactly as it was. */
  busy?: boolean;
  /** Warm a row before it is clicked — pass `useResourceItemPrefetch`'s function, a
   *  `router.prefetch` call, or both. Omit for no prefetching. */
  onPrefetch?: (id: string) => void;
  /** Override the header "+" action — e.g. open a "New …" POPUP instead of the default inline
   *  create (`form.actions.onCreate`). When set, the `+` never tints gold (there is no in-pane
   *  create-in-progress). Panes that create inline omit it. */
  onNew?: () => void;
  /** Show the header "+" at all. `false` when the SURFACE owns creation — a pane that publishes a
   *  button bar of its own (integrations' Add/Remove/Select/…) would otherwise offer two creators
   *  in the same field of view, one of them unlabelled. It suppresses only the affordance:
   *  `form.actions.onCreate` is untouched and is what the surface's own button calls, so the inline
   *  create path is identical either way and nothing about the editor has to know which drove it. */
  showNew?: boolean;
  /** Draw a tick box on every row. The SURFACE owns this: the rail knows how to draw a tick and
   *  nothing else, and what a set of ticked rows is FOR — remove these four, test these four,
   *  export these four — is a question only the pane publishing the button bar can answer. */
  checkable?: boolean;
  /** Which rows are ticked. Held by the surface (`useBatchSelect`), read by the rail.
   *
   *  A TICK IS NOT A SELECTION. `selectedId` is still `form.selectedId` while this is non-empty,
   *  so ticking four rows does not open four editors and does not close the one that is open —
   *  clicking a row still selects it, and the tick box is a separate hit target on the same row. */
  checkedIds?: ReadonlySet<string>;
  onToggleChecked?: (id: string) => void;
  /** Singular noun for one row, for the frontier's select nudge ("Select a persona …").
   *  Defaults to the noun inside a "New …" `newLabel` ("New Persona" → "persona"). */
  itemNoun?: string;
  /** Bespoke select-nudge copy: what one of these rows is and why to choose one. */
  overviewHelp?: ReactNode;
}): void {
  const rows: TopicDetailItem[] = (items ?? []).map((it) => ({
    id: getId(it),
    label: getLabel(it),
    sublabel: getSublabel?.(it),
    icon: getItemIcon ? getItemIcon(it) : itemIcon,
  }));

  const newButtonLabel = newLabel.replace(/…+$/, "").trim();
  // Every converted master/detail names its creator "New <singular noun>", so the select nudge
  // gets its noun for free ("New Persona" → "persona"); only the leading cap is folded, keeping
  // acronyms ("New LLM provider" → "LLM provider") intact. An explicit `itemNoun` overrides.
  const derivedNoun = /^new\s+/i.test(newButtonLabel)
    ? newButtonLabel.replace(/^new\s+/i, "").replace(/^[A-Z](?=[a-z])/, (c) => c.toLowerCase())
    : undefined;

  const level: TopicLevel = {
    id,
    title,
    items: rows,
    selectedId: form.selectedId,
    // When a leaf is threaded (a top-level master/detail topic), selection is URL-driven: route to
    // the row's leaf URL and let the form's url-sync effect re-hydrate the draft (keeps the URL the
    // single source of truth, no stale closure). With NO leaf (a group member, whose deeper
    // selection isn't a URL segment), route through the form's own local select/cancel so the
    // published rail still drives selection.
    onSelect: (rowId) => (leaf ? leaf.onSelect(rowId) : form.select(rowId)),
    onClear: () => (leaf ? leaf.onSelect(null) : form.actions.onCancel()),
    emptyLabel: emptyLabel ?? (items === null ? "Loading…" : "Nothing here yet."),
    busy,
    onPrefetch,
    checkable,
    checkedIds,
    onToggleChecked,
    // The New affordance is a right-justified `+`. Default: inline create (gold while creating). An
    // `onNew` override opens a popup instead — there is no in-pane create, so it never tints gold.
    // `showNew: false` omits the three together: a level with a label but no handler would draw a
    // dead `+`, and one with a handler but no label draws a live one with nothing to say.
    onNew: showNew ? (onNew ?? form.actions.onCreate) : undefined,
    newLabel: showNew ? newButtonLabel : undefined,
    newActive: showNew && !onNew ? form.creating : undefined,
    // While the inline editor is open the pane body IS the detail. CREATE is the
    // critical case: nothing is selected yet, so without this the automatic
    // frontier detail (the select nudge) covers the open form.
    overview: form.editing ? false : undefined,
    itemNoun: itemNoun ?? derivedNoun,
    overviewHelp,
  };

  useStackLevel(level);
  // Registered only while the draft is actually DIRTY, not merely while an editor is open.
  // Two things ride on this. HTDV is unaffected — it treats "no guard" and "clean guard"
  // identically, both exiting immediately. But the rail host re-renders on register/withdraw,
  // so `guards.size > 0` becomes a RENDER VALUE meaning "something is dirty" — which is what
  // the shell's UnsavedChangesGuard needs, since its `when` prop cannot call `isDirty()`.
  // Costs one re-render per clean↔dirty transition, not per keystroke.
  useRailExitGuard(form.dirty ? form.guard : null);
}
