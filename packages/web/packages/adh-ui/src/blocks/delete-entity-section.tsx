"use client";

import * as React from "react";
import { Archive, Trash2, TriangleAlert } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { cn } from "@agenticdevelopertoolkit/ui/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogFooter,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";

type Phase = "warn" | "confirm";

/** Props for {@link DeleteEntitySection}. */
export interface DeleteEntitySectionProps {
  /** Singular entity noun, e.g. "Ecosystem" — used in the button and copy. */
  entityNoun: string;
  /** The exact value the user must type to confirm (the entity's rdid). */
  confirmValue: string;
  /**
   * Child data the action affects, composed into a different carrier sentence depending on
   * `actionVerb.reversible` — the two shapes are not interchangeable:
   *  - Default (not reversible): "…deletes all the data associated with the {noun}, including
   *    {childEntities}." — a plain noun phrase, e.g. "applications, buckets, and users".
   *  - Reversible (`actionVerb.reversible: true`): "…affects {childEntities}." — this carrier
   *    reads naturally with a full relative clause instead, e.g. "its handle, which is released
   *    for anyone to claim" (see the organization Archive caller).
   */
  childEntities: string;
  /** Performs the delete (and any post-delete navigation). Throwing shows an inline error. */
  onConfirm: () => Promise<void>;
  /** Optional override for the danger-section description line. */
  description?: React.ReactNode;
  /**
   * The verb this section's copy is built from, in the two grammatical forms it needs, plus
   * whether that verb is reversible. `reversible` is required on the object — verb and
   * permanence are never independently settable, so a caller cannot write an object that type-
   * checks yet is self-contradicting (e.g. `{ imperative: "Archive", gerund: "Archiving" }`
   * rendering "Permanently archive this organization … This cannot be undone."). Defaults to
   * `{ imperative: "Delete", gerund: "Deleting", reversible: false }` — so passing no
   * `actionVerb` at all renders today's exact wording, including every "Permanently" / "cannot
   * be undone" / "deletion" phrase, unchanged.
   *
   * Pass `reversible: true` (e.g. `{ imperative: "Archive", gerund: "Archiving", reversible:
   * true }`) for an action the user can undo later — this swaps out every phrase in the section
   * that otherwise asserts permanence, irreversibility, or data destruction, not just the verb,
   * and swaps the trigger button's glyph from the trash-can to an archive box.
   * A caller whose action is reversible should still pass its own `description`: the built-in
   * fallback is generic ("can be undone later") where a specific caller usually has a sharper
   * one to give (e.g. what un-archiving restores).
   */
  actionVerb?: { imperative: string; gerund: string; reversible: boolean };
}

const article = (noun: string): string =>
  /^[aeiou]/i.test(noun.trim()) ? "an" : "a";

/**
 * The "Danger" section for an entity's own settings pane: a **disclosure**
 * (collapsed by default, neutral styling) that reveals a destructive action
 * button only once opened — the `apt-red` accent appears solely in the disclosed
 * state, so a closed Danger zone doesn't shout (least-astonishment). The action
 * button is gated behind a two-phase confirm dialog — first an acknowledgement
 * ("Do you wish to proceed?"), then a type-to-confirm step whose button (default:
 * "Permanently Delete") only enables once the entity's exact identifier is typed
 * (case-sensitive, no extra whitespace). Defaults to today's "Delete"/"Permanently
 * Delete"/"cannot be undone" wording unchanged; pass `actionVerb` with
 * `reversible: true` (e.g. "Archive") to swap in non-destructive copy throughout —
 * every "Permanently"/"cannot be undone"/"deletion" phrase, not just the verb.
 * Shared across every FTD route (see cookbook/focused-topic-detail.md).
 */
export function DeleteEntitySection({
  entityNoun,
  confirmValue,
  childEntities,
  onConfirm,
  description,
  actionVerb = { imperative: "Delete", gerund: "Deleting", reversible: false },
}: DeleteEntitySectionProps): React.ReactElement {
  const inputId = React.useId();
  // The section is a disclosure, collapsed by default (so the destructive
  // affordance is opt-in, not always-present). Controlled here so the red accent
  // can track the open state.
  const [disclosed, setDisclosed] = React.useState(false);
  const [open, setOpen] = React.useState(false);
  const [phase, setPhase] = React.useState<Phase>("warn");
  const [typed, setTyped] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const noun = entityNoun.toLowerCase();
  const verb = actionVerb.imperative;
  const verbLower = verb.toLowerCase();
  const reversible = actionVerb.reversible;
  // Exact match: case-sensitive, no normalization/trim — typed must equal the rdid.
  // Guard the empty case: an empty `confirmValue` would match the initial empty
  // input and arm the destructive button with no typing at all.
  const confirmEnabled = confirmValue.length > 0 && typed === confirmValue && !busy;

  // The whole copy contract in one block: every phrase that varies with reversibility, plus the
  // trigger glyph. Two goals — the contract reads in one place instead of six scattered
  // ternaries, and "no reversible branch leaks a permanence claim" becomes checkable by eye.
  // The non-reversible branch must stay byte-identical to the pre-`actionVerb` hardcoded
  // strings — a previous commit (5e8632e) exists specifically to guarantee that; do not reword it.
  const copy = reversible
    ? {
        blurb: (
          <>
            {verb} this {noun}. This can be undone later.
          </>
        ),
        warnBody: (
          <>
            {actionVerb.gerund} {article(entityNoun)} {noun} affects{" "}
            {childEntities}. Do you wish to proceed?
          </>
        ),
        confirmTitle: (
          <>
            {verb} this {entityNoun}
          </>
        ),
        confirmLead: (
          <>You are about to {verbLower} this {entityNoun}. Enter{" "}</>
        ),
        inputLabel: <>Type {confirmValue} to confirm</>,
        cta: `${verb} ${entityNoun}`,
        Icon: Archive,
      }
    : {
        blurb: (
          <>
            Permanently {verbLower} this {noun} and all of its data. This cannot be
            undone.
          </>
        ),
        warnBody: (
          <>
            {actionVerb.gerund} {article(entityNoun)} {noun} deletes all the data
            associated with the {noun}, including {childEntities}. Do you
            wish to proceed?
          </>
        ),
        confirmTitle: (
          <>Permanently {verbLower} this {entityNoun}</>
        ),
        confirmLead: (
          <>You are about to permanently {verbLower} this {entityNoun}. Enter{" "}</>
        ),
        inputLabel: <>Type {confirmValue} to confirm deletion</>,
        cta: `Permanently ${verb}`,
        Icon: Trash2,
      };

  function reset(): void {
    setOpen(false);
    setPhase("warn");
    setTyped("");
    setBusy(false);
    setError(null);
  }

  function onOpenChange(next: boolean): void {
    if (next) {
      setOpen(true);
      return;
    }
    if (busy) return; // never dismiss mid-delete
    reset();
  }

  async function handleConfirm(): Promise<void> {
    if (!confirmEnabled) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirm();
      reset(); // parent navigates away on success; close defensively
    } catch (e) {
      setError(e instanceof Error ? e.message : `Failed to ${verbLower} ${noun}.`);
      setBusy(false);
    }
  }

  return (
    <section aria-label="Danger Zone">
      {/* Collapsed + neutral by default; the apt-red accent appears only once the
          section is disclosed, so the destructive affordance doesn't shout
          (least-astonishment). The primitive's title is apt-text, so the title
          node recolors itself red in the open state. The warning glyph stays
          apt-gold (its own color) in both states. */}
      <Disclosure
        open={disclosed}
        onOpenChange={setDisclosed}
        title={
          <span
            className={cn(
              "inline-flex items-center gap-1.5",
              disclosed && "text-apt-red",
            )}
          >
            <TriangleAlert className="size-4 shrink-0 text-apt-gold" aria-hidden />
            Danger Zone
          </span>
        }
        className={disclosed ? "border-apt-red/40 bg-apt-red/5" : undefined}
      >
        <div className="flex flex-col gap-3">
          <p className="text-sm text-apt-text-muted">
            {description ?? copy.blurb}
          </p>
          <div>
            <Button
              variant="destructive-ghost"
              size="sm"
              onClick={() => {
                setPhase("warn");
                setOpen(true);
              }}
            >
              <copy.Icon data-icon="inline-start" />
              {verb} {entityNoun}
            </Button>
          </div>
        </div>
      </Disclosure>

      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent showClose={!busy}>
          {phase === "warn" ? (
            <>
              <DialogHeader>
                <DialogTitle>{verb} {entityNoun}?</DialogTitle>
                <DialogDescription>{copy.warnBody}</DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="ghost" size="sm" onClick={reset}>
                  Cancel
                </Button>
                <Button
                  variant="destructive-ghost"
                  size="sm"
                  onClick={() => setPhase("confirm")}
                >
                  Yes
                </Button>
              </DialogFooter>
            </>
          ) : (
            <>
              <DialogHeader>
                <DialogTitle>{copy.confirmTitle}</DialogTitle>
                <DialogDescription>
                  {copy.confirmLead}
                  <span className="font-mono text-apt-text">
                    &ldquo;{confirmValue}&rdquo;
                  </span>{" "}
                  below to confirm.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-2">
                <Label htmlFor={inputId} className="sr-only">
                  {copy.inputLabel}
                </Label>
                <Input
                  id={inputId}
                  autoFocus
                  autoComplete="off"
                  spellCheck={false}
                  value={typed}
                  placeholder={confirmValue}
                  onChange={(e) => setTyped(e.target.value)}
                  aria-invalid={error ? true : undefined}
                />
                <ErrorText error={error} />
              </div>
              <DialogFooter>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={reset}
                  disabled={busy}
                >
                  Cancel
                </Button>
                <Button
                  variant="destructive"
                  size="sm"
                  onClick={handleConfirm}
                  disabled={!confirmEnabled}
                >
                  {busy ? `${actionVerb.gerund}…` : copy.cta}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </section>
  );
}
