'use client'

import Link from 'next/link'
import { type ReactElement } from 'react'
import { NavigationPopover, type PopoverEntry, type PopoverItem } from './NavigationPopover'
import { type SiteLink } from './SiteOptionsMenu'

export type SiteSwitcherProps = {
  /** The current site's display name — the switcher's trigger text. */
  siteName: string
  /** Where the site name points when there is nothing to switch to. */
  siteNameHref?: string
  /** The switch targets, supplied by the CALLER. This component holds no site
   *  registry and performs no lookup: it renders exactly the list it is handed,
   *  which is what makes the header reusable by a consumer that has no site
   *  family at all. */
  sites?: SiteLink[]
  /** Transform a chosen target's href before navigating — e.g. route the switch
   *  through a silent SSO redirect so the destination lands already signed in.
   *  Receives the target's `id` when it has one and its `href` otherwise, which is
   *  the same value used as the row's React key. Returning `undefined` keeps the
   *  target's own `href`. */
  onSwitchSite?: (idOrHref: string) => string | undefined
}

/**
 * The header's site-name control: a plain home link when there is nowhere to
 * switch to, and a {@link NavigationPopover} over the caller-supplied `sites`
 * when there is.
 *
 * This is the REGISTRY-FREE primitive. A consumer that owns a site registry keeps
 * its richer switcher — curated menu taxonomy, recents, workspaces — in its own
 * package and injects it through `AdhHeader`'s `siteSwitcher`
 * slot; that variant is deliberately NOT reachable from here, because every part
 * of it resolves a registry this package does not have.
 */
export function SiteSwitcher({
  siteName,
  siteNameHref = '/',
  sites = [],
  onSwitchSite,
}: SiteSwitcherProps): ReactElement {
  if (sites.length === 0) {
    return (
      <Link href={siteNameHref} className="adh-header__title">
        {siteName}
      </Link>
    )
  }

  const entries: PopoverEntry[] = sites.map((site) => ({
    kind: 'leaf',
    section: 0,
    item: {
      //  `id` is optional on the published `SiteLink` (its owner, SiteOptionsMenu,
      //  never reads it), so fall back to the href — unique among switch targets by
      //  construction, and a stable key either way.
      key: site.id ?? site.href,
      label: site.label,
      description: site.description,
      href: site.href,
    },
  }))

  return (
    <NavigationPopover
      entries={entries}
      triggerLabel={`${siteName} — switch site`}
      triggerText={siteName}
      triggerClassName="adh-header__title"
      onChoose={(item: PopoverItem) => {
        // The caller may rewrite the destination (SSO hand-off); absent that, use
        // the href it supplied. A full-page assign, because a switch crosses sites.
        const href = onSwitchSite?.(item.key) ?? item.href
        if (href) window.location.assign(href)
      }}
    />
  )
}
