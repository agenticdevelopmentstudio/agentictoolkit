'use client'

export { AdhHeader } from './AdhHeader'
export type { AdhHeaderProps, AdhHeaderAuthProps, HeaderBadge } from './AdhHeader'
export { AvatarMenu } from './AvatarMenu'
export type { AvatarMenuProps, AvatarMenuUser } from './AvatarMenu'
export { SiteSwitcher } from './SiteSwitcher'
export type { SiteSwitcherProps } from './SiteSwitcher'
export { SiteOptionsMenu } from './SiteOptionsMenu'
export type { SiteOptionsMenuProps, SiteLink } from './SiteOptionsMenu'
export { AuthButtons } from './AuthButtons'
export type { AuthButtonsProps } from './AuthButtons'
export { NavLinkItem, pathMatches } from './NavLink'
export type { NavLink, NavLinkIcon, NavLinkItemProps } from './NavLink'
export { NavigationPopover } from './NavigationPopover'
export type {
  NavigationPopoverProps,
  PopoverClose,
  PopoverEntry,
  PopoverIcon,
  PopoverItem,
  PopoverListEntry,
  PopoverNotice,
  PopoverSearchCommand,
} from './NavigationPopover'
export { HubMark } from './HubMark'
export type { HubMarkProps } from './HubMark'
export { buildRouteItems, currentRoutePath } from './routeEntries'
export type { RouteDef, RouteSection } from './routeEntries'
export { useClientHost } from './useClientHost'
export { WorkspacesMenuProvider, useWorkspacesMenu } from './workspaces-menu'
export type { MenuWorkspace, WorkspacesMenu } from './workspaces-menu'

// adh's registry-bound header half, merged in from the former `@adh/chrome/header`: SiteHeader
// composes the registry-free AdhHeader above with adh's site registry, auth wiring,
// and its own site-menu taxonomy. `SiteMenuSwitcher` is renamed from that source's
// `SiteSwitcher` — this barrel already has a `SiteSwitcher` (the registry-free
// primitive above); the two are unrelated components that happened to share a name.
export { SiteHeader } from './SiteHeader'
export type { SiteHeaderProps } from './SiteHeader'
export { SiteMenuSwitcher } from './SiteMenuSwitcher'
export { WorkspaceMenu } from './WorkspaceMenu'
export type { WorkspaceMenuProps } from './WorkspaceMenu'
export type { SiteMenuSwitcherProps } from './SiteMenuSwitcher'
// The two config-only menus behind the SiteMenuSwitcher dispatcher + their shared base
// — exported so demos/tests can render a specific auth state directly (the
// dispatcher itself picks by route).
export { SiteMenu } from './SiteMenu'
export type { SiteMenuProps, SiteMenuChromeProps, MenuGroup, MenuLink } from './SiteMenu'
export { MarketingSiteMenu } from './MarketingSiteMenu'
export { WorkspaceSiteMenu } from './WorkspaceSiteMenu'
export { ADMIN_MENU_GROUPS, ADMIN_SECTION, FLEET_MENU_GROUPS, FLEET_SECTION } from './fleetMenuGroups'
export { StudioWordmark } from './StudioWordmark'
// The build half of the Debug Options gate (see devToolsEntries.ts). The bug-glyph
// dev-tools dropdown that used to sit beside the site name went when the repo owner
// asked for the glyph gone and Debug Options moved to the account end of the header
// (`useDebugOptions`), and its site-family and Routes flyouts went with it: nothing
// else mounted them. Everything build- or admin-gated stays out of SiteMenu, which is
// what lets that be the same menu in a dev build and a shipped one.
export { DEV_TOOLS_BUILD_ENABLED } from './devToolsEntries'
export { isWorkspaceMenuRoute } from './activeMenuGroups'
export { menuIcon } from './menu-icons'
export { PrefetchSiblingSites } from './PrefetchSiblingSites'
export { useSiteMenu } from './useSiteMenu'
export {
  getEnvOverride,
  parseEnvOverride,
  resolveEffectiveEnv,
  setEnvOverride,
  useEffectiveEnv,
  useEnvOverride,
} from './envOverride'

// PRESERVED IMPORT — do not rewrite to './recents'.
//
// This package builds with tsup `bundle: true, splitting: false`, so every entry
// that reaches a module by a RELATIVE specifier inlines its own private copy of
// that module. `recents.ts` holds module-level mutable state (`snapshot` and the
// `listeners` Set); a second copy means a recorded visit is invisible to the
// subscriber in the other bundle — silently, with no type or build error, and
// invisible in dev because `next dev`/vitest/tsc all resolve the `development`
// condition to `src/`. Inlining it would also hoist its `'use client'` directive
// over this whole entry file.
//
// The remedy has TWO halves and both must hold: `@agentic-toolkit/adh/header/recents`
// is listed in tsup's `external`, AND every specifier that reaches this module is
// written as the full package path. tsup's `external` matches SPECIFIERS, not
// packages — one surviving './recents' silently defeats it.
// Enforced by `<adh-tools>/sites/scripts/verify-bundle-boundaries.py`.
export {
  RECENTS_CAP,
  clearRecents,
  readRecents,
  recordRecent,
  useRecents,
} from '@agentic-toolkit/adh/header/recents'
export type { RecentPlace } from '@agentic-toolkit/adh/header/recents'
