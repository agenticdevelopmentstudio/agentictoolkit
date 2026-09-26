"use client";

import { useCallback, useId, useState, type ReactElement, type ReactNode } from "react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";

export interface TypeToConfirmDialogProps {
  open: boolean;
  title: string;
  description?: ReactNode;
  /** The exact string the operator has to type. Matched case-sensitively, untrimmed. */
  confirmValue: string;
  /** What to call the value in the prompt — "name", "address", "word". */
  valueNoun?: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
  /**
   * Move past THIS item and carry on, for a dialog that is walking a queue.
   *
   * Without it a queue has exactly two exits, and both are wrong once one item cannot succeed: the
   * dialog re-presents the same doomed item forever, or Cancel abandons every item behind it —
   * including the ones that would have worked. A per-item failure is ordinary (releasing a parent
   * before its children 409s by design), so stepping over one has to be an ordinary control.
   *
   * Omit it for a one-shot confirmation, where there is nothing to skip to.
   */
  onSkip?: () => void;
  skipLabel?: string;
  busy?: boolean;
  error?: string | null;
}

/**
 * A destructive confirmation that has to be TYPED, not clicked.
 *
 * The gap this closes is the one every "are you sure?" leaves open: a confirm button under the
 * pointer is one reflex away from the button that opened it, and an operator who meant to release
 * `storage.acme.notes` and had `storage.acme.node` selected gets no second look at which one it
 * was. Typing the value is the only gate that makes them READ it.
 *
 * Matched exactly — no trim, no case folding. Two rdids that differ only in case are two
 * different names, so a confirmation that accepted either would be confirming something other
 * than what it showed.
 */
export function TypeToConfirmDialog({
  open,
  title,
  description,
  confirmValue,
  valueNoun = "name",
  confirmLabel,
  onConfirm,
  onCancel,
  onSkip,
  skipLabel = "Skip",
  busy = false,
  error,
}: TypeToConfirmDialogProps): ReactElement {
  const inputId = useId();
  const [typed, setTyped] = useState("");
  // Focus when the input ATTACHES (dialog open) — the autoFocus prop is banned by
  // jsx-a11y/no-autofocus; a stable callback ref never re-steals focus on re-render.
  const focusOnAttach = useCallback((el: HTMLInputElement | null) => {
    el?.focus();
  }, []);

  // Re-arm for each value the dialog is pointed at, not just for each open: a dialog that steps
  // through a selection stays open and swaps `confirmValue` underneath, and carrying the previous
  // row's typing across would leave the box holding text that confirms nothing.
  //
  // Adjusted DURING RENDER rather than in an effect, which is React's own answer for state that
  // has to reset when a prop changes: an effect would paint the stale typing once first, and for
  // one frame the armed destructive button would belong to the previous target.
  const target = `${open}\u0000${confirmValue}`;
  const [armedTarget, setArmedTarget] = useState(target);
  if (armedTarget !== target) {
    setArmedTarget(target);
    setTyped("");
  }

  // The empty guard is load-bearing: an empty `confirmValue` matches the untouched input, which
  // would arm the destructive button with no typing at all.
  const armed = confirmValue.length > 0 && typed === confirmValue && !busy;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next && !busy) onCancel();
      }}
    >
      <DialogContent showClose={!busy}>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description != null && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor={inputId}>
            Type the {valueNoun}{" "}
            <span className="font-mono text-apt-text break-all">{confirmValue}</span> to confirm
          </Label>
          <Input
            id={inputId}
            ref={focusOnAttach}
            value={typed}
            spellCheck={false}
            autoComplete="off"
            disabled={busy}
            onChange={(e) => setTyped(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && armed) {
                e.preventDefault();
                onConfirm();
              }
            }}
          />
          {error && <ErrorText error={error} />}
        </div>
        <DialogFooter>
          <Button variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          {onSkip && (
            <Button variant="secondary" size="sm" onClick={onSkip} disabled={busy}>
              {skipLabel}
            </Button>
          )}
          <Button variant="destructive" size="sm" onClick={onConfirm} disabled={!armed}>
            {busy ? "Working…" : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
