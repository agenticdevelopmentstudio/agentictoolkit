"use client";

import type { ReactElement } from "react";
import { InvitationPendingUsersPane } from "@agentic-toolkit/adh-ui/blocks";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { NotesAndHistory } from "./NotesAndHistory";
import { AdminNotesModal } from "../components/AdminNotesModal";
import {
  usePendingUsers,
  useDeleteInvitationRow,
  useSendInvitations,
  useAddPendingUsers,
} from "../api/invitations";

export function PendingUsersPane(): ReactElement {
  const { data: pendingUsers = [], isPending, isError } = usePendingUsers();
  const deleteRow = useDeleteInvitationRow("pending");
  const sendInvitations = useSendInvitations();
  const addPendingUsers = useAddPendingUsers();

  if (isError) return <ErrorText error="Failed to load pending users." />;

  return (
    <InvitationPendingUsersPane
      rows={pendingUsers}
      loading={isPending}
      paramKey="pending"
      onDelete={(ids) => { for (const id of ids) deleteRow.mutate(id); }}
      onSend={(payload) =>
        // mutateAsync: the shared pane closes the send modal only when this
        // promise resolves; a failed POST keeps it open for retry.
        sendInvitations.mutateAsync({
          pendingUserIds: payload.pendingUserIds,
          email: payload.email ? { note: payload.email.note } : undefined,
          sms: payload.sms ? { note: payload.sms.note } : undefined,
        })
      }
      onAdd={(users) =>
        addPendingUsers.mutate(
          // `|| undefined` (not `??`): DraftUser fields default to "", and `"" ?? undefined` keeps the
          // empty string — the backend's `email: z.string().email().optional()` then rejects "" (400),
          // breaking the SMS-only (name+phone, blank email) add. Coerce blanks to omitted instead.
          users.map((u) => ({ name: u.name, email: u.email || undefined, phone: u.phone || undefined, note: u.note || undefined })),
        )
      }
      sendBusy={sendInvitations.isPending}
      addBusy={addPendingUsers.isPending}
      renderNotesAndHistory={(s) => <NotesAndHistory {...s} />}
      renderNotesModal={(s) => <AdminNotesModal author="admin@adh" {...s} />}
    />
  );
}
