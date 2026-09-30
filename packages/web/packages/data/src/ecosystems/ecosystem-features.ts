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
// `AuthHttpError` only, straight from the auth package rather than re-exported through
// ../http — the same direct-import pattern tenant.ts and stream/index.ts already use for
// functions ../http doesn't re-export. Needed here to read the parsed body a 409
// `feature_required` response carries (see `remove` below); ../http's own helpers
// (`isConflict` etc.) duck-type on `.status` only and drop everything else.
import { AuthHttpError } from "@agentic-toolkit/auth/client";
import { listedCatalog } from "./feature-requirements";

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
  /**
   * Other catalog feature keys that must be provisioned and active before the backend will
   * allow removing THIS feature — e.g. `signin-apps` requires `['users', 'user-authentication',
   * 'feature-flags', 'server-bags']`. Purely informational client-side (the picker can use it to
   * explain a disabled "remove" affordance); the backend is the enforcement point and answers a
   * blocked removal with a 409 (see {@link FeatureRequiredError}).
   */
  requiresFeatures?: readonly string[];
  /**
   * Only a user's or an organization's own ecosystem may hold it (Organizations) — a client
   * ecosystem cannot. Which ecosystems that rules out is the server's call, read per ecosystem
   * through {@link ecosystemFeaturesApi.availability}; this flag is informational.
   */
  ownEcosystemOnly?: boolean;
  /**
   * The feature this one COMES WITH — User Authentication and Email Signup with Users, Storage
   * Access Tokens with Storage, Client Auth with Applications. It is still a feature of its own on
   * the server (its key gates what it gates), but not one the owner picks: the Manage features
   * dialog does not list it ({@link listedCatalog}), adding the parent adds it, and removing the
   * parent removes it. The backend refuses removing it on its own (400).
   */
  includedWith?: string;
}

/** A catalog feature one ecosystem may not add, and the sentence that says why. */
export interface UnavailableFeature {
  key: string;
  reason: string;
}

/**
 * Where a feature got to.
 *
 * `provisioning` is not a transient the client can ignore: provisioning CREATES things,
 * so it can fail partway, and a row left in that state is a feature that is neither on
 * nor safely re-addable-in-silence. So the one list is read two ways, each named below
 * rather than re-filtered by every reader (the filters were copied by hand, and a copy
 * drifts): {@link activeFeatureKeys} for what can be navigated into — the hub's workspace
 * rail, and a product's own Features list, which must not draw a row for a feature that
 * could still fail partway through provisioning — and {@link presentFeatureKeys} for what
 * the ecosystem HAS — the Manage-features picker only, which shows `provisioning` as
 * already-taken so the owner cannot queue it twice (Mike, 2026-09-25).
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
 * Manage-features picker ticks, and only the picker — a product's Features list reads
 * {@link activeFeatureKeys} instead, since a still-provisioning feature is not yet safe to
 * navigate into (Mike, 2026-09-25).
 */
export function presentFeatureKeys(rows: readonly ProvisionedFeature[]): ReadonlySet<string> {
  return new Set(rows.filter((f) => f.state !== "removed").map((f) => f.featureKey));
}

/**
 * The keys an ecosystem can be NAVIGATED into: `active` rows only. A `provisioning` feature can
 * have stopped partway, so a row for it could open onto a pane whose storage is not there. Read
 * by the hub's workspace rail and by a product's own Features list ({@link heldTopics}) — a rail
 * or topic list shows only what is actually there to open (Mike, 2026-09-25).
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
interface AvailabilityResponse {
  unavailable: UnavailableFeature[];
}

const BASE = "/api/ecosystem/features";

/**
 * Thrown by {@link ecosystemFeaturesApi.remove} in place of a generic {@link AuthHttpError} when
 * the backend refuses the removal (409) because another active feature still needs this one —
 * `ecosystemFeatures.ts`'s `{ error: { code: "feature_required", message, neededBy } }` body.
 * `neededBy` is the blocking features' keys, so the caller can name them (the backend's own
 * `message` already spells out their labels, and is kept as this error's `message`).
 */
export class FeatureRequiredError extends Error {
  constructor(
    message: string,
    readonly neededBy: string[],
    /**
     * Other keys that ALSO failed to remove in the same batch (`useApplyFeatureChange`'s
     * `Promise.allSettled`) — never this error's own key. Empty when this was the only
     * failure. Keys, not full errors: the caller already knows how to name a key (the
     * picker's own `labelOf`), and this file must not take on the ecosystem's presentation.
     * Exists so a second, unrelated removal failure in the same batch is never silently
     * dropped just because the first one happened to be feature-required.
     */
    readonly otherFailures: string[] = [],
  ) {
    super(message);
    this.name = "FeatureRequiredError";
  }
}

/** `err` maps to a {@link FeatureRequiredError} when it is a 409 carrying the backend's
 *  `feature_required` body; otherwise null, so the caller rethrows unchanged. */
function asFeatureRequiredError(err: unknown): FeatureRequiredError | null {
  if (!(err instanceof AuthHttpError) || err.status !== 409) return null;
  const body = err.body as { error?: { code?: unknown; neededBy?: unknown } } | null | undefined;
  const neededBy = body?.error?.neededBy;
  if (body?.error?.code !== "feature_required" || !Array.isArray(neededBy)) return null;
  return new FeatureRequiredError(err.message, neededBy as string[]);
}

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
   * The catalog features THIS ecosystem may not add, and why — a client ecosystem cannot hold
   * Organizations. The backend refuses the same list on `provision`, so a picker that disables
   * exactly these never offers a change that would 400.
   */
  async availability(ecosystemId: string): Promise<UnavailableFeature[]> {
    const body = await authedJson<AvailabilityResponse>(`${BASE}/${enc(ecosystemId)}/availability`);
    return body.unavailable;
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
   *
   * A 409 because another active feature still needs this one is rethrown as a typed
   * {@link FeatureRequiredError} rather than the generic `AuthHttpError` — see
   * `asFeatureRequiredError`.
   */
  async remove(ecosystemId: string, featureKey: string): Promise<void> {
    try {
      await authedRequest(`${BASE}/${enc(ecosystemId)}/${enc(featureKey)}`, { method: "DELETE" });
    } catch (err) {
      if (isNotFound(err)) return;
      throw asFeatureRequiredError(err) ?? err;
    }
  },
};

// ── Query keys ────────────────────────────────────────────────────────────────

/** The catalog is a property of the server build, not of any ecosystem — see `useFeatureCatalog`. */
const CATALOG_STALE_MS = 30 * 60 * 1000;

const KEYS = {
  catalog: ["eco-features", "catalog"] as const,
  provisioned: (ecosystemId: string) => ["eco-features", ecosystemId] as const,
  availability: (ecosystemId: string) => ["eco-features", ecosystemId, "availability"] as const,
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
    staleTime: CATALOG_STALE_MS,
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
 * What `ecosystemId` may not add. A property of what the ecosystem IS (whose own ecosystem, or a
 * client's), not of what it holds, so it is cached as long as the catalog and never invalidated
 * by a provision or a removal. Disabled until there is an id to ask about.
 */
export function useFeatureAvailability(ecosystemId: string | null | undefined) {
  return useQuery({
    queryKey: KEYS.availability(ecosystemId ?? ""),
    queryFn: () => ecosystemFeaturesApi.availability(ecosystemId as string),
    enabled: Boolean(ecosystemId),
    staleTime: CATALOG_STALE_MS,
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
 * Order a batch of removals DEPENDENTS FIRST, as levels: every key in a level is required by
 * nothing in a LATER level, so sending each level only after the one before it has settled means
 * a key is never DELETEd while another key of the same batch that requires it is still active —
 * the backend refuses exactly that with a 409 `feature_required`. Requirements are the catalog's
 * `requiresFeatures`, followed transitively (A → B → C still orders A before C when B is not in
 * the batch). Keys within one level do not depend on each other and may go in parallel.
 *
 * Pure. Keys missing from the catalog have no requirements and land in the first level. A cycle
 * (the catalog should never have one) cannot hang this: the transitive walk stops on a `seen`
 * set, and the depth walk stops on the keys it is already visiting.
 */
export function removalLevels(remove: readonly string[], catalog: readonly CatalogFeature[]): string[][] {
  const byKey = new Map(catalog.map((f) => [f.key, f] as const));
  const requires = (key: string): Set<string> => {
    const seen = new Set<string>();
    const walk = (k: string): void => {
      for (const dep of byKey.get(k)?.requiresFeatures ?? []) {
        if (seen.has(dep)) continue;
        seen.add(dep);
        walk(dep);
      }
    };
    walk(key);
    return seen;
  };
  const batch = [...new Set(remove)];
  const closure = new Map(batch.map((k) => [k, requires(k)] as const));
  // depth(k) = 1 + the deepest batch key that requires k; 0 when nothing in the batch does.
  const depth = new Map<string, number>();
  const depthOf = (key: string, visiting: Set<string>): number => {
    const known = depth.get(key);
    if (known !== undefined) return known;
    if (visiting.has(key)) return 0;
    visiting.add(key);
    let d = 0;
    for (const other of batch) {
      if (other !== key && closure.get(other)?.has(key)) d = Math.max(d, depthOf(other, visiting) + 1);
    }
    visiting.delete(key);
    depth.set(key, d);
    return d;
  };
  const levels: string[][] = [];
  for (const key of batch) {
    const d = depthOf(key, new Set());
    (levels[d] ??= []).push(key);
  }
  return levels.filter((level) => level.length > 0);
}

/**
 * Apply one picker visit: the adds as a single POST (one transaction, see `provision`), then one
 * DELETE per removal. Removals go DEPENDENTS FIRST, level by level ({@link removalLevels}, from
 * the catalog's `requiresFeatures`): removing Client Auth and Users together sends Client Auth,
 * lets it settle, then sends Users — otherwise Users could land first and draw a 409. Within a
 * level the DELETEs run in parallel via `Promise.allSettled`, and every level runs whatever the
 * one before it did — one removal's failure (a 404 is already success, see `remove`, but a real
 * 5xx isn't) must not abort the rest silently the way a sequential `for … await` would. Any
 * removals that did fail are named in a thrown error so the caller can surface which keys are
 * still provisioned.
 *
 * The catalog is the cached one the picker already read (`useFeatureCatalog`'s key), fetched only
 * when it is not cached. If it cannot be read the removals go as ONE parallel level, as before:
 * the order is a courtesy, the backend's 409 is the enforcement, and a dependency failure still
 * surfaces as a {@link FeatureRequiredError}.
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
      let levels: string[][] = [remove];
      if (remove.length > 1) {
        try {
          const catalog = await qc.fetchQuery({
            queryKey: KEYS.catalog,
            queryFn: () => ecosystemFeaturesApi.catalog(),
            staleTime: CATALOG_STALE_MS,
          });
          // The picker removes LISTED keys, and a listed key's requirements include those of
          // the features that come with it (Applications brings Client Auth, which needs Users) —
          // so order over the listed catalog, or Applications and Users would go in parallel.
          levels = removalLevels(remove, listedCatalog(catalog));
        } catch {
          // Unordered is still correct, only less polite — see the doc above.
        }
      }
      const settled = new Map<string, PromiseSettledResult<void>>();
      for (const level of levels) {
        const outcomes = await Promise.allSettled(level.map((key) => ecosystemFeaturesApi.remove(id, key)));
        level.forEach((key, i) => settled.set(key, outcomes[i] as PromiseSettledResult<void>));
      }
      // Back in the caller's order, so the reporting below reads exactly as it always has.
      const results = remove.map((key) => settled.get(key) as PromiseSettledResult<void>);
      const failed = remove.filter((_, i) => results[i]?.status === "rejected");
      if (failed.length > 0) {
        // A FeatureRequiredError is a race with another session (it added something between the
        // picker's confirm and this DELETE landing) that the caller can explain by name — rethrow
        // it (as a NEW instance, `otherFailures` filled in) rather than folding it into the
        // generic message below, which would read as a plain failure instead of the reason the
        // removal is now blocked. Any OTHER key that failed in the same batch — another
        // FeatureRequiredError or a plain one — must still be named on the error that wins: the
        // old code threw only the first FeatureRequiredError it found and dropped every other
        // failure on the floor.
        const requiredIndex = results.findIndex(
          (r): r is PromiseRejectedResult => r.status === "rejected" && r.reason instanceof FeatureRequiredError,
        );
        if (requiredIndex !== -1) {
          const required = (results[requiredIndex] as PromiseRejectedResult).reason as FeatureRequiredError;
          const otherFailures = remove.filter(
            (_, i) => i !== requiredIndex && results[i]?.status === "rejected",
          );
          throw new FeatureRequiredError(required.message, required.neededBy, otherFailures);
        }
        throw new Error(`Couldn't remove: ${failed.join(", ")}`);
      }
    },
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: KEYS.provisioned(ecosystemId ?? "") });
    },
  });
}
