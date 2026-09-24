export { AdhAppShell } from './AdhAppShell'
export type { AdhAppShellProps } from './AdhAppShell'
// AdhAppShell mounts this itself; it is exported for hosts that render their own shell
// instead (adh's builds/status boards) and still want their stacks to answer to the flag.
export { HierarchicalDetailViewFlag } from './HierarchicalDetailViewFlag'
// Also mounted by AdhAppShell; `slideNavigate` is the call a link makes to slide instead of cut.
// By package path, like AdhAppShell's import: one copy of the slide state for every entry.
export { SlideTransitions, slideNavigate, canSlide } from '@agentic-toolkit/adh/layout/SlideNavigation'
export type { SlideDirection } from '@agentic-toolkit/adh/layout/SlideNavigation'
export { AppErrorBoundary } from './AppErrorBoundary'
export { ErrorFallback } from './ErrorFallback'
export { RouteError } from './RouteError'
export { GlobalError } from './GlobalError'
export { SiteNotFound } from './SiteNotFound'
export type { SiteNotFoundProps } from './SiteNotFound'
export { HomePlaceholder } from './HomePlaceholder'
export type { HomePlaceholderProps } from './HomePlaceholder'

// adh's page shell + seams, merged in from the former `@adh/chrome/layout`.
export { AppShell } from './AppShell'
export type { AppShellProps } from './AppShell'
// Renamed from that source's `SiteNotFound` — this barrel already publishes a `SiteNotFound`
// (the registry-free primitive above, which SiteSwitchNotFound wraps); the two are unrelated
// components that happened to share a name.
export { SiteSwitchNotFound } from './SiteSwitchNotFound'
export type { SiteSwitchNotFoundProps } from './SiteSwitchNotFound'
// Renamed from that source's `HomePlaceholder` — this barrel already publishes a
// `HomePlaceholder` (the registry-free primitive above, which SiteHomePlaceholder wraps); the
// two are unrelated components that happened to share a name.
export { SiteHomePlaceholder } from './SiteHomePlaceholder'
export type { SiteHomePlaceholderProps } from './SiteHomePlaceholder'
// The ADH family's placeholder landing hero — pure adh brand copy/palette, no registry or
// toolkit dependency.
export { SiteLanding } from './SiteLanding'
export type { SiteLandingProps } from './SiteLanding'
