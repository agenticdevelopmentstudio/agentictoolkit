import type { AdminUserSummary } from "../api/admin";

/**
 * What the Users table calls a customer's roles.
 *
 * All that is left of the old `sort-users.ts`. That module existed because the page paginated:
 * sorting and role-filtering had to happen inside the transform, BEFORE the slice, or they
 * arranged page one instead of the list. Nothing pages now — `useEditableList` sorts by a column's
 * `value` and filters by a facet's `valuesOf` — so the comparators and the filter went with the
 * pager, and only the vocabulary is still needed.
 */

/** The synthetic role the table shows for a customer holding no capability at all. */
export const NO_ROLE = "user";

/**
 * The row's roles as ONE string, for sorting and searching.
 *
 * Sorted before joining so two users holding the same capabilities in different orders compare
 * equal — the set is what the operator sees, and the order the grants happened to arrive in is
 * not part of it.
 */
export const roleLabel = (user: AdminUserSummary): string =>
  user.capabilities.length === 0 ? NO_ROLE : [...user.capabilities].sort().join(",");

/** Every role value a facet menu should offer for this row — the same vocabulary, as a list. */
export const roleValues = (user: AdminUserSummary): string[] =>
  user.capabilities.length === 0 ? [NO_ROLE] : user.capabilities;
