"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson } from "./http";

// ── Per-ecosystem offline-sync table enrollment ──────────────────────────────
//
// Admin-only surface over the backend's hand-written `/admin/sync/tables/:id`
// routes (backend/src/adh/src/routes/syncAdmin.ts) — lets platform staff decide,
// per ecosystem, which catalog resources sync offline, overriding each entry's
// code default in the sync registry. `:id` is the ecosystem's rdid OR its raw
// uuid (the route resolves either).
//
// `/admin/sync/tables` is NOT in the OpenAPI surface (@agentic-toolkit/adh-api-types), so
// the row/body shapes are hand-written here (as `AccessAuditEvent` in admin.ts
// does for its undocumented route). The ecosystem picker's list, by contrast,
// comes from the documented generic-CRUD `/ecosystem/ecosystems`, so that one
// stays spec-typed.
//
// Every mutating call (PUT/DELETE) returns the FULL refreshed catalog, so the
// hooks re-seed the query cache from `resp.tables` rather than hand-patching one
// row — the server is the authority on effective/overridden state.

/** One catalog resource's enrollment for an ecosystem (hand-written — see above). */
export interface EnrollmentRow {
  /** Dotted resource id, e.g. "content.feed", "persona_memory.links". */
  resource: string;
  /** 'customer' | 'ecosystem' (SyncScope) — display only. */
  scope: string;
  /** 'generic' | 'route' — display only. */
  pushMode: string;
  /** The code default this ecosystem inherits absent an override. */
  defaultEnabled: boolean;
  /** EFFECTIVE state (override ?? defaultEnabled) — this drives the toggle. */
  enabled: boolean;
  /** True when an explicit per-ecosystem override row exists (badge + reset). */
  overridden: boolean;
}

interface EnrollmentResponse {
  tables: EnrollmentRow[];
}

/** An ecosystem row from generic CRUD `GET /ecosystem/ecosystems` (spec-typed). */
export type EcosystemSummary = SuccessBody<"/ecosystem/ecosystems", "get">[number];

const base = (ecoId: string) => `/api/admin/sync/tables/${encodeURIComponent(ecoId)}`;

// ── Network shaping (mirrors ecosystemFeatureFlagsApi) ───────────────────────
//
// A plain object so the request shaping is unit-testable at the fetch boundary
// (mock `./http`); the hooks below are thin react-query wrappers over it.
export const syncTablesApi = {
  /** The full enrollment catalog for one ecosystem. */
  async get(ecoId: string): Promise<EnrollmentRow[]> {
    const { tables } = await authedJson<EnrollmentResponse>(base(ecoId));
    return tables;
  },

  /** Set (or flip) an explicit override for one resource; returns the refreshed catalog. */
  async setOverride(ecoId: string, resource: string, enabled: boolean): Promise<EnrollmentRow[]> {
    const { tables } = await authedJson<EnrollmentResponse>(
      `${base(ecoId)}/${encodeURIComponent(resource)}`,
      { method: "PUT", body: JSON.stringify({ enabled }) },
    );
    return tables;
  },

  /** Clear a resource's override (revert to the code default); returns the refreshed catalog. */
  async clearOverride(ecoId: string, resource: string): Promise<EnrollmentRow[]> {
    const { tables } = await authedJson<EnrollmentResponse>(
      `${base(ecoId)}/${encodeURIComponent(resource)}`,
      { method: "DELETE" },
    );
    return tables;
  },
};

// ── Pure view-model transform (unit-tested) ──────────────────────────────────

/**
 * The schema a resource belongs to — the part before the first dot.
 *
 * This used to be `groupBySchema`, which split the catalog into one table per schema. The shared
 * editable list took that job over as a facet: grouping is a filter someone else already chose,
 * and a page with nine little tables can neither sort across them nor tell you how many rows
 * matched. One list, one Schema facet, and the operator groups it themselves.
 */
export function schemaOf(row: EnrollmentRow): string {
  // `split` always yields ≥1 element, but noUncheckedIndexedAccess widens [0]
  // to `string | undefined`; a resource is always non-empty so "" never hits.
  return row.resource.split(".")[0] ?? "";
}

// ── Hooks (mirror admin.ts's flags hooks) ────────────────────────────────────

/** Ecosystems for the picker — deleted ones dropped, sorted by name. Admin
 *  bypasses tenant scoping, so this generic-CRUD list returns every ecosystem
 *  (same pattern as useAdminUsers sourcing `/customer/customers`). */
export function useAdminEcosystems() {
  return useQuery({
    queryKey: ["admin", "ecosystems"],
    queryFn: async (): Promise<EcosystemSummary[]> => {
      const rows = await authedJson<EcosystemSummary[]>("/api/ecosystem/ecosystems");
      return rows
        .filter((e) => !e.isDeleted)
        .sort((a, b) => a.name.localeCompare(b.name));
    },
  });
}

const tablesKey = (ecosystemId: string) => ["admin", "sync-tables", ecosystemId] as const;

/** The enrollment catalog for the selected ecosystem (idle until one is chosen). */
export function useSyncTables(ecosystemId: string | undefined) {
  return useQuery({
    queryKey: tablesKey(ecosystemId ?? ""),
    enabled: !!ecosystemId,
    queryFn: () => syncTablesApi.get(ecosystemId!),
  });
}

/** Set/flip a resource's override; re-seeds the catalog cache from the response. */
export function useSetSyncOverride(ecosystemId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ resource, enabled }: { resource: string; enabled: boolean }) =>
      syncTablesApi.setOverride(ecosystemId!, resource, enabled),
    onSuccess: (tables) => {
      if (ecosystemId) qc.setQueryData(tablesKey(ecosystemId), tables);
    },
    // The onSuccess reseed above shows the mutating request's own response instantly,
    // but two overlapping toggles can settle out of order and leave a stale last-writer
    // reseed. Refetch once things settle so the cache reconciles to server truth.
    onSettled: () => {
      if (ecosystemId) void qc.invalidateQueries({ queryKey: tablesKey(ecosystemId) });
    },
  });
}

/** Clear a resource's override (reset to default); re-seeds the catalog cache. */
export function useClearSyncOverride(ecosystemId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (resource: string) => syncTablesApi.clearOverride(ecosystemId!, resource),
    onSuccess: (tables) => {
      if (ecosystemId) qc.setQueryData(tablesKey(ecosystemId), tables);
    },
    // See useSetSyncOverride: reconcile to server truth after overlapping mutations settle.
    onSettled: () => {
      if (ecosystemId) void qc.invalidateQueries({ queryKey: tablesKey(ecosystemId) });
    },
  });
}
