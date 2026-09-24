/**
 * The ONE home for a tool's trust-legible provenance heading, shared by the owner view
 * (workspace AgentToolsPanel) and the per-user consent view (settings AssistantsPanel) so the
 * rule has a single authoritative representation and can never drift between the two panels.
 *
 * Invariant: a genuinely `null` source is the ONLY thing labelled "Built-in" (a curated, native
 * tool). Every non-null source gets its own distinct, clearly-not-native heading, so a
 * stale/delisted third-party or integration grant — which carries its real stored source, not
 * `null` — can never masquerade as a built-in. Sources are source ids: `web`,
 * `integration.<provider>.<connId>`, `mcp.<slug>`; any other non-null source is shown verbatim
 * (unrecognised, but NEVER "Built-in").
 */
export const BUILT_IN = "Built-in";

export function sourceLabel(source: string | null): string {
  if (source === null) return BUILT_IN;
  if (source === "web") return "Web";
  if (source.startsWith("integration.")) {
    const provider = source.split(".")[1];
    return provider ? `Integration: ${provider}` : "Integration";
  }
  if (source.startsWith("mcp.")) {
    const slug = source.slice("mcp.".length);
    return slug ? `Third-party: ${slug}` : "Third-party";
  }
  // Any other non-null source: show it verbatim — unrecognised, but NEVER "Built-in".
  return source;
}

/**
 * Group `items` by their `sourceLabel(getSource(item))` heading, sorted by label — the ONE
 * "group tools by source" shape shared by every tool/catalog listing (AbilitiesPanel's grant
 * catalog), so built-ins and each external source read as their own section identically
 * everywhere they're listed. (Settings AssistantsPanel shows the same `sourceLabel` as a
 * sortable Source COLUMN instead — its list is an EditableList like every other settings table.)
 */
export function groupBySource<T>(
  items: readonly T[],
  getSource: (item: T) => string | null,
): [string, T[]][] {
  const byLabel = new Map<string, T[]>();
  for (const item of items) {
    const label = sourceLabel(getSource(item));
    const rows = byLabel.get(label) ?? [];
    rows.push(item);
    byLabel.set(label, rows);
  }
  return [...byLabel.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}
