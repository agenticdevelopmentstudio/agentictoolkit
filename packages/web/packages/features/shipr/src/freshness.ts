import type { RepoState } from './types';

/**
 * HOW OLD A READ MAY BE BEFORE OPENING A REPOSITORY REFRESHES IT.
 *
 * An hour, named by the operator (Mike: "clicking on a website in home should fire status if
 * it's never been fired before, or if the last check was more than an hour prior"). The
 * number is the whole rate limit: reading a repository is a handful of forge round trips, so
 * a console that fired one on every click would spend them on browsing. One per repository
 * per hour is cheap, and it is the difference between a ladder that is current when someone
 * looks at it and one that is current when someone remembers to press a button.
 */
export const STATUS_MAX_AGE_MS = 60 * 60 * 1000;

/**
 * A backend stamp as milliseconds.
 *
 * `timestamp without time zone` read through drizzle's `mode: 'string'` comes back as
 * `2026-08-25 16:37:50.852` — a space, and no zone — which `Date.parse` reads as LOCAL time.
 * Every stamp compared against another gets the identical treatment here, so a comparison
 * holds whichever shape the wire settles on; naming UTC keeps it right if only one side ever
 * gains a `Z`.
 *
 * `NaN` for an absent or unparseable stamp, and that is load-bearing at both call sites:
 * every comparison against `NaN` is false, so "we cannot date this read" falls out as "this
 * read is not fresh" rather than as an accidental pass.
 */
export function stampMs(at: string | null | undefined): number {
  if (!at) return Number.NaN;
  const iso = at.includes('T') ? at : at.replace(' ', 'T');
  return Date.parse(/[Zz]|[+-]\d\d:?\d\d$/.test(iso) ? iso : `${iso}Z`);
}

/**
 * Is this repository's last `status` old enough to be worth reading again?
 *
 * NULL IS THE MAIN CASE, not the edge one: a repository nobody has ever run `status` against
 * has no state at all, which is every repository the moment it is registered or seeded, and
 * it is exactly the one whose pane says "Never read". So it answers true, and the first click
 * on it is what fills it in.
 */
export function statusIsStale(
  state: Pick<RepoState, 'readAt'> | null | undefined,
  now: number = Date.now(),
): boolean {
  return !(now - stampMs(state?.readAt) < STATUS_MAX_AGE_MS);
}
