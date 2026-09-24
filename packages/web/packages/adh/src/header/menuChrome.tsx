import type { ReactElement } from 'react'
import { Settings } from 'lucide-react'
import type { PopoverClose, PopoverEntry } from './NavigationPopover'
import { menuIcon } from './menu-icons'

// The chrome BOTH header switchers carry: the Help row and the command row's settings gear.
// SiteMenu (the family launcher) and WorkspaceMenu (the signed-in hub's workspaces) take turns
// in the same slot — the hub swaps one for the other at sign-in — so a person meets both, and
// they must be the same row and the same gear. They were two copies once, identical but for the
// Help row's section number, and a change to one did not reach the other.

/** The Help row: an ACTION, not a destination — choosing it opens the help panel over the page
 *  and navigates nowhere. `section` is the caller's, because the row closes a different block in
 *  each menu: SiteMenu's auth top section, and a section of its own under WorkspaceMenu's
 *  workspace list. */
export function helpEntry(openHelp: () => void, section: number): PopoverEntry {
  return {
    kind: 'leaf',
    section,
    item: { key: 'help', label: 'Help', icon: menuIcon('help'), onSelect: () => openHelp() },
  }
}

export type SettingsTrailingOptions = {
  /** The popover's own `close`, as its `commandTrailing` render prop hands it over. */
  close: PopoverClose
  /** Opens the in-app settings overlay over the current route. Wins over `settingsHref`. */
  onSettings?: () => void
  /** The settings page, for a host with no overlay (a satellite links to the hub's). */
  settingsHref?: string
}

/**
 * The command row's settings gear — a button that opens the overlay, else a link to the settings
 * page — or null when the host offers no settings surface at all.
 *
 * `onSettings` WINS over `settingsHref`: in-page beats a cross-site navigation whenever both are
 * available, and AvatarMenu's "User Settings" row applies the same order, so one header never
 * answers the same request two ways.
 *
 * Signed-in only, and that gate is the CALLER's: SiteMenu shows its "?" help button in this spot
 * while signed out, and WorkspaceMenu is only ever mounted signed in.
 */
export function settingsTrailing({
  close,
  onSettings,
  settingsHref,
}: SettingsTrailingOptions): ReactElement | null {
  if (onSettings) {
    return (
      <button
        type="button"
        className="adh-site-switcher__help"
        aria-label="User settings"
        onClick={() => {
          // Focus goes to the overlay, so the menu must not hand it back to the trigger; the
          // frame lets the menu finish closing before the overlay opens over it.
          close({ restoreFocus: false })
          requestAnimationFrame(() => onSettings())
        }}
      >
        <Settings className="adh-site-switcher__help-icon" aria-hidden />
      </button>
    )
  }
  if (settingsHref) {
    // A real link so middle-click / new-tab work; native nav tears down the page, so no
    // explicit close needed.
    return (
      <a className="adh-site-switcher__help" aria-label="User settings" href={settingsHref}>
        <Settings className="adh-site-switcher__help-icon" aria-hidden />
      </a>
    )
  }
  return null
}
