import { type ComponentType, type ReactElement, type ReactNode } from 'react';
import type { SiteId } from '@agentic-toolkit/adh-registry';
import type { NavLink } from '@agentic-toolkit/adh/header';
import type { FooterLink } from '@agentic-toolkit/adh/footer';
import { type SiteHelp } from '@agenticdevelopertoolkit/ui/components/help-content';
/** The serializable half of a link: what a server layout can hand across the
 *  boundary. NavLink's `icon`/function form and FooterLink's `onSelect` cannot
 *  cross it, and a site that needs either is not describing chrome any more.
 *  Derived from FooterLink so it narrows when that type does. */
type PlainLink = Pick<Extract<FooterLink, {
    href: string;
}>, 'label' | 'href'>;
export type MarketingRootHtmlProps = {
    /** Optional site-owned header nav items — the serializable subset of NavLink (this is
     *  a server component, so the function form and icon fields can't cross the boundary;
     *  matchPaths keeps active-link highlighting available to sites). */
    navLinks?: Pick<NavLink, 'label' | 'href' | 'matchPaths'>[];
    /** Optional site-owned header items rendered OUTSIDE the collapsing nav, at the bar's
     *  trailing edge — an off-site destination (`toolkit`'s GitHub) rather than a route. */
    trailingNavLinks?: PlainLink[];
    /** Optional site-owned footer links, added to the shared legal/sites row. The
     *  copyright is the brand's, not the site's, and stays owned by SiteFooter. */
    footerLinks?: PlainLink[];
    /** The marketing site this document chrome is for — drives the header brand. */
    siteId: SiteId;
    /**
     * Whether the AuthProvider runs the cross-site cold-load silent-SSO probe (default `true`,
     * the feature-site behaviour) — on EVERY route, the landing page included.
     *
     * `false` means one thing now: this site does not recognize a signed-in visitor. It used to
     * mean something else as well, which is why it exists at all — the probe is a top-level
     * `/authorize?prompt=none` navigation (the central session cookie is host-only + SameSite=Lax,
     * so it CANNOT be done in the background), and it used to make that navigation on a guess, so
     * an origin the AS return-origin allow-list was missing stranded the visitor on the central
     * login page. A fully public site turned the probe off to be sure that never happened.
     * `beginSilentLogin` now asks the AS first (`preflightSsoReturn`) and navigates only on a yes,
     * so a public site keeps that guarantee with the probe ON, and no site in the family passes
     * `false` (<adh-tools>/sites/scripts/verify-site-uniformity.py fails one that starts).
     *
     * Set it only for a surface that must not navigate on load for a reason the preflight does not
     * cover, and say what that reason is. See docs/platform/cross-site-auth.md.
     */
    silentSso?: boolean;
    /**
     * The site's own header, in place of the shared `<MarketingSiteHeader siteId/>`.
     *
     * This slot exists because its absence was expensive. Four sites needed a different header
     * component — community's board controls, the registry's persona search, the cookbook's
     * search/sidebar controls, the hub's app bar — and with no way to pass one, each reproduced
     * the whole `<html>`/`<head>`/`<body>`/`AuthProvider`/`AppShell` scaffold to reach the one
     * `AppShell` prop it wanted. All four then wrote `<html lang="en">` with no `dir`, silently
     * leaving the locale seam this component computes from `getLocale()`. A missing slot does not
     * keep a site on the shared shell; it just moves the whole document into the site.
     *
     * A node rather than a component type: it is rendered in the same server pass, so a site can
     * wrap its header in a `<Suspense>` boundary (the cookbook does — see its layout) without this
     * component knowing anything about it. `navLinks`/`trailingNavLinks` are the shared header's
     * props and are ignored when a site supplies its own.
     */
    header?: ReactNode;
    /**
     * The site's own context providers, mounted between the shared `AuthProvider` and `AppShell`.
     *
     * The cross-cutting providers are NOT here: `AuthProvider` is above (so a site never restates
     * the client id, the token store, or the SSO probe) and `AppShell` mounts the feature-flag,
     * help and telemetry providers below. This is only for context a site genuinely owns — the
     * cookbook's chrome coordinator, the hub's debug console / settings overlay / workspaces menu.
     *
     * A component rather than an element, because it has to WRAP `children`. It renders in the
     * same server pass, so it may be a client component (each of today's is). A site that also
     * wants a document-level node beside the shell — the cookbook's film grain — renders it here
     * as a sibling of `children`; providers emit no DOM, so the result is the same markup a
     * hand-rolled `<body>` produced.
     */
    providers?: ComponentType<{
        children: ReactNode;
    }>;
    /** The site's help copy, published to the whole document.
     *
     *  A provider rather than a header prop: the `header` slot below lets a site
     *  replace the shared header entirely (four do), and a prop would reach the
     *  shared header and miss them. */
    help?: SiteHelp;
    children: ReactNode;
};
/**
 * The shared root-document shell for the ADH marketing family. Every marketing
 * site's `app/layout.tsx` was byte-identical except its `siteId` + `metadata`
 * (and all 22 `providers.tsx` were byte-identical), so the whole `<html>` …
 * `<AppShell>` scaffold lives here once:
 *  • `<html lang dir>` from the active-locale seam (`getLocale`/`htmlLang`/`localeDir`)
 *  • a `<head>` whose whole content is `<AdhThemeStyle/>` — the theme CSS variables, the
 *    appearance pre-paint script, and the font `<link>`s. The preconnects this line used to
 *    name as a second item are AdhThemeStyle's own: it derives them from the theme's font
 *    origins, so a theme that changes fonts changes them too. Nothing else belongs here;
 *    per-site `<head>` content is `metadata` in the site's own layout.
 *  • an `<AuthProvider clientId="adh" silentSso={silentSso}>` — a feature site
 *    (docs/platform/feature-sites-redesign.md) leaves the probe ON (default): the header is
 *    session-aware and `/home` is the signed-in feature surface. It fires once per tab, on
 *    EVERY route including the landing deck, gated by `shouldSilentRestore` (a readable hint
 *    cookie, or cross-apex where the cookie cannot be read) — and it is safe to fire there
 *    because `beginSilentLogin` asks the AS whether it will return the browser before it
 *    navigates, so an origin the allow-list is missing costs the avatar rather than stranding
 *    the visitor on the central login page. That guarantee is what retired the two client-side
 *    guesses this comment used to describe (a landing-route exemption and a local-hostname
 *    veto); see docs/platform/cross-site-auth.md. `silentSso={false}` opts a site out of
 *    recognition entirely — no site in the family does, and
 *    <adh-tools>/sites/scripts/verify-site-uniformity.py fails one that starts, so the escape hatch cannot
 *    be taken quietly. See the prop doc above.
 *  • `<AppShell header={header ?? <MarketingSiteHeader siteId/>} footer={…}>` — the shared
 *    chrome with the smart auth widget (avatar / Login+Sign up via SSO returnTo).
 *
 * EVERY site in the family mounts this. A site does not build its own `<html>` — a site that
 * needs something different declares it as a prop here, and if no prop fits, the prop is what
 * gets added. That rule is enforced (`<adh-tools>/sites/scripts/verify-site-uniformity.py`, check `shell`)
 * and it is not waivable by recording an exception, because the four documents that were once
 * excused are what taught us the cost: each was a copy of this file made to reach ONE slot, and
 * each silently dropped `dir` and the locale seam on the way. The per-site seams are
 * `header`, `providers`, `navLinks`, `trailingNavLinks`, `footerLinks` and `silentSso`.
 *
 * A server component: it renders the client `AuthProvider`/`SiteHeader` exactly as a
 * site layout would. Per-site `metadata` (the one genuinely per-site, SEO-bearing
 * part) and the site's `globals.css` import stay in each `app/layout.tsx`.
 *
 * Home: `@agentic-toolkit/adh/marketing` — adh VOCABULARY end to end (the ADH marketing
 * family's root document, its siteId, its clientId). It lived in the @adh-shared auth shim only
 * because that package owned the header/auth chrome it composes; Task 6.2 folded `SiteHeader`
 * into the app tier's header barrel and the toolkit took the generic halves, so the
 * circular-dependency reason for the old home is gone. The client pieces are still imported via their package
 * paths (kept external by tsup) so their 'use client' boundaries survive bundling,
 * mirroring the graph subsystem.
 */
export declare function MarketingRootHtml({ siteId, navLinks, trailingNavLinks, footerLinks, silentSso, header, providers, help, children, }: MarketingRootHtmlProps): ReactElement;
export {};
//# sourceMappingURL=MarketingRootHtml.d.ts.map