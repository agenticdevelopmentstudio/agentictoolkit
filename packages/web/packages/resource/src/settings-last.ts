/** The fields {@link settingsLast} reads and writes. */
export interface DividedTopic {
  id: string;
  label?: string;
  dividerAfter?: boolean;
}

/** A topic row that IS a list's Settings: id `settings`, or labelled "Settings". */
export function isSettingsTopic(t: { id: string; label?: string }): boolean {
  return t.id === "settings" || t.label?.trim().toLowerCase() === "settings";
}

/**
 * The same rows with Settings moved to the END, behind a divider, whatever list they came from.
 *
 * Every topics list closes on Settings, alone under a rule (Mike, 2026-09-24) — the rails a
 * feature publishes and the group sub-rails {@link StackGroupDetail} draws alike, which is why it
 * lives here, below both (it moved down from features/ecosystems). Each host used to place it by
 * hand — the ecosystem site's list opened on it, and a product's hung its divider on Stores, which
 * the held-features filter drops for any product without a store, leaving Settings run straight
 * on from the row above. Deciding it on the rows AS DRAWN (after any filter) is the one place
 * that sees them that way. The other dividers are kept as authored, except on the row that is now
 * last, which would draw a line under nothing.
 */
export function settingsLast<T extends DividedTopic>(topics: readonly T[]): T[] {
  const settings = topics.find(isSettingsTopic);
  const rest = topics.filter((t) => t !== settings).map((t) => ({ ...t }));
  if (!settings) {
    if (rest.length) rest[rest.length - 1]!.dividerAfter = false;
    return rest;
  }
  if (rest.length) rest[rest.length - 1]!.dividerAfter = true;
  return [...rest, { ...settings, dividerAfter: false }];
}
