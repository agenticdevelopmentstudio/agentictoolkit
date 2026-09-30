<!-- leaf: implement-status-web-src-lib-1/colors · source: status-web-src-lib-colors.md -->

**Rules** (cite as `implement-status-web-src-lib-1/colors#<slug>`):

- `status-triad` MUST
- `health-colors` MUST
- `overall-colors` MUST
- `deploy-colors` MUST
- `deploy-unknown-muted` MUST
- `unknown-health-is-caution` MUST
- `status-table-missing-key` MUST
- `env-colors` MUST
- `env-categorical-hues` MUST
- `env-fallback-color` MUST
- `env-color-known` MUST
- `env-color-fallback` MUST
- `env-color-case-sensitive` MUST
- `env-badge-known` MUST
- `env-badge-unknown` MUST
- `env-badge-precondition` MUST
- `palette-roles` MUST
- `colors-surface-collapse` MUST
- `colors-text-soft` MUST
- `colors-amber-light` MUST
- `colors-amber-surfaces` MUST
- `colors-misc` MUST
- `tint-form` MUST
- `tint-amber` MUST
- `tint-red` MUST
- `tint-blue` MUST
- `tint-theme-independent` MUST
- `css-string-values` MUST
- `theme-token-owner` MUST
- `no-side-effects` MUST
- `pure-helpers` MUST
- `readonly-at-type-level` MUST
- `concurrency` MAY

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `env` (argument to `envColor`) | `string \| null \| undefined` | — | Environment name to color; nullish or unknown yields `ENV_FALLBACK_COLOR`. |
| `env` (argument to `envBadgeLabel`) | `string` | — | Environment name to label; unknown names are upper-cased. |
| `--color-apt-*` CSS custom properties | CSS color | Supplied by `@agenticdevelopertoolkit/themes` | Theme tokens every `var()` reference resolves against: `green`, `gold`, `gold-bright`, `red`, `blue`, `bg`, `surface`, `surface-2`, `border`, `text`, `text-muted`, `text-dim`, `cat-blue`, `cat-violet`, `cat-pink`. |

The module reads no environment variables, settings keys or injected dependencies.

## Localization

`envBadgeLabel` returns hard-coded English abbreviations; they are not localized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `ENV_BADGE_LABEL.production` | `PROD` | Env badge text for the production environment |
| `ENV_BADGE_LABEL.staging` | `STAG` | Env badge text for the staging environment |
| `ENV_BADGE_LABEL.testing` | `TEST` | Env badge text for the testing environment |

