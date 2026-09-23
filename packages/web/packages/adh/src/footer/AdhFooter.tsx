'use client'

import Link from 'next/link'
import { ChevronUp } from 'lucide-react'
import type { CSSProperties, MouseEvent, ReactNode } from 'react'

/** One entry of a {@link FooterMenu}: a real link, or a trigger for another popover. */
export type FooterMenuItem =
  | {
      label: string
      href: string
      onSelect?: (event: MouseEvent<HTMLAnchorElement>) => void
      prefetch?: boolean
    }
  | { label: string; popoverTarget: string; ariaLabel?: string }

export type FooterLink =
  /** A real navigation link. `onSelect` is optional progressive enhancement: it runs on a
   *  plain left-click and may `preventDefault()` to handle the click itself. The `href`
   *  stays in the server HTML either way, so the link is never dead without JS.
   *  `prefetch` is passed straight through to next/link — leave it `undefined` to keep
   *  Next's own default (host decides per-link; the toolkit takes no position). */
  | {
      label: string
      href: string
      onSelect?: (event: MouseEvent<HTMLAnchorElement>) => void
      prefetch?: boolean
      className?: string
    }
  /** A native popover trigger: `popovertarget` opens the panel with NO client JS. Carries
   *  the `adh-footer__sites-trigger` class, which a host stylesheet may use to hide it in
   *  browsers without the Popover API — where it cannot degrade to anything. */
  | { label: string; popoverTarget: string; ariaLabel?: string; className?: string }
  /** A popup menu of further entries — see {@link FooterMenu}. */
  | { label: string; menuId: string; items: FooterMenuItem[]; ariaLabel?: string; className?: string }

export type AdhFooterProps = {
  links?: FooterLink[]
  copyright?: ReactNode
  trailing?: ReactNode
}

/** Close the menu an item sits in. A menu entry that opens something else — a modal, a
 *  route — is done with the menu, and nothing else would close it: a client-side route
 *  change keeps the footer mounted, and a popover opened from INSIDE an open popover is
 *  nested under it, so the menu would still be up when the modal closed. */
function closeContainingMenu(el: HTMLElement): void {
  const menu = el.closest<HTMLElement>('[popover]')
  if (menu && 'hidePopover' in menu && menu.matches(':popover-open')) menu.hidePopover()
}

function menuItemClass(extra?: string): string {
  return ['adh-footer__link', extra].filter(Boolean).join(' ')
}

/**
 * A footer popup menu, on the native Popover API: a `popovertarget` button and the panel it
 * opens, both in the server HTML. The panel is collapsed by `display:none` rather than left
 * out, so every link in it is crawlable — the footer is on every page of every site, and a
 * menu that only existed after hydration would take those links out of the index.
 *
 * Positioned against its own trigger with CSS anchor positioning where the browser has it
 * (the anchor name is derived from `id`, so any number of menus can share a bar); where it
 * does not, the host stylesheet's fallback parks it above the bar. Light-dismiss and Escape
 * are the platform's.
 */
export function FooterMenu({
  id,
  label,
  items,
  ariaLabel,
  className,
  triggerClassName = 'adh-footer__link',
}: {
  id: string
  label: ReactNode
  items: FooterMenuItem[]
  ariaLabel?: string
  className?: string
  triggerClassName?: string
}) {
  const anchor = { '--adh-footer-menu-anchor': `--${id}` } as CSSProperties
  return (
    <span className={['adh-footer__menu-host', className].filter(Boolean).join(' ')} style={anchor}>
      <button
        type="button"
        popoverTarget={id}
        aria-label={ariaLabel}
        aria-haspopup="menu"
        className={`${triggerClassName} adh-footer__menu-trigger`}
      >
        {label}
        {/* Says "this opens a menu" — without it the copyright line read as plain text and
            Legal as a link to a page called Legal. UP, because every footer menu opens
            upward off the bottom edge (see .adh-footer__menu's position-area). */}
        <ChevronUp className="adh-footer__menu-caret" aria-hidden />
      </button>
      <div id={id} popover="auto" className="adh-footer__menu">
        <ul className="adh-footer__menu-list">
          {items.map((item) => (
            <li key={'popoverTarget' in item ? `popover:${item.popoverTarget}` : `href:${item.href}`}>
              {'popoverTarget' in item ? (
                <button
                  type="button"
                  popoverTarget={item.popoverTarget}
                  aria-label={item.ariaLabel}
                  className={menuItemClass('adh-footer__menu-item')}
                  onClick={(e) => closeContainingMenu(e.currentTarget)}
                >
                  {item.label}
                </button>
              ) : (
                <Link
                  href={item.href}
                  className={menuItemClass('adh-footer__menu-item')}
                  prefetch={item.prefetch}
                  onClick={(e) => {
                    closeContainingMenu(e.currentTarget)
                    item.onSelect?.(e)
                  }}
                >
                  {item.label}
                </Link>
              )}
            </li>
          ))}
        </ul>
      </div>
    </span>
  )
}

export function AdhFooter({ links = [], copyright, trailing }: AdhFooterProps) {
  return (
    <footer className="adh-footer" role="contentinfo">
      <div className="adh-footer__container">
        {copyright && <span className="adh-footer__copyright">{copyright}</span>}
        {links.length > 0 && (
          <nav className="adh-footer__links" aria-label="Footer">
            {links.map((link) =>
              'menuId' in link ? (
                <FooterMenu
                  key={`menu:${link.menuId}`}
                  id={link.menuId}
                  label={link.label}
                  items={link.items}
                  ariaLabel={link.ariaLabel}
                  className={link.className}
                />
              ) : 'popoverTarget' in link ? (
                <button
                  key={`popover:${link.popoverTarget}`}
                  type="button"
                  popoverTarget={link.popoverTarget}
                  aria-label={link.ariaLabel}
                  className={['adh-footer__link adh-footer__sites-trigger', link.className]
                    .filter(Boolean)
                    .join(' ')}
                >
                  {link.label}
                </button>
              ) : (
                <Link
                  key={`href:${link.href}:${link.label}`}
                  href={link.href}
                  className={menuItemClass(link.className)}
                  onClick={link.onSelect}
                  prefetch={link.prefetch}
                >
                  {link.label}
                </Link>
              ),
            )}
          </nav>
        )}
      </div>
      {trailing}
    </footer>
  )
}
