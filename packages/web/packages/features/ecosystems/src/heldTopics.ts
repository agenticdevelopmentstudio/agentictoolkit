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

/**
 * The topic rows an ecosystem actually holds: every row that names no catalog feature (Settings,
 * Child Ecosystems, a feature site's own rows), plus each row with at least one of its `features`
 * ACTIVE.
 *
 * The Features list used to draw every product topic whether or not the product had it — the
 * child "Agentic Developer Hub" showed nineteen rows while its Manage features dialog showed
 * nothing ticked (Mike, 2026-09-24). That first fix read the dialog's own rule
 * (`presentFeatureKeys`), on the theory that a list and the dialog that turns its rows on could
 * not disagree if they read one set. They can, and do: `provisioning` is a row the dialog must
 * tick (queuing it twice would be a bug) but a row this list must NOT draw, because a
 * still-provisioning feature can fail partway and a topic row that opens onto storage that isn't
 * there is worse than a row that briefly lags behind the dialog. So a list and the picker are
 * different questions after all — "can I navigate there" versus "is this in the ecosystem" — and
 * each reads the rule for its own question: this list `activeFeatureKeys`, the same one the hub's
 * workspace rail reads, and the dialog `presentFeatureKeys` (Mike, 2026-09-25). A coming-soon
 * feature is never provisionable, so its row stays off until the catalog ships it.
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
  const held = activeFeatureKeys(provisioned ?? []);
  return topics.filter(
    (t) =>
      t.features == null ||
      (provisioned === undefined && t.id === routed) ||
      t.features.some((k) => held.has(k)),
  );
}
