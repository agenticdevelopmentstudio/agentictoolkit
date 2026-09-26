"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { RequestBody, SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson } from "./http";
import { useCreateFlag, useUpdateFlag } from "./admin";

// ── Usage metering: the enforcement switch + the tiers it arms ────────────
//
// The platform meters every authenticated request and every LLM turn, but a cap
// only REFUSES anything when two switches agree: the tier's own `quota_enforced`
// column, and one global kill switch above all of them. This module reads both
// and writes both — the read through the admin-gated `GET /api/usage/enforcement`,
// which also reports the process-level pricing knobs no row can carry.

/** The `system.feature_flags` key holding the global switch. */
// Mirrors ENFORCEMENT_FLAG_KEY in the backend's src/lib/usage/enforcement.ts, which
// isn't importable from the frontend (same reason HUB_ECOSYSTEM_ID is duplicated in
// ./admin.ts). The backend's migration 0158 seeds the row; this constant is only
// needed for the one case where it is absent and the console has to create it.
export const ENFORCEMENT_FLAG_KEY = "usage_enforcement";

/** What the console shows next to the switch, when it has to create the row itself. */
const ENFORCEMENT_FLAG_DESCRIPTION =
  "Master kill switch above every tier's quota_enforced flag: off means usage is recorded but never refused.";

/** The effective switch, the input that decided it, and the pricing knobs. */
export type UsageEnforcement = SuccessBody<"/usage/enforcement", "get">;

export function useUsageEnforcement() {
  return useQuery({
    queryKey: ["admin", "usage", "enforcement"],
    queryFn: () => authedJson<UsageEnforcement>("/api/usage/enforcement"),
  });
}

/**
 * Flip the global switch. There is no `PUT /usage/enforcement`: the switch IS a
 * `system.feature_flags` row, so the write reuses the flag store's own admin CRUD
 * (the hooks the Feature Flags page uses) rather than adding a second write path for
 * one authorization decision. `flagId: null` means the row doesn't exist yet — the
 * only case that needs a POST, and the reason the key is named here at all.
 *
 * Both queries are invalidated: the flag hooks refresh `["admin","flags"]`
 * themselves, and this adds the enforcement read, which is what the page renders.
 */
export function useSetEnforcement() {
  const qc = useQueryClient();
  const createFlag = useCreateFlag();
  const updateFlag = useUpdateFlag();
  return useMutation({
    mutationFn: async ({ flagId, enabled }: { flagId: number | null; enabled: boolean }) => {
      if (flagId === null) {
        await createFlag.mutateAsync({
          key: ENFORCEMENT_FLAG_KEY,
          enabled,
          description: ENFORCEMENT_FLAG_DESCRIPTION,
        });
        return;
      }
      await updateFlag.mutateAsync({ id: flagId, changes: { enabled } });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "usage", "enforcement"] }),
  });
}

// ── Rate-limit tiers ──────────────────────────────────────────────────────
//
// `usage.rate_limit_tiers` through generic CRUD (`catalog` exposure: any signed-in
// caller reads, admins write). One row per tier; principals without an explicit
// `principal_tiers` assignment fall to the `is_default` row.

/** A `usage.rate_limit_tiers` row. */
export type RateLimitTier = SuccessBody<"/usage/rate-limit-tiers", "get">[number];
/** The partial update body (every column optional). */
export type UpdateTierBody = RequestBody<"/usage/rate-limit-tiers/{id}", "put">;

export function useRateLimitTiers() {
  return useQuery({
    queryKey: ["admin", "usage", "tiers"],
    queryFn: () => authedJson<RateLimitTier[]>("/api/usage/rate-limit-tiers"),
  });
}

export function useUpdateRateLimitTier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, changes }: { id: string; changes: UpdateTierBody }) =>
      authedJson<RateLimitTier>(`/api/usage/rate-limit-tiers/${encodeURIComponent(id)}`, {
        method: "PUT",
        body: JSON.stringify(changes),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "usage", "tiers"] }),
  });
}
