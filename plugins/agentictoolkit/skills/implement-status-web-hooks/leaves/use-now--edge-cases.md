<!-- leaf: implement-status-web-hooks/use-now--edge-cases · source: status-web-hooks-use-now.md -->

# useNow

**Rules** (cite as `implement-status-web-hooks/use-now--edge-cases#<slug>`):

- `omitted-argument` MUST — useNow() MUST use 30,000 ms (use-now-003).
- `explicit-default` MUST — useNow(30_000) (as FleetView calls it) MUST behave identically to useNow().
- `zero-or-negative-interval` MUST — The hook MUST pass the value to setInterval unchanged; the browser timer then treats it as 0 and fires as fast as the …
- `non-finite-interval` MUST — The hook MUST pass it unchanged; browser setInterval coerces NaN to 0. TypeScript's number type is the only constraint.
- `unmount-before-first-tick` MUST — The cleanup MUST clear the pending timer and no state update MUST occur.
- `interval-change-mid-period` MUST — The elapsed portion of the old period is discarded; the next tick MUST occur a full new intervalMs after the re-render …
- `background-tab-throttling` SHOULD — When the browser throttles timers in a hidden tab, ticks SHOULD be expected to arrive late; the hook does not …
- `system-clock-change` MUST — The hook reads wall-clock time; if the device clock jumps backward, the next tick MUST report the earlier value, so the …

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
