"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { authedJson } from "./http";

/**
 * The /system/reserved-identifiers surface: rdids that are held with nothing using them, and the
 * action that gives one back.
 *
 * Types are hand-written rather than generated. `pnpm gen`'s python target is broken on main, so
 * running codegen here would mean shipping an unrelated regeneration of every client; these three
 * shapes are small enough to state, and the backend's `ReservedIdentifier` / `ReleaseResult` are
 * their single source of truth.
 */

/** Why a name is being held. Mirrors `ReservedReason` in backend lib/reserved-identifiers.ts. */
export type ReservedReason = "rename-leftover" | "orphan" | "deleted-entity";

export type ReservedIdentifier = {
  rdid: string;
  entityType: string;
  entityId: string;
  reason: ReservedReason;
  heldSince: string | null;
  /**
   * May this one be released? False for the names the surface can only REPORT — a revoked token's
   * slug, reserved by policy, and legacy reverse-domain handles. Sent per row rather than re-derived
   * here from `entityType`: the policy is the backend's, and a second copy of it in the UI is a copy
   * that goes stale into a button that answers 403.
   */
  releasable: boolean;
};

export type ReservedIdentifierPage = {
  items: ReservedIdentifier[];
  page: number;
  pageSize: number;
  total: number;
  /**
   * SOME HELD NAME IS MISSING FROM `items`. Mirrors `truncated` on the backend's own page type.
   *
   * This list filters in the BROWSER, over whatever the one request returned, so a cap that is
   * not reported turns into the one wrong answer this surface exists to prevent: the operator
   * searches a name, the table comes back empty, and empty here reads as "that name is free".
   * The page renders it as a strip above the table rather than swallowing it.
   */
  truncated: boolean;
};

export type ReleaseResult = {
  rdid: string;
  reason: ReservedReason;
  freed: boolean;
  placeholder?: string;
  aliasesRemoved: number;
  stillHeldBy: string[];
  /** The held names UNDERNEATH this one that the same call freed, deepest first. */
  children: ReleaseResult[];
};

/**
 * The backend's own `LIST_CAP` — the most rows that surface will ever build.
 *
 * Asked for as one page rather than paged through, because the list filters, sorts and selects in
 * the browser and every one of those is a question about the WHOLE population: a type filter over
 * page one answers "which of these twenty-five", which is not what the operator asked. Fetching a
 * slice and then filtering it is the bug, not the saving.
 */
const LIST_PAGE_SIZE = 2000;

const KEYS = {
  list: () => ["system", "reserved-identifiers"] as const,
};

export function useReservedIdentifiers() {
  return useQuery({
    queryKey: KEYS.list(),
    queryFn: (): Promise<ReservedIdentifierPage> => {
      const params = new URLSearchParams({ page: "1", pageSize: String(LIST_PAGE_SIZE) });
      return authedJson<ReservedIdentifierPage>(`/api/system/reserved-identifiers?${params}`);
    },
  });
}

export function useReleaseReservedIdentifier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (item: ReservedIdentifier): Promise<ReleaseResult> =>
      authedJson<ReleaseResult>("/api/system/reserved-identifiers/release", {
        method: "POST",
        body: JSON.stringify({
          rdid: item.rdid,
          entityType: item.entityType,
          entityId: item.entityId,
        }),
      }),
    onSuccess: () => {
      // Every page, not just the current one: releasing an ecosystem re-homes its whole subtree, so
      // rows on other pages change too.
      void qc.invalidateQueries({ queryKey: ["system", "reserved-identifiers"] });
    },
  });
}
