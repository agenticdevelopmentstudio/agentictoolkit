"use client";

import { useMemo, type ReactElement } from "react";
import {
  useFeatureCatalog,
  useApplyFeatureChange,
  useProvisionedFeatures,
  presentFeatureKeys,
  type CatalogFeature,
} from "@agentic-toolkit/data/ecosystems";
import { FeaturePickerDialog } from "./FeaturePickerDialog";

/**
 * The feature picker, wired to one ecosystem: its catalog, what it already holds, and the
 * apply that adds and removes. Unticking a feature removes it (hidden and switched off over
 * REST and MCP, its data kept) behind the picker's own confirm.
 *
 * Rendered only while open, and that is what makes the catalog query lazy: `useFeatureCatalog`
 * has no `enabled` switch, so a host that mounted this unconditionally would fetch the whole
 * catalog on every page load for a dialog most visits never open. It also means every open
 * starts with a fresh `apply` mutation, so a failure from an earlier visit never greets the next.
 *
 * `alreadyProvisioned` counts `provisioning` as present (`presentFeatureKeys`) — unlike the hub's
 * rail, which draws only `active` (`activeFeatureKeys`). The two answer different questions: the
 * rail asks "can I navigate there yet", the picker asks "is this in the ecosystem", and a feature
 * still being built is.
 */
export function ManageFeaturesDialog({
  ecosystemId,
  onClose,
}: {
  /** The ecosystem's rdid or uuid — whatever the host is already addressing it by. */
  ecosystemId: string;
  onClose: () => void;
}): ReactElement {
  const catalog = useFeatureCatalog();
  const provisioned = useProvisionedFeatures(ecosystemId);
  const apply = useApplyFeatureChange(ecosystemId);

  const alreadyProvisioned = useMemo(
    () => presentFeatureKeys(provisioned.data ?? []),
    [provisioned.data],
  );
  // Only once the catalog has arrived: before that every held key is "missing" from it, and the
  // loading list would fill with stand-ins that the real rows then replace.
  const rows = useMemo(
    () => (catalog.data ? withStandIns(catalog.data, alreadyProvisioned) : []),
    [catalog.data, alreadyProvisioned],
  );

  return (
    <FeaturePickerDialog
      open
      catalog={rows}
      alreadyProvisioned={alreadyProvisioned}
      busy={apply.isPending}
      // The READS are `loading`, not `busy`: busy takes away every way out of the dialog (no ×,
      // Escape ignored, the footer only a spinner), and a read has no timeout — a hung or offline
      // one, passed as busy, held the user in here until a reload.
      loading={catalog.isPending || provisioned.isPending}
      catalogError={catalog.isError ? "Couldn't load the list of features." : null}
      error={
        provisioned.isError
          ? "Couldn't load which features are already on."
          : apply.isError
            ? "Failed to change the features. Check the list and try again."
            : null
      }
      onApply={(change) => apply.mutate(change, { onSuccess: onClose })}
      onCancel={onClose}
    />
  );
}

/**
 * The catalog, plus a stand-in row for each feature the ecosystem holds that the catalog does not
 * list. The picker draws its rows from the catalog alone, and it is the only way left to take a
 * feature off — the old features pane, which listed such a key with a Remove of its own, is gone
 * — so a held key with no catalog entry would stay on with no way to switch it off. The backend
 * calls catalog keys permanent and refuses unknown ones, so today this adds nothing; it is for
 * the day a key is dropped all the same.
 */
function withStandIns(
  catalog: CatalogFeature[],
  held: ReadonlySet<string>,
): CatalogFeature[] {
  const listed = new Set(catalog.map((f) => f.key));
  const missing = [...held].filter((key) => !listed.has(key));
  if (missing.length === 0) return catalog;
  return [
    ...catalog,
    ...missing.map((key) => ({
      key,
      label: key,
      description: "No longer offered.",
      // No tier to require: the picker leaves the subscription line off when this is empty.
      subscriptionTier: "",
    })),
  ];
}
