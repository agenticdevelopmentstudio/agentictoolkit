"use client";

import { type ReactElement } from "react";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection, unchangedFromStored } from "@agentic-toolkit/resource";
import type { Iteration } from "@agentic-toolkit/data/projects";

/**
 * The controlled form for ONE time-box — name, description, and the two ends of the span.
 *
 * Its own file for the reason GroupDetail is: the same fields are asked for twice, once in the
 * inline editor and once in the "New iteration" popup, and the two must not drift. The `title`
 * prop is what tells them apart — with one, the form wraps itself in a DetailSection (the
 * editor); without, it is the bare Card the dialog puts under its own heading.
 *
 * There is deliberately NO state field. An iteration's state is DERIVED by the server from the
 * two dates and never stored, so offering it here would be offering to set something the next
 * read overwrites — the honest control for "make this cycle active" is the start date.
 */

export interface IterationDraft {
  name: string;
  description: string;
  /** inclusive first day (YYYY-MM-DD), as the native date input's own string. */
  startDate: string;
  /** inclusive last day (YYYY-MM-DD). */
  endDate: string;
}

/** A blank draft — every field a string, which is also what {@link useDirtyDraft}-style
 *  `Object.is` comparison needs to call a draft clean. */
export function iterationBlank(): IterationDraft {
  return { name: "", description: "", startDate: "", endDate: "" };
}

export function iterationToInput(it: Iteration): IterationDraft {
  return {
    name: it.name,
    description: it.description,
    startDate: it.startDate,
    endDate: it.endDate,
  };
}

/** Trim on the way to the wire, so a trailing space is never the reason a form stays dirty. */
export function iterationNormalize(d: IterationDraft): IterationDraft {
  return {
    name: d.name.trim(),
    description: d.description.trim(),
    startDate: d.startDate.trim(),
    endDate: d.endDate.trim(),
  };
}

export function iterationDiffers(a: IterationDraft, b: IterationDraft): boolean {
  return (Object.keys(a) as (keyof IterationDraft)[]).some((k) => a[k].trim() !== b[k].trim());
}

/**
 * Why this draft cannot be saved yet, or null.
 *
 * The three rules are the backend's own, restated here so the reason arrives BEFORE the round
 * trip rather than as a 400 or a 409: both ends are required, they must be in order (the server
 * refuses the pair the box would end up as), and a live box's name is unique in its workspace.
 * `takenNames` is compared case-insensitively — the database's uniqueness is exact, so this is
 * strictly the stricter of the two and can only warn early, never permit something the server
 * would refuse.
 */
// A record that keeps the name it was stored with is never refused for it: the client folds case,
// but the backend's unique index is on the raw column, so "Sprint 12" and "sprint 12" can both
// exist — and each would otherwise block Save on every unrelated edit, forever. Whether it KEPT the
// name is `unchangedFromStored`'s call, shared with every other stored-value exemption; a create
// has no stored name, so the uniqueness check always runs on one.
export function iterationValidate(
  draft: IterationDraft,
  takenNames: string[],
  storedName?: string,
): string | null {
  const name = draft.name.trim();
  if (!name) return "Name is required.";
  if (
    !unchangedFromStored(name, storedName) &&
    takenNames.some((n) => n.trim().toLowerCase() === name.toLowerCase())
  ) {
    return `An iteration named "${name}" already exists in this workspace.`;
  }
  if (!draft.startDate) return "A start date is required.";
  if (!draft.endDate) return "An end date is required.";
  // Both ends are inclusive, so a one-day box (equal dates) is legal and only the strict
  // inversion is refused.
  if (draft.endDate < draft.startDate) return "The end date cannot be before the start date.";
  return null;
}

export function IterationDetail({
  title,
  draft,
  onChange,
  error,
}: {
  /** Present in the inline editor, absent in the create popup (which has its own heading). */
  title?: string;
  draft: IterationDraft;
  onChange: (next: IterationDraft) => void;
  error?: string | null;
}): ReactElement {
  function set<K extends keyof IterationDraft>(key: K, value: string): void {
    onChange({ ...draft, [key]: value });
  }

  const card = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <Field label="Name">
          <Input
            placeholder="Sprint 12"
            value={draft.name}
            onChange={(e) => set("name", e.target.value)}
          />
        </Field>
        <Field label="Description">
          <Textarea
            rows={3}
            placeholder="What this cycle is for."
            value={draft.description}
            onChange={(e) => set("description", e.target.value)}
          />
        </Field>
        <div className="flex flex-wrap gap-4">
          <Field label="Starts" className="min-w-40 flex-1">
            <Input
              type="date"
              value={draft.startDate}
              onChange={(e) => set("startDate", e.target.value)}
            />
          </Field>
          <Field label="Ends" className="min-w-40 flex-1">
            <Input
              type="date"
              value={draft.endDate}
              onChange={(e) => set("endDate", e.target.value)}
            />
          </Field>
        </div>
        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{card}</DetailSection> : card;
}
