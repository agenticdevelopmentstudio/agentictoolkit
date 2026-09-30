<!-- leaf: implement-status-web-src-lib-1/format · source: status-web-src-lib-format.md -->

**Rules** (cite as `implement-status-web-src-lib-1/format#<slug>`):

- `plural-signature` MUST
- `plural-default-form` MUST
- `plural-singular-at-one` MUST
- `plural-plural-otherwise` MUST
- `plural-output-shape` MUST
- `plural-number-rendering` MUST
- `plural-english-rule` MUST
- `short-sha-signature` MUST
- `short-sha-empty-null` MUST
- `short-sha-prefix` MUST
- `short-sha-short-input` MUST
- `short-sha-no-validation` MUST
- `first-line-signature` MUST
- `first-line-default-max` MUST
- `first-line-empty-null` MUST
- `first-line-subject` MUST
- `first-line-lf-only` MUST
- `first-line-empty-subject` MUST
- `first-line-cap` MUST
- `first-line-no-ellipsis` MUST
- `first-line-under-cap` MUST
- `utf16-length` MUST
- `pure-functions` MUST
- `synchronous` MUST

# Display Format Helpers

## Overview

`packages/web/packages/status-web/src/lib/format.ts` is the status-web package's "single source for small string shapes that were otherwise copy-pasted across the fetchers, row builders, and config surfaces" (its header comment). It exports three pure, synchronous functions:

- `plural(n, singular, pluralForm?)` — "count plus a correctly-pluralized noun", so "the banner, the Auto Configure summary, and the Config badges agree on copy". Callers include `StaleMonitorsBanner.tsx`, `AutoConfigureProvider.tsx`, `UnconfiguredProjectsBanner.tsx`, `BoardShell.tsx` and `ConfigPanel.tsx`.
- `shortSha(hash)` — "Short commit sha (GitHub's 7-char form), or null". Used by `OverviewTab.tsx`, `DeployList.tsx` and `row-model.ts`.
- `commitFirstLine(message, max?)` — "First line of a commit message, capped at `max` chars, or null", because "Commit messages are 'subject\n\nbody'; rows show only the subject". Used by `row-model.ts`.

The module owns no state, performs no I/O, and imports nothing. Behavior of `shortSha` and `commitFirstLine` is asserted by `format.test.ts`; `plural` has no test.

## Behavioral Requirements

### plural

- **plural-signature**: The module MUST export `plural(n: number, singular: string, pluralForm?: string): string`.
- **plural-default-form**: When `pluralForm` is omitted, `plural` MUST use `singular` with the letter `s` appended as the plural form.
- **plural-singular-at-one**: When `n` is strictly equal to `1`, `plural` MUST use `singular` as the noun.
- **plural-plural-otherwise**: When `n` is any value other than `1` (including `0`, negatives, fractions and `NaN`), `plural` MUST use the plural form as the noun.
- **plural-output-shape**: `plural` MUST return the number, one space, then the noun, with no other characters.
- **plural-number-rendering**: `plural` MUST render `n` with the language's default number-to-string conversion (no digit grouping, no locale decimal separator, no rounding), so `1000` renders as `1000` and `1.5` as `1.5`.
- **plural-english-rule**: `plural` MUST apply only the two-form English rule (one versus other); it MUST NOT consult a locale or plural-category rules.

### shortSha

- **short-sha-signature**: The module MUST export `shortSha(hash: string | null | undefined): string | null`.
- **short-sha-empty-null**: `shortSha` MUST return `null` when `hash` is `null`, `undefined` or the empty string.
- **short-sha-prefix**: For a non-empty `hash`, `shortSha` MUST return its first 7 characters.
- **short-sha-short-input**: For a non-empty `hash` of 7 or fewer characters, `shortSha` MUST return `hash` unchanged.
- **short-sha-no-validation**: `shortSha` MUST NOT validate that `hash` is hexadecimal or trim whitespace; any non-empty string is truncated as-is.

### commitFirstLine

- **first-line-signature**: The module MUST export `commitFirstLine(message: string | null | undefined, max?: number): string | null`.
- **first-line-default-max**: When `max` is omitted, `commitFirstLine` MUST use `200`.
- **first-line-empty-null**: `commitFirstLine` MUST return `null` when `message` is `null`, `undefined` or the empty string.
- **first-line-subject**: For a non-empty `message`, `commitFirstLine` MUST return the text before the first line-feed character (`\n`), or the whole message when it contains none.
- **first-line-lf-only**: `commitFirstLine` MUST split only on `\n`; a carriage return before the line feed MUST remain at the end of the returned subject.
- **first-line-empty-subject**: When `message` is non-empty but begins with `\n`, `commitFirstLine` MUST return the empty string, not `null`.
- **first-line-cap**: When the subject is longer than `max` characters, `commitFirstLine` MUST return exactly its first `max` characters.
- **first-line-no-ellipsis**: A capped subject MUST NOT carry an ellipsis or any other truncation indicator.
- **first-line-under-cap**: When the subject is `max` characters or shorter, `commitFirstLine` MUST return it unchanged.

### Module-wide

- **utf16-length**: Character counts in `shortSha` and `commitFirstLine` MUST be UTF-16 code units (the JavaScript string length), not grapheme clusters or code points.
- **pure-functions**: Every export MUST be a pure function: it MUST NOT read or write shared state, perform I/O, or throw for any input matching its declared parameter types.
- **synchronous**: Every export MUST return synchronously; there is no async work, caching or cancellation to order, and single-threaded JavaScript runs each call to completion.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `plural` `pluralForm` | `string` | `` `${singular}s` `` | Plural noun used when `n !== 1`; pass it for irregular plurals. |
| `commitFirstLine` `max` | `number` | `200` | Maximum length, in UTF-16 code units, of the returned subject. |

There are no environment variables, settings keys or injected dependencies.

## Localization

`format.ts` holds no user-facing strings of its own; callers pass hardcoded English nouns (for example `"site"`, `"stale monitor"`, `"Vercel project"`). The module embeds one English-only rule:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — `plural` default suffix) | `s` | Appended to `singular` when `pluralForm` is omitted and `n !== 1`; English pluralization, not locale-aware. |

The number in `plural` is rendered with default number-to-string conversion, not a locale-aware number formatter (plural-number-rendering).

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum` of `static` functions in a shared Swift module; they are trivially `Sendable`-safe. Swift `String.count` and `prefix(_:)` count grapheme clusters, not UTF-16 units, so use `utf16` views (or accept the difference and document it) to match utf16-length. Use `split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first` to keep first-line-empty-subject; note Swift treats `"\r\n"` as one `Character`, so splitting on `"\n"` does not match the CRLF grapheme — split on `unicodeScalars` to keep first-line-lf-only. For plural, `plural` matches the source; a localized port would use a String Catalog with plural variations instead.
- **Compose**: Kotlin top-level functions: `hash?.takeIf { it.isNotEmpty() }?.take(7)`, `message.substringBefore('\n')` then `take(max)`. Kotlin `String.length` and `take` count UTF-16 units like JavaScript. Do not use `lines()`/`lineSequence()`, which also split on `\r\n` and `\r` and would break first-line-lf-only. `take` throws `IllegalArgumentException` for a negative count, unlike the source's end-relative slice. A localized port would use `pluralStringResource`.
- **React/Web**: The source is `packages/web/packages/status-web/src/lib/format.ts` (TypeScript, no imports) with tests in `format.test.ts` (Vitest). Results feed JSX text and `title`/`aria-label` attributes in components and the row objects built by `row-model.ts`. A localized version would use `Intl.PluralRules` and `Intl.NumberFormat`.
- **AppKit / UIKit**: Same Swift port as SwiftUI; `NSString.length` and `substring(to:)` count UTF-16 units and match the source exactly, so a Foundation-based port can use `(hash as NSString).substring(to: min(7, length))`. A localized version would use `.stringsdict` plural rules.
- **WinUI 3**: Port as a `public static class DisplayFormat` in a shared .NET class library with no UI dependency. `ShortSha`: `string.IsNullOrEmpty(hash) ? null : hash[..Math.Min(7, hash.Length)]`. `CommitFirstLine`: `string.IsNullOrEmpty(message)` returns `null`; `message.Split('\n', 2)[0]` keeps the carriage return like the source; cap with `first[..Math.Min(max, first.Length)]`. C# `string.Length` and range slicing count UTF-16 units, matching the source, but a negative `max` throws `ArgumentOutOfRangeException` instead of dropping characters from the end — guard it or document the difference. `Plural`: `$"{n.ToString(CultureInfo.InvariantCulture)} {(n == 1 ? singular : pluralForm ?? singular + "s")}"`; without `InvariantCulture` the interpolated number uses the current culture (for example `1,5` in de-DE) and diverges from plural-number-rendering. Bind results to `TextBlock.Text` or `ToolTipService.ToolTip`; a localized version would use `.resw` resources with a plural-aware formatter.

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
