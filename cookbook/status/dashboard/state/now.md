---
id: 0b171409-02f8-4ad2-97d3-8f4b1adfa340
title: Coarse Clock
domain: agentictoolkit://cookbook/status/dashboard/state/now
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State returning a coarse wall-clock timestamp captured when first used and
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

# Coarse Clock

## Overview

Now is client-only state that returns a coarse wall-clock timestamp: a millisecond epoch value captured when a caller starts using it, then refreshed every `intervalMs` milliseconds (default `30,000`). Its purpose is a stable, per-use clock to rely on instead of reading the wall clock directly during rendering, because doing so is impure, makes "time ago" labels jump on unrelated updates, and is commonly flagged by state-hook lint rules. The periodic refresh also keeps relative-time labels ticking on their own.

Various dashboard views and the board state use the returned value for relative-time labels and staleness checks; board staleness is judged against this clock.

## Behavioral Requirements

- **signature**: Now MUST take one optional numeric input (the refresh interval in milliseconds) and MUST return a single number.
- **default-interval**: When the interval is omitted, the refresh interval MUST be 30,000 ms.
- **return-unit**: The returned value MUST be a millisecond Unix epoch timestamp representing the current wall-clock time.
- **mount-snapshot**: On first use, Now MUST return the current wall-clock time captured at that moment.
- **stable-between-ticks**: Repeated reads between ticks MUST return the same value as before; Now MUST NOT read the clock again except at the initial snapshot and at each scheduled refresh.
- **periodic-refresh**: Every `intervalMs` milliseconds after Now starts running, it MUST replace its stored value with a fresh wall-clock reading, which MUST notify the caller of the change.
- **no-immediate-refresh**: Now starting to run MUST NOT itself update the value; the first refresh happens one full `intervalMs` after it starts.
- **single-timer**: Now MUST keep at most one active interval timer per instance at any time.
- **interval-change-restart**: When the interval changes between uses, Now MUST clear the existing timer and start a new one with the new interval; the stored value MUST NOT be reset by the change.
- **unmount-cleanup**: When the caller stops using it, Now MUST clear its interval timer so no further updates are scheduled.
- **instance-independence**: Each use MUST own an independent clock and timer; two callers using Now are not synchronized and MAY return values that differ by up to one interval.
- **client-only-module**: Now has no server-only or universal-rendering variant; it requires a live client execution context, because it depends on state, update notifications and a repeating timer.
- **no-validation**: Now MUST pass the interval to the timer unchanged; it performs no range or type check of its own.
- **no-side-effects-beyond-timer**: Now MUST NOT perform network, storage, logging or other I/O; its only side effect is the interval timer.
- **concurrency**: All updates MUST run on a single execution thread via the timer callback and the caller's own update mechanism; there is no cross-thread access, so ordering between ticks and reads is determined by that thread's scheduling.

## Appearance

Not applicable — this is a clock concept, not a visual component.

## States

Not applicable — this is a clock concept, not a visual component.

## Accessibility

Not applicable — this is a clock concept, not a visual component.

## Conformance Test Vectors

No dedicated test file exists for this concept; it is exercised only indirectly by the board state's own tests (whose fixtures use the live clock because staleness is judged through Now). The vectors below are derived from the source and assume a controllable system clock and timer.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-now-001 | signature, return-unit, mount-snapshot | System clock at 1,000,000; start using Now with the default interval | Returns `1000000` |
| use-now-002 | stable-between-ticks | After use-now-001, advance the clock to 1,010,000 without firing the timer; read the value again | Still returns `1000000` |
| use-now-003 | default-interval, periodic-refresh, no-immediate-refresh | Clock at 1,000,000; start using Now with the default interval; advance the timer by 29,999 ms, then by 1 ms more | Value is `1000000` after 29,999 ms; becomes `1030000` after 30,000 ms |
| use-now-004 | periodic-refresh | Start using Now with a 1,000 ms interval at clock 0; advance the timer by 3,000 ms | Value updates three times, ending at `3000` |
| use-now-005 | interval-change-restart, single-timer | Start using Now with a 1,000 ms interval at clock 0; at 500 ms change the interval to 5,000 ms; advance to 1,000 ms | No update at 1,000 ms; value still `0`; exactly one timer pending; next update at 5,500 ms |
| use-now-006 | unmount-cleanup | Start using Now with a 1,000 ms interval; stop using it; advance the timer by 5,000 ms | The timer is cleared exactly once; no further update or warning occurs; zero pending timers |
| use-now-007 | instance-independence | Start using Now in two places: one with a 1,000 ms interval at clock 0, another at clock 400 | The first returns `0`, the second returns `400`; after advancing to 1,000 ms the first returns `1000` while the second still returns `400` |
| use-now-008 | no-side-effects-beyond-timer | Start using Now with the default interval, with network, storage and logging calls monitored | No calls to any of them |

## Edge Cases

- **Omitted argument**: Using Now with no interval argument MUST use 30,000 ms (use-now-003).
- **Explicit default**: Passing `30,000` explicitly MUST behave identically to omitting it.
- **Zero or negative interval**: Now MUST pass the value to the timer unchanged; the environment then treats it as 0 and fires as fast as its own minimum clamp allows. This produces an update on nearly every tick; Now provides no guard.
- **Non-finite interval**: Now MUST pass a non-finite value unchanged; the environment's own coercion rules apply. There is no runtime constraint beyond taking a numeric input.
- **Stopping use before the first tick**: The cleanup MUST clear the pending timer and no update MUST occur.
- **Interval change mid-period**: The elapsed portion of the old period is discarded; the next tick MUST occur a full new interval after the change (use-now-005).
- **Background throttling**: When the environment throttles timers while inactive in the background, ticks SHOULD be expected to arrive late; Now does not compensate, so the value may lag real time by more than the interval until the next tick.
- **System clock change**: Now reads wall-clock time; if the device clock jumps backward, the next tick MUST report the earlier value, so the value is not guaranteed to be monotonic.
- **Server render and hydration**: The initial snapshot is taken once during a server-rendering pass and again on the client, so the server-rendered timestamp and the client's first value can differ; Now does not reconcile them (see Design Decisions).
- **Concurrent uses**: Many callers using Now each create their own timer; there is no shared ticker, so N callers cost N timers.
- **Error states / offline**: Not applicable: Now performs no I/O and has no failure path; the underlying clock and timer operations do not throw for numeric input.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Interval | number | `30000` | Milliseconds between clock refreshes. Changing it restarts the timer. |

No environment variables, settings keys or injected dependencies; the clock and timer are read from the host environment's own globals.

## Deep Linking

Not applicable: Now is an internal clock with no route or URL surface.

## Localization

Not applicable: Now returns a number and contains no user-facing strings; formatting of relative times is done by its callers.

## Accessibility Options

Not applicable: Now renders nothing and does not respond to display options such as Reduce Motion.

## Feature Flags

Not applicable: Now reads no flag and is always active when used.

## Analytics

Not applicable: Now emits no events.

## Privacy

Not applicable: Now reads only the device clock and stores or transmits no data.

## Logging

Not applicable: Now contains no log calls.

## Platform Notes

- **SwiftUI**: Start from `TimelineView(.periodic(from: .now, by: 30))`, which supplies `context.date` and re-renders on schedule without a manual timer; alternatively a `@State var now = Date()` updated from `Timer.publish(every:on:in:).autoconnect()` via `.onReceive`. Swift uses `Date` (seconds as `TimeInterval`), so convert to milliseconds if parity with the web value matters. The view lifecycle cancels the timer on disappear, matching `unmount-cleanup`.
- **Compose**: Use `produceState(initialValue = System.currentTimeMillis(), intervalMs) { while (true) { delay(intervalMs); value = System.currentTimeMillis() } }`; keying on `intervalMs` restarts the coroutine like the source's effect dependency, and leaving composition cancels it.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/hooks/use-now.ts` exports `useNow(intervalMs?)`, using `useState` with a lazy initializer (`Date.now()`) for the mount snapshot and `useEffect` keyed on `[intervalMs]` to own a `setInterval` whose cleanup calls `clearInterval`. A zero or negative interval is passed to `setInterval` unchanged; HTML timers clamp nested timers to at least 4 ms, so it fires roughly at that rate. `setInterval` coerces a `NaN` interval to 0; TypeScript's `number` type is the only compile-time constraint. The `"use client"` directive marks it for a React Server Components framework. Callers in the app include `ActivityPanel`, `OverviewTab`, `StaleMonitorsBanner`, `Dashboard`, `DeployList`, `GlobalPanel`, `FleetView` (which calls `useNow(30_000)` explicitly), `StatusMatrix`, `ProjectBrowser`, and `useBoard`; `lib/board-staleness.ts` notes that board staleness is judged against this client clock.
- **AppKit / UIKit**: Hold a `Timer.scheduledTimer(withTimeInterval:repeats:)` (or a `DispatchSourceTimer`) in the owning view controller, store `Date()` on each fire, and invalidate the timer in `viewDidDisappear`/`deinit`. Add the timer to the `.common` run-loop mode if ticks must continue during scrolling.
- **WinUI 3**: Use a `Microsoft.UI.Xaml.DispatcherTimer` (or `DispatcherQueue.CreateTimer()` returning `DispatcherQueueTimer`) with `Interval = TimeSpan.FromMilliseconds(intervalMs)` and a `Tick` handler that sets a `Now` property (`DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()` for parity) on a view model implementing `INotifyPropertyChanged`, so `{x:Bind}` labels refresh. Initialize `Now` in the constructor (mount snapshot), call `Start()` in `Loaded` and `Stop()` in `Unloaded` to mirror `unmount-cleanup`; changing the interval means stopping, setting `Interval`, and restarting. Timer ticks already run on the UI thread, so no marshalling is needed. For a shared app-wide clock instead of per-control timers, expose one view-model instance rather than one timer per control.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-now.ts` |

## Design Decisions

**Decision**: Snapshot the clock into state instead of reading it directly during rendering.
**Rationale**: Reading the wall clock in-render is impure, makes "time ago" labels jump on unrelated re-renders, and is flagged by common state-hook lint rules; a stored snapshot keeps evaluation pure and stable between ticks.
**Approved**: pending

**Decision**: Coarse 30-second default refresh.
**Rationale**: The consumers show relative times and staleness judged in minutes, so a 30 s tick keeps labels current while limiting update frequency; callers may pass a smaller value when finer resolution matters.
**Approved**: pending

**Decision**: One timer per use, with no shared ticker.
**Rationale**: Keeps Now self-contained; the cost is that separate callers drift by up to one interval and each holds its own timer (`instance-independence`).
**Approved**: pending

**Decision**: No reconciliation of the server-rendered and client initial timestamps.
**Rationale**: The source relies on the lazy initializer alone; any text derived from the value can differ between server output and first client render. This rationale applies to the web platform, where a server-rendering pass and a client paint can disagree; a platform with no such split has no counterpart. Consumers accept this; a port that renders server-side should decide whether to defer the first reading to the client.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
