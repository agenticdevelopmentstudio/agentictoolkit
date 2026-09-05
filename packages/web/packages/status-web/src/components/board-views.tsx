import type { ReactNode } from "react";
import { Boxes, Cloud, Gauge, Globe, KeyRound, Network, Palette, Server, Settings, Table2, Users } from "lucide-react";

/** The board's deep-linked topics (each a root route `/overview`, `/settings`, …).
 *  Everything configurable lives one level down, as a SECTION under Settings
 *  (`/settings/<section>`) — see {@link SETTINGS_SECTIONS}. */
export type BoardTopic = "overview" | "details" | "fleet" | "settings";

export interface BoardView {
  id: BoardTopic;
  label: string;
  icon: ReactNode;
  /** Draw a separator row after this topic in the rail (splits the monitoring views
   *  from Settings). */
  dividerAfter?: boolean;
}

const ICON = 16;

// SINGLE SOURCE OF TRUTH for the board's topics. The rail topic list, the path→topic
// parser and StatusHeader's board-route set all derive from this — add or rename a topic
// HERE and everything follows (no separate lists to sync). Every topic is visible to
// every role; the role gate lives one level down, on the Settings sections.
export const BOARD_VIEWS: readonly BoardView[] = [
  { id: "overview", label: "Overview", icon: <Gauge size={ICON} aria-hidden /> },
  { id: "details", label: "Details", icon: <Table2 size={ICON} aria-hidden /> },
  { id: "fleet", label: "Fleet", icon: <Server size={ICON} aria-hidden />, dividerAfter: true },
  { id: "settings", label: "Settings", icon: <Settings size={ICON} aria-hidden /> },
];

const IDS: readonly BoardTopic[] = BOARD_VIEWS.map((v) => v.id);

/** The Settings sections — the board's SECOND topic level, at `/settings/<section>`. */
export type SettingsSection = "tokens" | "appearance" | "peers" | "groups" | "platforms" | "sites" | "users";

/** The config-roster sections: each opens an ENTITY LIST (the hierarchy's THIRD level)
 *  whose leaf is the entity editor. Appearance is the one leaf section, with no roster of
 *  its own. `peers` is Fleet's config counterpart: the Fleet view SHOWS the fleet, this
 *  roster is where its members are added and removed. */
export type RosterTopic = Exclude<SettingsSection, "appearance">;

export interface SettingsSectionView {
  id: SettingsSection;
  label: string;
  icon: ReactNode;
  /** The section's one-line document description, used verbatim as the `<meta name=
   *  "description">` for `/settings/<id>` (see the route's `generateMetadata`). It lives
   *  HERE because folding six routes into one catch-all otherwise collapses six distinct
   *  page titles into one: a second hand-kept list in the route file would be exactly the
   *  drift this file exists to prevent. */
  description: string;
}

// SINGLE SOURCE OF TRUTH for the Settings sections — the second-level topic list, the
// `/settings/<section>` parser and the role gate all derive from it.
//
// Ordered ALPHABETICALLY BY LABEL. These are unrelated destinations with no meaningful
// grouping between them, so alphabetical is the only order a reader can predict without
// learning it; keep the list sorted when adding a section.
export const SETTINGS_SECTIONS: readonly SettingsSectionView[] = [
  {
    id: "tokens",
    label: "API tokens",
    icon: <KeyRound size={ICON} aria-hidden />,
    description: "Bearer tokens for CLI, MCP, and machine access to this status board.",
  },
  {
    id: "appearance",
    label: "Appearance",
    icon: <Palette size={ICON} aria-hidden />,
    description: "Display preferences for this browser — the wallboard's font scale.",
  },
  {
    id: "peers",
    label: "Fleet peers",
    icon: <Network size={ICON} aria-hidden />,
    description: "The other status monitors this one polls — the fleet's membership.",
  },
  {
    id: "groups",
    label: "Groups",
    icon: <Boxes size={ICON} aria-hidden />,
    description: "Monitored site groups and their data-retention windows.",
  },
  {
    id: "platforms",
    label: "Platforms",
    icon: <Cloud size={ICON} aria-hidden />,
    description: "Connected deploy platforms and their monitored projects.",
  },
  {
    id: "sites",
    label: "Sites",
    icon: <Globe size={ICON} aria-hidden />,
    description: "Monitored sites and endpoints.",
  },
  {
    id: "users",
    label: "Users",
    icon: <Users size={ICON} aria-hidden />,
    description: "People with access to this status board.",
  },
];

const SECTION_IDS: readonly string[] = SETTINGS_SECTIONS.map((s) => s.id);

/** The sections that are NOT rosters — the leaves with no entity list of their own. The
 *  ONE hand-maintained side of the roster split; `RosterTopic` excludes exactly these, so
 *  the type and the runtime set below can't disagree. */
const LEAF_SECTIONS = ["appearance"] as const satisfies readonly Exclude<SettingsSection, RosterTopic>[];

// DERIVED from SETTINGS_SECTIONS, never hand-listed: a `new Set<RosterTopic>([...])`
// literal type-checks what it contains but NOT what it omits, so a hand-written copy lets
// a newly added section silently miss the roster set (no entity level, no editor, dead
// deep links) with a clean typecheck. Deriving it means a new section is a roster unless
// it is added to LEAF_SECTIONS above.
const ROSTER_SECTIONS: ReadonlySet<string> = new Set(
  SECTION_IDS.filter((id) => !(LEAF_SECTIONS as readonly string[]).includes(id)),
);

/** Whether a Settings section opens an entity roster (everything but Appearance). */
export function isRosterTopic(section: SettingsSection | null): section is RosterTopic {
  return section !== null && ROSTER_SECTIONS.has(section);
}

/** The gated board route paths: `/home` (the no-selection landing) + one per topic.
 *  StatusHeader checks first segments against this to decide when to show the live
 *  status pill (Settings carries deeper `/settings/<section>/<id>` segments). */
export const BOARD_PATHS: ReadonlySet<string> = new Set(["/home", ...IDS.map((id) => `/${id}`)]);

/** A pathname's segments, trailing-slash-normalized — `[]` for the root. The one
 *  place path splitting happens, so the parsers below can't drift on it. */
function segments(path: string): string[] {
  const trimmed = path.replace(/\/+$/, "").replace(/^\//, "");
  return trimmed === "" ? [] : trimmed.split("/");
}

/** First path segment — "" for the root. */
function firstSegment(path: string): string {
  return segments(path)[0] ?? "";
}

/** The selected topic for a pathname (its FIRST segment — Settings deep-links deeper,
 *  e.g. `/settings/sites`), or null for `/home` / any unknown segment. */
export function topicFromPath(path: string): BoardTopic | null {
  const seg = firstSegment(path);
  return (IDS as readonly string[]).includes(seg) ? (seg as BoardTopic) : null;
}

/** Whether a pathname is on the board (the landing or any topic, at any depth). */
export function isBoardPath(path: string): boolean {
  return BOARD_PATHS.has(`/${firstSegment(path)}`);
}

/** The selected Settings section for a pathname (`/settings/<section>`), or null. */
export function sectionFromPath(path: string): SettingsSection | null {
  const segs = segments(path);
  if (segs[0] !== "settings") return null;
  const seg = segs[1] ?? "";
  return SECTION_IDS.includes(seg) ? (seg as SettingsSection) : null;
}

/** The selected entity id for a roster pathname (`/settings/<roster-section>/<id>`), or
 *  null — Appearance has no entity level, so a third segment under it is ignored. */
export function entityIdFromPath(path: string): string | null {
  const segs = segments(path);
  if (segs[0] !== "settings" || !ROSTER_SECTIONS.has(segs[1] ?? "") || !segs[2]) return null;
  try {
    return decodeURIComponent(segs[2]);
  } catch {
    return null;
  }
}

/** The Settings sections a role may see. Appearance is a per-browser display preference,
 *  so everyone gets it; every ROSTER is admin-only, mirroring what the server already
 *  enforces — `configRoutes` puts `requireAdmin` on all of `/config/*` (sites, groups,
 *  platforms, endpoints, peers) and the users/tokens routers do the same.
 *
 *  Written as an ALLOW-list on purpose. The deny-list it replaced (`role !== "viewer"`)
 *  failed OPEN on every role it hadn't been told about: this backend's roles are
 *  `admin | viewer | pending`, so an unapproved `pending` account — and, for the beat
 *  before `useStatusUser` resolves, EVERY account — was offered rosters whose every read
 *  answers 403. An unknown role has to mean least privilege, which a deny-list can't say. */
export function visibleSettingsSections(role: string | null | undefined): readonly SettingsSectionView[] {
  return SETTINGS_SECTIONS.filter((s) => (isRosterTopic(s.id) ? role === "admin" : true));
}
