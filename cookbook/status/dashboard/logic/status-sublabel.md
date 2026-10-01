---
id: d79f556c-163b-48aa-82f0-baff52fa9dab
title: Status Sublabel
domain: agentictoolkit://cookbook/status/dashboard/logic/status-sublabel
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure function that builds the status sublabel: an all-clear endpoint line
  or a grouped problem breakdown whose parts sum to the problem count'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/logic/row-model
- agentictoolkit://cookbook/status/dashboard/logic/overview
related: []
references: []
approved-by: ''
approved-date: ''
---

# Status Sublabel

## Overview

This logic provides one pure, synchronous function, the sublabel-building function, that returns the one-line caption shown under the status headline. When the board is clear it reads like "12/12 endpoints healthy · no failed builds". Otherwise it is a grouped breakdown of the problem rows, such as "2 down · 1 failed build", and the doc comment requires it to account "for EVERY problem so the parts sum to the indicator count".

The doc comment says the function is "Shared by the mobile hero and the desktop top-bar pill". In the current tree its only caller is the overview tab view, which passes the result to the big indicator view as its sublabel. The inputs are typed by the indicator state (specified in [Overview Projections](agentictoolkit://cookbook/status/dashboard/logic/overview)) and a row (specified in [Row Model](agentictoolkit://cookbook/status/dashboard/logic/row-model)). The function reads only a row's `statusWord`.

This logic also holds a private table, the sublabel-phrase table, which maps a problem row's status word to a function that formats a count into a phrase.

## Behavioral Requirements

### Signature and purity

- **sublabel-signature**: The sublabel-building function MUST take a state (one of the indicator states), `healthyCount` (number), `servicesLength` (number) and `problems` (a list of rows), and MUST return a string.
- **sublabel-pure**: The sublabel-building function MUST have no side effects. It MUST NOT mutate `problems` or any row, and MUST NOT perform I/O, log, or read global state.
- **sublabel-synchronous**: The sublabel-building function MUST return its result synchronously, so calls cannot interleave.
- **sublabel-no-throw**: For inputs that match the declared types, the sublabel-building function MUST NOT throw. No path in the function raises an error.

### Clear board (state is `"ok"`)

- **ok-ignores-problems**: When `state` is `"ok"`, the result MUST NOT depend on `problems`, even if the list is non-empty.
- **ok-all-healthy**: When `state` is `"ok"` and `healthyCount` exactly equals `servicesLength`, the function MUST return `<healthyCount>/<servicesLength> endpoints healthy · no failed builds`, with the actual numbers substituted for `<healthyCount>` and `<servicesLength>`.
- **ok-not-all-healthy**: When `state` is `"ok"` and `healthyCount` does not exactly equal `servicesLength`, the function MUST return `<servicesLength> endpoints monitored · no failed builds` and MUST NOT print a fraction. The source comment explains why: while the board is operational, a non-healthy endpoint is a transient blip or an unprobed endpoint, and "4/5 healthy" would contradict "ALL SYSTEMS OPERATIONAL".
- **ok-strict-equality**: The all-healthy test MUST be exact numeric equality. Any other relationship, including `healthyCount` greater than `servicesLength`, MUST take the "monitored" branch.

### Problem breakdown (state is `"warn"` or `"down"`)

- **breakdown-group-by-status-word**: For any `state` other than `"ok"`, the function MUST count `problems` grouped by exact `statusWord`. Matching is case-sensitive and whitespace-sensitive.
- **breakdown-ignores-counts-args**: For any `state` other than `"ok"`, the result MUST NOT depend on `healthyCount` or `servicesLength`.
- **breakdown-phrase-down**: A group of `n` rows with status word `"down"` MUST render as `<n> down`. This phrase has no plural form.
- **breakdown-phrase-degraded**: A group of `n` rows with status word `"degraded"` MUST render as `<n> degraded`. This phrase has no plural form.
- **breakdown-phrase-build-failed**: A group with status word `"build failed"` MUST render as `"1 failed build"` when the count is 1, and as `<n> failed builds` for every other count.
- **breakdown-phrase-deploy-failed**: A group with status word `"deploy failed"` MUST render as `"1 failed deploy"` when the count is 1, and as `<n> failed deploys` otherwise.
- **breakdown-phrase-deployment-failed**: A group with status word `"deployment failed"` MUST render as `"1 stale deploy"` when the count is 1, and as `<n> stale deploys` otherwise. The status word is relabelled as "stale", not "failed".
- **breakdown-phrase-building**: A group with status word `"building"` MUST render as `"1 stuck build"` when the count is 1, and as `<n> stuck builds` otherwise. The source comment gives the reason: "a building row only reaches Problems when stuck".
- **breakdown-phrase-platform-unreachable**: A group with status word `"platform unreachable"` MUST render as `"1 platform unreachable"` when the count is 1, and as `<n> platforms unreachable` otherwise.
- **breakdown-mapped-order**: Mapped phrases MUST appear in the fixed table order `down`, `degraded`, `build failed`, `deploy failed`, `deployment failed`, `building`, `platform unreachable`, whatever order the rows arrive in.
- **breakdown-unmapped-verbatim**: A status word with no entry in the sublabel-phrase table MUST render as `<n> <statusWord>`, using the word verbatim with no pluralization.
- **breakdown-unmapped-after-mapped**: Unmapped groups MUST appear after all mapped phrases, in the order each word first occurs in `problems`.
- **breakdown-no-zero-groups**: Only status words that occur at least once in `problems` MUST produce a phrase. The function MUST NOT emit a zero-count phrase.
- **breakdown-separator**: Phrases MUST be joined with `" · "` (space, U+00B7 MIDDLE DOT, space), with no leading or trailing separator.
- **breakdown-sums-to-problem-count**: The counts in the phrases MUST add up to the length of `problems`, so every problem row is counted exactly once.
- **breakdown-empty-problems**: For any `state` other than `"ok"` with an empty `problems`, the function MUST return the empty string `""`.

### Caller preconditions

- **caller-pairs-state-and-problems**: The function MUST trust the caller's pairing of `state` with `problems` and MUST NOT re-derive the state. The "sum to the indicator count" guarantee in the doc comment holds only when the caller passes the same problem set the indicator counted. The overview tab view pairs the indicator's state with its `problems` rows.
- **caller-counts-services**: `healthyCount` and `servicesLength` are caller-computed. The overview tab view passes the number of env-filtered services with a status of `"healthy"` and the length of that filtered list. The function does not validate them.

## Appearance

Not applicable — this is a pure string-formatting function, not a visual component.

## States

Not applicable — this is a pure string-formatting function, not a visual component.

## Accessibility

Not applicable — this is a pure string-formatting function, not a visual component.

## Conformance Test Vectors

This logic has no reference test suite for these vectors (see Platform Notes). These vectors are derived from the sublabel-building function and the sublabel-phrase table. `row(w)` stands for a row whose `statusWord` is `w`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sublabel-001 | ok-all-healthy | the sublabel-building function called with state `"ok"`, `healthyCount` 12, `servicesLength` 12, no problems | `"12/12 endpoints healthy · no failed builds"` |
| sublabel-002 | ok-not-all-healthy | the sublabel-building function called with state `"ok"`, `healthyCount` 4, `servicesLength` 5, no problems | `"5 endpoints monitored · no failed builds"` |
| sublabel-003 | ok-ignores-problems | the sublabel-building function called with state `"ok"`, `healthyCount` 3, `servicesLength` 3, problems `[row("down")]` | `"3/3 endpoints healthy · no failed builds"` |
| sublabel-004 | ok-strict-equality | the sublabel-building function called with state `"ok"`, `healthyCount` 6, `servicesLength` 5, no problems | `"5 endpoints monitored · no failed builds"` |
| sublabel-005 | ok-all-healthy | the sublabel-building function called with state `"ok"`, `healthyCount` 0, `servicesLength` 0, no problems | `"0/0 endpoints healthy · no failed builds"` |
| sublabel-006 | breakdown-phrase-down, breakdown-phrase-degraded, breakdown-separator | the sublabel-building function called with state `"warn"`, problems `[row("degraded"), row("down"), row("down")]` | `"2 down · 1 degraded"` |
| sublabel-007 | breakdown-phrase-build-failed | the sublabel-building function called with state `"down"`, problems `[row("build failed")]`; the same with two such rows | `"1 failed build"`; `"2 failed builds"` |
| sublabel-008 | breakdown-phrase-deploy-failed | the sublabel-building function called with state `"down"`, problems `[row("deploy failed")]`; the same with three such rows | `"1 failed deploy"`; `"3 failed deploys"` |
| sublabel-009 | breakdown-phrase-deployment-failed | the sublabel-building function called with state `"warn"`, problems `[row("deployment failed"), row("deployment failed")]` | `"2 stale deploys"` |
| sublabel-010 | breakdown-phrase-building | the sublabel-building function called with state `"warn"`, problems `[row("building")]` | `"1 stuck build"` |
| sublabel-011 | breakdown-phrase-platform-unreachable | the sublabel-building function called with state `"down"`, problems one `row("platform unreachable")`; then two such rows | `"1 platform unreachable"`; `"2 platforms unreachable"` |
| sublabel-012 | breakdown-mapped-order | the sublabel-building function called with state `"down"`, problems `[row("building"), row("build failed"), row("down")]` | `"1 down · 1 failed build · 1 stuck build"` |
| sublabel-013 | breakdown-unmapped-verbatim, breakdown-unmapped-after-mapped | the sublabel-building function called with state `"warn"`, problems `[row("expired"), row("down"), row("cert warn"), row("expired")]` | `"1 down · 2 expired · 1 cert warn"` |
| sublabel-014 | breakdown-empty-problems | the sublabel-building function called with state `"warn"`, `healthyCount` 5, `servicesLength` 5, no problems | `""` |
| sublabel-015 | breakdown-group-by-status-word | the sublabel-building function called with state `"warn"`, problems `[row("Down")]` | `"1 Down"` (unmapped, because matching is case-sensitive) |
| sublabel-016 | breakdown-sums-to-problem-count | any non-ok call with a problems list of length 7 over mixed words | the integers in the result add up to 7 |
| sublabel-017 | breakdown-ignores-counts-args | the sublabel-building function called with state `"down"`, `healthyCount` 1, `servicesLength` 9, problems `[row("down")]`, versus `healthyCount` 9, `servicesLength` 9 with the same problems | both `"1 down"` |
| sublabel-018 | sublabel-pure | call with a frozen `problems` list of frozen rows | returns normally; the list and rows are unchanged |

## Edge Cases

- **Empty problems with a non-ok state**: The function MUST return `""`. The big indicator view renders the sublabel only when it is truthy, so the caption disappears. This logic itself does not guard this pairing.
- **Non-empty problems with a state of `"ok"`**: The problems MUST be ignored, and the clear-board line MUST be returned.
- **Zero services while ok**: state `"ok"`, `healthyCount` 0, `servicesLength` 0, no problems MUST return `"0/0 endpoints healthy · no failed builds"`. The function does not treat "monitoring nothing" as blindness. The overview tab view handles that case with its own blind-state panel, so this string does not reach the screen there.
- **`healthyCount` greater than `servicesLength`**: The function MUST take the "monitored" branch. It never prints an impossible fraction.
- **Negative, fractional or not-a-number counts**: They are interpolated with default number-to-string conversion (e.g. `"NaN endpoints monitored · no failed builds"`), and the function MUST NOT throw. Not-a-number is never equal to itself, so such inputs MUST take the "monitored" branch. The caller derives both counts from list lengths, which makes this a typed caller precondition.
- **Unknown status word**: The row MUST still be counted and rendered verbatim, so the breakdown keeps its sum-to-count guarantee.
- **Empty-string status word**: It is an unmapped word and MUST render as `<n> ` (count followed by a trailing space) in the unmapped section.
- **Status word differing only by case or whitespace**: It MUST be treated as a distinct, unmapped word (e.g. `"Down"` or `"down "`).
- **Large counts**: The count is interpolated as-is. Every value other than exactly 1 takes the plural suffix, including 0, which cannot occur because zero-count groups are skipped.
- **Concurrent access**: Not applicable. The function is stateless and synchronous, so calls cannot interleave. The sublabel-phrase table is a constant that is never written.
- **Error states and offline**: Not applicable. The function performs no I/O. A missing or stale board is handled by the overview tab view's early returns before the sublabel-building function is called.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `state` | one of `"ok"`, `"warn"`, `"down"` | none (required) | Chooses the clear-board line (`"ok"`) or the problem breakdown (anything else). |
| `healthyCount` | number | none (required) | Number of endpoints reporting healthy; used only when `state` is `"ok"`. |
| `servicesLength` | number | none (required) | Number of endpoints monitored; used only when `state` is `"ok"`. |
| `problems` | a list of rows | none (required) | The problem rows; only `statusWord` is read, and only when `state` is not `"ok"`. |
| the sublabel-phrase table | internal lookup table | seven compiled-in entries | Private map from status word to phrase formatter; not configurable by callers. |

This logic reads no environment variables or settings keys and takes no injected dependencies. It imports only type definitions.

## Deep Linking

Not applicable: this logic exports one pure function and has no navigable surface.

## Localization

Every string the function returns is hardcoded English, with no localization layer. Pluralization is a binary count-equals-1 test that appends `s` (or, for platforms, swaps in "platforms"). The `down`, `degraded` and unmapped phrases are never pluralized. The separator is a literal `" · "`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `{healthy}/{total} endpoints healthy · no failed builds` | Clear board, every endpoint healthy |
| (none; literal) | `{total} endpoints monitored · no failed builds` | Clear board, not every endpoint healthy |
| (none; literal) | `{n} down` | Breakdown, `down` rows |
| (none; literal) | `{n} degraded` | Breakdown, `degraded` rows |
| (none; literal) | `{n} failed build` / `{n} failed builds` | Breakdown, `build failed` rows |
| (none; literal) | `{n} failed deploy` / `{n} failed deploys` | Breakdown, `deploy failed` rows |
| (none; literal) | `{n} stale deploy` / `{n} stale deploys` | Breakdown, `deployment failed` rows |
| (none; literal) | `{n} stuck build` / `{n} stuck builds` | Breakdown, `building` rows |
| (none; literal) | `{n} platform unreachable` / `{n} platforms unreachable` | Breakdown, `platform unreachable` rows |
| (none; literal) | `{n} {statusWord}` | Breakdown, any unmapped status word (the word comes from the row) |
| (none; literal) | ` · ` | Separator between phrases |

## Accessibility Options

Not applicable: this logic renders nothing and responds to no display setting.

## Feature Flags

Not applicable: the sublabel-building function reads no flag.

## Analytics

Not applicable: this logic emits no events.

## Privacy

Not applicable: the function reads only problem status words and endpoint counts, and it stores and transmits nothing.

## Logging

Not applicable: this logic makes no log calls.

## Platform Notes

- **SwiftUI**: Port as a free function or a static member of a caseless `enum StatusSublabel` that returns `String`. Model `IndicatorState` as `enum IndicatorState: String, Sendable { case ok, warn, down }`. Swift `Dictionary` has no insertion order, so keep the phrase table as an ordered array of `(word: String, format: @Sendable (Int) -> String)` pairs. Group unmapped words with an array plus a `[String: Int]` counter to keep first-seen order (or use `OrderedDictionary` from swift-collections). Join the parts with `joined(separator: " · ")`. Use `String(localized:)` with a stringsdict plural variant if the strings are localized.
- **Compose**: Use a Kotlin top-level function. `linkedMapOf` and `LinkedHashMap` preserve insertion order, which gives both the table order and the first-seen order for unmapped words. `problems.groupingBy { it.statusWord }.eachCount()` returns a `LinkedHashMap` in first-seen order. Join with `joinToString(" · ")`. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/status-sublabel.ts`, exporting `buildSublabel(state, healthyCount, servicesLength, problems)` and the private table `SUBLABEL_PHRASE`, called from `src/components/OverviewTab.tsx` and rendered by `src/components/BigIndicator.tsx`. The ordering depends on two JavaScript guarantees. `Object.entries` returns string (non-integer) keys in insertion order, and `Map` iterates in insertion order. The function deletes each mapped word from the `Map` so that only unmapped words remain for the second loop. The single-threaded JavaScript runtime is what guarantees synchronous calls cannot interleave (sublabel-synchronous, and Concurrent access above).
- **AppKit / UIKit**: Use the same pure Swift port as SwiftUI, placed in a shared framework target. Nothing in it is UI-bound.
- **WinUI 3**: Port as `public static string BuildSublabel(IndicatorState state, int healthyCount, int servicesLength, IReadOnlyList<Row> problems)` in a `public static class StatusSublabel`, with `public enum IndicatorState { Ok, Warn, Down }`. `Dictionary<string, int>` does not guarantee enumeration order, so keep the phrase table as a `static readonly (string Word, Func<int, string> Format)[]` array. Count groups with a `Dictionary<string, int>` (ordinal comparer, matching JavaScript's case-sensitive keys) and keep a `List<string>` of first-seen words for the unmapped tail. Join with `string.Join(" · ", parts)`. Format numbers with `CultureInfo.InvariantCulture` or `ToString()` under the invariant culture, so a comma decimal separator cannot appear. If localized, the strings go in `.resw` resources through `ResourceLoader`, with plural handling moved to a helper, because `.resw` has no plural rules. The view model that exposes the sublabel raises `INotifyPropertyChanged` when its inputs change. The function itself stays synchronous, with no `Task`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/status-sublabel.ts` |

## Design Decisions

**Decision**: When the board is operational, print "N/N endpoints healthy" only when every endpoint is healthy, and otherwise print "N endpoints monitored".
**Rationale**: The source comment explains that under an operational board, a non-healthy endpoint is a transient blip (degraded within the window) or an unprobed one, not an incident. A fraction such as "4/5 healthy" beside "ALL SYSTEMS OPERATIONAL" would read as a contradiction.
**Approved**: pending

**Decision**: The breakdown accounts for every problem, and unmapped status words fall through verbatim.
**Rationale**: The doc comment requires the parts to "sum to the indicator count". A status word added elsewhere without a table entry still shows up as `{n} {word}` rather than silently disappearing from the caption.
**Approved**: pending

**Decision**: Some status words are relabelled rather than echoed: `building` becomes "stuck build" and `deployment failed` becomes "stale deploy".
**Rationale**: The source comment says a building row "only reaches Problems when stuck", so "stuck" names the actual condition. The "stale deploy" wording for `deployment failed` is taken directly from `SUBLABEL_PHRASE` and distinguishes it from the `deploy failed` phrase.
**Approved**: pending

**Decision**: One function serves every status caption surface.
**Rationale**: The doc comment says it is shared by the mobile hero and the desktop top-bar pill, so the two surfaces cannot word the same board differently. In the current tree only `OverviewTab` (feeding `BigIndicator`) calls it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [plural-forms](agenticdevelopercookbook://compliance/internationalization#plural-forms) | partial | internationalization |

**Separation of concerns.** The module only formats text. Problem derivation and indicator state come from the server's board through `OverviewTab`, and the endpoint counts are computed by the caller.

**Unit test coverage.** No test file exists for `status-sublabel.ts`, and no other test in `status-web` exercises `buildSublabel`.

**Explicit error handling.** No operation can fail. Unknown status words and empty inputs have defined outputs (verbatim phrase and `""`), so nothing is silently dropped.

**No hardcoded strings.** Every phrase, and the separator, is an English literal in the source.

**Plural forms.** Five of the seven mapped phrases apply an English singular/plural switch on `n === 1`. `down`, `degraded` and unmapped words are never pluralized, and no locale plural rules are used.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
