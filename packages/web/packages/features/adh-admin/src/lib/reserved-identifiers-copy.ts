import type {
  ReleaseResult,
  ReservedIdentifier,
  ReservedReason,
} from "../api/reserved-identifiers";

/**
 * The words the Reserved Identifiers page puts in front of an operator, kept out of the page so
 * they can be asserted.
 *
 * This is not decoration. "Remove the reservation" describes only two of the three cases — the
 * third RENAMES a deleted row and moves everything addressed beneath it — and an operator who
 * confirms a rename believing it was a delete has been misled by the button, not by the backend.
 * Same for the outcome: a release that left live addresses behind must not read as a clean success.
 */

/**
 * `label` is ONE WORD, and the blurb is a tooltip rather than a second line.
 *
 * The reason column used to stack the label over its blurb, which doubled every row's height for
 * a sentence an operator reads once and then never again. A one-line row is what makes a list of
 * a few hundred held names scannable at all; the sentence is still there on hover, where it costs
 * nothing.
 */
export const REASONS: Record<
  ReservedReason,
  { label: string; blurb: string; variant: "blue" | "orange" | "accent" }
> = {
  "rename-leftover": {
    label: "Renamed",
    blurb: "left behind by a rename, and still resolving for now",
    variant: "blue",
  },
  orphan: {
    label: "Orphan",
    blurb: "the thing it pointed at no longer exists",
    variant: "orange",
  },
  "deleted-entity": {
    label: "Deleted",
    blurb: "a deleted item is still sitting on this name",
    variant: "accent",
  },
};

/** The rdid's type prefix — its first segment (`storage.acme.notes` → `storage`). */
export const rdidType = (rdid: string): string => rdid.split(".")[0] ?? rdid;

/** `bucket_type` → "bucket type": the entity type as an operator would say it out loud. */
const spoken = (entityType: string): string => entityType.replace(/_/g, " ");

/** What releasing THIS row will actually do — the sentence the confirmation has to get right. */
export function releaseExplanation(item: ReservedIdentifier): string {
  if (item.reason === "deleted-entity") {
    return `The deleted ${spoken(item.entityType)} still holding "${item.rdid}" will be renamed to a placeholder, and anything still addressed underneath it moves with it. The name becomes available immediately.`;
  }
  if (item.reason === "orphan") {
    return `"${item.rdid}" points at a ${spoken(item.entityType)} that no longer exists. The mapping will be deleted and the name becomes available.`;
  }
  return `"${item.rdid}" is an old address kept so existing links keep working. Releasing it stops those links resolving and makes the name available.`;
}

export function outcomeTitle(result: ReleaseResult): string {
  return result.freed ? `Released ${result.rdid}` : `Partly released ${result.rdid}`;
}

export function outcomeDetail(result: ReleaseResult): string {
  const renamed = result.placeholder ? ` It was renamed to "${result.placeholder}".` : "";
  const kids =
    result.children.length > 0
      ? ` ${plural(result.children.length, "name")} held underneath it went with it.`
      : "";
  if (result.freed) return `The name is available again.${renamed}${kids}`;
  return `${renamed}${kids} These addresses are still in that namespace and were left alone: ${result.stillHeldBy.join(", ")}.`.trim();
}

const plural = (n: number, noun: string): string => `${n} ${noun}${n === 1 ? "" : "s"}`;

/**
 * The one line an operator reads after releasing a SELECTION.
 *
 * A release run is not one outcome: some names come back clean, some free a subtree with them,
 * some leave live addresses behind, and some the operator SKIPPED past after they failed.
 * Reporting only "released 6" would bury the ones that did not, which are the results the operator
 * has to act on — so the partial and skipped counts are stated whenever they are non-zero, and the
 * summary never says "released" about a name that is still held.
 *
 * `skipped` is the rdids the run stepped over. They are named rather than counted because a skip
 * is a piece of unfinished work the operator has to come back to, and "1 skipped" does not say
 * which one.
 */
export function releaseRunSummary(
  results: ReleaseResult[],
  skipped: string[] = [],
): { title: string; detail: string } {
  const freed = results.filter((r) => r.freed);
  const partial = results.filter((r) => !r.freed);
  const children = results.reduce((n, r) => n + r.children.length, 0);

  const title =
    partial.length === 0
      ? `Released ${plural(freed.length, "name")}`
      : `Released ${plural(freed.length, "name")}, ${partial.length} only partly`;

  const parts: string[] = [];
  if (children > 0) parts.push(`${plural(children, "name")} held underneath went with them.`);
  if (partial.length > 0) {
    parts.push(
      `Still held: ${partial.map((r) => r.rdid).join(", ")} — live addresses in those namespaces were left alone.`,
    );
  }
  if (skipped.length > 0) {
    parts.push(`Skipped, still held: ${skipped.join(", ")}.`);
  }
  if (parts.length === 0) parts.push("The names are available again.");
  return { title, detail: parts.join(" ") };
}
