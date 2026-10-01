---
id: 564c6102-e100-41ad-9c92-14606a33c394
title: Display Format
domain: agentictoolkit://cookbook/status/dashboard/logic/format
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure string helpers for the status dashboard: a count with a pluralized
  noun, a 7-char short commit sha, and a capped commit subject line.'
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Display Format

## Overview

This module is the status dashboard's "single source for small string shapes that were otherwise copy-pasted across the fetchers, row builders, and config surfaces" (its header comment). It exports three pure, synchronous operations:

- the pluralization operation — "count plus a correctly-pluralized noun", so "the banner, the Auto Configure summary, and the Config badges agree on copy". Called from several banners and config surfaces across the dashboard.
- the short-sha operation — "Short commit sha (GitHub's 7-char form), or no result". Called from the overview tab, the deploy list, and the row-building logic.
- the commit-first-line operation — "First line of a commit message, capped at a maximum length, or no result", because "Commit messages are 'subject\n\nbody'; rows show only the subject". Called from the row-building logic.

The module owns no state, performs no I/O, and imports nothing. Behavior of the short-sha and commit-first-line operations is asserted by the module's own test suite; the pluralization operation has no test.

## Behavioral Requirements

### Pluralization operation

- **plural-signature**: The module MUST export the pluralization operation, accepting a count, a singular noun, and an optional explicit plural noun, and returning a text value.
- **plural-default-form**: When the plural noun is omitted, the operation MUST use the singular noun with the letter `s` appended as the plural form.
- **plural-singular-at-one**: When the count is strictly equal to `1`, the operation MUST use the singular noun.
- **plural-plural-otherwise**: When the count is any value other than `1` (including `0`, negatives, fractions and a not-a-number value), the operation MUST use the plural form as the noun.
- **plural-output-shape**: The operation MUST return the number, one space, then the noun, with no other characters.
- **plural-number-rendering**: The operation MUST render the count with the platform's default number-to-text conversion (no digit grouping, no locale decimal separator, no rounding), so `1000` renders as `1000` and `1.5` as `1.5`.
- **plural-english-rule**: The operation MUST apply only the two-form English rule (one versus other); it MUST NOT consult a locale or plural-category rules.

### Short-sha operation

- **short-sha-signature**: The module MUST export the short-sha operation, accepting a text value that may be absent, and returning a text value or no result.
- **short-sha-empty-null**: The operation MUST return no result when the input is absent or the empty string.
- **short-sha-prefix**: For a non-empty input, the operation MUST return its first 7 characters.
- **short-sha-short-input**: For a non-empty input of 7 or fewer characters, the operation MUST return it unchanged.
- **short-sha-no-validation**: The operation MUST NOT validate that the input is hexadecimal or trim whitespace; any non-empty text is truncated as-is.

### Commit-first-line operation

- **first-line-signature**: The module MUST export the commit-first-line operation, accepting a text value that may be absent and an optional maximum length, and returning a text value or no result.
- **first-line-default-max**: When the maximum length is omitted, the operation MUST use `200`.
- **first-line-empty-null**: The operation MUST return no result when the message is absent or the empty string.
- **first-line-subject**: For a non-empty message, the operation MUST return the text before the first line-feed character, or the whole message when it contains none.
- **first-line-lf-only**: The operation MUST split only on the line-feed character; a carriage return before the line feed MUST remain at the end of the returned subject.
- **first-line-empty-subject**: When the message is non-empty but begins with a line feed, the operation MUST return the empty string, not no result.
- **first-line-cap**: When the subject is longer than the maximum length, the operation MUST return exactly its first `max` characters.
- **first-line-no-ellipsis**: A capped subject MUST NOT carry an ellipsis or any other truncation indicator.
- **first-line-under-cap**: When the subject is at the maximum length or shorter, the operation MUST return it unchanged.

### Module-wide

- **utf16-length**: Character counts in the short-sha and commit-first-line operations MUST be UTF-16 code units, not grapheme clusters or code points.
- **pure-functions**: Every export MUST be a pure function: it MUST NOT read or write shared state, perform I/O, or throw for any input matching its declared shape.
- **synchronous**: Every export MUST return synchronously; there is no async work, caching or cancellation to order.

## Appearance

Not applicable — this is a pure string-formatting module, not a visual component.

## States

Not applicable — this is a pure string-formatting module, not a visual component.

## Accessibility

Not applicable — this is a pure string-formatting module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| format-001 | short-sha-prefix | The short-sha operation on `"abcdef1234567"` | `"abcdef1"` |
| format-002 | short-sha-short-input | The short-sha operation on `"abc"` | `"abc"` |
| format-003 | short-sha-empty-null | The short-sha operation on each of: absent input, and `""` | No result, for each |
| format-004 | short-sha-no-validation | The short-sha operation on `"  zz-not-hex"` | `"  zz-no"` |
| format-005 | first-line-subject | The commit-first-line operation on `"subject\n\nbody text"` | `"subject"` |
| format-006 | first-line-subject, first-line-under-cap | The commit-first-line operation on `"just one line"` | `"just one line"` |
| format-007 | first-line-empty-null | The commit-first-line operation on each of: absent input, and `""` | No result, for each |
| format-008 | first-line-default-max, first-line-cap | The commit-first-line operation on `"x"` repeated 250 times, default max | a string of length 200 |
| format-009 | first-line-cap, first-line-no-ellipsis | The commit-first-line operation on `"x"` repeated 250 times, max 10 | `"xxxxxxxxxx"` — length 10, no ellipsis |
| format-010 | first-line-under-cap | The commit-first-line operation on `"short"`, max 200 | `"short"` |
| format-011 | first-line-lf-only | The commit-first-line operation on `"subject\r\nbody"` | `"subject\r"` |
| format-012 | first-line-empty-subject | The commit-first-line operation on `"\nbody"` | `""` |
| format-013 | plural-singular-at-one, plural-output-shape | The pluralization operation on count 1, noun `"site"` | `"1 site"` |
| format-014 | plural-default-form, plural-plural-otherwise | The pluralization operation on count 3, noun `"site"` | `"3 sites"` |
| format-015 | plural-plural-otherwise | The pluralization operation on count 0, noun `"project"` | `"0 projects"` |
| format-016 | plural-plural-otherwise | The pluralization operation on count -1, noun `"site"` | `"-1 sites"` |
| format-017 | plural-default-form | The pluralization operation on count 2, noun `"person"`, explicit plural `"people"` | `"2 people"` |
| format-018 | plural-number-rendering | The pluralization operation on count 1000, noun `"site"`; and on count 1.5, noun `"site"` | `"1000 sites"`, `"1.5 sites"` |
| format-019 | plural-english-rule | The pluralization operation on count 21, noun `"site"` | `"21 sites"` regardless of runtime locale |
| format-020 | utf16-length | The commit-first-line operation on `"ab😀cd"`, max 3 | a 3-code-unit string: `"ab"` followed by the lone high surrogate of the emoji |
| format-021 | pure-functions, synchronous | Each export, called twice with the same arguments | identical return values; no observable side effect; the result is not a deferred value |

## Edge Cases

- **Absent and empty input**: The short-sha and commit-first-line operations MUST return no result for an absent value and for `""` (format-003, format-007). The pluralization operation with an empty singular noun MUST return the number, a space, and `"s"` for a count other than 1 (an empty noun of `"0"` yields `"0 s"`) or the number and a trailing space for a count of exactly 1.
- **Whitespace-only input**: A hash or message consisting only of spaces is non-empty and MUST be processed, not treated as missing: the short-sha operation on `"   "` returns `"   "`.
- **Boundary at exactly 7 and exactly the maximum length**: A 7-character hash MUST be returned unchanged; a subject whose length equals the maximum MUST be returned unchanged, because the cap applies only when the length is strictly greater than the maximum.
- **Maximum length of zero**: The commit-first-line operation on `"abc"` with max 0 MUST return `""`.
- **Negative maximum length**: The operation does not validate the maximum. With a negative maximum the length test is always true and the slice counts from the end, so the commit-first-line operation on `"abcdef"` with max -2 MUST return `"abcd"` (the last two characters dropped). No caller in the package passes a maximum; the default 200 is the only value used.
- **Not-a-number maximum length**: A length compared with a not-a-number value is never greater, so the commit-first-line operation with such a maximum MUST return the whole first line uncapped.
- **Non-integer count in pluralization**: The pluralization operation on `1.0` MUST return `"1 site"` (1.0 equals 1); on a not-a-number count it MUST return `"NaN sites"`.
- **Surrogate pairs**: Truncation counts UTF-16 code units and MAY split a surrogate pair at the cap (format-020); commit hashes are ASCII, so the short-sha operation is unaffected in practice.
- **Windows line endings**: A CRLF message MUST keep the trailing carriage return on the subject (format-011).
- **Concurrent access**: Not applicable — the operations are pure, synchronous and stateless, so concurrent callers cannot observe each other.
- **Error states**: Not applicable — the operations touch no file, network or other dependency and cannot fail for inputs of their declared shapes.
- **Offline or disconnected state**: Not applicable — no network is involved.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| pluralization operation's explicit plural noun | a text value | the singular noun with `s` appended | Plural noun used when the count is not 1; pass it for irregular plurals. |
| commit-first-line operation's maximum length | a number | `200` | Maximum length, in UTF-16 code units, of the returned subject. |

There are no environment variables, settings keys or injected dependencies.

## Deep Linking

Not applicable: the module exports string helpers only and handles no URLs or routes.

## Localization

The module holds no user-facing strings of its own; callers pass hardcoded English nouns (for example `"site"`, `"stale monitor"`, `"Vercel project"`). The module embeds one English-only rule:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — pluralization operation's default suffix) | `s` | Appended to the singular noun when no explicit plural is given and the count is not 1; English pluralization, not locale-aware. |

The count in the pluralization operation is rendered with default number-to-text conversion, not a locale-aware number formatter (plural-number-rendering).

## Accessibility Options

Not applicable: the module produces plain strings and has no rendering, motion or color of its own.

## Feature Flags

Not applicable: the module reads no flags; every export is always available.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module collects, stores and transmits nothing; commit hashes and messages pass through in memory only.

## Logging

Not applicable: the module contains no logging calls.

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum` of `static` functions in a shared Swift module; they are trivially `Sendable`-safe. Swift `String.count` and `prefix(_:)` count grapheme clusters, not UTF-16 units, so use `utf16` views (or accept the difference and document it) to match utf16-length. Use `split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first` to keep first-line-empty-subject; note Swift treats `"\r\n"` as one `Character`, so splitting on `"\n"` does not match the CRLF grapheme — split on `unicodeScalars` to keep first-line-lf-only. For the pluralization operation, the port matches the source; a localized port would use a String Catalog with plural variations instead.
- **Compose**: Kotlin top-level functions: `hash?.takeIf { it.isNotEmpty() }?.take(7)`, `message.substringBefore('\n')` then `take(max)`. Kotlin `String.length` and `take` count UTF-16 units like the source. Do not use `lines()`/`lineSequence()`, which also split on `\r\n` and `\r` and would break first-line-lf-only. `take` throws `IllegalArgumentException` for a negative count, unlike the source's end-relative slice. A localized port would use `pluralStringResource`.
- **React/Web**: This is the source: `packages/web/packages/status-web/src/lib/format.ts` (TypeScript, no imports), exporting `plural(n, singular, pluralForm?)`, `shortSha(hash)` and `commitFirstLine(message, max?)`, with tests in `format.test.ts` (Vitest). Results feed JSX text and `title`/`aria-label` attributes in components (`StaleMonitorsBanner.tsx`, `AutoConfigureProvider.tsx`, `UnconfiguredProjectsBanner.tsx`, `BoardShell.tsx`, `ConfigPanel.tsx`, `OverviewTab.tsx`, `DeployList.tsx`) and the row objects built by `row-model.ts`. UTF-16 code units is simply the JavaScript string length. The module holds no state and runs on the single JavaScript thread, so concurrent calls cannot interleave. A localized version would use `Intl.PluralRules` and `Intl.NumberFormat`.
- **AppKit / UIKit**: Same Swift port as SwiftUI; `NSString.length` and `substring(to:)` count UTF-16 units and match the source exactly, so a Foundation-based port can use `(hash as NSString).substring(to: min(7, length))`. A localized version would use `.stringsdict` plural rules.
- **WinUI 3**: Port as a `public static class DisplayFormat` in a shared .NET class library with no UI dependency. `ShortSha`: `string.IsNullOrEmpty(hash) ? null : hash[..Math.Min(7, hash.Length)]`. `CommitFirstLine`: `string.IsNullOrEmpty(message)` returns `null`; `message.Split('\n', 2)[0]` keeps the carriage return like the source; cap with `first[..Math.Min(max, first.Length)]`. C# `string.Length` and range slicing count UTF-16 units, matching the source, but a negative `max` throws `ArgumentOutOfRangeException` instead of dropping characters from the end — guard it or document the difference. `Plural`: `$"{n.ToString(CultureInfo.InvariantCulture)} {(n == 1 ? singular : pluralForm ?? singular + "s")}"`; without `InvariantCulture` the interpolated number uses the current culture (for example `1,5` in de-DE) and diverges from plural-number-rendering. Bind results to `TextBlock.Text` or `ToolTipService.ToolTip`; a localized version would use `.resw` resources with a plural-aware formatter.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/format.ts` |

## Design Decisions

**Decision**: One module owns the pluralization, short-sha and commit-subject shapes.
**Rationale**: The header comment says these shapes "were otherwise copy-pasted across the fetchers, row builders, and config surfaces"; one definition keeps the banner, Auto Configure summary and Config badges in agreement on copy.
**Approved**: pending

**Decision**: `shortSha` uses a fixed 7-character prefix.
**Rationale**: The doc comment names "GitHub's 7-char form", matching the abbreviation users see on GitHub.
**Approved**: pending

**Decision**: Empty and missing inputs map to `null` rather than `""` in `shortSha` and `commitFirstLine`.
**Rationale**: The test comment reads "empty → no commit"; `null` lets callers such as `DeployList.tsx` (`shortSha(d.commitHash) ?? ""`) and `row-model.ts` distinguish "no commit" from a value.
**Approved**: pending

**Decision**: `commitFirstLine` truncates hard at 200 characters with no ellipsis.
**Rationale**: The doc comment specifies only a cap at `max`; rows show the subject, and the cap bounds pathological single-line messages. Truncation is silent by design.
**Approved**: pending

**Decision**: `plural` uses the English one/other rule with an optional explicit plural form.
**Rationale**: The dashboard's copy is English-only; the `pluralForm` parameter covers irregular nouns without a locale system.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [plural-forms](agenticdevelopercookbook://compliance/internationalization#plural-forms) | failed | internationalization |
| [locale-aware-formatting](agenticdevelopercookbook://compliance/internationalization#locale-aware-formatting) | failed | internationalization |

The module is pure, import-free and separate from the components that display its output, so separation-of-concerns passes. Unit-test-coverage is partial: the test suite covers the short-sha and commit-first-line operations (null, empty, short, subject and cap cases) but has no test for the pluralization operation. Explicit-error-handling passes because nothing is caught or swallowed; every input of the declared shapes produces a defined string or no result. Plural-forms fails because the pluralization operation applies the English singular/plural rule rather than locale plural categories, and locale-aware-formatting fails because the count is rendered with default number conversion rather than a locale-aware number formatter; both follow from the dashboard being English-only.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `packages/web/packages/status-web/src/lib/format.ts` |
