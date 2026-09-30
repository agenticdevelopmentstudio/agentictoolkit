"use client";

import { useCallback, useMemo, useState, type ReactElement } from "react";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { TagSetField } from "@agenticdevelopertoolkit/ui/blocks/tag-set-field";
import { useDirtyDraft } from "@agenticdevelopertoolkit/ui/hooks/useDirtyDraft";
import { projectWorkItemsApi, type WorkItem } from "@agentic-toolkit/data/projects";
import { projectActivityApi } from "@agentic-toolkit/data/projects";
import type {
  EstimateScale,
  Iteration,
  Milestone,
  PriorityScale,
  ProjectStatus,
  ProjectParticipant,
} from "@agentic-toolkit/data/projects";
import { DEFAULT_ITEM_WORDS, type ItemWords } from "./vocabulary";
import { AssigneePicker, toOptionValue, fromOptionValue, type AssigneeValue } from "./AssigneePicker";
import { IterationPicker, NO_ITERATION } from "./IterationPicker";
import { MilestonePicker, NO_MILESTONE } from "./MilestonePicker";
import { EstimatePicker, fromEstimateValue, toEstimateValue } from "./EstimatePicker";
import { ActivityFeed, ACTIVITY_PAGE_SIZE } from "./ActivityFeed";
import { ItemKey } from "./ItemKey";
import { WorkItemComments } from "./WorkItemComments";
import { itemLabel, type BadgeVariant } from "./helpers";

/**
 * The EDIT form over a single work item: title, description, status, assignee
 * (AssigneePicker), priority, start/due dates, an optional parent, its conversation, and its
 * activity trail.
 *
 * It only ever edits an EXISTING item — creating is a modal ({@link NewWorkItemDialog}), because
 * in the hierarchical stack the detail pane always shows a real, selected record. It PATCHes
 * only the changed fields (→ .update). The one subtlety is the
 * assignee clear: dropping an assignee to "Unassigned" sends an explicit
 * `assigneeKind: null, assigneeId: null` — the T1 client keeps explicit null, so
 * the PATCH carries the clear rather than stripping it. Reload-after-write (the
 * saved row flows back through onSaved so the pane refreshes its list), matching
 * the sibling ProjectOverviewPane / TeamMembersPane panes.
 */

/* ── Priority ─────────────────────────────────────────────────────────────
 * Priority is a small int; this is its single source of truth — the editor's
 * Select options AND the list's Badge both read it, so a label/tone is defined
 * once. Badge tones are variants (never raw colors) per the UI gate — the
 * `BadgeVariant` type comes from the shared `./helpers` module. */
export const PRIORITIES: { value: number; label: string; variant: BadgeVariant }[] = [
  { value: 0, label: "None", variant: "neutral" },
  { value: 1, label: "Low", variant: "blue" },
  { value: 2, label: "Medium", variant: "orange" },
  { value: 3, label: "High", variant: "accent" },
  { value: 4, label: "Urgent", variant: "error" },
];

export function priorityMeta(n: number): { label: string; variant: BadgeVariant } {
  return PRIORITIES.find((p) => p.value === n) ?? { label: String(n), variant: "neutral" };
}

/** Two label sets are the same when they hold the same labels in the same ORDER. Position is
 *  stored server-side (it round-trips), so a re-order is a change like any other. */
function sameLabels(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

/** The item's stored assignee as the picker's value ({kind,id} | null). */
function assigneeOf(item: WorkItem | null): AssigneeValue | null {
  if (!item || !item.assigneeKind || !item.assigneeId) return null;
  return { assigneeKind: item.assigneeKind, assigneeId: item.assigneeId };
}

/** The editor's one validity rule, in one place — both the pre-click reason shown beside Save and
 *  the error `save()` sets on the (now unreachable-by-click) guard path read this, so the button's
 *  explanation and the form's error can't drift apart. */
const TITLE_REQUIRED = "Title is required.";

/**
 * The editor's draft shape — one object so `useDirtyDraft` can tell whether ANY field differs
 * from what was loaded. `assignee` is carried as its encoded option string (`toOptionValue`'s
 * `"kind:id"` | `""`), not the `{assigneeKind,assigneeId}` object `AssigneePicker` works with:
 * `useDirtyDraft`'s dirty-check compares non-array fields by `Object.is`, so an object-valued field
 * would read as dirty forever the first time it's set (a fresh object each keystroke/selection,
 * never `===` the baseline's). Reusing the picker's own string codec sidesteps that instead of
 * papering over it — the same discipline `sameValue` already applies to arrays, applied here via
 * the field's representation rather than a hook change.
 */
type WorkItemDraft = {
  title: string;
  description: string;
  statusId: string;
  assigneeOption: string;
  priority: number;
  startDate: string;
  dueDate: string;
  /** The card's label set, in order. An ARRAY is safe here where the assignee object was not:
   *  `useDirtyDraft` compares arrays by CONTENT, so a fresh array from the chooser with the same
   *  labels in it does not read as dirty. */
  labels: string[];
  parentId: string;
  /** the committed iteration's id, or "" for the backlog — a string for the same reason the
   *  assignee is one, and because "" is already how this form spells "no reference". */
  iterationId: string;
  /** the milestone this card counts toward, or "" for none. Independent of the iteration above:
   *  a card can be in this fortnight AND aimed at the beta, and neither implies the other. */
  milestoneId: string;
  /** the estimate as the picker's string ("" = unestimated). A string rather than
   *  `number | null` so the two "empty" spellings stay one: `Object.is(null, undefined)` is
   *  false, and a Select hands back "" whatever the field means. */
  estimate: string;
};

/** Load a work item into the editor's draft shape — the ONE place "what a work item's editable
 *  fields look like as a draft" is defined, used both to seed the draft and (after a save) to
 *  rebuild the baseline from the server's row.
 *
 *  An item with NO status loads as `""`, not as the first status: the draft and the baseline are
 *  both built from this, so writing a fallback here would put the SAME invented value on both sides
 *  of the dirty check — the field would show a status the row does not have, `dirty` would stay
 *  false, re-picking it would hit `set`'s `sameValue` short-circuit, and the status could never be
 *  persisted at all. The Status field renders the empty case explicitly instead (see below). */
function draftFromItem(item: WorkItem): WorkItemDraft {
  return {
    title: item.title,
    description: item.description ?? "",
    statusId: item.statusId ?? "",
    assigneeOption: toOptionValue(assigneeOf(item)),
    priority: item.priority,
    startDate: item.startDate ?? "",
    dueDate: item.dueDate ?? "",
    labels: item.labels,
    parentId: item.parentId ?? "",
    iterationId: item.iterationId ?? NO_ITERATION,
    milestoneId: item.milestoneId ?? NO_MILESTONE,
    estimate: toEstimateValue(item.estimate),
  };
}

/* ── Per-item activity trail (edit mode only) ───────────────────────────────
 * The work item's own trail: a keyset ActivityFeed over workItemActivity.
 *
 * Read-only, and that is the point. This section used to carry a one-line comment box, from back
 * when a comment WAS an activity row and the trail was the only place it could be seen. Comments
 * are their own records now, with their own pane above — so a second composer here would be two
 * doors into one room, and the narrower one at that (a single-line Input for prose, no reply, no
 * edit, no way to take a comment back). What is left is what a trail is for: the record of what
 * happened, in the order it happened, which nothing types INTO. */
function ItemActivitySection({
  workItemId,
  words,
}: {
  workItemId: string;
  words: ItemWords;
}): ReactElement {
  const load = useCallback(
    (before?: string) =>
      projectActivityApi.workItemActivity(workItemId, {
        limit: ACTIVITY_PAGE_SIZE,
        before,
      }),
    [workItemId],
  );

  return (
    <div className="flex flex-col gap-3 border-t border-apt-border pt-5">
      {/* The same mono caption the Comments section above and the detail pane's Relations use —
          two section headings stacked in one pane have to read as siblings, and the louder of the
          two must not be the reference material. */}
      <h3 className="font-mono text-xs tracking-[0.02em] text-apt-text-dim">Activity</h3>
      <ActivityFeed load={load} words={words} />
    </div>
  );
}

export function WorkItemEditor({
  projectId,
  item,
  statuses,
  participants,
  workItems,
  labelOptions,
  iterations,
  milestones,
  estimateScale,
  priorityScale = "standard",
  words = DEFAULT_ITEM_WORDS,
  onSaved,
  onCancel,
}: {
  projectId: string;
  /** The item being edited. Creating goes through NewWorkItemDialog, never this editor. */
  item: WorkItem;
  statuses: ProjectStatus[];
  participants: ProjectParticipant[];
  /** the project's work items, for the parent picker (the edited item is excluded). */
  workItems: WorkItem[];
  /** The label vocabulary to SUGGEST — every label the project's owner has already used,
   *  anywhere (a research document's tags are the same keywords). Never a closed set: the
   *  chooser mints a new one, and a card may already carry a label absent from this list. */
  labelOptions: string[];
  /** the WORKSPACE's time-boxes — not the project's, because a cycle spans boards. */
  iterations: Iteration[];
  /** THIS board's milestones — the mirror image of the line above, and the one place the two
   *  plan axes genuinely differ in shape. An empty list renders no milestone field at all. */
  milestones: Milestone[];
  /** the owning project's estimate scale; `none` renders no estimate field at all. */
  estimateScale: EstimateScale;
  /** the owning project's priority scale; `none` renders no priority field at all — the same
   *  call the estimate field above makes, for the same reason: a board that does not rank has
   *  no use for a control whose every card answers the same. A card that was ranked BEFORE the
   *  board turned ranking off keeps its stored rank; it simply stops being editable here, which
   *  is what makes turning the scale back on lossless. */
  priorityScale?: PriorityScale;
  /** what this board calls its cards. */
  words?: ItemWords;
  onSaved: (saved: WorkItem) => void;
  onCancel: () => void;
}): ReactElement {
  // Seeded once from `item`; the pane keys this editor by item id (or "new") so a
  // switch remounts it with fresh state — no derive-from-props effect needed.
  const { draft, set, dirty, commit, baseline } = useDirtyDraft<WorkItemDraft>(() =>
    draftFromItem(item),
  );

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Why Save is blocked, or null — a located REASON rather than a bare boolean. `save()` still
  // sets the same message, but the gate below disables the button before that path can run, so a
  // user with a blank title would otherwise get a grey button and no explanation. One string,
  // reached two ways.
  const blockedReason = draft.title.trim().length === 0 ? TITLE_REQUIRED : null;
  // What a save would actually PATCH — and THIS, not `dirty`, is what gates Save. `dirty` compares
  // the RAW draft, while every field goes out normalised (titles and descriptions trimmed, empty
  // dates/parent as null), so a trailing space in the title flipped `dirty` true and lit Save up
  // for a write carrying nothing. An empty patch means there is nothing to save, whatever the
  // keystrokes say. `dirty` still gates the caption below, which is about the FORM having been
  // touched rather than about the write.
  const patch = buildPatch();
  const canSave = Object.keys(patch).length > 0 && blockedReason === null;
  // Parent options: every other work item in the project (an item can't parent itself).
  const parentOptions = useMemo(
    () => workItems.filter((w) => w.id !== item.id),
    [workItems, item.id],
  );

  async function save() {
    if (!draft.title.trim()) {
      setError(TITLE_REQUIRED);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      // Nothing changed → skip the no-op PATCH (empty body) and adopt the unchanged item, avoiding
      // a pointless network round-trip. The gate above now disables Save on exactly this condition,
      // so a click can't reach it; it stays because `save()` has to be correct on its own for any
      // other caller (a keyboard shortcut, a future inline surface), the same way the title guard
      // above does.
      const saved =
        Object.keys(patch).length === 0
          ? item
          : await projectWorkItemsApi.update(item.id, patch);
      // Adopt the saved row as the new baseline so Save re-disables until the next edit. This is
      // DEFENSIVE, not load-bearing for the current consumer: WorkItemsSurface's onSaved clears
      // selectedId, which unmounts this editor on every successful save (a fresh instance mounts
      // if the same item is reselected), so nothing here observes the moved baseline today. Keep
      // it anyway — single-source-of-truth is still right, and it's what makes this editor correct
      // for any FUTURE consumer that keeps it mounted across a save (e.g. an inline/non-modal
      // surface), the same way `baseline` itself is a general-purpose hook extension rather than
      // something built to this one consumer's current unmount behavior.
      commit(draftFromItem(saved));
      onSaved(saved);
    } catch (e) {
      setError(e instanceof Error ? e.message : `Failed to save ${words.one}.`);
    } finally {
      setSaving(false);
    }
  }

  // Edit mode: PATCH only the changed fields, diffed against the hook's committed BASELINE (what
  // was actually loaded/last saved) rather than the `item` prop — after `commit()` above the
  // baseline is the server's row while `item` is still the stale pre-save prop, so the two would
  // disagree exactly when it matters. Clearing the assignee / a date / the parent sends an
  // explicit null (the T1 client keeps it), which is the backend's clear semantics.
  function buildPatch(): Parameters<typeof projectWorkItemsApi.update>[1] {
    const patch: Parameters<typeof projectWorkItemsApi.update>[1] = {};
    // Both sides trimmed, deliberately: comparing a trimmed draft against a RAW baseline is
    // asymmetric, so a row stored with stray whitespace read as changed the instant it loaded —
    // Save was live on an untouched form, for a write that only re-normalises what is already
    // there. The server keeps whatever it was given; that is not this editor's to silently fix.
    if (draft.title.trim() !== baseline.title.trim()) patch.title = draft.title.trim();
    if (draft.description.trim() !== baseline.description.trim()) {
      patch.description = draft.description.trim();
    }
    if (draft.statusId !== baseline.statusId) patch.statusId = draft.statusId;

    if (draft.assigneeOption !== baseline.assigneeOption) {
      const decoded = fromOptionValue(draft.assigneeOption);
      patch.assigneeKind = (decoded?.assigneeKind ?? null) as WorkItem["assigneeKind"];
      patch.assigneeId = decoded?.assigneeId ?? null;
    }

    if (draft.priority !== baseline.priority) patch.priority = draft.priority;

    const newStart = draft.startDate || null;
    if (newStart !== (baseline.startDate || null)) patch.startDate = newStart;
    const newDue = draft.dueDate || null;
    if (newDue !== (baseline.dueDate || null)) patch.dueDate = newDue;
    // Labels go out as a WHOLE SET (the PATCH replaces, it does not append), so the diff is
    // "is this the same list in the same order" — ORDER included, because the order is stored
    // and read back, so re-arranging the chips is a real edit and must reach the server.
    if (!sameLabels(draft.labels, baseline.labels)) patch.labels = draft.labels;
    const newParent = draft.parentId || null;
    if (newParent !== (baseline.parentId || null)) patch.parentId = newParent;
    // "" is the BACKLOG, so this clears with an explicit null exactly as the assignee does —
    // dropping the key instead would leave the card in the cycle the user just took it out of.
    if (draft.iterationId !== baseline.iterationId) {
      patch.iterationId = draft.iterationId || null;
    }
    // Same clear semantics for the milestone, and a separate key on purpose: detaching a card
    // from a delivery says nothing about which fortnight it is being worked in.
    if (draft.milestoneId !== baseline.milestoneId) {
      patch.milestoneId = draft.milestoneId || null;
    }
    // Likewise for the size: "" un-estimates, which the server distinguishes from 0. Both sides
    // go through the picker's codec, so `null` and `""` can never be two different answers here.
    if (draft.estimate !== baseline.estimate) {
      patch.estimate = fromEstimateValue(draft.estimate);
    }

    return patch;
  }

  return (
    <div className="flex max-w-xl flex-col gap-5">
      {item && (
        <div className="flex items-center justify-end gap-2">
          {/* The key identifies WHICH card this form is editing — the one thing the form itself
              never shows, since every field below is the card's content rather than its name.
              Read-only here: neither half is a person's to type. The API affordance for this item
              now lives in the surface's header (WorkItemsSurface's FeatureTitle), not here. */}
          <ItemKey itemKey={item.itemKey} className="mr-auto text-sm" />
        </div>
      )}
      <Field label="Title">
        <Input
          /* eslint-disable-next-line jsx-a11y/no-autofocus -- intentional focus-on-open for the editor's first field */
          autoFocus
          value={draft.title}
          onChange={(e) => {
            setError(null);
            set("title", e.target.value);
          }}
          placeholder="Design the landing page"
        />
      </Field>

      <Field label="Description">
        <Textarea
          value={draft.description}
          onChange={(e) => set("description", e.target.value)}
          placeholder="What needs to happen? (optional)"
          rows={3}
        />
      </Field>

      <Field label="Status">
        <Select value={draft.statusId} onChange={(e) => set("statusId", e.target.value)}>
          {statuses.length === 0 && <option value="">Default</option>}
          {/* An item can genuinely have NO status (the board renders it as "—"). Keep an explicit
              empty option for as long as the loaded row has none, so the field states that instead
              of silently displaying the first status — which a `value` no option matches would do,
              turning "unset" into a status the user never picked and cannot save. Picking a real
              one is then a REAL change, and it stays revertible until the next save moves the
              baseline. */}
          {statuses.length > 0 && baseline.statusId === "" && (
            <option value="">— No status</option>
          )}
          {statuses.map((s) => (
            <option key={s.id} value={s.id}>
              {s.label}
            </option>
          ))}
        </Select>
      </Field>

      <AssigneePicker
        participants={participants}
        value={fromOptionValue(draft.assigneeOption)}
        onChange={(v) => set("assigneeOption", toOptionValue(v))}
      />

      {/* Absent on a board that does not rank — see the prop's docs. */}
      {priorityScale !== "none" && (
        <Field label="Priority">
          <Select
            value={String(draft.priority)}
            onChange={(e) => set("priority", Number(e.target.value))}
          >
            {PRIORITIES.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </Select>
        </Field>
      )}

      {/* Which cycle the card is committed to, and how big it is — the two planning answers, kept
          next to Priority rather than beside the dates below. A start date is a fact about one
          card; an iteration is a promise about a fortnight, and the estimate is what makes that
          promise measurable. */}
      <IterationPicker
        iterations={iterations}
        value={draft.iterationId}
        onChange={(id) => set("iterationId", id)}
      />

      {/* And what the card is FOR, directly under when it is being done. Renders nothing on a
          board with no milestones — see MilestonePicker. */}
      <MilestonePicker
        milestones={milestones}
        value={draft.milestoneId}
        onChange={(id) => set("milestoneId", id)}
      />

      {/* Renders nothing when the project's scale is `none` — see EstimatePicker. */}
      <EstimatePicker
        scale={estimateScale}
        value={draft.estimate}
        onChange={(v) => set("estimate", v)}
      />

      {/* The same tag-set row a research document's tags use — deliberately, because they are the
          same tagging system underneath: a label put on a paper is offered here, and vice versa. */}
      <TagSetField
        label="Labels"
        noun="label"
        hint="Shared with everything else this owner tags. Type to autocomplete, or Choose to browse."
        options={labelOptions}
        value={draft.labels}
        onChange={(labels) => set("labels", labels)}
      />

      <div className="flex flex-wrap gap-4">
        <Field label="Start date" className="min-w-40 flex-1">
          <Input
            type="date"
            value={draft.startDate}
            onChange={(e) => set("startDate", e.target.value)}
          />
        </Field>
        <Field label="Due date" className="min-w-40 flex-1">
          <Input
            type="date"
            value={draft.dueDate}
            onChange={(e) => set("dueDate", e.target.value)}
          />
        </Field>
      </div>

      <Field label="Parent" hint={`An optional parent ${words.one} in this project.`}>
        <Select value={draft.parentId} onChange={(e) => set("parentId", e.target.value)}>
          <option value="">None</option>
          {/* Named by key AND title, so a long list of similar titles is still tellable apart —
              and so the option reads the same way the Parent row on the detail pane does. */}
          {parentOptions.map((w) => (
            <option key={w.id} value={w.id}>
              {itemLabel(w)}
            </option>
          ))}
        </Select>
      </Field>

      <ErrorText error={error} />

      <div className="flex items-center gap-2">
        <Button variant="ghost" onClick={onCancel} disabled={saving}>
          Cancel
        </Button>
        <Button onClick={() => void save()} disabled={!canSave || saving}>
          {saving ? "Saving…" : "Save changes"}
        </Button>
        {/* Say WHY Save is grey when a validity rule is holding it down. Gated on `dirty` because
            "nothing to save yet" needs no caption — grey already means that — while an edited but
            unsavable draft does. */}
        {blockedReason && dirty && (
          <span className="text-xs text-apt-text-muted" role="status">
            {blockedReason}
          </span>
        )}
      </div>

      {/* Both live only on a saved item (each needs a real id). Comments first: the conversation
          is what someone came down here to join, and the trail below it is reference. */}
      <div className="border-t border-apt-border pt-5">
        <WorkItemComments workItemId={item.id} />
      </div>
      <ItemActivitySection workItemId={item.id} words={words} />
    </div>
  );
}
