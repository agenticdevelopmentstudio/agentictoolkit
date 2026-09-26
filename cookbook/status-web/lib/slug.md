---
id: cfe08d5c-029c-4e19-82ab-daf8329c5972
title: Status Web Slug
domain: agentictoolkit://cookbook/status-web/lib/slug
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The status board''s single slug form for groups and sites: lower-case, hyphenate
  runs of non-alphanumerics, trim edge hyphens.'
platforms:
- typescript
- web
tags:
- slug
- validation
depends-on: []
related:
- agentictoolkit://cookbook/status-web/lib/peer-url
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a pure string-to-slug function, not a visual component.

## States

Not applicable — this is a pure string-to-slug function, not a visual component.

## Accessibility

Not applicable — this is a pure string-to-slug function, not a visual component.

## Conformance Test Vectors

The source has no `slug.test.ts`. Every vector below follows from the four chained steps in `slugify`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slug-001 | lowercase-first, hyphenate-runs | `slugify("Production Sites")` | `"production-sites"` |
| slug-002 | trim, trim-hyphens | `slugify("  Hello World  ")` | `"hello-world"` |
| slug-003 | hyphenate-runs, no-double-hyphen | `slugify("a -- b__c")` | `"a-b-c"` |
| slug-004 | hyphenate-runs, shared-form | `slugify("status.example.com")` | `"status-example-com"` |
| slug-005 | trim-hyphens | `slugify("--Edge!!")` | `"edge"` |
| slug-006 | ascii-only-alphabet | `slugify("Café Menu")` | `"caf-menu"` |
| slug-007 | empty-allowed, total | `slugify("")`, `slugify("   ")`, `slugify("---")`, `slugify("日本")` | `""` each, no exception |
| slug-008 | idempotent | `slugify(slugify("My Group #1"))` | `"my-group-1"`, the same as `slugify("My Group #1")` |
| slug-009 | no-uniqueness | `slugify("A B")`, `slugify("a-b")`, `slugify("a_b")` | `"a-b"` each |
| slug-010 | ascii-only-alphabet | `slugify("Server 42")` | `"server-42"`, digits kept |
| slug-011 | signature, pure | Call `slugify("x")` twice | `"x"` both times, returned synchronously, nothing else observable changes |

## Edge Cases

- **Empty or whitespace-only input**: The function MUST return `""`. In `ConfigPanel.tsx` this means a group whose name and slug are both blank is sent with `slug: ""`. Whether the backend accepts that is up to status-server, not this module.
- **Input with no ASCII alphanumerics** (`"日本"`, `"🚀"`, `"!!!"`): The function MUST return `""`. Non-Latin names produce no slug.
- **Accented Latin letters** (`"Ünïcode"`): Each accented letter MUST be treated as a separator, so `"Ünïcode"` becomes `"n-code"`. The function does no transliteration or Unicode normalization.
- **Case mappings that change length**: Lower-casing happens before filtering, so a character whose lower-case form includes ASCII letters keeps them. The Kelvin sign U+212A lower-cases to ASCII `k`, and `İ` lower-cases to `i` plus a combining dot, which then acts as a separator (`İx` becomes `i-x`). The function MUST produce whatever the locale-independent `toLowerCase` followed by the ASCII filter gives.
- **Distinct names that collapse together**: Two group names such as `"Ops Team"` and `"ops-team"` MUST produce the same slug (no-uniqueness). The backend's unique slug index decides which write wins. The board surfaces the backend's error, and this module adds no suffix or retry.
- **Typed group slug**: `ConfigPanel.tsx` sends a non-blank typed slug trimmed but not passed through `slugify`. The shared form applies only to the default. This belongs to the caller, not to this module.
- **Very long input**: No length cap is applied. The output is never longer than the input.
- **Concurrent access**: Not applicable. The function is synchronous and pure on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module does no I/O, so no dependency can fail and connectivity does not matter.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `s` | `string` | — (required) | The name or host text to turn into a slug. This is the function's only input. |

The module reads no environment variables, settings or injected dependencies.

## Deep Linking

Not applicable: the module is one pure string function and exposes no route or URL of its own.

## Localization

Not applicable: `slugify` returns an identifier, not user-facing text, and contains no strings to translate.

## Accessibility Options

Not applicable: the module has no visual output for display options to affect.

## Feature Flags

Not applicable: `slugify` reads no flag and has no conditional code path.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module stores and transmits nothing. It returns a derived string to its caller.

## Logging

Not applicable: `slugify` never logs, and no input makes it fail.

## Platform Notes

- **SwiftUI**: Write a `nonisolated` free function. Call `lowercased()` (which is locale-independent, like `toLowerCase`), then `trimmingCharacters(in: .whitespacesAndNewlines)`, then `replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)`, then strip leading and trailing hyphens with a second regex or `trimmingCharacters(in: CharacterSet(charactersIn: "-"))`. Swift `String` works on grapheme clusters, but the regex path still matches per scalar, so non-ASCII letters become separators just as in the source.
- **Compose**: Write a Kotlin top-level function: `s.lowercase().trim().replace(Regex("[^a-z0-9]+"), "-").trim('-')`. `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `toLowerCase()` with the default locale, because it maps `I` to a dotless `ı` in Turkish locales.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/slug.ts` holds the function. `components/ConfigPanel.tsx` uses it for the group slug placeholder and the blank-slug default. `components/configure/EndpointsSection.tsx` uses it for the site slug derived from the URL host. There is no unit test file.
- **AppKit / UIKit**: Same Foundation `String` approach as SwiftUI, with no framework-specific differences. Call it from an `NSTextField`/`UITextField` editing-changed handler to update a placeholder live, as `ConfigPanel.tsx` does.
- **WinUI 3**: Write a static C# helper: `Regex.Replace(s.ToLowerInvariant().Trim(), "[^a-z0-9]+", "-").Trim('-')` using `System.Text.RegularExpressions`. Use `ToLowerInvariant()`, not `ToLower()`, to match the source's culture-independent lower-casing. .NET `Trim()` trims Unicode whitespace just as JavaScript `trim()` does. To reproduce the live placeholder, bind the slug `TextBox.PlaceholderText` to a computed property on an `INotifyPropertyChanged` view model that raises `PropertyChanged` for the slug whenever the name changes. .NET lower-cases one UTF-16 unit at a time, so `İ` becomes `i` with no combining dot. JavaScript adds the combining dot, which then acts as a separator. The slugs therefore differ when `İ` is followed by more letters: JavaScript turns `İx` into `i-x`, while .NET gives `ix`. A port that must match the board byte for byte has to special-case U+0130.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/slug.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | partial | Internationalization |

The function is a pure utility kept apart from the two editor components that call
it, so separation of concerns passes. Unit-test coverage fails because no `slug.test.ts`
sits beside `slug.ts`, while most sibling `lib` modules have one. Unicode support is
partial. The function takes any Unicode string without throwing and lower-cases it
with full Unicode rules. But it keeps only ASCII letters and digits, so accented,
non-Latin and emoji characters are dropped, and a wholly non-Latin name produces an
empty slug.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `status-web/src/lib/slug.ts` and its call sites |
