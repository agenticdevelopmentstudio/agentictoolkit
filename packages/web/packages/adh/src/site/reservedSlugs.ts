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
export const FAMILY_ROUTE_SEGMENTS: readonly string[] = [
  'auth', // app/auth — the SSO callback
  'home', // app/home — the workspace-resolving redirect
  'details', // app/details/[topic] — the shared concept pages
  'privacy',
  'terms',
  'tour', // the landing deck's second route
  // Not a directory on any site: `marketingNextConfig` rewrites `/api/*` to the backend, so
  // the segment is spoken for on all 42 without appearing in any `app/` tree.
  'api',
  // Next serves these from FILES at the root of `app/`, so they occupy the same segment as a
  // slug even though no directory names them.
  'favicon.ico',
  'icon.svg',
  'apple-icon.png',
  'opengraph-image.png',
  'robots.txt',
  'sitemap.xml',
  // The framework's own namespace.
  '_next',
]

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
export const SITE_ROUTE_SEGMENTS: readonly string[] = [
  // billing — app/claim, the link a purchaser follows out of Stripe's receipt. One site's route,
  // reserved on all 42 for the reason at the top of this list: the mint form's question is not
  // "is this free HERE" but "is this free ANYWHERE".
  'claim',
  // community — app/{categories,discussions,forum,people,topics}. (`admin` is below.) `forum` is
  // the board: it was this site's `/home` until `/home` became the family's workspace redirect,
  // and it is the one segment the convergence itself minted.
  'categories',
  'discussions',
  'forum',
  'people',
  'topics',
  // consultants — app/consultant/[entry], the public profile of one directory entry. The site is
  // named in the plural and the route in the singular, so the reserved word is the one the URL
  // spends, not the one on the tin.
  'consultant',
  // cookbook — the corpus IS these nine words. Each is a real directory,
  // `app/(reader)/<section>/[[...slug]]`, so `/guidelines/testing/test-pyramid` is a document's
  // own address with nothing in front of it; the route group contributes no segment. They are
  // reserved because a static segment beats `[workspace]`, not because a redirect claims them —
  // there is no `/docs` prefix any more, and the entry in RESERVED_HANDLE_WORDS below is taste,
  // not this site. `projects` is cookbook's ninth section directory as well as the hub's
  // feature-page redirect, and is listed once, under the hub. This is the cost recorded in that
  // site's `.claude/rules/site-design.md` — adding a section to the book adds a reserved slug
  // for the whole family.
  'introduction',
  'principles',
  'guidelines',
  'ingredients',
  'recipes',
  'compliance',
  'reference',
  'appendix',
  // hub — app/{features,integrations,old-landing}, app/(auth)/{join,oidc}, app/(hub)/explore.
  // (`login`, `signup`, `contact`, `settings` and `user` are below.) `old-landing` is the
  // superseded hero page, still routable and deliberately kept so, which makes it a segment
  // like any other. `features` is where the eight marketing pages moved to when the root
  // segment became `[workspace]`, and it is a real directory: `app/features/[id]/`. The
  // integrations SITE routes `integrations` too — `app/integrations/oauth-callback`, where a
  // provider's OAuth redirect lands, at a path `oauthCallbackUrl()` builds from the window's own
  // origin and so cannot vary per site. Every site that mounts that feature grows the same
  // directory; the word is listed once.
  'features',
  'integrations',
  'join',
  'oidc',
  'explore',
  'old-landing',
  // hub — the marketing feature pages. These are not directories either: they were served
  // by `app/[slug]/page.tsx`, which dispatched on the slug ahead of a user profile, and the
  // root segment is `[workspace]` now — so each is a permanent REDIRECT source in the hub's
  // `next.config.ts` (`/<id>` → `/features/<id>`), derived from the same list the route's
  // generateStaticParams reads. A redirect answers before any route does, so the segment is
  // spoken for exactly as a directory's is, and these stay here rather than moving down to
  // RESERVED_HANDLE_WORDS: they are addressable URLs, not merely words a handle may not take.
  'agentic-personas',
  'persona-data-store',
  'user-data-store',
  'status-pages',
  'rest-api',
  'mcp',
  'applications',
  'projects',
  // personaregistry — `org` and `persona`, both REDIRECT sources in that site's `next.config.ts`
  // for the same reason the hub's eight above are: a redirect source claims its segment as
  // surely as a directory does. Neither is a directory there any more. `app/persona/[slug]`
  // existed only while the family's `[workspace]` sat at that site's root; `app/org/[slug]` was
  // older and outlived that window. Personas, users and organizations all address off the ROOT
  // now (`app/[slug]`) — an org is shown the way a user is, so it needs no prefix — and the old
  // prefixes stayed behind pointing at it. (`user` is the hub's public profile prefix, listed
  // above, and is a redirect source on this site too.)
  'org',
  'persona',
  // registries — app/registry/[registry] and app/registry/[registry]/[entry]: one owner-built
  // directory, and one entry within it. Singular for the same reason `consultant` is.
  'registry',
  // research — app/{papers,search}.
  'papers',
  'search',
  // toolkit — app/demo.
  'demo',
]

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
export const GRAMMAR_SEGMENTS: readonly string[] = [
  // organizations, teams, projects, ecosystems — `parse-path.ts`, the "all" landing.
  'all',
  // No parser spends this one today. `games/parse-path.ts` did — `/<workspace>/new` opened the
  // create-game dialog — and it went when the games rail became a list of products and a game
  // stopped being something you create directly (2026-08-22, `product-gaming-modes`).
  //
  // It stays reserved anyway, and deliberately: reserving a word is reversible and un-reserving
  // one is not. Delete this line and the very next customer may mint a workspace called `new`,
  // at which point no future grammar in any of the twelve features can ever spend the word
  // again — the obvious word for "the create screen", held by one account, fleet-wide, forever.
  // The word is still held back — it moved to RESERVED_HANDLE_WORDS, which is the list for a
  // refusal that is NOT shadowing. Keeping it here would have made this list say something false
  // about itself: every entry above is a segment some parser really compares against, and that
  // is the only claim this list makes.
]

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
export const RESERVED_HANDLE_WORDS: readonly string[] = [
  'about',
  'admin',
  'assets',
  'billing',
  'blog',
  'contact',
  'dashboard',
  'docs',
  'help',
  'legal',
  'login',
  'logout',
  'me',
  'monitoring',
  // Held on the same footing as the rest of this list, not because anything routes it.
  // `games/parse-path.ts` matched `/<workspace>/new` for the create-game dialog until
  // 2026-08-22 (`product-gaming-modes`), and when that grammar went the word came here rather
  // than being un-reserved: `new` is the obvious word for "the create screen", so letting one
  // account claim it fleet-wide, permanently, to buy back a name nobody has asked for is the
  // trade this list's own docstring declines to make. If a grammar spends the segment again,
  // it belongs back in GRAMMAR_SEGMENTS — and in the backend's RESERVED_ROUTE_SLUGS, which
  // dropped it because that list admits only words a live route or grammar earns.
  'new',
  'pricing',
  'profile',
  'public',
  'register',
  'session',
  'sessions',
  'settings',
  'signin',
  'signout',
  'signup',
  'static',
  'status',
  'support',
  'user',
  'users',
  // The hub's feature vocabulary. Every one of these is a SECOND segment — `/<workspace>/teams`,
  // `/<workspace>/tokens` — so none of them shadows a slug, and that is why they sit here rather
  // than in SITE_ROUTE_SEGMENTS. The hub refused them anyway, on the grounds that a profile slug
  // reading as one of its own feature words is a URL nobody can parse at a glance, and that
  // judgement is kept. The first group mirrors `FEATURES` in the hub's `data/feature-routes.ts`;
  // the rest are rail routes listed outside it, plus ONE retired segment — `ecosystems`, which
  // Products replaced: the ecosystems site maps to the `products` segment, so no hub route
  // spends the word. It is held back so a stale link resolves predictably instead of landing on
  // whichever user claimed the handle.
  //
  // `communities` was the second retired segment and is not one any more: when the fleet came
  // home, agenticdevelopercommunities.com's own workspace became `/<workspace>/communities`, so
  // the word is a live hub route again and is reserved on the ordinary grounds beside it.
  'all-data',
  'communities',
  'dashboards',
  'ecosystems',
  'email-signup',
  'feature-flags',
  'gamification',
  'invitations',
  'knowledgebases',
  'llm-providers',
  'members',
  'messaging',
  'narratives',
  'persona-services',
  'personas',
  'products',
  'registries',
  'research',
  'server-bags',
  'signin-apps',
  'storage',
  'teams',
  'tokens',
]

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
export function reservedWorkspaceSlugs(): ReadonlySet<string> {
  const all = [
    ...FAMILY_ROUTE_SEGMENTS,
    ...SITE_ROUTE_SEGMENTS,
    ...GRAMMAR_SEGMENTS,
    ...RESERVED_HANDLE_WORDS,
  ]
  return new Set(all.map((s) => s.toLowerCase()))
}
