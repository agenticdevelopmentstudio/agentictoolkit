import type { ReactElement, ReactNode } from 'react';
import type { SiteId } from '@agentic-toolkit/adh-registry';
import type { ProfilePrincipal } from './types';
export interface ProfileViewProps {
    principal: ProfilePrincipal;
    /** The site this profile is being viewed ON, which decides whether the Full Profile link
     *  renders. Passed as a plain string from the server page rather than read from the site config
     *  here: a config is a SERVER-graph module (`site/SiteConfig`) and importing it from this
     *  client component would drag `research`'s sitemap reads into a browser bundle. */
    siteId: SiteId;
    /** This site's own public section, or nothing. */
    children?: ReactNode;
    /** Whether this view runs the signed-in widening itself. Default true, which is what
     *  every server-rendered consumer wants. `ProfileFallback` passes false because it
     *  already ran the hook to decide WHICH principal to render, and a second identical
     *  lookup would be pure waste. */
    upgrade?: boolean;
}
/**
 * A principal's profile, in the arrangement every site in the fleet shares:
 *
 *   [ standard header — avatar, name, general public info ]
 *   [ this site's own section, or nothing ]
 *   [ Full Profile → the hub, unless this IS the hub ]
 *
 * Lives in `@agentic-toolkit/adh` rather than `packages/ui` because it has to know site ids and
 * which one is the hub, and `ui` is the generic layer that must not.
 *
 * The header is `<UserCard>` unchanged — it already renders exactly what "general public info"
 * means here, and the backend has already removed every row the viewer may not see, so this
 * component makes no visibility decision of its own. It renders what it was handed.
 *
 * The one thing it does on its own is the second layer of the two-layer resolution: it runs
 * `useViewerPrincipal` over the principal it was given and renders the wider answer if one
 * arrives. That lives HERE, rather than in each of the six consumers, so every one of them gets
 * the signed-in widening without an API change — the prop stays "the principal you resolved",
 * and whether the viewer is entitled to more is this component's business, not theirs. The seed
 * is always a valid render, so a failed or absent upgrade simply leaves the anonymous view
 * standing. `upgrade={false}` is the one opt-out: `ProfileFallback` already ran the same hook to
 * decide which principal to render in the first place, so it passes its answer straight through
 * and tells this component not to duplicate the lookup.
 */
export declare function ProfileView({ principal, siteId, children, upgrade, }: ProfileViewProps): ReactElement;
/**
 * A profile on its way: the card's own skeleton, in ProfileView's frame, so the profile
 * replaces it in place when it arrives. A route's loading boundary (the hub's
 * `/<slug>/profile/loading.tsx`) renders this rather than composing the two itself: the frame
 * and the card are this directory's to change, and a site-side copy of either would stop
 * matching the day one of them does.
 */
export declare function ProfileSkeleton(): ReactElement;
//# sourceMappingURL=ProfileView.d.ts.map