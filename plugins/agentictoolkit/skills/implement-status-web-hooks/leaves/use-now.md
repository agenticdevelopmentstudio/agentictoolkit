<!-- leaf: implement-status-web-hooks/use-now · source: status-web-hooks-use-now.md -->

**Rules** (cite as `implement-status-web-hooks/use-now#<slug>`):

- `signature` MUST
- `default-interval` MUST
- `return-unit` MUST
- `mount-snapshot` MUST
- `stable-between-ticks` MUST
- `periodic-refresh` MUST
- `no-immediate-refresh` MUST
- `single-timer` MUST
- `interval-change-restart` MUST
- `unmount-cleanup` MUST
- `instance-independence` MUST
- `client-only-module` MUST
- `no-validation` MUST
- `no-side-effects-beyond-timer` MUST
- `concurrency` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `intervalMs` | `number` | `30_000` | Milliseconds between clock refreshes. Changing it restarts the timer. |

No environment variables, settings keys or injected dependencies; the clock (`Date.now`) and timers (`setInterval`/`clearInterval`) are the host globals.

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
