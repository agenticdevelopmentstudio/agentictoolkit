<!-- leaf: implement-status-web-src-lib-1/deploy-display--test-vectors · source: status-web-src-lib-deploy-display.md -->

# Deploy Display

## Conformance Test Vectors

The source has no test file (no `deploy-display.test.ts`, and no test imports these functions). The vectors below are traced to the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-display-001 | glyph-vercel | `platformGlyph("vercel")` | `"▲"` |
| deploy-display-002 | glyph-glitchtip-text-presentation | `platformGlyph("glitchtip")` | `"⚠︎"` (length 2) |
| deploy-display-003 | glyph-fallback | `platformGlyph("netlify")` | `"◆"` |
| deploy-display-004 | glyph-fallback | `platformGlyph("")` | `"◆"` |
| deploy-display-005 | glyph-cloudflare, glyph-railway, glyph-http, glyph-dns, glyph-crunchy | each of `cloudflare-pages`, `railway`, `http`, `dns`, `crunchy` | `☁`, `⬢`, `◉`, `⌖`, `⛁` respectively |
| deploy-display-006 | platform-key-vocabulary, glyph-fallback | `platformGlyph("Vercel")` | `"◆"` (case-sensitive) |
| deploy-display-007 | color-vercel, color-cloudflare, color-railway, color-http, color-dns | each of `vercel`, `cloudflare-pages`, `railway`, `http`, `dns` | `var(--color-apt-text)`, `var(--color-apt-cat-orange)`, `var(--color-apt-cat-purple)`, `var(--color-apt-cat-teal)`, `var(--color-apt-cat-indigo)` |
| deploy-display-008 | color-crunchy-shares-http | `platformColor("crunchy") === platformColor("http")` | `true` |
| deploy-display-009 | color-glitchtip-shares-cloudflare | `platformColor("glitchtip")` | `"var(--color-apt-cat-orange)"` |
| deploy-display-010 | color-fallback | `platformColor("netlify")` | `"var(--color-apt-text-muted)"` |
| deploy-display-011 | color-env-hue-exclusion, color-theme-tokens-only | every known platform key | result starts with `var(--color-apt-` and is none of `cat-blue`, `cat-violet`, `cat-pink` |
| deploy-display-012 | label-table | `platformLabel("cloudflare-pages")` | `"CLOUDFLARE"` |
| deploy-display-013 | label-fallback-uppercase | `platformLabel("glitchtip")` | `"GLITCHTIP"` |
| deploy-display-014 | label-fallback-uppercase | `platformLabel("fly-io")` | `"FLY-IO"` |
| deploy-display-015 | short-label-overrides | `platformLabelShort("cloudflare-pages")`, `platformLabelShort("crunchy")` | `"CF"`, `"CB"` |
| deploy-display-016 | short-label-fallback | `platformLabelShort("railway")` | `"RAILWAY"` |
| deploy-display-017 | short-label-fallback, label-fallback-uppercase | `platformLabelShort("netlify")` | `"NETLIFY"` |
| deploy-display-018 | status-color-lookup | `deployStatusColor("success")`, `("failed")`, `("building")` | `var(--color-apt-green)`, `var(--color-apt-red)`, `var(--color-apt-gold)` |
| deploy-display-019 | status-color-unknown-muted | `deployStatusColor("unknown")` | `"var(--color-apt-text-muted)"` |
| deploy-display-020 | status-color-fallback | `deployStatusColor("rolling-back")` | `"var(--color-apt-gold)"` (equal to `canceled`) |
| deploy-display-021 | status-label-success, status-label-failed-uppercase | `deployStatusLabel("success")`, `deployStatusLabel("failed")` | `"ready"`, `"FAILED"` |
| deploy-display-022 | status-label-in-flight, status-label-canceled | `deployStatusLabel` of `building`, `queued`, `canceled` | `"building"`, `"queued"`, `"canceled"` |
| deploy-display-023 | status-label-unknown | `deployStatusLabel("unknown")` | `"outcome unknown"` |
| deploy-display-024 | status-label-passthrough | `deployStatusLabel("PROMOTED")` | `"PROMOTED"` |
| deploy-display-025 | pure-functions | call each export twice with the same argument | identical results; no global state changed |
| deploy-display-026 | prototype-key-lookup | `typeof platformColor("constructor")` | `"function"` (inherited key; see prototype-key-lookup) |
