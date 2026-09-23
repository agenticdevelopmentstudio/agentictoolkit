'use client'

import Link from 'next/link'
import { ChevronDown, Home, LogOut, Settings, User as UserIcon } from 'lucide-react'
import { Avatar, AvatarFallback, AvatarImage } from '@agenticdevelopertoolkit/ui/components/avatar'
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLinkItem,
  DropdownMenuSeparator,
} from '@agenticdevelopertoolkit/ui/components/dropdown-menu'
import { slideNavigate } from '../layout/SlideNavigation'

export type AvatarMenuUser = {
  /** What this account is CALLED — the personal name when one is known, else the
   *  handle a source falls back to (hub's slug, the email local-part, 'User'; see
   *  `toAvatarUser`). Never empty by contract, which is why the trigger can use it
   *  as its accessible name and the avatar can derive initials from it. */
  name: string
  /** The person's own name, when the backend actually holds one. Present ⇒ the menu
   *  GREETS by its first word; absent ⇒ it prints `name` plainly.
   *
   *  Two fields rather than one because a handle is not a name, and only the source
   *  knows which it handed over: greeting "Welcome mikefullerton!" is worse than
   *  printing the handle. `name` still equals this whenever a name exists, so no
   *  caller has to choose between them for a11y or initials. */
  fullName?: string
  /** The account's handle. Data only — it does NOT gate the Profile row (see
   *  `AvatarMenuProps.profileHref`); a caller that has resolved a slug but knows this
   *  site carries no `/<slug>/profile` route must still withhold `profileHref`. */
  slug?: string
  imageUrl?: string
}

export type AvatarMenuProps = {
  user: AvatarMenuUser
  /** Where "Home" points. The site's own post-login landing, supplied by the
   *  registry-aware wrapper; defaults to the site root. */
  homeHref?: string
  /** Where the Profile row points, and whether it renders at all — present ⇒ the row
   *  offers it, absent ⇒ the row is omitted. This component resolves no site ids and
   *  holds no route map (same reason `homeHref` arrives pre-built rather than being
   *  derived from a slug here): the `/<slug>/profile` route this row links to does not
   *  exist on every site the shared header renders on, so the registry-aware wrapper
   *  decides, from the account's slug AND the current site's own route map, whether
   *  there is anywhere to send this row — and hands in the finished href only when
   *  both hold. */
  profileHref?: string
  onLogout?: () => void
  settingsHref?: string
  onSettings?: () => void
}

/** The first whitespace-delimited word of a name — "Mike" from "Mike Fullerton".
 *  A greeting takes the first word, never the whole form: "Welcome Mike Fullerton!"
 *  reads like a form letter. A single-word name is its own first word. */
function firstNameOf(name: string): string {
  return name.trim().split(/\s+/)[0] || name
}

function initialsOf(name: string | undefined | null): string {
  if (!name) return ''
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
}

/**
 * The signed-in account menu: the avatar in the bar, and under it the user's name
 * plus the four account destinations — Home, Profile, User Settings, Log out.
 *
 * It is an ACCOUNT menu, not a nav menu. A site's own destinations live in the bar
 * and in the site-name menu (the brand dropdown); routing them through here as well
 * grew this popup to the length of the site's whole feature list.
 *
 * **This menu is CLOSED at FIVE rows. Add nothing further** — no sixth row, no slot,
 * no prop that lets a host inject one. Not a workspace picker, not a theme toggle,
 * not a docs link, not a site-specific action. Everything proposed for here already
 * has a home: `AdhHeader`'s bar slots (`navLinks`, `trailingNavLinks`, `preAuthLinks`,
 * `leadingActions`) or `SiteMenu`, which is also where the bar's links go below
 * 768px. The rows are what was LEFT after this popup had absorbed the hub's whole
 * feature list and had to be emptied again; there is no threshold at which one more
 * is harmless, which is why the rule is a count and not a taste. Profile was added by
 * the repo owner's explicit instruction — which is the only way the count moves.
 * (Repo rule: `.claude/skills/project-guidelines/topics/ui-development.md`.)
 */
export function AvatarMenu({
  user,
  homeHref = '/',
  profileHref,
  onLogout,
  settingsHref,
  onSettings,
}: AvatarMenuProps) {
  const avatarInner = (
    <Avatar className="adh-avatar-menu-trigger__avatar">
      {user.imageUrl && <AvatarImage src={user.imageUrl} alt={user.name} />}
      <AvatarFallback>{initialsOf(user.name) || <UserIcon className="adh-avatar-menu-trigger__fallback-icon" />}</AvatarFallback>
    </Avatar>
  )

  // The icon LEADS the label in every item (the label keeps `flex: 1`, so it still
  // fills the row) — one column of glyphs down the left edge reads as a list of
  // destinations, where a trailing icon read as a per-row affordance.
  const settingsBody = (
    <>
      <Settings className="adh-avatar-menu__item-icon" />
      <span className="adh-avatar-menu__item-label">User Settings</span>
    </>
  )
  // `onSettings` WINS over `settingsHref`, the same precedence SiteMenu's commandTrailing
  // applies (SiteMenu.tsx: `authenticated && onSettings ? … : authenticated && settingsHref ?
  // …`). SiteHeader passes both — a resolved `onSettings` (its own prop, else the settings
  // overlay's openSettings once signed in) and whatever `settingsHref` its caller supplied —
  // and only suppresses the href for the switcher. Ordering them the other way round here made
  // one header answer the same click two ways: the switcher opened the in-page overlay while
  // the avatar menu navigated to the hub, on any site whose caller passes a href. In-page
  // beats a cross-site navigation whenever both are available.
  const settingsItem = onSettings ? (
    <DropdownMenuItem onClick={onSettings} className="adh-avatar-menu__item">
      {settingsBody}
    </DropdownMenuItem>
  ) : settingsHref ? (
    <DropdownMenuLinkItem render={<Link href={settingsHref} />} className="adh-avatar-menu__item">
      {settingsBody}
    </DropdownMenuLinkItem>
  ) : null

  return (
    <DropdownMenu>
      {/* The trigger is the avatar alone — no name, no slug. The name is still the
          trigger's ACCESSIBLE name (and heads the popup), so nothing is lost to a
          screen reader by dropping the visible copy. */}
      <DropdownMenuTrigger
        className="adh-avatar-menu-trigger"
        aria-label={`Open ${user.name} menu`}
      >
        <span className="adh-avatar-menu-trigger__avatar-wrap">{avatarInner}</span>
        <span className="adh-avatar-menu-trigger__chevron" aria-hidden="true">
          <ChevronDown className="adh-avatar-menu-trigger__chevron-icon" />
        </span>
      </DropdownMenuTrigger>
      <DropdownMenuContent className="adh-avatar-menu" align="end" sideOffset={8}>
        {/* A greeting when we know the person's name, the bare handle when we do
            not. Same element and same class either way, so the row keeps its one
            style and nothing has to reason about which shape is showing. */}
        <div className="adh-avatar-menu__header">
          <div className="adh-avatar-menu__identity">
            <span className="adh-avatar-menu__name">
              {user.fullName ? `Welcome ${firstNameOf(user.fullName)}!` : user.name}
            </span>
          </div>
        </div>
        <DropdownMenuSeparator />
        <DropdownMenuLinkItem render={<Link href={homeHref} />} className="adh-avatar-menu__item">
          <Home className="adh-avatar-menu__item-icon" />
          <span className="adh-avatar-menu__item-label">Home</span>
        </DropdownMenuLinkItem>
        {profileHref && (
          <DropdownMenuLinkItem
            // Profile SLIDES in, as if pushed onto a stack, and Back (button or swipe) slides it
            // off again to wherever it was opened from — it is a destination you visit and
            // return from, not a section you switch to. Still the same Link and the same push:
            // a modified click (new tab), a click the unsaved-changes guard has already
            // intercepted, or a browser that cannot animate all fall through to it untouched.
            render={
              <Link
                href={profileHref}
                onClick={(e) => {
                  if (e.defaultPrevented || e.button !== 0) return
                  if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
                  if (slideNavigate(profileHref)) e.preventDefault()
                }}
              />
            }
            className="adh-avatar-menu__item"
          >
            <UserIcon className="adh-avatar-menu__item-icon" />
            <span className="adh-avatar-menu__item-label">Profile</span>
          </DropdownMenuLinkItem>
        )}
        {settingsItem && (
          <>
            <DropdownMenuSeparator />
            {settingsItem}
          </>
        )}
        {onLogout && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              onClick={onLogout}
              className="adh-avatar-menu__item"
            >
              <LogOut className="adh-avatar-menu__item-icon" />
              <span className="adh-avatar-menu__item-label">Log out</span>
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
