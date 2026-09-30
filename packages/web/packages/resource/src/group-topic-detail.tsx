"use client";

import { Fragment, type ReactNode } from "react";
import { TopicSelectHint, type TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { useDualModeSelection } from "@agenticdevelopertoolkit/ui/hooks/useDualModeSelection";
import type { TopicLeaf } from "./resource-explorer";
import { StackLevels } from "./rail-host";
import { settingsLast } from "./settings-last";

/** A TopicLeaf that selects nothing and routes nowhere — the sub-leaf handed to a member when the
 *  caller doesn't cede a deeper URL segment (so a member's inner selection stays local).
 *
 *  ⚠️ It is a TRUTHY object, and it does NOT by itself make a member's selection local. The panes
 *  in this fleet decide their own mode by the leaf's truthiness (`leaf ? { selectedId: leaf.leafId,
 *  onSelect: leaf.onSelect } : undefined`), so a pane handed THIS goes URL-driven with a constant
 *  `null` id and a no-op setter — its rows render and clicking one does nothing, forever. A member
 *  whose pane works that way must pass `undefined` down when its group has no `renderSubLeaf`;
 *  `features/adh-billing/src/BillingGroup.tsx` does exactly that and says why. Widening this to
 *  `undefined` here would be the smaller fix and is a fleet-wide, compile-breaking change to
 *  `render`'s first parameter, so it is not made unilaterally. */
const LOCAL_SUBLEAF: TopicLeaf = { leafId: null, onSelect: () => {} };

export interface GroupTopicItem {
  id: string;
  label: string;
  icon: ReactNode;
  /** What this member is for. Carried on the row, rendered nowhere — it never did become a card
   *  grid here (that took the level-level `overview` opt-in, which this component never set), and
   *  the opt-in itself is now gone (docs/ui/fleet-ui-audit.md §1.5). The no-selection leaf is the
   *  select nudge; to explain the LIST, set the level's `overviewHelp`. */
  description?: string;
  /** Declare `"list"` for a member whose pane publishes deeper rails (a schema browser, an entity
   *  list), so the cascading view treats choosing it as an INTERMEDIATE select (the detail holds).
   *  Default `"detail"`: choosing the member IS the final choice (a settings pane). */
  leadsTo?: "list" | "detail";
  /** The member's detail pane (it may itself publish deeper rails). `subLeaf` carries the
   *  deep-linkable inner entity (the segment AFTER this member) for members that URL-drive their
   *  own selection — a persona list, a master/detail config pane; members without one ignore it.
   *
   *  `selectMember` moves THIS GROUP's own selection to a SIBLING member — for a pane whose job
   *  includes sending the operator somewhere else in the same rail (Billing's Setup reports the
   *  Stripe connection and offers a "Connect Stripe" button that opens the Stripe member, which is
   *  where credentials are actually entered). It respects the group's CURRENT selection mode: it
   *  routes through `urlSelection.onSelect` when the group is URL-driven and writes the internal
   *  state otherwise, which is the whole point of `useDualModeSelection` — so a pane that uses it
   *  works identically on a host that cedes a URL segment and on one that does not.
   *
   *  A SECOND parameter rather than a change to the first, deliberately: a function declared with
   *  fewer parameters is assignable in TypeScript, so every existing `render` in the fleet keeps
   *  compiling untouched and only a member that needs the setter has to name it.
   *
   *  OPTIONAL, though this component always supplies it. Assignability covers every `render` that
   *  is DECLARED, but not every one that is CALLED: a caller reaching into `items` and invoking
   *  `item.render(leaf)` itself — the hub's `registries/__tests__/entryTopics.test.tsx` does it
   *  seven times — passes one argument to a two-parameter type and fails to compile. The `?` costs
   *  a member that wants the setter one optional-chain and cannot break a caller anywhere. */
  render: (subLeaf: TopicLeaf, selectMember?: (memberId: string | null) => void) => ReactNode;
  /** Flags this member's rail row as the one holding the blocking field — forwarded to
   *  {@link TopicDetailItem}'s own `blocked` field, which draws an amber dot on the row's icon
   *  (expanded and collapsed alike), names it "needs attention" for AT, and sets
   *  `data-blocked="true"`. For a caller whose leaf blocks some action (e.g. Save) on a field that
   *  lives in a DIFFERENT member's pane, so the user can find which topic to open. */
  blocked?: boolean;
  /** Draw a separator under this member's row — forwarded to {@link TopicDetailItem}'s own
   *  `dividerAfter`, which the rail renders as a rule. The group places the one above Settings
   *  itself (see {@link settingsLast}); set this only for any other break the list needs. */
  dividerAfter?: boolean;
  /** With `dividerAfter`: a caption under the separator naming the section it opens. */
  dividerLabel?: string;
}

/**
 * A grouping level whose members live in the ONE merged stack. It publishes a rail of the group's
 * members (via {@link StackLevels}, which also advances the depth) and renders the active member as
 * the deeper content — so the member's own deeper rails (a persona list, a master/detail list) land
 * AFTER this group rail in the SAME stack, never as a separate nested rail. `leafHeader` renders
 * once above the active member's content, in the leaf (e.g. an editor's Save/Cancel bar).
 *
 * There is NEVER auto-selection: choosing this group (or the entity that owns it) shows its members
 * UNSELECTED — picking a member is an explicit act, never a cascade into the child rail (until then
 * the leaf shows `emptyHint`). This holds for editors exactly like navigation groups (spec:
 * selecting an item in a hierarchical topic/detail view never automatically selects a topic).
 * Selection is local; key the instance by group id at the call site.
 */
export function StackGroupDetail({
  items,
  levelId,
  title,
  busy,
  leafHeader,
  emptyHint = "Select a topic.",
  itemNoun,
  overviewHelp,
  urlSelection,
  renderSubLeaf,
}: {
  items: GroupTopicItem[];
  /** Stable id for this group's rail level (e.g. "persona-topics", "ecosystem-ai"). */
  levelId: string;
  /** The rail's heading (like every other stack rail): the group's name — "AI", the persona's
   *  name, etc. */
  title: string;
  /** A read THIS component is holding is in flight — the group's own rows, or something every
   *  member is scoped by (the workspace's default ecosystem, say). Draws the spinner ahead of
   *  `title`.
   *
   *  Not the place for a member's own body read: that happens inside the member's pane, a
   *  component below, and the pane reports it with `useReportBusy` — which lights this same
   *  spinner without the group having to hold six reads it does not need. Omit this prop entirely
   *  for a group that reads nothing of its own; the members are still covered. */
  busy?: boolean;
  /** Rendered once above the active member's content, in the leaf (e.g. a Save/Cancel bar). */
  leafHeader?: ReactNode;
  /** FALLBACK copy for the leaf until a member is chosen — reached only when this group's level is
   *  NOT the stack's unselected frontier (the usual case is that it IS, and the frame's own nudge
   *  replaces this). Word the frontier through `itemNoun` / `overviewHelp` instead; a hint set
   *  here is invisible on the ordinary path. */
  emptyHint?: ReactNode;
  /** Singular noun for one member ("token kind", "dashboard"), forwarded to the level so the
   *  frame's frontier nudge reads "Select a token kind" instead of the generic line. */
  itemNoun?: string;
  /** The group's bespoke frontier blurb — what these members are and why to pick one — forwarded
   *  to the level and rendered under the nudge's headline. This, not {@link GroupTopicItem
   *  .description}, is where a group's landing copy lives. */
  overviewHelp?: ReactNode;
  /** Opt-in URL-driven selection (a deep-linkable sub-tab / section). When provided, the active
   *  member lives in the URL instead of internal state — reads come from `selectedId` and every
   *  select/clear routes through `onSelect` so the caller can push the segment (mirrors
   *  {@link useMasterDetailForm}'s `urlSelection`). Omit for the legacy internal-selection
   *  behavior. */
  urlSelection?: { selectedId: string | null; onSelect: (id: string | null) => void };
  /** Builds the deep-linkable sub-leaf for the ACTIVE member (the URL segment after it), so the
   *  member's inner entity is itself deep-linkable (…/<group>/<member>/<entity>). Omit for the
   *  legacy behavior — the member's inner selection stays local ({@link LOCAL_SUBLEAF}). */
  renderSubLeaf?: (memberId: string) => TopicLeaf;
}) {
  // Every group starts unselected and onClear returns to that state — never a cascade into the
  // child rail. Selection lives in the URL when `urlSelection` is given (deep-linkable), else in
  // internal state — the shared dual-mode toggle.
  const { selectedId: selected, select: setSelected } = useDualModeSelection(urlSelection);
  // Selected item if present; else (nothing selected, or a stale id no longer in `items`) nothing.
  const active = selected != null ? items.find((i) => i.id === selected) ?? null : null;
  // Every topic list closes on Settings, alone under a divider — a group's sub-rail included, so a
  // member named Settings is moved last here rather than trusted to be authored there.
  const memberItems = settingsLast(items).map((i) => ({
    id: i.id,
    label: i.label,
    icon: i.icon,
    description: i.description,
    leadsTo: i.leadsTo,
    blocked: i.blocked,
    dividerAfter: i.dividerAfter,
    dividerLabel: i.dividerLabel,
  }));
  const level: TopicLevel = {
    id: levelId,
    title,
    items: memberItems,
    busy,
    selectedId: active?.id ?? null,
    onSelect: setSelected,
    onClear: () => setSelected(null),
    itemNoun,
    overviewHelp,
  };
  return (
    <StackLevels levels={[level]}>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        {leafHeader}
        {active ? (
          <Fragment key={active.id}>
            {active.render(renderSubLeaf ? renderSubLeaf(active.id) : LOCAL_SUBLEAF, setSelected)}
          </Fragment>
        ) : (
          // Fallback only — the frame's automatic frontier nudge replaces this whenever this
          // group's level is the unselected frontier of the merged stack. The shared card keeps
          // it identical to every other "pick something" pane; role="status" preserves the
          // announcement the old <p> made.
          <div role="status" className="flex min-h-0 min-w-0 flex-1 flex-col">
            <TopicSelectHint title={emptyHint} />
          </div>
        )}
      </div>
    </StackLevels>
  );
}
