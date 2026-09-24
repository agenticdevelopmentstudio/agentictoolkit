---
id: 0f423d74-6916-41cb-9f3c-bdb29c416a96
title: Status Server Monitor Cadence
domain: agentictoolkit://recipes/status-server-monitor-cadence
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Gates the status monitor's expensive deploy-sync phase behind a boot-safe
  delay and a recurring interval, with a manual override that re-anchors both.
platforms:
- typescript
- web
tags:
- monitor
- cadence
- deploy
- server
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-alerts
- agentictoolkit://recipes/status-server-config
references:
- packages/web/packages/status-server/src/monitor/cadence.ts (agentictoolkit)
- packages/web/packages/status-server/test/cadence.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/config-cadence.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/scheduler.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Cadence

## Overview

`cadence.ts` (`packages/web/packages/status-server/src/monitor/cadence.ts`) answers exactly one question for the status monitor's scheduler: on THIS tick, is the expensive deploy phase (provider polls, peer fetch, and telemetry — described by the module comment, wired externally by `cycle-runner.ts`'s `runMonitorCycle` and the scheduler in `scheduler.ts`) allowed to run? The file's own header comment records why this exists as a dedicated module rather than an inline check: the fast endpoint-probe tick that runs every interval must stay CHEAP, because an external supervisor (`start.py`, external to this package) restarts the whole container after three missed `/health` probes; a boot cycle that runs the heavy phase starves the probe loop right through that window, so the container dies, reboots, and re-enters the same heavy cycle — a crash loop the module comment says is exactly what happened before this fix. `createDeployCadence` produces one `DeployCadence` value whose single method, `shouldFullSync(manual)`, holds the first full sync back by `FIRST_FULL_SYNC_DELAY_MS` (60 seconds) after creation and, once past that boot grace period, allows one full sync per `deploySyncIntervalMs`; a `manual` call (the interactive "check now") always forces one and re-anchors the interval from the moment of that call. The endpoint probe itself is never gated by this file — only the deploy/peer/telemetry phase is.

## Behavioral Requirements

### Constant and Type Shape

- **first-full-sync-delay-constant**: The module MUST export `FIRST_FULL_SYNC_DELAY_MS` with the value `60_000` (60,000 milliseconds).
- **deploy-cadence-interface-shape**: The `DeployCadence` interface MUST declare exactly one member, `shouldFullSync(manual: boolean): boolean`, and MUST declare no other property or method.

### Construction (`createDeployCadence`)

- **required-deploy-sync-interval**: `createDeployCadence` MUST require its caller to supply `opts.deploySyncIntervalMs` as a number; the factory declares no default for this field.
- **first-delay-default**: `createDeployCadence` MUST use `opts.firstDelayMs` when it is a non-`null`, non-`undefined` value, and MUST otherwise use `FIRST_FULL_SYNC_DELAY_MS` (60,000) as the delay before the first full sync.
- **clock-default**: `createDeployCadence` MUST use `opts.now` when it is a non-`null`, non-`undefined` value, and MUST otherwise use `Date.now` as the clock; every timing decision inside the returned `DeployCadence` MUST read the current time by calling this resolved clock function, never `Date.now` directly.
- **initial-anchor-set-at-creation**: `createDeployCadence` MUST compute the first pending full-sync anchor once, at the moment it is called, as the resolved clock's current reading plus the resolved `firstDelayMs`; this computation MUST happen before the returned `DeployCadence`'s `shouldFullSync` is ever invoked, not lazily on first use.

### Cadence Decision (`shouldFullSync`)

- **manual-forces-full-sync**: `shouldFullSync` MUST return `true` whenever its `manual` argument is `true`, regardless of the pending anchor or how much time has elapsed since construction or the last full sync.
- **boot-grace-blocks-automatic-sync**: `shouldFullSync` MUST return `false` when `manual` is `false` and the clock's current reading is earlier than the pending anchor.
- **automatic-sync-after-anchor-elapsed**: `shouldFullSync` MUST return `true` when `manual` is `false` and the clock's current reading is no longer earlier than the pending anchor (i.e. the anchor time has been reached or passed).
- **reanchor-on-true-result**: Every call to `shouldFullSync` that returns `true` — whether forced by `manual` or triggered by the elapsed anchor — MUST set the pending anchor to that call's own clock reading plus `opts.deploySyncIntervalMs`, replacing whatever anchor was pending before the call.
- **anchor-unchanged-on-false-result**: A call to `shouldFullSync` that returns `false` MUST NOT modify the pending anchor in any way; the next call MUST see exactly the anchor that was pending before the `false`-returning call.

### Instance Independence

- **independent-per-call-state**: Each call to `createDeployCadence` MUST produce a `DeployCadence` with its own private, independently mutable anchor, closed over by the returned object; `createDeployCadence` MUST NOT share the anchor between two `DeployCadence` values it produces, and MUST NOT expose any way to read or set the anchor other than through `shouldFullSync`'s return value.

### Input Validation

- **interval-and-delay-validation**: a positive, finite `deploySyncIntervalMs` and a non-negative `firstDelayMs` are caller preconditions; `createDeployCadence` does not check them. A `deploySyncIntervalMs` of `0`, a negative value, or `NaN` makes `reanchor-on-true-result` land the anchor at or before the current clock reading, so `shouldFullSync(false)` returns `true` on every tick; a negative `firstDelayMs` makes the first automatic call after construction return `true`, running the heavy phase on the boot tick. The production caller satisfies the precondition through `config/port.ts`'s `deploySyncIntervalMs()`, which floors its output at 300,000ms via `Math.max`.

## Appearance

Not applicable — this is a scheduling-decision function, not a visual component.

## States

Not applicable — this is a scheduling-decision function, not a visual component; its only runtime state (whether the pending anchor has been reached) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a scheduling-decision function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-cadence-001 | boot-grace-blocks-automatic-sync | `createDeployCadence({deploySyncIntervalMs: 300_000, firstDelayMs: 60_000, now})`; call `shouldFullSync(false)` immediately after construction | Returns `false` — `cadence.test.ts` › "does NOT run the deploy phase on the boot tick" |
| status-server-monitor-cadence-002 | boot-grace-blocks-automatic-sync, automatic-sync-after-anchor-elapsed | Same cadence; `shouldFullSync(false)` → `false`; advance the injected clock by 59,000ms; `shouldFullSync(false)` → `false`; advance by 1,000ms more (60,000ms total); `shouldFullSync(false)` | Final call returns `true` — `cadence.test.ts` › "holds the deploy phase back until the first-sync delay has passed" |
| status-server-monitor-cadence-003 | reanchor-on-true-result, anchor-unchanged-on-false-result | Same cadence; advance 60,000ms; `shouldFullSync(false)` → `true` (first full sync); advance 60,000ms more; `shouldFullSync(false)` → `false` (a probe tick — stays cheap); advance 240,000ms more (300,000ms since the last `true`); `shouldFullSync(false)` | Final call returns `true` — `cadence.test.ts` › "then runs on the deploy interval, not every tick" |
| status-server-monitor-cadence-004 | manual-forces-full-sync, reanchor-on-true-result | Same cadence; `shouldFullSync(true)` called immediately at construction (still inside the 60,000ms boot grace) → `true`; advance 299,000ms; `shouldFullSync(false)` → `false`; advance 1,000ms more (300,000ms since the manual call); `shouldFullSync(false)` | The manual call returns `true` even during the boot grace window; the final automatic call returns `true` exactly 300,000ms after the manual call, not from the original boot anchor — `cadence.test.ts` › "a manual check-now forces a full sync and re-anchors the interval" |
| status-server-monitor-cadence-005 | anchor-unchanged-on-false-result | `createDeployCadence({deploySyncIntervalMs: 300_000, firstDelayMs: 60_000, now})`; call `shouldFullSync(false)` three times at clock offsets +10,000ms, +20,000ms, +30,000ms (each still inside the boot grace, each returns `false`); then advance to exactly +60,000ms and call `shouldFullSync(false)` | The fourth call returns `true` at +60,000ms, exactly the original boot anchor — the three intervening `false` calls did not push the anchor forward, confirming `anchor-unchanged-on-false-result` |
| status-server-monitor-cadence-006 | interval-and-delay-validation | `createDeployCadence({deploySyncIntervalMs: 0, firstDelayMs: 0, now})`; call `shouldFullSync(false)` three times in a row with the clock advanced by 1ms between each call | Every call returns `true`, including the second and third — a zero `deploySyncIntervalMs` collapses the cadence into "always full sync," reproducing the module's own crash-loop failure mode with no error or warning of any kind |
| status-server-monitor-cadence-007 | independent-per-call-state | Two independent calls, `createDeployCadence({deploySyncIntervalMs: 300_000, firstDelayMs: 60_000, now: clockA})` and `createDeployCadence({deploySyncIntervalMs: 300_000, firstDelayMs: 60_000, now: clockB})`, with `clockA` advanced to +60,000ms and `shouldFullSync(false)` called on the first cadence (returns `true`, re-anchoring it) while `clockB` stays at 0 | Calling `shouldFullSync(false)` on the SECOND cadence still returns `false` — the first cadence's re-anchor has no effect on the second's independent anchor |

## Edge Cases

- **Null and empty input**: Calling `shouldFullSync` with no argument at all treats `manual` as `undefined`, which is falsy, so the call is treated identically to `manual: false` — MUST (a fact of JavaScript truthiness, not a validated default). `opts.firstDelayMs` and `opts.now` explicitly passed as `null` are treated identically to being omitted, because both are read with the `??` nullish-coalescing operator, which falls through on `null` as well as `undefined` — MUST. `opts.deploySyncIntervalMs` passed as `undefined` produces `NaN` in the re-anchor arithmetic, which makes every subsequent comparison against the anchor evaluate to "already due" and collapses the cadence into returning `true` on every automatic call — MUST (see `interval-and-delay-validation`).
- **Boundary values**: `deploySyncIntervalMs` of `0` or a negative number collapses the recurring cadence into "always full sync" starting from the call that first re-anchors it — MUST, and see `interval-and-delay-validation` for why this is the one genuine gap in this file. `firstDelayMs` of exactly `0` is a legitimate, non-buggy boundary distinct from that case: it disables the boot grace entirely by design (the very first automatic call is treated as already due), which is a valid caller choice with no crash-loop implication of its own, since the recurring `deploySyncIntervalMs` interval — the value that actually protects the boot tick from repeating on every subsequent call — is unaffected — MUST.
- **Concurrent access**: Each `DeployCadence` returned by `createDeployCadence` closes over its own private anchor; no two instances ever share state, so concurrent use of two independently constructed cadences cannot interfere with each other — MUST. Within a single JavaScript thread, `shouldFullSync` performs no `await` and no asynchronous step between reading the clock and (conditionally) writing the anchor, so two calls into the SAME `DeployCadence` from that thread cannot interleave their reads and writes — this ordering is a fact of the single-threaded runtime, not a race requiring a lock — MUST. This file provides no synchronization primitive of its own and needs none for that reason.
- **Error states**: Not applicable — `cadence.ts` performs no network call, file I/O, or database access of any kind; it is pure arithmetic and comparison over a caller-supplied or default clock, so it has no dependency that can fail or return an error.
- **Offline or disconnected state**: Not applicable — this file has no network connectivity to lose; it decides only WHEN the deploy phase that later performs network I/O (provider polls, peer fetch, telemetry — all external to this file) is allowed to run, never whether that I/O succeeds.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.deploySyncIntervalMs` | `number` | none — required on every call | The recurring interval, in milliseconds, between allowed full syncs once the boot grace has passed. This file never reads an environment variable itself; the shipped caller (`config/port.ts`'s `deploySyncIntervalMs()` function, a different, external construct despite the identical name) derives this value from the `DEPLOY_SYNC_SECONDS` environment variable or a `max(300_000, 5 × probe interval)` default. |
| `opts.firstDelayMs` | `number \| undefined` | `FIRST_FULL_SYNC_DELAY_MS` (60,000) | Delay, in milliseconds, before the first automatic full sync after the `DeployCadence` is constructed (i.e. after process boot, for the shipped call site). |
| `opts.now` | `(() => number) \| undefined` | `Date.now` | Injectable clock, used by `cadence.test.ts` to drive time deterministically without real timers; production call sites never override it. |
| `FIRST_FULL_SYNC_DELAY_MS` (module constant) | `number` | `60_000` | Exported so callers and tests can reference the default first-delay value by name instead of repeating the literal. |

## Deep Linking

Not applicable: this file defines no application URL scheme, route, or navigable target of any kind — it returns a boolean scheduling decision to an in-process caller.

## Localization

Not applicable: this file contains no user-facing string of any kind — no rendered text, no error message, no log line — only numeric timestamps and a boolean return value.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; its only behavioral levers are the plain `opts` values passed to `createDeployCadence`, already documented under Configuration.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this file collects, stores, or transmits no data of any kind — its entire state is a single in-memory millisecond timestamp (the pending anchor) derived from a clock reading, never from user or credential data.

## Logging

Not applicable: this file contains no `console.*` call or structured-logger call of any kind; `shouldFullSync`'s boolean return value is the only signal it produces, and it is returned to the caller, never logged.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this cadence pattern would model `DeployCadence` as a small `Sendable` `struct` or `final class` wrapping a `Date` (or `ContinuousClock.Instant`) anchor, with `shouldFullSync(manual:)` as a method that mutates the anchor in place — Swift's value semantics make the "independent per construction, no shared state" requirement (`independent-per-call-state`) free for a `struct`, without needing the closure-over-private-variable trick this TypeScript file relies on.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the anchor as a `var` inside a small class instantiated per scheduler, using `Clock.System.now()` (kotlinx-datetime) or an injected `() -> Instant` lambda in place of the `now` parameter here, so tests can supply a fake clock the same way `cadence.test.ts` does.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/cadence.ts` as a plain factory function on the Node status backend, with no framework dependency of its own beyond the ambient `Date.now`. It is exported from the package's `index.ts` alongside `createScheduler` (`scheduler.ts`) precisely because the two are meant to be composed by the host: `scheduler.ts`'s `cycle` callback is expected to call `shouldFullSync(manual)` itself to decide the `fullSync` flag it passes into `runMonitorCycle` (`cycle-runner.ts`) — a composition this package's own given sources declare the intent for (via `index.ts`'s header comment and `scheduler.ts`'s `manual` parameter doc) but do not themselves perform.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no additional concern beyond what SwiftUI's bullet already covers; there is no per-thread module-duplication gotcha here the way there is for `alerts.ts`, because `createDeployCadence` is a factory that never relies on module-level singleton state.
- **WinUI 3**: a .NET port models `DeployCadence` as a small class (or a `readonly struct` holding a mutable field is not possible in C# without a wrapper, so a class is the natural fit) with a `bool ShouldFullSync(bool manual)` method and a `DateTimeOffset` (or `long` millisecond) anchor field, constructed via a factory taking `TimeSpan deploySyncInterval`, an optional `TimeSpan? firstDelay` defaulting to `TimeSpan.FromMinutes(1)`, and an optional `Func<DateTimeOffset>? now` defaulting to `() => DateTimeOffset.UtcNow` — mirroring the three `opts` fields exactly, including leaving `deploySyncInterval` non-optional to match `required-deploy-sync-interval`. The composition with a `System.Threading.Timer`-based scheduler (the WinUI 3 analogue of `scheduler.ts`) should call `ShouldFullSync` from that timer's callback to decide whether to run the heavy phase, exactly as `index.ts`'s header comment describes the intended `createScheduler` + `createDeployCadence` composition for this file's own host.

## Design Decisions

- **Decision**: compute the first pending anchor eagerly inside `createDeployCadence`, at construction time, rather than lazily on the first call to `shouldFullSync`.
  **Rationale**: the boot-grace window this file exists to guarantee is measured from when the process constructs its `DeployCadence` (i.e. from boot), not from whenever a caller happens to first invoke `shouldFullSync`. Computing the anchor lazily on first call would let a caller construct the cadence early and defer its first call, silently shrinking or growing the grace window relative to actual process boot time.
  **Approved**: pending
- **Decision**: a manual call re-anchors from that call's own clock reading (`now()`) plus `deploySyncIntervalMs`, not from whatever automatic anchor was already pending.
  **Rationale**: not spelled out in a comment on `shouldFullSync` itself, but demonstrated directly by `cadence.test.ts`'s "manual check-now" test — a user-triggered full sync pushes the NEXT automatic one a full interval into the future from the moment of that manual run, mirroring `scheduler.ts`'s own `runNow`/`runNowDetached`, which the source comment there says exist specifically to re-anchor the grid so "the next automatic tick is a full interval from now, rather than firing again moments after this manual run."
  **Approved**: pending
- **Decision**: re-anchor the pending time only when `shouldFullSync` returns `true`; never touch it on a `false` return.
  **Rationale**: not spelled out in a comment, but implied by the only two call sites in `shouldFullSync`'s body — a `false`-returning call has nothing to measure a new interval from, and anchoring on every call regardless of outcome would let a stream of ignored, cheap probe ticks perpetually push the deploy phase's due time forward, so the interval could never elapse under a probe cadence shorter than `deploySyncIntervalMs`.
  **Approved**: pending
- **Decision**: leave `deploySyncIntervalMs` and `firstDelayMs` unvalidated inside this file (see the `interval-and-delay-validation` marker under Behavioral Requirements).
  **Rationale**: this file trusts its caller's numbers rather than re-checking them itself. In the shipped composition, that trust is only partially earned: `config/port.ts`'s `deploySyncIntervalMs()` helper floors its output at 300,000ms via `Math.max`, which protects the one production call path this package ships — but nothing in `cadence.ts` itself enforces that floor for any other caller, which is exactly the gap the marker records.
  **Approved**: pending
- **Decision**: keep this recipe's Behavioral Requirements list shorter than a sibling like `status-server-monitor-alerts`.
  **Rationale**: `cadence.ts` is genuinely smaller in scope — one exported constant, one exported type, and one exported factory around roughly twenty lines of arithmetic and comparison, with no queue, no rendering, no network call, and no multi-thread module-duplication concern. The requirement count here is proportional to that smaller surface, not an authoring shortfall.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | failed | Reliability |

`unit-test-coverage` passes: `cadence.test.ts` exercises the boot-tick suppression, the boot-grace-to-first-sync transition, the recurring interval against a probe tick that must stay cheap, and the manual check-now's forced sync plus re-anchor, each with a deterministic injected clock. `separation-of-concerns` passes: this file's only concern is the timing decision itself — it performs no network I/O, no logging, and no knowledge of what a full sync actually does, leaving that entirely to `cycle-runner.ts` and the scheduler wiring described in `index.ts`'s header comment. `good-test-properties` passes: every test in `cadence.test.ts` drives an injected `now` function instead of real timers, making each test fast, isolated (a fresh cadence per test via the local `at()` helper), repeatable, and self-validating via plain `expect` assertions. `fault-tolerance` is `partial`: the code never throws or crashes on any input, including a zero, negative, or `undefined` `deploySyncIntervalMs` — but it also never rejects that input, so an unexpected state (a misconfigured caller) is tolerated in the sense of not crashing while producing the exact malfunction (`interval-and-delay-validation`) this file's own header comment says it exists to prevent; "doesn't crash" is satisfied, "handles unexpected input" is not. `health-observability` fails: `DeployCadence` exposes no way for any caller to read the pending anchor, when the last full sync happened, or why a given tick returned `false` — unlike `scheduler.ts`'s own `Scheduler` interface, which exposes `lastCycleAt`, `nextCycleAt`, and `cycleStale` for exactly this purpose, this file provides no equivalent observability surface of its own for a component consumed by a long-lived background process.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
