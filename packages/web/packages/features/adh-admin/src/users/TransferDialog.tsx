"use client";

import * as React from "react";
import { Alert, AlertDescription, AlertTitle } from "@agenticdevelopertoolkit/ui/components/alert";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import type { TransferConflict } from "./transfer";

export interface ConfirmSourceDialogProps {
  open: boolean;
  /** The ecosystem the selected users are LEAVING — the string that must be typed. */
  sourceRdid: string;
  targetRdid: string;
  count: number;
  /** What the preflight found, keyed to the same selection. Empty means a clean move. */
  conflicts?: TransferConflict[];
  /** The preflight is still running. */
  checking?: boolean;
  /** How to name a user in the conflict list — the ids alone say nothing to an operator. */
  labelOf?: (userId: string) => string;
  onCancel: () => void;
  onConfirm: () => void;
}

/**
 * The second gate: type the CURRENT ecosystem's address to release the transfer.
 *
 * The two gates ask different questions on purpose. The picker asked "where to"; this asks "from
 * where", which is the question a mis-click actually gets wrong — the operator just chose the
 * destination off a list, so retyping it would confirm nothing but their own last click. Typing
 * the SOURCE is a claim about which set of users is selected.
 *
 * CASE SENSITIVE, per the brief, and the reason is that this gate exists to be slow. Accepting a
 * case-insensitive match accepts a half-remembered address; requiring it exactly means the
 * operator has to read the one on screen.
 *
 * No trimming either: a pasted value with a stray space is a value that came from somewhere other
 * than the address above, which is exactly the situation worth catching.
 */
export function ConfirmSourceDialog({
  open,
  sourceRdid,
  targetRdid,
  count,
  conflicts,
  checking = false,
  labelOf,
  onCancel,
  onConfirm,
}: ConfirmSourceDialogProps): React.ReactElement {
  const [typed, setTyped] = React.useState("");
  const fieldId = React.useId();

  // A reopened dialog must not still hold the last confirmation's text: the gate would already
  // be open before the operator had read what they were confirming this time.
  React.useEffect(() => {
    if (!open) setTyped("");
  }, [open]);

  // The empty-string guard is the whole reason this is not a bare `===`. The source address is
  // RESOLVED, not hardcoded, so it is "" for the moment before the lookup lands — and an empty
  // field equals an empty expectation, which would open the gate on a dialog that had not even
  // told the operator what they were leaving.
  const matches = sourceRdid !== "" && typed === sourceRdid;

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) onCancel(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Transfer users to another ecosystem</DialogTitle>
          <DialogDescription>
            {count} users will move from <span className="font-mono">{sourceRdid}</span> to{" "}
            <span className="font-mono">{targetRdid}</span>. Their addresses change; the old ones
            keep resolving as aliases.
          </DialogDescription>
        </DialogHeader>

        {/*
          The preflight's answer, shown ABOVE the field the operator has to type into. Below it
          would be read after the decision was made; the point of running the check before the move
          is that it can still change the decision. It never DISABLES the button — a collision is
          the operator's to weigh, and the transfer loop halts on it anyway with the same
          Continue/Stop choice. What it removes is the surprise.
        */}
        {checking ? (
          <p className="text-xs text-apt-text-dim">Checking for collisions in the destination…</p>
        ) : conflicts && conflicts.length > 0 ? (
          // `accent`, matching the Transfer button's `warning`: a collision stops a move, it does
          // not destroy anything, and `error` is the tone reserved for what already went wrong.
          <Alert variant="accent">
            <AlertTitle>
              {conflicts.length} {conflicts.length === 1 ? "collision" : "collisions"} in{" "}
              <span className="font-mono">{targetRdid}</span>
            </AlertTitle>
            <AlertDescription>
              <ul className="flex flex-col gap-1">
                {conflicts.map((conflict, i) => (
                  <li key={`${conflict.userId}-${conflict.constraint}-${i}`}>
                    <span className="font-medium text-apt-text">
                      {labelOf?.(conflict.userId) ?? conflict.userId}
                    </span>
                    {" — "}
                    {conflict.detail}{" "}
                    <span className="font-mono text-apt-text-dim">({conflict.constraint})</span>
                  </li>
                ))}
              </ul>
            </AlertDescription>
          </Alert>
        ) : conflicts ? (
          <p className="text-xs text-apt-text-dim">No collisions found in the destination.</p>
        ) : null}

        <div className="flex flex-col gap-1.5">
          <Label htmlFor={fieldId}>
            Type the current ecosystem address to continue (case sensitive)
          </Label>
          <Input
            id={fieldId}
            value={typed}
            autoComplete="off"
            spellCheck={false}
            placeholder={sourceRdid}
            onChange={(e) => setTyped(e.target.value)}
          />
        </div>

        <DialogFooter>
          <Button size="sm" variant="ghost" onClick={onCancel}>
            Cancel
          </Button>
          {/*
            `warning`, not `destructive`. That variant's own docstring names this exact case: a
            transfer moves an object and drops other people's access, but destroys nothing —
            painting it the same red as Delete spends the colour that has to mean "unrecoverable".
          */}
          <Button size="sm" variant="warning" disabled={!matches} onClick={onConfirm}>
            Transfer
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
