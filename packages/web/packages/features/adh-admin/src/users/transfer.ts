"use client";

import { useQuery } from "@tanstack/react-query";
import { authedJson } from "../api/http";

/** One thing that would collide if this user moved — see backend provisioning/customer-transfer.ts. */
export interface TransferConflict {
  userId: string;
  constraint: string;
  detail: string;
}

/**
 * What the whole selection would hit, asked BEFORE any of it moves.
 *
 * The endpoint existed from the start and nothing called it, which made the preflight dead code
 * and left the operator learning about a collision the only other way there is: a batch that stops
 * three users in with the first three already committed. The moves that succeeded cannot be
 * undone, so "find out first" is the only cheap moment there is.
 *
 * Keyed by the target and the exact selection, and `enabled` only while the confirmation dialog is
 * open — the ids come from a selection that changes as the operator ticks boxes, and asking on
 * every tick would be a request per checkbox.
 */
export function useTransferPreview(userIds: string[], target: string | null, enabled: boolean) {
  const ids = [...userIds].sort();
  const key = ids.join(",");
  return useQuery({
    queryKey: ["admin", "transfer-preview", target, key],
    enabled: enabled && target !== null && ids.length > 0,
    // The answer is about rows that are about to be rewritten; a cached one from a minute ago is
    // about a different database.
    staleTime: 0,
    queryFn: async (): Promise<TransferConflict[]> => {
      const params = new URLSearchParams({ userIds: key, target: target! });
      const body = await authedJson<{ target: string; conflicts: TransferConflict[] }>(
        `/api/customer/transfer/preview?${params}`,
      );
      return body.conflicts;
    },
  });
}

/**
 * Move ONE user to another ecosystem. Its own transaction on the server, which is why a batch of
 * them is run one at a time by `useBatchRun` rather than fired together — see that hook for the
 * sequencing and halting argument that used to live in this file.
 */
export const transferUser = (userId: string, target: string): Promise<unknown> =>
  authedJson("/api/customer/transfer", {
    method: "POST",
    body: JSON.stringify({ userId, target }),
  });
