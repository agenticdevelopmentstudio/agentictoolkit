---
id: 2d763e2e-ef33-4d49-957e-6b8ced23218e
title: Issue Sources
domain: agentictoolkit://recipes/status-web-src-lib-issue-sources
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- agentictoolkit://recipes/status-web-hooks-use-source-filter
- agentictoolkit://recipes/status-web-src-lib-board-types
- agentictoolkit://recipes/status-web-src-lib-endpoint-kinds
references: []
approved-by: ''
approved-date: ''
---

# Issue Sources

## Overview

`issue-sources.ts` (`packages/web/packages/status-web/src/lib/issue-sources.ts`) declares where a status-board row or Problem came from: DNS resolution, the HTTP probe, the GlitchTip error tracker, or one of four deploy providers. Its doc comment explains why `glitchtip` is a separate source: "the other sources answer 'is the thing reachable', it answers 'is the thing THROWING'".

It exports five things:

- `IssueSource`, a string-literal union of the seven source identifiers.
- `SOURCE_LABEL`, a `Record<IssueSource, string>` of display labels for the source filter and badges.
- `ISSUE_SOURCES`, an `IssueSource[]` giving the canonical order for the source filter UI.
- `isIssueSource(s)`, a type guard that narrows a raw platform or source string to `IssueSource`.
- `STUCK_DEPLOY_MS`, the number of milliseconds a build may sit BUILDING before the backend counts it as stuck.

The module is a client-side MIRROR of `status-server/src/monitor/issue-sources.ts`: "same union, same labels, same order". The server file also holds the judgment functions (`httpIsBad`, `deployIsBad`, `deployIsStuck`, `nextPlatformStreak` and others). The client copies only the vocabulary and the threshold constant. It has no state, no I/O and no side effects.

Consumers in status-web: `hooks/use-source-filter.ts` seeds its selection from `ISSUE_SOURCES` ([useSourceFilter](agentictoolkit://recipes/status-web-hooks-use-source-filter)); `lib/board-types.ts` types board rows with `IssueSource` ([Board Types](agentictoolkit://recipes/status-web-src-lib-board-types)); `lib/row-model.ts`, `components/ActivityPanel.tsx`, `components/OverviewTab.tsx` and `components/GlobalPanel.tsx` read the labels, order and guard.

## Behavioral Requirements

### IssueSource

- **source-union**: `IssueSource` MUST be exactly the union `"dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy"`.
- **source-spelling**: The Cloudflare source MUST be spelled `"cloudflare-pages"`, not `"cloudflare"`. A row whose source is `"cloudflare"` is not an `IssueSource`.
- **source-glitchtip-separate**: `glitchtip` MUST be a distinct member from `http`, so an error-tracker Problem can be open on a site that every probe reports as up. The doc comment calls carrying it here "rather than folding it into `http`" the whole point.

### SOURCE_LABEL

- **label-map-total**: `SOURCE_LABEL` MUST have exactly one entry for every `IssueSource` member and no other keys. Its `Record<IssueSource, string>` type makes a missing key a type error.
- **label-values**: `SOURCE_LABEL` MUST map `dns` to `"DNS"`, `http` to `"HTTP"`, `glitchtip` to `"GlitchTip"`, `vercel` to `"Vercel"`, `cloudflare-pages` to `"Cloudflare"`, `railway` to `"Railway"` and `crunchy` to `"Crunchy Bridge"`.
- **label-non-empty**: Every value in `SOURCE_LABEL` MUST be a non-empty string.
- **label-unguarded-index**: Indexing `SOURCE_LABEL` with a string that is not an `IssueSource` MUST yield `undefined` at runtime. The module does not supply a fallback label; the doc comment warns that such a source "renders `undefined` in the filter and the badge". Callers holding a plain string narrow it with `isIssueSource` first (`row-model.ts` falls back to the raw string when the guard fails).

### ISSUE_SOURCES

- **order-members**: `ISSUE_SOURCES` MUST contain each `IssueSource` member exactly once, seven entries in all.
- **order-canonical**: `ISSUE_SOURCES` MUST list the sources in the order `dns`, `http`, `glitchtip`, `vercel`, `cloudflare-pages`, `railway`, `crunchy`. Consumers render filter checkboxes and group lists by filtering this array, so this order is the display order.
- **order-mutable-type**: `ISSUE_SOURCES` MUST be typed `IssueSource[]`, a mutable array, not a readonly tuple. The module never mutates it. Nothing in the type system ties its members to the union, so a member missing from `ISSUE_SOURCES` would still compile.

### isIssueSource

- **guard-signature**: `isIssueSource` MUST take one argument `s: string` and MUST return a `boolean` that the type system treats as the predicate `s is IssueSource`.
- **guard-true**: `isIssueSource` MUST return `true` when `s` is exactly equal (strict comparison, as `Array.prototype.includes` does for strings) to a member of `ISSUE_SOURCES`.
- **guard-false**: `isIssueSource` MUST return `false` for every other string, including the empty string, a member with different casing (`"DNS"`), a member with surrounding whitespace, and the integration spelling `"cloudflare"`.
- **guard-no-normalization**: `isIssueSource` MUST NOT trim, lowercase or otherwise normalize `s` before comparing. (The server's separate `platformHealthSource` trims and lowercases, and maps `"cloudflare"` to `"cloudflare-pages"`; this client guard does neither.)
- **guard-no-throw**: `isIssueSource` MUST NOT throw for any string argument.
- **guard-order-source**: `isIssueSource` MUST decide membership from `ISSUE_SOURCES`, so the guard and the filter order agree by construction.

### STUCK_DEPLOY_MS

- **stuck-threshold-value**: `STUCK_DEPLOY_MS` MUST equal `1800000` (30 × 60 × 1000, thirty minutes).
- **stuck-threshold-mirror**: `STUCK_DEPLOY_MS` MUST equal the server's `STUCK_DEPLOY_MS` in `status-server/src/monitor/issue-sources.ts`, which drives the backend's stuck issues and alerts.
- **stuck-not-client-derived**: The client MUST NOT derive stuck Problems from `STUCK_DEPLOY_MS`. The doc comment records this as an owner call dated 2026-07-10: an in-flight `building` row is activity, never a Problem. No module in status-web reads the constant.
- **queued-never-stuck**: A `queued` deploy MUST NOT count as stuck at any age. The doc comment gives the reason: "a long queue is almost always an INTENTIONAL hold, not a wedge".
- **platform-debounce-server-side**: The client MUST NOT implement the platform-unreachable debounce. The module's closing note says the debounce lives server-side (`applyPlatformIssues` and the `platform_health_state` table) and reaches the board as a `platform-health|<source>` Problem, which the client renders directly with no client-side streak or threshold.

### Mirror contract

- **mirror-union**: The client `IssueSource` union MUST contain the same members as the server's `IssueSource`.
- **mirror-labels**: The client `SOURCE_LABEL` MUST hold the same key-to-label pairs as the server's `SOURCE_LABEL`.
- **mirror-order**: The client `ISSUE_SOURCES` MUST list the same members in the same order as the server's `ISSUE_SOURCES`.
- **mirror-hand-synced**: The two files restate the vocabulary rather than share it. Both doc comments name the other file; no import, generated code or parity test ties them together. A port MUST keep both sides in step when a source is added.
- **mirror-client-extras**: `isIssueSource` exists only on the client side. The server file has no equivalent guard.

### Purity and concurrency

- **pure-module**: The module MUST have no side effects on import and MUST perform no I/O.
- **single-threaded**: The module runs on the single JavaScript thread and never mutates its exports, so calls cannot interleave and it needs no ordering rule.

## Appearance

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## States

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## Accessibility

Not applicable — this is a constant vocabulary and type-guard module, not a visual component.

## Conformance Test Vectors

Vector 001 is traced to the assertions in `issue-sources.test.ts` ("includes dns as a first-class source with a label"). Vector 002 is traced to `row-model.test.ts` (the `cloudflare-pages` source-filter regression). The rest are traced to the declarations in `issue-sources.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| issue-sources-001 | order-members, label-non-empty, label-values | `ISSUE_SOURCES.includes("dns")`; `SOURCE_LABEL.dns`; `SOURCE_LABEL[s]` for each s in `ISSUE_SOURCES` | `true`; `"DNS"`; every value truthy |
| issue-sources-002 | source-spelling, guard-true | `isIssueSource("cloudflare-pages")`; `new Set(ISSUE_SOURCES).has("cloudflare-pages")` | `true`; `true` |
| issue-sources-003 | order-canonical, order-members | Read `ISSUE_SOURCES` | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]`, length 7 |
| issue-sources-004 | label-values, label-map-total | `Object.entries(SOURCE_LABEL)` | Exactly seven pairs: dns/"DNS", http/"HTTP", glitchtip/"GlitchTip", vercel/"Vercel", cloudflare-pages/"Cloudflare", railway/"Railway", crunchy/"Crunchy Bridge" |
| issue-sources-005 | guard-true, guard-order-source | `isIssueSource(s)` for each s in `ISSUE_SOURCES` | `true` for all seven |
| issue-sources-006 | guard-false, source-spelling | `isIssueSource("cloudflare")` | `false` |
| issue-sources-007 | guard-false, guard-no-normalization | `isIssueSource("DNS")`; `isIssueSource(" http")`; `isIssueSource("http ")` | `false` for all three |
| issue-sources-008 | guard-false, guard-no-throw | `isIssueSource("")`; `isIssueSource("deploy")` | `false`, `false`; no exception |
| issue-sources-009 | guard-signature | In a typed context, `const s: string = "railway"; if (isIssueSource(s)) { const k: IssueSource = s; }` | Compiles; `s` is narrowed to `IssueSource` inside the branch |
| issue-sources-010 | label-unguarded-index | `(SOURCE_LABEL as Record<string, string>)["netlify"]` | `undefined` |
| issue-sources-011 | label-map-total | Type-check a `SOURCE_LABEL` literal with the `crunchy` key removed | Type error: property `crunchy` is missing |
| issue-sources-012 | source-union | Type-check `const k: IssueSource = "cloudflare"` | Type error; `"cloudflare"` is not assignable to `IssueSource` |
| issue-sources-013 | stuck-threshold-value | Read `STUCK_DEPLOY_MS` | `1800000` |
| issue-sources-014 | mirror-union, mirror-labels, mirror-order, stuck-threshold-mirror | Compare the client exports with the server's `ISSUE_SOURCES`, `SOURCE_LABEL` and `STUCK_DEPLOY_MS` | Arrays deep-equal in order; label maps deep-equal; thresholds equal |
| issue-sources-015 | stuck-not-client-derived | Search status-web sources for readers of `STUCK_DEPLOY_MS` outside `issue-sources.ts` | None found |

## Edge Cases

- **Empty string**: `isIssueSource("")` MUST return `false`. No member is empty.
- **Case and whitespace variants**: `"DNS"`, `"Http"` and `" http"` MUST return `false`. The guard does no normalization, so a caller with untrimmed input has to normalize first.
- **Integration spelling of Cloudflare**: `isIssueSource("cloudflare")` MUST return `false`. The deploy-integration vocabulary spells the platform `"cloudflare"`, and the board's target keys canonicalise `"cloudflare-pages"` down to `"cloudflare"`. Only the un-canonicalised `"cloudflare-pages"` passes the guard. `row-model.test.ts` asserts that an activity row's source arrives as `"cloudflare-pages"` so it survives the source filter's default seed.
- **A source the server emits that the client lacks**: If the server adds a member to its union and the client is not updated, `SOURCE_LABEL[x]` MUST yield `undefined` and `isIssueSource(x)` MUST return `false`. Callers that index `SOURCE_LABEL` directly with a value typed `IssueSource` (for example `GlobalPanel.tsx` and the `ActivityPanel.tsx` checkbox label) then render `undefined`; `row-model.ts` narrows first and shows the raw string instead. The module's own doc comment states this failure, and the owner of the fix is whoever edits the server union.
- **Unattributed rows**: An activity row with no attributed source falls back to its `kind` (for example `"deploy"`), per the comment in `row-model.ts`. `isIssueSource` MUST return `false` for such a string, and the caller shows it unlabeled.
- **Non-string input at runtime**: The signature takes `string`. A JavaScript caller that passes `undefined`, `null` or a number MUST get `false`, because `Array.prototype.includes` does not throw and no member equals a non-string.
- **Mutation of ISSUE_SOURCES**: The array is typed mutable. A consumer that pushed to or sorted it in place would change the filter order and the guard's answers for every other consumer. No consumer in status-web does so; they only call `filter` and `includes`, which return new values.
- **Long-running builds**: A deploy BUILDING for more than 30 minutes MUST NOT become a client-side Problem. Any stuck verdict arrives from the backend on the board.
- **Null, boundary and error states**: There are no numeric inputs and no I/O. The only numeric export is the fixed constant `STUCK_DEPLOY_MS`. The module cannot fail at runtime.
- **Concurrent access**: Not applicable. The exports are never mutated and JavaScript runs them on one thread.
- **Offline or disconnected**: Not applicable. The module performs no network access.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ISSUE_SOURCES` | `IssueSource[]` | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]` | Compiled-in vocabulary and filter order. Changing it means editing this file and the server mirror. |
| `SOURCE_LABEL` | `Record<IssueSource, string>` | the seven labels listed under label-values | Compiled-in display labels. |
| `STUCK_DEPLOY_MS` | `number` | `1800000` | Compiled-in mirror of the server's stuck-build threshold. |
| `s` (argument to `isIssueSource`) | `string` | none (required) | The candidate source or platform string to test. |

The module reads no environment variables and no settings keys, imports nothing, and takes no injected dependencies.

## Deep Linking

Not applicable: the module exports constants, a type and a pure function, and has no navigable surface.

## Localization

The labels are hardcoded English (brand and protocol names) with no localization keys. They are shown in the source filter and on badges.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `SOURCE_LABEL.dns` | DNS | Source filter checkbox and badge for DNS-resolution rows |
| `SOURCE_LABEL.http` | HTTP | Source filter checkbox and badge for HTTP-probe rows |
| `SOURCE_LABEL.glitchtip` | GlitchTip | Source filter checkbox and badge for error-tracker rows |
| `SOURCE_LABEL.vercel` | Vercel | Source filter checkbox and badge for Vercel deploy rows |
| `SOURCE_LABEL.cloudflare-pages` | Cloudflare | Source filter checkbox and badge for Cloudflare Pages deploy rows |
| `SOURCE_LABEL.railway` | Railway | Source filter checkbox and badge for Railway deploy rows |
| `SOURCE_LABEL.crunchy` | Crunchy Bridge | Source filter checkbox and badge for Crunchy Bridge database rows |

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and every source is always in the vocabulary.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only fixed source identifiers and labels. It stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls, and `isIssueSource` reports its answer only as its return value.

## Platform Notes

- **SwiftUI**: Port the union as `enum IssueSource: String, CaseIterable, Codable, Sendable` with cases `dns`, `http`, `glitchtip`, `vercel`, `cloudflarePages = "cloudflare-pages"`, `railway`, `crunchy`, declared in canonical order so `allCases` replaces `ISSUE_SOURCES`. Put the label on the enum as a `var label: String` computed with an exhaustive `switch`, so a new case fails to compile until it has a label. `IssueSource(rawValue:)` replaces `isIssueSource`, returning `nil` instead of `false`, case-sensitive like the source. Declare `static let stuckDeployInterval: Duration = .seconds(1800)`.
- **Compose**: Use `enum class IssueSource(val wire: String, val label: String)` with `entries` for the ordered list, and implement the guard as `IssueSource.entries.firstOrNull { it.wire == s }`. Do not use `enumValueOf` as the guard; it throws on a miss and matches the Kotlin constant name, not the wire string. With kotlinx.serialization, annotate `CLOUDFLARE_PAGES` with `@SerialName("cloudflare-pages")`. Declare `const val STUCK_DEPLOY_MS = 30 * 60 * 1000L`.
- **React/Web**: This is the source: `src/lib/issue-sources.ts`, with its test in `src/lib/issue-sources.test.ts`. The union is written by hand rather than derived from `ISSUE_SOURCES`, so the `Record<IssueSource, string>` type guarantees label coverage but nothing guarantees the order array is complete. The `as readonly string[]` cast widens the array so `includes` accepts any string. The server twin is `status-server/src/monitor/issue-sources.ts`, which adds the judgment functions and `platformHealthSource`.
- **AppKit / UIKit**: Use the same Swift enum as the SwiftUI port, in a shared framework target since nothing is UI-bound. Build the source filter from `IssueSource.allCases` as `NSButton` checkboxes or `UIMenu` toggle actions, using `label` for the title.
- **WinUI 3**: Port as a C# `public enum IssueSource { Dns, Http, GlitchTip, Vercel, CloudflarePages, Railway, Crunchy }`, declared in canonical order so `Enum.GetValues<IssueSource>()` replaces `ISSUE_SOURCES`. `System.Text.Json` needs explicit wire names: put `[JsonStringEnumMemberName("cloudflare-pages")]` (and the lowercase names) on each member with a `JsonStringEnumConverter`, or keep a `static readonly IReadOnlyList<string> Wire` and translate by hand. Keep labels in a `static readonly FrozenDictionary<IssueSource, string> Labels`, or in a `switch` expression that the compiler's exhaustiveness warning covers. The guard becomes `static bool TryParse(string s, out IssueSource source)` that compares wire strings with `StringComparison.Ordinal`; do not use `Enum.TryParse` with `ignoreCase`, which would accept `"DNS"`. For the filter UI, bind an `ItemsRepeater` or `ListView` of `CheckBox` items to `Enum.GetValues<IssueSource>()`, with `Content` bound to the label; the list is immutable, so no `ObservableCollection` is needed. Declare `public static readonly TimeSpan StuckDeploy = TimeSpan.FromMinutes(30);`. Everything is synchronous, with no `Task`.

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

**Unit test coverage.** `issue-sources.test.ts` checks that `dns` is present with the label `"DNS"` and that every source has a label. `row-model.test.ts` checks `isIssueSource("cloudflare-pages")` and the source filter's default seed. No test covers the full order, the guard's rejection cases, `STUCK_DEPLOY_MS`, or parity with the server file.

**Explicit error handling.** The guard returns `false` for any non-member rather than throwing, and its predicate type makes callers branch on the result.

**Data integrity.** `Record<IssueSource, string>` guarantees every union member has a label. Nothing ties `ISSUE_SOURCES` to the union, and nothing checks the client against the server mirror, so a source added on one side only reaches the screen as an `undefined` label.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from source |
