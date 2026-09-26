---
id: a076f315-885d-45df-998d-68703a319ec8
title: useBuildProgress
domain: agentictoolkit://cookbook/status-web/hooks/use-build-progress
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that derives progress over the current build cohort from server-toned
  activity rows, holding 100% for 2s before resetting.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/hooks/use-activity-ttl
references: []
approved-by: ''
approved-date: ''
---

# useBuildProgress

## Overview

`useBuildProgress(activity: ActivityRow[]): BuildProgress` is a client-side React hook in the status-web package that computes progress over the current build "cohort" — the set of builds seen in flight since the last all-idle moment. A build joins the cohort while the board reports it in flight (a row with `kind === "deploy"`, `step === "build"` and `tone === "progress"`) and counts as completed once the board stops saying so: the row settles, the server expires it to `"stale"`, or it drops out of the feed. The hook has no clock of its own for judging a build; the only timer it runs is the 2-second hold at 100% after every cohort build is done, after which the cohort resets and the bar hides.

`OverviewTab` passes its env-filtered activity (`envActivity`), so a filtered-out environment's build does not count; the value drives `BuildProgressBar`. The hook reads nothing but its argument and performs no I/O.

## Behavioral Requirements

- **signature**: The hook MUST accept one argument, `activity: ActivityRow[]`, and return a `BuildProgress` object on every render.
- **return-shape**: `BuildProgress` MUST carry exactly five fields: `visible: boolean`, `completed: number`, `total: number`, `pct: number`, `complete: boolean`.
- **in-flight-predicate**: A row MUST be treated as an in-flight build if and only if `kind === "deploy"` AND `step === "build"` AND `tone === "progress"`.
- **deploy-step-excluded**: A row with `step === "deploy"` MUST NOT enter the cohort, whatever its tone.
- **non-deploy-kind-excluded**: A row whose `kind` is `"probe"` or `"platform"` MUST NOT enter the cohort, whatever its tone or step.
- **no-client-clock**: The in-flight predicate MUST NOT consult the row's `at` timestamp or any wall-clock time; a build the board still tones `"progress"` MUST remain in flight regardless of its age.
- **identity-by-id**: Cohort membership MUST be keyed by `ActivityRow.id`; rows sharing an `id` MUST count as one build.
- **cohort-accumulation**: Every `id` observed in flight MUST be added to the cohort and MUST stay in it until the cohort resets, even after its row leaves the feed.
- **cohort-no-op-when-idle**: When the current snapshot contains no in-flight builds, the accumulation step MUST NOT modify the cohort.
- **cohort-stable-identity**: When every in-flight `id` is already in the cohort, the accumulation step MUST keep the existing cohort set instead of storing a new one, so no extra re-render is triggered.
- **accumulation-trigger**: Accumulation MUST re-run only when the sorted, `|`-joined list of in-flight ids (`inFlightKey`) changes between renders.
- **total-definition**: `total` MUST equal the number of distinct ids in the cohort.
- **completed-definition**: `completed` MUST equal the number of cohort ids not in flight in the current `activity` snapshot, counting settled, server-expired (`"stale"`) and absent rows alike.
- **pct-definition**: `pct` MUST be `0` when `total` is `0`, and otherwise `Math.round((completed / total) * 100)`, an integer from 0 to 100.
- **visible-definition**: `visible` MUST be `true` exactly when `total > 0`.
- **complete-definition**: `complete` MUST be `true` exactly when `total > 0` and `completed === total`.
- **complete-hold**: When `complete` becomes `true`, the hook MUST schedule a single timer of `COMPLETE_HOLD_MS` (2000 ms) that clears the cohort to an empty set.
- **hold-visible**: During the 2000 ms hold the hook MUST keep returning `visible: true`, `pct: 100`, `complete: true`.
- **hold-cancel**: If `complete` becomes `false` before the timer fires (a new build enters the cohort, or a cohort build is toned `"progress"` again), the pending timer MUST be cleared and the cohort MUST NOT be reset.
- **reset-effect**: After the timer fires, the hook MUST return `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false` until another in-flight build is observed.
- **unmount-cleanup**: Unmounting while a hold timer is pending MUST clear that timer.
- **one-render-lag**: A build first observed in flight MUST be absent from `total` in the render that first sees it and MUST appear after the accumulation effect commits and triggers a re-render; the cohort is state updated in an effect, not derived during render.
- **input-not-mutated**: The hook MUST NOT mutate the `activity` array or its rows.
- **no-side-effects**: The hook MUST perform no network, storage, logging or DOM side effects; its only side effect is the hold timer.
- **caller-filters**: The hook MUST track exactly the rows it is given; filtering by environment is the caller's responsibility (`OverviewTab` passes `envActivity`), and display-only narrowing (ttl, clear, search) MUST NOT be applied to its input.
- **server-owns-demotion**: This hook MUST NOT demote an in-flight build itself; expiry of a wedged build is owned by the server (`reconcile-stuck-deploys` sets tone to `"stale"`, `deployIsStuck` raises a Problem), and until that happens the bar stays visible below 100%.
- **client-only**: The module MUST be a client module (`"use client"`), since it uses `useState`, `useEffect` and `setTimeout`.
- **threading**: All reads and state updates MUST run on the browser's single JavaScript thread during React render and effect phases; no two hook invocations interleave, so cohort updates are ordered by render order.

## Appearance

Not applicable — this is a React state hook computing build progress, not a visual component.

## States

Not applicable — this is a React state hook computing build progress, not a visual component.

## Accessibility

Not applicable — this is a React state hook computing build progress, not a visual component.

## Conformance Test Vectors

Rows below are built as in `use-build-progress.test.ts`: `id: deploy:vc_<name>:build`, `kind: "deploy"`, `step: "build"`, with the tone stated. Values are read after effects flush.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| build-progress-001 | in-flight-predicate, visible-definition, total-definition, pct-definition | `[build("app", "progress")]` | `visible: true`, `total: 1`, `completed: 0`, `pct: 0` |
| build-progress-002 | completed-definition, complete-definition | `[build("app","progress")]`, then rerender with `[build("app","good")]` | `total: 1`, `completed: 1`, `pct: 100`, `complete: true` |
| build-progress-003 | completed-definition, server-owns-demotion | `[build("app","progress")]`, then rerender with `[build("app","stale")]` | `completed: 1`, `complete: true` |
| build-progress-004 | no-client-clock | `[build("wedged","progress")]` with `at` one hour before now | `visible: true`, `total: 1`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-005 | pct-definition, hold-visible, complete-hold, reset-effect | Fake timers. `[one:progress, two:progress]` → `[one:good, two:progress]` → `[one:good, two:good]` → advance 2100 ms | `total: 2`; then `pct: 50`, `visible: true`; then `pct: 100`, `visible: true`; then `visible: false` |
| build-progress-006 | deploy-step-excluded, non-deploy-kind-excluded | `[{step:"deploy", tone:"progress", id:"deploy:vc_app:deploy"}, {kind:"probe", step:null, tone:"progress", id:"issue:ep-app:opened:<T0>:41"}]` | `visible: false`, `total: 0` |
| build-progress-007 | cohort-accumulation, completed-definition | `[build("app","progress")]`, then rerender with `[]` | `total: 1`, `completed: 1`, `complete: true` |
| build-progress-008 | hold-cancel | Fake timers. `[a:progress]` → `[a:good]` → advance 1000 ms → `[a:good, b:progress]` → advance 2000 ms | After the last step: `total: 2`, `completed: 1`, `pct: 50`, `visible: true` (the cohort was not reset) |
| build-progress-009 | pct-definition | Cohort of 3 with 1 settled | `pct: 33`; with 2 settled, `pct: 67` |
| build-progress-010 | identity-by-id | Two rows with the same `id`, both `"progress"` | `total: 1` |
| build-progress-011 | cohort-no-op-when-idle, reset-effect | `[]` on first render | `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-012 | unmount-cleanup | Fake timers. Reach `complete: true`, unmount, advance 2000 ms | No state update is attempted after unmount (no pending timer remains) |

Vectors 001–006 are the assertions of `use-build-progress.test.ts`; 007–012 are traced to `useBuildProgress`'s accumulation and hold effects.

## Edge Cases

- **Empty activity**: `[]` MUST yield `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false`, and the accumulation effect MUST return early without touching state.
- **Build drops out of the feed**: A cohort id missing from the next snapshot MUST count as completed; the hook cannot distinguish "finished" from "paged out" and MUST NOT try.
- **Wedged build**: A build toned `"progress"` indefinitely MUST keep the bar visible below 100% until the server re-tones the row; there is no client timeout.
- **Build re-enters progress**: A cohort id that settled and then is toned `"progress"` again MUST count as not completed again; if this happens during the hold it MUST cancel the reset.
- **New build during the hold**: A new in-flight id arriving before 2000 ms elapse MUST join the existing cohort, and `total` MUST include the already-completed builds.
- **Same id after reset**: After the cohort resets, an id seen in flight again MUST start a new cohort of one.
- **Duplicate ids in one snapshot**: They MUST collapse to one cohort member.
- **Tones other than `"progress"`**: `"good"`, `"bad"`, `"neutral"` and `"stale"` MUST all count as not in flight.
- **Malformed input**: The hook relies on the `ActivityRow` type; it performs no runtime validation, and a row missing `kind`, `step` or `tone` MUST simply fail the in-flight predicate.
- **Environment filter changes**: If the caller's filtered array stops including a cohort build, that build MUST count as completed, exactly like a row leaving the feed.
- **Concurrent access**: Not applicable beyond the threading requirement; the hook runs on the single JS thread and each render sees one snapshot.
- **Network or offline**: Not applicable; the hook does no I/O. A stale board simply keeps the last snapshot's rows, and the bar reflects them unchanged.
- **Unmount**: A pending hold timer MUST be cleared by the effect cleanup.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `activity` | `ActivityRow[]` | — (required) | The rows to track. `OverviewTab` passes its env-filtered `envActivity`. |
| `COMPLETE_HOLD_MS` | `number` (module constant) | `2000` | How long the bar holds at 100% after the last cohort build completes before the cohort resets. Not overridable by the caller. |

## Deep Linking

Not applicable: the hook is internal state logic with no route or URL handling.

## Localization

Not applicable: the hook returns only numbers and booleans and contains no user-facing strings.

## Accessibility Options

Not applicable: the hook renders nothing; any motion or contrast handling belongs to `BuildProgressBar`.

## Feature Flags

Not applicable: the hook is not gated by any flag in the source.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook reads activity rows already in memory, stores only a set of row ids in React state, and persists or transmits nothing.

## Logging

Not applicable: the hook makes no logging calls.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-build-progress.ts`, a `"use client"` hook using `useState<ReadonlySet<string>>` for the cohort, one `useEffect` keyed on `inFlightKey` to accumulate (with lint suppressions for `set-state-in-effect` and `exhaustive-deps`, deliberately, as an external-observation sync), and one `useEffect` keyed on `allDone` that owns the `setTimeout`/`clearTimeout` hold. Tests use Vitest + `@testing-library/react` `renderHook` with fake timers.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
