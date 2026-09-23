"use client";

import { type ReactElement } from "react";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { TagSetField } from "@agenticdevelopertoolkit/ui/blocks/tag-set-field";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection } from "@agentic-toolkit/resource";
import {
  projectBodyOf,
  workItemBodyOf,
  DEFAULT_ITEM_NOUN,
  DEFAULT_ITEM_NOUN_PLURAL,
  WORK_ITEM_PRIORITY_MAX,
  WORK_ITEM_PRIORITY_MIN,
  type EstimateScale,
  type PriorityScale,
  type StatusCategory,
  type ProjectTemplateBody,
  type Template,
  type TemplateKind,
  type WorkItemTemplateBody,
} from "@agentic-toolkit/data/projects";
import {
  ESTIMATE_SCALES,
  estimateScaleOptionLabel,
  PRIORITY_SCALES,
  priorityScaleOptionLabel,
} from "./helpers";

/**
 * The controlled form for ONE template — its identity, and the SHAPE it stamps out.
 *
 * Its own file for the reason {@link ProgramDetail} and {@link MilestoneDetail} have one: the same
 * fields are asked for twice, inline and in the "New template" popup, and the two must not drift.
 * `title` tells them apart.
 *
 * TWO BODIES, ONE DRAFT. A template's `kind` decides which half of the form is real, and the draft
 * carries both halves at all times rather than being a discriminated union. That is deliberate:
 * in the create dialog the kind is a live choice, and a discriminated draft would throw away
 * whatever had been typed each time the choice flipped. Only the half matching `kind` is ever
 * serialised, so the unused half costs nothing but the keystrokes it preserves.
 *
 * THE KIND IS FROZEN ONCE SAVED (`kindLocked`), because the backend refuses to re-kind a stored
 * template: what it makes is its identity, and re-reading a stored body against the other schema
 * is not an edit, it is a different template. The inline editor therefore states the kind rather
 * than offering it.
 *
 * WHAT A BODY MAY NOT HOLD is worth stating, because it is the whole reason the form looks thin:
 * no status id, no milestone id, no iteration id, no assignee. Every one of those exists on ONE
 * board, and a template belongs to the WORKSPACE — storing one would make the template work on the
 * board it was authored from and fail on every other. They are answered at INSTANTIATION instead,
 * where a board is finally in hand. Labels are the exception, and the reason is real: they belong
 * to the owner's vocabulary rather than to any board.
 */

/* ── The draft ────────────────────────────────────────────────────────────── */

/** One card in a card template — the parent or one of its checklist steps. Numbers are held as
 *  the input's own strings, "" meaning unset, so a half-typed number is never a NaN on the draft. */
export interface TemplateCardDraft {
  title: string;
  description: string;
  priority: string;
  estimate: string;
  labels: string[];
}

export interface TemplateStatusDraft {
  key: string;
  label: string;
  category: StatusCategory;
}

export interface TemplateMilestoneDraft {
  name: string;
  description: string;
}

export interface TemplateDraft {
  kind: TemplateKind;
  name: string;
  description: string;
  /* the `work_item` half */
  card: TemplateCardDraft;
  children: TemplateCardDraft[];
  /* the `project` half */
  boardDescription: string;
  color: string;
  estimateScale: EstimateScale;
  priorityScale: PriorityScale;
  /** what the boards this stamps out call their cards. Held as two strings and saved as a PAIR —
   *  "" for both means the template says nothing and the boards it makes use the defaults. */
  itemNoun: string;
  itemNounPlural: string;
  statuses: TemplateStatusDraft[];
  milestones: TemplateMilestoneDraft[];
}

/** The categories a column may belong to, in the order a board reads left to right. The backend's
 *  own vocabulary — a column outside it is refused, so this list is the whole choice. */
const CATEGORIES: { value: StatusCategory; label: string }[] = [
  { value: "backlog", label: "Backlog" },
  { value: "todo", label: "To do" },
  { value: "in_progress", label: "In progress" },
  { value: "done", label: "Done" },
  { value: "canceled", label: "Canceled" },
];

/** The backend's own caps, restated so the reason arrives before the round trip. */
const MAX_CHILDREN = 50;
const MAX_STATUSES = 30;
const MAX_MILESTONES = 50;

/** The accent a new board template starts on — the same blue a program and a board default to, so
 *  a template and what it makes do not arrive mismatched. */
const DEFAULT_COLOR = "#007AFF";

function blankCard(): TemplateCardDraft {
  return { title: "", description: "", priority: "", estimate: "", labels: [] };
}

export function templateBlank(): TemplateDraft {
  return {
    kind: "work_item",
    name: "",
    description: "",
    card: blankCard(),
    children: [],
    boardDescription: "",
    color: DEFAULT_COLOR,
    estimateScale: "none",
    priorityScale: "standard",
    // Blank, NOT the default words: "" is the template saying nothing about the noun, which is a
    // different claim from stamping "work item" onto every board it makes — and it is the one that
    // keeps following the platform's default if that ever moves.
    itemNoun: "",
    itemNounPlural: "",
    // A board template that names NO columns opens its boards on the platform's own defaults
    // (To do / In progress / Done), which is what a blank list means here — not "a board with no
    // columns", which is not a thing that can exist.
    statuses: [],
    milestones: [],
  };
}

function cardToDraft(c: {
  title: string;
  description?: string;
  priority?: number;
  estimate?: number;
  labels?: string[];
}): TemplateCardDraft {
  return {
    title: c.title,
    description: c.description ?? "",
    priority: c.priority === undefined ? "" : String(c.priority),
    estimate: c.estimate === undefined ? "" : String(c.estimate),
    labels: c.labels ?? [],
  };
}

export function templateToInput(t: Template): TemplateDraft {
  const blank = templateBlank();
  const card = workItemBodyOf(t);
  const board = projectBodyOf(t);
  return {
    ...blank,
    kind: t.kind,
    name: t.name,
    description: t.description,
    ...(card
      ? { card: cardToDraft(card), children: (card.children ?? []).map(cardToDraft) }
      : {}),
    ...(board
      ? {
          boardDescription: board.description ?? "",
          color: board.color || DEFAULT_COLOR,
          estimateScale: board.estimateScale ?? "none",
          priorityScale: board.priorityScale ?? "standard",
          itemNoun: board.itemNoun ?? "",
          itemNounPlural: board.itemNounPlural ?? "",
          statuses: (board.statuses ?? []).map((s) => ({ ...s })),
          milestones: (board.milestones ?? []).map((m) => ({
            name: m.name,
            description: m.description ?? "",
          })),
        }
      : {}),
  };
}

function normalizeCard(c: TemplateCardDraft): TemplateCardDraft {
  return {
    title: c.title.trim(),
    description: c.description.trim(),
    priority: c.priority.trim(),
    estimate: c.estimate.trim(),
    labels: c.labels.map((l) => l.trim()).filter(Boolean),
  };
}

/** Trim on the way to the wire, so a trailing space is never the reason a form stays dirty. */
export function templateNormalize(d: TemplateDraft): TemplateDraft {
  return {
    kind: d.kind,
    name: d.name.trim(),
    description: d.description.trim(),
    card: normalizeCard(d.card),
    children: d.children.map(normalizeCard),
    boardDescription: d.boardDescription.trim(),
    color: d.color.trim(),
    estimateScale: d.estimateScale,
    priorityScale: d.priorityScale,
    itemNoun: d.itemNoun.trim(),
    itemNounPlural: d.itemNounPlural.trim(),
    statuses: d.statuses.map((s) => ({
      key: s.key.trim(),
      label: s.label.trim(),
      category: s.category,
    })),
    milestones: d.milestones.map((m) => ({
      name: m.name.trim(),
      description: m.description.trim(),
    })),
  };
}

/**
 * Dirty check. A structural compare rather than a per-field one, because the draft holds three
 * ARRAYS whose length is itself an edit — adding a checklist step and deleting one leaves every
 * scalar field identical, and a key-by-key compare would call that clean and lose the work.
 */
export function templateDiffers(a: TemplateDraft, b: TemplateDraft): boolean {
  return JSON.stringify(templateNormalize(a)) !== JSON.stringify(templateNormalize(b));
}

/** A whole number in `[min, …]`, or null when the text is not one. "" is handled by the caller —
 *  unset is not an error. */
function intOrNull(text: string, min: number): number | null {
  if (!/^-?\d+$/.test(text)) return null;
  const n = Number(text);
  return Number.isSafeInteger(n) && n >= min ? n : null;
}

function cardProblem(c: TemplateCardDraft, where: string): string | null {
  if (!c.title) return `${where} needs a title.`;
  // The LADDER's rungs, not merely "a whole number": the backend bounds a template's card the same
  // way it bounds a real one, precisely so a template cannot store a rank that 500s the day someone
  // instantiates it. Restating the bound here is what turns that into a sentence before the round
  // trip rather than a rejection after it.
  const rank = c.priority ? intOrNull(c.priority, WORK_ITEM_PRIORITY_MIN) : null;
  if (c.priority && (rank === null || rank > WORK_ITEM_PRIORITY_MAX)) {
    return `${where}: priority must be a whole number from ${WORK_ITEM_PRIORITY_MIN} to ${WORK_ITEM_PRIORITY_MAX}.`;
  }
  if (c.estimate && intOrNull(c.estimate, 0) === null) {
    return `${where}: estimate must be a whole number, zero or more.`;
  }
  return null;
}

/**
 * Why this draft cannot be saved yet, or null.
 *
 * Every rule is the backend's own, restated so the reason arrives before the round trip: a name is
 * required and unique among LIVE templates OF THE SAME KIND in the workspace (the two kinds may
 * share a name — they can never be offered in the same picker), the caps are the stored ones, and
 * a column's key must be unique within the board it describes because the key IS how a card names
 * its column.
 */
// A record that keeps the name it was stored with is never refused for it: the client folds case,
// but the backend's unique index is on the raw column, so "Sprint 12" and "sprint 12" can both
// exist — and each would otherwise block Save on every unrelated edit, forever.
export function templateValidate(
  draft: TemplateDraft,
  taken: { name: string; kind: TemplateKind }[],
  storedName?: string,
): string | null {
  const d = templateNormalize(draft);
  if (!d.name) return "Name is required.";
  if (
    d.name !== storedName?.trim() &&
    taken.some(
      (t) => t.kind === d.kind && t.name.trim().toLowerCase() === d.name.toLowerCase(),
    )
  ) {
    return `A ${d.kind === "project" ? "board" : "card"} template named "${d.name}" already exists in this workspace.`;
  }

  if (d.kind === "work_item") {
    const parent = cardProblem(d.card, "The card");
    if (parent) return parent;
    if (d.children.length > MAX_CHILDREN) {
      return `A checklist may hold at most ${MAX_CHILDREN} steps.`;
    }
    for (const [i, child] of d.children.entries()) {
      const problem = cardProblem(child, `Step ${i + 1}`);
      if (problem) return problem;
    }
    return null;
  }

  if (d.color.length > 20) return "Color is too long (20 characters at most).";
  // Both words or neither — the backend's own rule, and the one place a template can hold a
  // half-answer the boards it makes would read as "recipe"/"work items". Caught here rather than
  // dropped quietly at `templateToBody`, because a silently discarded word is a rename that looks
  // saved and is not.
  if (Boolean(d.itemNoun) !== Boolean(d.itemNounPlural)) {
    return "Give both the singular and plural item name, or neither.";
  }
  if (d.itemNoun.length > 32 || d.itemNounPlural.length > 32) {
    return "An item name is too long (32 characters at most).";
  }
  if (d.statuses.length > MAX_STATUSES) {
    return `A board may open with at most ${MAX_STATUSES} columns.`;
  }
  const keys = new Set<string>();
  for (const [i, s] of d.statuses.entries()) {
    if (!s.key) return `Column ${i + 1} needs a key.`;
    if (!s.label) return `Column ${i + 1} needs a label.`;
    if (keys.has(s.key.toLowerCase())) return `Two columns share the key "${s.key}".`;
    keys.add(s.key.toLowerCase());
  }
  if (d.milestones.length > MAX_MILESTONES) {
    return `A board may open with at most ${MAX_MILESTONES} milestones.`;
  }
  const names = new Set<string>();
  for (const [i, m] of d.milestones.entries()) {
    if (!m.name) return `Milestone ${i + 1} needs a name.`;
    if (names.has(m.name.toLowerCase())) return `Two milestones share the name "${m.name}".`;
    names.add(m.name.toLowerCase());
  }
  return null;
}

function cardToWire(c: TemplateCardDraft) {
  const priority = c.priority ? intOrNull(c.priority, WORK_ITEM_PRIORITY_MIN) : null;
  const estimate = c.estimate ? intOrNull(c.estimate, 0) : null;
  return {
    title: c.title,
    ...(c.description ? { description: c.description } : {}),
    ...(priority === null ? {} : { priority }),
    ...(estimate === null ? {} : { estimate }),
    ...(c.labels.length ? { labels: c.labels } : {}),
  };
}

/**
 * The draft as the stored body — the ONE place a draft becomes wire.
 *
 * Empty is OMITTED rather than sent as "": the body schemas are `.strict()` about unknown keys but
 * lenient about absent ones, and a stored `description: ""` would later re-hydrate as a description
 * the author never wrote. An omitted key means "the template says nothing about this", which is
 * exactly what an empty field means.
 */
export function templateToBody(
  draft: TemplateDraft,
): WorkItemTemplateBody | ProjectTemplateBody {
  const d = templateNormalize(draft);
  if (d.kind === "work_item") {
    return {
      ...cardToWire(d.card),
      ...(d.children.length ? { children: d.children.map(cardToWire) } : {}),
    };
  }
  return {
    ...(d.boardDescription ? { description: d.boardDescription } : {}),
    ...(d.color ? { color: d.color } : {}),
    // Each scale is omitted at ITS OWN default — the value the boards would take anyway — so a
    // template only ever carries a setting it actually has an opinion about. The two defaults sit
    // at opposite ends (boards rank unless told not to, and do not estimate unless told to), which
    // is why these two lines do not read the same way.
    ...(d.estimateScale === "none" ? {} : { estimateScale: d.estimateScale }),
    ...(d.priorityScale === "standard" ? {} : { priorityScale: d.priorityScale }),
    // BOTH or NEITHER: the backend 400s a half, because a body is read against the defaults and a
    // lone singular would mint "recipe"/"work items" on every board this ever makes.
    ...(d.itemNoun && d.itemNounPlural
      ? { itemNoun: d.itemNoun, itemNounPlural: d.itemNounPlural }
      : {}),
    ...(d.statuses.length ? { statuses: d.statuses } : {}),
    ...(d.milestones.length
      ? {
          milestones: d.milestones.map((m) => ({
            name: m.name,
            ...(m.description ? { description: m.description } : {}),
          })),
        }
      : {}),
  };
}

/** The draft as the create/patch input the client takes. */
export function templateToPatch(d: TemplateDraft): {
  name: string;
  description: string;
  body: WorkItemTemplateBody | ProjectTemplateBody;
} {
  const n = templateNormalize(d);
  return { name: n.name, description: n.description, body: templateToBody(n) };
}

/* ── The card sub-form ────────────────────────────────────────────────────── */

/**
 * One card's fields — used for the parent AND for every checklist step, so a step is authored with
 * the same vocabulary the card it hangs off is. `onRemove` is what makes it a step: the parent has
 * no remove, because a card template with no card is not a template.
 *
 * The label vocabulary is EMPTY here, unlike a work item's editor, and that is not an oversight: a
 * template belongs to a workspace while labels resolve per owner through a BOARD, and there is no
 * board in hand at authoring time. The chooser still mints new labels, which is the affordance
 * that matters — a template's labels are written, not picked off a board.
 */
function CardFields({
  card,
  onChange,
}: {
  card: TemplateCardDraft;
  onChange: (next: TemplateCardDraft) => void;
}): ReactElement {
  function set<K extends keyof TemplateCardDraft>(
    key: K,
    value: TemplateCardDraft[K],
  ): void {
    onChange({ ...card, [key]: value });
  }
  return (
    <>
      <Field label="Title">
        <Input
          placeholder="Cut the release tag"
          value={card.title}
          onChange={(e) => set("title", e.target.value)}
        />
      </Field>
      <Field label="Description">
        <Textarea
          rows={2}
          placeholder="What this step means, for whoever picks it up. (optional)"
          value={card.description}
          onChange={(e) => set("description", e.target.value)}
        />
      </Field>
      <div className="flex flex-wrap gap-4">
        {/* The rank is a LADDER POSITION, not a free number, so the hint names its ends — and a
            board that turns ranking off simply ignores what a template stamped, the same way it
            ignores a rank a card already carried. */}
        <Field
          label="Priority"
          className="min-w-32 flex-1"
          hint={`Optional — ${WORK_ITEM_PRIORITY_MIN} (none) to ${WORK_ITEM_PRIORITY_MAX} (urgent).`}
        >
          <Input
            inputMode="numeric"
            value={card.priority}
            onChange={(e) => set("priority", e.target.value)}
            placeholder="2"
          />
        </Field>
        <Field
          label="Estimate"
          className="min-w-32 flex-1"
          hint="Optional — in the target board's own units."
        >
          <Input
            inputMode="numeric"
            value={card.estimate}
            onChange={(e) => set("estimate", e.target.value)}
            placeholder="5"
          />
        </Field>
      </div>
      <TagSetField
        label="Labels"
        noun="label"
        hint="Written here rather than picked — a template has no board to read a vocabulary from."
        options={[]}
        value={card.labels}
        onChange={(labels) => set("labels", labels)}
      />
    </>
  );
}

/* ── The form ─────────────────────────────────────────────────────────────── */

export function TemplateDetail({
  title,
  draft,
  onChange,
  error,
  kindLocked = false,
}: {
  /** Present in the inline editor, absent in the create popup (which has its own heading). */
  title?: string;
  draft: TemplateDraft;
  onChange: (next: TemplateDraft) => void;
  error?: string | null;
  /** True once the template exists: the backend refuses to re-kind a stored template, so the
   *  choice is stated rather than offered. */
  kindLocked?: boolean;
}): ReactElement {
  function set<K extends keyof TemplateDraft>(key: K, value: TemplateDraft[K]): void {
    onChange({ ...draft, [key]: value });
  }

  const kindNoun = draft.kind === "project" ? "board" : "card";

  const card = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <Field
          label="Makes"
          hint={
            kindLocked
              ? "Fixed once saved — what a template makes is its identity."
              : "A card and its checklist, or a whole board with its columns and plan."
          }
        >
          {kindLocked ? (
            <p className="text-sm text-apt-text">
              {draft.kind === "project" ? "A board" : "A card"}
            </p>
          ) : (
            <Select
              value={draft.kind}
              onChange={(e) => set("kind", e.target.value as TemplateKind)}
            >
              <option value="work_item">A card</option>
              <option value="project">A board</option>
            </Select>
          )}
        </Field>

        <Field label="Name">
          <Input
            placeholder={draft.kind === "project" ? "Delivery board" : "Ship a release"}
            value={draft.name}
            onChange={(e) => set("name", e.target.value)}
          />
        </Field>

        <Field
          label="Description"
          hint={`What this template is for — shown in the ${kindNoun} picker.`}
        >
          <Textarea
            rows={2}
            value={draft.description}
            onChange={(e) => set("description", e.target.value)}
            placeholder="When to reach for this one."
          />
        </Field>

        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  const body =
    draft.kind === "work_item" ? (
      <div className="flex flex-col gap-4">
        <FieldGroup title="The card">
          <CardFields card={draft.card} onChange={(next) => set("card", next)} />
        </FieldGroup>

        {draft.children.map((child, i) => (
          <FieldGroup
            // Index-keyed on purpose: a step has no id of its own, and re-keying on content would
            // remount every row on each keystroke. Removal splices, so the index IS the identity.
            key={i}
            title={`Step ${i + 1}`}
            trailing={
              <Button
                variant="destructive-ghost"
                size="sm"
                aria-label={`Remove step ${i + 1}`}
                onClick={() =>
                  set(
                    "children",
                    draft.children.filter((_, j) => j !== i),
                  )
                }
              >
                <Trash2 size={14} aria-hidden />
                Remove
              </Button>
            }
          >
            <CardFields
              card={child}
              onChange={(next) =>
                set(
                  "children",
                  draft.children.map((c, j) => (j === i ? next : c)),
                )
              }
            />
          </FieldGroup>
        ))}

        <div>
          <Button
            variant="outline"
            size="sm"
            disabled={draft.children.length >= MAX_CHILDREN}
            onClick={() => set("children", [...draft.children, blankCard()])}
          >
            <Plus size={14} aria-hidden />
            Add a step
          </Button>
        </div>
      </div>
    ) : (
      <div className="flex flex-col gap-4">
        <FieldGroup title="The board">
          <Field
            label="Description"
            hint="The boards this makes start with this, unless the creator says otherwise."
          >
            <Textarea
              rows={2}
              value={draft.boardDescription}
              onChange={(e) => set("boardDescription", e.target.value)}
              placeholder="What this kind of board is for."
            />
          </Field>
          {/* Free text, not a swatch — the same control a project's and a program's accent use,
              because the column is the same free-form 20-char string and a native colour input
              would silently rewrite anything that is not `#rrggbb` into black. */}
          <Field label="Color" hint="The board's accent.">
            <Input
              value={draft.color}
              onChange={(e) => set("color", e.target.value)}
              maxLength={20}
              placeholder="Board accent color"
            />
          </Field>
          <Field
            label="Estimate scale"
            hint="The units cards on these boards are sized in."
          >
            <Select
              value={draft.estimateScale}
              onChange={(e) => set("estimateScale", e.target.value as EstimateScale)}
            >
              {ESTIMATE_SCALES.map((s) => (
                <option key={s} value={s}>
                  {estimateScaleOptionLabel(s)}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            label="Priority scale"
            hint="Whether cards on these boards carry a priority."
          >
            <Select
              value={draft.priorityScale}
              onChange={(e) => set("priorityScale", e.target.value as PriorityScale)}
            >
              {PRIORITY_SCALES.map((s) => (
                <option key={s} value={s}>
                  {priorityScaleOptionLabel(s)}
                </option>
              ))}
            </Select>
          </Field>
          {/* Both boxes or neither: a template that names only the singular would stamp out boards
              reading "recipe" and "work items", which is worse than one that renames nothing. Left
              empty the boards it makes use the platform's own words — the template simply has no
              opinion, which is a different claim from stamping the default onto every board. */}
          <div className="flex flex-wrap gap-4">
            <Field
              label="Item name"
              className="min-w-44 flex-1"
              hint="Optional — what one card is called on these boards."
            >
              <Input
                value={draft.itemNoun}
                onChange={(e) => set("itemNoun", e.target.value)}
                maxLength={32}
                placeholder={DEFAULT_ITEM_NOUN}
              />
            </Field>
            <Field
              label="Item name (plural)"
              className="min-w-44 flex-1"
              hint="Required if the singular is given."
            >
              <Input
                value={draft.itemNounPlural}
                onChange={(e) => set("itemNounPlural", e.target.value)}
                maxLength={32}
                placeholder={DEFAULT_ITEM_NOUN_PLURAL}
              />
            </Field>
          </div>
        </FieldGroup>

        {/* The array IS the column order, which is why there are no positions to disagree with
            it — a column's place is where it sits in this list. */}
        <FieldGroup
          title="Columns"
          trailing={
            <Button
              variant="outline"
              size="sm"
              disabled={draft.statuses.length >= MAX_STATUSES}
              onClick={() =>
                set("statuses", [
                  ...draft.statuses,
                  { key: "", label: "", category: "todo" },
                ])
              }
            >
              <Plus size={14} aria-hidden />
              Add
            </Button>
          }
        >
          {draft.statuses.length === 0 ? (
            <p className="text-sm text-apt-text-muted">
              None — boards from this template open on the standard To do / In progress / Done.
            </p>
          ) : (
            draft.statuses.map((s, i) => (
              <div key={i} className="flex flex-wrap items-end gap-3">
                <Field label="Key" className="min-w-28 flex-1">
                  <Input
                    value={s.key}
                    onChange={(e) =>
                      set(
                        "statuses",
                        draft.statuses.map((x, j) =>
                          j === i ? { ...x, key: e.target.value } : x,
                        ),
                      )
                    }
                    placeholder="in_review"
                  />
                </Field>
                <Field label="Label" className="min-w-32 flex-1">
                  <Input
                    value={s.label}
                    onChange={(e) =>
                      set(
                        "statuses",
                        draft.statuses.map((x, j) =>
                          j === i ? { ...x, label: e.target.value } : x,
                        ),
                      )
                    }
                    placeholder="In review"
                  />
                </Field>
                <Field label="Category" className="min-w-36 flex-1">
                  <Select
                    value={s.category}
                    onChange={(e) =>
                      set(
                        "statuses",
                        draft.statuses.map((x, j) =>
                          j === i
                            ? { ...x, category: e.target.value as StatusCategory }
                            : x,
                        ),
                      )
                    }
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c.value} value={c.value}>
                        {c.label}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Button
                  variant="destructive-ghost"
                  size="sm"
                  aria-label={`Remove column ${i + 1}`}
                  onClick={() =>
                    set(
                      "statuses",
                      draft.statuses.filter((_, j) => j !== i),
                    )
                  }
                >
                  <Trash2 size={14} aria-hidden />
                </Button>
              </div>
            ))
          )}
        </FieldGroup>

        {/* Seeded UNDATED, in this order. A plan point's date is a fact about one delivery, and a
            template used three months after it was written would seed a plan already overdue. */}
        <FieldGroup
          title="Milestones"
          trailing={
            <Button
              variant="outline"
              size="sm"
              disabled={draft.milestones.length >= MAX_MILESTONES}
              onClick={() =>
                set("milestones", [...draft.milestones, { name: "", description: "" }])
              }
            >
              <Plus size={14} aria-hidden />
              Add
            </Button>
          }
        >
          {draft.milestones.length === 0 ? (
            <p className="text-sm text-apt-text-muted">
              None — boards from this template open with an empty plan.
            </p>
          ) : (
            draft.milestones.map((m, i) => (
              <div key={i} className="flex flex-wrap items-end gap-3">
                <Field label="Name" className="min-w-32 flex-1">
                  <Input
                    value={m.name}
                    onChange={(e) =>
                      set(
                        "milestones",
                        draft.milestones.map((x, j) =>
                          j === i ? { ...x, name: e.target.value } : x,
                        ),
                      )
                    }
                    placeholder="Beta"
                  />
                </Field>
                <Field
                  label="Description"
                  className="min-w-48 flex-[2]"
                  hint={i === 0 ? "Dates are set on the board, not here." : undefined}
                >
                  <Input
                    value={m.description}
                    onChange={(e) =>
                      set(
                        "milestones",
                        draft.milestones.map((x, j) =>
                          j === i ? { ...x, description: e.target.value } : x,
                        ),
                      )
                    }
                    placeholder="What this point means."
                  />
                </Field>
                <Button
                  variant="destructive-ghost"
                  size="sm"
                  aria-label={`Remove milestone ${i + 1}`}
                  onClick={() =>
                    set(
                      "milestones",
                      draft.milestones.filter((_, j) => j !== i),
                    )
                  }
                >
                  <Trash2 size={14} aria-hidden />
                </Button>
              </div>
            ))
          )}
        </FieldGroup>
      </div>
    );

  return title ? (
    <>
      <DetailSection title={title}>{card}</DetailSection>
      <DetailSection title={draft.kind === "project" ? "The shape" : "The checklist"}>
        {body}
      </DetailSection>
    </>
  ) : (
    <>
      {card}
      {body}
    </>
  );
}
