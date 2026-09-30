<!-- leaf: implement-status-web-src-lib-1/colors--test-vectors · source: status-web-src-lib-colors.md -->

# Status Web Colors

## Conformance Test Vectors

The package has no `colors.test.ts`; these vectors are derived directly from the source tables and helpers.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| colors-001 | health-colors | `HEALTH_COLORS.down` | `"var(--color-apt-red)"` |
| colors-002 | health-colors, unknown-health-is-caution | `HEALTH_COLORS.unknown` | `"var(--color-apt-gold)"` |
| colors-003 | overall-colors | `OVERALL_COLORS.operational`, `OVERALL_COLORS.major_outage` | `"var(--color-apt-green)"`, `"var(--color-apt-red)"` |
| colors-004 | deploy-colors | `DEPLOY_COLORS.building`, `.queued`, `.canceled` | each `"var(--color-apt-gold)"` |
| colors-005 | deploy-unknown-muted | `DEPLOY_COLORS.unknown` | `"var(--color-apt-text-muted)"` |
| colors-006 | status-table-missing-key | `DEPLOY_COLORS["nonexistent"]` | `undefined` |
| colors-007 | env-colors, env-color-known | `envColor("staging")` | `"var(--color-apt-cat-violet)"` |
| colors-008 | env-color-fallback, env-fallback-color | `envColor(null)`, `envColor(undefined)`, `envColor("")`, `envColor("preview")` | each `"var(--color-apt-text-dim)"` |
| colors-009 | env-color-case-sensitive | `envColor("Production")` | `"var(--color-apt-text-dim)"` |
| colors-010 | env-badge-known | `envBadgeLabel("production")`, `("staging")`, `("testing")` | `"PROD"`, `"STAG"`, `"TEST"` |
| colors-011 | env-badge-unknown | `envBadgeLabel("preview")` | `"PREVIEW"` |
| colors-012 | env-badge-unknown | `envBadgeLabel("")` | `""` |
| colors-013 | env-categorical-hues | every value of `ENV_COLORS` | none equals `var(--color-apt-green)`, `var(--color-apt-gold)` or `var(--color-apt-red)` |
| colors-014 | palette-roles | `PALETTE.amber` | `"var(--color-apt-gold)"` |
| colors-015 | colors-surface-collapse | `COLORS.surfacePane === COLORS.surfaceHover` | `true`; both `"var(--color-apt-surface-2)"` |
| colors-016 | colors-text-soft | `COLORS.textSoft` | `"color-mix(in srgb, var(--color-apt-text) 80%, var(--color-apt-text-muted))"` |
| colors-017 | colors-amber-surfaces | `COLORS.amberBgMid` | `"color-mix(in srgb, var(--color-apt-gold) 30%, var(--color-apt-bg))"` |
| colors-018 | colors-amber-light | `COLORS.amberLight`; keys of `COLORS` | `"var(--color-apt-gold-bright)"`; no `greenLight` or `redLight` key |
| colors-019 | tint-form, tint-amber | `TINT.amberGlow` | `"color-mix(in srgb, var(--color-apt-gold) 45%, transparent)"` |
| colors-020 | tint-red | `TINT.redBgStrong` | `"color-mix(in srgb, var(--color-apt-red) 16%, transparent)"` |
| colors-021 | tint-blue | `TINT.blueBgMed` | `"color-mix(in srgb, var(--color-apt-blue) 14%, transparent)"` |
| colors-022 | tint-theme-independent | `TINT.shadowStrong`, `TINT.whiteGhost` | `"color-mix(in srgb, black 60%, transparent)"`, `"color-mix(in srgb, white 2%, transparent)"` |
| colors-023 | colors-misc | `COLORS.white`, `COLORS.dimBlue` | `"white"`, `"var(--color-apt-text-dim)"` |
| colors-024 | status-triad, css-string-values | every value of `HEALTH_COLORS`, `OVERALL_COLORS`, `DEPLOY_COLORS` | each starts with `var(--color-apt-` and contains no `#` |
| colors-025 | pure-helpers, no-side-effects | call `envColor("testing")` twice with a spy on `console`, `fetch` and `localStorage` | both return `"var(--color-apt-cat-pink)"`; no spy is called |
| colors-026 | env-object-prototype-keys | `typeof envColor("constructor")` | `"function"` (inherited key; see env-object-prototype-keys) |
