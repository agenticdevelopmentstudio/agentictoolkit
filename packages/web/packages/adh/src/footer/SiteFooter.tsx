'use client'

import {
  AdhFooter as ToolkitFooter,
  FooterMenu,
  type FooterLink,
  type FooterMenuItem,
} from '@agentic-toolkit/adh/footer'
import { AboutModal, ABOUT_DIALOG_ID, BRAND_LABEL } from './AboutModal'
import { FooterChat } from './FooterChat'
import { SitesPopover, SITES_OVERVIEW_POPOVER_ID } from './SitesOverview'
import { openLegalModal, TermsModal, PrivacyModal, TERMS_DIALOG_ID, PRIVACY_DIALOG_ID } from './LegalModals'

export type SiteFooterProps = {
  links?: FooterLink[]
  /** Mount bitbag. Default true — he belongs on every real footer. `false` is for
   *  the ONE case that isn't one: a footer rendered as a specimen inside the theme
   *  editor's preview pane. He portals himself to `document.body` (see
   *  FooterChatInner), so a preview cannot contain him with a scoped `display:none`
   *  the way it hides the in-flow theme switcher — he escapes the pane and lands
   *  full-size over the console that is previewing him. Not mounting him is the
   *  only thing that actually works, and it says what it means.
   *
   *  On THIS component, not the {@link ToolkitFooter} primitive it wraps: the
   *  primitive takes a generic `trailing` slot and has no idea bitbag exists, which
   *  is the whole point of the split. */
  chat?: boolean
  /** The running server's own build identity, passed by {@link AppShell} in development
   *  only. Omitted everywhere else, where the baked `NEXT_PUBLIC_*` literals are the
   *  build and correct by construction — see {@link buildVersionLabel}.
   *
   *  A plain serializable object, deliberately: this component is `'use client'`, so the
   *  value has to cross the server/client boundary as data. It cannot be read here —
   *  resolving it needs `node:fs` and a `git` fork. */
  live?: { version?: string; sha?: string }
}

const COPYRIGHT_PREFIX = '© 2026 '
const COPYRIGHT_MENU_ID = 'adh-footer-copyright-menu'
const LEGAL_MENU_ID = 'adh-footer-legal-menu'

// The copyright is a MENU: About (who makes these sites, and this build's version — the
// version used to sit in the bar itself) and Sites (the family overview, which used to be
// a link of its own at the head of the nav). Both are popover triggers, so the whole
// menu works before hydration and every href behind it is in the server HTML.
const COPYRIGHT_MENU: FooterMenuItem[] = [
  { label: 'About', popoverTarget: ABOUT_DIALOG_ID },
  {
    label: 'Sites',
    popoverTarget: SITES_OVERVIEW_POPOVER_ID,
    ariaLabel: 'Sites — Agentic Developer family overview',
  },
]

// `.adh-footer` is sticky-positioned (bottom: 0), so it is in the viewport on every
// page view of every site — next/link's default in-viewport prefetch would eagerly
// fetch /terms and /privacy on every page load. With JS on, onSelect preventDefault's
// the click and opens a modal instead, so the user never actually navigates to the
// prefetched route: prefetching it is pure waste. prefetch={false} keeps the href
// (no-JS / modified-click fallback) but drops the eager fetch. Site-passed links are
// not ours to decide for, so this is set here, not as a toolkit-wide default.
const TERMS: FooterMenuItem = {
  label: 'Terms',
  href: '/terms',
  onSelect: openLegalModal(TERMS_DIALOG_ID),
  prefetch: false,
}
const PRIVACY: FooterMenuItem = {
  label: 'Privacy',
  href: '/privacy',
  onSelect: openLegalModal(PRIVACY_DIALOG_ID),
  prefetch: false,
}

// Terms + Privacy appear on EVERY footer — owned here so individual sites can't drop
// them. Folded into one "Legal" menu at every width: inline they cost the bar the room
// the studio's full name needs on a phone, and a bar that changed shape at a breakpoint
// read as two different footers. The inline pair is still rendered, as the fallback for
// a browser without the Popover API — where the Legal menu is dead and a crowded bar
// beats an unreachable Terms page. Which one shows is CSS (adh-site.css), so the server
// HTML carries both hrefs either way.
const LEGAL_LINKS: FooterLink[] = [
  { ...TERMS, className: 'adh-footer__link--no-popover' },
  { ...PRIVACY, className: 'adh-footer__link--no-popover' },
  { label: 'Legal', menuId: LEGAL_MENU_ID, items: [TERMS, PRIVACY], className: 'adh-footer__legal' },
]

/** The footer's build identity: `v1.0.155 · a73e79b7`, or null when neither field exists.
 *
 *  Two fields doing two jobs. The semver is hand-bumped and scoped to ONE site's
 *  directory, so it answers "did my change ship?"; the SHA is stamped on every
 *  build from any cause — including a submodule bump that touched no file under
 *  the site — so it answers "which build is this?". Each covers the other's blind
 *  spot: a version alone only moves when someone remembers, and a bare SHA means
 *  nothing unless you happen to be holding the commit you deployed.
 *
 *  Both are read as literal `process.env.NEXT_PUBLIC_*` expressions so Next's
 *  build-time substitution reaches them (the same mechanism TelemetryProvider
 *  already round-trips for NEXT_PUBLIC_ADH_RELEASE). Exported for the contract test.
 *
 *  The title carries the FULL sha rather than a build timestamp: a timestamp would
 *  make every build's bundle differ from identical source, and this repo has already
 *  paid for non-reproducible artifacts once.
 *
 *  `live` overrides either field, and exists for exactly one mode. Under `next build`
 *  the literals below ARE the build, so nothing overrides them and this argument is
 *  never passed. Under `next dev` they freeze at dev-server boot and then keep
 *  reporting the commit the session started on for as long as it runs — which is how
 *  a bumped `VERSION` could show nothing on screen. AppShell (a Server Component)
 *  resolves the real pair per render and passes it down; see `liveBuildIdentity`.
 *  A field it could not read with confidence arrives `undefined` and the baked
 *  literal shows through, so this can only ever correct a value, never blank one.
 *
 *  @param live the running server's own identity, in development only. */
export function buildVersionLabel(live?: { version?: string; sha?: string }) {
  const version = live?.version ?? process.env.NEXT_PUBLIC_ADH_SITE_VERSION ?? ''
  const sha = live?.sha ?? process.env.NEXT_PUBLIC_ADH_RELEASE ?? ''
  const label = [version && `v${version}`, sha && sha.slice(0, 8)].filter(Boolean).join(' · ')
  if (!label) return null
  return <span title={sha || undefined}>{label}</span>
}

/** adh's footer: the toolkit's identity-free primitive ({@link ToolkitFooter}, published as
 *  `AdhFooter` from this same barrel) plus everything that IS adh — the studio's copyright
 *  menu, the About dialog, the sites popover, the legal modals, and bitbag himself. The
 *  copyright is a fixed brand line, deliberately not per-site.
 *
 *  Named `SiteFooter` rather than `AdhFooter`: this barrel already publishes an `AdhFooter`
 *  — the registry-free primitive this component wraps. The two are unrelated components
 *  that happened to share a name; this one is adh's REGISTRY-AWARE composition. */
export function SiteFooter({ links = [], chat = true, live }: SiteFooterProps) {
  // bitbag is rendered here but does NOT live here: FooterChatInner portals him to
  // `document.body` and he fixes himself to the viewport's bottom edge, so the
  // primitive's `trailing` slot is his mount point and nothing else. At rest he is his
  // face alone, parked in the bar's lower-right corner — and `adh-footer--with-chat` is
  // what makes the bar leave that corner empty for him (adh-site.css). Only when he is
  // mounted: a chat-less footer has no one to make room for.
  return (
    <>
      <ToolkitFooter
        className={chat ? 'adh-footer--with-chat' : undefined}
        links={[...links, ...LEGAL_LINKS]}
        copyright={
          <FooterMenu
            id={COPYRIGHT_MENU_ID}
            triggerClassName="adh-footer__copyright-trigger"
            label={
              <>
                {COPYRIGHT_PREFIX}
                <span className="adh-footer__brand-link">{BRAND_LABEL}</span>
              </>
            }
            items={COPYRIGHT_MENU}
          />
        }
        trailing={chat ? <FooterChat /> : null}
      />
      <AboutModal version={buildVersionLabel(live)} />
      <SitesPopover />
      <TermsModal />
      <PrivacyModal />
    </>
  )
}
