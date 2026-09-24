"use client";

import type { ReactNode } from "react";
import { Pencil, Plus, Trash2 } from "lucide-react";

import { Button } from "@agenticdevelopertoolkit/ui/components/button";

/**
 * The Add / Edit / Delete verbs an `EditableList`'s bar carries, laid out the way admin's Users
 * table lays its own: ghost buttons, the destructive one last, each enabled by the SELECTION
 * rather than drawn once per row.
 *
 * Here because every User Settings list used to spell its verbs differently — a pencil and a
 * trash can on each row in Social links and Addresses, a Remove button per row in Contacts and
 * Passkeys, Revoke per row in Tokens, a floating "+ Add" on the right of a heading — and the
 * sections read as though they came from different sites. One strip is what makes them one.
 *
 *   • Edit needs exactly ONE selected row: an editor opens one record, and quietly picking "the
 *     first ticked row" out of three is a guess the user never asked for.
 *   • Delete needs at least one; the caller owns the confirmation, because the caller is the one
 *     that knows what a failed delete should say.
 *   • `children` goes between Edit and Delete, so a list's own verb (Verify, Restore, All on)
 *     sits with the others and Delete stays the last, most-separated button.
 *
 * `noun` names the Add button for assistive tech ("Add social link") while the visible label
 * stays the bar's one word, matching its siblings.
 */
export function ListBarActions({
  noun,
  selectedCount,
  onAdd,
  addLabel = "Add",
  onEdit,
  onDelete,
  deleteLabel = "Delete",
  children,
}: {
  noun: string;
  selectedCount: number;
  onAdd?: () => void;
  addLabel?: string;
  onEdit?: () => void;
  onDelete?: () => void;
  deleteLabel?: string;
  children?: ReactNode;
}) {
  return (
    <>
      {onAdd && (
        <Button size="sm" variant="ghost" aria-label={`${addLabel} ${noun}`} onClick={onAdd}>
          <Plus data-icon="inline-start" />
          {addLabel}
        </Button>
      )}
      {onEdit && (
        <Button size="sm" variant="ghost" disabled={selectedCount !== 1} onClick={onEdit}>
          <Pencil data-icon="inline-start" />
          Edit
        </Button>
      )}
      {children}
      {onDelete && (
        <Button
          size="sm"
          variant="destructive-ghost"
          disabled={selectedCount === 0}
          onClick={onDelete}
        >
          <Trash2 data-icon="inline-start" />
          {deleteLabel}
        </Button>
      )}
    </>
  );
}
