// src/header/menu-icons.ts
import {
  Activity,
  AppWindow,
  Bell,
  Blocks,
  BookMarked,
  BookOpen,
  BookText,
  BookUser,
  Bot,
  Boxes,
  Briefcase,
  Building,
  ChefHat,
  CircleHelp,
  ClipboardCheck,
  ClipboardList,
  Code,
  Contact,
  CreditCard,
  Database,
  Fingerprint,
  Flag,
  FlaskConical,
  FolderKanban,
  Gamepad2,
  Gauge,
  GitPullRequest,
  Globe,
  GraduationCap,
  Hammer,
  HardHat,
  Handshake,
  HardDrive,
  Hexagon,
  History,
  House,
  KeyRound,
  LayoutDashboard,
  LayoutGrid,
  LayoutTemplate,
  Library,
  LifeBuoy,
  Lightbulb,
  LogIn,
  Mail,
  MessageCircle,
  MessagesSquare,
  MonitorSmartphone,
  Network,
  Newspaper,
  NotebookPen,
  NotebookText,
  Package,
  Plug,
  Rocket,
  School,
  ScrollText,
  Send,
  Server,
  Settings,
  ShieldCheck,
  ShoppingBag,
  Sparkles,
  Store,
  Trophy,
  UserCircle,
  UserCog,
  UserPlus,
  Users,
  UsersRound,
  Wrench
} from "lucide-react";
import { SITE_FOR_HUB_SEGMENT } from "@agentic-toolkit/adh-registry";
var ICONS = {
  // --- Hub + its ecosystem sites (inline sub-items under Hub) ---
  hub: Hexagon,
  bitbag: Bot,
  // the hub's AI persona
  community: Users,
  // the community site; the hub has no communities feature to match
  personaregistry: UserCircle,
  // matches FEATURE_META `personas`
  toolkit: Wrench,
  // matches the myagenticteams landing's toolkit glyph
  cookbook: ChefHat,
  // recipes/cookbook
  devteam: UsersRound,
  // matches FEATURE_META `teams`
  myagenticteams: Sparkles,
  // matches the myagenticteams landing
  narratives: ScrollText,
  // matches FEATURE_META `narratives`
  help: CircleHelp,
  // matches SiteMenu's existing help affordance
  "hub-help": CircleHelp,
  // the promoted family Help site (help.adh.com)
  news: Newspaper,
  // --- Destination rows keyed by route path ---
  // The two that moved out of hub's header bar keep the glyph they wore there, so a
  // visitor who knew them in the bar recognizes them in the menu. '/details' is
  // resolved per-SITE rather than on the hub (see SiteMenu) — the key is still the
  // route, because that is what the row points at on whichever site renders it.
  "/contact": Mail,
  "/details": LayoutGrid,
  // --- Hub WORKSPACE feature routes, for the Recents rows -----------------------
  // Recents keys each recorded place by the feature route it sits under
  // (`/<slug>/personas` → '/personas'), so this block must cover EVERY hub workspace
  // segment: a key that resolves to nothing renders a blank icon slot beside rows
  // that have one, which is how Recents came to be the only inconsistently-iconed
  // block in the menu. It is the whole of HUB_WORKSPACE_SEGMENTS minus `home` (the
  // menu's own permanent row, never recorded) — held to that by the hub's
  // recents-recorder test, which walks the registry set and resolves each one here.
  //
  // Only the hub's OWN knobs are written out here. The other half of that set — the
  // segments that are a SITE's implementation mounted in the hub — is folded in from
  // the registry below, so a site added to HUB_FEATURE_SEGMENT arrives with the glyph
  // its own menu row already wears instead of an empty slot.
  "/all-data": Database,
  "/applications": AppWindow,
  "/email-signup": Mail,
  "/feature-flags": Flag,
  "/invitations": UsersRound,
  "/llm-providers": Boxes,
  "/members": BookUser,
  "/persona-services": Boxes,
  "/server-bags": Server,
  "/settings": Settings,
  "/signin-apps": LogIn,
  // The workspace's ecosystem sign-in CONFIGURATION — a hub knob, which is why it is written
  // out here beside its neighbours rather than folded in from the registry. It sat in the
  // block below until 2026-08-31, when `authentication` was repointed from `auth` to `tokens`
  // and this segment stopped being any site's.
  "/auth": KeyRound,
  // The three fleet segments whose HUB glyph is deliberately not its site's, so the
  // derivation below must not decide them. A hand-written key always wins.
  //   '/tokens'    — the Authentication site's own feature, but wearing the KEY it is about
  //                  (beside '/auth') rather than that site's identity Fingerprint.
  //   '/messaging' — labelled "Messages" in the hub and leading to the DM workspace; the
  //                  site that owns the `messaging` segment is about email & SMS.
  //   '/teams'     — the Teams feature, not the team DIRECTORY teamregistry.com is.
  "/tokens": KeyRound,
  "/messaging": MessageCircle,
  "/teams": UsersRound,
  // --- Fleet-menu rows the registry cannot name (see fleetMenuGroups) ---
  // The two grouping topics, which are no single site: a checklist for the things
  // you decide before writing anything, blocks for the things you assemble after.
  plan: ClipboardList,
  build: Blocks,
  // The fleet monitor (lewis.agenticdeveloperhub.com), in the admin section — the
  // one row left in the tree with no registry entry at all, so it keys its own icon
  // here (see fleetMenuGroups). `registry` used to be such a row too; it is a real
  // site now and is keyed by its site id among the marketing family below.
  monitor: Gauge,
  // The "Learn" topic. Not the `help` site's glyph, which its own row inside that
  // submenu already wears — a topic that duplicates one of its children's icons
  // reads as that child promoted, rather than as the group it is.
  learn: Lightbulb,
  // --- Chrome rows (the auth-conditional top section) ---
  home: House,
  workspaces: Boxes,
  recents: History,
  login: LogIn,
  signup: UserPlus,
  // --- Remaining MAIN family sites (websites/main/), for the admin section's
  //     consoles and the fleet tree's operations rows. The rest of the family
  //     (hub, bitbag, community, cookbook, devteam, help, myagenticteams, news,
  //     personaregistry, toolkit) is mapped among the Hub-core rows above. ---
  admin: ShieldCheck,
  // operations console
  api: Code,
  builds: HardHat,
  // the build console
  shipr: Rocket,
  // walks a commit from main to production
  status: Activity,
  // system status / pulse
  support: LifeBuoy,
  // --- MARKETING family sites (websites/marketing/), for the fleet tree's
  //     `{ site }` rows and the Recents fold below. Where a site mirrors a hub
  //     feature, it reuses the FEATURE_META glyph so the menu matches the workspace
  //     rail. ('narratives' is mapped among the Hub-core rows above.) ---
  academy: GraduationCap,
  authentication: Fingerprint,
  // customer auth / identity
  billing: CreditCard,
  // matches FEATURE_META `billing`
  codereviews: GitPullRequest,
  communities: Users,
  // marketing site only — the hub route was removed
  consultants: Briefcase,
  consulting: Handshake,
  // services CTA
  customers: Contact,
  dashboards: LayoutDashboard,
  // matches FEATURE_META `dashboards`
  devices: MonitorSmartphone,
  docs: BookText,
  // documents you keep, filed and searchable
  domains: Globe,
  ecosystems: Network,
  // matches FEATURE_META `ecosystems` (+ the '/ecosystems' route)
  education: School,
  games: Gamepad2,
  // authoring games, not the achievements feature below
  gamification: Trophy,
  // matches the '/gamification' route
  integrations: Plug,
  // matches the '/integrations' route
  knowledgebases: BookOpen,
  // matches FEATURE_META `knowledgebases`
  messages: MessagesSquare,
  // the conversations themselves, read and written
  messaging: Send,
  // what a PRODUCT sends out — email and SMS, not your own inbox
  notebook: NotebookPen,
  // "Notes" in the fleet menu
  notifications: Bell,
  orgs: Building,
  // "Organizations" in the fleet menu
  personabuilder: UserCog,
  // configure personas
  personas: UserCircle,
  // matches FEATURE_META `personas` (+ the '/personas' route)
  products: Package,
  projects: FolderKanban,
  // matches FEATURE_META `projects`
  recipes: NotebookText,
  registries: Library,
  registry: BookMarked,
  // the directory of registered hub developers
  research: FlaskConical,
  // matches FEATURE_META `research` (+ the '/research' route)
  sites: LayoutTemplate,
  // quick landing pages
  storage: HardDrive,
  store: ShoppingBag,
  // the hub's own merch shop — the one site that ships in a box
  stores: Store,
  // storefronts you open for YOUR products
  teambuilder: UsersRound,
  // matches FEATURE_META `teams`
  teamregistry: BookUser,
  // a directory of teams
  testing: ClipboardCheck,
  // test plans, runs, and the bugs they turn up
  tools: Hammer
};
for (const [segment, siteId] of Object.entries(SITE_FOR_HUB_SEGMENT)) {
  const route = `/${segment}`;
  const icon = ICONS[siteId];
  if (icon !== void 0 && ICONS[route] === void 0) ICONS[route] = icon;
}
var MENU_ICONS = ICONS;
function menuIcon(key) {
  return key ? MENU_ICONS[key] : void 0;
}
export {
  MENU_ICONS,
  menuIcon
};
//# sourceMappingURL=menu-icons.js.map