import { type ReactElement } from 'react';
import { type SiteLink } from './SiteOptionsMenu';
export type SiteSwitcherProps = {
    /** The current site's display name — the switcher's trigger text. */
    siteName: string;
    /** Where the site name points when there is nothing to switch to. */
    siteNameHref?: string;
    /** The switch targets, supplied by the CALLER. This component holds no site
     *  registry and performs no lookup: it renders exactly the list it is handed,
     *  which is what makes the header reusable by a consumer that has no site
     *  family at all. */
    sites?: SiteLink[];
    /** Transform a chosen target's href before navigating — e.g. route the switch
     *  through a silent SSO redirect so the destination lands already signed in.
     *  Receives the target's `id` when it has one and its `href` otherwise, which is
     *  the same value used as the row's React key. Returning `undefined` keeps the
     *  target's own `href`. */
    onSwitchSite?: (idOrHref: string) => string | undefined;
};
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
export declare function SiteSwitcher({ siteName, siteNameHref, sites, onSwitchSite, }: SiteSwitcherProps): ReactElement;
//# sourceMappingURL=SiteSwitcher.d.ts.map