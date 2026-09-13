'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';

import {
  SettingsForm,
  settingsTitle,
  type RepoSettingsPatch,
  type SettingsTarget,
} from './SettingsForm';
import { SHIPR_DIALOG_SURFACE } from '../dialogSurface';

/**
 * Settings — a modal, because configuration is not the answer to "how is this repository
 * doing".
 *
 * The names underneath a pipeline (which branch is `ship`, which CI context is watched,
 * which mirror is pushed) used to sit under the ladder in the detail pane, where they were
 * read approximately never and pushed the one thing people opened the pane for up out of
 * sight. They are reference material, so they live behind a menu item and the pane is left
 * saying what the pipeline is doing.
 *
 * A FRAME AND NOTHING ELSE. Everything it shows is {@link SettingsForm}, which the Configure
 * dialog also mounts — in a pane rather than a modal, because a modal on top of a modal is
 * not a thing to offer. One implementation, two frames, so the two cannot drift.
 */
export type { RepoSettingsPatch, SettingsTarget };

export interface SettingsDialogProps {
  open: boolean;
  /** Null while closed — the dialog holds no state of its own between openings. */
  target: SettingsTarget | null;
  onClose: () => void;
  /** The repositories to write. Empty when nothing moved, and the form does not call it
   *  then: a Save that writes nothing should still not spend eleven round trips saying so. */
  onSave: (patches: RepoSettingsPatch[]) => Promise<void>;
}

export function SettingsDialog({
  open,
  target,
  onClose,
  onSave,
}: SettingsDialogProps): React.ReactElement {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className={SHIPR_DIALOG_SURFACE}>
        <DialogHeader>
          <DialogTitle>{settingsTitle(target)}</DialogTitle>
        </DialogHeader>

        {/* `active={open}` and not the default: a dialog stays MOUNTED while closed, so the
            boxes have to be re-seeded when it opens rather than when it mounts. A pane is
            mounted per selection and wants the default. */}
        <SettingsForm
          target={target}
          active={open}
          onSave={onSave}
          onSaved={onClose}
          cancel={
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
          }
        />
      </DialogContent>
    </Dialog>
  );
}
