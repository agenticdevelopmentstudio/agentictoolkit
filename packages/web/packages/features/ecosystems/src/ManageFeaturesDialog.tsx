"use client";

import { useMemo, type ReactElement } from "react";
import {
  useFeatureCatalog,
  useApplyFeatureChange,
  useProvisionedFeatures,
  type ProvisionedFeature,
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
 * `alreadyProvisioned` counts `provisioning` as present — unlike the hub's rail, which draws only
 * `active`. The two answer different questions: the rail asks "can I navigate there yet", the
 * picker asks "is this in the ecosystem", and a feature still being built is.
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
    () =>
      new Set<string>(
        (provisioned.data ?? [])
          .filter((f: ProvisionedFeature) => f.state !== "removed")
          .map((f: ProvisionedFeature) => f.featureKey),
      ),
    [provisioned.data],
  );

  return (
    <FeaturePickerDialog
      open
      catalog={catalog.data ?? []}
      alreadyProvisioned={alreadyProvisioned}
      busy={apply.isPending || catalog.isPending || provisioned.isPending}
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
