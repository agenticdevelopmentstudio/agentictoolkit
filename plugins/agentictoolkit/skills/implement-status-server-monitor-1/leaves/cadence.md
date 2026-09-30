<!-- leaf: implement-status-server-monitor-1/cadence · source: status-server-monitor-cadence.md -->

**Rules** (cite as `implement-status-server-monitor-1/cadence#<slug>`):

- `first-full-sync-delay-constant` MUST
- `deploy-cadence-interface-shape` MUST
- `required-deploy-sync-interval` MUST
- `first-delay-default` MUST
- `clock-default` MUST
- `initial-anchor-set-at-creation` MUST
- `manual-forces-full-sync` MUST
- `boot-grace-blocks-automatic-sync` MUST
- `automatic-sync-after-anchor-elapsed` MUST
- `reanchor-on-true-result` MUST
- `anchor-unchanged-on-false-result` MUST
- `independent-per-call-state` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.deploySyncIntervalMs` | `number` | none — required on every call | The recurring interval, in milliseconds, between allowed full syncs once the boot grace has passed. This file never reads an environment variable itself; the shipped caller (`config/port.ts`'s `deploySyncIntervalMs()` function, a different, external construct despite the identical name) derives this value from the `DEPLOY_SYNC_SECONDS` environment variable or a `max(300_000, 5 × probe interval)` default. |
| `opts.firstDelayMs` | `number \| undefined` | `FIRST_FULL_SYNC_DELAY_MS` (60,000) | Delay, in milliseconds, before the first automatic full sync after the `DeployCadence` is constructed (i.e. after process boot, for the shipped call site). |
| `opts.now` | `(() => number) \| undefined` | `Date.now` | Injectable clock, used by `cadence.test.ts` to drive time deterministically without real timers; production call sites never override it. |
| `FIRST_FULL_SYNC_DELAY_MS` (module constant) | `number` | `60_000` | Exported so callers and tests can reference the default first-delay value by name instead of repeating the literal. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this cadence pattern would model `DeployCadence` as a small `Sendable` `struct` or `final class` wrapping a `Date` (or `ContinuousClock.Instant`) anchor, with `shouldFullSync(manual:)` as a method that mutates the anchor in place — Swift's value semantics make the "independent per construction, no shared state" requirement (`independent-per-call-state`) free for a `struct`, without needing the closure-over-private-variable trick this TypeScript file relies on.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the anchor as a `var` inside a small class instantiated per scheduler, using `Clock.System.now()` (kotlinx-datetime) or an injected `() -> Instant` lambda in place of the `now` parameter here, so tests can supply a fake clock the same way `cadence.test.ts` does.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/cadence.ts` as a plain factory function on the Node status backend, with no framework dependency of its own beyond the ambient `Date.now`. It is exported from the package's `index.ts` alongside `createScheduler` (`scheduler.ts`) precisely because the two are meant to be composed by the host: `scheduler.ts`'s `cycle` callback is expected to call `shouldFullSync(manual)` itself to decide the `fullSync` flag it passes into `runMonitorCycle` (`cycle-runner.ts`) — a composition this package's own given sources declare the intent for (via `index.ts`'s header comment and `scheduler.ts`'s `manual` parameter doc) but do not themselves perform.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no additional concern beyond what SwiftUI's bullet already covers; there is no per-thread module-duplication gotcha here the way there is for `alerts.ts`, because `createDeployCadence` is a factory that never relies on module-level singleton state.
- **WinUI 3**: a .NET port models `DeployCadence` as a small class (or a `readonly struct` holding a mutable field is not possible in C# without a wrapper, so a class is the natural fit) with a `bool ShouldFullSync(bool manual)` method and a `DateTimeOffset` (or `long` millisecond) anchor field, constructed via a factory taking `TimeSpan deploySyncInterval`, an optional `TimeSpan? firstDelay` defaulting to `TimeSpan.FromMinutes(1)`, and an optional `Func<DateTimeOffset>? now` defaulting to `() => DateTimeOffset.UtcNow` — mirroring the three `opts` fields exactly, including leaving `deploySyncInterval` non-optional to match `required-deploy-sync-interval`. The composition with a `System.Threading.Timer`-based scheduler (the WinUI 3 analogue of `scheduler.ts`) should call `ShouldFullSync` from that timer's callback to decide whether to run the heavy phase, exactly as `index.ts`'s header comment describes the intended `createScheduler` + `createDeployCadence` composition for this file's own host.

