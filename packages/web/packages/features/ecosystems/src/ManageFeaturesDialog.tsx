"use client";

import { useMemo, type ReactElement } from "react";
import {
  useEcosystemFeatures,
  neededByMessage,
  FeatureRequiredError,
  type CatalogFeature,
} from "@agentic-toolkit/data/ecosystems";
import { FeaturePickerDialog } from "./FeaturePickerDialog";

/**
 * The feature picker, wired to one ecosystem through the feature manager
 * (`useEcosystemFeatures`) — the same holdings the rails draw from, so whatever a rail shows is
 * ticked here — plus what this ecosystem may not add, and the apply that adds and removes. Unticking a feature removes it (hidden and switched off over
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
  const { catalog, listed, listedKeyOf, provisioned, holdings, apply, unavailable } =
    useEcosystemFeatures(ecosystemId);

  const alreadyProvisioned = useMemo(() => holdings?.present ?? new Set<string>(), [holdings]);
  // Held but not yet finished — badged in the picker, so a feature stuck in `provisioning` is not
  // just a ticked box that looks exactly like one that works.
  const stillProvisioning = useMemo(() => holdings?.provisioning ?? new Set<string>(), [holdings]);
  // No BASELINE: what the ecosystem holds has never been read. Pending and failed alike — a failed
  // first read used to fall through to `alreadyProvisioned = ∅` with the ticks live, so every held
  // feature looked absent and Apply would queue it again. A failed REFRESH keeps its last answer,
  // and that answer is still a baseline.
  const noBaseline = provisioned.data === undefined;
  // Only once the catalog has arrived: before that every held key is "missing" from it, and the
  // loading list would fill with stand-ins that the real rows then replace. The rows are the LISTED
  // catalog — a feature that comes with another (User Authentication with Users, Client Auth with
  // Applications) is not the owner's to pick, so it has no row; it is on while its parent is.
  const rows = useMemo(
    () => (catalog.data && listed ? withStandIns(listed, catalog.data, alreadyProvisioned) : []),
    [catalog.data, listed, alreadyProvisioned],
  );

  // A race with another session: it added something, between the picker's own confirm and this
  // DELETE landing, that now needs the key being removed. The picker already refuses this in-dialog
  // (`FeaturePickerDialog`'s own `neededBy` check) — this is the same refusal from the backend
  // instead, for the window the picker cannot see, so it gets the SAME copy rather than the generic
  // apply failure below.
  // The backend names blockers by their own keys, which may be one that comes with another (Client
  // Auth); the owner knows it by the row it comes with (Applications).
  const blockerLabels = (keys: readonly string[]) => [
    ...new Set(
      keys.map((key) => {
        const shown = listedKeyOf(key);
        return catalog.data?.find((f) => f.key === shown)?.label ?? shown;
      }),
    ),
  ];
  const requiredError =
    apply.error instanceof FeatureRequiredError
      ? neededByMessage(blockerLabels(apply.error.neededBy)) +
        // Some OTHER removal in the same batch also failed — a second FeatureRequiredError, or a
        // plain one. This dialog is the last place that failure could still be surfaced (the
        // typed error keeps only keys, not enough to phrase each one individually), so a count
        // it is, rather than dropping it now that the race already has the one error slot.
        (apply.error.otherFailures.length > 0
          ? ` (and ${apply.error.otherFailures.length} other ${apply.error.otherFailures.length === 1 ? "removal" : "removals"} failed)`
          : "")
      : null;

  return (
    <FeaturePickerDialog
      open
      catalog={rows}
      alreadyProvisioned={alreadyProvisioned}
      busy={apply.isPending}
      // The READS are `loading`, not `busy`: busy takes away every way out of the dialog (no ×,
      // Escape ignored, the footer only a spinner), and a read has no timeout — a hung or offline
      // one, passed as busy, held the user in here until a reload.
      // `noBaseline`, not `isPending`, is what keeps the ticks and Apply waiting: a failed first
      // read is no longer pending, and a change computed against no baseline is wrong.
      loading={catalog.isPending || noBaseline}
      catalogError={catalog.isError ? "Couldn't load the list of features." : null}
      provisioning={stillProvisioning}
      unavailable={unavailable}
      // Both, each in its own slot: a failed read and a failed apply are two different problems,
      // and one slot for the pair hid the apply failure behind the read failure.
      loadError={
        provisioned.isError
          ? noBaseline
            ? "Couldn't load which features are already on, so nothing can be changed yet. Close and try again."
            : "Couldn't refresh which features are already on — the ticks show the last list that loaded."
          : null
      }
      error={requiredError ?? (apply.isError ? "Failed to change the features. Check the list and try again." : null)}
      onApply={(change) => apply.mutate(change, { onSuccess: onClose })}
      onCancel={onClose}
    />
  );
}

/**
 * The listed catalog, plus a stand-in row for each feature the ecosystem holds that the catalog
 * does not know at all (a key that only comes with another is known: it is not a stand-in). The picker draws its rows from the catalog alone, and it is the only way left to take a
 * feature off — the old features pane, which listed such a key with a Remove of its own, is gone
 * — so a held key with no catalog entry would stay on with no way to switch it off. The backend
 * calls catalog keys permanent and refuses unknown ones, so today this adds nothing; it is for
 * the day a key is dropped all the same.
 */
function withStandIns(
  listed: CatalogFeature[],
  catalog: readonly CatalogFeature[],
  held: ReadonlySet<string>,
): CatalogFeature[] {
  const known = new Set(catalog.map((f) => f.key));
  const missing = [...held].filter((key) => !known.has(key));
  if (missing.length === 0) return listed;
  return [
    ...listed,
    ...missing.map((key) => ({
      key,
      label: key,
      description: "No longer offered.",
      // No tier to require: the picker leaves the subscription line off when this is empty.
      subscriptionTier: "",
    })),
  ];
}
