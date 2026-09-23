"use client";

import { type ReactElement } from "react";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection } from "@agentic-toolkit/resource";
import type { Milestone } from "@agentic-toolkit/data/projects";

/**
 * The controlled form for ONE point in a project's plan — name, description, target date.
 *
 * Its own file for the reason {@link IterationDetail} has one: the same fields are asked for
 * twice, once in the inline editor and once in the "New milestone" popup, and the two must not
 * drift. The `title` prop is what tells them apart — with one, the form wraps itself in a
 * DetailSection (the editor); without, it is the bare Card the dialog puts under its own heading.
 *
 * Two absences are deliberate.
 *
 * There is no PROGRESS field: a milestone's counts are derived by the server from the cards
 * pointing at it, so offering a number here would be offering to set something the next read
 * overwrites — the honest control for "move this milestone along" is the cards' own statuses.
 *
 * And there is no START date, where an iteration has two. A milestone is a POINT, not a span: it
 * is the moment a plan claims something will be true, and giving it a beginning would quietly turn
 * it into a second kind of iteration. The date is optional for the same reason it is on the wire —
 * an ordered plan that has not been scheduled is a real and common state, and requiring a date only
 * gets one invented.
 */

export interface MilestoneDraft {
  name: string;
  description: string;
  /** the day the point is aimed at (YYYY-MM-DD) as the native date input's own string; "" is
   *  undated, which the client turns into an explicit `null` on the way out. */
  targetDate: string;
}

/** A blank draft — every field a string, which is also what the substrate's `Object.is` dirty
 *  comparison needs to call a draft clean. */
export function milestoneBlank(): MilestoneDraft {
  return { name: "", description: "", targetDate: "" };
}

export function milestoneToInput(m: Milestone): MilestoneDraft {
  return {
    name: m.name,
    description: m.description,
    // The wire says null for undated; the form says "". One conversion, here, so the date input
    // never receives a null it would render as an uncontrolled field.
    targetDate: m.targetDate ?? "",
  };
}

/** Trim on the way to the wire, so a trailing space is never the reason a form stays dirty. */
export function milestoneNormalize(d: MilestoneDraft): MilestoneDraft {
  return {
    name: d.name.trim(),
    description: d.description.trim(),
    targetDate: d.targetDate.trim(),
  };
}

export function milestoneDiffers(a: MilestoneDraft, b: MilestoneDraft): boolean {
  return (Object.keys(a) as (keyof MilestoneDraft)[]).some((k) => a[k].trim() !== b[k].trim());
}

/**
 * Why this draft cannot be saved yet, or null.
 *
 * Both rules are the backend's own, restated here so the reason arrives BEFORE the round trip
 * rather than as a 400 or a 409: a name is required, and a live milestone's name is unique WITHIN
 * ITS PROJECT (the same name on another board is fine — a plan is per-board). `takenNames` is
 * compared case-insensitively, so this is strictly the stricter of the two and can only warn
 * early, never permit something the server would refuse.
 */
// A record that keeps the name it was stored with is never refused for it: the client folds case,
// but the backend's unique index is on the raw column, so "Sprint 12" and "sprint 12" can both
// exist — and each would otherwise block Save on every unrelated edit, forever.
export function milestoneValidate(
  draft: MilestoneDraft,
  takenNames: string[],
  storedName?: string,
): string | null {
  const name = draft.name.trim();
  if (!name) return "Name is required.";
  if (name !== storedName?.trim() && takenNames.some((n) => n.trim().toLowerCase() === name.toLowerCase())) {
    return `A milestone named "${name}" already exists in this project.`;
  }
  return null;
}

/** The draft as the client's create/patch input: "" becomes an explicit `null`, which is how the
 *  date is CLEARED (the client's `compact` keeps an explicit null and drops only `undefined`). */
export function milestoneToPatch(d: MilestoneDraft): {
  name: string;
  description: string;
  targetDate: string | null;
} {
  const n = milestoneNormalize(d);
  return { name: n.name, description: n.description, targetDate: n.targetDate || null };
}

export function MilestoneDetail({
  title,
  draft,
  onChange,
  error,
}: {
  /** Present in the inline editor, absent in the create popup (which has its own heading). */
  title?: string;
  draft: MilestoneDraft;
  onChange: (next: MilestoneDraft) => void;
  error?: string | null;
}): ReactElement {
  function set<K extends keyof MilestoneDraft>(key: K, value: string): void {
    onChange({ ...draft, [key]: value });
  }

  const card = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <Field label="Name">
          <Input
            placeholder="Public beta"
            value={draft.name}
            onChange={(e) => set("name", e.target.value)}
          />
        </Field>
        <Field label="Description">
          <Textarea
            rows={3}
            placeholder="What has to be true when this milestone is reached."
            value={draft.description}
            onChange={(e) => set("description", e.target.value)}
          />
        </Field>
        <Field
          label="Target date"
          hint="Optional — an undated milestone is a point in the order, not the calendar."
        >
          <Input
            type="date"
            value={draft.targetDate}
            onChange={(e) => set("targetDate", e.target.value)}
          />
        </Field>
        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{card}</DetailSection> : card;
}
