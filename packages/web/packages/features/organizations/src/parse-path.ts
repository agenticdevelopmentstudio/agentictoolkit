// The Organizations URL grammar — the ONE authoritative parse of an organizations route's path
// segments into OrganizationsFeature's selection props, so a host route can't drift its parsing
// away from what the feature expects (mirrors @agentic-toolkit/ecosystems and
// @agentic-toolkit/teams's parse-path).
//
// SERVER-SAFE, and its own entry (`@agentic-toolkit/organizations/parse`) for that reason: the
// package barrel's dist carries "use client", so an RSC importing the parser from there would
// throw on a render-only client reference.

/**
 * The landing's own segment, matched LITERALLY ahead of reading the first segment as an
 * organization slug — the same shadowing a route directory does, with this parser as the matcher
 * instead of Next's router.
 *
 * That makes it a word no organization may be minted with, and it is refused at the mint boundary
 * (`RESERVED_ROUTE_SLUGS` in backend/src/adh/src/lib/rdid.ts) for the same reason `details` and
 * `home` are: the collision is between a database slug and a matcher, so no uniqueness constraint
 * spans both. Sibling grammars (Teams, Projects, Ecosystems) match the identical word without
 * needing that, because their first segment is an opaque id — only THIS feature addresses its
 * resource by a slug the user chose (`getId={(w) => w.slug}`).
 *
 * `<adh-tools>/sites/scripts/verify_reserved_route_slugs.py` re-derives this from the source and fails when
 * the backend stops refusing it, so the two cannot drift apart.
 */
const ALL_SEGMENT = "all";

/** The selection OrganizationsFeature renders, parsed from a route's path segments. Maps 1:1
 *  onto its props (the host supplies `basePath`). Unlike Ecosystems there IS an "All" landing —
 *  the organization list is the first rail level, and a bare path shows the org cards. */
export interface OrganizationsPathSelection {
  /** The `/all` landing was asked for by name, rather than fallen back to. */
  all?: boolean;
  /** The organization's SLUG, which is what identifies an org everywhere on the platform (and
   *  what `?workspace=` takes) — there is no separate org id in a URL. */
  activeOrgSlug?: string;
  activeTopic?: string;
  /**
   * Everything BELOW the topic, handed over whole rather than parsed into a single leaf id.
   *
   * This is the one place this grammar differs from Ecosystems' and Teams', and it is deliberate:
   * an org topic may own a URL tail deeper than one segment. Teams re-parses its tail with
   * `parseTeamsPath` (it is a whole nested feature, with its own four-segment grammar); Settings
   * takes a `path` array. A single `activeLeafId` would have made this grammar the ceiling on
   * every topic's, and each new depth a change HERE — which is exactly the coupling `basePath`
   * exists to avoid.
   *
   * Always an array, never undefined: a topic reading `topicPath[0]` should not also have to ask
   * whether there is a path at all.
   */
  topicPath: string[];
}

/**
 * Parse an organizations route's catch-all `path` segments:
 *   (none) / []            → { topicPath: [] }              (the org card landing)
 *   ["all"]                → { all: true, topicPath: [] }   (the same landing, asked for by name)
 *   [slug]                 → { activeOrgSlug }              (that org, no topic selected)
 *   [slug, topic]          → { …, activeTopic }
 *   [slug, topic, ...rest] → { …, topicPath: rest }         (the topic's own grammar, untouched)
 *
 * Empty segments are dropped so a trailing or doubled slash lands on the same selection as the
 * tidy URL — the same reading `parseNotebookPath` and `parseIntegrationsPath` give them. It
 * matters more here than there: a leading empty segment would shift the ORG slug into the topic
 * position, so `//acme/teams` would parse as the org named "" with topic "acme".
 */
export function parseOrganizationsPath(path?: string[]): OrganizationsPathSelection {
  const [first, second, ...rest] = (path ?? []).filter(Boolean);
  if (!first) return { topicPath: [] };
  if (first === ALL_SEGMENT) return { all: true, topicPath: [] };
  return {
    activeOrgSlug: first,
    activeTopic: second,
    topicPath: rest,
  };
}
