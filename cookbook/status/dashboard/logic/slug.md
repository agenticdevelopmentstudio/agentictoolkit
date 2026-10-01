---
id: cfe08d5c-029c-4e19-82ab-daf8329c5972
title: Status Slug
domain: agentictoolkit://cookbook/status/dashboard/logic/slug
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/status/dashboard/logic/peer-url
references: []
approved-by: ''
approved-date: ''
---

# Status Slug

## Overview

This logic provides one pure function that turns text into a slug. Its doc comment describes it as "Lowercase, hyphenate
runs of non-alphanumerics, trim leading/trailing hyphens" and calls it "The one
shared slug form for groups and sites."

The board uses it in two places:

- the config panel view shows the slug function's result for the draft name as the placeholder of the
  group slug field. When the typed slug is blank after trimming, it sends
  the slug function's result for the draft name as the group's `slug` on save.
- the endpoints configuration view derives a site's `slug` from the
  endpoint URL's host, via the slug function. It does this when it creates the backing
  site row, and again when it renames a site that only this endpoint owns.

The function does no I/O and does not check whether a slug is unique. The backend
(the status server) enforces uniqueness through the `uniq_site_group_slug` and
`uniq_site_group_site_slug` indexes.

## Behavioral Requirements

- **signature**: The slug function MUST take one string and return a string synchronously.
- **lowercase-first**: The function MUST lower-case the whole input using locale-independent case mapping before any other step.
- **trim**: After lower-casing, the function MUST trim leading and trailing whitespace.
- **hyphenate-runs**: The function MUST replace every maximal run of one or more characters outside ASCII `a`–`z` and `0`–`9` with a single `-`.
- **ascii-only-alphabet**: The output alphabet MUST be limited to ASCII lower-case letters, ASCII digits and `-`. Any other character, including accented and non-Latin letters, MUST be treated as a separator (`Café` becomes `caf`).
- **trim-hyphens**: The function MUST remove every leading and trailing `-` from the result.
- **no-double-hyphen**: The result MUST NOT contain two consecutive `-` characters, because each separator run collapses to one hyphen (hyphenate-runs).
- **empty-allowed**: The function MUST return `""`, without throwing, when the input contains no ASCII letter or digit (for example `""`, `"   "`, `"---"` or `"日本"`).
- **idempotent**: Applying the function to its own output MUST return the same string.
- **total**: The function MUST NOT throw for any string input.
- **no-uniqueness**: The function MUST NOT guarantee distinct outputs for distinct inputs. `"A B"`, `"a-b"` and `"a_b"` all become `"a-b"`. Uniqueness is the backend's job, through its unique slug indexes.
- **shared-form**: Group slugs defaulted by the config panel view and site slugs derived by the endpoints configuration view MUST both come from this one function, so the two follow the same rules.
- **pure**: The function MUST be free of side effects: no network, storage, logging or global state. Its result depends only on the argument.
- **concurrency**: The function MUST run synchronously to completion, so calls cannot interleave and need no ordering rule.

## Appearance

Not applicable — this is a pure string-to-slug function, not a visual component.

## States

Not applicable — this is a pure string-to-slug function, not a visual component.

## Accessibility

Not applicable — this is a pure string-to-slug function, not a visual component.

## Conformance Test Vectors

This logic has no reference test suite for these vectors (see Platform Notes). Every vector below follows from the four chained steps in the slug function.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slug-001 | lowercase-first, hyphenate-runs | the slug function called with `"Production Sites"` | `"production-sites"` |
| slug-002 | trim, trim-hyphens | the slug function called with `"  Hello World  "` | `"hello-world"` |
| slug-003 | hyphenate-runs, no-double-hyphen | the slug function called with `"a -- b__c"` | `"a-b-c"` |
| slug-004 | hyphenate-runs, shared-form | the slug function called with `"status.example.com"` | `"status-example-com"` |
| slug-005 | trim-hyphens | the slug function called with `"--Edge!!"` | `"edge"` |
| slug-006 | ascii-only-alphabet | the slug function called with `"Café Menu"` | `"caf-menu"` |
| slug-007 | empty-allowed, total | the slug function called with `""`, `"   "`, `"---"`, `"日本"` | `""` each, no exception |
| slug-008 | idempotent | the slug function called on its own result for `"My Group #1"` | `"my-group-1"`, the same as calling it once on `"My Group #1"` |
| slug-009 | no-uniqueness | the slug function called with `"A B"`, `"a-b"`, `"a_b"` | `"a-b"` each |
| slug-010 | ascii-only-alphabet | the slug function called with `"Server 42"` | `"server-42"`, digits kept |
| slug-011 | signature, pure | call the slug function with `"x"` twice | `"x"` both times, returned synchronously, nothing else observable changes |

## Edge Cases

- **Empty or whitespace-only input**: The function MUST return `""`. In the config panel view this means a group whose name and slug are both blank is sent with `slug: ""`. Whether the backend accepts that is up to the status server, not this logic.
- **Input with no ASCII alphanumerics** (`"日本"`, `"🚀"`, `"!!!"`): The function MUST return `""`. Non-Latin names produce no slug.
- **Accented Latin letters** (`"Ünïcode"`): Each accented letter MUST be treated as a separator, so `"Ünïcode"` becomes `"n-code"`. The function does no transliteration or Unicode normalization.
- **Case mappings that change length**: Lower-casing happens before filtering, so a character whose lower-case form includes ASCII letters keeps them. The Kelvin sign U+212A lower-cases to ASCII `k`, and `İ` lower-cases to `i` plus a combining dot, which then acts as a separator (`İx` becomes `i-x`). The function MUST produce whatever locale-independent lower-casing followed by the ASCII filter gives (see Platform Notes for the exact API and a platform where this differs).
- **Distinct names that collapse together**: Two group names such as `"Ops Team"` and `"ops-team"` MUST produce the same slug (no-uniqueness). The backend's unique slug index decides which write wins. The board surfaces the backend's error, and this logic adds no suffix or retry.
- **Typed group slug**: the config panel view sends a non-blank typed slug trimmed but not passed through the slug function. The shared form applies only to the default. This belongs to the caller, not to this logic.
- **Very long input**: No length cap is applied. The output is never longer than the input.
- **Concurrent access**: Not applicable. The function is synchronous and pure, so calls cannot interleave.
- **Error states and offline**: Not applicable. This logic does no I/O, so no dependency can fail and connectivity does not matter.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `s` | `string` | — (required) | The name or host text to turn into a slug. This is the function's only input. |

This logic reads no environment variables, settings or injected dependencies.

## Deep Linking

Not applicable: this logic is one pure string function and exposes no route or URL of its own.

## Localization

Not applicable: the slug function returns an identifier, not user-facing text, and contains no strings to translate.

## Accessibility Options

Not applicable: this logic has no visual output for display options to affect.

## Feature Flags

Not applicable: the slug function reads no flag and has no conditional code path.

## Analytics

Not applicable: this logic emits no events.

## Privacy

Not applicable: this logic stores and transmits nothing. It returns a derived string to its caller.

## Logging

Not applicable: the slug function never logs, and no input makes it fail.

## Platform Notes

- **SwiftUI**: Write a `nonisolated` free function. Call `lowercased()` (which is locale-independent, like `toLowerCase`), then `trimmingCharacters(in: .whitespacesAndNewlines)`, then `replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)`, then strip leading and trailing hyphens with a second regex or `trimmingCharacters(in: CharacterSet(charactersIn: "-"))`. Swift `String` works on grapheme clusters, but the regex path still matches per scalar, so non-ASCII letters become separators just as in the source.
- **Compose**: Write a Kotlin top-level function: `s.lowercase().trim().replace(Regex("[^a-z0-9]+"), "-").trim('-')`. `lowercase()` uses `Locale.ROOT`, which matches the source. Avoid `toLowerCase()` with the default locale, because it maps `I` to a dotless `ı` in Turkish locales.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/slug.ts` holds the function, exported as `slugify(s: string): string`. `components/ConfigPanel.tsx` uses it for the group slug placeholder and the blank-slug default. `components/configure/EndpointsSection.tsx` uses it for the site slug derived from the URL host. There is no unit test file. Lower-casing uses the locale-independent `String.prototype.toLowerCase`. The single-threaded JavaScript runtime is what guarantees calls cannot interleave.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `status-web/src/lib/slug.ts` and its call sites |
