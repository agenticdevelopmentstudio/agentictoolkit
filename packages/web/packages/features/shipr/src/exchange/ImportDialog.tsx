'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import { DocumentError, parseDocument, writtenBy, type ShiprDocument } from './document';
import { readTextFile } from './files';
import { planImport, type ImportPlan, type PlanRow, type RowState } from './plan';
import { useSubmit } from '../toolbar/dialogs';
import type { ForgeConnection, Group, RepoItem } from '../types';
import { SHIPR_DIALOG_SURFACE } from '../dialogSurface';

/**
 * Reading a `shipr-config-export.json` back in.
 *
 * THE FILE IS SHOWN AS A PLAN BEFORE ANY OF IT HAPPENS, which is `shipr import`'s own shape:
 * the CLI is dry by default and writes only under `--apply`, and the reason is stronger on
 * this side of the wire. There, applying overwrites JSON files on a workstation; here it
 * registers repositories on a forge and starts a run per registration. A dialog that read a
 * file and did that on one click would be asking the operator to trust a file they had not
 * been shown the consequences of.
 *
 * THE MARKS ARE THE CLI'S — `+` a registration, `~` settings that differ, `=` already as
 * written — plus `!` for a project this console cannot act on, which the CLI has no need of
 * because a workstation can always write a config file. Anyone reading both outputs is
 * reading one vocabulary.
 *
 * IT DOES NOT WRITE. `onImport` goes back up to the console, which owns every client call in
 * this feature; a registration queued from here lands in the same queue, spins the same rail
 * and is cancelled by the same button as one made through the wizard.
 */

export interface ImportDialogProps {
  open: boolean;
  onClose: () => void;
  /** The live tree, which is what the file is compared against. */
  groups: readonly Group[];
  items: readonly RepoItem[];
  /** Which installation a registration goes out over. The plan's `+` rows need one; a
   *  document with none of them never asks. */
  connections?: readonly ForgeConnection[];
  /** Run the plan. The console holds the client, so what comes back — the runs it queued —
   *  is queued where every other run is. */
  onImport: (plan: ImportPlan, connectionId?: string) => Promise<void>;
}

const MARK: Record<RowState, string> = {
  new: '+',
  differs: '~',
  same: '=',
  blocked: '!',
};

const MARK_CLASS: Record<RowState, string> = {
  new: 'text-apt-green',
  differs: 'text-apt-gold',
  same: 'text-apt-text-muted',
  blocked: 'text-apt-red',
};

export function ImportDialog({
  open,
  onClose,
  groups,
  items,
  connections,
  onImport,
}: ImportDialogProps): React.ReactElement {
  const [filename, setFilename] = React.useState('');
  const [document, setDocument] = React.useState<ShiprDocument | null>(null);
  const [readError, setReadError] = React.useState<string | null>(null);
  const [connectionId, setConnectionId] = React.useState('');
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  const firstConnectionId = connections?.[0]?.id ?? '';

  // Re-seeded on OPEN, not on mount — the dialog stays mounted while closed, and a second
  // import must not start on the first one's file. Especially this one: the tree it would be
  // compared against has moved since, so the plan on the screen would describe a fleet that
  // no longer exists. Keyed on `open` ALONE: `connections` is not, so a list that merely
  // reordered mid-read (a background revalidation) does not run this and throw away a file
  // the operator already picked.
  React.useEffect(() => {
    if (!open) return;
    setFilename('');
    setDocument(null);
    setReadError(null);
    // The platform control keeps whatever the operator last chose; without this, picking the
    // SAME file again after a reset fires no change event and the dialog just sits there.
    if (fileInputRef.current) fileInputRef.current.value = '';
  }, [open]);

  // Seeding the connection default is a separate concern from resetting the read: it should
  // track the connections list, not just `open`, so a picker that arrives after the dialog is
  // already open (the list finishes loading a beat later) still gets a default.
  React.useEffect(() => {
    if (!open) return;
    setConnectionId(firstConnectionId);
  }, [open, firstConnectionId]);

  const onFile = React.useCallback(async (file: File | undefined) => {
    if (!file) return;
    setFilename(file.name);
    setDocument(null);
    setReadError(null);
    try {
      setDocument(parseDocument(await readTextFile(file)));
    } catch (e) {
      // `DocumentError` already says which of the four things is wrong, in a sentence. Any
      // other failure is the browser's, and its message is the only account of it there is.
      setReadError(
        e instanceof DocumentError ? e.message : `That file could not be read (${(e as Error).message}).`,
      );
    }
  }, []);

  const plan = React.useMemo<ImportPlan | null>(
    () => (document ? planImport({ document, groups, items }) : null),
    [document, groups, items],
  );

  const acts = plan ? plan.counts.new + plan.counts.differs : 0;
  const submit = React.useCallback(
    () => (plan ? onImport(plan, connectionId || undefined) : Promise.resolve()),
    [plan, onImport, connectionId],
  );
  const { busy, error, run } = useSubmit(submit, onClose);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className={`flex max-h-[80vh] max-w-2xl flex-col gap-4 ${SHIPR_DIALOG_SURFACE}`}>
        <DialogHeader>
          <DialogTitle>Import configuration</DialogTitle>
          <DialogDescription>
            A <span className="font-mono">shipr-config-export.json</span> — the file{' '}
            <span className="font-mono">shipr export</span> writes, or one this console
            exported. Nothing happens until the plan below is applied.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="shipr-import-file">Configuration file</Label>
          {/* The platform's own file picker, unstyled beyond the row it sits in: it is the
              one control on this screen whose behaviour every operator already knows, and a
              custom drop zone would be a second way to do the same thing badly. */}
          <input
            id="shipr-import-file"
            ref={fileInputRef}
            type="file"
            accept="application/json,.json"
            className="text-xs text-apt-text-muted file:mr-3 file:rounded file:border file:border-apt-border file:bg-apt-surface-2 file:px-2 file:py-1 file:text-xs file:text-apt-text"
            onChange={(e) => void onFile(e.target.files?.[0])}
          />
          <ErrorText error={readError} />
        </div>

        {document && plan ? (
          <>
            <p className="text-xs text-apt-text-muted">
              <span className="font-mono text-apt-text">{filename}</span> — {document.projects.length}{' '}
              {document.projects.length === 1 ? 'project' : 'projects'}, written by{' '}
              {writtenBy(document)}
              {document.exported_at ? ` on ${document.exported_at}` : ''}.
            </p>

            <ul className="min-h-0 flex-1 divide-y divide-apt-border overflow-y-auto rounded border border-apt-border">
              {plan.rows.map((row) => (
                <Row key={`${row.project.directory}:${row.project.group ?? ''}`} row={row} />
              ))}
            </ul>

            <Summary plan={plan} />

            {/* Asked for only when something will actually be registered. An import that only
                changes settings on repositories that are already here goes out over the
                installations they were registered with, so a picker would be a question with
                no consequence. */}
            {plan.counts.new > 0 ? (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="shipr-import-connection">GitHub App installation</Label>
                {connections && connections.length > 0 ? (
                  <Select
                    id="shipr-import-connection"
                    value={connectionId}
                    onChange={(e) => setConnectionId(e.target.value)}
                  >
                    {connections.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.accountLogin ? `${c.accountLogin} — ${c.label}` : c.label}
                      </option>
                    ))}
                  </Select>
                ) : (
                  <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
                    No GitHub App installation. Install the app on the account that holds
                    these repositories, and the registrations below can go out over it.
                  </p>
                )}
              </div>
            ) : null}
          </>
        ) : null}

        <ErrorText error={error} />

        <DialogFooter>
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="button"
            disabled={busy || acts === 0}
            title={
              plan && acts === 0 ? 'Everything in that file is already as it describes.' : undefined
            }
            onClick={run}
          >
            {busy ? 'Importing…' : 'Import'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** One project, its mark, and what the mark means for it — the changes under a `~`, the
 *  refusal under a `!`, and the notes under either, which are the things the import is
 *  deliberately NOT carrying. A dropped field that is never mentioned is the failure a plan
 *  exists to prevent. */
function Row({ row }: { row: PlanRow }): React.ReactElement {
  return (
    <li className="flex gap-2 px-3 py-2 text-xs">
      <span className={`font-mono ${MARK_CLASS[row.state]}`} aria-hidden>
        {MARK[row.state]}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-apt-text">
          <span className="font-mono">{row.project.directory}</span>
          {row.project.group ? (
            <span className="text-apt-text-muted"> in {row.project.group}</span>
          ) : null}
          <span className="sr-only"> — {STATE_WORD[row.state]}</span>
        </p>
        {row.state === 'new' ? (
          <p className="text-apt-text-muted">
            register <span className="font-mono">{row.project.remotes.dev.slug}</span> →{' '}
            <span className="font-mono">{row.project.remotes.deployment.slug}</span>
          </p>
        ) : null}
        {row.changes.map((change) => (
          <p key={change} className="text-apt-text-muted">
            {change}
          </p>
        ))}
        {row.reason ? <p className="text-apt-red">{row.reason}</p> : null}
        {row.notes.map((note) => (
          <p key={note} className="text-apt-text-muted italic">
            {note}
          </p>
        ))}
      </div>
    </li>
  );
}

/** What the mark says, for a reader who is not looking at the colour. */
const STATE_WORD: Record<RowState, string> = {
  new: 'to register',
  differs: 'settings differ',
  same: 'already as written',
  blocked: 'cannot be imported',
};

/**
 * The counts, and the one thing about a registration this plan cannot show as a change.
 *
 * A `+` row's ship branch, gate context and environments are NOT sent with the registration —
 * `register` takes the source, the branches it is cut from and where to file it, and the rest
 * of the config belongs to a deployment repository that does not exist until the run makes
 * it. Importing the same file again once the runs have landed carries them, and the second
 * import is a `~`. Saying so here is the difference between an idempotent verb and one that
 * looks like it lost half the file.
 */
function Summary({ plan }: { plan: ImportPlan }): React.ReactElement {
  const parts = [
    plan.counts.new > 0 ? `${plan.counts.new} to register` : null,
    plan.counts.differs > 0 ? `${plan.counts.differs} to update` : null,
    plan.counts.same > 0 ? `${plan.counts.same} already as written` : null,
    plan.counts.blocked > 0 ? `${plan.counts.blocked} skipped` : null,
    plan.newGroups.length > 0
      ? `${plan.newGroups.length} ${plan.newGroups.length === 1 ? 'folder' : 'folders'} to create`
      : null,
  ].filter(Boolean);
  return (
    <div className="flex flex-col gap-1 text-xs text-apt-text-muted">
      <p>{parts.length > 0 ? parts.join(', ') : 'Nothing to do.'}</p>
      {plan.counts.new > 0 ? (
        <p>
          A registration carries the source, its branches and its folder. The ship branch,
          gate context and environments arrive on a second import of the same file, once
          those runs have made the deployment repositories.
        </p>
      ) : null}
    </div>
  );
}
