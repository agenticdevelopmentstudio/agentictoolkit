"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { authedJson, authedRequest } from "./http";
import {
  toRequest,
  toPendingUser,
  toInvite,
  toAdminNote,
  toHistoryEntry,
  type InvitationRequest,
  type PendingUser,
  type Invite,
  type AdminNote,
  type HistoryEntry,
  type EntityKind,
  type BackendRequest,
  type BackendPendingUser,
  type BackendInvite,
  type BackendAdminNote,
  type BackendHistoryEntry,
} from "@agentic-toolkit/adh-ui/invitations-types";
import { adminInvitationEndpoints } from "@agentic-toolkit/adh-ui/invitations-endpoints";

// Platform-admin endpoint surface (/api/auth/* + /api/system/*).
const E = adminInvitationEndpoints();

// ── Query keys ────────────────────────────────────────────────────────────────

const KEYS = {
  requests: ["auth", "invitation-requests"] as const,
  pending: ["auth", "pending-users"] as const,
  invites: ["auth", "invitations"] as const,
  notes: (subjectTable: string, subjectId: string) =>
    ["system", "admin-notes", subjectTable, subjectId] as const,
  history: (subjectTable: string, subjectId: string) =>
    ["system", "entity-history", subjectTable, subjectId] as const,
};

// ── List hooks ────────────────────────────────────────────────────────────────

export function useInvitationRequests() {
  return useQuery({
    queryKey: KEYS.requests,
    queryFn: async (): Promise<InvitationRequest[]> => {
      const rows = await authedJson<BackendRequest[]>(E.requests);
      return rows.map(toRequest);
    },
  });
}

export function usePendingUsers() {
  return useQuery({
    queryKey: KEYS.pending,
    queryFn: async (): Promise<PendingUser[]> => {
      const rows = await authedJson<BackendPendingUser[]>(E.pendingUsers);
      return rows.map(toPendingUser);
    },
  });
}

export function useInvites() {
  return useQuery({
    queryKey: KEYS.invites,
    queryFn: async (): Promise<Invite[]> => {
      const rows = await authedJson<BackendInvite[]>(E.invitations);
      return rows.map(toInvite);
    },
  });
}

// ── Notes + history hooks ─────────────────────────────────────────────────────

export function useRowNotes(subjectTable: string, subjectId: string) {
  return useQuery({
    queryKey: KEYS.notes(subjectTable, subjectId),
    queryFn: async (): Promise<AdminNote[]> => {
      const rows = await authedJson<BackendAdminNote[]>(E.adminNotes(subjectTable, subjectId));
      return rows.map(toAdminNote);
    },
    enabled: !!subjectId,
  });
}

export function useRowHistory(subjectTable: string, subjectId: string) {
  return useQuery({
    queryKey: KEYS.history(subjectTable, subjectId),
    queryFn: async (): Promise<HistoryEntry[]> => {
      const rows = await authedJson<BackendHistoryEntry[]>(E.entityHistory(subjectTable, subjectId));
      return rows.map(toHistoryEntry);
    },
    enabled: !!subjectId,
  });
}

export function useSaveNotes() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      subjectTable,
      subjectId,
      notes,
    }: {
      subjectTable: string;
      subjectId: string;
      notes: { id?: string; content: string }[];
    }) =>
      authedJson(E.adminNotesPut, {
        method: "PUT",
        body: JSON.stringify({
          subjectTable,
          subjectId,
          notes: notes.map((n) => ({ id: n.id, content: n.content })),
        }),
      }),
    onSuccess: (_data, { subjectTable, subjectId }) => {
      void qc.invalidateQueries({ queryKey: KEYS.notes(subjectTable, subjectId) });
      void qc.invalidateQueries({ queryKey: KEYS.history(subjectTable, subjectId) });
    },
  });
}

// ── Mutation hooks ────────────────────────────────────────────────────────────

export function useSendInvitations() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      pendingUserIds,
      email,
      sms,
    }: {
      pendingUserIds: string[];
      email?: { note?: string };
      sms?: { note?: string };
    }) =>
      authedJson(E.invitations, {
        method: "POST",
        body: JSON.stringify({ pendingUserIds, email, sms }),
      }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: KEYS.pending });
      void qc.invalidateQueries({ queryKey: KEYS.invites });
    },
  });
}

export function useAddPendingUsers() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (users: Array<{ name: string; email?: string; phone?: string; note?: string }>) =>
      authedJson(E.pendingUsers, {
        method: "POST",
        body: JSON.stringify({ users }),
      }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: KEYS.pending });
    },
  });
}

/** Delete one row from a topic. topic = EntityKind mapped to the endpoint. */
export function useDeleteInvitationRow(topic: EntityKind) {
  const qc = useQueryClient();
  const itemUrl =
    topic === "request"
      ? E.requestItem
      : topic === "pending"
        ? E.pendingUserItem
        : E.invitationItem;
  return useMutation({
    mutationFn: (id: string) =>
      authedRequest(itemUrl(id), {
        method: "DELETE",
      }),
    onSuccess: () => {
      if (topic === "request") void qc.invalidateQueries({ queryKey: KEYS.requests });
      else if (topic === "pending") void qc.invalidateQueries({ queryKey: KEYS.pending });
      else void qc.invalidateQueries({ queryKey: KEYS.invites });
    },
  });
}
