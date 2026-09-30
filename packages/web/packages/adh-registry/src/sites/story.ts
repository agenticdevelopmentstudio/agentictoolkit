import type { SiteId } from './registry'

// The brand-story layer — one structural story record per site, the data spine
// behind every logged-out landing (see docs/planning/brand-story-plan.md).
// PURE DATA + TYPES (no React), like the registry it sits beside. Copy (labels,
// blurbs, hero prose) stays in the locale content catalog (websites/site-config);
// this module holds only what is identical across translations: where each site
// sits in the brand architecture, the message house, and the visitor journey.
//
// Why a sibling Record instead of fields on SiteDef: the SITES literal's
// <gen:sites> block is owned by scaffold-sites.py, so hand-authored judgment
// fields there would be clobbered on regeneration. `Record<SiteId, SiteStory>`
// makes the compiler the governance instead — scaffolding a new SiteId without
// authoring its story is a type error, never a silent gap.

/** Brand tier — the From/Of rule (brand-story-plan §2).
 *  - `masterbrand`: the Hub itself; carries the whole promise.
 *  - `chapter`: prefix-named sites OF the hub — one capability or stage each.
 *  - `satellite`: endorsed own-identity products (Toolkit, Persona Registry,
 *    Cookbook, FishLamp Design) — their own audience, visibly "from the Hub".
 *  - `proof`: own-named consumer products FROM the hub (Bitbag, My Agentic
 *    Teams, Learn True Facts) — the proof layer; only tie is a provenance mark,
 *    and they are excluded from hub-brand chrome and audits. */
export type BrandTier = 'masterbrand' | 'chapter' | 'satellite' | 'proof'

/** Message-house pillar (brand-story-plan §3) — which third of the promise
 *  ("everything your AI agents need to become real software") a site serves:
 *  agent `identity`, the agentic `backend`, or `build`-with-agents. */
export type StoryPillar = 'identity' | 'backend' | 'build'

/** Visitor-journey stage (brand-story-plan §4): Discover → Learn → Build →
 *  Ship → Adopt. Drives the logged-out landing's framing and its default CTA. */
export type FunnelStage = 'discover' | 'learn' | 'build' | 'ship' | 'adopt'

export interface SiteStory {
  tier: BrandTier
  pillar: StoryPillar
  funnelStage: FunnelStage
  /** The next site in this site's story — the logged-out landing's "next step"
   *  cross-link (e.g. the personas pipeline: personas → personabuilder →
   *  personaregistry → hub). Every chain converges on the hub (guarded by a
   *  test): whatever door a visitor entered, the story leads to the platform.
   *
   *  NOT the guided tour's graph. `/tour` walks the family in one sequence
   *  ending on a terminal site; this converges every branch on the hub. The
   *  two are different edge sets with different shapes and different owners
   *  — this one is hand-authored brand judgment, the tour's is derived from
   *  the `next:` frontmatter in `frontend/content/landing/sites/` — and the
   *  tour's lives in `SITE_TOUR_NEXT` below. They agree for many sites,
   *  which is exactly why reading one for the other stays wrong quietly. */
  nextStep: SiteId
}

/** One story per site, keyed by SiteId — same display order as SITES. */
export const SITE_STORIES: Record<SiteId, SiteStory> = {
  // --- proof layer: own-named products FROM the hub ---
  bitbag: { tier: 'proof', pillar: 'identity', funnelStage: 'discover', nextStep: 'hub' },
  // --- the masterbrand + core family ---
  hub: { tier: 'masterbrand', pillar: 'backend', funnelStage: 'discover', nextStep: 'hub-help' },
  // help.adh.com (the consolidated help surface). Its own chapter, converging straight on the hub.
  'hub-help': { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'hub' },
  cookbook: { tier: 'satellite', pillar: 'build', funnelStage: 'learn', nextStep: 'toolkit' },
  projects: { tier: 'chapter', pillar: 'build', funnelStage: 'build', nextStep: 'devteam' },
  narratives: { tier: 'chapter', pillar: 'build', funnelStage: 'discover', nextStep: 'hub' },
  personaregistry: { tier: 'satellite', pillar: 'identity', funnelStage: 'adopt', nextStep: 'hub' },
  devteam: { tier: 'chapter', pillar: 'build', funnelStage: 'build', nextStep: 'hub' },
  toolkit: { tier: 'satellite', pillar: 'build', funnelStage: 'build', nextStep: 'hub' },
  myagenticteams: { tier: 'proof', pillar: 'identity', funnelStage: 'adopt', nextStep: 'hub' },
  mcp: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'hub' },
  // --- the scaffolded chapters ---
  community: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'hub' },
  support: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'hub-help' },
  // docs.adh.com and the `docs` SiteId are retired (folded into help.adh.com, which serves the
  // guides + /rest-api); help continues to toolkit (docs' former nextStep). The landing itself
  // (agenticdeveloperhelp.com) is delisted — stories that used to flow INTO 'help' (hub, support)
  // now flow to 'hub-help', the family's Help destination.
  help: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'toolkit' },
  news: { tier: 'chapter', pillar: 'build', funnelStage: 'discover', nextStep: 'hub' },
  academy: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'cookbook' },
  dashboards: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  recipes: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'cookbook' },
  personas: { tier: 'chapter', pillar: 'identity', funnelStage: 'build', nextStep: 'personabuilder' },
  communities: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  ecosystems: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  registries: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  storage: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'hub' },
  customers: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'billing' },
  products: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'billing' },
  billing: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  domains: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  authentication: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'customers' },
  sites: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'hub' },
  devices: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  notifications: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  knowledgebases: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'hub' },
  tools: { tier: 'chapter', pillar: 'build', funnelStage: 'build', nextStep: 'toolkit' },
  education: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'academy' },
  teamregistry: { tier: 'chapter', pillar: 'identity', funnelStage: 'adopt', nextStep: 'hub' },
  teambuilder: { tier: 'chapter', pillar: 'identity', funnelStage: 'build', nextStep: 'teamregistry' },
  codereviews: { tier: 'chapter', pillar: 'build', funnelStage: 'ship', nextStep: 'hub' },
  personabuilder: { tier: 'chapter', pillar: 'identity', funnelStage: 'build', nextStep: 'personaregistry' },
  research: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'knowledgebases' },
  consultants: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'fishlamp' },
  // Organizations is the account-shape chapter: who your org is, who is in it, how it
  // is configured. Its teams topic is what hands the story to teambuilder.
  orgs: { tier: 'chapter', pillar: 'backend', funnelStage: 'adopt', nextStep: 'teambuilder' },
  // Notebook sits beside research — the same markdown surface, kept private. It hands
  // off to research, which is where a note becomes something you publish.
  notebook: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'research' },
  integrations: { tier: 'chapter', pillar: 'backend', funnelStage: 'build', nextStep: 'hub' },
  // Gamification is a property OF a product, so its story continues into products.
  gamification: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'products' },
  games: { tier: 'chapter', pillar: 'build', funnelStage: 'ship', nextStep: 'products' },
  // --- selling, testing, finding people, and filing what you write down ---
  // The hub's own merch shop: physical goods, so its story hands straight back to
  // the hub rather than into any product chapter.
  store: { tier: 'chapter', pillar: 'backend', funnelStage: 'adopt', nextStep: 'hub' },
  // Stores is the storefront ON a product, so its story continues into products.
  stores: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'products' },
  // Testing is the other half of shipping quality, beside code review.
  testing: { tier: 'chapter', pillar: 'build', funnelStage: 'ship', nextStep: 'codereviews' },
  // Shipr is the last step of building: a reviewed, tested commit walked from main to
  // production one branch at a time. It hands off to status, which is where you watch
  // what you just shipped.
  shipr: { tier: 'chapter', pillar: 'build', funnelStage: 'ship', nextStep: 'status' },
  // The developer directory — the people layer beside the consultant directory.
  registry: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'consultants' },
  // Docs is research with the publishing stripped out, so it hands off to research.
  docs: { tier: 'chapter', pillar: 'build', funnelStage: 'learn', nextStep: 'research' },
  // --- the two halves of messaging, which are deliberately different chapters ---
  // Messaging is what a PRODUCT sends — the providers, senders and templates behind
  // its email and SMS — so it is a backend chapter and hands off to notifications,
  // the surface those messages go out through.
  messaging: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'notifications' },
  // Messages is what YOU read and write, across every workspace and ecosystem at
  // once. That is a hub surface rather than a product service, so it hands back to
  // the hub rather than into any product chapter.
  messages: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'hub' },
  // --- studio & consulting. FishLamp Design is the studio the family sits under
  // (it replaced Agentic Developer Studio, whose site is gone); consulting points
  // at it as the absorbing site. fishlampdesign is the same site on its second
  // domain, so it shares fishlamp's story. ---
  consulting: { tier: 'chapter', pillar: 'build', funnelStage: 'adopt', nextStep: 'fishlamp' },
  fishlamp: { tier: 'satellite', pillar: 'build', funnelStage: 'discover', nextStep: 'hub' },
  fishlampdesign: { tier: 'satellite', pillar: 'build', funnelStage: 'discover', nextStep: 'fishlamp' },
  // --- operational consoles ---
  admin: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  status: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'hub' },
  builds: { tier: 'chapter', pillar: 'backend', funnelStage: 'ship', nextStep: 'status' },
}

/** The guided tour's next-step graph: whose `/tour` this site's `/tour` hands
 *  off to. Read `SITE_STORIES[id].nextStep` for the brand story instead — the
 *  note on that field says why the two are not the same edge set.
 *
 *  GENERATED, from THREE sources that cannot see each other. The walk was one
 *  ring through every site until the marketing sites moved to their own repo,
 *  and then the placeholder sites to theirs. It is now three rings, and each
 *  repo's `content/landing/` owns exactly its own — so there are three managed
 *  regions here rather than one, each spliced by `content-buildr update` from that
 *  repo's manifest and diffed by `content-buildr check`. To change a walk, edit that
 *  repo's markdown, not this file. The declarations, this comment, and the
 *  merge below are hand-written and sit outside all three regions.
 *
 *  Three rings, FOUR repos: agenticdeveloperhubwebsite took the hub, hub-help,
 *  admin and status on 2026-08-30 and owns no ring at all. Its manifest names a
 *  one-entry `tour_map` — a walk with nowhere to walk to — so it emits nothing
 *  here, and the `hub: 'research'` edge that used to head the main ring is gone
 *  from this file for good. That is not an omission to repair: `content-buildr` reads
 *  every edge off ADJACENT entries in one manifest's `tour_map`, and the two
 *  ends of that edge are now in different repos, so no generator anywhere can
 *  state it. Restoring it means teaching `content-buildr` that a ring can span repos,
 *  or hand-writing the edge here and accepting that nothing checks it.
 *
 *  One region per owner is the whole point, and the split is not cosmetic.
 *  With a single region, whichever repo generated last would write the map
 *  and DELETE the other repos' entries — and nothing would say so, because a
 *  shorter map still compiles, still satisfies every assertion about the
 *  entries it kept, and simply drops the other fleets off the tour. Separate
 *  regions make that impossible rather than unlikely.
 *
 *  What separate regions cost is the compiler's duplicate-key check: TS1117
 *  catches a site named twice inside ONE object literal, but a site claimed by
 *  two rings is just a spread that quietly wins. `tour-region.test.ts` asserts
 *  the key sets are pairwise disjoint, which is the half the type system
 *  cannot see.
 *
 *  `Partial` is load-bearing twice over, and is why this is a separate const
 *  rather than a field spliced into `SITE_STORIES`: the walk is being ported a
 *  few sites at a time, so the regions cover a SUBSET of `SiteId` and will
 *  until every site has a markdown file; and each ring's terminal site — where
 *  that walk ends — never has a next step, so even a finished walk leaves an id
 *  absent by construction. A site with no entry here is not on the tour yet;
 *  that is a state to render, not an error. */
export const TOUR_MAIN: Partial<Record<SiteId, SiteId>> = {
  // <gen:tour-main> managed by landing — do not edit by hand
  // </gen:tour-main>
}

/** The marketing fleet's ring, owned by the adhmarketing repo's manifest. This
 *  package is a submodule of all FOUR fleet repos — the fourth, the hub's, owns
 *  no ring — so a checkout whose sibling generator has not run yet reads an
 *  empty region here, which is a real state to render, not a broken one. */
export const TOUR_MARKETING: Partial<Record<SiteId, SiteId>> = {
  // <gen:tour-marketing> managed by landing — do not edit by hand
  narratives: 'education',
  education: 'recipes',
  recipes: 'authentication',
  authentication: 'knowledgebases',
  knowledgebases: 'notebook',
  notebook: 'personabuilder',
  personabuilder: 'personas',
  personas: 'projects',
  projects: 'sites',
  sites: 'storage',
  storage: 'teambuilder',
  teambuilder: 'billing',
  billing: 'codereviews',
  codereviews: 'testing',
  testing: 'communities',
  communities: 'customers',
  customers: 'dashboards',
  dashboards: 'devices',
  devices: 'domains',
  domains: 'ecosystems',
  ecosystems: 'gamification',
  gamification: 'integrations',
  integrations: 'messaging',
  messaging: 'notifications',
  notifications: 'messages',
  messages: 'orgs',
  orgs: 'games',
  games: 'products',
  products: 'stores',
  stores: 'registries',
  // </gen:tour-marketing>
}

/** The placeholder fleet's ring, owned by the adhplaceholders repo's manifest.
 *  Same submodule-of-three arrangement as the ring above: a checkout whose
 *  sibling generator has not run yet reads an empty region here, which is a real
 *  state to render rather than a broken one. */
export const TOUR_PLACEHOLDER: Partial<Record<SiteId, SiteId>> = {
  // <gen:tour-placeholder> managed by landing — do not edit by hand
  news: 'store',
  store: 'academy',
  academy: 'tools',
  tools: 'consultants',
  consultants: 'consulting',
  consulting: 'support',
  support: 'help',
  help: 'teamregistry',
  // </gen:tour-placeholder>
}

/** The whole walk, all three rings. Consumers index this; only the generators
 *  touch the three consts above. */
export const SITE_TOUR_NEXT: Partial<Record<SiteId, SiteId>> = {
  ...TOUR_MAIN,
  ...TOUR_MARKETING,
  ...TOUR_PLACEHOLDER,
}

export function getSiteStory(id: SiteId): SiteStory {
  return SITE_STORIES[id]
}
