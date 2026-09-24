---
id: 0b171409-02f8-4ad2-97d3-8f4b1adfa340
title: useNow
domain: agentictoolkit://recipes/status-web-hooks-use-now
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook returning a coarse wall-clock timestamp snapshotted on mount and
  refreshed on a fixed interval (default 30 s).
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# useNow

## Overview

`useNow` is a client-only React hook in the status web app (`packages/web/packages/status-web/src/hooks/use-now.ts`). It returns a millisecond epoch timestamp that is captured with `Date.now()` when the calling component mounts and then refreshed every `intervalMs` milliseconds (default `30_000`). Its doc comment states the purpose: it is a "coarse, stable-per-render clock" to use "instead of calling `Date.now()` directly in render", because an in-render `Date.now()` is impure, makes "time ago" labels jump on unrelated re-renders, and is flagged by the React hooks lint. The periodic refresh also "keeps relative times ticking on their own".

Callers in the app (`ActivityPanel`, `OverviewTab`, `StaleMonitorsBanner`, `Dashboard`, `DeployList`, `GlobalPanel`, `FleetView`, `StatusMatrix`, `ProjectBrowser`, and the `useBoard` hook) use the returned value as `nowMs` for relative-time labels and staleness checks; `lib/board-staleness.ts` notes that board staleness is judged against this client clock.

## Behavioral Requirements

- **signature**: The hook MUST be callable as `useNow(intervalMs?)`, taking one optional numeric argument and returning a single `number`.
- **default-interval**: When `intervalMs` is omitted, the refresh interval MUST be 30,000 ms.
- **return-unit**: The returned value MUST be a millisecond Unix epoch timestamp as produced by `Date.now()`.
- **mount-snapshot**: On the first render of the calling component the hook MUST return the value of `Date.now()` captured at that moment (lazy state initializer).
- **stable-between-ticks**: Re-renders of the calling component that occur between ticks MUST return the same value as the previous render; the hook MUST NOT read the clock during render after the initial snapshot.
- **periodic-refresh**: Every `intervalMs` milliseconds after the effect starts, the hook MUST replace its stored value with a fresh `Date.now()` reading, which triggers a re-render of the calling component.
- **no-immediate-refresh**: Starting the interval MUST NOT itself update the value; the first refresh happens one full `intervalMs` after the effect runs.
- **single-timer**: The hook MUST keep at most one active interval timer per hook instance at any time.
- **interval-change-restart**: When `intervalMs` changes between renders, the hook MUST clear the existing timer and start a new one with the new interval; the stored value MUST NOT be reset by the change.
- **unmount-cleanup**: When the calling component unmounts, the hook MUST clear its interval timer so no further updates are scheduled.
- **instance-independence**: Each call site MUST own an independent clock and timer; two components using the hook are not synchronized and MAY return values that differ by up to one interval.
- **client-only-module**: The module MUST be marked as client code (the `"use client"` directive) because it depends on React state, effects and browser timers.
- **no-validation**: The hook MUST pass `intervalMs` to the timer unchanged; it performs no range or type check of its own.
- **no-side-effects-beyond-timer**: The hook MUST NOT perform network, storage, logging or other I/O; its only side effect is the interval timer.
- **concurrency**: All updates MUST run on the single JavaScript thread via the timer callback and React state; there is no cross-thread access, so ordering between ticks and renders is determined by the event loop.

## Appearance

Not applicable — this is a React clock hook, not a visual component.

## States

Not applicable — this is a React clock hook, not a visual component.

## Accessibility

Not applicable — this is a React clock hook, not a visual component.

## Conformance Test Vectors

No test file exists for `use-now.ts`; `use-board.dom.test.tsx` exercises it only indirectly (its fixtures use live `Date.now()` because staleness is judged "via `useNow`"). The vectors below are derived from the source and assume fake timers with a controllable system clock.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-now-001 | signature, return-unit, mount-snapshot | System clock at 1,000,000; render `useNow()` | Returns `1000000` |
| use-now-002 | stable-between-ticks | After use-now-001, advance clock to 1,010,000 without firing timers; force a re-render | Still returns `1000000` |
| use-now-003 | default-interval, periodic-refresh, no-immediate-refresh | Clock at 1,000,000; render `useNow()`; advance timers by 29,999 ms, then by 1 ms more | Value is `1000000` after 29,999 ms; becomes `1030000` after 30,000 ms |
| use-now-004 | periodic-refresh | Render `useNow(1000)` at clock 0; advance timers by 3,000 ms | Value updates three times, ending at `3000` |
| use-now-005 | interval-change-restart, single-timer | Render `useNow(1000)` at clock 0; at 500 ms re-render with `useNow(5000)`; advance to 1,000 ms | No update at 1,000 ms; value still `0`; exactly one timer pending; next update at 5,500 ms |
| use-now-006 | unmount-cleanup | Render `useNow(1000)`; unmount; advance timers by 5,000 ms | `clearInterval` called once with the timer id; no state update or React warning occurs; zero pending timers |
| use-now-007 | instance-independence | Mount component A with `useNow(1000)` at clock 0 and component B at clock 400 | A returns `0`, B returns `400`; after advancing to 1,000 ms A returns `1000` while B still returns `400` |
| use-now-008 | no-side-effects-beyond-timer | Render `useNow()` with `fetch`, `localStorage` and `console` spied | No calls to any spy |

## Edge Cases

- **Omitted argument**: `useNow()` MUST use 30,000 ms (use-now-003).
- **Explicit default**: `useNow(30_000)` (as `FleetView` calls it) MUST behave identically to `useNow()`.
- **Zero or negative interval**: The hook MUST pass the value to `setInterval` unchanged; the browser timer then treats it as 0 and fires as fast as the host clamps allow (HTML timers clamp nested timers to at least 4 ms). This produces a re-render on nearly every tick; the hook provides no guard.
- **Non-finite interval (`NaN`, `Infinity`)**: The hook MUST pass it unchanged; browser `setInterval` coerces `NaN` to 0. TypeScript's `number` type is the only constraint.
- **Unmount before first tick**: The cleanup MUST clear the pending timer and no state update MUST occur.
- **Interval change mid-period**: The elapsed portion of the old period is discarded; the next tick MUST occur a full new `intervalMs` after the re-render that changed it (use-now-005).
- **Background tab throttling**: When the browser throttles timers in a hidden tab, ticks SHOULD be expected to arrive late; the hook does not compensate, so the value may lag real time by more than `intervalMs` until the next tick.
- **System clock change**: The hook reads wall-clock time; if the device clock jumps backward, the next tick MUST report the earlier value, so the value is not guaranteed to be monotonic.
- **Server render and hydration**: The lazy initializer runs once on the server render and again on the client, so the server-rendered timestamp and the client's first value can differ; the hook does not reconcile them (see Design Decisions).
- **Concurrent calls**: Many components calling the hook each create their own timer; there is no shared ticker, so N callers cost N timers.
- **Error states / offline**: Not applicable: the hook performs no I/O and has no failure path; `Date.now()`, `setInterval` and `clearInterval` do not throw for numeric input.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `intervalMs` | `number` | `30_000` | Milliseconds between clock refreshes. Changing it restarts the timer. |

No environment variables, settings keys or injected dependencies; the clock (`Date.now`) and timers (`setInterval`/`clearInterval`) are the host globals.

## Deep Linking

Not applicable: the hook is an internal clock with no route or URL surface.

## Localization

Not applicable: the hook returns a number and contains no user-facing strings; formatting of relative times is done by its callers.

## Accessibility Options

Not applicable: the hook renders nothing and does not respond to display options such as Reduce Motion.

## Feature Flags

Not applicable: the source reads no flag and the hook is always active when called.

## Analytics

Not applicable: the hook emits no events.

## Privacy

Not applicable: the hook reads only the device clock and stores or transmits no data.

## Logging

Not applicable: the source contains no log calls.

## Platform Notes

- **SwiftUI**: Start from `TimelineView(.periodic(from: .now, by: 30))`, which supplies `context.date` and re-renders on schedule without a manual timer; alternatively a `@State var now = Date()` updated from `Timer.publish(every:on:in:).autoconnect()` via `.onReceive`. Swift uses `Date` (seconds as `TimeInterval`), so convert to milliseconds if parity with the web value matters. The view lifecycle cancels the timer on disappear, matching `unmount-cleanup`.
- **Compose**: Use `produceState(initialValue = System.currentTimeMillis(), intervalMs) { while (true) { delay(intervalMs); value = System.currentTimeMillis() } }`; keying on `intervalMs` restarts the coroutine like the React effect dependency, and leaving composition cancels it.
- **React/Web**: Source platform. `src/hooks/use-now.ts` uses `useState` with a lazy initializer for the mount snapshot and `useEffect` keyed on `[intervalMs]` to own a `setInterval` whose cleanup calls `clearInterval`. The `"use client"` directive marks it for Next.js client components.
- **AppKit / UIKit**: Hold a `Timer.scheduledTimer(withTimeInterval:repeats:)` (or a `DispatchSourceTimer`) in the owning view controller, store `Date()` on each fire, and invalidate the timer in `viewDidDisappear`/`deinit`. Add the timer to the `.common` run-loop mode if ticks must continue during scrolling.
- **WinUI 3**: Use a `Microsoft.UI.Xaml.DispatcherTimer` (or `DispatcherQueue.CreateTimer()` returning `DispatcherQueueTimer`) with `Interval = TimeSpan.FromMilliseconds(intervalMs)` and a `Tick` handler that sets a `Now` property (`DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()` for parity) on a view model implementing `INotifyPropertyChanged`, so `{x:Bind}` labels refresh. Initialize `Now` in the constructor (mount snapshot), call `Start()` in `Loaded` and `Stop()` in `Unloaded` to mirror `unmount-cleanup`; changing the interval means stopping, setting `Interval`, and restarting. Timer ticks already run on the UI thread, so no marshalling is needed. For a shared app-wide clock instead of per-control timers, expose one view-model instance rather than one timer per control.

## Design Decisions

**Decision**: Snapshot the clock into React state instead of calling `Date.now()` during render.
**Rationale**: The doc comment says an in-render `Date.now()` is impure, makes "time ago" labels jump on unrelated re-renders, and is flagged by the React hooks lint; state keeps renders pure and stable between ticks.
**Approved**: pending

**Decision**: Coarse 30-second default refresh.
**Rationale**: The consumers show relative times and staleness judged in minutes, so a 30 s tick keeps labels current while limiting re-renders; callers may pass a smaller value when finer resolution matters.
**Approved**: pending

**Decision**: One timer per hook instance, with no shared ticker.
**Rationale**: Keeps the hook self-contained; the cost is that separate components drift by up to one interval and each holds its own timer (`instance-independence`).
**Approved**: pending

**Decision**: No reconciliation of the server-rendered and client initial timestamps.
**Rationale**: The source relies on the lazy initializer alone; any text derived from the value can differ between server HTML and first client render. The hook's consumers accept this; a port that server-renders should decide whether to defer the first reading to the client.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | performance |

The hook does one thing — supply a stable, periodically refreshed timestamp — and leaves formatting and staleness logic to callers, so separation of concerns passes. There is no dedicated test file for `use-now.ts`; it is exercised only indirectly through `use-board.dom.test.tsx`, so unit test coverage is partial. Resource use passes: the timer is cleared on unmount and on interval change, and the coarse default limits re-renders, though every caller holds its own timer.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
