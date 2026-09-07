'use client'

import { useEffect } from 'react'
import { detectEnv } from '@agentic-toolkit/adh-registry'

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
export function PrefetchSiblingSites(): null {
  useEffect(() => {
    if (typeof window === 'undefined') return
    // Cross-origin prerender needs same-site siblings; only local dev has them
    // (suite subdomains of one host). Deployed envs are cross-site ⇒ skip.
    // (Browsers without Speculation Rules support simply ignore the script.)
    if (detectEnv(window.location.hostname) !== 'local') return

    // Same-site host pattern: siblings share everything after the first DNS label
    // (`academy.hub-x.dev.test` ⇒ `*.hub-x.dev.test`). `window.location.host`
    // keeps any port (bare-localhost dev) so the pattern still matches.
    const hostPattern = window.location.host.replace(/^[^.]+/, '*')
    const rules = {
      prerender: [
        {
          where: { href_matches: `${window.location.protocol}//${hostPattern}/*` },
          eagerness: 'moderate',
        },
      ],
    }
    const script = document.createElement('script')
    script.type = 'speculationrules'
    script.textContent = JSON.stringify(rules)
    document.head.appendChild(script)
    return () => {
      script.remove()
    }
  }, [])
  return null
}
