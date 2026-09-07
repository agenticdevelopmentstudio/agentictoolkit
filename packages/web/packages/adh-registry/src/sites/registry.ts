// Single source of truth for the ADH site family: display names, production
// hosts, which deploy environments exist, and which sites expose the shared
// auth-gated /home route. The header's site-switcher and the route-fallback
// not-found page both read from here.
//
// Hosts come from the deployment domain table in the repo CLAUDE.md (the
// authoritative source). Testing/staging hosts are derived by prepending
// `testing.`/`staging.` to the production host.

export type SiteId =
  | 'bitbag'
  | 'hub'
  | 'admin'
  | 'cookbook'
  | 'projects'
  | 'personaregistry'
  | 'consulting'
  | 'devteam'
  | 'toolkit'
  | 'myagenticteams'
  | 'mcp'
  | 'status'
  | 'builds'
  // <gen:union> managed by scaffold-sites.py — do not edit by hand
  | 'community'
  | 'support'
  | 'help'
  | 'hub-help'
  | 'news'
  | 'academy'
  | 'dashboards'
  | 'recipes'
  | 'personas'
  | 'communities'
  | 'ecosystems'
  | 'registries'
  | 'storage'
  | 'customers'
  | 'products'
  | 'billing'
  | 'domains'
  | 'authentication'
  | 'sites'
  | 'devices'
  | 'notifications'
  | 'knowledgebases'
  | 'tools'
  | 'education'
  | 'teamregistry'
  | 'teambuilder'
  | 'codereviews'
  | 'personabuilder'
  | 'research'
  | 'consultants'
  | 'orgs'
  | 'notebook'
  | 'integrations'
  | 'games'
  | 'gamification'
  | 'store'
  | 'stores'
  | 'testing'
  | 'registry'
  | 'docs'
  | 'messaging'
  | 'messages'
  | 'shipr'
  // </gen:union>
  | 'narratives'
  // fishlamp / fishlampdesign: FishLamp Design, the studio that publishes the whole
  // family (the brand that replaced Agentic Developer Studio). Both domains serve the
  // same site. `external: true` — they are link-outs, not apps in this repo.
  | 'fishlamp'
  | 'fishlampdesign'

export type SiteRedirect = {
  readonly source: string
  readonly destination: string
  readonly permanent: boolean
}

export interface SiteDef {
  id: SiteId
  /** Name shown in the switcher dropdown list. Short by convention (e.g. "Hub",
   *  "Cookbook"). */
  label: string
  /** Full brand name shown as the header's current-site title (the switcher
   *  trigger), e.g. "Agentic Developer Team". Defaults to `label`. */
  fullLabel?: string
  /** Even shorter name for the footer interlink row; defaults to `label`. */
  shortLabel?: string
  /** Short tagline shown alongside the label in the switcher. */
  description?: string
  /** Production host, no protocol. testing/staging prepend `testing.`/`staging.`. */
  prodHost: string
  /** A `staging.<prodHost>` deployment exists. */
  hasStaging: boolean
  /** A `testing.<prodHost>` deployment exists. */
  hasTesting: boolean
  /** Site exposes the shared auth-gated /home route (drives route carry). */
  hasHome: boolean
  /** The site's authenticated WORKSPACE route — the path a cross-site switch carries
   *  the active workspace slug onto (see {@link siteWorkspaceHref}).
   *
   *  There is ONE shape now: `/<slug>`, `app/[workspace]/[[...path]]`, the same bytes in
   *  every site that has one. The field once held three, because the PR #197 rollout could
   *  not use one — cookbook, personaregistry and research nested theirs under `/home/<slug>`
   *  to keep their own one-segment routes, and the hub hung its workspace off a public
   *  profile at `/<slug>/home`. Both of those are gone: the root segment addresses a
   *  principal on every site, and everything else took a static prefix.
   *
   *  So the remaining distinction is not the SHAPE but who can read a slug back OUT of a
   *  path (see {@link siteWorkspaceSlug}):
   *   - `'root'` — the template's sites. Their static top-level routes are the family's,
   *     which is exactly {@link SITE_LANDING_SEGMENTS}, so this package can tell a slug
   *     from a page.
   *   - `'hub'`  — the hub, which serves top-level routes no other site has (`/login`,
   *     `/explore`, `/settings`, …). Those are {@link HUB_ROUTE_SEGMENTS}, a second set
   *     for the second root; the parse that reads them sits in `@agentic-toolkit/adh`
   *     because it also answers for the two slug-less workspace routes.
   *  Absent ⇒ the site has NO workspace route, and a switch from a workspace falls back
   *  to its landing.
   *
   *  ⚠️ This is NOT derivable from `hasHome`, and must not be re-derived from it: `bitbag`,
   *  `status` and `admin` are workspace-less, while `hub-help` and `personaregistry` have
   *  neither — a `/home` and a `[workspace]` are separate facts about a site's route tree, and
   *  keying one off the other would send a workspace switch to a 404. The values are stamped
   *  from the actual route tree and held to it by `registry.test.ts` ("workspaceRoute matches
   *  the route tree").
   *
   *  `personaregistry` is the one site in the landing family without one, and its reason is
   *  worth knowing because it is structural rather than a rollout leftover: its root segment
   *  is a PUBLIC persona/user handle, and Next permits one dynamic name per level. See the
   *  comment on its entry below. */
  workspaceRoute?: 'root' | 'hub'
  /** The site's `[workspace]` segment is a PUBLISHED PUBLIC HANDLE, not a private
   *  workspace — `/<workspace>` is a public index and its children are public pages,
   *  not an authenticated shell. That flips two things the template otherwise does
   *  unconditionally at `app/[workspace]/layout.tsx`:
   *   - the segment is NOT gated there (no `WorkspaceOrProfileGate`, no
   *     `PublicProfileEscape`) — each private child gates itself instead;
   *   - the segment is NOT blanket-noindexed there — a public handle and its public
   *     children must be crawlable, so the layout emits no metadata at all and lets
   *     each child decide its own `robots`.
   *  A consequence, not a separate declaration: the site mounts NO
   *  `[workspace]/[[...path]]` catch-all. Next allows exactly one dynamic segment
   *  name per directory level, and this site's public child is a NAMED dynamic
   *  segment (research: `[paperSlug]`), which already claims that slot.
   *
   *  `research` is the site this exists for. `personaregistry` solved the identical
   *  problem the other way — by giving up `[workspace]` entirely and moving its public
   *  handle to `app/[slug]` (see its entry below) — which works when nothing needs the
   *  authenticated workspace shape at the root. Research still does (`workspaceRoute:
   *  'root'`, `hasHome: true`, an authenticated `home/` and `edit/`), so it keeps
   *  `[workspace]` and spends it on the public handle instead.
   *
   *  Absent or false ⇒ the template's default, gated arrangement — the same for all
   *  other sites with a `[workspace]` route today. */
  publicWorkspaceSegment?: true
  /** Part of the derived family roster ({@link LISTED_SITES}, and the footer
   *  interlinks under it). Defaults to true; set false to keep a site in the registry
   *  — so its own header still resolves a label and its pages keep serving — while
   *  leaving that roster.
   *
   *  ⚠️ It does NOT hide a site from the site menu, despite the name. That tree is
   *  hand-authored (`fleetMenuGroups.ts`) and names its rows one at a time, so a
   *  delisted site appears there exactly when someone wrote it in — which several do,
   *  on purpose. Delisting is about the roster, not about reachability. */
  listed?: boolean
  /** Render a divider above this entry in the switcher dropdown — used to set
   *  a site apart from the rest of the family. */
  dividerBefore?: boolean
  /** Opens a labelled group in the footer "sites overview" popover. Set on the
   *  FIRST entry of each group; following entries (without their own label) join
   *  it. Entries before the first labelled group render as an unlabelled lead. */
  sectionLabel?: string
  /** Marks the one entry that is the BRAND the family sits under (FishLamp
   *  Design), rather than a member of it. ⚠️ Declared intent only: nothing reads
   *  this today (the switcher menus are curated per-site props, not derived from
   *  the registry), so it renders as an ordinary row. Kept as the marker for
   *  whoever styles it. */
  featured?: boolean
  /** NOT an app in this repo — a link-out to a site we merely own (FishLamp
   *  Design). It is a normal entry in the footer "sites overview" and resolves
   *  through `buildSiteHref` like any other, but it never participates in
   *  cross-site SSO: `ssoReturnOrigins` excludes it, so its origin is never
   *  added to the central `adh` OAuth client's allowed-return list. Fail closed
   *  — an origin that can't complete an ADH login has no business being a legal
   *  `return` target. (It also has no `frontend/src/*` folder, so it is absent
   *  from MAIN_SITE_IDS/MARKETING_SITE_IDS and from the generated route map.) */
  external?: boolean
  /** Is a live, crawlable HTML site. Defaults to true; set false for hosts that
   *  aren't an indexable web page (e.g. the MCP server endpoint) so they're
   *  excluded from the SEO interlink row in the footer. */
  crawlable?: boolean
  /** An operations console only an adh admin has any use for. Two effects, both
   *  from this one fact: the site is dropped from {@link FOOTER_SITES} (so it is
   *  absent from the footer "sites overview" and from the SEO interlink set), and
   *  it is what {@link ADMIN_SITE_IDS} — the site menu's admin-gated section —
   *  is derived from. NOT a permission: the console does its own authorization.
   *  This only decides who is shown the door. */
  adminOnly?: boolean
}

// Display order = switcher order, grouped into divider-separated sections:
//   1. bitbag — the Agentic Developer persona, set apart at the very top.
//   2. the core site family (hub … research).
//   3. consultants — the services CTA, its own section above the studio brand.
//   4. fishlamp — FishLamp Design, the studio the family sits under (marked
//      `featured`, currently unrendered), followed by its second domain.
//   5. admin + status + builds — the operational consoles, set apart at the end.
// `dividerBefore` on the first entry of a section draws the separator above it.
// There is no `studio` entry: FishLamp Design replaced Agentic Developer Studio
// and the studio app was deleted from the repo, so agenticdeveloper.studio and
// agenticdevelopmentstudio.com are no longer sites this family knows about. Both
// domains are dead — nothing redirects them at fishlamp.com. Do not re-add them.
export const SITES: SiteDef[] = [
  // --- bitbag: the ADH persona, its own section at the top. Opens the
  // "Core platform" group in the footer sites-overview popover. ---
  { id: 'bitbag', label: 'Bitbag', fullLabel: 'Bitbag', description: 'The Agentic Developer persona', prodHost: 'bitbag.ai', hasStaging: true, hasTesting: true, hasHome: false, sectionLabel: 'Core platform' },
  // --- the core site family ---
  { id: 'hub', label: 'Hub', fullLabel: 'Agentic Developer Hub', description: 'The Agentic Developer Hub', prodHost: 'agenticdeveloperhub.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'hub', dividerBefore: true },
  { id: 'cookbook', label: 'Cookbook', fullLabel: 'Agentic Developer Cookbook', description: 'Recipes & patterns', prodHost: 'agenticdevelopercookbook.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'projects', label: 'Projects', fullLabel: 'Agentic Developer Projects', description: 'Project planning', prodHost: 'agenticdeveloperprojects.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  // narratives: the ecosystem-story site at agenticdevelopernarratives.com
  // (deployed in a later phase). It's ALSO an in-hub feature workspace at
  // /<slug>/narratives (see HUB_FEATURE_SEGMENT + the [slug]/(workspace)/narratives
  // route, which auth-gates an iframe of the published static bundle) — a temporary bridge
  // until it's backed by the adh backend. Has testing+staging+production Vercel
  // tiers (hasTesting:true) so cross-site SSO allows testing.<domain>.
  // Its prod domain is live now, so it is crawlable (the default) and carries a
  // real description rather than its own host — it is a footer interlink like
  // every other content site.
  { id: 'narratives', label: 'Narratives', fullLabel: 'Agentic Developer Narratives', description: 'Ecosystem stories', prodHost: 'agenticdevelopernarratives.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  // personaregistry spends its root segment on PUBLIC handles — `/<persona>` and
  // `/<owner>/<persona>` are the addresses the whole site exists to publish — so it has no
  // `app/[workspace]` and no `/home`. Next allows one dynamic name per level, so the root is
  // the family's workspace or the registry's handles, and here it is the handles. Nothing was
  // lost with them: personas are configured on agenticdeveloperpersonas.com and accounts on
  // the hub, so the signed-in surface this site used to mount rendered a placeholder.
  { id: 'personaregistry', label: 'Persona Registry', fullLabel: 'Agentic Persona Registry', description: 'Browse agentic personas', prodHost: 'agenticpersonaregistry.com', hasStaging: true, hasTesting: true, hasHome: false },
  { id: 'devteam', label: 'Team', fullLabel: 'Agentic Developer Team', description: 'Your agentic dev team', prodHost: 'agenticdeveloperteam.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'toolkit', label: 'Toolkit', fullLabel: 'Agentic Developer Toolkit', description: 'The developer toolkit', prodHost: 'agenticdevelopertoolkit.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  // myagenticteams: off-pattern consumer brand (not agenticdeveloper<x>.com), so
  // `fullLabel` is required — siteHeaderTitle can't derive the brand from the host.
  { id: 'myagenticteams', label: 'My Teams', fullLabel: 'My Agentic Teams', description: 'Build your own agentic teams', prodHost: 'myagenticteams.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'mcp', label: 'MCP', fullLabel: 'Agentic Developer MCP', description: 'MCP server', prodHost: 'mcp.agenticdeveloperhub.com', hasStaging: true, hasTesting: false, hasHome: false, crawlable: false },
  // <gen:sites> managed by scaffold-sites.py — do not edit by hand
  { id: 'community', label: 'Community', fullLabel: 'Agentic Developer Community', description: 'Forums & discussion', prodHost: 'agenticdevelopercommunity.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', dividerBefore: true, sectionLabel: 'Developer platform' },
  { id: 'support', label: 'Support', fullLabel: 'Agentic Developer Support', description: 'Get support', prodHost: 'agenticdevelopersupport.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'help', label: 'Help', fullLabel: 'Agentic Developer Help', description: 'Help topics', prodHost: 'agenticdeveloperhelp.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', listed: false },
  { id: 'hub-help', label: 'Help', fullLabel: 'Agentic Developer Hub Help', description: 'Help topics', prodHost: 'help.agenticdeveloperhub.com', hasStaging: true, hasTesting: true, hasHome: false },
  { id: 'news', label: 'News', fullLabel: 'Agentic Developer News', description: 'News & updates', prodHost: 'agenticdevelopernews.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'academy', label: 'Academy', fullLabel: 'Agentic Developer Academy', description: 'Learn agentic dev', prodHost: 'agenticdeveloperacademy.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'dashboards', label: 'Dashboards', fullLabel: 'Agentic Developer Dashboards', description: 'Status dashboards', prodHost: 'agenticdeveloperdashboards.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'recipes', label: 'Recipes', fullLabel: 'Agentic Developer Recipes', description: 'Developer recipes', prodHost: 'agenticdeveloperrecipes.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', listed: false },
  { id: 'personas', label: 'Personas', fullLabel: 'Agentic Developer Personas', description: 'Define your personas', prodHost: 'agenticdeveloperpersonas.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'communities', label: 'Communities', fullLabel: 'Agentic Developer Communities', description: 'Build communities', prodHost: 'agenticdevelopercommunities.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'ecosystems', label: 'Ecosystems', fullLabel: 'Agentic Developer Ecosystems', description: 'Build ecosystems', prodHost: 'agenticdeveloperecosystems.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'registries', label: 'Registries', fullLabel: 'Agentic Developer Registries', description: 'Build registries', prodHost: 'agenticdeveloperregistries.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'storage', label: 'Storage', fullLabel: 'Agentic Developer Storage', description: 'Manage storage', prodHost: 'agenticdeveloperstorage.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'customers', label: 'Customers', fullLabel: 'Agentic Developer Customers', description: 'Manage customers', prodHost: 'agenticdevelopercustomers.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'products', label: 'Products', fullLabel: 'Agentic Developer Products', description: 'Define products', prodHost: 'agenticdeveloperproducts.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'billing', label: 'Billing', fullLabel: 'Agentic Developer Billing', description: 'Customer billing', prodHost: 'agenticdeveloperbilling.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'domains', label: 'Domains', fullLabel: 'Agentic Developer Domains', description: 'Custom domains', prodHost: 'agenticdeveloperdomains.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'authentication', label: 'Authentication', fullLabel: 'Agentic Developer Authentication', description: 'Customer auth', prodHost: 'agenticdeveloperauthentication.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'sites', label: 'Sites', fullLabel: 'Agentic Developer Sites', description: 'Quick landing pages', prodHost: 'agenticdevelopersites.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'devices', label: 'Devices', fullLabel: 'Agentic Developer Devices', description: 'Connect devices', prodHost: 'agenticdeveloperdevices.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'notifications', label: 'Notifications', fullLabel: 'Agentic Developer Notifications', description: 'Send notifications', prodHost: 'agenticdevelopernotifications.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'knowledgebases', label: 'Knowledge Bases', fullLabel: 'Agentic Developer Knowledge Bases', description: 'Knowledge bases', prodHost: 'agenticdeveloperknowledgebases.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'tools', label: 'Tools', fullLabel: 'Agentic Developer Tools', description: 'Developer tools', prodHost: 'agenticdevelopertools.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'education', label: 'Education', fullLabel: 'Agentic Developer Education', description: 'Educational products', prodHost: 'agenticdevelopereducation.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', listed: false },
  { id: 'teamregistry', label: 'Team Registry', fullLabel: 'Agentic Team Registry', description: 'Register agentic teams', prodHost: 'agenticteamregistry.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'teambuilder', label: 'Team Builder', fullLabel: 'Agentic Team Builder', description: 'Build agentic teams', prodHost: 'agenticteambuilder.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'codereviews', label: 'Code Reviews', fullLabel: 'Agentic Developer Code Reviews', description: 'Code reviews', prodHost: 'agenticdevelopercodereviews.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'personabuilder', label: 'Persona Builder', fullLabel: 'Agentic Persona Builder', description: 'Configure personas', prodHost: 'agenticpersonabuilder.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'research', label: 'Research', fullLabel: 'Agentic Developer Research', description: 'Store & review research', prodHost: 'agenticdeveloperresearch.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', publicWorkspaceSegment: true },
  { id: 'consultants', label: 'Consultants', fullLabel: 'Agentic Development Consultants', description: 'Find consultants', prodHost: 'agenticdeveloperconsultants.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'orgs', label: 'Organizations', fullLabel: 'Agentic Developer Organizations', description: 'Manage organizations', prodHost: 'agenticdeveloperorgs.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'notebook', label: 'Notebook', fullLabel: 'Agentic Developer Notebook', description: 'Notes & notebooks', prodHost: 'agenticdevelopernotes.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'integrations', label: 'Integrations', fullLabel: 'Agentic Developer Integrations', description: 'Manage integrations', prodHost: 'agenticdeveloperintegrations.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'games', label: 'Games', fullLabel: 'Agentic Developer Games', description: 'Build your games', prodHost: 'agenticdevelopergames.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'gamification', label: 'Gamification', fullLabel: 'Agentic Developer Gamification', description: 'Product gamification', prodHost: 'agenticdevelopergamification.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'store', label: 'Store', fullLabel: 'Agentic Developer Store', description: 'Hub merch & gear', prodHost: 'agenticdeveloperstore.com', hasStaging: true, hasTesting: true, hasHome: false, workspaceRoute: 'root' },
  { id: 'stores', label: 'Stores', fullLabel: 'Agentic Developer Stores', description: 'Sell your products', prodHost: 'agenticdeveloperstores.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'testing', label: 'Testing', fullLabel: 'Agentic Developer Testing', description: 'Test plans & bugs', prodHost: 'agenticdevelopertesting.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'registry', label: 'Registry', fullLabel: 'Agentic Developer Registry', description: 'Registered hub developers', prodHost: 'agenticdeveloperregistry.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'docs', label: 'Docs', fullLabel: 'Agentic Developer Docs', description: 'Organize your documents', prodHost: 'agenticdeveloperdocs.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'messaging', label: 'Messaging', fullLabel: 'Agentic Developer Messaging', description: 'Email & SMS integrations', prodHost: 'agenticdevelopermessaging.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'messages', label: 'Messages', fullLabel: 'Agentic Developer Messages', description: 'Send & receive messages', prodHost: 'agenticdevelopermessages.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  { id: 'shipr', label: 'Shipr', fullLabel: 'Agentic Developer Shipr', description: 'Move code to production', prodHost: 'shipr.agenticdeveloperhub.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root' },
  // </gen:sites>
  // --- consulting: FOLDED into the studio brand (brand-story-plan portfolio
  // pruning) — stays registered (its own header resolves, /details keep serving)
  // but it leaves the switcher + footer. ---
  { id: 'consulting', label: 'Consulting', description: 'Let us help you', prodHost: 'agenticdeveloperconsulting.com', hasStaging: true, hasTesting: true, hasHome: true, workspaceRoute: 'root', listed: false },
  // --- FishLamp Design: the studio the whole family sits under, and the name in
  // every footer's copyright. Featured (centered, gold, italic, name-only) in the
  // switcher; carries a description for the overview popover. Opens the
  // "Studio & consulting" group. Both domains serve the SAME site — fishlamp.com
  // is the canonical one, fishlampdesign.com the longer second door. `external`:
  // neither is an app in this repo, so neither joins the SSO return allowlist. ---
  { id: 'fishlamp', label: 'FishLamp Design', shortLabel: 'FishLamp', description: 'The studio behind the Hub', prodHost: 'fishlamp.com', hasStaging: false, hasTesting: false, hasHome: false, external: true, dividerBefore: true, sectionLabel: 'Studio & consulting', featured: true },
  { id: 'fishlampdesign', label: 'fishlampdesign.com', description: 'FishLamp Design — second domain', prodHost: 'fishlampdesign.com', hasStaging: false, hasTesting: false, hasHome: false, external: true },
  // --- operational consoles, their own section at the very end ---
  // `status` heads the section because it is the only PUBLIC one: it carries the
  // section's `sectionLabel`, and the two `adminOnly` consoles below it are dropped
  // from FOOTER_SITES — a head that vanished from that roster would leave the ones
  // after it in an unlabelled tail.
  { id: 'status', label: 'Status', fullLabel: 'Agentic Developer Status', description: 'System status', prodHost: 'status.agenticdeveloperhub.com', hasStaging: true, hasTesting: true, hasHome: false, dividerBefore: true, sectionLabel: 'Operations' },
  // admin is a wholly-authenticated console — its dashboard root IS its home,
  // so the switcher links it to '/' rather than a separate /home.
  { id: 'admin', label: 'Admin', fullLabel: 'Agentic Developer Admin', description: 'Operations console', prodHost: 'admin.agenticdeveloperhub.com', hasStaging: true, hasTesting: true, hasHome: false, adminOnly: true },
  { id: 'builds', label: 'Builds', fullLabel: 'Agentic Developer Builds', description: 'Build status', prodHost: 'builder.agenticdeveloperhub.com', hasStaging: false, hasTesting: true, hasHome: false, adminOnly: true },
]

export type SiteBuildConfig = {
  readonly legacyHomePaths?: boolean
  readonly extraRedirects?: readonly SiteRedirect[]
  readonly requiresBackendUrl?: boolean
  /**
   * True for the six sites that keep a hand-written `next.config.ts` (Task 6a):
   * `admin`, `bitbag`, `hub-help`, `status`, `cookbook`, `hub` (`learntruefacts` was a
   * seventh until it left the fleet on 2026-08-14). Each
   * still calls `adhNextConfig()` for the shared dependency gate, headers and env, but
   * layers its own `rewrites`/`redirects`/`env`/`transpilePackages` on top rather than
   * taking the uniform three-line template. Consumed by Task 7 and by
   * `frontend/testing/probe-auth-fleet.py`'s `applies_bff()` (Task 6b/A4): a site with
   * `handRolledConfig` is checked by its own config text, not by "has a folder + calls
   * `adhNextConfig()`".
   */
  readonly handRolledConfig?: boolean
}

/**
 * Per-site build data, read by `@agentic-toolkit/adh-next-config` so each site's
 * `next.config.ts` can stay byte-exact: per-site DATA read by uniform CODE.
 *
 * DELIBERATELY NOT fields on `SiteDef`. Most `SITES` entries live inside the
 * `<gen:sites>` region above, which `frontend/tools/scaffold-sites.py:608`
 * regenerates wholesale from a fixed template blind to these fields — a field
 * written up there is silently dropped on the next scaffold run, with no error and
 * no failing test. Keeping the data in this table, below the close marker, is what
 * makes that impossible rather than merely discouraged.
 *
 * `cookbook` and `hub` are absent on purpose (Ruling T4-a): their redirects derive
 * from site-local modules (`OVERVIEW_PATH`, `featureIds`) this package cannot
 * import, and freezing those values here would re-create the drift their own
 * comments exist to prevent. They keep hand-written configs and still get the
 * shared config's dependency gate.
 */
export const SITE_BUILD: Partial<Record<SiteId, SiteBuildConfig>> = {
  // Every panel on this site reads /api/billing/*, so a hosted build with no API_BACKEND_URL
  // would deploy a site whose calls all proxy to localhost — green build, permanently empty
  // panel. The flag makes that a build failure instead.
  billing: { requiresBackendUrl: true },
  bitbag: { requiresBackendUrl: true, handRolledConfig: true },
  // `requiresBackendUrl` on these two is not decoration: BOTH shipped a
  // `src/lib/backend-url.ts` that threw UNCONDITIONALLY when `API_BACKEND_URL` was
  // unset, and their old configs imported it. Taking the byte-exact template deleted
  // that import, and without this flag a hosted build would resolve the fallback and
  // deploy a site whose every `/api/*` call proxies to `http://localhost:3000`. The
  // flag is weaker than what they had — `resolveBackendUrl` only throws under
  // `VERCEL_ENV`, so local dev now falls back like the other 41 templated sites do —
  // but it restores the half that was load-bearing, which is the hosted build. The two
  // sites that keep the stricter unconditional throw (admin, hub) do it by staying
  // hand-rolled; a templated site has no place to put it.
  projects: { legacyHomePaths: true, requiresBackendUrl: true },
  narratives: { legacyHomePaths: true, requiresBackendUrl: true },
  personaregistry: {
    requiresBackendUrl: true,
    extraRedirects: [
      { source: '/persona/:path+', destination: '/:path+', permanent: false },
      { source: '/user/:path+', destination: '/:path+', permanent: false },
      { source: '/org/:path+', destination: '/:path+', permanent: false },
    ],
  },
  help: {
    extraRedirects: [
      { source: '/api', destination: 'https://help.agenticdeveloperhub.com/rest-api', permanent: true },
      { source: '/docs', destination: 'https://help.agenticdeveloperhub.com/quickstart', permanent: true },
      { source: '/docs/quickstart', destination: 'https://help.agenticdeveloperhub.com/quickstart', permanent: true },
      { source: '/docs/hub-features', destination: 'https://help.agenticdeveloperhub.com/hub', permanent: true },
      { source: '/docs/api', destination: 'https://help.agenticdeveloperhub.com/rest-api', permanent: true },
      { source: '/docs/mcp', destination: 'https://help.agenticdeveloperhub.com/mcp', permanent: true },
      { source: '/docs/errors', destination: 'https://help.agenticdeveloperhub.com/reference/errors', permanent: true },
      { source: '/docs/webhooks', destination: 'https://help.agenticdeveloperhub.com/reference/webhooks', permanent: true },
      { source: '/docs/changelog', destination: 'https://help.agenticdeveloperhub.com/reference/changelog', permanent: true },
      { source: '/docs/oauth/:step*', destination: 'https://help.agenticdeveloperhub.com/quickstart/oauth/:step*', permanent: true },
    ],
  },
  dashboards: { legacyHomePaths: true },
  ecosystems: { legacyHomePaths: true },
  knowledgebases: { legacyHomePaths: true },
  teamregistry: { legacyHomePaths: true },
  personabuilder: { legacyHomePaths: true },
  research: { legacyHomePaths: true },
  // The hand-rolled sites (Ruling T4-a / Task 6a) — six here plus `bitbag` above.
  // `learntruefacts` was a seventh until it left the fleet on 2026-08-14. `cookbook`
  // and `hub` carry no
  // other fields here on purpose — their redirects derive from site-local modules
  // (`OVERVIEW_PATH`, `featureIds`) this package cannot import; freezing those values
  // here would re-create the drift their own comments exist to prevent.
  admin: { handRolledConfig: true },
  'hub-help': { handRolledConfig: true },
  status: { handRolledConfig: true },
  cookbook: { handRolledConfig: true },
  hub: { handRolledConfig: true },
}

/** Build data for a site; `{}` for the sites that need no per-site build behaviour. */
export function siteBuildConfig(id: SiteId): SiteBuildConfig {
  return SITE_BUILD[id] ?? {}
}

/** The family roster — every site that counts as a public member of the family, in
 *  display order. What consumes it is the footer/overview surfaces below; the site
 *  menu does NOT (see {@link SiteDef.listed}). */
export const LISTED_SITES: SiteDef[] = SITES.filter((s) => s.listed !== false)

/** The crawlable sites to interlink from the footer, in display order. The roster
 *  above minus non-HTML endpoints (e.g. the MCP server) and minus the admin-only
 *  consoles, which have their own gated menu section and no business in a public
 *  overview or an SEO interlink set. These render as real server-side `<a href>`
 *  links to absolute production hosts so search engines can follow them between
 *  properties. */
export const FOOTER_SITES: SiteDef[] = LISTED_SITES.filter(
  (s) => s.crawlable !== false && s.adminOnly !== true,
)

/** The operations consoles, in display order — the site menu's admin-gated section.
 *  Derived from {@link SiteDef.adminOnly} rather than hand-listed beside it, so the
 *  set the menu shows an admin and the set the footer overview hides are the same
 *  fact stated once. (The section's third row, the fleet monitor, is not a registry
 *  site at all — see `fleetMenuGroups.ts`.) */
export const ADMIN_SITE_IDS: SiteId[] = SITES.filter((s) => s.adminOnly === true).map((s) => s.id)

export function getSite(id: SiteId): SiteDef | undefined {
  return SITES.find((s) => s.id === id)
}

/** Runtime guard for a `SiteId` — required wherever a value comes from outside the type
 *  system (a directory name, a CLI arg, …) and needs narrowing before it can index the
 *  registry. Derived from `SITES` itself rather than a second hand-kept list, so it can
 *  never drift from the ids the registry actually knows about. */
export function isSiteId(value: string): value is SiteId {
  return SITES.some((s) => s.id === value)
}

/** The apex domain minus its TLD — which is exactly what a site's Next app folder
 *  is named. `help.agenticdeveloperhub.com` → `help.agenticdeveloperhub`. */
function dirNameOf(site: SiteDef): string {
  return site.prodHost.replace(/\.[a-z]+$/, '')
}

/** Which site owns the directory called `name`?
 *
 *  A site's id and its folder name are two different strings, and have been since
 *  the folders were renamed to match the domains they serve (`billing` builds in
 *  `agenticdeveloperbilling/`). The join is the `prodHost` already declared here,
 *  so this needs no second list to keep in step — and it is the ONLY place the
 *  convention is spelled, because a caller that re-derives it (strip a leading
 *  `agenticdeveloper`, say) gets `agenticpersonabuilder` and the four hub
 *  subdomain sites wrong.
 *
 *  A bare id still resolves to itself: a checkout may predate the rename, and
 *  answering for both costs one comparison. Returns undefined for anything that
 *  is neither — the caller decides whether not-a-site is an error. */
export function siteIdForDir(name: string): SiteId | undefined {
  if (isSiteId(name)) return name
  return SITES.find((s) => dirNameOf(s) === name)?.id
}

/** The two physical site families — the ids whose Next app folders live under
 *  `websites/main/` and `websites/marketing/`. The dev-only site-menu submenus
 *  ("Main sites" / "Marketing sites", shown only in staging/testing/local — see
 *  {@link ../header/debugSiteGroups}) link every one to its deployment in the
 *  CURRENT env, so a developer can jump straight to any site's build. A registry
 *  test asserts these arrays against adh's directory listing, so a newly-scaffolded
 *  site can't silently drop out of the menu. Alphabetical, mirroring that listing.
 *
 *  Membership here means "this id HAS a Next app", not "its app is checked out
 *  beside this file": `bitbag` and `myagenticteams` are built from their own repos
 *  since 2026-08-15 and are full members regardless, which is why the test names
 *  them rather than the registry doing it — where a site's source sits is a fact
 *  about one checkout, and this file is shared by all of them. `mcp` and `builds`
 *  have no site folder ANYWHERE (an endpoint and a backend), so they're in neither
 *  list. `messaging` was a third until 2026-08-22, when it stopped being an
 *  in-hub-only feature and got a deck, a domain and a directory of its own. The hub
 *  view at `/<slug>/messaging` is still there, but it is `messages`'s now (see
 *  HUB_FEATURE_SEGMENT): the id was reused for a site about configuring email & SMS,
 *  and sending and receiving messages — which is what that route does — went to
 *  `messages`. A site and its hub view were always two things rather than a choice,
 *  which is why the route did not have to move when the id changed hands. */
export const MAIN_SITE_IDS: SiteId[] = [
  'admin', 'bitbag', 'community', 'cookbook', 'devteam', 'help', 'hub', 'hub-help',
  'myagenticteams', 'news', 'personaregistry', 'shipr', 'status', 'support', 'toolkit',
]
export const MARKETING_SITE_IDS: SiteId[] = [
  'academy', 'authentication', 'billing', 'codereviews', 'communities', 'consultants', 'consulting',
  'customers', 'dashboards', 'devices', 'docs', 'domains', 'ecosystems', 'education', 'games',
  'gamification', 'integrations', 'knowledgebases', 'messages', 'messaging', 'narratives',
  'notebook', 'notifications',
  'orgs', 'personabuilder', 'personas', 'products', 'projects', 'recipes', 'registries',
  'registry', 'research', 'sites', 'storage', 'store', 'stores', 'teambuilder', 'teamregistry',
  'testing', 'tools',
]

/** The family grouped for the footer "sites overview", in display order.
 *  ⚠️ These groups MIRROR the site menu's tree (`fleetMenuGroups.ts`) — same
 *  labels, same membership, same order — because the two are the same answer to
 *  the same question ("where does this site live?") shown on two surfaces, and a
 *  visitor who learns the menu should recognise the overview. The menu's two
 *  top-level leaves (Bitbag, Organizations) have no group of their own there, so
 *  they join Hub here; everything else lines up row for row.
 *
 *  The mirror is a convention held by a test, not a derivation: the menu is a
 *  React config in another package (icons, absolute hrefs, hub routes) and this
 *  is pure data the registry owns. Change one, change the other.
 *
 *  Order-independent of the SITES array (the scaffolded sites live in one gen
 *  block), so grouping is by membership here. Every listed site should appear in
 *  exactly one category (guarded by a test); supersedes the per-entry
 *  `dividerBefore`/`sectionLabel` hints for these two surfaces.
 *
 *  Two kinds of site the MENU carries are deliberately absent here, because both
 *  are absent from {@link FOOTER_SITES} and naming them would declare membership
 *  of a group that can never render (a test pins it):
 *
 *  - the admin-only consoles (`admin`, `builds`) — their menu section is derived
 *    from {@link ADMIN_SITE_IDS} instead;
 *  - the folded sites (`help`, `recipes`, `education`, `consulting`), which are
 *    `listed: false`: still registered and still reachable, so a menu row may
 *    point AT them, but they are no longer part of the roster the family shows.
 *
 *  The gap runs BOTH ways, and neither list is a subset of the other (the menu
 *  side says the same thing in `fleetMenuGroups.ts`). Coming the other way, three
 *  sites are categorized here with no menu row at all — `mcp` (an endpoint, not a
 *  page), `fishlamp` and `fishlampdesign` — so a category member is not a promise
 *  of a row any more than a row is a promise of a category. Only the GROUPING is
 *  shared: same labels, same order, and a site in the same group on both surfaces
 *  (`registry.test.ts` pins the labels and the exactly-once membership; it does
 *  not, and cannot, pin a row-for-member correspondence, because there isn't one). */
export const SITE_CATEGORIES: { label: string; ids: SiteId[] }[] = [
  {
    // The hub and the surfaces that ARE the hub — plus the three rows the menu
    // promotes to its top level (bitbag and messages above Hub, orgs below it),
    // which have no group of their own to mirror. `store` is the hub's own merch
    // shop: the one place in the family that ships something you can hold, run by
    // the hub.
    label: 'Hub',
    ids: ['bitbag', 'messages', 'hub', 'news', 'status', 'community', 'hub-help', 'support', 'store', 'orgs'],
  },
  // The menu's Learn topic, minus both of its other rows: the topic's own trigger
  // is the folded `help` landing, and its Help row is hub-help, which sits in Hub
  // above — one destination reached from two groups, and a site may be in only
  // one category, so it is grouped where it lives rather than where it repeats.
  { label: 'Learn', ids: ['academy'] },
  { label: 'Plan', ids: ['projects', 'narratives', 'notebook', 'research', 'docs'] },
  // mcp has no menu row of its own (it is an endpoint, not a page — `crawlable:
  // false` keeps it out of the overview too), and Build is where the rest of the
  // developer tooling sits, so that is where it is filed.
  {
    label: 'Build',
    ids: ['devteam', 'codereviews', 'cookbook', 'toolkit', 'tools', 'testing', 'shipr', 'mcp'],
  },
  {
    label: 'Personas',
    ids: ['personas', 'personabuilder', 'personaregistry', 'knowledgebases', 'teambuilder', 'teamregistry', 'myagenticteams'],
  },
  // Everything a product IS or is configured with: gamification is configured PER
  // PRODUCT, `stores` is the storefront ON a product, `education` is a product
  // kind — none of them is a Build concern.
  {
    label: 'Products',
    ids: ['products', 'storage', 'ecosystems', 'authentication', 'customers', 'billing', 'messaging', 'notifications', 'sites', 'communities', 'dashboards', 'devices', 'domains', 'integrations', 'registries', 'gamification', 'games', 'stores'],
  },
  // Hire absorbed the old "Studio & consulting" group: the studio brand and the
  // two people-directories are one answer to "get someone to do this". The menu's
  // topic trigger (the folded `consulting` landing) and its Agentic Development
  // Studio row are both absent — the first is delisted, the second has no registry
  // entry at all.
  {
    label: 'Hire',
    ids: ['consultants', 'registry', 'fishlamp', 'fishlampdesign'],
  },
]

export type SiteGroup = { label: string; sites: SiteDef[] }

/** Partition `sites` into the SITE_CATEGORIES groups, in category + member order,
 *  dropping empty groups. Anything not categorized lands in a trailing "More"
 *  group so a new site is never silently dropped from the menu. */
export function groupSitesByCategory(sites: SiteDef[]): SiteGroup[] {
  const byId = new Map(sites.map((s) => [s.id, s]))
  const used = new Set<SiteId>()
  const groups: SiteGroup[] = []
  for (const cat of SITE_CATEGORIES) {
    const members: SiteDef[] = []
    for (const id of cat.ids) {
      const s = byId.get(id)
      if (s) {
        members.push(s)
        used.add(id)
      }
    }
    if (members.length) groups.push({ label: cat.label, sites: members })
  }
  const leftover = sites.filter((s) => !used.has(s.id))
  if (leftover.length) groups.push({ label: 'More', sites: leftover })
  return groups
}

/** The brand name shown in the header (the switcher trigger). Rule: any site on
 *  an `agenticdeveloper<x>.com` apex domain reads "Agentic Developer <X>",
 *  derived from the host so it's automatic for every such site (e.g.
 *  agenticdeveloperconsulting.com → "Agentic Developer Consulting"). An explicit
 *  `fullLabel` always wins (for off-pattern brands like the Persona Registry or
 *  Bitbag); otherwise we fall back to `label`. */
export function siteHeaderTitle(site: SiteDef): string {
  if (site.fullLabel) return site.fullLabel
  const rest = /^agenticdeveloper([a-z0-9-]+)\.com$/.exec(site.prodHost)?.[1]
  if (rest) {
    return `Agentic Developer ${rest.charAt(0).toUpperCase()}${rest.slice(1)}`
  }
  return site.label
}

/** The brand prefix the hero/graph render in plain weight, with the trailing
 *  word(s) accented (gold italic). */
const TITLE_PREFIX = 'Agentic Developer'

/** Split a site's brand title into the plain "Agentic Developer" lead + the
 *  accent word(s). Sites on the `agenticdeveloper<x>.com` pattern split into
 *  lead "Agentic Developer" + accent "<X>"; an off-pattern brand (e.g. the
 *  Persona Registry) has no lead and the whole name is the accent. The single
 *  source of truth for the SiteLanding/MarketingLanding + LandingGraph title
 *  shape — both render `{titleLead} <i>{titleAccent}</i>`. */
export function splitSiteTitle(site: SiteDef): { titleLead: string; titleAccent: string } {
  const full = siteHeaderTitle(site)
  if (full.startsWith(`${TITLE_PREFIX} `)) {
    return { titleLead: TITLE_PREFIX, titleAccent: full.slice(TITLE_PREFIX.length + 1) }
  }
  return { titleLead: '', titleAccent: full }
}

export type SiteEnv = 'production' | 'staging' | 'testing' | 'local'

/** Hash appended to switcher links so a target site's not-found page knows to
 *  walk the path up to the nearest existing route instead of showing a 404. */
export const SITE_SWITCH_HASH = '#site-switch'

/** Classify the current environment from a hostname (no protocol/port).
 *
 *  `.test` is here for the same reason `.local` is: RFC 6761 reserves it for
 *  testing, so no such name can ever be a deployed site. The local suite serves
 *  `dev.test` today and `dev.local` before that — matching the whole TLD rather
 *  than either suite domain keeps this classifier out of the business of knowing
 *  which one is current, which is `localOrigin`'s job and nothing else's. */
export function detectEnv(hostname: string): SiteEnv {
  const host = hostname.toLowerCase().replace(/:\d+$/, '')
  if (
    host === 'localhost' ||
    host.startsWith('127.') ||
    host === '::1' ||
    host.endsWith('.local') ||
    host.endsWith('.test') ||
    host.endsWith('.localhost')
  ) {
    return 'local'
  }
  if (host.startsWith('testing.')) return 'testing'
  if (host.startsWith('staging.')) return 'staging'
  return 'production'
}

/** Resolve the host for a target site in a given env, falling back
 *  testing → staging → production when the target lacks that env. */
function hostForEnv(site: SiteDef, env: SiteEnv): string {
  if (env === 'testing') {
    if (site.hasTesting) return `testing.${site.prodHost}`
    if (site.hasStaging) return `staging.${site.prodHost}`
    return site.prodHost
  }
  if (env === 'staging') {
    return site.hasStaging ? `staging.${site.prodHost}` : site.prodHost
  }
  return site.prodHost
}

/** Domains the `dev.local` tool serves a suite under, current one first.
 *
 *  `dev.test` is what it serves today; `dev.local` is the superseded spelling,
 *  kept because a bookmark, an open tab, or an install that has not been
 *  re-run still puts that host in the address bar — and a host this list does
 *  not recognise falls through to the bare-`localhost` branch below, i.e. every
 *  switcher link on the page silently points at the wrong origin.
 *
 *  Order matters only for readability: `localOrigin` matches on suffix and
 *  rebuilds with the domain it matched, so each spelling stays on itself
 *  rather than bouncing the user between two domains mid-session. */
const LOCAL_SUITE_DOMAINS = ['dev.test', 'dev.local'] as const

/** Build the local-dev origin for a target site from the current host. Two local
 *  schemes are supported:
 *
 *   - a `dev.local` suite (the `dev.local suite` dev server) on any domain in
 *     {@link LOCAL_SUITE_DOMAINS}: the hub apex is `<suite>.<domain>` and every
 *     other site is `<id>.<suite>.<domain>`, where `<suite>` is `hub` on main
 *     and `hub-<branch>` on other worktrees. Mirrors the routing in
 *     `dev.local/suite.toml` (apex = 'hub'); change both together.
 *   - bare `localhost` (single-site `next dev`, optionally carrying a port, e.g.
 *     "admin.localhost:5171"): hub is the bare apex, others are `<id>.localhost`. */
function localOrigin(target: SiteDef, currentHost: string): string {
  const sub = target.id === 'hub' ? '' : `${target.id}.`
  const host = currentHost.toLowerCase().replace(/:\d+$/, '')
  const domain = LOCAL_SUITE_DOMAINS.find((d) => host.endsWith(`.${d}`))
  if (domain) {
    // Current host is `<suite>.<domain>` (apex) or `<id>.<suite>.<domain>`
    // (child). `<suite>` is a single DNS label, so it's the label immediately
    // before the domain (robust even if a deeper subdomain ever appears).
    const base = host.slice(0, -(domain.length + 1))
    const suite = base.slice(base.lastIndexOf('.') + 1)
    return `https://${sub}${suite}.${domain}`
  }
  const port = currentHost.match(/:(\d+)$/)?.[1]
  const suffix = port ? `:${port}` : ''
  return `http://${sub}localhost${suffix}`
}

/** Map the current path onto the path to open on the target site.
 *  Only `/` and `/home` are guaranteed to exist on every chrome site, so:
 *   - root and site-specific deep routes → the target's landing `/`
 *   - `/home` (or `/home/*`) → the target's `/home`; deep `/home/*` routes
 *     carry the marker so the target up-walks if the exact route is missing. */
function carryPath(target: SiteDef, pathname: string): string {
  const path = pathname || '/'
  if (path === '/home' || path.startsWith('/home/')) {
    if (!target.hasHome) return '/'
    if (path === '/home') return '/home'
    return `${path}${SITE_SWITCH_HASH}`
  }
  return '/'
}

/** Build the absolute href to switch to `target` from the current location,
 *  preserving the environment and matching route per the rules above. */
export function buildSiteHref(target: SiteDef, currentHostname: string, pathname: string): string {
  const env = detectEnv(currentHostname)
  if (env === 'local') return `${localOrigin(target, currentHostname)}${carryPath(target, pathname)}`
  const host = hostForEnv(target, env)
  return `https://${host}${carryPath(target, pathname)}`
}

// ---------------------------------------------------------------------------
// Hub workspace routes (hand-managed — NOT scaffolded; keep outside gen blocks).
//
// Every fleet site's gated workspace ALSO exists inside the hub, under the active workspace slug
// at `/<slug>/<segment>`, and this table says which segment. It is the whole roster now rather
// than the eleven leftovers it held for a fortnight: the fleet's workspace implementations moved
// into `@agentic-toolkit/adh-site-homes`, so the hub mounts the SAME model the site mounts on its
// own domain (see the hub's FleetSiteRoute), and a signed-in user never has to leave
// agenticdeveloperhub.com to work. The sites keep their domains, their deployments and their
// landing decks; what changed is that the hub has a route onto each of them again.
//
// Three things read it, and the third is new:
//   - {@link HUB_WORKSPACE_SEGMENTS}, which names the second segments of a hub path that ARE
//     workspace routes — how the menu knows there is a workspace to carry at all.
//   - `useSiteMenu`'s hub branch: signed in, on the hub, inside a workspace, a site row resolves
//     to `/<slug>/<segment>` — a ROUTE — instead of hopping to the site's origin. Signed out and
//     from every other site the menu is still the cross-site navigator {@link siteWorkspaceHref}
//     describes.
//   - `frontend/tools/gen-hub-fleet-routes.py`, which writes the hub's route directory per entry
//     that does not already have one, and `--check`s that the tree and this table agree.
//
// The DEFAULT is `<site id>: '<site id>'`. Every entry that departs from it says why below, and
// the departures are all of one kind: the hub already routed that feature under a name of its own
// before its site existed, and reusing the existing route is what keeps today's URLs working.
// Two sites may share a segment (ecosystems + products) — the hub renders one pane, so the rail
// draws one row, which is keyed by SEGMENT rather than by site.
//
// Values are bare feature SEGMENTS (no leading slash).
export const HUB_FEATURE_SEGMENT = {
  // --- sites whose hub route predates them, under the hub's own name for it ---
  // The persona EDITOR, which is what agenticdeveloperpersonas.com renders — the same
  // @agentic-toolkit/personas surface, so the site's row leads to the hub's own copy of it. This
  // used to point at `all-data`, the persona-DATA CRUD; that route is untouched and still reached
  // from the rail, it simply is not this site's implementation. `all-data` keeps its place in
  // HUB_EXTRA_FEATURE_SEGMENTS below.
  personas: 'personas',
  // The hub's DM workspace + notification inbox, at /<slug>/messaging. Keyed by `messages` —
  // sending and receiving messages is what that site is — while the segment keeps the older
  // `messaging` spelling, which is a route name and not a site name.
  messages: 'messaging',
  // The `messaging` SITE is email & SMS integrations for your products, and the hub surface for
  // that has always been the `integrations` feature. It is a placeholder on its own domain, so
  // pointing it at the feature that does the job beats minting a second Messaging row that leads
  // to the inbox — a different product.
  messaging: 'integrations',
  // Ecosystems are managed as PRODUCTS in the hub (/<slug>/products — each product IS an
  // ecosystem), so both the ecosystems and products sites resolve to that view.
  ecosystems: 'products',
  products: 'products',
  // The two TOKEN families — `Tokens ▸ API tokens` and `Tokens ▸ Storage tokens` — which is
  // what agenticdeveloperauthentication.com's workspace surface IS (see adh-site-homes'
  // authentication.tsx). The hub mounts that same `TokensFeature` at `/<slug>/tokens`.
  //
  // It read `'auth'` until 2026-08-31, because the hub had routed customer auth under that name
  // since before the site existed. That was a mislanding, not a spelling: `/<slug>/auth` is the
  // workspace's ecosystem SIGN-IN CONFIGURATION, a hub-own knob this site does not implement, so
  // `useSiteMenu`'s hub branch answered the Authentication row with a route onto a different
  // feature entirely — the exact failure the whole in-hub mounting exists to remove. The map's
  // contract is the segment that mounts the SITE's implementation; `tokens` is where that is.
  authentication: 'tokens',
  // The teams feature is agenticteamregistry.com's implementation; the hub's route for it is
  // `teams`, which is also what the header and the breadcrumb have always called it.
  teamregistry: 'teams',
  // --- sites whose hub route already carries their own name ---
  billing: 'billing',
  dashboards: 'dashboards',
  gamification: 'gamification',
  integrations: 'integrations',
  knowledgebases: 'knowledgebases',
  narratives: 'narratives',
  projects: 'projects',
  registries: 'registries',
  research: 'research',
  storage: 'storage',
  // --- the rest of the fleet, each at its own name (gen-hub-fleet-routes.py writes these) ---
  academy: 'academy',
  codereviews: 'codereviews',
  // `communities` is BACK. Its hub route once rendered "Coming soon" and was removed when the
  // features left; the site's own workspace model is that same placeholder, and the hub mounts
  // it now rather than sending anyone to another origin to read it.
  communities: 'communities',
  community: 'community',
  consultants: 'consultants',
  consulting: 'consulting',
  cookbook: 'cookbook',
  customers: 'customers',
  devices: 'devices',
  devteam: 'devteam',
  docs: 'docs',
  domains: 'domains',
  education: 'education',
  games: 'games',
  help: 'help',
  news: 'news',
  notebook: 'notebook',
  notifications: 'notifications',
  orgs: 'orgs',
  personabuilder: 'personabuilder',
  recipes: 'recipes',
  registry: 'registry',
  shipr: 'shipr',
  sites: 'sites',
  store: 'store',
  stores: 'stores',
  support: 'support',
  teambuilder: 'teambuilder',
  testing: 'testing',
  toolkit: 'toolkit',
  tools: 'tools',
} as const satisfies Partial<Record<SiteId, string>>

/** A hub workspace segment that is some SITE's implementation — the values above, as a type.
 *
 *  `as const satisfies` rather than an annotation, so the literals survive: the hub's `FeatureId`
 *  IS this union plus {@link HubExtraFeatureSegment}, which turns "the rail has a row for every
 *  routed site" from a pair of vitest lockstep assertions into a compile error in the file that
 *  would otherwise be missing the row. `satisfies` keeps the keys checked against `SiteId` exactly
 *  as the annotation did. */
export type HubFeatureSegment = (typeof HUB_FEATURE_SEGMENT)[keyof typeof HUB_FEATURE_SEGMENT]

/** The hub segment that mounts site `id`'s workspace implementation, or undefined when the hub
 *  has no view of it.
 *
 *  A function rather than a bare index because the map is `as const`: it carries only the sites
 *  it names, so indexing it with an arbitrary {@link SiteId} is an error at the type level even
 *  though "does the hub route this site?" is exactly the question every caller has. Asking it
 *  here keeps the widening in ONE place instead of at each call site. */
export function hubFeatureSegment(id: SiteId): HubFeatureSegment | undefined {
  return (HUB_FEATURE_SEGMENT as Partial<Record<SiteId, HubFeatureSegment>>)[id]
}

/** The site whose implementation a hub segment mounts — the reverse of {@link HUB_FEATURE_SEGMENT},
 *  for the readers that have a segment and need the site's label, glyph or blurb (the hub's rail
 *  rows are built from exactly those three).
 *
 *  Two sites can name one segment, so "the site" needs a rule rather than a last-write-wins
 *  accident: the site whose ID IS the segment wins, and only when none is does the first mapping
 *  take it. That gives `products` → the Products site (not Ecosystems, which also renders there)
 *  and `integrations` → Integrations (not Messaging, which borrows it), which is what those rows
 *  are called everywhere else. */
export const SITE_FOR_HUB_SEGMENT: Record<HubFeatureSegment, SiteId> = (() => {
  const out = {} as Record<HubFeatureSegment, SiteId>
  for (const [siteId, segment] of Object.entries(HUB_FEATURE_SEGMENT) as [SiteId, HubFeatureSegment][]) {
    if (out[segment] === undefined || siteId === segment) out[segment] = siteId
  }
  return out
})()

/** Hub workspace feature segments with no DISTINCT registry site behind them: recognized as
 *  workspace routes (so the menu reads a slug to carry) but absent from HUB_FEATURE_SEGMENT,
 *  which is keyed by site.
 *
 *  It SHRANK when the fleet came home, and the ones that left were not deleted — they moved.
 *  `teams`, `projects`, `personas`, `integrations`, `gamification` and `auth` are each some
 *  site's implementation (teamregistry, projects, personas, integrations, gamification,
 *  authentication), so they are keyed by that site above, where they can also tell the site menu
 *  and the route generator where the site lives. What is left here is what genuinely has no site:
 *  hub knobs scoped to an ecosystem, and the persona-DATA CRUD.
 *
 *  `all-data` is the one arrival. It used to be reached through `personas: 'all-data'`, which is
 *  now `personas: 'personas'` — the editor is what that site renders — so the CRUD route needs
 *  its own line to stay a recognized workspace segment.
 *
 *  Exported, unlike before, because the hub builds `FEATURE_META` by spreading this half over the
 *  fleet half and a consumer has to be able to count the two apart: a knob added here that
 *  collides with a segment above is otherwise absorbed in silence by that spread, and the only
 *  visible trace is a rail row missing its site. */
export const HUB_EXTRA_FEATURE_SEGMENTS = [
  // `auth` moved here from HUB_FEATURE_SEGMENT on 2026-08-31, when `authentication` was repointed
  // at `tokens`: the workspace's ecosystem sign-in configuration is a hub knob with no site
  // behind it, which is precisely what this list is. `tokens` went the other way — it is the
  // authentication site's own feature now, not the hub's.
  'all-data', 'persona-services', 'auth', 'members', 'settings',
  // Ecosystem topics + LLM Providers promoted onto the root workspace rail (each is a
  // `/<slug>/<segment>` route with a FEATURE_META entry, no distinct registry site to
  // switch into) — kept lockstep with FEATURE_META by the reverse-lockstep test (#9).
  'applications', 'invitations', 'signin-apps', 'feature-flags',
  'server-bags', 'llm-providers',
  // Email Signup: a bespoke rail route (audience.* lists/templates/campaigns), no
  // distinct registry site of its own — same lockstep as the row above.
  'email-signup',
] as const

/** A hub workspace segment with no site behind it — the hub's own knobs, as a type. */
export type HubExtraFeatureSegment = (typeof HUB_EXTRA_FEATURE_SEGMENTS)[number]

/** EVERY `/<workspace>/<segment>` the hub serves as a feature: the fleet's implementations plus
 *  the hub's own knobs. The hub's `FeatureId` is defined as exactly this, so the two cannot drift
 *  — see {@link HubFeatureSegment}. The value-level {@link HUB_WORKSPACE_SEGMENTS} below is the
 *  same set, for the readers that hold a `string` and need to ask. */
export type HubWorkspaceSegment = HubFeatureSegment | HubExtraFeatureSegment

// The set of SECOND-path segments that name a hub workspace feature — `/<workspace>/<segment>`.
// The value-level twin of {@link HubWorkspaceSegment}, for the readers holding a plain `string`.
//
// `home` was a member until the route convergence, and its removal is the same fact from two
// directions. A workspace's landing IS the bare `/<workspace>` now, so `home` names no route
// under a slug — `useSiteMenu`'s routeHref would have minted `/<slug>/home`, a URL that only
// still resolves because next.config.ts redirects it back. And the other reason it was here —
// letting the switcher recognize the slug-less `/home` — went with `isHubWorkspacePath` (below).
//
// Exported as the single source of truth for "is this a hub workspace FEATURE segment?":
// useSiteMenu's routeHref guards on it (#8), and the hub's workspace-features test asserts the
// lockstep both ways against FEATURE_META (#9). It is NOT what decides whether a path is a
// workspace path — see the note further down where that pair used to live.
export const HUB_WORKSPACE_SEGMENTS = new Set<string>([
  ...HUB_EXTRA_FEATURE_SEGMENTS,
  ...Object.values(HUB_FEATURE_SEGMENT),
])

// `isHubWorkspacePath` and `hubWorkspaceSlug` used to sit here, deciding by the SECOND path
// segment — the hub's root was `[slug]`, a public profile, so a workspace URL was only
// recognizable by the known feature that followed it. The root is `[workspace]` now, which makes
// the FIRST segment the whole answer, and answering it means reading the reserved-slug list. That
// list lives in `@agentic-toolkit/adh/site`, which depends on this package — so the pair moved
// there rather than inverting the dependency. `HUB_WORKSPACE_SEGMENTS` stays: it is data about
// which features exist, which is this package's job, and `useSiteMenu` still needs it to decide
// whether a hand-built row is an in-hub destination.

/** The path of `target`'s OWN authenticated workspace, scoped to `slug` — the
 *  destination the site menu carries a signed-in visitor to when they switch
 *  sites from a workspace route, so they land in the SAME workspace on the site
 *  they picked. Returns undefined when `target` has no workspace route, and the
 *  caller falls back to the site's landing.
 *
 *  It sends the visitor to the SITE — never to the hub's own view of that site's feature
 *  (`/<slug>/<feature>`, see {@link HUB_FEATURE_SEGMENT}), which is a different destination and
 *  not this function's to pick.
 *
 *  That used to be the whole rule, stated here because the menu had no other: picking "Storage"
 *  meant the Storage site, from wherever you picked it. It is now the rule for everywhere EXCEPT
 *  the hub. The hub mounts every routed site's own implementation under `/<slug>/<segment>`, so
 *  `useSiteMenu`'s hrefFor answers a signed-in in-workspace hub row with that route and never
 *  reaches this function; a signed-out hub visitor, and every other site's header, still does.
 *  The behaviour is unchanged HERE — a caller that asks for a site's workspace path still gets
 *  the site's own — and the sentence above is about the one caller there is.
 *
 *  One line, and that is the route convergence's whole point: this used to switch on
 *  {@link SiteDef.workspaceRoute} for three destinations. The value still decides WHETHER
 *  there is one — it is the fact that the site mounts `app/[workspace]` — but no longer
 *  where, because every site that mounts it mounts the same bytes. */
export function siteWorkspaceHref(target: SiteDef, slug: string): string | undefined {
  if (!slug || !target.workspaceRoute) return undefined
  return `/${slug}`
}

/** The top-level path segments a `workspaceRoute: 'root'` site owns that are NOT a
 *  workspace slug. Those sites put their workspace at `/<slug>`, so its segment sits
 *  in the same position as every public page they ship — this is the set that tells
 *  the two apart, and it is exactly the static top-level routes those sites have
 *  (asserted against the generated route map by registry.test's lockstep case, so a
 *  page added at a site's root fails there until it is listed here, and a page retired
 *  fails until it is removed).
 *
 *  It is the UNION over those sites, not a per-site set, and after the route convergence
 *  that union is no longer just the template's seven: the sites whose own routes used to
 *  force a nested workspace now put it at the root beside them, so cookbook's nine corpus
 *  sections and community's board are in here too. Listing a segment one site owns costs
 *  the others nothing — every one of these is already reserved family-wide by
 *  `SITE_ROUTE_SEGMENTS` in `@agentic-toolkit/adh/site`, so no workspace can be named any
 *  of them anywhere, and a segment that reads as "not a slug" on a site that does not serve
 *  it is a page that 404s either way.
 *
 *  Only the STATIC ones can be listed, so anything else reads as a workspace slug — which
 *  is what makes this set's ACCURACY load-bearing rather than merely tidy. The destination
 *  no longer repairs a slug it cannot resolve: `useWorkspaceRoute` used to replace an
 *  unknown one with the visitor's own workspace, and this branch replaced that with a 404
 *  on a settled list with no match, because silently rewriting the URL to a DIFFERENT
 *  workspace is a worse answer than saying the address is wrong. So a page missing from
 *  this set is carried across the switch as if it were a slug, and lands on a 404 instead
 *  of a redirect. The lockstep case in registry.test.ts is what keeps that from happening:
 *  it fails the moment a `'root'` site adds or retires a top-level route without this list
 *  following. A genuinely unknown segment (`/typo`) still reads as a slug and still 404s —
 *  that one was already a wrong address, and the alternative, refusing to carry any slug at
 *  all, costs the carry on every site. */
export const SITE_LANDING_SEGMENTS = new Set<string>([
  // The template's own — every site in the family serves these.
  'auth',
  'details',
  'home',
  'integrations',
  'privacy',
  'terms',
  'tour',
  // cookbook — the corpus IS these nine words, each an `app/(reader)/<section>/[[...slug]]`
  // directory with nothing in front of it. `projects` and `recipes` are section names as
  // well as sibling sites' ids; that collision is only about this set, not about the ids.
  'appendix',
  'compliance',
  'guidelines',
  'ingredients',
  'introduction',
  'principles',
  'projects',
  'recipes',
  'reference',
  // community — the forum. `forum` is the board that was this site's `/home` until `/home`
  // became the family's workspace redirect.
  'admin',
  'categories',
  'discussions',
  'forum',
  'people',
  'topics',
  // personaregistry used to contribute `org`, `persona` and `user` here. It has no workspace
  // route at all now — its root segment IS the public handle — so it is outside this union,
  // and a word only it serves would make the lockstep case fail. The three stay reserved
  // family-wide by `SITE_ROUTE_SEGMENTS` in `@agentic-toolkit/adh/site`, which is a different
  // question: this set says "not a slug", that one says "nobody may claim it".
  // research — the finder. A paper's own address is `/<author>/<paper-slug>`, whose first
  // segment IS the workspace slug, so `search` is the only word of research's that lands here.
  'search',
  // registries + consultants — the public registry and profile pages beside the workspace.
  // `search` above is theirs too: all three sites put a finder at their root, and a Set
  // holds the word once.
  'consultant',
  'registry',
  // integrations — the OAuth return the site owns at its own root.
  'integrations',
  // billing — where a checkout comes back to be attached to an account.
  'claim',
  // toolkit — the component demo.
  'demo',
  // billing — where a purchase made before signing in is attached to an account
  // (`app/claim/`). Signed-out by design, so it is a landing page, not a workspace.
  'claim',
])

/** The hub's own static top-level path segments — what tells one of ITS pages from a
 *  workspace slug, exactly as {@link SITE_LANDING_SEGMENTS} does for a `'root'` site.
 *
 *  Two sets rather than one, because the two sites' roots hold different words: the hub
 *  serves `/login`, `/explore`, `/settings` and `/features`, which no template site
 *  has, and does not serve cookbook's `/guidelines` or community's `/forum`, which the
 *  other set carries. Either set used on the other's site gives a wrong answer in both
 *  directions at once.
 *
 *  Held to `SITE_ROUTES['hub']` in BOTH directions by registry.test's lockstep case, on
 *  the same reasoning as the set above: a page added or retired at the hub's top level
 *  fails there until this list follows.
 *
 *  ⚠️ WHY THIS SET AND NOT THE MINT-TIME ONE. `hubWorkspacePath.ts` used to answer from
 *  `reservedWorkspaceSlugs()` — the union every slug FORM refuses — on the reasoning that
 *  a wider list can only ever err toward "not a workspace", and that the dangerous
 *  direction is a route missing from a hand-written list and read as a slug. Half of that
 *  is right, and the lockstep below is what closes it. The other half is not: the mint
 *  list is 41 words wider than what the API actually refuses (`RESERVED_PRINCIPAL_SLUGS`
 *  in `backend/src/adh/src/lib/rdid.ts` is the rdid type prefixes plus the route words —
 *  `teams`, `support`, `research`, `me` and 37 more are held back by the two forms on
 *  taste alone), and every one of those is a slug a principal can hold: `organizations.ts`
 *  validates a create with `assertPrincipalSlug`, which does not consult taste, and BOTH
 *  lists are mint-time refusals that leave older rows exactly as they are. A workspace
 *  slugged any of them then reads as a hub route — `hubWorkspaceSlug` returns null, and
 *  the header quietly substitutes the visitor's OWN slug into every feature link while
 *  they are looking at someone else's workspace. Answering a question about the hub's
 *  routes from a list of taste words was the error; width was never the safe side.
 *
 *  The eight `/<feature-id>` → `/features/<id>` redirects in the hub's `next.config.ts`
 *  are deliberately absent, the same way help's `/docs` redirect is absent from
 *  {@link SITE_LANDING_SEGMENTS}: a redirect answers before anything renders, so those
 *  words are never a pathname a component sees, and listing them would carve a permanent
 *  exception into the lockstep — which is the drift this shape exists to prevent. */
export const HUB_ROUTE_SEGMENTS = new Set<string>([
  // The template's own — the same words every site in the family serves.
  'auth',
  'details',
  'home',
  'integrations',
  'privacy',
  'terms',
  'tour',
  // app/(auth)/ — the sign-in group. A route group contributes no segment of its own, so
  // its children sit at the top level.
  'join',
  'login',
  'oidc',
  'signup',
  // app/(hub)/ — the two marketing surfaces that stayed at the root.
  'contact',
  'explore',
  // The hub's own trees. `features` is where the eight marketing feature pages moved when
  // `[workspace]` claimed the root (`app/features/[id]`); `settings` is the account, which
  // came off `/home` when that segment became the family's workspace redirect; `integrations`
  // is the OAuth return that every site mounting that feature grows, at a path built from the
  // window's own origin; `old-landing` is the superseded hero page, still routable and
  // deliberately kept so.
  'features',
  'integrations',
  'old-landing',
  'settings',
])

/** The workspace slug `pathname` names on `site`, or null when it names none — the
 *  inverse of {@link siteWorkspaceHref}, and what the site menu reads to carry the
 *  visitor's CURRENT workspace across a site switch.
 *
 *  Only meaningful for an authenticated visitor: every workspace route in the family
 *  sits behind an auth gate, so a signed-out path that happens to parse is not one.
 *  The caller owns that check (see useSiteMenu).
 *
 *  ⚠️ Answers for a `'root'` site only. Building a workspace path needs nothing but the
 *  slug; reading one back needs the list of first segments that are NOT slugs, and the
 *  hub's is a different list — {@link HUB_ROUTE_SEGMENTS}, right above. Answering the hub
 *  from {@link SITE_LANDING_SEGMENTS} would read `/login` and `/explore` as workspace
 *  slugs, so this refuses rather than guessing.
 *
 *  It refuses instead of switching on the set because a hub path needs MORE than a set:
 *  `/home` and `/settings` are workspace chrome carrying no slug, where the answer is the
 *  signed-in visitor's own — a fact this package has no notion of. `hubWorkspacePath.ts`
 *  in `@agentic-toolkit/adh` owns that whole answer and reads the set from here, and
 *  `useSiteMenu` — the only caller either has — asks it directly. (The set itself lived
 *  there too until it turned out to be answering from the mint-time reserved list; see
 *  HUB_ROUTE_SEGMENTS for what that cost.) */
export function siteWorkspaceSlug(site: SiteDef, pathname: string): string | null {
  if (site.workspaceRoute !== 'root') return null
  const seg = (pathname || '/').split('/').filter(Boolean)[0]
  return seg && !SITE_LANDING_SEGMENTS.has(seg) ? seg : null
}

/** Resolve an absolute URL to a specific path on another site, in the current
 *  environment (testing/staging/production/local), e.g. the shared login/join
 *  pages that live on the hub. Unlike buildSiteHref this carries the exact path
 *  rather than route-matching, so it suits fixed destinations like `/login`. */
/**
 * The persona registry's public namespaces, as paths.
 *
 * All four hosts that link into that site mint these — the registry's own pages, the hub's
 * persona surfaces, personabuilder, and the registry's smoke test — so the rule lives here,
 * where `personaProfileUrl` already had to live for the same reason: two copies of it drifted
 * once already, and that showed up as a review finding rather than a broken page.
 *
 * A persona's address is its handle at the ROOT — `agenticpersonaregistry.com/<handle>` — and
 * that is the address the site exists to publish. It is why this site alone has no
 * `app/[workspace]`: Next allows one dynamic name per level, so the root is either the
 * family's workspace segment or the registry's handles, and here it is the handles.
 *
 * A user's slug shares that root namespace, and so does an ORGANIZATION's: all three are
 * minted flat, and the root page resolves them in that order (persona, user, org). An owner
 * is an owner — `/<owner>/<persona>` is the owner-scoped form of the same persona whether the
 * owner is a person or an org, which is why there is no longer an `/org/` prefix to mint.
 *
 * The order is a tiebreak, not a guarantee of disjointness: `uq_users_slug` and
 * `uq_organizations_slug` are separate indexes and neither knows about persona handles, so
 * `bob` can be all three and the first hit wins.
 */
export function personaProfilePath(slug: string): string {
  return `/${encodeURIComponent(slug)}`
}

/** A registry user's public profile — their personas, their creator sheet. Shares the root
 *  namespace with personas, which the root page resolves in that order. */
export function registryUserPath(slug: string): string {
  return `/${encodeURIComponent(slug)}`
}

/** A persona addressed through its OWNER — a user OR an organization, since both hold slugs
 *  in the same root namespace. The same persona also has a global handle at
 *  `personaProfilePath`; this is the address that says whose it is. */
export function registryUserPersonaPath(ownerSlug: string, personaSlug: string): string {
  return `${registryUserPath(ownerSlug)}/${encodeURIComponent(personaSlug)}`
}

/** An organization's public profile on the registry — the SAME root namespace a user's slug
 *  lives in. It is deliberately identical to `registryUserPath`: an org is shown the way a
 *  user is, and its personas hang off it at `/<org>/<persona>` like anyone else's. The two
 *  names are kept apart because the call sites mean different things, not different paths. */
export function registryOrgPath(slug: string): string {
  return `/${encodeURIComponent(slug)}`
}

/**
 * A persona's public profile URL on the registry — absolute, for a host linking in from
 * somewhere else. `siteUrl` resolves the right host for the current environment (local suite
 * / testing / staging / prod). Only reachable once the persona is saved with `public` or `hub`
 * visibility — a `hub` persona resolves for a signed-in viewer and 404s for an anonymous one, so
 * a link built here is not a promise that the recipient can open it.
 */
export function personaProfileUrl(slug: string): string {
  // globalThis, not `window`: this file is also typechecked by the backend (no dom lib),
  // where a bare `window` reference is TS2304 even behind a typeof guard.
  const hostname = (globalThis as { location?: { hostname?: string } }).location?.hostname ?? "";
  return siteUrl("personaregistry", personaProfilePath(slug), hostname);
}

export function siteUrl(id: SiteId, path: string, currentHostname: string): string {
  const site = getSite(id)
  if (!site) return path
  const env = detectEnv(currentHostname)
  if (env === 'local') return `${localOrigin(site, currentHostname)}${path}`
  return `https://${hostForEnv(site, env)}${path}`
}

/** Production host for a site, used as the deterministic SSR default before the
 *  client knows its own hostname (avoids hydration mismatch on auth links). */
export function siteProdUrl(id: SiteId, path: string): string {
  const site = getSite(id)
  if (!site) return path
  return `https://${site.prodHost}${path}`
}

/** The post-login landing PATH for a site: its `/home` when it exposes one
 *  (`hasHome`), else the site root `/`. This is the default "come back here"
 *  target the header's Login / Sign up buttons pass to the hub as `?return=`, so a
 *  visitor lands back on the site they started from rather than the hub's own
 *  /home. See docs/platform/login-and-return.md. */
export function siteHomePath(id: SiteId): string {
  return getSite(id)?.hasHome ? '/home' : '/'
}

/** The brand origins a given backend environment must allow as OAuth `return`
 *  targets for the central `adh` cross-site-SSO client. Every brand site begins
 *  login by navigating to the shared Authorization Server with
 *  `return=https://<this site>/auth/callback`; the backend only honors a return
 *  whose origin is on the `adh` client's allowlist, so the seeder feeds it this
 *  list.
 *
 *  Each Vercel project talks ONLY to its same-env backend, so an env's allowlist
 *  needs exactly the origins that can reach that env: production = every site;
 *  staging = sites with a staging deploy; testing = sites with a testing deploy.
 *  A site with no deploy in `env` is reached via the testing→staging fallback on
 *  a DIFFERENT env's host (see `hostForEnv`), so its origin never hits this env's
 *  backend and is intentionally absent here.
 *
 *  `external` sites (FishLamp Design) are excluded from EVERY env: they are
 *  link-outs, not ADH apps — they have no `/auth/callback` and never begin an
 *  ADH login, so listing them would widen the OAuth redirect surface for nothing.
 *
 *  ⚠️ `hasStaging` / `hasTesting` ARE THE OAUTH REDIRECT SURFACE, and editing one
 *  is a one-way door. The enforcement point is a DB column, and the deploy-time
 *  sync that fills it (`backend/src/adh/src/lib/sync-return-origins.ts`) is
 *  ADDITIVE, NEVER PRUNING — it adds what this function names and keeps whatever
 *  else is already there. So flipping a flag to `true` allow-lists that origin on
 *  that env permanently; flipping it back to `false` does NOT take it off, and
 *  nothing in the deploy path will. Un-widening is a deliberate, hand-run
 *  `tools/sync-return-origins.ts --prune` against that env. Treat a flag flip on
 *  an EXISTING row the way you would treat editing the allow-list itself, and
 *  flip one only for a site that really is deployed on that tier — a claimed tier
 *  with nothing behind it buys a live redirect target for a host we are not
 *  serving. (`testing/probe-auth-fleet.py` derives its roster from these same
 *  flags, so a tier claimed and not deployed shows up there as a failing probe
 *  rather than as silence.)
 *
 *  This has happened once. `messaging` was an in-hub-only feature id until
 *  2026-08-22 — `hasStaging: false, hasTesting: false, listed: false`, so only its
 *  production origin was ever listed — and became a real three-tier site that day
 *  (deployed by `.shipr`'s group4 shard, all three hosts live in DNS), which added
 *  `https://staging.agenticdevelopermessaging.com` and
 *  `https://testing.agenticdevelopermessaging.com` for good. Intended, and written
 *  down here because the diff that did it looked like a listing change. */
export function ssoReturnOrigins(env: 'production' | 'staging' | 'testing'): string[] {
  const prefix = env === 'production' ? '' : `${env}.`
  return SITES.filter(
    (s) =>
      !s.external &&
      (env === 'production' ? true : env === 'staging' ? s.hasStaging : s.hasTesting),
  ).map((s) => `https://${prefix}${s.prodHost}`)
}
