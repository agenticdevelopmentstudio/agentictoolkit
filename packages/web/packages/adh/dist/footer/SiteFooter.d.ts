import { type FooterLink } from '@agentic-toolkit/adh/footer';
export type SiteFooterProps = {
    links?: FooterLink[];
    /** Mount bitbag. Default true — he belongs on every real footer; `false` leaves him out,
     *  and the bar keeps no corner for him. A {@link SiteFooterProps.specimen | specimen}
     *  never mounts him, whatever this says.
     *
     *  On THIS component, not the {@link ToolkitFooter} primitive it wraps: the
     *  primitive takes a generic `trailing` slot and has no idea bitbag exists, which
     *  is the whole point of the split. */
    chat?: boolean;
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
    specimen?: boolean;
    /** The running server's own build identity, passed by {@link AppShell} in development
     *  only. Omitted everywhere else, where the baked `NEXT_PUBLIC_*` literals are the
     *  build and correct by construction — see {@link buildVersionLabel}.
     *
     *  A plain serializable object, deliberately: this component is `'use client'`, so the
     *  value has to cross the server/client boundary as data. It cannot be read here —
     *  resolving it needs `node:fs` and a `git` fork. */
    live?: {
        version?: string;
        sha?: string;
    };
};
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
export declare function buildVersionLabel(live?: {
    version?: string;
    sha?: string;
}): import("react").JSX.Element | null;
/** adh's footer: the toolkit's identity-free primitive ({@link ToolkitFooter}, published as
 *  `AdhFooter` from this same barrel) plus everything that IS adh — the studio's copyright
 *  menu, the About dialog, the sites popover, the legal modals, and bitbag himself. The
 *  copyright is a fixed brand line, deliberately not per-site.
 *
 *  Named `SiteFooter` rather than `AdhFooter`: this barrel already publishes an `AdhFooter`
 *  — the registry-free primitive this component wraps. The two are unrelated components
 *  that happened to share a name; this one is adh's REGISTRY-AWARE composition. */
export declare function SiteFooter({ links, chat, live, specimen }: SiteFooterProps): import("react").JSX.Element;
//# sourceMappingURL=SiteFooter.d.ts.map