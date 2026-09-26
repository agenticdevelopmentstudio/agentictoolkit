---
id: 74380f06-a663-44c7-981d-191301a66b8e
title: Platform Filter Options
domain: agentictoolkit://cookbook/status-web/lib/platform-filter
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/status-web/lib/filter
references: []
approved-by: ''
approved-date: ''
---

# Platform Filter Options

## Overview

`platform-filter.ts` (`packages/web/packages/status-web/src/lib/platform-filter.ts`) holds the option taxonomy for the Platform filter in the Sites config list. It exports three things: the sentinel `PLATFORM_NONE` (`"__none__"`), the factory `allPlatformKeys()`, and the pure function `platformFilterOptions(endpoints)`.

The module's header comment names the bug it owns: "a purely data-driven list only showed platforms PRESENT among endpoints, so `railway` vanished from the filter whenever no site was wired to a railway project". The fix is that the known platforms are always offered.

The known platforms come from `PLATFORMS` in `src/api/monitored-sites.ts`, currently `["vercel", "railway", "cloudflare", "crunchy"]` (declared `as const`). Option rows use the `MultiSelectOption` shape (`{ key: string; label: string }`) from `src/components/MultiSelectFilter.tsx`.

The one call site is `EndpointsSection` (`src/components/configure/EndpointsSection.tsx`). It seeds its selection state with `useState(allPlatformKeys)`, resets it with `allPlatformKeys()` or an empty set from its "all" toggle, builds its rows with `useMemo(() => platformFilterOptions(endpoints), [endpoints])`, and keeps an endpoint when `platformFilter.has(e.platform ?? PLATFORM_NONE)`. The module holds no state and does no I/O.

## Behavioral Requirements

- **none-sentinel**: The module MUST export the constant `PLATFORM_NONE` with the value `"__none__"`, used as the filter key for an endpoint whose `platform` is `null`.
- **all-keys-contents**: `allPlatformKeys()` MUST return a `Set<string>` containing every entry of `PLATFORMS` plus `PLATFORM_NONE`, and nothing else.
- **all-keys-fresh-set**: `allPlatformKeys()` MUST return a new `Set` on every call, so a caller that mutates the result does not change the next result.
- **all-keys-ignores-data**: `allPlatformKeys()` MUST take no arguments and MUST include `PLATFORM_NONE` whether or not any endpoint is unwired.
- **options-signature**: `platformFilterOptions` MUST take an array of objects that each carry `platform: string | null` and MUST return a `MultiSelectOption[]`.
- **options-synchronous**: `platformFilterOptions` MUST return its result synchronously and MUST NOT mutate its argument, keep state between calls, or perform I/O.
- **known-platforms-always**: `platformFilterOptions` MUST emit one row for every entry of `PLATFORMS`, even when no endpoint uses that platform or the input array is empty.
- **known-platforms-order**: The known-platform rows MUST come first, in the canonical order of `PLATFORMS`.
- **known-platform-label**: Each known-platform row MUST use the platform string as both `key` and `label` (for example `{ key: "railway", label: "railway" }`), with no capitalization or display-name mapping.
- **known-platform-no-duplicate**: A known platform that is also present among the endpoints MUST appear exactly once.
- **unknown-platforms-appended**: Every non-null `platform` value present among the endpoints that is not in `PLATFORMS` MUST get one row, with the value as both `key` and `label`, placed after all known-platform rows.
- **unknown-platforms-order**: Unknown-platform rows MUST appear in the order their value first occurs in the input array.
- **unknown-platforms-deduplicated**: An unknown value that occurs on several endpoints MUST produce exactly one row.
- **known-match-exact**: Membership in `PLATFORMS` MUST be tested by exact, case-sensitive string equality, so a value such as `"Vercel"` is treated as an unknown platform.
- **none-row-conditional**: `platformFilterOptions` MUST append a row `{ key: "__none__", label: "no platform" }` only when at least one endpoint has `platform === null`.
- **none-row-last**: When the no-platform row is present, it MUST be the final row.
- **null-maps-to-sentinel**: A `null` `platform` MUST be mapped to `PLATFORM_NONE` before de-duplication, and MUST NOT produce an unknown-platform row.
- **no-errors**: `platformFilterOptions` and `allPlatformKeys` MUST NOT throw for input that matches its TypeScript signature; the module has no failure path and returns no error values.
- **selection-contract**: A caller that keeps an endpoint when its selection set contains `e.platform ?? PLATFORM_NONE` MUST see every known platform and every unwired endpoint pass when the selection is `allPlatformKeys()`. An endpoint with an unknown platform is not in `allPlatformKeys()` and so does not pass that default selection.
- **single-threaded**: Both functions MUST run to completion on the calling thread; the module has no asynchronous work and no shared mutable state, so calls cannot interleave.

## Appearance

Not applicable — this is a pure option-taxonomy function, not a visual component.

## States

Not applicable — this is a pure option-taxonomy function, not a visual component.

## Accessibility

Not applicable — this is a pure option-taxonomy function, not a visual component.

## Conformance Test Vectors

Vectors pf-001 to pf-006 are derived from the assertions in `src/lib/platform-filter.test.ts`. The rest trace to `platformFilterOptions` and `allPlatformKeys` directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pf-001 | known-platforms-always, known-platforms-order | `platformFilterOptions([{platform:"vercel"},{platform:"vercel"},{platform:"cloudflare"}])` | keys `["vercel","railway","cloudflare","crunchy"]` (railway present with zero endpoints) |
| pf-002 | known-platforms-always | `platformFilterOptions([])` | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-003 | none-row-conditional | `platformFilterOptions([{platform:"vercel"}])` | no row has key `"__none__"` |
| pf-004 | none-row-conditional, none-row-last, null-maps-to-sentinel | `platformFilterOptions([{platform:"vercel"},{platform:null}])` | last row equals `{ key: "__none__", label: "no platform" }` |
| pf-005 | unknown-platforms-appended, none-row-last | `platformFilterOptions([{platform:"fly"},{platform:null}])` | keys `["vercel","railway","cloudflare","crunchy","fly","__none__"]` |
| pf-006 | known-platform-no-duplicate | `platformFilterOptions([{platform:"railway"},{platform:"railway"}])` | keys `["vercel","railway","cloudflare","crunchy"]` |
| pf-007 | all-keys-contents, all-keys-ignores-data | `allPlatformKeys()` | set equal to `{"vercel","railway","cloudflare","crunchy","__none__"}` |
| pf-008 | known-platform-label | `platformFilterOptions([])[1]` | `{ key: "railway", label: "railway" }` |
| pf-009 | unknown-platforms-order, unknown-platforms-deduplicated | `platformFilterOptions([{platform:"render"},{platform:"fly"},{platform:"render"}])` | keys `["vercel","railway","cloudflare","crunchy","render","fly"]` |
| pf-010 | known-match-exact | `platformFilterOptions([{platform:"Vercel"}])` | keys `["vercel","railway","cloudflare","crunchy","Vercel"]` |
| pf-011 | all-keys-fresh-set | `const a = allPlatformKeys(); a.clear(); allPlatformKeys().size` | `5` |
| pf-012 | none-sentinel | read `PLATFORM_NONE` | `"__none__"` |
| pf-013 | options-synchronous | call `platformFilterOptions(input)` with a frozen input array | returns rows without throwing; input unchanged |
| pf-014 | selection-contract | selection `allPlatformKeys()`; endpoints with platform `"railway"`, `null`, `"fly"` | `railway` and `null` endpoints pass; `fly` endpoint does not |
| pf-015 | no-errors, single-threaded | call both functions with valid input | return a value synchronously (not a promise); nothing thrown |

## Edge Cases

- **Empty endpoint list**: `platformFilterOptions([])` MUST return exactly the four known-platform rows, with no no-platform row (pf-002).
- **All endpoints unwired**: Input where every `platform` is `null` MUST return the four known-platform rows followed by the no-platform row.
- **Empty-string platform**: A `platform` of `""` is not `null` and not in `PLATFORMS`, so it MUST produce an unknown-platform row with `key: ""` and `label: ""`. The source does not reject or relabel it; `EndpointsSection` sets `platform` from the `PLATFORMS` select, which bounds how such a value could arise.
- **Value equal to the sentinel**: An endpoint whose `platform` is the literal string `"__none__"` MUST be treated as unwired: it produces the no-platform row and no unknown-platform row, because the sentinel check does not distinguish it from `null`.
- **Case variants**: `"Vercel"` or `"RAILWAY"` MUST produce separate unknown-platform rows, since matching is case-sensitive (pf-010).
- **Unknown platform under the default selection**: An endpoint with an unknown platform gets a filter row but its key is not in `allPlatformKeys()`. With the default or "all" selection, a caller filtering by set membership MUST hide it until the operator selects that row (pf-014).
- **Missing `platform` field**: A `platform` of `undefined` is excluded by the type signature; at runtime the `??` operator maps it to `PLATFORM_NONE` the same as `null`.
- **Large input**: Work is linear in the number of endpoints plus a scan of `PLATFORMS` per distinct value; there is no size limit and no truncation.
- **Concurrent access**: Not applicable. Both functions are synchronous and stateless, and JavaScript runs them on one thread.
- **Error states and offline**: Not applicable. The module performs no I/O, so there is no dependency to fail and no connectivity to lose.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `endpoints` | `{ platform: string \| null }[]` | required | Monitored endpoints whose `platform` values drive the unknown and no-platform rows. |
| `PLATFORMS` (import) | `readonly ["vercel","railway","cloudflare","crunchy"]` | as declared in `src/api/monitored-sites.ts` | Canonical known-platform list and order; editing it changes both functions. |
| `PLATFORM_NONE` | `string` | `"__none__"` | Sentinel key for an endpoint with no platform. |

No environment variables, settings keys or injected dependencies are read.

## Deep Linking

Not applicable: the module returns option data only and defines no route or URL.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; hardcoded) | `no platform` | Label of the trailing row for endpoints with `platform === null`, returned by `platformFilterOptions`. |

The label `"no platform"` is a hardcoded English literal with no localization lookup. Known and unknown platform rows use the raw platform string as the label, untranslated.

## Accessibility Options

Not applicable: the module renders nothing; `MultiSelectFilter` owns presentation of the rows.

## Feature Flags

Not applicable: neither function reads a flag; the known platforms are always offered unconditionally.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module reads only platform names, collects no data, and stores or transmits nothing.

## Logging

Not applicable: the module has no log calls.

## Platform Notes

- **SwiftUI**: Port as free functions over a `static let platforms = ["vercel", "railway", "cloudflare", "crunchy"]`. Build the present set while preserving first-seen order: Swift `Set` is unordered, so track insertion with an `[String]` plus a `Set<String>` (or `OrderedSet` from swift-collections) to keep **unknown-platforms-order**. Map `nil` with `endpoint.platform ?? platformNone`. Return `[MultiSelectOption]` where the option is a `struct` that is `Identifiable, Hashable, Sendable`, and feed it to a `Menu` of `Toggle`s. Hold the selection as `@State var platformFilter: Set<String> = allPlatformKeys()`.
- **Compose**: Write top-level Kotlin functions. `endpoints.map { it.platform ?: PLATFORM_NONE }.toSet()` returns a `LinkedHashSet`, which keeps first-seen order like the JavaScript `Set`. Use `PLATFORMS.contains(k)` for exact-case matching. Return `List<MultiSelectOption>` of a `data class`. Hold the selection in `remember { mutableStateOf(allPlatformKeys()) }` and derive rows with `remember(endpoints) { platformFilterOptions(endpoints) }`.
- **React/Web**: This is the source: `src/lib/platform-filter.ts`, tested by `src/lib/platform-filter.test.ts` (vitest), and called only from `src/components/configure/EndpointsSection.tsx`. It relies on the JavaScript `Set` keeping insertion order, on `Array.prototype.includes` for exact matching, and on `PLATFORMS` being a `readonly` tuple (hence the `as readonly string[]` cast before `includes`).
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
