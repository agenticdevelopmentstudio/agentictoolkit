<!-- leaf: implement-status-web-hooks/use-now--test-vectors · source: status-web-hooks-use-now.md -->

# useNow

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
