---
id: 691f84ba-242a-40bc-a164-c95e535bb387
title: Deploy Display
domain: agentictoolkit://cookbook/status-web/lib/deploy-display
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure lookups mapping a deploy platform or deploy status string to its glyph,
  theme color token and badge label
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/deploy-status
references: []
approved-by: ''
approved-date: ''
---

# Deploy Display

## Overview

`deploy-display.ts` (`packages/web/packages/status-web/src/lib/deploy-display.ts`) is the status dashboard's platform taxonomy. Its header comment states its purpose: "glyph, brand color, and badge label for each deploy platform (plus the http/dns health checks). One module owns 'what a platform looks like', so adding a platform is a single edit here."

It exports six pure functions:

- `platformGlyph(platform)` returns a Unicode glyph.
- `platformColor(platform)` returns a CSS color expression that references a theme token.
- `platformLabel(platform)` returns an upper-case badge label.
- `platformLabelShort(platform)` returns a compact label for dense strips.
- `deployStatusColor(status)` returns the color for a deploy status dot or label.
- `deployStatusLabel(status)` returns a short text label for a deploy status.

The module has no state, no I/O and no side effects. It imports the `DeployStatus` type from `./deploy-status` and the `DEPLOY_COLORS` map from `./colors`. The callers are dashboard components (`DeployList`, `StatusMatrix`, `StatusRow`, `KpiStrip`, `GlobalPanel`, `UnconfiguredProjectsBanner`, `AutoConfigureReview`, `configure/ProjectBrowser`, `configure/PlatformProjects`) and `row-detail.ts`. They render the returned strings and never branch on them. The server-side status vocabulary is specified in [Monitor Deploy Status](agentictoolkit://cookbook/status-server/monitor/deploy-status).

## Behavioral Requirements

### Platform keys

- **platform-key-vocabulary**: The module MUST recognise these platform keys, compared by exact, case-sensitive string equality: `vercel`, `cloudflare-pages`, `railway`, `http`, `dns`, `crunchy`, `glitchtip`. `http` and `dns` are health checks, not hosting platforms. `crunchy` is a database, and `glitchtip` stands for thrown errors.
- **platform-input-type**: Every platform function MUST accept any `string` and MUST NOT throw for any string input.

### platformGlyph

- **glyph-signature**: `platformGlyph(platform: string)` MUST return a `string`.
- **glyph-vercel**: `platformGlyph` MUST return `▲` (U+25B2) for `vercel`.
- **glyph-cloudflare**: `platformGlyph` MUST return `☁` (U+2601) for `cloudflare-pages`.
- **glyph-railway**: `platformGlyph` MUST return `⬢` (U+2B22) for `railway`.
- **glyph-http**: `platformGlyph` MUST return `◉` (U+25C9) for `http`.
- **glyph-dns**: `platformGlyph` MUST return `⌖` (U+2316) for `dns`.
- **glyph-crunchy**: `platformGlyph` MUST return `⛁` (U+26C1) for `crunchy`.
- **glyph-glitchtip-text-presentation**: `platformGlyph` MUST return the two-code-point string U+26A0 U+FE0E for `glitchtip`. The source comment says the bare warning sign has an emoji presentation by default on macOS and iOS, so it would render full-colour and double-width beside six monochrome glyphs. VARIATION SELECTOR-15 forces the text form.
- **glyph-fallback**: `platformGlyph` MUST return `◆` (U+25C6) for every other string, including the empty string.

### platformColor

- **color-signature**: `platformColor(platform: string)` MUST return a `string` holding a CSS color expression.
- **color-vercel**: `platformColor` MUST return `var(--color-apt-text)` for `vercel`. The source comment calls this the brand near-white.
- **color-cloudflare**: `platformColor` MUST return `var(--color-apt-cat-orange)` for `cloudflare-pages`.
- **color-railway**: `platformColor` MUST return `var(--color-apt-cat-purple)` for `railway`.
- **color-http**: `platformColor` MUST return `var(--color-apt-cat-teal)` for `http`.
- **color-dns**: `platformColor` MUST return `var(--color-apt-cat-indigo)` for `dns`.
- **color-crunchy-shares-http**: `platformColor` MUST return `var(--color-apt-cat-teal)` for `crunchy`, the same value as `http`.
- **color-glitchtip-shares-cloudflare**: `platformColor` MUST return `var(--color-apt-cat-orange)` for `glitchtip`, the same value as `cloudflare-pages`.
- **color-fallback**: `platformColor` MUST return `var(--color-apt-text-muted)` for any platform with no own entry in the color map.
- **color-env-hue-exclusion**: A platform color MUST NOT equal an environment hue. The environment hues in `ENV_COLORS` are `var(--color-apt-cat-blue)`, `var(--color-apt-cat-violet)` and `var(--color-apt-cat-pink)`. The source comment gives the reason: a row that shows both an env badge and a platform badge must read unambiguously.
- **color-theme-tokens-only**: Every returned platform color MUST be a `var(--color-apt-*)` theme-token reference, never a literal hex value. The token values are owned by the shared theme package.

### platformLabel

- **label-signature**: `platformLabel(platform: string)` MUST return a `string`.
- **label-table**: `platformLabel` MUST return `VERCEL` for `vercel`, `CLOUDFLARE` for `cloudflare-pages`, `RAILWAY` for `railway`, `HTTP` for `http`, `DNS` for `dns` and `CRUNCHY` for `crunchy`.
- **label-fallback-uppercase**: `platformLabel` MUST return `platform.toUpperCase()` for any platform with no own entry in the label map. This includes `glitchtip`, which has no label entry and so yields `GLITCHTIP`.

### platformLabelShort

- **short-label-signature**: `platformLabelShort(platform: string)` MUST return a `string`.
- **short-label-overrides**: `platformLabelShort` MUST return `CF` for `cloudflare-pages` and `CB` for `crunchy`.
- **short-label-fallback**: `platformLabelShort` MUST return `platformLabel(platform)` for every platform with no short override. For example, it returns `VERCEL` for `vercel`.

### deployStatusColor

- **status-color-signature**: `deployStatusColor(status: DeployStatus | string)` MUST return a `string`. `DeployStatus` is `"success" | "failed" | "building" | "queued" | "canceled" | "unknown"`.
- **status-color-lookup**: `deployStatusColor` MUST return `DEPLOY_COLORS[status]` when that entry exists. The values are `success` → `var(--color-apt-green)`, `failed` → `var(--color-apt-red)`, `building`/`queued`/`canceled` → `var(--color-apt-gold)`, and `unknown` → `var(--color-apt-text-muted)`.
- **status-color-unknown-muted**: `deployStatusColor("unknown")` MUST return the muted token, not the amber used for live progress. The `DEPLOY_COLORS` comment says `unknown` is "an ABSENCE of a verdict".
- **status-color-fallback**: `deployStatusColor` MUST return `DEPLOY_COLORS["canceled"]` (`var(--color-apt-gold)`) for any status string that is not a key of `DEPLOY_COLORS`. An unrecognised status therefore renders amber, not muted.
- **status-color-token-not-hex**: `deployStatusColor` MUST return a theme-token expression. Its doc comment says "CSS hex color", but `DEPLOY_COLORS` holds only `var(--color-apt-*)` references, so the doc comment is stale.

### deployStatusLabel

- **status-label-signature**: `deployStatusLabel(status: DeployStatus | string)` MUST return a `string`.
- **status-label-success**: `deployStatusLabel` MUST return `ready` for `success`.
- **status-label-failed-uppercase**: `deployStatusLabel` MUST return `FAILED`, in upper case, for `failed`. It is the only upper-case status label.
- **status-label-in-flight**: `deployStatusLabel` MUST return `building` for `building` and `queued` for `queued`.
- **status-label-canceled**: `deployStatusLabel` MUST return `canceled` for `canceled`.
- **status-label-unknown**: `deployStatusLabel` MUST return `outcome unknown` for `unknown`. The source comment says `unknown` is an in-flight phase the backend expired without confirmation, and the label must say so rather than echo the raw enum.
- **status-label-passthrough**: `deployStatusLabel` MUST return the input string unchanged for any other status.

### Contract-wide

- **pure-functions**: Every export MUST be a synchronous, side-effect-free function whose result depends only on its argument and the module's constant maps.
- **no-mutation**: The module MUST NOT expose its lookup maps (`PLATFORM_COLOR`, `PLATFORM_LABEL`, `PLATFORM_LABEL_SHORT`). They are module-private constants, and no function mutates them.
- **concurrency**: The functions MAY be called from any context. They run on the single JavaScript thread, hold no state and cannot interleave.
- **prototype-key-lookup**: `platformColor`, `platformLabel`, `platformLabelShort` and `deployStatusColor` index plain object literals and fall back only on `null`/`undefined` (`??`), so an inherited key such as `constructor` or `toString` returns the inherited value (a function) instead of a string. The parameters are typed `string`, and nothing in the package passes such a key or tests one. A port using a real dictionary or an own-property check returns the fallback instead, which is the intended behavior.

## Appearance

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

## States

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

## Accessibility

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

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

## Edge Cases

- **Empty platform string**: `platformGlyph("")` MUST return `◆`, `platformColor("")` MUST return the muted token, and `platformLabel("")` and `platformLabelShort("")` MUST return `""`. No function validates or rejects the empty string.
- **Empty status string**: `deployStatusColor("")` MUST return the amber `canceled` color, and `deployStatusLabel("")` MUST return `""`.
- **Case mismatch**: A key that differs only in case, such as `Vercel` or `SUCCESS`, MUST miss every map and take the fallback path. There is no normalisation.
- **Unknown platform**: A platform the module does not know MUST still render. It gets the `◆` glyph, the muted color, and its own name upper-cased as the label. The module MUST NOT throw.
- **Unknown status**: An unrecognised status MUST render amber (the `canceled` color), and its label MUST be the raw string. This differs from the known `unknown` status, which renders muted with the label `outcome unknown`.
- **glitchtip partial registration**: `glitchtip` has a glyph and a color but no label entry and no short label. Both label functions MUST yield `GLITCHTIP` through the upper-case fallback.
- **Shared hues**: `crunchy`/`http` and `glitchtip`/`cloudflare-pages` MUST return identical colors. The source comment says the glyph and label disambiguate them, and glitchtip rows (error incidents) and cloudflare rows (deploys) never appear in the same list.
- **Glyph string length**: The `glitchtip` glyph MUST be two UTF-16 code units long. A port that measures or truncates glyphs by code-unit count MUST keep the variation selector.
- **Inherited object keys**: Inputs such as `constructor`, `toString` or `__proto__` currently return non-string values from the map lookups. See prototype-key-lookup.
- **Concurrent calls**: Not applicable. The functions are pure and run on the single JavaScript thread.
- **Error states, offline, timeouts, cancellation**: Not applicable. The module performs no I/O, has no dependency that can fail, and cannot be cancelled or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | `string` | none (required) | Platform or check key passed to the four platform functions. Unknown keys fall back as described above. |
| `status` | `DeployStatus \| string` | none (required) | Deploy status passed to `deployStatusColor` and `deployStatusLabel`. |
| `DEPLOY_COLORS` | `Record<string, string>` (imported from `./colors`) | theme-token map | Supplies the status colors. The fallback for unrecognised statuses is its `canceled` entry. |
| `--color-apt-*` CSS custom properties | theme tokens | owned by the shared theme package | The returned strings resolve only where the theme stylesheet defines these properties. |

The module reads no environment variables and no settings keys, and takes no injected dependencies.

## Deep Linking

Not applicable: the module is a set of pure lookup functions and defines no route or URL.

## Localization

The module returns hardcoded English strings and has no localization layer. These are facts of the source, not gaps.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `deployStatusLabel.success` | `ready` | Status label for a successful deploy |
| `deployStatusLabel.failed` | `FAILED` | Status label for a failed deploy (upper case for emphasis) |
| `deployStatusLabel.building` | `building` | Status label while building or deploying |
| `deployStatusLabel.queued` | `queued` | Status label for a queued build |
| `deployStatusLabel.canceled` | `canceled` | Status label for a canceled build |
| `deployStatusLabel.unknown` | `outcome unknown` | Status label for an in-flight phase the backend expired without confirmation |
| `platformLabel.*` | `VERCEL`, `CLOUDFLARE`, `RAILWAY`, `HTTP`, `DNS`, `CRUNCHY` | Brand and check names. These are proper nouns and are not translated. |
| `platformLabelShort.*` | `CF`, `CB` | Compact brand abbreviations for dense strips |

The upper-case fallback uses `String.prototype.toUpperCase()`, which is locale-independent.

## Accessibility Options

Not applicable: the module returns strings and color tokens only, and responds to no display option such as reduce motion, increase contrast or differentiate without color.

## Feature Flags

Not applicable: the module reads no flag, and every lookup is unconditional.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only platform names and deploy status enums, and stores or transmits nothing.

## Logging

Not applicable: the module has no logging calls. Unknown inputs fall back silently to defined values, which is the documented behavior.

## Platform Notes

- **SwiftUI**: Port as a caseless `enum DeployDisplay` namespace of `static func`s, or as computed properties on a `String`-backed `Platform` enum with an `.unknown(String)` case. Use `[String: String]` dictionaries with `?? fallback`. Swift dictionaries have no prototype chain, so inherited keys (prototype-key-lookup) fall back normally. The theme tokens become `Color` assets or a theme struct. Put the U+26A0 U+FE0E glyph in a `Text` literal as `"\u{26A0}\u{FE0E}"`. `String.uppercased()` matches the fallback. Mark the namespace `Sendable` (it is, being stateless).
- **Compose**: Use a Kotlin `object DeployDisplay` with `mapOf(...)` lookups and `?:` fallbacks, and `uppercase()` (locale-invariant) for the label fallback. Colors map to `MaterialTheme`/custom theme `Color` values rather than CSS vars. Kotlin maps have no inherited keys.
- **React/Web**: This is the source, `src/lib/deploy-display.ts`. The colors are CSS `var(--color-apt-*)` strings consumed through inline `style` or `color-mix` in components. Glyphs are rendered as text, often inside `aria-hidden` spans by the callers. Lookups use plain object literals with `??`. A `Map` or `Object.hasOwn` check would make inherited keys fall back (prototype-key-lookup).
- **AppKit / UIKit**: Use the same pure Swift namespace as the SwiftUI port, returning `NSColor`/`UIColor` from a theme type. Nothing is UI-bound, so the code belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class DeployDisplay` in C#. Hold each map as a `static readonly FrozenDictionary<string, string>` (or `IReadOnlyDictionary<string, string>`) with `StringComparer.Ordinal`, and use `TryGetValue` for the fallback. This rules out the inherited-key issue. Return `ToUpperInvariant()` for unknown labels. Colors cannot be CSS vars, so return a theme resource key (for example `"AptCatOrangeBrush"`) and resolve it with `Application.Current.Resources[key]` in a `ThemeResource`-aware `IValueConverter`. That way light/dark theme switches retarget through `ThemeDictionaries`. Model `DeployStatus` as an `enum` with a `JsonStringEnumConverter` for `System.Text.Json`, and keep a `string` overload for the pass-through label and the amber fallback. Render the glitchtip glyph as `"⚠︎"` in a `TextBlock` with `FontFamily="Segoe UI Symbol"` so that Segoe UI Emoji does not take the character. The functions are synchronous: no `Task`, `ObservableCollection` or `INotifyPropertyChanged`. The view model that binds a row raises property change for its own status field.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/deploy-display.ts` |

## Design Decisions

**Decision**: One module owns the full platform taxonomy (glyph, color, label, short label).
**Rationale**: The header comment says "adding a platform is a single edit here", so every component renders platforms consistently and no component keeps its own table.
**Approved**: pending

**Decision**: Platform colors use categorical theme hues kept clear of the three environment hues.
**Rationale**: A row can show both an env badge and a platform badge. Sharing a hue would make one read as the other. The categorical palette is fully allocated, so `crunchy` reuses `http`'s teal and `glitchtip` reuses Cloudflare's orange.
**Approved**: pending

**Decision**: `glitchtip` takes orange rather than another reused hue.
**Rationale**: The source comment says orange is the hue that reads as a warning. Glitchtip rows (error incidents) and Cloudflare rows (deploys) never appear in the same list, so the glyph and label disambiguate them.
**Approved**: pending

**Decision**: The glitchtip glyph carries VARIATION SELECTOR-15.
**Rationale**: Without it, macOS and iOS render U+26A0 as a full-colour, double-width emoji beside six monochrome glyphs.
**Approved**: pending

**Decision**: `unknown` status is labelled `outcome unknown` and colored muted.
**Rationale**: It marks an in-flight phase the backend expired without confirmation, which is the absence of a verdict. Echoing the raw enum or using the amber of live progress would imply a claim the data cannot back.
**Approved**: pending

**Decision**: Unrecognised statuses fall back to the `canceled` color (amber), and unrecognised platforms fall back to the muted color, `◆` and the upper-cased name.
**Rationale**: The source chooses to render something for any input rather than throw. The status fallback reuses an existing entry instead of a separate token. As a result an unknown status reads amber, while the known `unknown` status reads muted.
**Approved**: pending

**Decision**: `failed` is the only upper-case status label.
**Rationale**: The source returns `FAILED` while every other label is lower case, which makes a failure stand out in a list.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of concerns.** The module owns only the display taxonomy. Status colors come from `colors.ts`, the status vocabulary comes from `deploy-status.ts`, and components only render the results.

**Unit test coverage.** No test file exercises any export of `deploy-display.ts`, so the mappings and fallbacks above are unverified by tests.

**Explicit error handling.** Unknown inputs take explicit, defined fallbacks and never throw. However, the plain-object lookups let inherited keys return a non-string value. That gap is carried by the prototype-key-lookup requirement.

**Graceful degradation.** A platform or status the module does not know still renders with a neutral glyph, color and label instead of failing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
