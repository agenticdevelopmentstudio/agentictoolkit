"use client";

// The features an ecosystem has been PROVISIONED with — the client for the backend's
// hand-written `/api/ecosystem/features/*` route, plus the react-query glue the picker
// and the rail read.
//
// Routes: /api/ecosystem/features/catalog     every feature that can be added
//         /api/ecosystem/features/{id}        what THIS ecosystem has (GET) / add (POST)
//         /api/ecosystem/features/{id}/{key}  remove one (DELETE)
//
// `{id}` is the ecosystem's rdid or uuid — the same `:id` every other ecosystem-scoped
// route takes, resolved server-side.
//
// NOT generic CRUD, and that is the point: the table is in the backend's SKIP_TABLES
// because adding a row has SIDE EFFECTS — a feature's storage bucket, its child
// ecosystem, its roles are created when the feature is added and at no other time.
// So there is a bespoke route, and this is its only client.
//
// Wire types are hand-written here rather than imported from
// `@agentic-toolkit/adh-api-types`, following `./wire.ts`: this package is portable
// mechanism and must not take on adh product vocabulary.

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { authedJson, authedRequest, isNotFound } from "../http";
import { enc } from "../client-helpers";

// ── Types ─────────────────────────────────────────────────────────────────────

/**
 * The subscription level a feature requires, shown in the picker's details pane as
 * `Subscription Level Required: <tier>`.
 *
 * **A PLACEHOLDER, server-side too.** Nothing enforces it today; every catalog entry
 * is `Free`. Typed as a plain string rather than a union so a tier the backend adds
 * later renders instead of failing to parse — the client displays this value, it never
 * branches on it.
 */
export type FeatureSubscriptionTier = string;

/** One feature the owner can add. Served verbatim from the backend's catalog. */
export interface CatalogFeature {
  /** Stable, permanent. What a provisioned row is keyed by. */
  key: string;
  /** Display name. The picker and the rail alphabetise by this. */
  label: string;
  /** One or two sentences — the picker's details pane. */
  description: string;
  subscriptionTier: FeatureSubscriptionTier;
  /** The feature carries a standalone public site of its own (persona registry, research). */
  featureSite?: boolean;
  /**
   * Not built yet: listed so the owner can see it is coming, never provisionable — the
   * backend refuses it. The picker shows it under "Coming soon" with its checkbox disabled,
   * unless the ecosystem already holds it: that one can still be unticked, because the
   * picker is the only way left to take a feature off.
   */
  comingSoon?: boolean;
}

/**
 * Where a feature got to.
 *
 * `provisioning` is not a transient the client can ignore: provisioning CREATES things,
 * so it can fail partway, and a row left in that state is a feature that is neither on
 * nor safely re-addable-in-silence. So the one list is read two ways, each named below
 * rather than re-filtered by every reader (the filters were copied by hand, and a copy
 * drifts): {@link activeFeatureKeys} for what can be navigated into — the hub's workspace
 * rail — and {@link presentFeatureKeys} for what the ecosystem has — the picker, which
 * shows `provisioning` as already-taken so the owner cannot queue it twice, and a
 * product's Features list, which has to agree with the picker.
 */
export type FeatureState = "provisioning" | "active" | "removed";

export interface ProvisionedFeature {
  featureKey: string;
  state: FeatureState;
  provisionedAt: string;
  provisionedBy: string | null;
  updatedAt: string;
}

/**
 * The keys an ecosystem HAS: every row but `removed`, `provisioning` included — a feature still
 * being built is in the ecosystem, and offering it for adding would queue it twice. What the
 * picker ticks and what a product's Features list draws rows for: one rule, so the two agree.
 */
export function presentFeatureKeys(rows: readonly ProvisionedFeature[]): ReadonlySet<string> {
  return new Set(rows.filter((f) => f.state !== "removed").map((f) => f.featureKey));
}

/**
 * The keys an ecosystem can be NAVIGATED into: `active` rows only. A `provisioning` feature can
 * have stopped partway, so a row for it could open onto a pane whose storage is not there.
 */
export function activeFeatureKeys(rows: readonly ProvisionedFeature[]): ReadonlySet<string> {
  return new Set(rows.filter((f) => f.state === "active").map((f) => f.featureKey));
}

/** One visit to the picker, applied: features to add, and provisioned features to remove. */
export interface FeatureChange {
  add: string[];
  remove: string[];
}

interface CatalogResponse {
  features: CatalogFeature[];
}
interface ProvisionedResponse {
  features: ProvisionedFeature[];
}

const BASE = "/api/ecosystem/features";

// ── Client ────────────────────────────────────────────────────────────────────

export const ecosystemFeaturesApi = {
  /** Every feature that can be added, in the backend's own order. */
  async catalog(): Promise<CatalogFeature[]> {
    const body = await authedJson<CatalogResponse>(`${BASE}/catalog`);
    return body.features;
  },

  /** What this ecosystem has, every state included — callers filter. */
  async list(ecosystemId: string): Promise<ProvisionedFeature[]> {
    const body = await authedJson<ProvisionedResponse>(`${BASE}/${enc(ecosystemId)}`);
    return body.features;
  },

  /**
   * Add features. PLURAL and one request on purpose: the picker adds a batch behind a
   * single "Add N features?" confirmation, the backend runs the whole batch in one
   * transaction, and a partial failure rolls back whole — so the owner never ends up
   * with three of five and no way to tell which three.
   *
   * Returns the ecosystem's FULL list afterwards, which is what the caller needs to
   * re-render and saves a second round trip. A key that is already active is a no-op,
   * not a conflict: the picker can legitimately be holding a stale list.
   */
  async provision(ecosystemId: string, keys: string[]): Promise<ProvisionedFeature[]> {
    const body = await authedJson<ProvisionedResponse>(`${BASE}/${enc(ecosystemId)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ keys }),
    });
    return body.features;
  },

  /**
   * Remove one feature. Marks it removed; the data it provisioned is left alone.
   *
   * A 404 is treated as success: the row is already gone, which is the caller's goal
   * either way. Without this, a double-click, a stale list, or a second tab racing the
   * same removal reports failure for an outcome that already happened.
   */
  async remove(ecosystemId: string, featureKey: string): Promise<void> {
    try {
      await authedRequest(`${BASE}/${enc(ecosystemId)}/${enc(featureKey)}`, { method: "DELETE" });
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  },
};

// ── Query keys ────────────────────────────────────────────────────────────────

const KEYS = {
  catalog: ["eco-features", "catalog"] as const,
  provisioned: (ecosystemId: string) => ["eco-features", ecosystemId] as const,
};

// ── Hooks ─────────────────────────────────────────────────────────────────────

/**
 * The catalog. One list for the whole session, shared by every ecosystem: it is a
 * property of the SERVER BUILD, not of any ecosystem, so it is cached without an id in
 * the key and given a long stale time — re-fetching it per picker open would refetch
 * the same 35 rows every time.
 */
export function useFeatureCatalog() {
  return useQuery({
    queryKey: KEYS.catalog,
    queryFn: () => ecosystemFeaturesApi.catalog(),
    staleTime: 30 * 60 * 1000,
  });
}

/** What `ecosystemId` is provisioned with. Disabled until there is an id to ask about. */
export function useProvisionedFeatures(ecosystemId: string | null | undefined) {
  return useQuery({
    queryKey: KEYS.provisioned(ecosystemId ?? ""),
    queryFn: () => ecosystemFeaturesApi.list(ecosystemId as string),
    enabled: Boolean(ecosystemId),
  });
}

/**
 * Add a batch. Writes the response straight into the provisioned query's cache rather
 * than only invalidating it: the POST already returns the full post-add list, so the
 * rail can redraw on the same tick the dialog closes instead of flickering through a
 * refetch. The invalidate still follows, to pick up anything a concurrent session did.
 */
export function useProvisionFeatures(ecosystemId: string | null | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (keys: string[]) => ecosystemFeaturesApi.provision(ecosystemId as string, keys),
    onSuccess: (features) => {
      qc.setQueryData(KEYS.provisioned(ecosystemId ?? ""), features);
      void qc.invalidateQueries({ queryKey: KEYS.provisioned(ecosystemId ?? "") });
    },
  });
}

/** Remove one. DELETE returns no list, so this one can only invalidate. */
export function useRemoveFeature(ecosystemId: string | null | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (featureKey: string) =>
      ecosystemFeaturesApi.remove(ecosystemId as string, featureKey),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: KEYS.provisioned(ecosystemId ?? "") });
    },
  });
}

/**
 * Apply one picker visit: the adds as a single POST (one transaction, see `provision`), then one
 * DELETE per removal, in parallel via `Promise.allSettled` — one removal's failure (a 404 is
 * already success, see `remove`, but a real 5xx isn't) must not abort the rest silently the way a
 * sequential `for … await` would. Any removals that did fail are named in a thrown error so the
 * caller can surface which keys are still provisioned.
 *
 * Adds go first so a failed removal never costs the owner the features they just added. The list
 * is invalidated whatever happened, since a failure partway still changed some of it.
 */
export function useApplyFeatureChange(ecosystemId: string | null | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ add, remove }: FeatureChange) => {
      const id = ecosystemId as string;
      if (add.length > 0) await ecosystemFeaturesApi.provision(id, add);
      const results = await Promise.allSettled(
        remove.map((key) => ecosystemFeaturesApi.remove(id, key)),
      );
      const failed = remove.filter((_, i) => results[i]?.status === "rejected");
      if (failed.length > 0) {
        throw new Error(`Couldn't remove: ${failed.join(", ")}`);
      }
    },
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: KEYS.provisioned(ecosystemId ?? "") });
    },
  });
}
