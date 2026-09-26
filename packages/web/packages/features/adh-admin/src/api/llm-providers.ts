"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { RequestBody, SuccessBody, components } from "@agentic-toolkit/adh-api-types";
import { authedJson, authedRequest } from "./http";
import { useWindowedList, type WindowedList } from "./windowed";

// ── LLM provider-template catalog ───────────────────────────────────────────
//
// Admin-gated CRUD (+ a probe endpoint) over `/persona/provider-templates*`.
// GET is public; POST/PUT/DELETE/verify are admin-only (the backend enforces
// this — the admin app just happens to be the only caller today). Not a
// generic-CRUD table: `models` is a nested child list synced declaratively
// (the full desired name set, not a diff) and `connectionSpec` is a typed JSON
// column, so this is a hand-written client like oauth/feature-flags/server-bag.
//
// Types are spec-derived (@agentic-toolkit/adh-api-types) so a backend schema change
// (new field, renamed key, a new providerKind) fails this file's tsc instead
// of drifting silently at runtime.

export type ProviderTemplate = components["schemas"]["ProviderTemplate"];
export type ProviderTemplateModel = components["schemas"]["ProviderTemplateModel"];
export type ProviderConnectionSpec = components["schemas"]["ProviderConnectionSpec"];
export type ProviderTemplateList = SuccessBody<"/persona/provider-templates", "get">;
export type ProviderTemplateVerifyResult = SuccessBody<
  "/persona/provider-templates/{id}/verify",
  "post"
>;

/** Operator-only upstream sync mapping (null when a template never syncs). */
export type TemplateSyncKeys = components["schemas"]["TemplateSyncKeys"];
export type CatalogSyncRun = components["schemas"]["CatalogSyncRun"];
export type CatalogSyncOutcome = components["schemas"]["CatalogSyncOutcome"];
export type SyncStatusResult = SuccessBody<"/persona/provider-templates/sync-status", "get">;
export type RunSyncResult = SuccessBody<"/persona/provider-templates/sync", "post">;
export type TemplateSyncKeysResult = SuccessBody<
  "/persona/provider-templates/{id}/sync-keys",
  "get"
>;

/** The create body: providerKind/name/baseUrl required, the rest optional. */
export type CreateProviderTemplateInput = RequestBody<"/persona/provider-templates", "post">;
/** The update body: every field optional; `models` present = full desired set;
 *  `connectionSpec` object replaces, `null` clears, omitted leaves untouched. */
export type UpdateProviderTemplateInput = RequestBody<
  "/persona/provider-templates/{id}",
  "put"
>;

/**
 * The provider-template catalog as a GROWING WINDOW, in the server's own order.
 *
 * This used to take `q` and `page` and hand them to the server, which set the operator's filter
 * and the pager against each other: a search matched forty templates, the table showed the first
 * twenty, and the rest sat behind a control that reset every time another character was typed.
 * Searching happens in the browser now, over rows already fetched, and the window only ever grows
 * — the route caps a page at 100, so a catalog past that gets a Load-more that APPENDS rather
 * than a pager that exchanges one slice for another.
 */
export function useProviderTemplateWindow(): WindowedList<ProviderTemplate> {
  return useWindowedList<ProviderTemplate>({
    key: ["admin", "llm-providers", "templates"],
    getRowId: (t) => t.id,
    // The route's own MAX_PAGE_SIZE. Asking for more is silently clamped, so this is the largest
    // honest fetch — and most deployments hold the whole catalog in the first one.
    pageSize: 100,
    fetchPage: (page, pageSize) =>
      authedJson<ProviderTemplateList>(
        `/api/persona/provider-templates?page=${page}&pageSize=${pageSize}`,
      ),
  });
}

export function useCreateProviderTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateProviderTemplateInput) =>
      authedJson<ProviderTemplate>("/api/persona/provider-templates", {
        method: "POST",
        body: JSON.stringify(input),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "llm-providers", "templates"] }),
  });
}

export function useUpdateProviderTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, ...input }: UpdateProviderTemplateInput & { id: string }) =>
      authedJson<ProviderTemplate>(`/api/persona/provider-templates/${id}`, {
        method: "PUT",
        body: JSON.stringify(input),
      }),
    // The sync mapping lives in its OWN query (it isn't on the template DTO), so
    // it needs its own invalidation: a PUT can change it, and the app's 30s
    // staleTime would otherwise re-serve the pre-save mapping to a dialog
    // reopened within the window — which the next save would write back.
    onSuccess: (_data, { id }) => {
      qc.invalidateQueries({ queryKey: ["admin", "llm-providers", "templates"] });
      qc.invalidateQueries({ queryKey: syncKeysQueryKey(id) });
    },
  });
}

export function useDeleteProviderTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      authedRequest(`/api/persona/provider-templates/${id}`, { method: "DELETE" }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "llm-providers", "templates"] }),
  });
}

/**
 * Probe a template's live endpoint with a caller-supplied key. The key is used
 * for this one request only — the backend never persists it, and this hook
 * caches nothing (no queryKey, no invalidation): a verify result is a
 * point-in-time probe outcome, not state to keep around.
 */
export function useVerifyProviderTemplate() {
  return useMutation({
    mutationFn: ({
      id,
      apiKey,
      baseUrl,
    }: {
      id: string;
      apiKey: string;
      baseUrl?: string;
    }) =>
      authedJson<ProviderTemplateVerifyResult>(
        `/api/persona/provider-templates/${id}/verify`,
        {
          method: "POST",
          body: JSON.stringify({ apiKey, ...(baseUrl?.trim() ? { baseUrl: baseUrl.trim() } : {}) }),
        },
      ),
  });
}

// ── Catalog sync (admin) ─────────────────────────────────────────────────────
//
// The template catalog is refreshed from upstream sources (models.dev /
// OpenRouter / arena) on a TTL; these hooks expose the operator controls that
// sit alongside the CRUD table — read the last run per source, force a round
// now, and read a single template's operator-only sync-key mapping when editing.

/** Last catalog-sync run per source (admin). */
export function useSyncStatus() {
  return useQuery({
    queryKey: ["llm-sync-status"],
    queryFn: () =>
      authedJson<SyncStatusResult>("/api/persona/provider-templates/sync-status"),
  });
}

/**
 * Force a full catalog-sync round NOW (bypassing the TTL) and return per-source
 * outcomes. Invalidates both the sync-status query and the template list, since
 * a round can upsert/delete synced model rows on the templates it touches.
 */
export function useRunSync() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      authedJson<RunSyncResult>("/api/persona/provider-templates/sync", { method: "POST" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["llm-sync-status"] });
      qc.invalidateQueries({ queryKey: ["admin", "llm-providers", "templates"] });
    },
  });
}

/** Query key for one template's sync mapping — shared with the update mutation,
 *  which must invalidate it (see `useUpdateProviderTemplate`). */
export function syncKeysQueryKey(id: string | null) {
  return ["llm-sync-keys", id] as const;
}

/**
 * A single template's operator-only upstream sync mapping — the public template
 * DTO omits it, so the edit dialog fetches it separately. Enabled only when
 * editing (a real `id`); in create mode there is nothing to fetch.
 */
export function useTemplateSyncKeys(id: string | null) {
  return useQuery({
    queryKey: syncKeysQueryKey(id),
    queryFn: () =>
      authedJson<TemplateSyncKeysResult>(`/api/persona/provider-templates/${id}/sync-keys`),
    enabled: id !== null,
  });
}
