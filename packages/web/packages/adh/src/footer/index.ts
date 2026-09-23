'use client'

export { AdhFooter, FooterMenu } from './AdhFooter'
export type { AdhFooterProps, FooterLink, FooterMenuItem } from './AdhFooter'

// adh's registry-aware footer, merged in from the former `@adh/chrome/footer`. Renamed from that
// source's `AdhFooter` — this barrel already publishes an `AdhFooter` (the registry-free
// primitive above, which SiteFooter wraps); the two are unrelated components that
// happened to share a name.
export { SiteFooter } from './SiteFooter'
export type { SiteFooterProps } from './SiteFooter'
export { SITES_OVERVIEW_POPOVER_ID } from './SitesOverview'
// The seeded-backend primitives are exported because the Help sites reuse them
// (see sites/help/src/components/helpMockBackend.ts); the footer itself no longer
// does — bitbag speaks his own scripted voice through BitbagDock.
export { BITBAG_PERSONA, createSeededBackend } from './seededBackend'
export type { SeededReply, SeededBackendOptions } from './seededBackend'
// Exported for the hub's Debug console, the only writer — see the module doc for
// why the theme travels as a prop rather than as a host-scoped <style>.
export { useChatTheme } from './chat-theme-store'
