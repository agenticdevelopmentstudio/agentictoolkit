"use client";

import { type ReactElement } from "react";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection, unchangedFromStored } from "@agentic-toolkit/resource";
import type { Program } from "@agentic-toolkit/data/projects";

/**
 * The controlled form for ONE program — name, description, accent, and the two ends of its span.
 *
 * Its own file for the reason {@link IterationDetail} and {@link MilestoneDetail} have one: the
 * same fields are asked for twice, in the inline editor and in the "New program" popup, and the
 * two must not drift. `title` tells them apart — with one, the form wraps itself in a
 * DetailSection; without, it is the bare Card the dialog puts under its own heading.
 *
 * The accent is the same control a project's is, because a program is the thing a board's colour
 * is trying to belong to — a roll-up whose colour is unrelated to its members' would be worse
 * than no colour at all.
 *
 * Both dates are optional AND independent, which is the backend's rule and not a leniency: a
 * standing program ("Platform") has neither end, and a delivery program usually knows its target
 * long before anyone commits to a start. The one thing that is refused is a target BEFORE a start,
 * checked here so the reason arrives before the round trip.
 */

export interface ProgramDraft {
  name: string;
  description: string;
  /** the accent as free text — the column is a 1..20-char token, not a validated hex, so this
   *  carries whatever a board's accent carries. */
  color: string;
  /** the two ends (YYYY-MM-DD) as the native date inputs' strings; "" is unset, which the client
   *  turns into an explicit `null` on the way out. */
  startDate: string;
  targetDate: string;
}

/** The accent a new program starts on — the platform's own blue, which is also what the backend
 *  defaults a project's colour to, so a program and its first board do not arrive mismatched. */
const DEFAULT_COLOR = "#007AFF";

export function programBlank(): ProgramDraft {
  return {
    name: "",
    description: "",
    color: DEFAULT_COLOR,
    startDate: "",
    targetDate: "",
  };
}

export function programToInput(p: Program): ProgramDraft {
  return {
    name: p.name,
    description: p.description,
    // A row from before the column had a default could carry "", which the backend then refuses
    // on the next save (the field is `min(1)`) — so the fallback happens here, once.
    color: p.color || DEFAULT_COLOR,
    startDate: p.startDate ?? "",
    targetDate: p.targetDate ?? "",
  };
}

/** Trim on the way to the wire, so a trailing space is never the reason a form stays dirty. */
export function programNormalize(d: ProgramDraft): ProgramDraft {
  return {
    name: d.name.trim(),
    description: d.description.trim(),
    color: d.color.trim(),
    startDate: d.startDate.trim(),
    targetDate: d.targetDate.trim(),
  };
}

export function programDiffers(a: ProgramDraft, b: ProgramDraft): boolean {
  return (Object.keys(a) as (keyof ProgramDraft)[]).some((k) => a[k].trim() !== b[k].trim());
}

/**
 * Why this draft cannot be saved yet, or null.
 *
 * Every rule here is the backend's own, restated so the reason arrives before the round trip: a
 * name is required, a live program's name is unique within its WORKSPACE (a program spans boards,
 * so the same name under two boards' shared owner really is a collision), an accent is a
 * 1..20-character token, and a target may not precede a start. The date comparison is a string one
 * on purpose — `YYYY-MM-DD` sorts lexicographically exactly as it sorts chronologically, so this
 * needs no parsing and, more to the point, no timezone.
 */
// A record that keeps the name it was stored with is never refused for it: the client folds case,
// but the backend's unique index is on the raw column, so "Sprint 12" and "sprint 12" can both
// exist — and each would otherwise block Save on every unrelated edit, forever. Whether it KEPT the
// name is `unchangedFromStored`'s call, shared with every other stored-value exemption; a create
// has no stored name, so the uniqueness check always runs on one.
export function programValidate(
  draft: ProgramDraft,
  takenNames: string[],
  storedName?: string,
): string | null {
  const { name, color, startDate, targetDate } = programNormalize(draft);
  if (!name) return "Name is required.";
  if (
    !unchangedFromStored(name, storedName) &&
    takenNames.some((n) => n.trim().toLowerCase() === name.toLowerCase())
  ) {
    return `A program named "${name}" already exists in this workspace.`;
  }
  if (!color) return "Color is required.";
  if (color.length > 20) return "Color is too long (20 characters at most).";
  if (startDate && targetDate && targetDate < startDate) {
    return "The target date is before the start date.";
  }
  return null;
}

/** The draft as the client's create/patch input: "" becomes an explicit `null`, which is how an
 *  end is CLEARED (the client's `compact` keeps an explicit null and drops only `undefined`). */
export function programToPatch(d: ProgramDraft): {
  name: string;
  description: string;
  color: string;
  startDate: string | null;
  targetDate: string | null;
} {
  const n = programNormalize(d);
  return {
    name: n.name,
    description: n.description,
    color: n.color,
    startDate: n.startDate || null,
    targetDate: n.targetDate || null,
  };
}

export function ProgramDetail({
  title,
  draft,
  onChange,
  error,
}: {
  /** Present in the inline editor, absent in the create popup (which has its own heading). */
  title?: string;
  draft: ProgramDraft;
  onChange: (next: ProgramDraft) => void;
  error?: string | null;
}): ReactElement {
  function set<K extends keyof ProgramDraft>(key: K, value: string): void {
    onChange({ ...draft, [key]: value });
  }

  const card = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <Field label="Name">
          <Input
            placeholder="Platform"
            value={draft.name}
            onChange={(e) => set("name", e.target.value)}
          />
        </Field>
        <Field label="Description">
          <Textarea
            rows={3}
            placeholder="What this program is for, and which boards belong in it."
            value={draft.description}
            onChange={(e) => set("description", e.target.value)}
          />
        </Field>
        {/* A free-text token, not a swatch — the same control a project's accent uses, because
            the column is the same free-form 20-char string and a native colour input would
            silently rewrite anything that is not `#rrggbb` into black. */}
        <Field label="Color" hint="The program's accent, wherever it labels a board.">
          <Input
            value={draft.color}
            onChange={(e) => set("color", e.target.value)}
            maxLength={20}
            placeholder="Program accent color"
          />
        </Field>
        <div className="flex flex-wrap gap-4">
          <Field
            label="Start date"
            className="min-w-44 flex-1"
            hint="Optional — a standing program has no ends."
          >
            <Input
              type="date"
              value={draft.startDate}
              onChange={(e) => set("startDate", e.target.value)}
            />
          </Field>
          <Field
            label="Target date"
            className="min-w-44 flex-1"
            hint="Optional, and independent of the start."
          >
            <Input
              type="date"
              value={draft.targetDate}
              onChange={(e) => set("targetDate", e.target.value)}
            />
          </Field>
        </div>
        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{card}</DetailSection> : card;
}
