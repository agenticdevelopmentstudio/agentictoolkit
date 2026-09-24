---
id: d79f556c-163b-48aa-82f0-baff52fa9dab
title: Status Sublabel
domain: agentictoolkit://recipes/status-web-src-lib-status-sublabel
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- agentictoolkit://recipes/status-web-src-lib-row-model
- agentictoolkit://recipes/status-web-src-lib-overview
related: []
references: []
approved-by: ''
approved-date: ''
---

# Status Sublabel

## Overview

`status-sublabel.ts` (`packages/web/packages/status-web/src/lib/status-sublabel.ts`) exports one pure, synchronous function, `buildSublabel(state, healthyCount, servicesLength, problems)`, that returns the one-line caption shown under the status headline. When the board is clear it reads like "12/12 endpoints healthy · no failed builds". Otherwise it is a grouped breakdown of the problem rows, such as "2 down · 1 failed build", and the doc comment requires it to account "for EVERY problem so the parts sum to the indicator count".

The doc comment says the function is "Shared by the mobile hero and the desktop top-bar pill". In the current tree its only caller is `src/components/OverviewTab.tsx`, which passes the result to `BigIndicator` as `sublabel`. The inputs are typed by `IndicatorState` from [Overview Projections](agentictoolkit://recipes/status-web-src-lib-overview) and `Row` from [Row Model](agentictoolkit://recipes/status-web-src-lib-row-model). The function reads only `Row.statusWord`.

The module also holds a private table, `SUBLABEL_PHRASE`, which maps a problem row's status word to a function that formats a count into a phrase.

## Behavioral Requirements

### Signature and purity

- **sublabel-signature**: `buildSublabel` MUST take `state: IndicatorState`, `healthyCount: number`, `servicesLength: number` and `problems: Row[]`, and MUST return a `string`.
- **sublabel-pure**: `buildSublabel` MUST have no side effects. It MUST NOT mutate `problems` or any row, and MUST NOT perform I/O, log, or read global state.
- **sublabel-synchronous**: `buildSublabel` MUST return its result synchronously. The module runs on single-threaded JavaScript, so calls cannot interleave.
- **sublabel-no-throw**: For inputs that match the declared types, `buildSublabel` MUST NOT throw. No path in the function raises an error.

### Clear board (`state === "ok"`)

- **ok-ignores-problems**: When `state` is `"ok"`, the result MUST NOT depend on `problems`, even if the array is non-empty.
- **ok-all-healthy**: When `state` is `"ok"` and `healthyCount === servicesLength`, the function MUST return `` `${healthyCount}/${servicesLength} endpoints healthy · no failed builds` ``.
- **ok-not-all-healthy**: When `state` is `"ok"` and `healthyCount !== servicesLength`, the function MUST return `` `${servicesLength} endpoints monitored · no failed builds` `` and MUST NOT print a fraction. The source comment explains why: while the board is operational, a non-healthy endpoint is a transient blip or an unprobed endpoint, and "4/5 healthy" would contradict "ALL SYSTEMS OPERATIONAL".
- **ok-strict-equality**: The all-healthy test MUST be strict numeric equality (`===`). Any other relationship, including `healthyCount > servicesLength`, MUST take the "monitored" branch.

### Problem breakdown (`state` is `"warn"` or `"down"`)

- **breakdown-group-by-status-word**: For any `state` other than `"ok"`, the function MUST count `problems` grouped by exact `statusWord`. Matching is case-sensitive and whitespace-sensitive.
- **breakdown-ignores-counts-args**: For any `state` other than `"ok"`, the result MUST NOT depend on `healthyCount` or `servicesLength`.
- **breakdown-phrase-down**: A group of `n` rows with status word `"down"` MUST render as `` `${n} down` ``. This phrase has no plural form.
- **breakdown-phrase-degraded**: A group of `n` rows with status word `"degraded"` MUST render as `` `${n} degraded` ``. This phrase has no plural form.
- **breakdown-phrase-build-failed**: A group with status word `"build failed"` MUST render as `"1 failed build"` when `n === 1`, and as `` `${n} failed builds` `` for every other `n`.
- **breakdown-phrase-deploy-failed**: A group with status word `"deploy failed"` MUST render as `"1 failed deploy"` when `n === 1`, and as `` `${n} failed deploys` `` otherwise.
- **breakdown-phrase-deployment-failed**: A group with status word `"deployment failed"` MUST render as `"1 stale deploy"` when `n === 1`, and as `` `${n} stale deploys` `` otherwise. The status word is relabelled as "stale", not "failed".
- **breakdown-phrase-building**: A group with status word `"building"` MUST render as `"1 stuck build"` when `n === 1`, and as `` `${n} stuck builds` `` otherwise. The source comment gives the reason: "a building row only reaches Problems when stuck".
- **breakdown-phrase-platform-unreachable**: A group with status word `"platform unreachable"` MUST render as `"1 platform unreachable"` when `n === 1`, and as `` `${n} platforms unreachable` `` otherwise.
- **breakdown-mapped-order**: Mapped phrases MUST appear in the fixed table order `down`, `degraded`, `build failed`, `deploy failed`, `deployment failed`, `building`, `platform unreachable`, whatever order the rows arrive in.
- **breakdown-unmapped-verbatim**: A status word with no entry in `SUBLABEL_PHRASE` MUST render as `` `${n} ${statusWord}` ``, using the word verbatim with no pluralization.
- **breakdown-unmapped-after-mapped**: Unmapped groups MUST appear after all mapped phrases, in the order each word first occurs in `problems`.
- **breakdown-no-zero-groups**: Only status words that occur at least once in `problems` MUST produce a phrase. The function MUST NOT emit a zero-count phrase.
- **breakdown-separator**: Phrases MUST be joined with `" · "` (space, U+00B7 MIDDLE DOT, space), with no leading or trailing separator.
- **breakdown-sums-to-problem-count**: The counts in the phrases MUST add up to `problems.length`, so every problem row is counted exactly once.
- **breakdown-empty-problems**: For any `state` other than `"ok"` with an empty `problems`, the function MUST return the empty string `""`.

### Caller preconditions

- **caller-pairs-state-and-problems**: The function MUST trust the caller's pairing of `state` with `problems` and MUST NOT re-derive the state. The "sum to the indicator count" guarantee in the doc comment holds only when the caller passes the same problem set the indicator counted. `OverviewTab` pairs `indicator.state` with its `problems` rows.
- **caller-counts-services**: `healthyCount` and `servicesLength` are caller-computed. `OverviewTab` passes the number of env-filtered services with `status === "healthy"` and the length of that filtered list. The function does not validate them.

## Appearance

Not applicable — this is a pure string-formatting function, not a visual component.

## States

Not applicable — this is a pure string-formatting function, not a visual component.

## Accessibility

Not applicable — this is a pure string-formatting function, not a visual component.

## Conformance Test Vectors

The source has no test file (`status-sublabel.test.ts` does not exist). These vectors are derived from `buildSublabel` and `SUBLABEL_PHRASE`. `row(w)` stands for a `Row` whose `statusWord` is `w`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sublabel-001 | ok-all-healthy | `buildSublabel("ok", 12, 12, [])` | `"12/12 endpoints healthy · no failed builds"` |
| sublabel-002 | ok-not-all-healthy | `buildSublabel("ok", 4, 5, [])` | `"5 endpoints monitored · no failed builds"` |
| sublabel-003 | ok-ignores-problems | `buildSublabel("ok", 3, 3, [row("down")])` | `"3/3 endpoints healthy · no failed builds"` |
| sublabel-004 | ok-strict-equality | `buildSublabel("ok", 6, 5, [])` | `"5 endpoints monitored · no failed builds"` |
| sublabel-005 | ok-all-healthy | `buildSublabel("ok", 0, 0, [])` | `"0/0 endpoints healthy · no failed builds"` |
| sublabel-006 | breakdown-phrase-down, breakdown-phrase-degraded, breakdown-separator | `buildSublabel("warn", 0, 0, [row("degraded"), row("down"), row("down")])` | `"2 down · 1 degraded"` |
| sublabel-007 | breakdown-phrase-build-failed | `buildSublabel("down", 0, 0, [row("build failed")])`; the same with two rows | `"1 failed build"`; `"2 failed builds"` |
| sublabel-008 | breakdown-phrase-deploy-failed | `buildSublabel("down", 0, 0, [row("deploy failed")])`; the same with three rows | `"1 failed deploy"`; `"3 failed deploys"` |
| sublabel-009 | breakdown-phrase-deployment-failed | `buildSublabel("warn", 0, 0, [row("deployment failed"), row("deployment failed")])` | `"2 stale deploys"` |
| sublabel-010 | breakdown-phrase-building | `buildSublabel("warn", 0, 0, [row("building")])` | `"1 stuck build"` |
| sublabel-011 | breakdown-phrase-platform-unreachable | one `row("platform unreachable")`; then two such rows, with state `"down"` | `"1 platform unreachable"`; `"2 platforms unreachable"` |
| sublabel-012 | breakdown-mapped-order | `buildSublabel("down", 0, 0, [row("building"), row("build failed"), row("down")])` | `"1 down · 1 failed build · 1 stuck build"` |
| sublabel-013 | breakdown-unmapped-verbatim, breakdown-unmapped-after-mapped | `buildSublabel("warn", 0, 0, [row("expired"), row("down"), row("cert warn"), row("expired")])` | `"1 down · 2 expired · 1 cert warn"` |
| sublabel-014 | breakdown-empty-problems | `buildSublabel("warn", 5, 5, [])` | `""` |
| sublabel-015 | breakdown-group-by-status-word | `buildSublabel("warn", 0, 0, [row("Down")])` | `"1 Down"` (unmapped, because matching is case-sensitive) |
| sublabel-016 | breakdown-sums-to-problem-count | any non-ok call with `problems.length === 7` over mixed words | the integers in the result add up to 7 |
| sublabel-017 | breakdown-ignores-counts-args | `buildSublabel("down", 1, 9, [row("down")])` vs `buildSublabel("down", 9, 9, [row("down")])` | both `"1 down"` |
| sublabel-018 | sublabel-pure | call with a frozen `problems` array of frozen rows | returns normally; the array and rows are unchanged |

## Edge Cases

- **Empty problems with a non-ok state**: The function MUST return `""`. `BigIndicator` renders the sublabel only when it is truthy, so the caption disappears. The module itself does not guard this pairing.
- **Non-empty problems with `state === "ok"`**: The problems MUST be ignored, and the clear-board line MUST be returned.
- **Zero services while ok**: `buildSublabel("ok", 0, 0, [])` MUST return `"0/0 endpoints healthy · no failed builds"`. The function does not treat "monitoring nothing" as blindness. `OverviewTab` handles that case with its `store.blind` panel, so this string does not reach the screen there.
- **`healthyCount` greater than `servicesLength`**: The function MUST take the "monitored" branch. It never prints an impossible fraction.
- **Negative, fractional or `NaN` counts**: They are interpolated with default number-to-string conversion (e.g. `"NaN endpoints monitored · no failed builds"`), and the function MUST NOT throw. `NaN === NaN` is false, so `NaN` inputs MUST take the "monitored" branch. The caller derives both counts from array lengths, which makes this a typed caller precondition.
- **Unknown status word**: The row MUST still be counted and rendered verbatim, so the breakdown keeps its sum-to-count guarantee.
- **Empty-string status word**: It is an unmapped word and MUST render as `` `${n} ` `` (count followed by a trailing space) in the unmapped section.
- **Status word differing only by case or whitespace**: It MUST be treated as a distinct, unmapped word (e.g. `"Down"` or `"down "`).
- **Large counts**: The count is interpolated as-is. Every value other than exactly 1 takes the plural suffix, including 0, which cannot occur because zero-count groups are skipped.
- **Concurrent access**: Not applicable. The function is stateless and runs on single-threaded JavaScript. `SUBLABEL_PHRASE` is a module constant that is never written.
- **Error states and offline**: Not applicable. The function performs no I/O. A missing or stale board is handled by `OverviewTab`'s early returns before `buildSublabel` is called.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `state` | `IndicatorState` (`"ok" \| "warn" \| "down"`) | none (required) | Chooses the clear-board line (`"ok"`) or the problem breakdown (anything else). |
| `healthyCount` | `number` | none (required) | Number of endpoints reporting healthy; used only when `state` is `"ok"`. |
| `servicesLength` | `number` | none (required) | Number of endpoints monitored; used only when `state` is `"ok"`. |
| `problems` | `Row[]` | none (required) | The problem rows; only `statusWord` is read, and only when `state` is not `"ok"`. |
| `SUBLABEL_PHRASE` | `Record<string, (n: number) => string>` | seven compiled-in entries | Private map from status word to phrase formatter; not configurable by callers. |

The module reads no environment variables or settings keys and takes no injected dependencies. It imports only types.

## Deep Linking

Not applicable: the module exports one pure function and has no navigable surface.

## Localization

Every string the function returns is hardcoded English, with no localization layer. Pluralization is a binary `n === 1` test that appends `s` (or, for platforms, swaps in "platforms"). The `down`, `degraded` and unmapped phrases are never pluralized. The separator is a literal `" · "`.

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

Not applicable: the module renders nothing and responds to no display setting.

## Feature Flags

Not applicable: the source reads no flag.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the function reads only problem status words and endpoint counts, and it stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as a free function or a static member of a caseless `enum StatusSublabel` that returns `String`. Model `IndicatorState` as `enum IndicatorState: String, Sendable { case ok, warn, down }`. Swift `Dictionary` has no insertion order, so keep the phrase table as an ordered array of `(word: String, format: @Sendable (Int) -> String)` pairs. Group unmapped words with an array plus a `[String: Int]` counter to keep first-seen order (or use `OrderedDictionary` from swift-collections). Join the parts with `joined(separator: " · ")`. Use `String(localized:)` with a stringsdict plural variant if the strings are localized.
- **Compose**: Use a Kotlin top-level function. `linkedMapOf` and `LinkedHashMap` preserve insertion order, which gives both the table order and the first-seen order for unmapped words. `problems.groupingBy { it.statusWord }.eachCount()` returns a `LinkedHashMap` in first-seen order. Join with `joinToString(" · ")`. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/status-sublabel.ts`, called from `src/components/OverviewTab.tsx` and rendered by `src/components/BigIndicator.tsx`. The ordering depends on two JavaScript guarantees. `Object.entries` returns string (non-integer) keys in insertion order, and `Map` iterates in insertion order. The function deletes each mapped word from the `Map` so that only unmapped words remain for the second loop.
- **AppKit / UIKit**: Use the same pure Swift port as SwiftUI, placed in a shared framework target. Nothing in it is UI-bound.
- **WinUI 3**: Port as `public static string BuildSublabel(IndicatorState state, int healthyCount, int servicesLength, IReadOnlyList<Row> problems)` in a `public static class StatusSublabel`, with `public enum IndicatorState { Ok, Warn, Down }`. `Dictionary<string, int>` does not guarantee enumeration order, so keep the phrase table as a `static readonly (string Word, Func<int, string> Format)[]` array. Count groups with a `Dictionary<string, int>` (ordinal comparer, matching JavaScript's case-sensitive keys) and keep a `List<string>` of first-seen words for the unmapped tail. Join with `string.Join(" · ", parts)`. Format numbers with `CultureInfo.InvariantCulture` or `ToString()` under the invariant culture, so a comma decimal separator cannot appear. If localized, the strings go in `.resw` resources through `ResourceLoader`, with plural handling moved to a helper, because `.resw` has no plural rules. The view model that exposes the sublabel raises `INotifyPropertyChanged` when its inputs change. The function itself stays synchronous, with no `Task`.

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
| 1.0.0 | | | Initial creation from source |
