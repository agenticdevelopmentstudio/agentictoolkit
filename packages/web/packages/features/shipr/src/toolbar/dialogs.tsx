'use client';

import * as React from 'react';

import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal';
import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import { flattenGroups, type NodeRef } from '../tree/levels';
import {
  ENVIRONMENTS,
  type Environment,
  type ForgeConnection,
  type Group,
} from '../types';

/**
 * The small forms the console opens.
 *
 * All of them share one shape — a modal, one submit, an error line, a spinner while the call
 * is out — so they share a file rather than four near-identical ones. Each takes an `onSubmit`
 * that RETURNS A PROMISE and closes only when it resolves: a dialog that dismisses on click
 * and fails behind the operator's back is how a rename that never happened gets believed.
 *
 * None of them decide anything. Which folders may be moved into, whether a name is taken,
 * whether the caller may delete — the backend answers all of it, and these forms surface
 * that answer verbatim.
 */

/** Shared submit plumbing: pending state, the error line, and closing only on success.
 *  Exported because the settings dialog is the same promise with a bigger form in front of
 *  it, and a second copy of this is a second chance to close over a rejected call. */
export function useSubmit(
  onSubmit: () => Promise<void>,
  onClose: () => void,
): { busy: boolean; error: string | null; run: () => void } {
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const run = React.useCallback(() => {
    setBusy(true);
    setError(null);
    void onSubmit().then(
      () => {
        setBusy(false);
        onClose();
      },
      (e: Error) => {
        setBusy(false);
        setError(e.message);
      },
    );
  }, [onSubmit, onClose]);
  return { busy, error, run };
}

export interface NameDialogProps {
  open: boolean;
  onClose: () => void;
  title: string;
  /** Pre-filled for a rename; empty for a create. */
  initial?: string;
  submitLabel: string;
  onSubmit: (name: string) => Promise<void>;
}

/** New folder, and Rename — the same form, because they are the same question. */
export function NameDialog({
  open,
  onClose,
  title,
  initial = '',
  submitLabel,
  onSubmit,
}: NameDialogProps): React.ReactElement {
  const [name, setName] = React.useState(initial);
  // Re-seed each time it OPENS, not on every render: an operator typing in a rename must not
  // have their edit overwritten by the row's old name on the next parent render.
  React.useEffect(() => {
    if (open) setName(initial);
  }, [open, initial]);

  const trimmed = name.trim();
  const submit = React.useCallback(() => onSubmit(trimmed), [onSubmit, trimmed]);
  const { busy, error, run } = useSubmit(submit, onClose);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (trimmed && !busy) run();
          }}
          className="flex flex-col gap-2"
        >
          <Label htmlFor="shipr-folder-name">Name</Label>
          <Input
            id="shipr-folder-name"
            value={name}
            autoFocus
            onChange={(e) => setName(e.target.value)}
            placeholder="fleet"
          />
          <ErrorText error={error} />
          <DialogFooter className="pt-2">
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={!trimmed || busy}>
              {busy ? 'Working…' : submitLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export interface ConfirmDialogProps {
  open: boolean;
  onClose: () => void;
  title: string;
  body: React.ReactNode;
  confirmLabel: string;
  onConfirm: () => Promise<void>;
}

/**
 * The confirmation, for every destructive verb this console offers.
 *
 * It is the platform's {@link AlertModal} in confirm mode rather than a modal assembled
 * here: a second implementation of "are you sure" is a second set of keyboard rules for the
 * same question, and this one was that second implementation until it was folded back.
 * `destructive` is the whole safety argument — the action button is red, Cancel takes
 * initial focus, and Enter and Escape are both dead, so nothing here can be answered by
 * momentum. It is one press, and deliberately not a phrase to retype.
 *
 * The refusal goes UNDER the question rather than replacing it. These calls are refused by
 * the backend for reasons the operator can act on ("move them out first"), and a dialog that
 * swapped its sentence for the refusal would drop what was about to happen.
 */
export function ConfirmDialog({
  open,
  onClose,
  title,
  body,
  confirmLabel,
  onConfirm,
}: ConfirmDialogProps): React.ReactElement {
  const { busy, error, run } = useSubmit(onConfirm, onClose);
  return (
    <AlertModal
      open={open}
      title={title}
      description={
        <>
          {body}
          <ErrorText error={error} />
        </>
      }
      confirmLabel={confirmLabel}
      cancelLabel="Cancel"
      destructive
      busy={busy}
      onConfirm={run}
      onCancel={onClose}
    />
  );
}

/**
 * Every folder a set of rows may be moved INTO, in tree order, with the ones that would
 * make a cycle removed.
 *
 * A group cannot move into itself or into anything beneath it. The database refuses both
 * (a CHECK for the first, the path trigger for the second), but offering a destination that
 * is guaranteed to fail is a menu that lies — so the descendants come out here too, computed
 * from the same `parentId` edge the rail draws.
 */
export function moveDestinations(
  groups: readonly Group[],
  moving: readonly NodeRef[],
): Group[] {
  const movingGroups = new Set(
    moving.filter((m) => m.kind === 'group').map((m) => m.id),
  );
  const forbidden = new Set(movingGroups);
  // Walk down from each moving folder. Repeat until nothing new is added: the rows are flat,
  // so one pass in `groups` order would miss a grandchild listed before its parent.
  let grew = true;
  while (grew) {
    grew = false;
    for (const g of groups) {
      if (g.parentId && forbidden.has(g.parentId) && !forbidden.has(g.id)) {
        forbidden.add(g.id);
        grew = true;
      }
    }
  }
  // Flattened FIRST and filtered after, so what survives keeps the rail's order rather
  // than being re-sorted into one of its own.
  return flattenGroups(groups).filter((g) => !forbidden.has(g.id));
}

export interface MoveDialogProps {
  open: boolean;
  onClose: () => void;
  groups: readonly Group[];
  moving: readonly NodeRef[];
  /** What is being moved, in words, for the dialog's own sentence. */
  movingLabel: string;
  /** `null` is the root — a folder or a repository with no parent at all. */
  onSubmit: (destination: string | null) => Promise<void>;
}

export function MoveDialog({
  open,
  onClose,
  groups,
  moving,
  movingLabel,
  onSubmit,
}: MoveDialogProps): React.ReactElement {
  const destinations = React.useMemo(
    () => moveDestinations(groups, moving),
    [groups, moving],
  );
  const [destination, setDestination] = React.useState<string>('');
  React.useEffect(() => {
    if (open) setDestination('');
  }, [open]);

  const submit = React.useCallback(
    () => onSubmit(destination === '' ? null : destination),
    [onSubmit, destination],
  );
  const { busy, error, run } = useSubmit(submit, onClose);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Move {movingLabel}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="shipr-move-destination">Destination</Label>
          <Select
            id="shipr-move-destination"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
          >
            <option value="">(top level)</option>
            {destinations.map((g) => (
              <option key={g.id} value={g.id}>
                {/* Indented by depth rather than showing the whole path: the rail already
                    taught the reader this shape, and a long path truncates in a select. */}
                {'  '.repeat(g.depth)}
                {g.name}
              </option>
            ))}
          </Select>
          <ErrorText error={error} />
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={run}>
            {busy ? 'Moving…' : 'Move'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** One of the caller's forge connections, as the host names it. The host reads them from
 *  `GET /shipr/connections`; this alias is the name the dialog knows them by. */
export type ConnectionOption = ForgeConnection;

export interface DeployRequest {
  /** Bring the prepared branch up to date first, as a run of its own before the deploy. */
  prepare: boolean;
  environments: Environment[];
}

export interface DeployDialogProps {
  open: boolean;
  onClose: () => void;
  /** What the run will be aimed at, so the dialog says it rather than "the selection". */
  targetLabel: string;
  onSubmit: (request: DeployRequest) => Promise<void>;
}

/**
 * Deploy — the one button that needs an answer before it does anything.
 *
 * It was a dropdown, and a dropdown is the wrong shape for this: each entry fired the
 * instant it was clicked, so choosing production was ONE click with nothing in between, and
 * there was no way to say "prepare, then ship to staging and production" without pressing
 * two controls and hoping they queued in the right order.
 *
 * A modal makes the whole request visible before any of it happens, and gives the operator
 * somewhere to change their mind. Deploy stays dead until at least one box is ticked —
 * there is no such thing as a deploy to nowhere — and Escape leaves without running
 * anything, which is the property that makes pressing Deploy safe to do by accident.
 */
export function DeployDialog({
  open,
  onClose,
  targetLabel,
  onSubmit,
}: DeployDialogProps): React.ReactElement {
  const [prepare, setPrepare] = React.useState(false);
  const [envs, setEnvs] = React.useState<readonly Environment[]>([]);

  // Every opening starts from nothing chosen. A dialog that remembers last time's ticks is
  // a dialog that deploys to production because of a decision made an hour ago.
  React.useEffect(() => {
    if (open) {
      setPrepare(false);
      setEnvs([]);
    }
  }, [open]);

  const toggle = (env: Environment) =>
    setEnvs((prev) =>
      prev.includes(env) ? prev.filter((e) => e !== env) : [...prev, env],
    );

  // ORDERED BY THE LADDER, not by the order they were ticked: `ENVIRONMENTS` is testing,
  // staging, production — outermost first — and that is the order the backend walks them.
  const chosen = ENVIRONMENTS.filter((env) => envs.includes(env));
  const anything = prepare || chosen.length > 0;

  const submit = React.useCallback(
    () =>
      onSubmit({
        prepare,
        environments: [...chosen],
      }),
    // `chosen` is derived from `envs` on every render; keying on the contents keeps the
    // submit callback from changing identity when nothing about the request has.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [onSubmit, prepare, chosen.join(',')],
  );
  const { busy, error, run } = useSubmit(submit, onClose);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Deploy {targetLabel}</DialogTitle>
        </DialogHeader>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (anything && !busy) run();
          }}
          className="flex min-w-0 flex-col gap-3"
        >
          {/* Prepare sits ABOVE the environments and outside their fieldset, because it is
              not one of them: it is the step that happens first, on the way there. */}
          {/* The label wraps a BUTTON — Base UI's checkbox is not a native input, and a
              wrapping <label> names only labelable elements — so each box carries its own
              `aria-label`. Without it the whole form is a row of anonymous checkboxes. */}
          <label className="flex items-center gap-2 text-sm text-apt-text">
            <Checkbox
              checked={prepare}
              aria-label="Prepare"
              onCheckedChange={(checked: boolean) => setPrepare(checked)}
            />
            <span>Prepare</span>
          </label>

          <fieldset className="flex flex-col gap-2 border-t border-apt-border pt-3">
            <div className="flex items-center gap-2">
              <legend className="flex-1 text-xs font-semibold text-apt-text-muted">
                Deployment environments
              </legend>
              {/* `outline`, not `ghost`: a ghost button beside a legend is a word with
                  nothing around it, and these two read as part of the caption rather than
                  as things to press (Mike). The border and fill are the whole difference. */}
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => setEnvs([...ENVIRONMENTS])}
              >
                All
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => setEnvs([])}
              >
                None
              </Button>
            </div>

            {ENVIRONMENTS.map((env) => (
              <label
                key={env}
                className="flex items-center gap-2 text-sm text-apt-text"
              >
                <Checkbox
                  checked={envs.includes(env)}
                  aria-label={env}
                  onCheckedChange={() => toggle(env)}
                />
                <span>{env}</span>
              </label>
            ))}
          </fieldset>

          <ErrorText error={error} />
          <DialogFooter className="pt-1">
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            {/* `type="submit"` is what makes Return press it: the form's default action is
                this button, so the keyboard path and the mouse path are one piece of code.
                Escape is the Dialog's own, and closes without running anything. */}
            <Button type="submit" disabled={!anything || busy}>
              {busy ? 'Starting…' : 'Deploy'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
