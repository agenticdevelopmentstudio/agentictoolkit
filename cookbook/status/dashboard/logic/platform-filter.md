---
id: 74380f06-a663-44c7-981d-191301a66b8e
title: Platform Filter Options
domain: agentictoolkit://cookbook/status/dashboard/logic/platform-filter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure taxonomy for the Sites config Platform filter: always lists known platforms,
  then unknown ones present, then a no-platform row'
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/logic/filter
references: []
approved-by: ''
approved-date: ''
---

# Platform Filter Options

## Overview

The platform filter options logic holds the option taxonomy for the Platform filter in the Sites config list. It provides three things: a no-platform sentinel value, a function that returns the full set of known platform keys, and a pure function that computes the filter's option rows from a list of endpoints.

The logic exists to fix a specific bug: a purely data-driven list only showed platforms present among the endpoints, so an entry such as "railway" vanished from the filter whenever no site was wired to it. The fix is that every known platform is always offered, regardless of which endpoints exist.

The known platforms are a canonical, ordered list, currently `vercel`, `railway`, `cloudflare`, and `crunchy`. Each option row carries a key and a label.

The one caller is the endpoints configuration view. It seeds its selection state with the full set of known keys (including the no-platform sentinel), resets it to that full set or to an empty set from its "all" toggle, recomputes its option rows whenever the endpoint list changes, and keeps an endpoint visible when its selection contains that endpoint's platform (with an absent platform mapped to the no-platform sentinel). The logic itself holds no state and performs no I/O.

## Behavioral Requirements

- **none-sentinel**: The logic MUST provide a no-platform sentinel value equal to `"__none__"`, used as the filter key for an endpoint whose platform is absent (`null`).
- **all-keys-contents**: The all-keys function MUST return a collection with set semantics (each key present at most once) containing every entry of the known-platforms list plus the no-platform sentinel, and nothing else.
- **all-keys-fresh-set**: The all-keys function MUST return a newly created collection on every call, so a caller that mutates the result does not change the next result.
- **all-keys-ignores-data**: The all-keys function MUST take no arguments and MUST include the no-platform sentinel whether or not any endpoint is unwired.
- **options-signature**: The options function MUST accept a list of endpoints, each carrying a platform value that is either a string or absent (`null`), and MUST return a list of options, each with a `key` and a `label`.
- **options-synchronous**: The options function MUST return its result synchronously and MUST NOT mutate its argument, keep state between calls, or perform I/O.
- **known-platforms-always**: The options function MUST emit one row for every entry of the known-platforms list, even when no endpoint uses that platform or the input list is empty.
- **known-platforms-order**: The known-platform rows MUST come first, in the canonical order of the known-platforms list.
- **known-platform-label**: Each known-platform row MUST use the platform string as both key and label (for example a row with key and label both equal to `railway`), with no capitalization or display-name mapping.
- **known-platform-no-duplicate**: A known platform that is also present among the endpoints MUST appear exactly once.
- **unknown-platforms-appended**: Every non-null platform value present among the endpoints that is not in the known-platforms list MUST get one row, with the value as both key and label, placed after all known-platform rows.
- **unknown-platforms-order**: Unknown-platform rows MUST appear in the order their value first occurs in the input list.
- **unknown-platforms-deduplicated**: An unknown value that occurs on several endpoints MUST produce exactly one row.
- **known-match-exact**: Membership in the known-platforms list MUST be tested by exact, case-sensitive string equality, so a value such as `"Vercel"` is treated as an unknown platform.
- **none-row-conditional**: The options function MUST append a row whose key is the no-platform sentinel and whose label is `"no platform"` only when at least one endpoint has an absent platform.
- **none-row-last**: When the no-platform row is present, it MUST be the final row.
- **null-maps-to-sentinel**: An absent (`null`) platform MUST be mapped to the no-platform sentinel before de-duplication, and MUST NOT produce an unknown-platform row.
- **no-errors**: The options function and the all-keys function MUST NOT throw for input matching the expected shape; the logic has no failure path and returns no error values.
- **selection-contract**: A caller that keeps an endpoint when its selection contains that endpoint's platform (or the no-platform sentinel when absent) MUST see every known platform and every unwired endpoint pass when the selection is the full set returned by the all-keys function. An endpoint with an unknown platform is not in that full set and so does not pass that default selection.
- **single-threaded**: Both functions MUST run to completion synchronously; the logic has no asynchronous work and no shared mutable state, so calls cannot interleave.

## Appearance

Not applicable — this is a pure option-taxonomy function, not a visual component.

## States

Not applicable — this is a pure option-taxonomy function, not a visual component.

## Accessibility

Not applicable — this is a pure option-taxonomy function, not a visual component.

## Conformance Test Vectors

Vectors pf-001 to pf-006 are derived from the implementation's test suite (see Platform Notes). The rest trace to the options and all-keys functions directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pf-001 | known-platforms-always, known-platforms-order | endpoints with platforms `vercel`, `vercel`, `cloudflare` | keys `["vercel","railway","cloudflare","crunchy"]` (railway present with zero endpoints) |
| pf-002 | known-platforms-always | empty endpoint list | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-003 | none-row-conditional | endpoints with platform `vercel` | no row has the no-platform sentinel as its key |
| pf-004 | none-row-conditional, none-row-last, null-maps-to-sentinel | endpoints with platforms `vercel`, absent | last row's key/label equal the no-platform sentinel and `"no platform"` |
| pf-005 | unknown-platforms-appended, none-row-last | endpoints with platforms `fly`, absent | keys `["vercel","railway","cloudflare","crunchy","fly","__none__"]` |
| pf-006 | known-platform-no-duplicate | endpoints with platforms `railway`, `railway` | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-007 | all-keys-contents, all-keys-ignores-data | call the all-keys function | set equal to `{"vercel","railway","cloudflare","crunchy","__none__"}` |
| pf-008 | known-platform-label | second row of the options for an empty endpoint list | key and label both `"railway"` |
| pf-009 | unknown-platforms-order, unknown-platforms-deduplicated | endpoints with platforms `render`, `fly`, `render` | keys `["vercel","railway","cloudflare","crunchy","render","fly"]` |
| pf-010 | known-match-exact | endpoints with platform `"Vercel"` | keys `["vercel","railway","cloudflare","crunchy","Vercel"]` |
| pf-011 | all-keys-fresh-set | call the all-keys function, clear the result, call it again, read its size | `5` |
| pf-012 | none-sentinel | read the no-platform sentinel value | `"__none__"` |
| pf-013 | options-synchronous | call the options function with an immutable input list | returns rows without throwing; input unchanged |
| pf-014 | selection-contract | selection equal to the full known-key set; endpoints with platforms `railway`, absent, `fly` | `railway` and the absent-platform endpoint pass; `fly` endpoint does not |
| pf-015 | no-errors, single-threaded | call both functions with valid input | return a value synchronously (not a deferred result); nothing thrown |

## Edge Cases

- **Empty endpoint list**: The options function on an empty list MUST return exactly the four known-platform rows, with no no-platform row (pf-002).
- **All endpoints unwired**: Input where every platform is absent MUST return the four known-platform rows followed by the no-platform row.
- **Empty-string platform**: A platform of `""` is not absent and not in the known-platforms list, so it MUST produce an unknown-platform row with key `""` and label `""`. The logic does not reject or relabel it; the endpoints configuration view sets platform from a fixed selection control, which bounds how such a value could arise.
- **Value equal to the sentinel**: An endpoint whose platform is the literal string equal to the no-platform sentinel MUST be treated as unwired: it produces the no-platform row and no unknown-platform row, because the sentinel check does not distinguish it from an absent platform.
- **Case variants**: `"Vercel"` or `"RAILWAY"` MUST produce separate unknown-platform rows, since matching is case-sensitive (pf-010).
- **Unknown platform under the default selection**: An endpoint with an unknown platform gets a filter row but its key is not in the full set returned by the all-keys function. With the default or "all" selection, a caller filtering by set membership MUST hide it until the operator selects that row (pf-014).
- **Missing platform field**: A platform value that is entirely absent from the record (rather than explicitly `null`) MUST be treated the same as `null` and mapped to the no-platform sentinel.
- **Large input**: Work is linear in the number of endpoints plus a scan of the known-platforms list per distinct value; there is no size limit and no truncation.
- **Concurrent access**: Not applicable. Both functions are synchronous and stateless, and run to completion without yielding, so calls cannot interleave.
- **Error states and offline**: Not applicable. The logic performs no I/O, so there is no dependency to fail and no connectivity to lose.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `endpoints` | list of objects, each with a `platform` field (string or absent) | required | Monitored endpoints whose `platform` values drive the unknown and no-platform rows. |
| known-platforms list | ordered list of strings | `vercel`, `railway`, `cloudflare`, `crunchy` | Canonical known-platform list and order; editing it changes both functions. |
| no-platform sentinel | string | `"__none__"` | Sentinel key for an endpoint with no platform. |

No environment variables, settings keys or injected dependencies are read.

## Deep Linking

Not applicable: the logic returns option data only and defines no route or URL.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; hardcoded) | `no platform` | Label of the trailing row for endpoints with an absent platform, returned by the options function. |

The label `"no platform"` is a hardcoded English literal with no localization lookup. Known and unknown platform rows use the raw platform string as the label, untranslated.

## Accessibility Options

Not applicable: the logic renders nothing; the filter control owns presentation of the rows.

## Feature Flags

Not applicable: neither function reads a flag; the known platforms are always offered unconditionally.

## Analytics

Not applicable: the logic emits no events.

## Privacy

Not applicable: the logic reads only platform names, collects no data, and stores or transmits nothing.

## Logging

Not applicable: the logic has no log calls.

## Platform Notes

- **SwiftUI**: Port as free functions over a `static let platforms = ["vercel", "railway", "cloudflare", "crunchy"]`. Build the present set while preserving first-seen order: Swift `Set` is unordered, so track insertion with an `[String]` plus a `Set<String>` (or `OrderedSet` from swift-collections) to keep **unknown-platforms-order**. Map `nil` with `endpoint.platform ?? platformNone`. Return `[MultiSelectOption]` where the option is a `struct` that is `Identifiable, Hashable, Sendable`, and feed it to a `Menu` of `Toggle`s. Hold the selection as `@State var platformFilter: Set<String> = allPlatformKeys()`.
- **Compose**: Write top-level Kotlin functions. `endpoints.map { it.platform ?: PLATFORM_NONE }.toSet()` returns a `LinkedHashSet`, which keeps first-seen order like the JavaScript `Set`. Use `PLATFORMS.contains(k)` for exact-case matching. Return `List<MultiSelectOption>` of a `data class`. Hold the selection in `remember { mutableStateOf(allPlatformKeys()) }` and derive rows with `remember(endpoints) { platformFilterOptions(endpoints) }`.
- **React/Web**: This is the source: `platform-filter.ts` (`packages/web/packages/status-web/src/lib/platform-filter.ts`), tested by `platform-filter.test.ts` (vitest; vectors pf-001 to pf-006 are derived from its assertions). It exports the sentinel `PLATFORM_NONE` (`"__none__"`), the factory `allPlatformKeys()`, and the pure function `platformFilterOptions(endpoints)`. The known-platforms list is `PLATFORMS` from `src/api/monitored-sites.ts`, currently `["vercel", "railway", "cloudflare", "crunchy"]` (declared `as const`); it relies on `PLATFORMS` being a `readonly` tuple (hence the `as readonly string[]` cast before `includes`). Options use the `MultiSelectOption` shape (`{ key: string; label: string }`) from `src/components/MultiSelectFilter.tsx`, which also owns presentation of the rows. The one call site is `EndpointsSection` (`src/components/configure/EndpointsSection.tsx`): it seeds its selection state with `useState(allPlatformKeys)`, resets it with `allPlatformKeys()` or an empty set from its "all" toggle, builds its rows with `useMemo(() => platformFilterOptions(endpoints), [endpoints])`, and keeps an endpoint when `platformFilter.has(e.platform ?? PLATFORM_NONE)`. It relies on the JavaScript `Set` keeping insertion order and on `Array.prototype.includes` for exact matching; the single-thread guarantee noted under Edge Cases comes from JavaScript's execution model.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port, in a shared framework target since nothing is UI-bound. In AppKit, build an `NSMenu` of `NSMenuItem`s with `state` `.on`/`.off` from the selection set. In UIKit, build a `UIMenu` of `UIAction`s with `.displayInline` and `state`, or a `UIButton` with `showsMenuAsPrimaryAction`.
- **WinUI 3**: Port as a `static class PlatformFilter` with `public const string PlatformNone = "__none__";`, `public static HashSet<string> AllPlatformKeys()` returning `new HashSet<string>(Platforms) { PlatformNone }`, and `public static IReadOnlyList<MultiSelectOption> Options(IEnumerable<Endpoint> endpoints)`. `HashSet<T>` does not guarantee enumeration order, so compute unknown values with `endpoints.Select(e => e.Platform ?? PlatformNone).Distinct()` (LINQ `Distinct` yields in first-seen order) and filter with `!Platforms.Contains(k, StringComparer.Ordinal)` to keep exact-case matching. Make `MultiSelectOption` a `record(string Key, string Label)`. In the view model, expose the rows as an `ObservableCollection<MultiSelectOption>` rebuilt when the endpoint list changes, and the selection as a `HashSet<string>` behind a property that raises `INotifyPropertyChanged`; render rows in a `DropDownButton` whose `MenuFlyout` holds `ToggleMenuFlyoutItem`s bound by `IsChecked`, or a `ListView` with `SelectionMode="Multiple"` inside a `Flyout`. No `Task`/`async` is needed; the functions are synchronous.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/platform-filter.ts` |

## Design Decisions

**Decision**: Always offer every known platform, regardless of which endpoints exist.
**Rationale**: The header comment records the regression: a data-driven list hid `railway` whenever no monitored site used it, which is the steady state because railway hosts backends rather than the monitored frontends (pf-001).
**Approved**: pending

**Decision**: Show unknown platform values that are actually present, after the known ones.
**Rationale**: The doc comment calls these "legacy/odd data"; listing them keeps such endpoints filterable without adding them to the canonical list (pf-005).
**Approved**: pending

**Decision**: Show the no-platform row only when some endpoint is unwired, but always include its key in the "all" set.
**Rationale**: The doc comment says the bucket "is meaningful as a filter only when such sites exist", while `allPlatformKeys` includes it so the "all" reset "can never omit one" and an unwired site that appears later is visible by default (pf-003, pf-007).
**Approved**: pending

**Decision**: Use a string sentinel `"__none__"` for the null platform.
**Rationale**: The selection is a `Set<string>`, so `null` needs a string stand-in to be a selectable key; the doc comment says this keeps an unwired site "a selectable filter row rather than being silently dropped from 'all'".
**Approved**: pending

**Decision**: Leave unknown platform keys out of `allPlatformKeys()`.
**Rationale**: `allPlatformKeys` takes no endpoint data, so it can only name the known platforms and the sentinel. The consequence is that endpoints with an unknown platform are hidden under the default selection until selected (pf-014).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |

**Separation of concerns.** The module holds only the option taxonomy and the "all" set. It knows nothing about React, the popover, or how rows are filtered; `EndpointsSection` owns selection state and applies the membership test, and `MultiSelectFilter` owns rendering.

**Unit test coverage.** `platform-filter.test.ts` covers the railway regression, the empty input, the conditional no-platform row, unknown-value ordering, de-duplication of a present known platform, and the contents of `allPlatformKeys`. First-seen order among several unknown values and case-sensitive matching are not asserted by the tests.

**Explicit error handling.** No failure path exists for input that matches the signature; the functions use only set construction, iteration and `includes`, none of which throw on strings or `null`.

**Good test properties.** The tests are deterministic and isolated, with no mocks, clock or I/O, and each `it` block names the single behavior it asserts.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
