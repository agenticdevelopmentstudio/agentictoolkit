"use client";

import type { ReactElement } from "react";
import { InvitationInvitesPane } from "@agentic-toolkit/adh-ui/blocks";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { NotesAndHistory } from "./NotesAndHistory";
import { AdminNotesModal } from "../components/AdminNotesModal";
import { useInvites, useDeleteInvitationRow } from "../api/invitations";

export function InvitesPane(): ReactElement {
  const { data: invites = [], isPending, isError } = useInvites();
  const deleteRow = useDeleteInvitationRow("invite");

  if (isError) return <ErrorText error="Failed to load invites." />;

  return (
    <InvitationInvitesPane
      rows={invites}
      loading={isPending}
      paramKey="invite"
      onDelete={(ids) => { for (const id of ids) deleteRow.mutate(id); }}
      renderNotesAndHistory={(s) => <NotesAndHistory {...s} />}
      renderNotesModal={(s) => <AdminNotesModal author="admin@adh" {...s} />}
    />
  );
}
