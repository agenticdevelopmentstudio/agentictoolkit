---
id: a076f315-885d-45df-998d-68703a319ec8
title: Build Progress
domain: agentictoolkit://cookbook/status/dashboard/state/build-progress
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Derives progress over the current build cohort from server-toned activity
  rows, holding 100% for 2 seconds before resetting.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/activity-ttl
references: []
approved-by: ''
approved-date: ''
---

# Build Progress

## Overview

This logic computes progress over the current build "cohort" — the set of builds seen in flight since the last all-idle moment. A build joins the cohort while the board reports it in flight (a row with `kind === "deploy"`, `step === "build"` and `tone === "progress"`) and counts as completed once the board stops saying so: the row settles, the server expires it to `"stale"`, or it drops out of the feed. This logic has no clock of its own for judging a build; the only timer it runs is the 2-second hold at 100% after every cohort build is done, after which the cohort resets and the bar hides.

The caller passes its env-filtered activity, so a filtered-out environment's build does not count; the value drives the build-progress bar view. This logic reads nothing but its argument and performs no I/O.

## Behavioral Requirements

- **signature**: This logic MUST accept one argument, the activity rows, and return a build-progress result on every evaluation.
- **return-shape**: The build-progress result MUST carry exactly five fields: `visible` (boolean), `completed` (number), `total` (number), `pct` (number), `complete` (boolean).
- **in-flight-predicate**: A row MUST be treated as an in-flight build if and only if `kind === "deploy"` AND `step === "build"` AND `tone === "progress"`.
- **deploy-step-excluded**: A row with `step === "deploy"` MUST NOT enter the cohort, whatever its tone.
- **non-deploy-kind-excluded**: A row whose `kind` is `"probe"` or `"platform"` MUST NOT enter the cohort, whatever its tone or step.
- **no-client-clock**: The in-flight predicate MUST NOT consult the row's `at` timestamp or any wall-clock time; a build the board still tones `"progress"` MUST remain in flight regardless of its age.
- **identity-by-id**: Cohort membership MUST be keyed by the row's `id` field; rows sharing an `id` MUST count as one build.
- **cohort-accumulation**: Every `id` observed in flight MUST be added to the cohort and MUST stay in it until the cohort resets, even after its row leaves the feed.
- **cohort-no-op-when-idle**: When the current snapshot contains no in-flight builds, the accumulation step MUST NOT modify the cohort.
- **cohort-stable-identity**: When every in-flight `id` is already in the cohort, the accumulation step MUST keep the existing cohort set instead of storing a new one, so no unnecessary change notification is triggered.
- **accumulation-trigger**: Accumulation MUST re-run only when the sorted, `|`-joined list of in-flight ids changes between evaluations (see Platform Notes).
- **total-definition**: `total` MUST equal the number of distinct ids in the cohort.
- **completed-definition**: `completed` MUST equal the number of cohort ids not in flight in the current activity snapshot, counting settled, server-expired (`"stale"`) and absent rows alike.
- **pct-definition**: `pct` MUST be `0` when `total` is `0`, and otherwise the nearest integer to `(completed / total) * 100`, an integer from 0 to 100 (see Platform Notes).
- **visible-definition**: `visible` MUST be `true` exactly when `total > 0`.
- **complete-definition**: `complete` MUST be `true` exactly when `total > 0` and `completed === total`.
- **complete-hold**: When `complete` becomes `true`, this logic MUST schedule a single timer of 2000 ms that clears the cohort to an empty set.
- **hold-visible**: During the 2000 ms hold this logic MUST keep returning `visible: true`, `pct: 100`, `complete: true`.
- **hold-cancel**: If `complete` becomes `false` before the timer fires (a new build enters the cohort, or a cohort build is toned `"progress"` again), the pending timer MUST be cleared and the cohort MUST NOT be reset.
- **reset-effect**: After the timer fires, this logic MUST return `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false` until another in-flight build is observed.
- **unmount-cleanup**: Teardown while a hold timer is pending MUST clear that timer.
- **one-render-lag**: A build first observed in flight MUST be absent from `total` in the evaluation that first observes it, and MUST appear only after the accumulation step commits and the result is recomputed; the cohort is updated as a side effect rather than derived synchronously during that first evaluation (see Platform Notes).
- **input-not-mutated**: This logic MUST NOT mutate the given activity rows or their contents.
- **no-side-effects**: This logic MUST perform no network, storage, logging or UI side effects; its only side effect is the hold timer.
- **caller-filters**: This logic MUST track exactly the rows it is given; filtering by environment is the caller's responsibility, and display-only narrowing (ttl, clear, search) MUST NOT be applied to its input.
- **server-owns-demotion**: This logic MUST NOT demote an in-flight build itself; expiry of a wedged build is owned by the server (`reconcile-stuck-deploys` sets tone to `"stale"`, `deployIsStuck` raises a Problem), and until that happens the bar stays visible below 100%.
- **client-only**: This logic MUST run in a runtime context that supports local state and timers (see Platform Notes).
- **threading**: All reads and state updates MUST run without concurrent execution; no two evaluations of this logic interleave, so cohort updates are ordered by evaluation order (see Platform Notes).

## Appearance

Not applicable — this is state-computation logic, not a visual component.

## States

Not applicable — this is state-computation logic, not a visual component.

## Accessibility

Not applicable — this is state-computation logic, not a visual component.

## Conformance Test Vectors

Rows below are built with `id: deploy:vc_<name>:build`, `kind: "deploy"`, `step: "build"`, and the tone stated (see Platform Notes for the test suite these vectors are drawn from). Values are read after the accumulation step has settled.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| build-progress-001 | in-flight-predicate, visible-definition, total-definition, pct-definition | `[build("app", "progress")]` | `visible: true`, `total: 1`, `completed: 0`, `pct: 0` |
| build-progress-002 | completed-definition, complete-definition | `[build("app","progress")]`, then re-evaluated with `[build("app","good")]` | `total: 1`, `completed: 1`, `pct: 100`, `complete: true` |
| build-progress-003 | completed-definition, server-owns-demotion | `[build("app","progress")]`, then re-evaluated with `[build("app","stale")]` | `completed: 1`, `complete: true` |
| build-progress-004 | no-client-clock | `[build("wedged","progress")]` with `at` one hour before now | `visible: true`, `total: 1`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-005 | pct-definition, hold-visible, complete-hold, reset-effect | Fake timers. `[one:progress, two:progress]` → `[one:good, two:progress]` → `[one:good, two:good]` → advance 2100 ms | `total: 2`; then `pct: 50`, `visible: true`; then `pct: 100`, `visible: true`; then `visible: false` |
| build-progress-006 | deploy-step-excluded, non-deploy-kind-excluded | `[{step:"deploy", tone:"progress", id:"deploy:vc_app:deploy"}, {kind:"probe", step:null, tone:"progress", id:"issue:ep-app:opened:<T0>:41"}]` | `visible: false`, `total: 0` |
| build-progress-007 | cohort-accumulation, completed-definition | `[build("app","progress")]`, then re-evaluated with `[]` | `total: 1`, `completed: 1`, `complete: true` |
| build-progress-008 | hold-cancel | Fake timers. `[a:progress]` → `[a:good]` → advance 1000 ms → `[a:good, b:progress]` → advance 2000 ms | After the last step: `total: 2`, `completed: 1`, `pct: 50`, `visible: true` (the cohort was not reset) |
| build-progress-009 | pct-definition | Cohort of 3 with 1 settled | `pct: 33`; with 2 settled, `pct: 67` |
| build-progress-010 | identity-by-id | Two rows with the same `id`, both `"progress"` | `total: 1` |
| build-progress-011 | cohort-no-op-when-idle, reset-effect | `[]` on first evaluation | `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-012 | unmount-cleanup | Fake timers. Reach `complete: true`, tear down, advance 2000 ms | No state update is attempted after teardown (no pending timer remains) |

Vectors 001–006 are the assertions of this logic's test suite (see Platform Notes); 007–012 are traced to the accumulation and hold behavior described above.

## Edge Cases

- **Empty activity**: `[]` MUST yield `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false`, and the accumulation step MUST return early without touching state.
- **Build drops out of the feed**: A cohort id missing from the next snapshot MUST count as completed; this logic cannot distinguish "finished" from "paged out" and MUST NOT try.
- **Wedged build**: A build toned `"progress"` indefinitely MUST keep the bar visible below 100% until the server re-tones the row; there is no client timeout.
- **Build re-enters progress**: A cohort id that settled and then is toned `"progress"` again MUST count as not completed again; if this happens during the hold it MUST cancel the reset.
- **New build during the hold**: A new in-flight id arriving before 2000 ms elapse MUST join the existing cohort, and `total` MUST include the already-completed builds.
- **Same id after reset**: After the cohort resets, an id seen in flight again MUST start a new cohort of one.
- **Duplicate ids in one snapshot**: They MUST collapse to one cohort member.
- **Tones other than `"progress"`**: `"good"`, `"bad"`, `"neutral"` and `"stale"` MUST all count as not in flight.
- **Malformed input**: This logic relies on the activity-row shape; it performs no runtime validation, and a row missing `kind`, `step` or `tone` MUST simply fail the in-flight predicate.
- **Environment filter changes**: If the caller's filtered array stops including a cohort build, that build MUST count as completed, exactly like a row leaving the feed.
- **Concurrent access**: Not applicable beyond the threading requirement; this logic runs without concurrent execution and each evaluation sees one snapshot (see Platform Notes).
- **Network or offline**: Not applicable; this logic does no I/O. A stale board simply keeps the last snapshot's rows, and the bar reflects them unchanged.
- **Teardown**: A pending hold timer MUST be cleared during teardown (see Platform Notes).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Activity rows | list of activity rows | — (required) | The rows to track. The caller passes its env-filtered activity rows. |
| Hold duration at 100% | number (fixed) | `2000` (ms) | How long the bar holds at 100% after the last cohort build completes before the cohort resets. Not overridable by the caller. |

## Deep Linking

Not applicable: this logic is internal state computation with no route or URL handling.

## Localization

Not applicable: this logic returns only numbers and booleans and contains no user-facing strings.

## Accessibility Options

Not applicable: this logic renders nothing; any motion or contrast handling belongs to the build-progress bar view.

## Feature Flags

Not applicable: this logic is not gated by any flag in the source.

## Analytics

Not applicable: this logic emits no analytics events.

## Privacy

Not applicable: this logic reads activity rows already in memory, stores only a set of row ids in local state, and persists or transmits nothing.

## Logging

Not applicable: this logic makes no logging calls.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-build-progress.ts`, a `"use client"` hook using `useState<ReadonlySet<string>>` for the cohort, one `useEffect` keyed on the sorted, `|`-joined in-flight-id key (`inFlightKey`) to accumulate (with lint suppressions for `set-state-in-effect` and `exhaustive-deps`, deliberately, as an external-observation sync), and one `useEffect` keyed on `allDone` that owns the `setTimeout`/`clearTimeout` hold, sized by the module constant `COMPLETE_HOLD_MS`. `pct` is rounded with `Math.round`. Because the cohort update runs in an effect rather than during render, a newly observed build lags one render behind before it counts toward `total`; React's single-threaded render and effect phases guarantee no two hook invocations interleave, so cohort updates are strictly ordered, and unmounting runs the effects' cleanup, clearing any pending hold timer. Tests use Vitest + `@testing-library/react` `renderHook` with fake timers, in `use-build-progress.test.ts`.
- **SwiftUI**: Model as an `@Observable` `@MainActor` class holding `cohort: Set<String>`, with a method taking `[ActivityRow]` that unions in-flight ids and recomputes; the hold is a `Task { try await Task.sleep(for: .seconds(2)) }` stored and cancelled when completion flips false. Because the update is synchronous in the method, the one-render lag of the React version disappears.
- **Compose**: A `ViewModel` exposing `StateFlow<BuildProgress>`; accumulate the cohort in a `MutableStateFlow<Set<String>>` on each activity emission, and run the hold as a `viewModelScope.launch { delay(2000) }` `Job` cancelled when completion flips false. `derivedStateOf` fits the computed fields.
- **AppKit / UIKit**: A plain model object on the main thread with a `Set<String>` and a cancellable `DispatchWorkItem` (or `Timer`) for the 2-second hold, notifying the view through a delegate, closure, or Combine publisher.
- **WinUI 3**: A view-model class implementing `INotifyPropertyChanged` (or `ObservableObject` from CommunityToolkit.Mvvm) with a `HashSet<string>` cohort and an `Update(IReadOnlyList<ActivityRow> activity)` method called on the UI thread whenever the board refreshes; expose `Visible`, `Completed`, `Total`, `Pct`, `Complete` as bindable properties driving a `ProgressBar` (`Value` = `Pct`, `Maximum` = 100) whose `Visibility` binds to `Visible`. Run the hold as `await Task.Delay(2000, cts.Token)` with a `CancellationTokenSource` cancelled when completion flips false, or a `DispatcherQueueTimer` from `DispatcherQueue.GetForCurrentThread().CreateTimer()` with `Interval` 2 s and `IsRepeating = false`. Rows arrive already deserialized (e.g. via `System.Text.Json`); keep the predicate on `Kind`/`Step`/`Tone` and never on `At`. Unlike React, the update is synchronous, so there is no render lag before a new build counts.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-build-progress.ts` |

## Design Decisions

**Decision**: In-flight is decided only by the server's `tone === "progress"`; the former client-side 10-minute `UNCONFIRMED_AFTER_MS` clock was removed.

**Rationale**: The private clock made the progress bar read complete while the row below it still said "building" — one fact with two derivations. The server now owns demotion (`reconcile-stuck-deploys` → `"stale"`), so the bar and the row always agree; the accepted cost is that a wedged build keeps the bar visible below 100% until the server expires it.

**Approved**: pending

---

**Decision**: The cohort accumulates in state via an effect rather than being derived from the current snapshot.

**Rationale**: Completed builds leave the in-flight set, so a snapshot alone cannot know how many builds the cohort had; the ids must be remembered across snapshots. The source comments call this an external-observation sync, mirroring `useEnvFilter`'s hydration pattern.

**Approved**: pending

---

**Decision**: Hold at 100% for 2000 ms before resetting, and let a new build cancel the reset.

**Rationale**: The hold lets the viewer see completion before the bar hides; cancelling on a new build keeps a busy period in one cohort rather than flashing the bar to zero.

**Approved**: pending

---

**Decision**: A build that drops out of the feed counts as completed.

**Rationale**: The source treats "no longer asserted in flight by the board" as done, whether settled, expired or gone, because the server decides what the feed contains.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [progress-indication](agenticdevelopercookbook://compliance/performance#progress-indication) | passed | performance |

The hook computes progress only; rendering lives in `BuildProgressBar` and filtering in `OverviewTab`, so concerns are separated. `use-build-progress.test.ts` covers the in-flight predicate, settle, server expiry, the absent client clock, the mixed cohort with the 2-second hold, and non-build rows; it does not cover hold cancellation by a new build, a row leaving the feed, or unmount cleanup, hence partial. The hook supplies determinate progress (completed/total, integer percent) for the build bar.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
