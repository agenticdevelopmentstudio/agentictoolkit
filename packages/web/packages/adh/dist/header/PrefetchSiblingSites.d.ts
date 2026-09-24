/**
 * Makes switching between sibling sites in the header dropdown INSTANT and
 * flash-free instead of a multi-second cross-origin full-page reload.
 *
 * It injects a Speculation Rules document rule so the browser PRERENDERS a
 * sibling site the moment the user hovers its row in the switcher (eagerness
 * `moderate` = hover/pointerdown). A prerendered page activates on click with no
 * network wait and no white "ugly refresh" — the new document is swapped in
 * atomically.
 *
 * Scoped to LOCAL dev, where every sibling site is a SAME-SITE origin (the suite
 * serves them all as subdomains of one `*.dev.test` / `*.localhost` host), which
 * is the platform's precondition for cross-origin prerendering — paired with the
 * `Supports-Loading-Mode: credentialed-prerender` response header the apps send
 * (see `PRERENDER_HEADERS` in `@agentic-toolkit/next-headers`, merged into every
 * site's config by `@agentic-toolkit/adh-next-config`'s `adhNextConfig`). Every DEPLOYED
 * env puts each site on its OWN registrable domain (cross-site), where the platform
 * disallows prerender, so this is a deliberate no-op there — not a regression.
 *
 * Rendered once by {@link SiteMenuSwitcher}; returns no UI.
 */
export declare function PrefetchSiblingSites(): null;
//# sourceMappingURL=PrefetchSiblingSites.d.ts.map