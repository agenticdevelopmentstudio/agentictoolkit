'use client'

import { FOOTER_SITES, groupSitesByCategory, siteProdUrl } from '@agentic-toolkit/adh-registry'
import { AdhModalPopover } from './AdhModalPopover'

/** The DOM id of the single shared sites-overview popover. The footer renders
 *  the panel once; every trigger (the "Sites" entry in the footer's copyright
 *  menu, the header site-switcher's "?" icon and its "help" command) opens it by this id, so
 *  there's exactly one instance — and therefore one crawlable copy of the SEO
 *  interlink set. */
export const SITES_OVERVIEW_POPOVER_ID = 'adh-sites-overview'

/**
 * The footer "sites overview" — a modal dialog (AdhModalPopover) that lists every
 * family site (grouped, with descriptions). It is BOTH the human overview panel
 * AND the SEO interlink set: every `<a href>` is rendered into the server HTML
 * (the popover is collapsed via the UA stylesheet's `display:none`, not removed),
 * so crawlers follow the links while the panel stays hidden until opened. No
 * client JS — a `popovertarget` trigger (the Sites entry of SiteFooter's copyright
 * menu) opens it and
 * the modal's close box dismisses it natively.
 */
export function SitesPopover() {
  const groups = groupSitesByCategory(FOOTER_SITES)
  return (
    <AdhModalPopover id={SITES_OVERVIEW_POPOVER_ID} title="The Agentic Developer family">
      {groups.map((group) => (
        <nav
          key={group.label}
          className="adh-sites-popover__group"
          aria-label={group.label}
        >
          <h3 className="adh-sites-popover__group-title">{group.label}</h3>
          <ul className="adh-sites-popover__list">
            {group.sites.map((site) => (
              <li key={site.id}>
                <a
                  className="adh-sites-popover__item"
                  href={siteProdUrl(site.id, '/')}
                >
                  <span className="adh-sites-popover__name">{site.label}</span>
                  {site.description && (
                    <span className="adh-sites-popover__blurb">
                      {site.description}
                    </span>
                  )}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      ))}
    </AdhModalPopover>
  )
}
