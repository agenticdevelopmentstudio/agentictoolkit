---
id: 2d763e2e-ef33-4d49-957e-6b8ced23218e
title: Issue Sources
domain: agentictoolkit://cookbook/status/dashboard/logic/issue-sources
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status dashboard's issue-source vocabulary, its display labels, filter
  order, type guard, and the mirrored stuck-deploy threshold
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/source-filter
- agentictoolkit://cookbook/status/dashboard/logic/board-types
- agentictoolkit://cookbook/status/dashboard/logic/endpoint-kinds
references: []
approved-by: ''
approved-date: ''
---

# Issue Sources

## Overview

This module declares where a status-board row or Problem came from: DNS resolution, the HTTP probe, the GlitchTip error tracker, or one of four deploy providers. Its doc comment explains why `glitchtip` is a separate source: "the other sources answer 'is the thing reachable', it answers 'is the thing THROWING'".

It exports five things:

- the issue-source vocabulary, a closed set of seven source identifiers.
- the source label map, giving display labels for the source filter and badges, one per vocabulary member.
- the source order list, giving the canonical order for the source filter UI.
- the issue-source guard operation, which decides whether a raw platform or source string is a member of the vocabulary.
- the stuck-deploy threshold, the number of milliseconds a build may sit BUILDING before the backend counts it as stuck.

The module is a client-side MIRROR of the server's own issue-sources module: "same union, same labels, same order". The server file also holds the judgment functions that decide whether an HTTP check, a deploy, or a platform stream counts as bad or stuck. The client copies only the vocabulary and the threshold constant. It has no state, no I/O and no side effects.

Consumers in the client: the source-filter state ([Source Filter](agentictoolkit://cookbook/status/dashboard/state/source-filter)) seeds its selection from the source order list; the board types ([Board Types](agentictoolkit://cookbook/status/dashboard/logic/board-types)) type board rows with the issue-source vocabulary; the row-building logic, the activity panel, the overview tab and the global panel read the labels, order and guard.

## Behavioral Requirements

### Issue-source vocabulary

- **source-union**: the issue-source vocabulary MUST be exactly these seven identifiers: `"dns"`, `"http"`, `"glitchtip"`, `"vercel"`, `"cloudflare-pages"`, `"railway"`, `"crunchy"`.
- **source-spelling**: The Cloudflare source MUST be spelled `"cloudflare-pages"`, not `"cloudflare"`. A row whose source is `"cloudflare"` MUST NOT be treated as a member of the vocabulary.
- **source-glitchtip-separate**: `glitchtip` MUST be a distinct member from `http`, so an error-tracker Problem can be open on a site that every probe reports as up. The doc comment calls carrying it here "rather than folding it into `http`" the whole point.

### Source label map

- **label-map-total**: the source label map MUST have exactly one entry for every member of the issue-source vocabulary and no other keys.
- **label-values**: the source label map MUST map `dns` to `"DNS"`, `http` to `"HTTP"`, `glitchtip` to `"GlitchTip"`, `vercel` to `"Vercel"`, `cloudflare-pages` to `"Cloudflare"`, `railway` to `"Railway"` and `crunchy` to `"Crunchy Bridge"`.
- **label-non-empty**: Every value in the source label map MUST be a non-empty string.
- **label-unguarded-index**: Looking up the source label map with an identifier that is not a member of the issue-source vocabulary MUST yield no result. The module does not supply a fallback label; the doc comment warns that such a source "renders `undefined` in the filter and the badge". Callers holding a plain string narrow it with the issue-source guard operation first (the row-building logic falls back to the raw string when the guard fails).

### Source order list

- **order-members**: the source order list MUST contain each member of the issue-source vocabulary exactly once, seven entries in all.
- **order-canonical**: the source order list MUST list the sources in the order `dns`, `http`, `glitchtip`, `vercel`, `cloudflare-pages`, `railway`, `crunchy`. Consumers render filter checkboxes and group lists by filtering this list, so this order is the display order.
- **order-not-mutated**: The module MUST NOT mutate the source order list after it is defined.

### Issue-source guard operation

- **guard-signature**: the issue-source guard operation MUST take one text-value argument and MUST return a true-or-false result indicating whether that value is a member of the issue-source vocabulary.
- **guard-true**: it MUST return true when the argument is exactly equal (strict comparison) to a member of the source order list.
- **guard-false**: it MUST return false for every other string, including the empty string, a member with different casing (`"DNS"`), a member with surrounding whitespace, and the integration spelling `"cloudflare"`.
- **guard-no-normalization**: it MUST NOT trim, lowercase or otherwise normalize its argument before comparing. (The server's separate source-normalization function trims and lowercases, and maps `"cloudflare"` to `"cloudflare-pages"`; this client guard does neither.)
- **guard-no-throw**: it MUST NOT throw for any string argument.
- **guard-order-source**: it MUST decide membership from the source order list, so the guard and the filter order agree by construction.

### Stuck-deploy threshold

- **stuck-threshold-value**: the stuck-deploy threshold MUST equal `1800000` (30 × 60 × 1000, thirty minutes).
- **stuck-threshold-mirror**: the stuck-deploy threshold MUST equal the server's own mirrored threshold, which drives the backend's stuck issues and alerts.
- **stuck-not-client-derived**: The client MUST NOT derive stuck Problems from the stuck-deploy threshold. The doc comment records this as an owner call dated 2026-07-10: an in-flight `building` row is activity, never a Problem. No module in the client reads the constant.
- **queued-never-stuck**: A `queued` deploy MUST NOT count as stuck at any age. The doc comment gives the reason: "a long queue is almost always an INTENTIONAL hold, not a wedge".
- **platform-debounce-server-side**: The client MUST NOT implement the platform-unreachable debounce. The module's closing note says the debounce lives server-side, reaching the board as a `platform-health|<source>` Problem, which the client renders directly with no client-side streak or threshold.

### Mirror contract

- **mirror-union**: The client's issue-source vocabulary MUST contain the same members as the server's.
- **mirror-labels**: The client's source label map MUST hold the same key-to-label pairs as the server's.
- **mirror-order**: The client's source order list MUST list the same members in the same order as the server's.
- **mirror-hand-synced**: The two files restate the vocabulary rather than share it. Both doc comments name the other file; no import, generated code or parity test ties them together. A port MUST keep both sides in step when a source is added.
- **mirror-client-extras**: the issue-source guard operation exists only on the client side. The server file has no equivalent guard.

### Purity and concurrency

- **pure-module**: The module MUST have no side effects on import, MUST perform no I/O, and MUST NOT mutate any of its exports after they are defined.
- **single-threaded**: The module's exports are never mutated after load, so calls cannot interleave and it needs no ordering rule between calls.

## Appearance

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## States

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## Accessibility

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## Conformance Test Vectors

Vector 001 is traced to the assertions in the module's own test suite ("includes dns as a first-class source with a label"). Vector 002 is traced to the row-building logic's test suite (the `cloudflare-pages` source-filter regression). The rest are traced to the module's declarations. Three additional checks — that the vocabulary is closed to unlisted strings, that removing a label from the map is rejected, and that the guard narrows a plain string to the vocabulary type in a typed caller — are compile-time checks specific to the reference implementation's type system; they are recorded in Platform Notes rather than here, since they have no runtime-observable input or output.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| issue-sources-001 | order-members, label-non-empty, label-values | Whether `"dns"` is a member of the source order list; the source label map's `dns` entry; every entry in the source label map | `true`; `"DNS"`; every value non-empty |
| issue-sources-002 | source-spelling, guard-true | The issue-source guard operation on `"cloudflare-pages"`; whether `"cloudflare-pages"` is a member of the source order list | `true`; `true` |
| issue-sources-003 | order-canonical, order-members | Read the source order list | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]`, length 7 |
| issue-sources-004 | label-values, label-map-total | Read every entry of the source label map | Exactly seven pairs: dns/"DNS", http/"HTTP", glitchtip/"GlitchTip", vercel/"Vercel", cloudflare-pages/"Cloudflare", railway/"Railway", crunchy/"Crunchy Bridge" |
| issue-sources-005 | guard-true, guard-order-source | The issue-source guard operation on each member of the source order list | `true` for all seven |
| issue-sources-006 | guard-false, source-spelling | The issue-source guard operation on `"cloudflare"` | `false` |
| issue-sources-007 | guard-false, guard-no-normalization | The issue-source guard operation on `"DNS"`; on `" http"`; on `"http "` | `false` for all three |
| issue-sources-008 | guard-false, guard-no-throw | The issue-source guard operation on `""`; on `"deploy"` | `false`, `false`; no exception |
| issue-sources-010 | label-unguarded-index | Looking up the source label map with `"netlify"` | No result |
| issue-sources-013 | stuck-threshold-value | Read the stuck-deploy threshold | `1800000` |
| issue-sources-014 | mirror-union, mirror-labels, mirror-order, stuck-threshold-mirror | Compare the client's exports with the server's issue-source vocabulary, source label map and stuck-deploy threshold | Equal in order; label maps equal; thresholds equal |
| issue-sources-015 | stuck-not-client-derived | Search the client's source tree for readers of the stuck-deploy threshold outside this module | None found |

## Edge Cases

- **Empty string**: The issue-source guard operation on `""` MUST return `false`. No member is empty.
- **Case and whitespace variants**: `"DNS"`, `"Http"` and `" http"` MUST return `false`. The guard does no normalization, so a caller with untrimmed input has to normalize first.
- **Integration spelling of Cloudflare**: The issue-source guard operation on `"cloudflare"` MUST return `false`. The deploy-integration vocabulary spells the platform `"cloudflare"`, and the board's target keys canonicalise `"cloudflare-pages"` down to `"cloudflare"`. Only the un-canonicalised `"cloudflare-pages"` passes the guard. A companion test elsewhere in the client asserts that an activity row's source arrives as `"cloudflare-pages"` so it survives the source filter's default seed.
- **A source the server emits that the client lacks**: If the server adds a member to its union and the client is not updated, looking up that source in the label map MUST yield no result and the guard operation on it MUST return `false`. Callers that index the label map directly with a value already typed as a vocabulary member (for example the global panel and the activity panel's checkbox label) then render nothing; the row-building logic narrows first and shows the raw string instead. The module's own doc comment states this failure, and the owner of the fix is whoever edits the server union.
- **Unattributed rows**: An activity row with no attributed source falls back to its kind (for example `"deploy"`). The issue-source guard operation MUST return `false` for such a string, and the caller shows it unlabeled.
- **Non-text input at runtime**: A caller that passes an absent value or a non-text value MUST get `false`, because an exact-match comparison does not throw and no member equals a non-text value.
- **Mutation of the source order list**: The list is not protected against in-place modification. A consumer that pushed to or sorted it in place would change the filter order and the guard's answers for every other consumer. No consumer does so; they only derive new lists from it.
- **Long-running builds**: A deploy BUILDING for more than 30 minutes MUST NOT become a client-side Problem. Any stuck verdict arrives from the backend on the board.
- **Null, boundary and error states**: There are no numeric inputs and no I/O. The only numeric export is the fixed stuck-deploy threshold. The module cannot fail at runtime.
- **Concurrent access**: Not applicable. The exports are never mutated.
- **Offline or disconnected**: Not applicable. The module performs no network access.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Source order list | a list of issue-source identifiers | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]` | Compiled-in vocabulary and filter order. Changing it means editing this file and the server mirror. |
| Source label map | a map of issue-source identifiers to text labels | the seven labels listed under label-values | Compiled-in display labels. |
| Stuck-deploy threshold | a number | `1800000` | Compiled-in mirror of the server's stuck-build threshold. |
| the issue-source guard operation's argument | a text value | none (required) | The candidate source or platform string to test. |

The module reads no environment variables and no settings keys, imports nothing, and takes no injected dependencies.

## Deep Linking

Not applicable: the module exports constants, a vocabulary and a pure guard, and has no navigable surface.

## Localization

The labels are hardcoded English (brand and protocol names) with no localization keys. They are shown in the source filter and on badges.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| Source label map: dns | DNS | Source filter checkbox and badge for DNS-resolution rows |
| Source label map: http | HTTP | Source filter checkbox and badge for HTTP-probe rows |
| Source label map: glitchtip | GlitchTip | Source filter checkbox and badge for error-tracker rows |
| Source label map: vercel | Vercel | Source filter checkbox and badge for Vercel deploy rows |
| Source label map: cloudflare-pages | Cloudflare | Source filter checkbox and badge for Cloudflare Pages deploy rows |
| Source label map: railway | Railway | Source filter checkbox and badge for Railway deploy rows |
| Source label map: crunchy | Crunchy Bridge | Source filter checkbox and badge for Crunchy Bridge database rows |

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and every source is always in the vocabulary.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only fixed source identifiers and labels. It stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls, and the guard reports its answer only as its return value.

## Platform Notes

- **SwiftUI**: Port the union as `enum IssueSource: String, CaseIterable, Codable, Sendable` with cases `dns`, `http`, `glitchtip`, `vercel`, `cloudflarePages = "cloudflare-pages"`, `railway`, `crunchy`, declared in canonical order so `allCases` replaces the source order list. Put the label on the enum as a `var label: String` computed with an exhaustive `switch`, so a new case fails to compile until it has a label — this is Swift's equivalent of the source's compile-time label-coverage guarantee. `IssueSource(rawValue:)` replaces the guard operation, returning `nil` instead of `false`, case-sensitive like the source. Declare `static let stuckDeployInterval: Duration = .seconds(1800)`.
- **Compose**: Use `enum class IssueSource(val wire: String, val label: String)` with `entries` for the ordered list, and implement the guard as `IssueSource.entries.firstOrNull { it.wire == s }`. Do not use `enumValueOf` as the guard; it throws on a miss and matches the Kotlin constant name, not the wire string. With kotlinx.serialization, annotate `CLOUDFLARE_PAGES` with `@SerialName("cloudflare-pages")`. Declare `const val STUCK_DEPLOY_MS = 30 * 60 * 1000L`.
- **React/Web**: This is the source: `src/lib/issue-sources.ts`, with its test in `src/lib/issue-sources.test.ts`. `IssueSource` is a string-literal union type, written by hand rather than derived from the order array (`ISSUE_SOURCES: IssueSource[]`), so the label map's `Record<IssueSource, string>` type makes a missing key a compile-time type error and guarantees label coverage, but nothing in the type system ties the order array's membership to the union — a member missing from `ISSUE_SOURCES` would still compile, and the array is typed as a mutable `IssueSource[]`, not a readonly tuple. `isIssueSource(s)`'s return type is `boolean`, but TypeScript also treats it as the narrowing predicate `s is IssueSource`, so a caller who guards a plain `string` with it gets that string narrowed to `IssueSource` inside the branch (a caller-visible effect only in the type checker, not at runtime). The compile-time checks omitted from the Conformance Test Vectors table — the closed union rejecting `"cloudflare"`, the label map rejecting a literal missing the `crunchy` key, and the guard's narrowing effect — are exactly these three TypeScript-specific guarantees. The guard's true/false decision is a strict-equality scan of `ISSUE_SOURCES`, equivalent to `Array.prototype.includes`. The `as readonly string[]` cast widens the array so `includes` accepts any string. The server twin is `status-server/src/monitor/issue-sources.ts`, which adds the judgment functions (`httpIsBad`, `deployIsBad`, `deployIsStuck`, `nextPlatformStreak` and others) and a separate `platformHealthSource` normalizer, and whose `applyPlatformIssues` function and `platform_health_state` table own the platform-unreachable debounce. The module holds no state and runs on the single JavaScript thread, so calls cannot interleave.
- **AppKit / UIKit**: Use the same Swift enum as the SwiftUI port, in a shared framework target since nothing is UI-bound. Build the source filter from `IssueSource.allCases` as `NSButton` checkboxes or `UIMenu` toggle actions, using `label` for the title.
- **WinUI 3**: Port as a C# `public enum IssueSource { Dns, Http, GlitchTip, Vercel, CloudflarePages, Railway, Crunchy }`, declared in canonical order so `Enum.GetValues<IssueSource>()` replaces the source order list. `System.Text.Json` needs explicit wire names: put `[JsonStringEnumMemberName("cloudflare-pages")]` (and the lowercase names) on each member with a `JsonStringEnumConverter`, or keep a `static readonly IReadOnlyList<string> Wire` and translate by hand. Keep labels in a `static readonly FrozenDictionary<IssueSource, string> Labels`, or in a `switch` expression that the compiler's exhaustiveness warning covers. The guard becomes `static bool TryParse(string s, out IssueSource source)` that compares wire strings with `StringComparison.Ordinal`; do not use `Enum.TryParse` with `ignoreCase`, which would accept `"DNS"`. For the filter UI, bind an `ItemsRepeater` or `ListView` of `CheckBox` items to `Enum.GetValues<IssueSource>()`, with `Content` bound to the label; the list is immutable, so no `ObservableCollection` is needed. Declare `public static readonly TimeSpan StuckDeploy = TimeSpan.FromMinutes(30);`. Everything is synchronous, with no `Task`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/issue-sources.ts` |

## Design Decisions

**Decision**: Mirror the server's vocabulary by hand instead of sharing a module.
**Rationale**: Both files' doc comments name each other and promise "same union, same labels, same order". The client indexes `SOURCE_LABEL[row.source]`, so agreement is what keeps labels from rendering `undefined`. No shared package, generator or parity test exists, so agreement rests on editing both files together.
**Approved**: pending

**Decision**: Keep `glitchtip` as its own source rather than folding it into `http`.
**Rationale**: The doc comment says the other sources answer reachability while GlitchTip answers whether the site is throwing, and a site can be up on every probe with an error Problem open.
**Approved**: pending

**Decision**: Keep `STUCK_DEPLOY_MS` on the client even though no client code derives stuck Problems from it.
**Rationale**: The doc comment calls it a "mirror of the server threshold" and records the owner call of 2026-07-10 that an in-flight `building` row is activity, never a Problem. The constant stays as documentation of the backend's rule; the stuck verdict itself comes from the server.
**Approved**: pending

**Decision**: Add `isIssueSource` on the client only.
**Rationale**: Its doc comment says it lets a caller "filter/index by it without an unchecked `as IssueSource` cast". `row-model.ts` explains that `Row.source` is a plain string that can fall back to an activity `kind`, and the guard turns the fallback into a real branch.
**Approved**: pending

**Decision**: The platform-unreachable debounce stays out of this module.
**Rationale**: The closing note says the server's `applyPlatformIssues` and the `platform_health_state` table own the streak and threshold and publish a `platform-health|<source>` Problem, which the client renders as given.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

**Separation of concerns.** The module holds only the vocabulary, labels, guard and one mirrored constant. Judging problems (bad HTTP states, failed and stuck deploys, platform streaks) stays in the server file, and the client renders the server's verdicts.

**Unit test coverage.** The module's own test checks that `dns` is present with the label `"DNS"` and that every source has a label. The row-building logic's test checks the guard on `"cloudflare-pages"` and the source filter's default seed. No test covers the full order, the guard's rejection cases, the stuck-deploy threshold, or parity with the server file.

**Explicit error handling.** The guard returns `false` for any non-member rather than throwing, and its predicate type makes callers branch on the result.

**Data integrity.** The label map's type guarantees every union member has a label in the reference implementation. Nothing ties the order list to the vocabulary, and nothing checks the client against the server mirror, so a source added on one side only reaches the screen as an empty label.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
