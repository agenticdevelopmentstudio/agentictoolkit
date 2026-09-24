import type { ProvisionedFeature } from "@agentic-toolkit/data/ecosystems";

/** The one field of a topic row this module reads: see `EcosystemsTopicConfig.features`. */
interface FeatureKeyedTopic {
  features?: readonly string[];
}

/**
 * The topic rows an ecosystem actually holds: every row that names no catalog feature (Settings,
 * Child Ecosystems, a feature site's own rows), plus each row with at least one of its `features`
 * provisioned and not removed.
 *
 * The Features list used to draw every product topic whether or not the product had it — the
 * child "Agentic Developer Hub" showed nineteen rows while its Manage features dialog showed
 * nothing ticked (Mike, 2026-09-24). The list and the dialog now read the same provisioned set,
 * so they cannot disagree. A coming-soon feature is never provisionable, so its row stays off
 * until the catalog ships it.
 *
 * `provisioned` is `undefined` while the read is in flight: keyed rows are withheld until it
 * lands rather than drawn and then yanked. On a FAILED read the caller passes `null` and every
 * row is shown — a transient error must not make a product look empty, and each pane still
 * reports its own failure.
 */
export function heldTopics<T extends FeatureKeyedTopic>(
  topics: readonly T[],
  provisioned: readonly ProvisionedFeature[] | null | undefined,
): T[] {
  if (provisioned === null) return [...topics];
  const held = new Set(
    (provisioned ?? []).filter((f) => f.state !== "removed").map((f) => f.featureKey),
  );
  return topics.filter((t) => t.features == null || t.features.some((k) => held.has(k)));
}
