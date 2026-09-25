'use client'

import { useId, type ReactNode } from 'react'
import { Wrench } from 'lucide-react'
import { AvatarMenu, type AvatarMenuUser } from './AvatarMenu'
import { AuthButtons } from './AuthButtons'
import { SiteSwitcher } from './SiteSwitcher'
import { type SiteLink } from './SiteOptionsMenu'
import { NavLinkItem, type NavLink } from './NavLink'
import { PreviewNotice } from './PreviewNotice'
import type { AdhThemeKey } from '../themes/adh-themes'
import { Badge } from '@agenticdevelopertoolkit/ui/components/badge'
import { HelpEnabled } from '@agenticdevelopertoolkit/ui/components/help-enabled'

/** A small pill shown under the site name. `tone` selects its colour. */
export type HeaderBadge = {
  label: string
  tone?: 'neutral' | 'accent' | 'orange' | 'blue'
}

// The strip's own module owns its markup, its defaults and its disclosure state; both
// defaults are re-exported here because this is where they have always been imported
// from.
export { DEFAULT_PREVIEW_NOTICE, DEFAULT_PREVIEW_DETAIL } from './PreviewNotice'

/** The auth-related slice of the header's props. An auth-aware wrapper in the
 *  consuming app supplies these from its auth source while the non-auth props are
 *  passed straight through. Kept as a named type so the source contract and the
 *  header can't drift apart — add an auth prop here and a derived type such as
 *  `HeaderAuthState` picks it up automatically. */
export type AdhHeaderAuthProps = {
  /** Transform a cross-site switcher destination href before use. Supplied by the
   *  auth-aware header when signed in, to route the switch through a silent SSO
   *  redirect so the target lands already logged in.
   *
   *  Consumed by a CALLER-SUPPLIED `siteSwitcher` (a registry-driven menu), not
   *  by the default switcher below — it lives on this type so the whole auth
   *  slice stays one object that a wrapper can forward in a single spread. */
  resolveSwitchHref?: (defaultHref: string) => string
  user?: AvatarMenuUser | null
  /** Auth is still resolving (the source's `isLoading`). While true the auth
   *  cluster shows a spinner instead of the login buttons, so a session resolving
   *  in the background never flashes "login / join" first. Defaults false. */
  authLoading?: boolean
  /** The signed-in user holds the host app's `admin` capability. Forwarded to a
   *  caller-supplied site switcher, where a registry-driven menu can use it to
   *  unlock an admin-only tail in EVERY env — production included. Ignored by the
   *  default switcher. */
  userIsAdmin?: boolean
  loginHref?: string
  signupHref?: string
  onLogin?: () => void
  onSignup?: () => void
  onLogout?: () => void
  settingsHref?: string
  onSettings?: () => void
}

export type AdhHeaderProps = AdhHeaderAuthProps & {
  /** The current site's display name — the default switcher's trigger text. */
  siteName: string
  /** Where the site name points when there is nowhere to switch to. */
  siteNameHref?: string
  /** Switch targets for the DEFAULT switcher. Ignored when `siteSwitcher` is set.
   *  This component performs no registry lookup: whoever knows the site family
   *  hands the list in. */
  sites?: SiteLink[]
  /** Rewrite a chosen target's href before navigating (default switcher only).
   *  Receives the target's `id`, or its `href` when it has no `id`. */
  onSwitchSite?: (idOrHref: string) => string | undefined
  /** Replaces the default `sites`-driven switcher in the header's lead slot.
   *
   *  This is the seam that keeps the header registry-free: a consumer whose site
   *  switcher must resolve a private registry (recents, workspaces) renders it
   *  itself and passes it here, from its own package. The
   *  default and the slot are mutually exclusive by
   *  construction: when this is set the default is not rendered at all. */
  siteSwitcher?: ReactNode
  /** A second dropdown rendered immediately AFTER the switcher, on the same row.
   *
   *  Its own slot rather than something the caller folds into `siteSwitcher`,
   *  because the point of it is that the two menus are INDEPENDENT: a menu a host
   *  shows only to some visitors (a dev build, an admin) can sit here while the
   *  switcher beside it renders identically either way. A caller that nested the two
   *  would put the disappearing thing inside the one that must not change.
   *
   *  SiteHeader leaves it empty. The dev-tools dropdown it used to hold was deleted
   *  when the repo owner asked for its bug glyph gone from beside the site name; the
   *  one row in it anybody used is `onDebugOptions` now, at the account end of the
   *  bar. Absent, the row simply holds one child. */
  debugMenu?: ReactNode
  /** Optional page/section title, shown centered in the bar. */
  pageTitle?: string
  /** Help id for `pageTitle`, making the title help-enabled.
   *
   *  Separate from `pageTitle` because that slot holds the SITE name only when a
   *  page named nothing; when a page names itself, help about the site would be
   *  help about the wrong thing. SiteHeader sets this only in the former case. */
  pageTitleHelp?: string
  /** Copy for `pageTitleHelp` when the site published no entry under that id.
   *
   *  Ignored unless `pageTitleHelp` is set, and always loses to a real entry. It
   *  exists because a handful of sites mount no help provider at all, and a title
   *  that silently stops being help-enabled on those sites is worse than one
   *  explained by a shorter line. */
  pageTitleHelpFallback?: string
  /** Optional interactive content centered in the bar (e.g. a live status
   *  indicator + refresh). Unlike `pageTitle` it accepts arbitrary nodes and stays
   *  clickable. When set it occupies the centre slot in place of `pageTitle`. */
  center?: ReactNode
  /** Badges shown under the site name. Empty by default — the family-wide preview
   *  notice is the strip above the bar, not a badge. */
  badges?: HeaderBadge[]
  /** Site-specific controls injected at the start (left) of the right-hand
   *  cluster, before the nav links + auth. Used for functional controls a site
   *  needs in the bar (e.g. a cookbook's search/sidebar/theme). */
  leadingActions?: ReactNode
  navLinks?: NavLink[]
  trailingNavLinks?: NavLink[]
  /** Prominent links rendered AFTER the primary nav links and BEFORE the auth
   *  cluster — a distinct slot from `navLinks`, because the position is behavior:
   *  it is the last thing a signed-out visitor reads before "login / join", and it
   *  sits outside `.adh-header__links`, so it survives the phone breakpoint that
   *  collapses the primary nav into the site menu.
   *
   *  A consumer whose site family gives some of its sites one extra prominent
   *  link fills this. The predicate that decides WHICH sites get one, and what
   *  the link says, is the consumer's own vocabulary and stays with the caller;
   *  the header only knows there is a slot here. */
  preAuthLinks?: ReactNode
  /** Account-scoped controls rendered immediately BEFORE the auth cluster — the
   *  notification bell, and anything else that belongs to the signed-in PERSON
   *  rather than to the site.
   *
   *  Its own slot rather than something the caller folds into `leadingActions`,
   *  and the position is the reason: `leadingActions` opens the right-hand
   *  cluster, ahead of the nav links, and is the site's own (a cookbook's search
   *  and theme switches). This sits at the other end, against the avatar it
   *  belongs with, so a site can fill both without the two fighting over one
   *  slot's order. The header knows only that there is a slot here — who may see
   *  it, and what it fetches, is the caller's. */
  accountActions?: ReactNode
  /** Where the avatar menu's "Home" points — the site's own post-login landing.
   *  This header resolves no site ids, so whoever knows the registry hands it in;
   *  defaults to the site root. */
  homeHref?: string
  /** Where the avatar menu's Profile row points, and whether it renders at all —
   *  `AvatarMenu`'s own `profileHref` prop. This header resolves no site ids and holds
   *  no route map, so whoever knows the registry (and whether the current site
   *  carries `/<slug>/profile`) hands it in; absent omits the row. */
  profileHref?: string
  /** Opens the Debug console. The header draws ONE door for it, whichever the auth
   *  state allows: signed in, the avatar menu's last row (`AvatarMenu`'s own
   *  `onDebugOptions`); signed out, a "Debug Options" icon button after login / join —
   *  a signed-out visitor has no account menu, and without the button they would have
   *  no way into the console at all, including the way to switch OFF a console flag
   *  they saved earlier. Neither while the session is still resolving: which door
   *  applies is not known yet. Absent draws no door. Who is offered it (a dev build,
   *  an adh admin) is the caller's to decide; this header only draws the door. */
  onDebugOptions?: () => void
  /** The door's secondary text ("Sim: prod") — `AvatarMenu`'s `debugOptionsHint`, and
   *  the signed-out button's description. Never part of either door's name, which
   *  stays "Debug Options". */
  debugOptionsHint?: string
  /** The words in the full-width strip above the bar. Defaults to
   *  {@link DEFAULT_PREVIEW_NOTICE}. The package draws the strip; the host supplies
   *  what it says.
   *
   *  The words only — there is deliberately no value that REMOVES the strip. Its
   *  height is `--adh-header-preview-height`, and `--adh-header-height` (which every
   *  sticky sidebar in the family offsets by) is `calc()`ed from it on `:root`. A prop
   *  that emptied the markup would leave that sum untouched, so every one of those
   *  sidebars would sit 1.125rem too low with nothing to say why. Retiring the strip is
   *  that token going to `0` and this default going away together — one coordinated
   *  change, not a per-host switch. */
  previewNotice?: string
  /** The sentence behind the strip's caret — what "preview" actually means for a
   *  visitor. Defaults to {@link DEFAULT_PREVIEW_DETAIL}; same split as
   *  `previewNotice`, for the same reason (the package draws the disclosure, the host
   *  owns the words). */
  previewDetail?: string
  /** The active theme key. Presentational hosts may key styling off it. */
  themeKey?: AdhThemeKey
}

export function AdhHeader({
  siteName,
  siteNameHref = '/',
  sites,
  onSwitchSite,
  siteSwitcher,
  debugMenu,
  pageTitle,
  pageTitleHelp,
  pageTitleHelpFallback,
  center,
  badges = [],
  leadingActions,
  navLinks = [],
  trailingNavLinks = [],
  preAuthLinks,
  accountActions,
  homeHref,
  profileHref,
  onDebugOptions,
  debugOptionsHint,
  previewNotice,
  previewDetail,
  user,
  authLoading = false,
  loginHref,
  signupHref,
  onLogin,
  onSignup,
  onLogout,
  settingsHref,
  onSettings,
}: AdhHeaderProps) {
  // The bar carries the primary nav in BOTH auth states. It used to be emptied when
  // signed in, because the avatar dropdown absorbed these links — that dropdown is an
  // account menu now (name / Home / User Settings / Log out), so emptying the bar would
  // leave a signed-in visitor no nav at all. A site whose signed-in nav is long enough
  // to crowd the bar owns that: it should not hand the header a list it can't show.
  //
  // Either way, drop any link that just points at the site title: `SiteSwitcher`
  // already renders that href as the title, so keeping it here puts the same
  // destination in the bar twice.
  //
  // Only when the title IS that link, though. `SiteSwitcher` renders `siteNameHref`
  // as an anchor; a caller-supplied `siteSwitcher` is a menu TRIGGER — a button — and
  // every adh site supplies one, so on those sites nothing in the header goes to
  // `siteNameHref` at all. Filtering there deleted a declared destination and put
  // nothing in its place: hub signed out declares `home → /`, and the bar was quietly
  // dropping it on every marketing route. Same premise the phone menu's
  // `buildSiteNavEntries` reasons from, so the two now agree.
  const barLinks = siteSwitcher
    ? navLinks
    : navLinks.filter((l) => l.href !== siteNameHref)

  return (
    <header className="adh-header" role="banner">
      {/* Family-wide preview notice, INSIDE the banner so it inherits the header's
          sticky/z-index and can never scroll away from the bar it qualifies. It is a
          full-width strip, so it takes no horizontal room from the bar below.

          NOT `aria-hidden`, unlike the badge slot below it. A badge under the site
          name is decoration that repeats what the page already says; "this is a
          preview release" is a fact about the product that a sighted visitor is told
          on every page, and hiding it from a screen reader would withhold it from the
          one audience that cannot glance at the strip. Its headline is static text
          rather than a `role="status"` live region for the same reason — it never
          changes, and a live region announces CHANGES. Nor is the caret's panel one:
          it appears because the reader asked for it, which is what `aria-expanded` on
          the trigger already says. */}
      <PreviewNotice notice={previewNotice} detail={previewDetail} />
      <div className="adh-header__container">
        <div className="adh-header__lead">
          {/* The lead is a COLUMN (the badges stack under the site name), so anything
              that belongs BESIDE the switcher needs this row of its own — dropped in
              as a bare sibling, `debugMenu` would land under the switcher, not after
              it. Always rendered, even with no `debugMenu`: a wrapper holding one
              child lays out exactly as the bare switcher did. */}
          <div className="adh-header__brand-row">
            {/* Exactly one switcher: the caller's if it supplied one, else the
                built-in `sites` one. Never both. */}
            {siteSwitcher ?? (
              <SiteSwitcher
                siteName={siteName}
                siteNameHref={siteNameHref}
                sites={sites}
                onSwitchSite={onSwitchSite}
              />
            )}
            {debugMenu}
          </div>
          {badges.length > 0 && (
            <span className="adh-header__badges" aria-hidden="true">
              {badges.map((badge) => (
                // The ui Badge owns the skin; the adh-header__badge* classes stay
                // as stable hooks — they're a theme-editor surface.
                <Badge
                  key={badge.label}
                  variant={badge.tone ?? 'neutral'}
                  className={
                    badge.tone
                      ? `adh-header__badge adh-header__badge--${badge.tone}`
                      : 'adh-header__badge'
                  }
                >
                  {badge.label}
                </Badge>
              ))}
            </span>
          )}
        </div>
        {center ? (
          <div className="adh-header__center">{center}</div>
        ) : (
          pageTitle &&
          (pageTitleHelp ? (
            // The TRIGGER carries the title class, rather than wrapping a span that
            // has it: `.adh-header__page-title` is the container's own centred grid
            // item and sets `pointer-events: none` (G47, Mike, 2026-09-25 — was
            // absolutely centred; a grid item now, same reasoning either way), so a
            // button around it would be both a second, differently-laid-out box and
            // unclickable over the text. The inner span exists to keep the ellipsis,
            // which a flex item (HelpEnabled's own root) cannot do for itself.
            <HelpEnabled
              id={pageTitleHelp}
              fallback={pageTitleHelpFallback}
              className="adh-header__page-title adh-header__page-title--help"
            >
              <span className="adh-header__page-title-text">{pageTitle}</span>
            </HelpEnabled>
          ) : (
            <span className="adh-header__page-title">{pageTitle}</span>
          ))
        )}
        <nav className="adh-header__nav" aria-label="Primary">
          {leadingActions && (
            <span className="adh-header__actions">{leadingActions}</span>
          )}
          {/* The primary links, grouped so they can collapse together on a phone
              (see .adh-header__links). They're `display: contents` otherwise, so on
              a wide bar they still sit directly in the nav's flex row — same gaps,
              same layout as when they were bare children. */}
          {barLinks.length > 0 && (
            <span className="adh-header__links">
              {barLinks.map((link) => (
                <NavLinkItem key={link.href + link.label} link={link} />
              ))}
            </span>
          )}
          {/* Caller-supplied prominent links, before the auth cluster. */}
          {preAuthLinks}
          {/* Account chrome, against the avatar. Outside `.adh-header__links`, so it
              survives the phone breakpoint that collapses the primary nav — the point
              of it is that it is the same control in the same place on every route. */}
          {accountActions}
          {authLoading && !user ? (
            <span
              className="adh-header__auth-spinner"
              role="status"
              aria-label="Checking sign-in"
            />
          ) : user ? (
            <AvatarMenu
              user={user}
              homeHref={homeHref}
              profileHref={profileHref}
              onLogout={onLogout}
              settingsHref={settingsHref}
              onSettings={onSettings}
              onDebugOptions={onDebugOptions}
              debugOptionsHint={debugOptionsHint}
            />
          ) : (
            <>
              <AuthButtons
                loginHref={loginHref}
                signupHref={signupHref}
                onLogin={onLogin}
                onSignup={onSignup}
              />
              {/* The signed-out Debug Options door, where the avatar and its row
                  would be — see `onDebugOptions`. */}
              {onDebugOptions && (
                <DebugOptionsButton onOpen={onDebugOptions} hint={debugOptionsHint} />
              )}
            </>
          )}
          {trailingNavLinks.map((link) => (
            <NavLinkItem key={link.href + link.label} link={link} />
          ))}
        </nav>
      </div>
    </header>
  )
}

/**
 * The signed-out Debug Options door (see `onDebugOptions`): one quiet glyph, not a
 * menu — the console is the only thing behind it.
 *
 * A bare `<button>` in `.adh-header__icon-button`, the header's own icon-control
 * identity (dim at rest, brighter on hover, no ground), for the reason that class
 * gives for not being a shared ghost Button. The glyph is the avatar-menu row's
 * wrench, so the same door looks the same in both auth states — and is not the bug
 * the repo owner asked to have removed from beside the site name.
 *
 * Icon-only, so `aria-label` carries the name; the hint is the DESCRIPTION, never
 * part of the name, so the control is "Debug Options" whether or not production is
 * being simulated. `title` repeats both for a pointer, and only while there is a hint:
 * without one it would read back the name as a description.
 */
function DebugOptionsButton({ onOpen, hint }: { onOpen: () => void; hint?: string }) {
  const hintId = useId()
  return (
    <button
      type="button"
      className="adh-header__icon-button"
      aria-label="Debug Options"
      aria-describedby={hint ? hintId : undefined}
      title={hint ? `Debug Options — ${hint}` : undefined}
      onClick={onOpen}
    >
      <Wrench aria-hidden />
      {hint && (
        <span id={hintId} hidden>
          {hint}
        </span>
      )}
    </button>
  )
}
