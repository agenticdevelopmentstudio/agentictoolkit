---
id: 691f84ba-242a-40bc-a164-c95e535bb387
title: Deploy Display
domain: agentictoolkit://cookbook/status/dashboard/logic/deploy-display
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure lookups mapping a deploy platform or deploy status string to its
  glyph, theme color role and badge label.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/service/monitor/deploy-status
references: []
approved-by: ''
approved-date: ''
---

# Deploy Display

## Overview

This module is the status dashboard's platform taxonomy. Its header comment
states its purpose: "glyph, brand color, and badge label for each deploy
platform (plus the http/dns health checks). One module owns 'what a platform
looks like', so adding a platform is a single edit here."

It exports six pure operations:

- the platform-glyph operation returns a Unicode glyph.
- the platform-color operation returns a theme color role.
- the platform-label operation returns an upper-case badge label.
- the short-platform-label operation returns a compact label for dense
  strips.
- the deploy-status-color operation returns the theme color role for a
  deploy status dot or label.
- the deploy-status-label operation returns a short text label for a deploy
  status.

The module has no state, no I/O and no side effects. It draws its deploy
status vocabulary and its color-role map from two sibling modules. The
callers are dashboard components and views that render deploy or platform
badges; they render the returned strings and never branch on them. The
server-side status vocabulary is specified in [Monitor Deploy
Status](agentictoolkit://cookbook/status/service/monitor/deploy-status).

## Behavioral Requirements

### Platform keys

- **platform-key-vocabulary**: The module MUST recognise these platform keys, compared by exact, case-sensitive string equality: `vercel`, `cloudflare-pages`, `railway`, `http`, `dns`, `crunchy`, `glitchtip`. `http` and `dns` are health checks, not hosting platforms. `crunchy` is a database, and `glitchtip` stands for thrown errors.
- **platform-input-type**: Every platform operation MUST accept any text value and MUST NOT throw for any input.

### Platform-glyph operation

- **glyph-signature**: the platform-glyph operation MUST return a text value.
- **glyph-vercel**: it MUST return `▲` (U+25B2) for `vercel`.
- **glyph-cloudflare**: it MUST return `☁` (U+2601) for `cloudflare-pages`.
- **glyph-railway**: it MUST return `⬢` (U+2B22) for `railway`.
- **glyph-http**: it MUST return `◉` (U+25C9) for `http`.
- **glyph-dns**: it MUST return `⌖` (U+2316) for `dns`.
- **glyph-crunchy**: it MUST return `⛁` (U+26C1) for `crunchy`.
- **glyph-glitchtip-text-presentation**: it MUST return the two-code-point text U+26A0 U+FE0E for `glitchtip`. The bare warning sign can render full-colour and double-width beside six monochrome glyphs on some platforms; VARIATION SELECTOR-15 forces the text form.
- **glyph-fallback**: it MUST return `◆` (U+25C6) for every other string, including the empty string.

### Platform-color operation

- **color-signature**: the platform-color operation MUST return a theme color role.
- **color-vercel**: it MUST return the theme role `apt-text` for `vercel`. This is the brand near-white role.
- **color-cloudflare**: it MUST return the theme role `apt-cat-orange` for `cloudflare-pages`.
- **color-railway**: it MUST return the theme role `apt-cat-purple` for `railway`.
- **color-http**: it MUST return the theme role `apt-cat-teal` for `http`.
- **color-dns**: it MUST return the theme role `apt-cat-indigo` for `dns`.
- **color-crunchy-shares-http**: it MUST return the theme role `apt-cat-teal` for `crunchy`, the same role as `http`.
- **color-glitchtip-shares-cloudflare**: it MUST return the theme role `apt-cat-orange` for `glitchtip`, the same role as `cloudflare-pages`.
- **color-fallback**: it MUST return the muted theme role `apt-text-muted` for any platform with no own entry in the color map.
- **color-env-hue-exclusion**: a platform color role MUST NOT equal an environment hue role. The environment hue roles are `apt-cat-blue`, `apt-cat-violet` and `apt-cat-pink`. A row that shows both an env badge and a platform badge must read unambiguously.
- **color-theme-tokens-only**: every returned platform color MUST be a named theme role, never a hardcoded literal color value. The role's concrete rendering is owned by the shared theme package.

### Platform-label operation

- **label-signature**: the platform-label operation MUST return a text value.
- **label-table**: it MUST return `VERCEL` for `vercel`, `CLOUDFLARE` for `cloudflare-pages`, `RAILWAY` for `railway`, `HTTP` for `http`, `DNS` for `dns` and `CRUNCHY` for `crunchy`.
- **label-fallback-uppercase**: it MUST return the platform's own name, upper-cased, for any platform with no own entry in the label map. This includes `glitchtip`, which has no label entry and so yields `GLITCHTIP`.

### Short-platform-label operation

- **short-label-signature**: the short-platform-label operation MUST return a text value.
- **short-label-overrides**: it MUST return `CF` for `cloudflare-pages` and `CB` for `crunchy`.
- **short-label-fallback**: it MUST return the platform-label operation's result for every platform with no short override. For example, it returns `VERCEL` for `vercel`.

### Deploy-status-color operation

- **status-color-signature**: the deploy-status-color operation MUST return a theme color role for a deploy status, which is one of `success`, `failed`, `building`, `queued`, `canceled`, `unknown`, or any other text value.
- **status-color-lookup**: it MUST return the mapped role when the status has one: `success` → `apt-green`, `failed` → `apt-red`, `building`/`queued`/`canceled` → `apt-gold`, and `unknown` → `apt-text-muted`.
- **status-color-unknown-muted**: it MUST return the muted role for `unknown`, not the gold used for live progress. `unknown` is documented as "an ABSENCE of a verdict".
- **status-color-fallback**: it MUST return the `canceled` role (`apt-gold`) for any status string that is not one of the mapped statuses. An unrecognised status therefore renders gold, not muted.
- **status-color-token-not-hex**: it MUST return a theme-role reference, never a literal color value. Its doc comment describes a literal-color return, which is stale relative to the theme-role map it actually returns.

### Deploy-status-label operation

- **status-label-signature**: the deploy-status-label operation MUST return a text value.
- **status-label-success**: it MUST return `ready` for `success`.
- **status-label-failed-uppercase**: it MUST return `FAILED`, in upper case, for `failed`. It is the only upper-case status label.
- **status-label-in-flight**: it MUST return `building` for `building` and `queued` for `queued`.
- **status-label-canceled**: it MUST return `canceled` for `canceled`.
- **status-label-unknown**: it MUST return `outcome unknown` for `unknown`. `unknown` is an in-flight phase the backend expired without confirmation, and the label must say so rather than echo the raw status.
- **status-label-passthrough**: it MUST return the input string unchanged for any other status.

### Contract-wide

- **pure-functions**: every export MUST be a synchronous, side-effect-free function whose result depends only on its argument and the module's constant maps.
- **no-mutation**: the module MUST NOT expose its internal lookup maps (the platform color, label, and short-label maps). They are module-private, and no function mutates them.
- **concurrency**: the functions MAY be called from any context; they hold no state, so calls cannot interleave with themselves.

## Appearance

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

## States

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

## Accessibility

Not applicable — this is a pure display-taxonomy lookup module, not a visual component.

## Conformance Test Vectors

The source has no test file. The vectors below are traced to the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-display-001 | glyph-vercel | The platform-glyph operation on `vercel` | `"▲"` |
| deploy-display-002 | glyph-glitchtip-text-presentation | The platform-glyph operation on `glitchtip` | `"⚠︎"` (length 2) |
| deploy-display-003 | glyph-fallback | The platform-glyph operation on `netlify` | `"◆"` |
| deploy-display-004 | glyph-fallback | The platform-glyph operation on `""` | `"◆"` |
| deploy-display-005 | glyph-cloudflare, glyph-railway, glyph-http, glyph-dns, glyph-crunchy | The platform-glyph operation on each of `cloudflare-pages`, `railway`, `http`, `dns`, `crunchy` | `☁`, `⬢`, `◉`, `⌖`, `⛁` respectively |
| deploy-display-006 | platform-key-vocabulary, glyph-fallback | The platform-glyph operation on `Vercel` | `"◆"` (case-sensitive) |
| deploy-display-007 | color-vercel, color-cloudflare, color-railway, color-http, color-dns | The platform-color operation on each of `vercel`, `cloudflare-pages`, `railway`, `http`, `dns` | `apt-text`, `apt-cat-orange`, `apt-cat-purple`, `apt-cat-teal`, `apt-cat-indigo` |
| deploy-display-008 | color-crunchy-shares-http | The platform-color operation on `crunchy` compared with on `http` | Equal |
| deploy-display-009 | color-glitchtip-shares-cloudflare | The platform-color operation on `glitchtip` | `apt-cat-orange` |
| deploy-display-010 | color-fallback | The platform-color operation on `netlify` | `apt-text-muted` |
| deploy-display-011 | color-env-hue-exclusion, color-theme-tokens-only | The platform-color operation on every known platform key | result is a theme role and none of `apt-cat-blue`, `apt-cat-violet`, `apt-cat-pink` |
| deploy-display-012 | label-table | The platform-label operation on `cloudflare-pages` | `"CLOUDFLARE"` |
| deploy-display-013 | label-fallback-uppercase | The platform-label operation on `glitchtip` | `"GLITCHTIP"` |
| deploy-display-014 | label-fallback-uppercase | The platform-label operation on `fly-io` | `"FLY-IO"` |
| deploy-display-015 | short-label-overrides | The short-platform-label operation on `cloudflare-pages`, then on `crunchy` | `"CF"`, `"CB"` |
| deploy-display-016 | short-label-fallback | The short-platform-label operation on `railway` | `"RAILWAY"` |
| deploy-display-017 | short-label-fallback, label-fallback-uppercase | The short-platform-label operation on `netlify` | `"NETLIFY"` |
| deploy-display-018 | status-color-lookup | The deploy-status-color operation on `success`, `failed`, `building` | `apt-green`, `apt-red`, `apt-gold` |
| deploy-display-019 | status-color-unknown-muted | The deploy-status-color operation on `unknown` | `apt-text-muted` |
| deploy-display-020 | status-color-fallback | The deploy-status-color operation on `rolling-back` | `apt-gold` (equal to `canceled`) |
| deploy-display-021 | status-label-success, status-label-failed-uppercase | The deploy-status-label operation on `success`, then on `failed` | `"ready"`, `"FAILED"` |
| deploy-display-022 | status-label-in-flight, status-label-canceled | The deploy-status-label operation on `building`, `queued`, `canceled` | `"building"`, `"queued"`, `"canceled"` |
| deploy-display-023 | status-label-unknown | The deploy-status-label operation on `unknown` | `"outcome unknown"` |
| deploy-display-024 | status-label-passthrough | The deploy-status-label operation on `PROMOTED` | `"PROMOTED"` |
| deploy-display-025 | pure-functions | Call each export twice with the same argument | identical results; no global state changed |

## Edge Cases

- **Empty platform string**: the platform-glyph operation on `""` MUST return `◆`, the platform-color operation on `""` MUST return the muted role, and the platform-label and short-platform-label operations on `""` MUST return `""`. No operation validates or rejects the empty string.
- **Empty status string**: the deploy-status-color operation on `""` MUST return the gold `canceled` role, and the deploy-status-label operation on `""` MUST return `""`.
- **Case mismatch**: A key that differs only in case, such as `Vercel` or `SUCCESS`, MUST miss every map and take the fallback path. There is no normalisation.
- **Unknown platform**: A platform the module does not know MUST still render. It gets the `◆` glyph, the muted role, and its own name upper-cased as the label. The module MUST NOT throw.
- **Unknown status**: An unrecognised status MUST render gold (the `canceled` role), and its label MUST be the raw string. This differs from the known `unknown` status, which renders muted with the label `outcome unknown`.
- **glitchtip partial registration**: `glitchtip` has a glyph and a color but no label entry and no short label. Both label operations MUST yield `GLITCHTIP` through the upper-case fallback.
- **Shared hues**: `crunchy`/`http` and `glitchtip`/`cloudflare-pages` MUST return identical roles. The glyph and label disambiguate them, and glitchtip rows (error incidents) and cloudflare rows (deploys) never appear in the same list.
- **Glyph string length**: the `glitchtip` glyph MUST be two UTF-16 code units long. A port that measures or truncates glyphs by code-unit count MUST keep the variation selector.
- **Concurrent calls**: Not applicable. The functions are pure and hold no state, so calls cannot interleave.
- **Error states, offline, timeouts, cancellation**: Not applicable. The module performs no I/O, has no dependency that can fail, and cannot be cancelled or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | text value | none (required) | Platform or check key passed to the four platform operations. Unknown keys fall back as described above. |
| `status` | one of the known deploy-status values, or any other text value | none (required) | Deploy status passed to the deploy-status-color and deploy-status-label operations. |
| Deploy-status color map | text-to-theme-role map (module-internal) | built-in | Supplies the status colors. The fallback for unrecognised statuses is its `canceled` entry. |
| Theme color roles | theme tokens | owned by the shared theme package | The returned role names resolve only where the platform's theme system defines them (see Platform Notes for how each platform realizes a theme role). |

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

The upper-case fallback uses a locale-independent case conversion.

## Accessibility Options

Not applicable: the module returns strings and color-role tokens only, and responds to no display option such as reduce motion, increase contrast or differentiate without color.

## Feature Flags

Not applicable: the module reads no flag, and every lookup is unconditional.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only platform names and deploy status enums, and stores or transmits nothing.

## Logging

Not applicable: the module has no logging calls. Unknown inputs fall back silently to defined values, which is the documented behavior.

## Platform Notes

- **SwiftUI**: Port as a caseless `enum DeployDisplay` namespace of `static func`s, or as computed properties on a `String`-backed `Platform` enum with an `.unknown(String)` case. Use `[String: String]` dictionaries with `?? fallback`. Swift dictionaries have no prototype chain, so an inherited-key lookup (see the React/Web entry) cannot occur. The theme tokens become `Color` assets or a theme struct. Put the U+26A0 U+FE0E glyph in a `Text` literal as `"\u{26A0}\u{FE0E}"`. `String.uppercased()` matches the fallback. Mark the namespace `Sendable` (it is, being stateless).
- **Compose**: Use a Kotlin `object DeployDisplay` with `mapOf(...)` lookups and `?:` fallbacks, and `uppercase()` (locale-invariant) for the label fallback. Colors map to `MaterialTheme`/custom theme `Color` values rather than CSS vars. Kotlin maps have no inherited keys.
- **React/Web**: This is the source, `src/lib/deploy-display.ts`. Every theme color role returned by this module is realized as a `var(--color-<role>)` CSS custom-property expression (for example the `apt-text` role becomes `var(--color-apt-text)`), consumed through inline `style` or `color-mix` in components; `DEPLOY_COLORS` (keyed by deploy status), `PLATFORM_COLOR`, `PLATFORM_LABEL`, and `PLATFORM_LABEL_SHORT` are the module's own lookup-map names, and `ENV_COLORS` names the excluded environment-hue set. `deployStatusColor`'s doc comment describes a "CSS hex color" return, which is stale — the map holds only `var(--color-apt-*)` references. The upper-case label fallback uses `String.prototype.toUpperCase()`, which is locale-independent. Glyphs are rendered as text, often inside `aria-hidden` spans by the callers. Lookups use plain object literals with `??` for the null/undefined fallback; because a plain object's keys resolve through its prototype chain, an inherited key such as `constructor` or `toString` returns the inherited value (a function) instead of a string — nothing in the package passes such a key or tests one, but a `Map` or an `Object.hasOwn` check would make even that fall back correctly instead, which is the intended behavior. The Concurrency requirement and the Concurrent-calls edge case hold because this runs on the browser's single JavaScript thread with no shared mutable state.
- **AppKit / UIKit**: Use the same pure Swift namespace as the SwiftUI port, returning `NSColor`/`UIColor` from a theme type. Nothing is UI-bound, so the code belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class DeployDisplay` in C#. Hold each map as a `static readonly FrozenDictionary<string, string>` (or `IReadOnlyDictionary<string, string>`) with `StringComparer.Ordinal`, and use `TryGetValue` for the fallback. This rules out the inherited-key issue described in the React/Web entry. Return `ToUpperInvariant()` for unknown labels. Colors cannot be CSS vars, so return a theme resource key (for example `"AptCatOrangeBrush"`) and resolve it with `Application.Current.Resources[key]` in a `ThemeResource`-aware `IValueConverter`. That way light/dark theme switches retarget through `ThemeDictionaries`. Model the deploy-status vocabulary as an `enum` with a `JsonStringEnumConverter` for `System.Text.Json`, and keep a `string` overload for the pass-through label and the gold fallback. Render the glitchtip glyph as `"⚠︎"` in a `TextBlock` with `FontFamily="Segoe UI Symbol"` so that Segoe UI Emoji does not take the character. The functions are synchronous: no `Task`, `ObservableCollection` or `INotifyPropertyChanged`. The view model that binds a row raises property change for its own status field.

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

**Decision**: The glitchtip glyph carries VARIATION SELECTOR-15. (Apple platforms — macOS and iOS.)
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

**Explicit error handling.** Unknown inputs take explicit, defined fallbacks and never throw. However, the plain-object lookups let inherited keys return a non-string value, as described in the React/Web platform note.

**Graceful degradation.** A platform or status the module does not know still renders with a neutral glyph, color and label instead of failing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
