"use client";

import type { ReactElement } from "react";
import { InvitationRequestsPane } from "@agentic-toolkit/adh-ui/blocks";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { NotesAndHistory } from "./NotesAndHistory";
import { AdminNotesModal } from "../components/AdminNotesModal";
import { useInvitationRequests, useDeleteInvitationRow } from "../api/invitations";

export function RequestsPane(): ReactElement {
  const { data: requests = [], isPending, isError } = useInvitationRequests();
  const deleteRow = useDeleteInvitationRow("request");

  if (isError) return <ErrorText error="Failed to load requests." />;

  return (
    <InvitationRequestsPane
      rows={requests}
      loading={isPending}
      paramKey="request"
      onDelete={(ids) => { for (const id of ids) deleteRow.mutate(id); }}
      renderNotesAndHistory={(s) => <NotesAndHistory {...s} />}
      renderNotesModal={(s) => <AdminNotesModal author="admin@adh" {...s} />}
    />
  );
}
