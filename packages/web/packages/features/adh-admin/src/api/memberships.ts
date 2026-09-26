"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { authedJson, authedRequest } from "./http";
import type { RdidMapping } from "./admin";

/**
 * /customer/memberships — which ecosystems a person is a customer of, and the two admin actions
 * that change it.
 *
 * A person is not one row: `customer.customers` is per-ecosystem, and the same human has one row
 * per ecosystem joined by email (the backend route's header states the rule). So the Users page's
 * Ecosystems column is a SET, an "add to ecosystem" adds a row rather than moving one, and the
 * trash can on a chip deletes exactly that ecosystem's row and leaves the others alone.
 *
 * Separate from `admin.ts` because it is a different question about the same page: that module
 * answers "who are the hub's users", this one answers "and where else does each of them exist".
 */

/** One ecosystem a person is a customer of. */
export interface UserEcosystem {
  /** The customer row carrying this membership — what a removal deletes. */
  customerId: string;
  ecosystemId: string;
  /** The ecosystem's address, once the registry has answered. Null while unresolved. */
  rdid: string | null;
  /**
   * This is the user's HUB account, not a membership. The backend refuses to remove it (that is
   * "delete the user", a different button with a different confirmation) and the chip therefore
   * carries no trash can — an affordance that always answers 400 is worse than no affordance.
   */
  isHub: boolean;
}

/** One row of `GET /customer/memberships`. */
interface MembershipRow {
  userId: string;
  customerId: string;
  ecosystemId: string;
}

/** Ecosystem zero — see `HUB_ECOSYSTEM_ID` in admin.ts and backend lib/ecosystem.ts. */
const HUB_ECOSYSTEM_ID = "00000000-0000-4000-8000-00000000a001";

/**
 * The backend's own `LOOKUP_MAX_USERS`, and the same chunk `fetchRdids` uses for the same reason:
 * the ids travel in a query string, and Node's default `maxHeaderSize` is 16 KB.
 */
const CHUNK = 200;

/**
 * Every user's ecosystems, keyed by user id, with each ecosystem's address resolved.
 *
 * DEGRADES rather than fails, exactly as the address lookup beside it does: a chunk that errors
 * costs those users their Ecosystems cell, not the whole user list. The rows themselves have
 * already arrived by the time this runs, and reporting the query as failed would take a working
 * page down for a column.
 */
export async function fetchMemberships(userIds: string[]): Promise<Map<string, UserEcosystem[]>> {
  const rows: MembershipRow[] = [];
  for (let i = 0; i < userIds.length; i += CHUNK) {
    const ids = userIds.slice(i, i + CHUNK).join(",");
    try {
      rows.push(
        ...(await authedJson<MembershipRow[]>(
          `/api/customer/memberships?userIds=${encodeURIComponent(ids)}`,
        )),
      );
    } catch (err) {
      console.warn("admin users: membership lookup failed for a chunk of users", err);
    }
  }

  const rdidByEcosystem = await fetchEcosystemRdids([...new Set(rows.map((r) => r.ecosystemId))]);
  const out = new Map<string, UserEcosystem[]>();
  for (const row of rows) {
    const entry: UserEcosystem = {
      customerId: row.customerId,
      ecosystemId: row.ecosystemId,
      rdid: rdidByEcosystem.get(row.ecosystemId) ?? null,
      isHub: row.ecosystemId === HUB_ECOSYSTEM_ID,
    };
    const list = out.get(row.userId);
    if (list) list.push(entry);
    else out.set(row.userId, [entry]);
  }
  // The hub account first, then the rest by address: the chip an operator is looking for is the
  // one that is NOT the hub, and a stable order stops the cell reshuffling between refetches.
  for (const list of out.values()) {
    list.sort((a, b) =>
      a.isHub !== b.isHub ? (a.isHub ? -1 : 1) : (a.rdid ?? "").localeCompare(b.rdid ?? ""),
    );
  }
  return out;
}

/** ecosystem id → rdid, one batched registry lookup rather than one per chip. */
async function fetchEcosystemRdids(ecosystemIds: string[]): Promise<Map<string, string>> {
  const found = new Map<string, string>();
  for (let i = 0; i < ecosystemIds.length; i += CHUNK) {
    const ids = ecosystemIds.slice(i, i + CHUNK).join(",");
    try {
      for (const m of await authedJson<RdidMapping[]>(
        `/api/registry/identifiers?entityType=ecosystem&entityIds=${encodeURIComponent(ids)}`,
      )) {
        found.set(m.entityId, m.rdid);
      }
    } catch (err) {
      console.warn("admin users: ecosystem address lookup failed for a chunk", err);
    }
  }
  return found;
}

/**
 * Make a user a customer of another ecosystem too.
 *
 * IDEMPOTENT at the backend: adding someone who is already a member returns their existing row
 * with `created: false` rather than a constraint violation, so a run over a mixed selection does
 * not have to know in advance which of them were already in.
 */
export function useAddToEcosystem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { userId: string; ecosystemId: string }) =>
      authedJson<{ userId: string; customerId: string; ecosystemId: string; created: boolean }>(
        "/api/customer/memberships",
        { method: "POST", body: JSON.stringify(input) },
      ),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
}

/** Take a user out of ONE ecosystem. Addressed by the membership's own customer row. */
export function useRemoveFromEcosystem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (customerId: string) =>
      authedRequest(`/api/customer/memberships/${encodeURIComponent(customerId)}`, {
        method: "DELETE",
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
}
