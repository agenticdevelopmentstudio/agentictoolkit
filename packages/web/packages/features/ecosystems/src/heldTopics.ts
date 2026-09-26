import { activeFeatureKeys, type ProvisionedFeature } from "@agentic-toolkit/data/ecosystems";

/** The fields of a topic row {@link heldTopics} reads: see `EcosystemsTopicConfig.features`. */
interface FeatureKeyedTopic {
  id: string;
  features?: readonly string[];
}

/** The fields {@link settingsLast} reads and writes. */
interface DividedTopic {
  id: string;
  dividerAfter?: boolean;
}

/**
 * The same rows with Settings moved to the END, behind a divider, whatever list they came from.
 *
 * Every topics list closes on Settings, alone under a rule (Mike, 2026-09-24). Each host used to
 * place it by hand — the ecosystem site's list opened on it, and a product's hung its divider on
 * Stores, which the held-features filter drops for any product without a store, leaving Settings
 * run straight on from the row above. Deciding it here, AFTER that filter, is the one place that
 * sees the rows as drawn. The other dividers are kept as authored, except on the row that is now
 * last, which would draw a line under nothing.
 */
export function settingsLast<T extends DividedTopic>(topics: readonly T[]): T[] {
  const settings = topics.find((t) => t.id === "settings");
  const rest = topics.filter((t) => t.id !== "settings").map((t) => ({ ...t }));
  if (!settings) {
    if (rest.length) rest[rest.length - 1]!.dividerAfter = false;
    return rest;
  }
  if (rest.length) rest[rest.length - 1]!.dividerAfter = true;
  return [...rest, { ...settings, dividerAfter: false }];
}

/** A row {@link heldTopics} kept, marked when its feature is still being set up. */
export type HeldTopic<T> = T & {
  /** Every one of the row's features that the ecosystem holds is still `provisioning` — none is
   *  `active` yet. The row is SHOWN, so the list agrees with the Manage features dialog that ticked
   *  it, but it must not open onto its pane: see {@link heldTopics}. */
  provisioning?: boolean;
};

/**
 * The topic rows an ecosystem actually holds: every row that names no catalog feature (Settings,
 * Child Ecosystems, a feature site's own rows), plus each row with at least one of its `features`
 * ACTIVE or still PROVISIONING — the latter marked `provisioning: true`.
 *
 * The Features list used to draw every product topic whether or not the product had it — the
 * child "Agentic Developer Hub" showed nineteen rows while its Manage features dialog showed
 * nothing ticked (Mike, 2026-09-24). A still-provisioning feature is the other half of that
 * disagreement: the dialog ticks it (`presentFeatureKeys` — queuing it twice would be a bug), and
 * a list that simply HID it left a feature the user had just added nowhere on screen but a ticked
 * box, and one stuck in `provisioning` invisible for good. So the row is drawn, and marked:
 * `provisioning` is set only when none of the row's features is `active` (`activeFeatureKeys`, the
 * rule the hub's workspace rail reads), so the caller shows its status and — because a
 * provisioning feature can have stopped partway — a "still being set up" notice in place of a pane
 * that could open onto storage that isn't there. A coming-soon feature is never provisionable, so
 * its row stays off until the catalog ships it.
 *
 * `provisioned` is `undefined` while the read is in flight: keyed rows are withheld until it
 * lands rather than drawn and then yanked — all but `routed`, the row the URL names. Withholding
 * that one too left a deep link to a product feature on "Select a topic to view.", beside a list
 * holding only Settings, for as long as the read took; the hub's workspace rail draws its routed
 * feature for the same reason (`railGrants`). Should the product turn out not to hold it, that
 * one row goes when the read lands. On a read that failed with NO answer the caller passes `null`
 * and every row is shown, unmarked — a transient error must not make a product look empty, and
 * each pane still reports its own failure.
 */
export function heldTopics<T extends FeatureKeyedTopic>(
  topics: readonly T[],
  provisioned: readonly ProvisionedFeature[] | null | undefined,
  routed?: string,
): HeldTopic<T>[] {
  if (provisioned === null) return [...topics];
  const active = activeFeatureKeys(provisioned ?? []);
  const provisioning = new Set(
    (provisioned ?? []).filter((f) => f.state === "provisioning").map((f) => f.featureKey),
  );
  const held: HeldTopic<T>[] = [];
  for (const t of topics) {
    if (t.features == null || t.features.some((k) => active.has(k))) held.push(t);
    else if (t.features.some((k) => provisioning.has(k))) held.push({ ...t, provisioning: true });
    else if (provisioned === undefined && t.id === routed) held.push(t);
  }
  return held;
}
