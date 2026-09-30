"use client";

// The feature manager: the ONE place that answers "what does this ecosystem hold, what is each
// feature called, and is this row drawn" — for every surface that shows an ecosystem's features.
//
// The rails (the hub's workspace rail, a product's Features list and the groups inside it) and the
// Manage features dialog used to answer those questions each for themselves: the dialog from the
// provisioned rows, the rails from hand-kept lists — rows with no feature behind them (Messaging,
// Dashboards), group members drawn whatever the ecosystem held, a "Customers" row for a feature
// that is Users, labels copied beside the catalog's ("Sign-in apps" for Client Auth), and a rail
// row for any feature the URL happened to name. Each list agreed with the dialog until it didn't
// (Mike, 2026-09-29). So the rule lives here, once:
//
//   A row that stands on catalog features is drawn only while the ecosystem holds one of them —
//   `present` in the dialog's own sense. The dialog ticks exactly `present`, so anything a rail
//   draws is ticked in the dialog, by construction rather than by keeping two lists level.
//
// A new ecosystem holds nothing, so every feature row is hidden until the owner adds one.
//
// It is also the one answer to "may this ecosystem add that, and what comes with it": the
// dialog asks {@link EcosystemFeatureManager.unavailable} which features to disable (not built
// yet, or not for this kind of ecosystem — a client ecosystem cannot hold Organizations), and
// reads requirements through the same module ({@link requiredClosure}, {@link neededBy}).

import { useCallback, useMemo } from "react";
import {
  activeFeatureKeys,
  presentFeatureKeys,
  useApplyFeatureChange,
  useFeatureAvailability,
  useFeatureCatalog,
  useProvisionedFeatures,
  type CatalogFeature,
  type ProvisionedFeature,
} from "./ecosystem-features";
import { listedCatalog, listedFeatureKey, neededBy, requiredClosure } from "./feature-requirements";

/** What an ecosystem holds, read every way a surface needs it — derived from one list. */
export interface FeatureHoldings {
  /** Every key but `removed`: what the Manage features dialog ticks. */
  present: ReadonlySet<string>;
  /** Finished provisioning: safe to navigate into. */
  active: ReadonlySet<string>;
  /** Held but still being built: drawn and ticked, never opened onto. */
  provisioning: ReadonlySet<string>;
  /** Taken off by the owner. Not held. */
  removed: ReadonlySet<string>;
}

export function featureHoldings(rows: readonly ProvisionedFeature[]): FeatureHoldings {
  const keysIn = (state: ProvisionedFeature["state"]) =>
    new Set(rows.filter((f) => f.state === state).map((f) => f.featureKey));
  return {
    present: presentFeatureKeys(rows),
    active: activeFeatureKeys(rows),
    provisioning: keysIn("provisioning"),
    removed: keysIn("removed"),
  };
}

/**
 * How a row standing on `features` is drawn:
 *  - `active` — at least one of its features is active: drawn, and opens.
 *  - `provisioning` — held, but none active yet: drawn and marked, never opened onto.
 *  - `hidden` — the ecosystem holds none of them: not drawn.
 *
 * `features === undefined` is a STRUCTURAL row — Settings, Child Ecosystems, a feature site's own
 * rows — which no feature stands behind and which is always drawn. A row that stands for a feature
 * must name it: leaving `features` off is what drew Messaging and Dashboards on every new product.
 */
export type FeatureRowState = "active" | "provisioning" | "hidden";

export function featureRowState(
  features: readonly string[] | undefined,
  holdings: FeatureHoldings,
): FeatureRowState {
  if (features === undefined) return "active";
  if (features.some((k) => holdings.active.has(k))) return "active";
  if (features.some((k) => holdings.provisioning.has(k))) return "provisioning";
  return "hidden";
}

/**
 * The name a row standing on `features` is drawn with: the catalog's label when the row IS one
 * feature, else `fallback`. The rail and the dialog are two views of one list, so a feature is
 * called what the dialog calls it — the backend's catalog label, never a copy that drifts from it.
 * A row covering several features (Gaming: gaming + gamification) or none keeps its own name.
 */
export function featureRowLabel(
  features: readonly string[] | undefined,
  fallback: string,
  catalog: readonly Pick<CatalogFeature, "key" | "label">[] | undefined,
): string {
  if (features?.length !== 1) return fallback;
  return catalog?.find((f) => f.key === features[0])?.label ?? fallback;
}

/**
 * Why `feature` cannot be ADDED to this ecosystem, or `undefined` when it can. One the ecosystem
 * already holds is never unavailable: the dialog is the only way to take a feature off, so its
 * tick must stay live for unticking. `unavailable` is the server's per-ecosystem list.
 */
export function featureUnavailableReason(
  feature: Pick<CatalogFeature, "key" | "comingSoon">,
  holdings: Pick<FeatureHoldings, "present"> | undefined,
  unavailable: ReadonlyMap<string, string> | undefined,
): string | undefined {
  if (holdings?.present.has(feature.key)) return undefined;
  if (feature.comingSoon) return "Coming soon.";
  return unavailable?.get(feature.key);
}

/**
 * The features that come with `key` when it is added: `key` itself, then its requirements
 * transitively — minus any this ecosystem cannot add, which the backend would refuse.
 */
export function featuresAddedWith(
  key: string,
  catalog: readonly CatalogFeature[],
  cannotAdd: (key: string) => boolean,
): string[] {
  return [key, ...requiredClosure(key, catalog)].filter((k) => !cannotAdd(k));
}

export interface EcosystemFeatureManager {
  /** The catalog: every feature that can be added. */
  catalog: ReturnType<typeof useFeatureCatalog>;
  /** The catalog as the Manage features dialog lists it ({@link listedCatalog}): no feature that
   *  comes with another. `undefined` until the catalog lands. */
  listed: CatalogFeature[] | undefined;
  /** The listed feature a key stands under — itself, or the one it comes with. */
  listedKeyOf: (key: string) => string;
  /** The raw provisioned read, for surfaces that report its loading and error states. */
  provisioned: ReturnType<typeof useProvisionedFeatures>;
  /** What the ecosystem holds; `undefined` until the first read lands. */
  holdings: FeatureHoldings | undefined;
  /** The catalog label for `key`, else `fallback`, else the key itself. */
  labelOf: (key: string, fallback?: string) => string;
  /** The one way to change what the ecosystem holds. */
  apply: ReturnType<typeof useApplyFeatureChange>;
  /** Key → why this ecosystem may not add it (server-decided). Empty until the read lands. */
  unavailable: ReadonlyMap<string, string>;
  /** The raw availability read, for surfaces that wait on it. */
  availability: ReturnType<typeof useFeatureAvailability>;
  /** The currently-ON listed features that need `key` — what blocks taking it off. */
  neededBy: (key: string, isOn: (key: string) => boolean) => CatalogFeature[];
}

/**
 * One ecosystem's features, for any surface: the rails read `holdings` (through
 * {@link featureRowState}) and `labelOf`, the Manage features dialog reads the same `holdings`
 * and changes them through `apply`. Every reader shares one react-query cache entry per ecosystem,
 * so an apply redraws every surface on the same tick.
 */
export function useEcosystemFeatures(ecosystemId: string | null | undefined): EcosystemFeatureManager {
  const catalog = useFeatureCatalog();
  const provisioned = useProvisionedFeatures(ecosystemId);
  const apply = useApplyFeatureChange(ecosystemId);
  const availability = useFeatureAvailability(ecosystemId);
  const unavailable = useMemo(
    () => new Map((availability.data ?? []).map((f) => [f.key, f.reason] as const)),
    [availability.data],
  );
  const listed = useMemo(() => (catalog.data ? listedCatalog(catalog.data) : undefined), [catalog.data]);
  const listedKeyOf = useCallback(
    (key: string) => listedFeatureKey(key, catalog.data ?? []),
    [catalog.data],
  );
  const neededByKey = useCallback(
    (key: string, isOn: (key: string) => boolean) => neededBy(listedKeyOf(key), listed ?? [], isOn),
    [listed, listedKeyOf],
  );
  const holdings = useMemo(
    () => (provisioned.data === undefined ? undefined : featureHoldings(provisioned.data)),
    [provisioned.data],
  );
  const labels = useMemo(
    () => new Map((catalog.data ?? []).map((f) => [f.key, f.label] as const)),
    [catalog.data],
  );
  const labelOf = useCallback(
    (key: string, fallback?: string) => labels.get(key) ?? fallback ?? key,
    [labels],
  );
  return {
    catalog,
    listed,
    listedKeyOf,
    provisioned,
    holdings,
    labelOf,
    apply,
    unavailable,
    availability,
    neededBy: neededByKey,
  };
}
