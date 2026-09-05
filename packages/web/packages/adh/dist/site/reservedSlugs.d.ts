/**
 * The names a workspace slug may not take.
 *
 * The workspace is the FIRST path segment on every site in the family — `/<workspace>` — so
 * a slug competes for that segment with the template's own static routes. Next resolves a
 * static segment ahead of a dynamic one, and it does not fall through to the dynamic one
 * when the static directory exists but has no page at that level, so a principal whose slug
 * is one of these names is unreachable at its own address whether the name renders something
 * else or plain 404s.
 *
 * That is why this lives in the toolkit rather than in a site. A slug is minted ONCE — it is
 * the principal's handle — and it is spent at the root of all 42 sites, so what may be
 * reserved is a fact about the shared template, not about whichever site's form happens to
 * take the input. Two sites offer that form (personaregistry's settings pane and the hub's),
 * and each used to carry its own hand-written answer.
 *
 * The server refuses a NARROWER set, and this list is the wider one. `RESERVED_PRINCIPAL_SLUGS`
 * in `backend/src/adh/src/lib/rdid.ts` is the rdid type prefixes plus `RESERVED_ROUTE_SLUGS`,
 * and `/auth/slug-available/:slug` reports a hit there as `reason: 'format'` — so a word that
 * shadows a route is refused whichever way the slug is minted, while the words held back on
 * taste alone (`admin`, `login`, the hub's feature vocabulary) are refused only by the two
 * forms. `<adh-tools>/sites/scripts/verify_reserved_route_slugs.py` is what keeps the narrow set from
 * falling behind the route trees, and it checks this list against them too.
 *
 * Adding a name here narrows what the forms will accept; it does not evict a slug already
 * stored, on either side — both are mint-time refusals.
 */
/**
 * Top-level route segments the site template itself owns.
 *
 * Measured from the 42 `app/` trees, not assumed: `auth` and `home` exist in all 42 today,
 * and `details`, `privacy`, `terms` and `tour` in every site that has been through the
 * template. They are listed unconditionally rather than per-site because the template is
 * what decides them — a site that lacks one today gets it on the next template change, and a
 * slug reserved slightly early costs a handle nobody has, while one reserved slightly late
 * costs a principal their address on 42 sites at once.
 */
export declare const FAMILY_ROUTE_SEGMENTS: readonly string[];
/**
 * First URL segments an individual site adds beyond the template.
 *
 * Every one of these shadows a workspace on the site that owns it, and each is reserved on
 * all 42 anyway. That is the whole point of the list: a slug is minted once, so the question
 * a mint form has to answer is not "is this free HERE" but "is this free ANYWHERE", and the
 * only list that can answer it is one list. Reserving cookbook's `papers`-shaped words on
 * academy costs a handle nobody holds; not reserving them costs a principal their address on
 * whichever site they forgot about.
 *
 * Measured from the 42 `app/` trees plus the two `next.config.ts` files that add redirects —
 * a route group contributes nothing to the URL, so its children are first segments too, and a
 * redirect source occupies its segment as surely as a directory does. Regenerate the reading
 * rather than editing from memory; the sites move.
 */
export declare const SITE_ROUTE_SEGMENTS: readonly string[];
/**
 * Segments a FEATURE'S OWN URL grammar matches literally, ahead of reading a slug.
 *
 * A fourth list rather than an entry in one of the three above, because the matcher is
 * different and every one of those describes Next's router. A feature mounted under the
 * workspace's catch-all parses the segments itself: `parseOrganizationsPath` compares the first
 * one to `"all"` before treating it as an organization slug, so `/<workspace>/all` is the org-card
 * landing and an organization slugged `all` has no address — the same shadowing a route directory
 * does, with the feature's parser as the matcher instead of the router. Nothing under `app/` names
 * the word, which is exactly why it needs writing down: there is no directory to read it off.
 *
 * Organizations is the feature that makes it matter, because it is the one whose resource id IS a
 * claimable slug (`getId={(w) => w.slug}`). Teams, Projects and Ecosystems spend the identical
 * word against opaque ids, where nothing can collide — but the word is listed once for the family
 * either way, on the same reasoning as SITE_ROUTE_SEGMENTS: a slug is minted once, so the only
 * question a form can answer is "is this free ANYWHERE".
 *
 * `<adh-tools>/sites/scripts/verify_reserved_route_slugs.py` re-derives these from the parser sources — both
 * the comparison and the named constant one may be spelled as — and fails when a grammar starts
 * matching a word neither list carries, so this cannot silently fall behind.
 */
export declare const GRAMMAR_SEGMENTS: readonly string[];
/**
 * Names refused for a reason other than shadowing.
 *
 * Nothing here is reserved BECAUSE it shadows — that is what the three lists above are for.
 * These are words a handle should not be able to claim because the handle appears next to the
 * site's own vocabulary, and `/admin`, `/login`, `/settings` read as the site speaking rather
 * than as a person.
 *
 * A few of them are first segments as well (`login`, `signup` and `contact` on the hub, and
 * `settings` and `user` since its route move), and that is not a filing error: the reason
 * recorded here is the one that outlives the route. Delete the hub's `/user/[slug]` tree and
 * `user` is still not a handle anyone may hold.
 *
 * The first group is the union of what personaregistry and the hub each already refused before
 * this list existed. Un-reserving a name that has been refused for years is a decision with its
 * own consequences — someone claims it, and it can never be taken back — so the merge keeps
 * both sides rather than trimming to what is provably needed.
 */
export declare const RESERVED_HANDLE_WORDS: readonly string[];
/**
 * Every name a workspace slug may not take, on any site in the family.
 *
 * It takes no arguments, and that is the load-bearing part. It used to accept the extra
 * segments a caller's own site adds, which quietly made reservation a per-site answer: hub
 * passed its list and personaregistry passed a different one, so a slug minted on either was
 * only ever checked against the site it was typed into and could land on a name some OTHER
 * site had already spent. A slug is one slug, so the answer is one answer.
 *
 * Everything is lowercased on the way out, because the callers lowercase the slug before the
 * lookup and a mixed-case entry would sit in the set matching nothing.
 */
export declare function reservedWorkspaceSlugs(): ReadonlySet<string>;
//# sourceMappingURL=reservedSlugs.d.ts.map