"use client";

import { type ReactElement } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@agenticdevelopertoolkit/ui/components/dialog";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { AdminNotesModal as SharedAdminNotesModal } from "@agentic-toolkit/adh-ui/blocks";
import { useRowNotes, useSaveNotes } from "../api/invitations";

/**
 * Thin react-query wrapper around the shared, prop-driven staged notes editor.
 *
 * Fetches notes for the subject, gating on the load so the shared editor mounts
 * (and seeds its staged working copy) only once the loaded notes are available.
 * The subject `key` forces a fresh working copy when the target row changes.
 *
 * Save → PUT via useSaveNotes, then close + invalidate on success.
 */
export function AdminNotesModal({ open, onClose, author, subjectTable, subjectId }: {
  open: boolean;
  onClose: () => void;
  author: string;
  subjectTable: string;
  subjectId: string;
}): ReactElement {
  const notesQ = useRowNotes(subjectTable, subjectId);
  const save = useSaveNotes();

  // Gate the shared editor on the load: its working copy seeds AT MOUNT from the
  // notes prop, so it must not mount until the loaded notes are in hand.
  if (notesQ.isPending || notesQ.data === undefined) {
    return (
      <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
        <DialogContent className="max-w-3xl">
          <DialogHeader><DialogTitle className="text-apt-gold">Admin notes</DialogTitle></DialogHeader>
          <div className="flex h-[420px] items-center justify-center">
            <p className="text-sm text-apt-text-dim">Loading…</p>
          </div>
          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={onClose}>Cancel</Button>
            <Button size="sm" disabled>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <SharedAdminNotesModal
      key={`${subjectTable}:${subjectId}`}
      open={open}
      onClose={onClose}
      author={author}
      notes={notesQ.data}
      onSave={(notes) => save.mutate({ subjectTable, subjectId, notes }, { onSuccess: onClose })}
      busy={save.isPending}
    />
  );
}
