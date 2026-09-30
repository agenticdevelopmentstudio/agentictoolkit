<!-- leaf: implement-sync-engine/triggers--test-vectors · source: sync-engine-triggers.md -->

# SyncEngineTriggers

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| trig-001 | periodic-init, periodic-reason, periodic-fixed-delay | Construct a periodic source with `interval` 0.02; await two elements from one iterator (`testPeriodicTicks`) | Both elements are `.periodic` |
| trig-002 | periodic-first-tick-delay | Construct with `interval` 0.5; record the time of the first element | First element arrives no sooner than 0.5 s after construction |
| trig-003 | periodic-stop-cancels, periodic-stop-finishes, finish-ends-iteration | Interval 0.02; await one tick; call `stop()`; drain the iterator (`testPeriodicStopFinishesContinuation`) | Any already-buffered tick is returned, then iteration returns end-of-sequence instead of hanging |
| trig-004 | periodic-deinit-stops, periodic-no-self-capture | Hold the only strong reference in a box; await one tick; set the box to nil; drain (`testPeriodicDeinitStopsTicking`) | Iteration ends; the instance is deallocated while the task was running |
| trig-005 | periodic-stop-idempotent | Call `stop()` twice, then release the instance | No crash; the stream stays finished |
| trig-006 | periodic-cancel-check, periodic-sleep-error | Interval 10; call `stop()` 0.01 s later | Iteration ends promptly; no `.periodic` is ever yielded; no error surfaces to the consumer |
| trig-007 | connectivity-stop-finishes, connectivity-stop-cancels | Construct a connectivity source; call `stop()` immediately; drain (`testConnectivityStopFinishesContinuation`) | Iteration returns end-of-sequence without any element |
| trig-008 | connectivity-no-initial-kick | Path update sequence: satisfied | No element yielded |
| trig-009 | connectivity-transition-only, connectivity-reason, connectivity-init | Path update sequence: unsatisfied, satisfied | Exactly one `.connectivityRestored` |
| trig-010 | connectivity-repeat-satisfied | Path update sequence: unsatisfied, satisfied, satisfied | Exactly one `.connectivityRestored` |
| trig-011 | connectivity-transition-only | Path update sequence: satisfied, unsatisfied, satisfied, unsatisfied, satisfied | Exactly two `.connectivityRestored` |
| trig-012 | connectivity-unsatisfied-definition | Path update sequence: requires-connection, satisfied | Exactly one `.connectivityRestored` |
| trig-013 | connectivity-default-queue | Construct with no `queue` argument | Path updates are delivered on a serial queue labelled `ConnectivityTriggerSource` |
| trig-014 | manual-fire, manual-fire-before-subscribe | Create a manual source; make an iterator; `fire(.manual)`; await `next()` (`testManualFires`) | Returns `.manual` |
| trig-015 | manual-fire, manual-no-validation, kick-reason-equality | `fire(.hostSpecific("push"))` then `fire(.hostSpecific(""))` | Consumer receives `.hostSpecific("push")` then `.hostSpecific("")`, in that order; the first is not equal to `.hostSpecific("other")` |
| trig-016 | unbounded-buffer, stream-created-at-init | Manual source; fire 1,000 `.manual` before any iteration; then drain 1,000 | All 1,000 elements are delivered |
| trig-017 | manual-fire-any-thread | Fire 100 reasons concurrently from 10 tasks | Consumer receives exactly 100 elements; no crash |
| trig-018 | engine-stop-does-not-stop-source | Attach a periodic source to an engine; call `SyncEngine.stop()`; iterate the source directly | The source keeps yielding `.periodic` until its own `stop()` is called |
| trig-019 | kick-reason-cases, trigger-protocol, trigger-sendable | Compile a switch over `SyncKickReason` with no default; pass each source across a task boundary as `any SyncTriggerSource` | Compiles with exactly four cases; each source is accepted as `Sendable` |
| trig-020 | single-consumer | Iterate one source's `kicks` from one task and fire three reasons | That task receives all three in fire order |
| trig-021 | connectivity-no-deinit | Release a connectivity source without calling `stop()` | No explicit `stop()` runs; the source has no `deinit` |
| trig-022 | manual-no-stop | Inspect the manual source's public surface | Exposes `kicks`, `init()` and `fire(_:)` only; no `stop()` |
