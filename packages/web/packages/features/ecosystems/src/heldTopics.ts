import { presentFeatureKeys, type ProvisionedFeature } from "@agentic-toolkit/data/ecosystems";

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

/**
 * The topic rows an ecosystem actually holds: every row that names no catalog feature (Settings,
 * Child Ecosystems, a feature site's own rows), plus each row with at least one of its `features`
 * provisioned and not removed.
 *
 * The Features list used to draw every product topic whether or not the product had it — the
 * child "Agentic Developer Hub" showed nineteen rows while its Manage features dialog showed
 * nothing ticked (Mike, 2026-09-24). The list and the dialog now read the same provisioned set
 * through the same rule, `presentFeatureKeys`, so once the read has landed a keyed row is drawn
 * exactly when the dialog opens with one of its features ticked. A coming-soon feature is never
 * provisionable, so its row stays off until the catalog ships it.
 *
 * `provisioned` is `undefined` while the read is in flight: keyed rows are withheld until it
 * lands rather than drawn and then yanked — all but `routed`, the row the URL names. Withholding
 * that one too left a deep link to a product feature on "Select a topic to view.", beside a list
 * holding only Settings, for as long as the read took; the hub's workspace rail draws its routed
 * feature for the same reason (`railGrants`). Should the product turn out not to hold it, that
 * one row goes when the read lands. On a FAILED read the caller passes `null` and every row is
 * shown — a transient error must not make a product look empty, and each pane still reports its
 * own failure.
 */
export function heldTopics<T extends FeatureKeyedTopic>(
  topics: readonly T[],
  provisioned: readonly ProvisionedFeature[] | null | undefined,
  routed?: string,
): T[] {
  if (provisioned === null) return [...topics];
  const held = presentFeatureKeys(provisioned ?? []);
  return topics.filter(
    (t) =>
      t.features == null ||
      (provisioned === undefined && t.id === routed) ||
      t.features.some((k) => held.has(k)),
  );
}
