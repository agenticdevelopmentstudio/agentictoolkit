---
id: 66cf24b9-04bf-4767-8af9-f82d7e2b5268
title: Deploy View
domain: agentictoolkit://cookbook/status/dashboard/logic/deploy-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure helpers that bucket deploys by platform and correlate a monitored endpoint
  to its deploys by explicit platform and project
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/logic/board-staleness
- agentictoolkit://cookbook/status/dashboard/session-client
references: []
approved-by: ''
approved-date: ''
---

# Deploy View

## Overview

This module is the status dashboard's view-side logic over raw deploy records. It has no state, no I/O and no side effects. It exports:

- a platform summary shape: a per-platform count record (platform, ready, building, failed, total).
- the platform order list: the shared stable ordering of known platforms, `["vercel", "cloudflare-pages", "railway", "crunchy"]`.
- the platform-summary operation: buckets deploys by status per platform. It demotes a stale in-flight deploy to "total only", using the same rule as the activity list and the deploy list. The build-pipeline pane and the KPI building pill call it.
- the endpoint shape: the deploy-target fields of a monitored endpoint (platform, deployProject, environment).
- the endpoint-deploys, latest-terminal-for-endpoint and failures-for-endpoint operations: correlate an endpoint to its deploys by the EXPLICIT (platform, project) wired on the endpoint in config, with "No host guessing." The detail panel and the status matrix call them.
- the deploy-target-key and platform-canonicalization operations: re-exported unchanged from a shared canon module. The source comment says they are "Re-exported (never restated) so the two sides can't key the same deploy differently" — the backend keys deploys with the same function.

The stale-in-flight test is a helper shared with the row model. The [Board Staleness](agentictoolkit://cookbook/status/dashboard/logic/board-staleness) recipe shares its fail-closed clock rule.

## Behavioral Requirements

### Data shapes

- **platform-summary-shape**: the platform summary MUST have exactly the fields `platform` (a text value), `ready`, `building`, `failed` and `total` (each a count).
- **platform-summary-invariant**: For every platform summary returned, `ready + building + failed` MUST be less than or equal to `total`. Every deploy increments `total`, and at most one of the other three.
- **endpoint-like-shape**: the endpoint shape MUST have three optional, nullable fields — `platform`, `deployProject` and `environment` — each either a text value or absent. A structurally wider object (the host's endpoint roster entry) MUST be accepted.
- **platform-order-value**: the platform order list MUST equal `["vercel", "cloudflare-pages", "railway", "crunchy"]`, in that order.
- **platform-order-shared**: the platform order list MUST be exported, so that every platform-grouped surface (the deploy summary, and the auto-configure review view) orders sections from one list.

### Platform-summary operation

- **summarize-signature**: the platform-summary operation MUST take a list of deploy records, the current time (epoch milliseconds), and an optional probe-interval value (milliseconds), and MUST return a list of platform summaries.
- **summarize-group-key**: the platform-summary operation MUST group by each deploy's raw platform field, with no canonicalization. Deploys with `"cloudflare"` and `"cloudflare-pages"` MUST land in two separate summaries.
- **summarize-entry-creation**: The first deploy seen for a platform MUST create an entry with all four counts at 0 before that deploy is counted.
- **summarize-total**: Every deploy MUST increment its platform's `total` exactly once, whatever its status or staleness.
- **summarize-demotion**: A deploy for which the stale-in-flight test, given the deploy, the current time, and the probe interval, returns true MUST count in `total` only, and in none of `ready`, `building` or `failed`.
- **summarize-demotion-rule**: the stale-in-flight test MUST return false for any status other than the in-flight statuses (`building` or `queued`). For an in-flight status it MUST use the deploy's phase-confirmation time, falling back to its creation time when the phase-confirmation time is absent. It MUST return true when neither value is usable (fail closed), and otherwise return true only when the current time exceeds that time by strictly more than the greater of 600000 and five times the probe interval (treating a missing probe interval as zero).
- **summarize-ready**: A non-demoted deploy with status `"success"` MUST increment `ready`.
- **summarize-building**: A non-demoted deploy with status `"building"` or `"queued"` MUST increment `building`.
- **summarize-failed**: A deploy with status `"failed"` MUST increment `failed`.
- **summarize-total-only-statuses**: A deploy with status `"canceled"` or `"unknown"` MUST increment `total` only.
- **summarize-order-known**: The result MUST list the summaries for platforms in the platform order list first, in that order, including only the platforms present.
- **summarize-order-unknown**: Summaries for platforms not in the platform order list MUST follow the known ones, in the order each platform was first seen in the input.
- **summarize-empty**: the platform-summary operation on an empty list MUST return an empty list.

### Endpoint-deploys operation

- **endpoint-deploys-signature**: the endpoint-deploys operation MUST take a list of deploy records and an endpoint, and MUST return a new list of deploy records.
- **endpoint-key**: the endpoint-deploys operation MUST compute the endpoint key using the deploy-target-key operation on the endpoint's platform, project and environment fields.
- **endpoint-no-target**: When the endpoint key is absent (no platform, or no project, as for a health-only check), the endpoint-deploys operation MUST return an empty list.
- **endpoint-match**: A deploy MUST be included exactly when the deploy-target-key operation on its platform, project and environment fields equals the endpoint key.
- **target-key-format**: the deploy-target-key operation MUST return no key when the canonical platform is empty or the project is missing or empty. Otherwise it MUST return `"<canonPlatform>|<project>|<env>"`, where `<env>` is the lowercased environment (or `""` when the environment is absent) for `railway`, and `""` for every other platform.
- **platform-canon-rule**: the platform-canonicalization operation MUST map `"cloudflare-pages"` to `"cloudflare"`, an absent value to `""`, and every other value to itself.
- **endpoint-railway-env**: For a `railway` endpoint, a deploy of the same project in a different environment MUST NOT match. The match on environment MUST be case-insensitive.
- **endpoint-non-railway-env**: For a non-railway endpoint, the environment MUST NOT affect the match, because Vercel and Cloudflare projects are environment-specific.
- **endpoint-cloudflare-alias**: An endpoint configured with platform `"cloudflare"` MUST match deploys whose platform is `"cloudflare-pages"`, and the reverse.
- **endpoint-project-case**: The project name comparison MUST be case-sensitive. Only the environment is lowercased.
- **endpoint-sort**: The result MUST be sorted newest first by the deploy's creation timestamp.
- **endpoint-no-mutation**: the endpoint-deploys operation MUST NOT reorder or modify the caller's input list. It sorts a filtered copy.

### Latest-terminal-for-endpoint operation

- **latest-terminal-signature**: the latest-terminal-for-endpoint operation MUST take a list of deploy records and an endpoint, and MUST return a deploy record or no result.
- **latest-terminal-pick**: it MUST return the first deploy, in the endpoint-deploys operation's order (newest first), whose status is `"success"` or `"failed"`.
- **latest-terminal-skip**: it MUST skip deploys with status `"canceled"`, `"building"`, `"queued"` or `"unknown"`, even when they are newer.
- **latest-terminal-none**: it MUST return no result when no correlated deploy is terminal, and when the endpoint correlates to nothing.
- **latest-terminal-no-demotion**: it MUST NOT apply stale-in-flight demotion. It takes no clock argument.

### Failures-for-endpoint operation

- **failures-signature**: the failures-for-endpoint operation MUST take a list of deploy records and an endpoint, and MUST return a count.
- **failures-count**: it MUST return the count of correlated deploys whose status is exactly `"failed"`, across the whole input with no time window.
- **failures-zero**: it MUST return 0 when nothing correlates.

### Purity and concurrency

- **pure-functions**: Every exported operation MUST be synchronous and MUST NOT perform I/O, log, or mutate its arguments.
- **no-throw**: Every exported operation MUST NOT throw on input of the declared shapes. An unparseable date yields a non-comparable result and is handled by comparison, not by an exception.
- **single-threaded**: The module holds no state, so calls cannot interleave with each other, and no ordering rule between calls is needed.

## Appearance

Not applicable — this is a pure deploy-aggregation and correlation module, not a visual component.

## States

Not applicable — this is a pure deploy-aggregation and correlation module, not a visual component.

## Accessibility

Not applicable — this is a pure deploy-aggregation and correlation module, not a visual component.

## Conformance Test Vectors

Unless stated, every deploy has platform `"vercel"`, project `"test-project"`, environment `"production"`, and creation and phase-confirmation times equal to `NOW = 2026-06-12T12:00:00.000Z`, so nothing is demoted. Vectors 001 to 017 are traced to assertions in the module's own test suite. Vectors 018 to 022 are traced to the source bodies of the platform-summary operation, the stale-in-flight test, and the deploy-target-key operation.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-view-001 | summarize-empty | The platform-summary operation on an empty list | An empty list |
| deploy-view-002 | summarize-demotion, summarize-total | Two vercel `building` deploys; one has a phase-confirmation time 3 600 000 ms before now | `building` 1, `total` 2 |
| deploy-view-003 | summarize-ready, summarize-building, summarize-failed, summarize-total-only-statuses | Vercel deploys with statuses success, building, queued, failed, canceled | One summary: `{ platform: "vercel", ready: 1, building: 2, failed: 1, total: 5 }` |
| deploy-view-004 | summarize-group-key, summarize-entry-creation | vercel success ×2, cloudflare-pages success, railway failed | 3 summaries; vercel `ready` 2; cloudflare-pages `ready` 1, `failed` 0; railway `failed` 1 |
| deploy-view-005 | summarize-order-known | Deploys in the order railway, vercel, cloudflare-pages | Platforms `["vercel", "cloudflare-pages", "railway"]` |
| deploy-view-006 | summarize-order-unknown | vercel, then custom-host | First result's platform is `"vercel"`, second's is `"custom-host"` |
| deploy-view-007 | summarize-total-only-statuses | Two vercel `canceled` | `total` 2; `ready`, `building` and `failed` all 0 |
| deploy-view-008 | latest-terminal-pick, latest-terminal-skip | Endpoint vercel/hub-production; deploys success at 10:00, failed at 11:00, canceled at 12:00, building at 12:30 | Returns the `failed` deploy |
| deploy-view-009 | latest-terminal-none | Same endpoint; only canceled and building deploys | No result |
| deploy-view-010 | endpoint-no-target | Endpoint with no platform or deployProject; one vercel deploy | Empty list |
| deploy-view-011 | endpoint-match, endpoint-non-railway-env | Endpoint vercel/hub-staging (env staging); deploys hub-production, hub-staging, hub-testing | Exactly one, with project name `"hub-staging"` |
| deploy-view-012 | endpoint-railway-env | Endpoint railway/adh-backend, env staging; deploys of adh-backend in production, staging and testing | Exactly one, with environment `"staging"` |
| deploy-view-013 | endpoint-cloudflare-alias | Endpoint platform `"cloudflare"`, project temporal-web; cloudflare-pages deploys temporal-web and temporal-other | Exactly one, with project name `"temporal-web"` |
| deploy-view-014 | endpoint-sort | Endpoint vercel/hub-production; creation times 2024-01-03, 2024-01-01, 2024-01-02 | Order 2024-01-03, 2024-01-02, 2024-01-01 |
| deploy-view-015 | failures-zero | The failures-for-endpoint operation on an empty list with endpoint vercel/"nope" | 0 |
| deploy-view-016 | failures-count | Matching deploys failed, success, failed, building | 2 |
| deploy-view-017 | failures-count | Matching deploys building and canceled | 0 |
| deploy-view-018 | summarize-demotion-rule | One vercel `queued` deploy whose phase-confirmation time is unparseable | `building` 0, `total` 1 (fails closed) |
| deploy-view-019 | summarize-demotion-rule | Vercel `building`, phase-confirmation time 900 000 ms before now; evaluated once with no probe interval and once with a 300 000 ms probe interval | No interval: `building` 0 (900 000 > 600 000). Interval 300 000: `building` 1 (900 000 ≤ 1 500 000) |
| deploy-view-020 | summarize-demotion-rule, summarize-ready | Vercel `success`, phase-confirmation time 3 600 000 ms before now | `ready` 1 (terminal statuses never demote) |
| deploy-view-021 | summarize-group-key | One `"cloudflare"` success and one `"cloudflare-pages"` success | Two summaries: `"cloudflare-pages"` first (known), then `"cloudflare"` (unknown) |
| deploy-view-022 | endpoint-railway-env, target-key-format | Endpoint railway/adh-backend, env `"Staging"`; deploy railway/adh-backend, env `"staging"` | The deploy matches (both sides key to railway, adh-backend, staging) |

## Edge Cases

- **Empty input list**: the platform-summary operation MUST return an empty list, the endpoint-deploys operation MUST return an empty list, the latest-terminal-for-endpoint operation MUST return no result, and the failures-for-endpoint operation MUST return 0.
- **Endpoint with no platform or no project**: the deploy-target-key operation returns no key, so every endpoint helper MUST report no deploys (empty list, no result, 0). This is the documented health-only-check contract, not an error.
- **Empty-string project**: the deploy-target-key operation treats an empty project as missing. The endpoint MUST correlate to nothing, and a deploy with an empty project name MUST never match any endpoint.
- **Railway deploy or endpoint with no environment**: The key's environment segment is `""`. A no-environment railway endpoint MUST match only no-environment railway deploys of that project.
- **Unknown platform name** (for example `"crunchy"` absent from the data, or `"custom-host"` present): the platform-summary operation MUST omit known platforms with no deploys, and MUST place unknown platforms after the known ones in first-seen order.
- **Canonical alias in summaries**: the platform-summary operation does not canonicalize. A `"cloudflare"` platform string MUST produce its own summary, sorted as unknown, apart from `"cloudflare-pages"`. The endpoint helpers, by contrast, MUST treat the two as one platform.
- **Unparseable phase-confirmation or creation time on an in-flight deploy**: the stale-in-flight test MUST fail closed. The deploy MUST count in `total` only.
- **Future phase-confirmation time**: The age is negative, so the deploy MUST NOT be demoted and MUST count as `building`.
- **Exactly at the window**: An age exactly equal to the greater of 600000 and five times the probe interval MUST NOT demote. The comparison is strictly greater than.
- **Missing, zero or negative probe interval**: The demotion window MUST fall back to the 600 000 ms floor.
- **Unparseable creation time in the endpoint-deploys operation**: The comparison yields a value the sort treats as equal. The position of such a deploy MUST be treated as unspecified. Creation time is a typed server-supplied timestamp, so this is a caller precondition, not validated here.
- **Equal creation times**: Sorting MUST be stable, so ties MUST keep their input order.
- **Many failures**: the failures-for-endpoint operation MUST count every failed deploy in the input. It applies no time window and no cap. Bounding the history is the caller's job (the server that fills the deploy list).
- **Concurrent access**: Not applicable. The module is stateless.
- **Error states and offline**: Not applicable. The module performs no I/O. A missing or failed deploy feed reaches it only as an empty or older deploy list. Fetching and error reporting belong to the layer that loads the board.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploys` | a list of deploy records | none (required) | The deploy rows to summarize or correlate, supplied by the board. |
| `nowMs` | a number | none (required) | Client clock in epoch ms, used by the platform-summary operation for stale-in-flight demotion. |
| `probeIntervalMs` | a number, or absent | absent (600 000 ms window) | Backend probe cadence. The demotion window is the greater of 600000 and five times this value. |
| `ep` | an endpoint shape | none (required) | The endpoint's configured platform, deployProject and environment. |
| Platform order list | a constant list | `["vercel", "cloudflare-pages", "railway", "crunchy"]` | Compiled-in section order for known platforms. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. It composes the stale-in-flight test from the row model, and the deploy-target-key and platform-canonicalization operations from a shared canon module.

## Deep Linking

Not applicable: the module exports pure operations and a constant and has no navigable surface.

## Localization

Not applicable: the module returns counts, records and platform identifiers, not user-facing text.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and every helper always applies.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module reads deploy metadata already on the board (platform, project, environment, status, timestamps). It stores and transmits nothing, and handles no token or credential.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum DeployView` namespace over a `Sendable` deploy record struct. The platform summary becomes a `struct` with `var` counts. Use a `[String: PlatformSummary]` plus an insertion-order `[String]` array, because Swift `Dictionary` does not keep insertion order. Parse dates with `ISO8601DateFormatter` (with `.withFractionalSeconds`), and map a `nil` parse to "unconfirmed" to keep the fail-closed rule. Sort with `sorted { $0.createdAt > $1.createdAt }` on parsed `Date` values.
- **Compose**: Use Kotlin top-level functions over a `data class DeploymentDto`. A `LinkedHashMap<String, PlatformSummary>` keeps the first-seen order the source gets from `Map`. `Instant.parse` throws rather than returning an unparseable sentinel, so wrap it in `runCatching` and treat a failure as unconfirmed. Use `sortedByDescending { it.createdAt }` (it is stable) and `firstOrNull { ... }` for the latest terminal deploy.
- **React/Web**: This is the source: `src/lib/deploy-view.ts`, tested by `src/lib/deploy-view.test.ts`. It relies on `deployDtoUnconfirmed` in `src/lib/row-model.ts` and on `IN_FLIGHT_STATUSES` in `src/lib/deploy-status.ts`. The key functions (`deployTargetKey`, `platformCanon`) live in `packages/deploy-platform/src/canon/index.ts`, which the backend (a Hono server) shares. Call sites are `Dashboard.tsx` (`summarizeByPlatform`), `DetailPanel.tsx` (`deploysForEndpoint`), `StatusMatrix.tsx` (latest terminal and failure count) and `AutoConfigureReview.tsx` (`PLATFORM_ORDER`). The code depends on JavaScript `Map` insertion order and on `Array.prototype.sort` being stable and treating a `NaN` comparator result (from an unparseable `Date.parse`) as no swap, which is how an unparseable `createdAt` is tolerated without a special case. The module holds no state and runs on the single JavaScript thread, so calls cannot interleave.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port, in a shared framework target. Nothing here is UI-bound. `NSTableView` or `UITableView` data sources consume the returned arrays directly.
- **WinUI 3**: Port as a `public static class DeployView` over `record DeploymentDto` (deserialized with `System.Text.Json`, with `DeployStatus` as a `[JsonConverter(typeof(JsonStringEnumConverter))]` enum). `PlatformSummary` becomes a `record` or a small class. `Dictionary<string, PlatformSummary>` does not guarantee enumeration order, so keep a separate `List<string>` of first-seen platforms, or use `OrderedDictionary<TKey,TValue>` (.NET 9). Parse dates with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and treat `false` as unconfirmed, since .NET has no NaN parse result. Use LINQ `Where(...).OrderByDescending(d => d.CreatedAt)`, which is stable, and `FirstOrDefault(...)` for the latest terminal deploy. Share `DeployTargetKey` and `PlatformCanon` from one assembly with whatever server code keys deploys, matching the source's single-owner re-export. Lowercase the environment with `ToLowerInvariant()`. The view model binds the summaries to an `ObservableCollection<PlatformSummary>`, and recomputes on a `DispatcherQueueTimer` tick so demotion tracks the clock. The functions stay synchronous, with no `Task`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/deploy-view.ts` |

## Design Decisions

**Decision**: Demote a stale in-flight deploy to "total only" in `summarizeByPlatform`, using the same `deployDtoUnconfirmed` rule as `DeployList` and the activity list.
**Rationale**: Per the doc comment, an in-flight deploy that nothing has re-confirmed is no longer a live "building". Counting it would let the Build-pipeline pane and the KPI building pill assert progress the rest of the board has stopped asserting.
**Approved**: pending

**Decision**: Correlate endpoints to deploys only by the explicit (platform, project) configured on the endpoint, never by host.
**Rationale**: The section comment says "No host guessing." An endpoint with no platform or project wired is a health-only check and correlates to nothing.
**Approved**: pending

**Decision**: Re-export `deployTargetKey` and `platformCanon` from the shared canon package rather than restating them.
**Rationale**: The server keys deploys with `deployTargetKey`. A previous local copy omitted the environment lowercasing, so a Railway endpoint whose stored environment differed in case correlated to nothing in the browser while the server matched it.
**Approved**: pending

**Decision**: Match the environment only for Railway.
**Rationale**: Railway serves every environment from one project. Vercel and Cloudflare projects are environment-specific, so the project alone identifies them.
**Approved**: pending

**Decision**: `latestTerminalForEndpoint` skips canceled and in-flight deploys.
**Rationale**: Per its doc comment, the deploy status shown should reflect the last real outcome, not a canceled or in-flight build on top of it.
**Approved**: pending

**Decision**: `summarizeByPlatform` groups by the raw platform string, while the endpoint helpers canonicalize.
**Rationale**: This is how the source behaves. Summary sections are keyed by the platform string on the deploy row (`"cloudflare-pages"` is the one in `PLATFORM_ORDER`). Correlation has to bridge the config spelling `"cloudflare"`. A port that canonicalizes in the summary would change section keys and ordering.
**Approved**: pending

**Decision**: Export `PLATFORM_ORDER` as the single ordering source.
**Rationale**: Per the source comment, every platform-grouped surface should order sections identically, instead of each keeping its own list.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of concerns.** The module holds only aggregation and correlation rules, with no I/O or rendering. The key derivation is owned by the shared canon package, and the staleness rule by the row model.

**Unit test coverage.** The module's test suite covers every status bucket, stale demotion, platform ordering, the no-target, Vercel, Railway and Cloudflare correlation paths, newest-first sorting, terminal selection and failure counting.

**Explicit error handling.** Unparseable clocks in the demotion path are caught by a finite-value guard that fails closed, not by an exception.

**Data integrity.** A single shared key function keeps client and server correlation in agreement. Every deploy is counted in `total`, so demoted and canceled rows are never lost from the count.

**Graceful degradation.** A missing probe interval falls back to the 600 000 ms floor. An endpoint without a deploy target yields empty results rather than a guess.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
