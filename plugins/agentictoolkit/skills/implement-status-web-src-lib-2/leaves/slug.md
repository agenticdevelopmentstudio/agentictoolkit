<!-- leaf: implement-status-web-src-lib-2/slug · source: status-web-src-lib-slug.md -->

**Rules** (cite as `implement-status-web-src-lib-2/slug#<slug>`):

- `signature` MUST
- `lowercase-first` MUST
- `trim` MUST
- `hyphenate-runs` MUST
- `ascii-only-alphabet` MUST
- `trim-hyphens` MUST
- `no-double-hyphen` MUST
- `empty-allowed` MUST
- `idempotent` MUST
- `total` MUST
- `no-uniqueness` MUST
- `shared-form` MUST
- `pure` MUST

# Status Web Slug

## Overview

`packages/web/packages/status-web/src/lib/slug.ts` exports one pure function,
`slugify(s: string): string`. Its doc comment describes it as "Lowercase, hyphenate
runs of non-alphanumerics, trim leading/trailing hyphens" and calls it "The one
shared slug form for groups and sites."

The board uses it in two places:

- `components/ConfigPanel.tsx` shows `slugify(draft.name)` as the placeholder of the
  group slug field. When the typed slug is blank after trimming, it sends
  `slugify(draft.name)` as the group's `slug` on save.
- `components/configure/EndpointsSection.tsx` derives a site's `slug` from the
  endpoint URL's host (`slugify(host)`). It does this when it creates the backing
  site row, and again when it renames a site that only this endpoint owns.

The function does no I/O and does not check whether a slug is unique. The backend
(status-server) enforces uniqueness through the `uniq_site_group_slug` and
`uniq_site_group_site_slug` indexes.

## Behavioral Requirements

- **signature**: `slugify` MUST take one string and return a string synchronously.
- **lowercase-first**: The function MUST lower-case the whole input with the locale-independent `String.prototype.toLowerCase` before any other step.
- **trim**: After lower-casing, the function MUST trim leading and trailing whitespace.
- **hyphenate-runs**: The function MUST replace every maximal run of one or more characters outside ASCII `a`–`z` and `0`–`9` with a single `-`.
- **ascii-only-alphabet**: The output alphabet MUST be limited to ASCII lower-case letters, ASCII digits and `-`. Any other character, including accented and non-Latin letters, MUST be treated as a separator (`Café` becomes `caf`).
- **trim-hyphens**: The function MUST remove every leading and trailing `-` from the result.
- **no-double-hyphen**: The result MUST NOT contain two consecutive `-` characters, because each separator run collapses to one hyphen (hyphenate-runs).
- **empty-allowed**: The function MUST return `""`, without throwing, when the input contains no ASCII letter or digit (for example `""`, `"   "`, `"---"` or `"日本"`).
- **idempotent**: Applying the function to its own output MUST return the same string.
- **total**: The function MUST NOT throw for any string input.
- **no-uniqueness**: The function MUST NOT guarantee distinct outputs for distinct inputs. `"A B"`, `"a-b"` and `"a_b"` all become `"a-b"`. Uniqueness is the backend's job, through its unique slug indexes.
- **shared-form**: Group slugs defaulted in `ConfigPanel.tsx` and site slugs derived in `EndpointsSection.tsx` MUST both come from this one function, so the two follow the same rules.
- **pure**: The function MUST be free of side effects: no network, storage, logging or global state. Its result depends only on the argument.
- **concurrency**: The function is synchronous and runs on the single JavaScript thread, so calls cannot interleave and need no ordering rule.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `s` | `string` | — (required) | The name or host text to turn into a slug. This is the function's only input. |

The module reads no environment variables, settings or injected dependencies.

## Platform Notes

- **SwiftUI**: Write a `nonisolated` free function. Call `lowercased()` (which is locale-independent, like `toLowerCase`), then `trimmingCharacters(in: .whitespacesAndNewlines)`, then `replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)`, then strip leading and trailing hyphens with a second regex or `trimmingCharacters(in: CharacterSet(charactersIn: "-"))`. Swift `String` works on grapheme clusters, but the regex path still matches per scalar, so non-ASCII letters become separators just as in the source.
- **Compose**: Write a Kotlin top-level function: `s.lowercase().trim().replace(Regex("[^a-z0-9]+"), "-").trim('-')`. `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `toLowerCase()` with the default locale, because it maps `I` to a dotless `ı` in Turkish locales.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/slug.ts` holds the function. `components/ConfigPanel.tsx` uses it for the group slug placeholder and the blank-slug default. `components/configure/EndpointsSection.tsx` uses it for the site slug derived from the URL host. There is no unit test file.
- **AppKit / UIKit**: Same Foundation `String` approach as SwiftUI, with no framework-specific differences. Call it from an `NSTextField`/`UITextField` editing-changed handler to update a placeholder live, as `ConfigPanel.tsx` does.
- **WinUI 3**: Write a static C# helper: `Regex.Replace(s.ToLowerInvariant().Trim(), "[^a-z0-9]+", "-").Trim('-')` using `System.Text.RegularExpressions`. Use `ToLowerInvariant()`, not `ToLower()`, to match the source's culture-independent lower-casing. .NET `Trim()` trims Unicode whitespace just as JavaScript `trim()` does. To reproduce the live placeholder, bind the slug `TextBox.PlaceholderText` to a computed property on an `INotifyPropertyChanged` view model that raises `PropertyChanged` for the slug whenever the name changes. .NET lower-cases one UTF-16 unit at a time, so `İ` becomes `i` with no combining dot. JavaScript adds the combining dot, which then acts as a separator. The slugs therefore differ when `İ` is followed by more letters: JavaScript turns `İx` into `i-x`, while .NET gives `ix`. A port that must match the board byte for byte has to special-case U+0130.

## Design Decisions

**Decision**: Use one shared slug function for both groups and sites.
**Rationale**: The doc comment calls it "The one shared slug form for groups and sites". Group defaults in `ConfigPanel.tsx` and host-derived site slugs in `EndpointsSection.tsx` therefore follow the same rules and cannot drift apart.
**Approved**: pending

**Decision**: Restrict the slug alphabet to ASCII `a`–`z`, `0`–`9` and `-`, with no transliteration.
**Rationale**: The replacement pattern keeps only ASCII alphanumerics, so every slug is URL- and identifier-safe without encoding. The cost is that non-Latin and accented names lose characters or become empty, which the function accepts rather than reports.
**Approved**: pending

**Decision**: Leave uniqueness to the backend.
**Rationale**: The function is pure and cannot see existing slugs. The status-server unique indexes on group and site slugs are the authority, so collisions surface as backend responses instead of being resolved on the client.
**Approved**: pending
