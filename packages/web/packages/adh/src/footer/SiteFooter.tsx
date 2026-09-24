'use client'

import { useId } from 'react'
import {
  AdhFooter as ToolkitFooter,
  FooterMenu,
  type FooterLink,
  type FooterMenuItem,
} from '@agentic-toolkit/adh/footer'
import { AboutModal, ABOUT_DIALOG_ID, BRAND_HREF, BRAND_LABEL } from './AboutModal'
import { FooterChat } from './FooterChat'
import { SitesPopover, SITES_OVERVIEW_POPOVER_ID } from './SitesOverview'
import { openLegalModal, TermsModal, PrivacyModal, TERMS_DIALOG_ID, PRIVACY_DIALOG_ID } from './LegalModals'
import { REST_SLOT_HOST_CLASS } from './useFooterRestOffset'

export type SiteFooterProps = {
  links?: FooterLink[]
  /** Mount bitbag. Default true — he belongs on every real footer; `false` leaves him out,
   *  and the bar keeps no corner for him. A {@link SiteFooterProps.specimen | specimen}
   *  never mounts him, whatever this says.
   *
   *  On THIS component, not the {@link ToolkitFooter} primitive it wraps: the
   *  primitive takes a generic `trailing` slot and has no idea bitbag exists, which
   *  is the whole point of the split. */
  chat?: boolean
  /** A COPY of the footer, shown beside the page's own: the theme editor's preview pane
   *  (theme-editor/areas.tsx). The footer carries things a page must have exactly one of,
   *  and a specimen renders none of them:
   *
   *  - Its menus get ids of their own. `popovertarget` finds its panel by id across the
   *    whole document, so on the page's ids the specimen's copyright opened the PAGE's
   *    menu, and a second copy of each id is invalid HTML besides.
   *  - No About, Sites, Terms or Privacy dialog. Those are found by id too, so the
   *    specimen's entries open the page footer's own. On a page with no SiteFooter they
   *    open nothing, which a specimen can afford: it is there to show what the footer
   *    looks like, not to be one.
   *  - No bitbag. He portals himself to `document.body` (see FooterChatInner), so a
   *    preview cannot contain him with a scoped `display:none` the way it hides the
   *    in-flow theme switcher: he escaped the pane and landed full-size over the console
   *    previewing him. And a second dock would share the first's `view-transition-name`
   *    (adh-site.css), which skips every slide while the specimen is on screen. */
  specimen?: boolean
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
//
// REST_SLOT_HOST_CLASS marks the FIRST item of whichever form shows — Legal, or Terms in
// the fallback — as the one that keeps bitbag's resting slot as its left margin
// (adh-site.css), and it is what `useFooterRestOffset` measures. On both, not on Legal
// alone: the fallback hides Legal, and a slot kept on a hidden element is no slot at all —
// measured there, it flung his resting face off the left edge of the screen.
//
// A function of the menu's id only because a specimen needs an id of its own (see
// `SiteFooterProps.specimen`); the page's footer always passes LEGAL_MENU_ID.
const legalLinks = (menuId: string): FooterLink[] => [
  { ...TERMS, className: `adh-footer__link--no-popover ${REST_SLOT_HOST_CLASS}` },
  { ...PRIVACY, className: 'adh-footer__link--no-popover' },
  {
    label: 'Legal',
    menuId,
    items: [TERMS, PRIVACY],
    className: `adh-footer__legal ${REST_SLOT_HOST_CLASS}`,
  },
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
export function SiteFooter({ links = [], chat = true, live, specimen = false }: SiteFooterProps) {
  // bitbag is rendered here but does NOT live here: FooterChatInner portals him to
  // `document.body` and he fixes himself to the viewport's bottom edge, so the
  // primitive's `trailing` slot is his mount point and nothing else. At rest he is his
  // face alone, parked in the bar's lower-right corner — and `adh-footer--with-chat` is
  // what makes the bar leave that corner empty for him (adh-site.css). Only when he is
  // mounted: a chat-less footer has no one to make room for.
  const withChat = chat && !specimen
  const version = buildVersionLabel(live)
  // A specimen's menu ids, unique to this mount. useId is stable across renders and
  // differs per instance; it is cut down to identifier characters because FooterMenu also
  // spells the menu's CSS anchor name from the id, and React's `«r1»` is not one.
  const instance = useId().replace(/[^\w-]/g, '')
  const copyrightMenuId = specimen ? `${COPYRIGHT_MENU_ID}-${instance}` : COPYRIGHT_MENU_ID
  const legalMenuId = specimen ? `${LEGAL_MENU_ID}-${instance}` : LEGAL_MENU_ID
  return (
    <>
      <ToolkitFooter
        className={withChat ? 'adh-footer--with-chat' : undefined}
        links={[...links, ...legalLinks(legalMenuId)]}
        copyright={
          <>
            <FooterMenu
              id={copyrightMenuId}
              triggerClassName="adh-footer__copyright-trigger"
              label={
                <>
                  {COPYRIGHT_PREFIX}
                  <span className="adh-footer__brand-link">{BRAND_LABEL}</span>
                </>
              }
              items={COPYRIGHT_MENU}
            />
            {/* The copyright menu's fallback, as the inline Terms / Privacy pair is Legal's:
                without the Popover API the menu is a dead button and About never opens, so
                the studio's link and this build's version — the two things the bar carried
                before they moved into About — had no way onto the screen. Shown only there
                (adh-site.css). AFTER the menu, because the theme editor reads the brand's
                current values off the first `.adh-footer__brand-link` it finds
                (theme-editor/areas.tsx), and that has to be the one people see. */}
            <span className="adh-footer__copyright-fallback">
              {COPYRIGHT_PREFIX}
              <a className="adh-footer__brand-link" href={BRAND_HREF}>
                {BRAND_LABEL}
              </a>
              {version && <span className="adh-footer__copyright-version"> · {version}</span>}
            </span>
          </>
        }
        trailing={withChat ? <FooterChat /> : null}
      />
      {/* The page's, one each: a specimen's entries open these (see `specimen`). */}
      {!specimen && (
        <>
          <AboutModal version={version} />
          <SitesPopover />
          <TermsModal />
          <PrivacyModal />
        </>
      )}
    </>
  )
}
