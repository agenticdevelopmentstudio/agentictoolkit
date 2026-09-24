---
id: 63f8a602-58f8-4fdc-9461-b959be427a4d
title: Status Web Colors
domain: agentictoolkit://recipes/status-web-src-lib-colors
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Status-board color tables mapping health, overall, deploy and env values
  to shared theme CSS tokens, plus env badge helpers
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-src
references: []
approved-by: ''
approved-date: ''
---

# Status Web Colors

## Overview

`colors.ts` is the status board's palette module. It exports constant lookup tables that map status vocabularies (service health, overall board status, deploy status, environment) to CSS color strings, a set of named UI roles (`PALETTE`, `COLORS`) and semi-transparent tints (`TINT`), plus two pure helpers: `envColor` and `envBadgeLabel`. Every theme-dependent value is a CSS `var(--color-apt-*)` reference or a `color-mix(in srgb, …)` expression over one; the actual color values are owned by `@agenticdevelopertoolkit/themes`, not by this module ("No hard-coded hex: a token's value is owned by @agenticdevelopertoolkit/themes, not copied here"). The module is re-exported from the package entry point (`export * from "./lib/colors"` in `src/index.ts`) and is consumed by the board's components (for example `UptimeBar`, `ChecksStrip`, `ActivityPanel`, `Dashboard`) and by `deployStatusColor` in `deploy-display.ts`.

Use it whenever a status-board view needs a color for a status value, an environment tag, or a surface/text/tint role, so the board tracks the suite theme.

## Behavioral Requirements

### Status color tables

- **status-triad**: The module MUST express status using exactly three status colors: good as `var(--color-apt-green)`, caution as `var(--color-apt-gold)`, and hard fail as `var(--color-apt-red)`.
- **health-colors**: `HEALTH_COLORS` MUST map `healthy` to the good color, `degraded` to the caution color, `down` to the hard-fail color, and `unknown` to the caution color.
- **overall-colors**: `OVERALL_COLORS` MUST map `operational` to the good color, `degraded` to the caution color, `major_outage` to the hard-fail color, and `unknown` to the caution color.
- **deploy-colors**: `DEPLOY_COLORS` MUST map `success` to the good color, `failed` to the hard-fail color, and each of `building`, `queued` and `canceled` to the caution color.
- **deploy-unknown-muted**: `DEPLOY_COLORS.unknown` MUST be `var(--color-apt-text-muted)`, not the caution color, because it denotes "an ABSENCE of a verdict" for an in-flight phase the backend expired unconfirmable; this matches the `stale` tone in `row-model.ts` (`TONE_COLOR.stale`).
- **unknown-health-is-caution**: In `HEALTH_COLORS` and `OVERALL_COLORS`, `unknown` MUST share the caution color rather than a muted color (unlike `DEPLOY_COLORS.unknown`).
- **status-table-missing-key**: A lookup of a key absent from `HEALTH_COLORS`, `OVERALL_COLORS` or `DEPLOY_COLORS` MUST yield `undefined` at runtime; the tables supply no default of their own, and each caller chooses its fallback (for example `deployStatusColor` in `deploy-display.ts` falls back to `DEPLOY_COLORS["canceled"]`).

### Environment colors and labels

- **env-colors**: `ENV_COLORS` MUST map `production` to `var(--color-apt-cat-blue)`, `staging` to `var(--color-apt-cat-violet)`, and `testing` to `var(--color-apt-cat-pink)`.
- **env-categorical-hues**: Environment colors MUST come from the theme's categorical `apt-cat-*` hues and MUST NOT reuse any status-triad token, so an env badge "never reads as a health signal".
- **env-fallback-color**: `ENV_FALLBACK_COLOR` MUST be `var(--color-apt-text-dim)`.
- **env-color-known**: `envColor(env)` MUST return `ENV_COLORS[env]` when `env` is a truthy string whose lookup is truthy.
- **env-color-fallback**: `envColor(env)` MUST return `ENV_FALLBACK_COLOR` when `env` is `null`, `undefined`, the empty string, or a string with no truthy entry in `ENV_COLORS`.
- **env-color-case-sensitive**: `envColor` MUST match keys case-sensitively; `"Production"` MUST return `ENV_FALLBACK_COLOR`.
- **env-badge-known**: `envBadgeLabel(env)` MUST return `"PROD"` for `production`, `"STAG"` for `staging`, and `"TEST"` for `testing`.
- **env-badge-unknown**: `envBadgeLabel(env)` MUST return `env.toUpperCase()` for any other string, with no truncation to four characters (for example `"preview"` returns `"PREVIEW"`).
- **env-badge-precondition**: `envBadgeLabel` takes a non-null `string` by its type signature; a caller MUST NOT pass `null` or `undefined` (unlike `envColor`, it has no nullish guard).
- **env-object-prototype-keys**: `ENV_COLORS` and `ENV_BADGE_LABEL` are plain object literals, so an env string naming an inherited `Object.prototype` member (for example `"constructor"` or `"toString"`) makes `envColor` and `envBadgeLabel` return the inherited value (a function) instead of a string. The lookups are not restricted to own keys; the parameters are typed `string`, and nothing in the package passes such a key or tests one. A port using a real dictionary or an own-property check falls back normally instead, which is the intended behavior.

### UI roles and tints

- **palette-roles**: `PALETTE` MUST expose `bg`, `surface`, `border`, `text`, `muted`, `dim`, `blue`, `green`, `amber` and `red`, mapped to `--color-apt-bg`, `--color-apt-surface`, `--color-apt-border`, `--color-apt-text`, `--color-apt-text-muted`, `--color-apt-text-dim`, `--color-apt-blue`, `--color-apt-green`, `--color-apt-gold` and `--color-apt-red` respectively.
- **colors-surface-collapse**: `COLORS.surfaceDeep` MUST be `var(--color-apt-bg)`, `COLORS.surfaceMid` MUST be `var(--color-apt-surface)`, and both `COLORS.surfacePane` and `COLORS.surfaceHover` MUST be `var(--color-apt-surface-2)` ("near steps collapse onto the nearest token").
- **colors-text-soft**: `COLORS.textSoft` MUST be `color-mix(in srgb, var(--color-apt-text) 80%, var(--color-apt-text-muted))`.
- **colors-amber-light**: `COLORS.amberLight` MUST be `var(--color-apt-gold-bright)`; the module MUST NOT define bright variants for green or red, because the theme has none.
- **colors-amber-surfaces**: `COLORS.amberBgDeep`, `amberBgDeeper` and `amberBgMid` MUST mix `var(--color-apt-gold)` into `var(--color-apt-bg)` at 8%, 6% and 30% respectively.
- **colors-misc**: `COLORS.border` MUST be `var(--color-apt-border)`, `textFaint` MUST be `var(--color-apt-text-muted)`, `signRim` MUST be `var(--color-apt-text)`, `gold` MUST be `var(--color-apt-gold)`, `dimBlue` MUST be `var(--color-apt-text-dim)`, and `white` MUST be the literal `white`.
- **tint-form**: Every `TINT` value MUST have the form `color-mix(in srgb, <color> <N>%, transparent)`, applying alpha by mixing with `transparent` rather than using `rgba` or hex alpha.
- **tint-amber**: `TINT` amber entries MUST use `var(--color-apt-gold)` at `amberTint` 6%, `amberTintMed` 8%, `amberBg` 10%, `amberBgMed` 12%, `amberBgStrong` 18%, `amberBorder` 35%, `amberBorderStrong` 40%, and `amberGlow` 45%.
- **tint-red**: `TINT` red entries MUST use `var(--color-apt-red)` at `redBg` 7%, `redBgMed` 9%, `redBgStrong` 16%, and `redBorder` 40%.
- **tint-blue**: `TINT` blue entries MUST use `var(--color-apt-blue)` at `blueBg` 7% and `blueBgMed` 14%.
- **tint-theme-independent**: `TINT.shadow`, `shadowMed` and `shadowStrong` MUST mix literal `black` at 45%, 55% and 60%, and `TINT.whiteGhost` MUST mix literal `white` at 2%; these values MUST NOT depend on the theme.

### Data shape, purity and side effects

- **css-string-values**: Every exported color value MUST be a CSS color string (a `var()` reference, a `color-mix()` expression, or a named color) that is resolved by the browser at render time, never a precomputed hex or RGB value.
- **theme-token-owner**: Token values MUST be supplied by the host page's stylesheet from `@agenticdevelopertoolkit/themes`; this module MUST NOT define or inject any CSS custom property.
- **no-side-effects**: Importing the module and calling `envColor` or `envBadgeLabel` MUST perform no I/O, DOM access, logging, network, or storage access.
- **pure-helpers**: `envColor` and `envBadgeLabel` MUST be deterministic: the same input MUST always produce the same output.
- **readonly-at-type-level**: `PALETTE`, `COLORS` and `TINT` MUST be declared `as const` (readonly literal types); none of the exported objects is frozen at runtime.
- **concurrency**: The module runs on the single JavaScript thread and holds no mutable state, so calls MAY occur from any render without ordering constraints.

## Appearance

Not applicable — this is a palette of CSS color strings and lookup helpers, not a visual component.

## States

Not applicable — this is a palette of CSS color strings and lookup helpers, not a visual component.

## Accessibility

Not applicable — this is a palette of CSS color strings and lookup helpers, not a visual component.

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

## Edge Cases

- **Null and empty env for envColor**: `null`, `undefined` or `""` MUST return `ENV_FALLBACK_COLOR` via the truthiness guard.
- **Null env for envBadgeLabel**: passing `null` or `undefined` violates the `string` parameter type; at runtime `env.toUpperCase()` throws a `TypeError`. Callers MUST supply a string.
- **Empty env for envBadgeLabel**: `""` has no entry, so the function MUST return `"".toUpperCase()`, the empty string.
- **Unknown env names**: an unknown env MUST get the dim fallback color from `envColor` and its full upper-cased name from `envBadgeLabel`; the badge is not truncated, so long names widen the env column beyond the four characters the authoring comment describes for known envs.
- **Case variants**: `"PRODUCTION"` or `"Production"` MUST NOT match `production`; `envColor` returns the fallback and `envBadgeLabel` returns the upper-cased input (`"PRODUCTION"`).
- **Inherited object keys**: env strings such as `"constructor"`, `"toString"` or `"__proto__"` resolve inherited members of the object literals and return non-string values; see env-object-prototype-keys.
- **Missing status key**: a status string absent from a status table MUST yield `undefined`; the module raises no error and the caller supplies the fallback.
- **Undefined theme token**: if the host page does not define a referenced `--color-apt-*` property, the browser treats the `var()` as invalid at computed-value time and the CSS property falls back to its inherited or initial value; this module neither detects nor reports that, and the token set is owned by `@agenticdevelopertoolkit/themes`.
- **Browsers without color-mix()**: `COLORS.textSoft`, the amber surfaces and every `TINT` value depend on CSS `color-mix()`; in an engine without it the declaration is invalid and is dropped by the browser. The module provides no fallback value.
- **Runtime mutation**: the exported objects are not frozen, so a consumer that writes to one (possible for the `Record<string, string>` tables without a type error) changes the value for every other consumer in the page. No consumer in the package does this.
- **Concurrent access**: not applicable; the module has no mutable state and runs on the single JavaScript thread.
- **Error, offline and I/O states**: not applicable; the module performs no I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `env` (argument to `envColor`) | `string \| null \| undefined` | — | Environment name to color; nullish or unknown yields `ENV_FALLBACK_COLOR`. |
| `env` (argument to `envBadgeLabel`) | `string` | — | Environment name to label; unknown names are upper-cased. |
| `--color-apt-*` CSS custom properties | CSS color | Supplied by `@agenticdevelopertoolkit/themes` | Theme tokens every `var()` reference resolves against: `green`, `gold`, `gold-bright`, `red`, `blue`, `bg`, `surface`, `surface-2`, `border`, `text`, `text-muted`, `text-dim`, `cat-blue`, `cat-violet`, `cat-pink`. |

The module reads no environment variables, settings keys or injected dependencies.

## Deep Linking

Not applicable: the module exports constants and pure functions and registers no route or URL.

## Localization

`envBadgeLabel` returns hard-coded English abbreviations; they are not localized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `ENV_BADGE_LABEL.production` | `PROD` | Env badge text for the production environment |
| `ENV_BADGE_LABEL.staging` | `STAG` | Env badge text for the staging environment |
| `ENV_BADGE_LABEL.testing` | `TEST` | Env badge text for the testing environment |

## Accessibility Options

Not applicable: the module returns fixed CSS strings and reads no Reduce Motion, Increase Contrast or Differentiate Without Color setting; any contrast adaptation belongs to the theme tokens it references.

## Feature Flags

Not applicable: no export is gated by a flag.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only environment names and status keywords and stores or transmits nothing.

## Logging

Not applicable: the module contains no logging calls.

## Platform Notes

- **SwiftUI**: Model the tables as `[String: Color]` dictionaries or, better, as enums with a `color` property (`enum HealthStatus { case healthy, degraded, down, unknown }`) so lookups are total. Theme tokens map to named colors in an asset catalog or a shared `ShapeStyle` extension; `color-mix` translates to `Color.mix(with:by:in:)` (iOS 18 / macOS 15+) or `.opacity(_:)` for the mix-with-`transparent` tints. `envColor`/`envBadgeLabel` become static functions on an `Environment` type; a Swift dictionary has no prototype chain, so the inherited-key issue disappears.
- **Compose**: Hold tokens in a `MaterialTheme`-style `CompositionLocal` of a custom `Immutable` data class (`AptColors`); status tables become `when` expressions over enum classes. Tints are `color.copy(alpha = 0.06f)`; mixes into a background use `androidx.compose.ui.graphics.lerp(bg, gold, 0.08f)`. Kotlin `Map` lookups return `null` for missing keys, matching the JS `undefined`, and have no inherited keys.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/colors.ts` returns CSS strings consumed in inline `style` props, so resolution is deferred to the browser and theme switches apply without re-render. It depends on the host stylesheet defining `--color-apt-*` and on CSS `color-mix()` support. A safer port would use `Object.hasOwn` or a `Map` for the env lookups.
- **AppKit / UIKit**: Use `NSColor(named:)` / `UIColor(named:)` from an asset catalog with appearance variants for the tokens; tints via `withAlphaComponent(_:)`, mixes via `NSColor.blended(withFraction:of:)` (AppKit) or manual component interpolation (UIKit). Dynamic colors resolve per trait collection, which is the analogue of CSS variables re-resolving on theme change.
- **WinUI 3**: Put each token in a `ResourceDictionary` under `ThemeDictionaries` (`Default`/`Light`/`HighContrast`) as `SolidColorBrush` resources (`AptGreenBrush`, `AptGoldBrush`, …) and reference them with `{ThemeResource AptGoldBrush}` so they re-resolve on theme change like `var()`. There is no `color-mix`: precompute tints as brushes with `Opacity="0.06"` or as `Color` values with a scaled alpha channel, and blended surfaces (`amberBgDeep`) as separate theme resources or via a helper that interpolates `Windows.UI.Color` channels. Status tables become C# `enum`s with a `switch` expression returning a brush key, or a `FrozenDictionary<string, string>` (System.Collections.Frozen) of resource keys; `TryGetValue` replaces the `undefined` result, and C# dictionaries have no inherited-key hazard. `envBadgeLabel` becomes a static method using `ToUpperInvariant()` for unknowns. For code-behind lookups use `Application.Current.Resources["AptGoldBrush"]`; for binding, an `IValueConverter` that maps a status string to a brush.

## Design Decisions

**Decision**: Every color is a theme-token reference, never a hard-coded hex value.
**Rationale**: The authoring comment states the board "tracks the same theme as the rest of the suite" and that shade changes against the old bespoke values are intentional; ownership of values stays with `@agenticdevelopertoolkit/themes`.
**Approved**: pending

**Decision**: Alpha is applied with `color-mix(in srgb, <token> N%, transparent)` rather than `rgba()`.
**Rationale**: A `var()` token cannot take an alpha channel directly, and the comment names `color-mix` as "the form the UI checker accepts"; the percentages mirror the old `rgba` opacities.
**Approved**: pending

**Decision**: `DEPLOY_COLORS.unknown` is muted text, while `unknown` in the health and overall tables is amber.
**Rationale**: For deploys, `unknown` is an expired, unconfirmable in-flight phase, "an ABSENCE of a verdict, muted (never the amber of live progress)", matching `row-model`'s `stale` tone. The health and overall tables keep `unknown` at caution.
**Approved**: pending

**Decision**: Environment colors use the categorical `apt-cat-*` hues.
**Rationale**: They must read as "which env", never as a health signal, and must not collide with the platform badges, which use other `apt-cat-*` hues.
**Approved**: pending

**Decision**: Surface steps finer than the theme's three levels collapse onto the nearest token (`surfacePane` and `surfaceHover` share `surface-2`).
**Rationale**: The monitor had finer steps than the theme exposes; collapsing keeps every value theme-owned at the cost of a visible hover step.
**Approved**: pending

**Decision**: Only amber has a bright headline variant (`amberLight`).
**Rationale**: The theme exposes `gold-bright` but no bright green or red, so green and red headlines use `PALETTE.green` / `PALETTE.red` directly with "no redundant same-value alias".
**Approved**: pending

**Decision**: Env badge labels are four upper-case characters for known envs; unknown envs are upper-cased but not truncated.
**Rationale**: Four characters keep the env column narrow; unknowns stay recognizable rather than ambiguous.
**Approved**: pending

**Decision**: Shadows and the white ghost use literal `black` / `white`.
**Rationale**: The comment calls them theme-independent.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |

**Separation of concerns.** The module holds only color data and two pure helpers, with no React, DOM or I/O; components apply the values and the theme package owns the token values.

**Unit test coverage.** There is no `colors.test.ts`, and no test asserts `envColor`, `envBadgeLabel` or the table contents; `row-model.test.ts` covers only `row-model`'s own tone colors.

**Explicit error handling.** `envColor` handles nullish and unknown input with an explicit fallback, and missing status keys return `undefined` for the caller to handle. The env lookups do not restrict themselves to own keys, so inherited object members leak through as non-string values (see env-object-prototype-keys), and `envBadgeLabel` throws on nullish input, which its type signature forbids.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from `status-web/src/lib/colors.ts` |
