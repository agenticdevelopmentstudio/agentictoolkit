---
id: 4e32bf7a-b87a-44f6-aa16-f57a533e3b77
title: Status Server Monitor Self-Check Stability
domain: agentictoolkit://cookbook/status-server/monitor/self-check-stability
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Debounces unreachable self-check failures across repeated runs and correlates
  simultaneous confirmed failures into one Connectivity warning.
platforms:
- typescript
- web
tags:
- monitor
- self-check
- debounce
- correlation
- server
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/integrations
- agentictoolkit://cookbook/status-server/monitor/issue-sources
references:
- packages/web/packages/status-server/src/monitor/self-check-stability.ts (agentictoolkit)
- packages/web/packages/status-server/test/self-check-stability.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/integrations.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Self-Check Stability

## Overview

`self-check-stability.ts` (`packages/web/packages/status-server/src/monitor/self-check-stability.ts`) exports `createSelfCheckStabilizer`, a factory producing one `SelfCheckStabilizer` — an object with two methods, `stabilize(checks, nowMs?)` and `reset()` — that smooths the status monitor's self-check (`runIntegrationsCheck` in `./integrations.ts`, this file's sole consumer) across repeated runs. Per its own module doc comment, the pattern mirrors `nextPlatformStreak`'s debounce for platform-health issues (`./issue-sources.ts`): an `unreachable` failure — a probe that got NO HTTP response at all — is reported as healthy-with-a-note until it has persisted `CONFIRM_RUNS` (2) consecutive `stabilize` calls spanning `CONFIRM_WINDOW_MS` (90,000ms), so a momentary egress blip on the monitor's own side never reaches the error bar. A failure that DID get an HTTP response (401/5xx — an invalid token and the like) passes through untouched, because that is real and actionable, never debounced. Recovery is never debounced either — one call in which a check is no longer both `unreachable` and in an `"error"` state clears its streak immediately. When several ids are confirmed-unreachable within the SAME `stabilize` call, `CORRELATED_MIN` (2) or more, the outage is treated as monitor-side connectivity rather than independent provider outages: each confirmed check is downgraded to a `"warn"`, `correlated: true` entry, and one synthetic `connectivity` check is appended naming the real suspect, so the integrations panel shows a single amber chip instead of a wall of red provider errors.

## Behavioral Requirements

### Constants and Type Shape

- **confirm-runs-constant**: The module MUST export `CONFIRM_RUNS` with the value `2` — the minimum number of consecutive debounce-eligible failing calls required before an unreachable-kind failure can be confirmed.
- **confirm-window-constant**: The module MUST export `CONFIRM_WINDOW_MS` with the value `90_000` (90,000 milliseconds) — the minimum wall-clock span, measured from a failure streak's first failing call, that must also have elapsed before confirmation.
- **correlated-min-constant**: The module MUST export `CORRELATED_MIN` with the value `2` — the minimum number of ids confirmed within one `stabilize` call at which they are treated as monitor-side connectivity rather than independent provider outages.
- **self-check-stabilizer-shape**: The `SelfCheckStabilizer` interface MUST declare exactly two members — `stabilize(checks: IntegrationCheck[], nowMs?: number): IntegrationCheck[]` and `reset(): void` — and MUST declare no other property or method.

### Construction (`createSelfCheckStabilizer`)

- **stateless-construction**: `createSelfCheckStabilizer` MUST accept no arguments and MUST return a `SelfCheckStabilizer` whose internal failure-tracking map (keyed by check `id`, each entry a `runs`/`firstFailedAtMs` pair) starts empty — no id is treated as failing immediately after construction.
- **independent-per-call-state**: Each call to `createSelfCheckStabilizer` MUST produce a `SelfCheckStabilizer` with its own private failure-tracking map, closed over by the returned object; two separately constructed stabilizers MUST NOT share tracking state, and neither exposes any way to read or set an id's tracked run count or first-failed time other than through `stabilize`'s return value.

### Debounce Decision (`stabilize`)

- **default-clock-per-call**: `stabilize` MUST use its `nowMs` argument when the caller supplies one, and MUST otherwise evaluate `Date.now()` at the moment of that call, as the current time used for every timing decision inside that call.
- **debounce-eligibility**: `stabilize` MUST apply the confirmation logic below to a check only when that check's `unreachable` is `true` AND its `state` is `"error"`; every check for which that conjunction is false — a healthy check, a warn-level check, or a definitive HTTP-style error check whose `unreachable` is not `true` — MUST be returned as the identical object it received, unmodified.
- **recovery-clears-streak**: whenever a check id is passed to `stabilize` in a call where debounce-eligibility is false for that id, `stabilize` MUST delete that id's entry from the failure-tracking map (a no-op if no entry exists), so a later debounce-eligible failure for the same id begins a new streak.
- **streak-continuation**: for a debounce-eligible check whose id already has a tracked entry, `stabilize` MUST replace that entry with one whose run count is the previous entry's run count plus `1` and whose first-failed time is carried over unchanged from the previous entry; for a debounce-eligible check with no existing entry, `stabilize` MUST create an entry with a run count of `1` and the first-failed time set to that call's resolved `nowMs`.
- **confirmation-threshold**: a debounce-eligible check MUST be treated as confirmed in a given call, and returned as the identical object it received, only when its tracked run count is at least `CONFIRM_RUNS` (`2`) AND the call's resolved `nowMs` minus its tracked first-failed time is at least `CONFIRM_WINDOW_MS` (`90_000`); meeting only one of the two conditions MUST NOT confirm it.
- **suppressed-output-shape**: a debounce-eligible check that does not meet confirmation-threshold MUST be replaced in the output with a new object that shallow-copies every own property of the input check, then overrides `ok` to `true`, `state` to `"ok"`, and `detail` to the literal string `"recheck pending — "` immediately followed by the input check's original `detail` value; the copy MUST retain `unreachable: true` and any `missingEnv` carried on the input.
- **output-array-shape-below-correlation**: for any `stabilize` call whose confirmed-id count is below `CORRELATED_MIN`, the returned array MUST contain exactly one entry per input check, in the same order as the input `checks` array, with no entry added or removed.

### Correlation (`stabilize`)

- **correlated-downgrade**: when the number of ids confirmed within one `stabilize` call is at least `CORRELATED_MIN` (`2`), `stabilize` MUST, for every check whose id is in that call's confirmed set, replace it with a new object that shallow-copies its own properties, then overrides `state` to `"warn"` and sets `correlated` to `true`, leaving `ok`, `detail`, and `unreachable` exactly as they were.
- **synthetic-connectivity-check**: whenever correlated-downgrade applies, `stabilize` MUST append exactly one further object to the end of the returned array, after every input-derived entry, with `id: "connectivity"`, `label: "Connectivity"`, `configured: true`, `ok: false`, `state: "warn"`, and `detail` equal to the confirmed count followed by the literal text `" providers unreachable at once — likely monitor-side connectivity, not provider outages"`.
- **non-confirmed-ids-unaffected-by-correlation**: when correlated-downgrade applies, every returned entry whose id is NOT in that call's confirmed set MUST be exactly the value it already held before the correlation step ran — its debounce-eligible suppressed form, its unmodified pass-through, or an unconfirmed non-debounced value.

### Reset (`reset`)

- **reset-clears-all-streaks**: `reset()` MUST discard every entry in the failure-tracking map, MUST accept no arguments, and MUST return no value; the first debounce-eligible failure for any id passed to `stabilize` after a `reset()` call MUST be treated as a fresh streak (a run count of `1`, first-failed time set to that call's resolved `nowMs`), exactly as if that id had never failed before.

## Appearance

Not applicable — this is a cross-run debounce and correlation function for a self-check report, not a visual component.

## States

Not applicable — this is a cross-run debounce and correlation function for a self-check report, not a visual component; its runtime states (a per-id failure streak in progress, confirmed, or correlated) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a cross-run debounce and correlation function for a self-check report, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-self-check-stability-001 | debounce-eligibility, streak-continuation, suppressed-output-shape | `stabilize([unreachable("vercel")], T0)` on a fresh stabilizer | Returned check has `state === "ok"`, `ok === true`, `detail === "recheck pending — This operation was aborted"` — `self-check-stability.test.ts` › "suppresses a first-run unreachable failure (blip stays off the bar)" |
| status-server-monitor-self-check-stability-002 | confirmation-threshold | Same stabilizer; second call `stabilize([unreachable("vercel")], T0 + 5_000)` (run count now 2, elapsed only 5,000ms) | Returned check still has `state === "ok"` — the run-count condition is met but the wall-clock condition is not, so confirmation-threshold correctly withholds confirmation — `self-check-stability.test.ts` › "keeps suppressing while the failure has not spanned the confirmation window" |
| status-server-monitor-self-check-stability-003 | confirmation-threshold, output-array-shape-below-correlation | `stabilize([unreachable("vercel"), reachable("railway")], T0)` then `stabilize([unreachable("vercel"), reachable("railway")], T0 + CONFIRM_WINDOW_MS + 1_000)` | The vercel entry has `state === "error"` and `correlated === undefined`; no `connectivity` entry is present, because only one id is confirmed and `CORRELATED_MIN` is `2` — `self-check-stability.test.ts` › "confirms a single provider that stays unreachable across runs AND the window — red" |
| status-server-monitor-self-check-stability-004 | recovery-clears-streak | `stabilize([unreachable("vercel")], T0)`; `stabilize([reachable("vercel")], T0 + 60_000)`; `stabilize([unreachable("vercel")], T0 + CONFIRM_WINDOW_MS + 61_000)` | The third call's returned check has `state === "ok"` — the intervening reachable call cleared the streak, so the third failing call is a fresh streak, not a continuation — `self-check-stability.test.ts` › "a good run resets the streak — fail/recover/fail is two separate blips" |
| status-server-monitor-self-check-stability-005 | correlated-downgrade, synthetic-connectivity-check | `stabilize([unreachable("cloudflare"), unreachable("posthog")], T0)` then the same input at `T0 + CONFIRM_WINDOW_MS + 1_000` | Both `cloudflare` and `posthog` entries have `state === "warn"` and `correlated === true`; a `connectivity` entry exists with `state === "warn"` and `detail` containing `2 providers unreachable at once` — `self-check-stability.test.ts` › "correlates simultaneous confirmed failures as monitor-side — amber, one Connectivity chip" |
| status-server-monitor-self-check-stability-006 | debounce-eligibility | `stabilize([httpError("vercel")], T0)` on a fresh stabilizer, where the input's `unreachable` is not set | Returned check has `state === "error"` and `detail === "HTTP 401 — token invalid"`, unchanged from the input — never routed through the debounce path because `unreachable` is falsy — `self-check-stability.test.ts` › "passes real HTTP errors through untouched — token-invalid surfaces immediately" |
| status-server-monitor-self-check-stability-007 | debounce-eligibility | `stabilize([warnCheck], T0)` where `warnCheck.state === "warn"` and `warnCheck.unreachable` is unset | The returned check deep-equals the input object exactly — `self-check-stability.test.ts` › "passes warn-level checks (missing env, freshness) through untouched" |
| status-server-monitor-self-check-stability-008 | output-array-shape-below-correlation | `stabilize([], T0)` on a fresh stabilizer | Returns `[]` — traced directly to the map over an empty input array producing an empty output, with a confirmed count of `0` below `CORRELATED_MIN`, so no `connectivity` entry is appended; not exercised by a dedicated assertion in the given test file |
| status-server-monitor-self-check-stability-009 | reset-clears-all-streaks | `stabilize([unreachable("vercel")], T0)` (run count 1); `reset()`; `stabilize([unreachable("vercel")], T0 + CONFIRM_WINDOW_MS + 1_000)` | The final call's returned check still has `state === "ok"` — `reset()` discarded the tracked streak, so the call after it is a fresh run-count-1 streak despite the elapsed time exceeding `CONFIRM_WINDOW_MS` — traced directly to `reset`'s map-clearing body; not exercised by a dedicated assertion in the given test file |
| status-server-monitor-self-check-stability-010 | confirm-runs-constant, confirm-window-constant, correlated-min-constant | Import `CONFIRM_RUNS`, `CONFIRM_WINDOW_MS`, and `CORRELATED_MIN` from the module | Values equal `2`, `90_000`, and `2` respectively — traced directly to the module's exported constant declarations; `self-check-stability.test.ts` imports `CONFIRM_WINDOW_MS` and `CORRELATED_MIN` directly and uses them to compute its own test offsets and assertions (vectors 002, 003, 005), which is possible only because these constants hold the stated values |
| status-server-monitor-self-check-stability-011 | stateless-construction, independent-per-call-state | Call `createSelfCheckStabilizer()` twice, producing `sA` and `sB`; drive `sA` through a debounce-eligible failure so its tracked run count reaches 2, while never calling `stabilize` on `sB` | `sB.stabilize([unreachable("vercel")], anyNowMs)` still returns a fresh, unconfirmed (`state: "ok"`) result at run count 1 — `sA`'s tracked state has no effect on `sB` — traced directly to each call to `createSelfCheckStabilizer` creating its own failure-tracking map; not exercised by a dedicated assertion in the given test file, since every `it` block in `self-check-stability.test.ts` constructs exactly one stabilizer |
| status-server-monitor-self-check-stability-012 | self-check-stabilizer-shape | Inspect the object returned by `createSelfCheckStabilizer()` | `typeof stabilizer.stabilize === "function"` and `typeof stabilizer.reset === "function"` — traced directly to the object literal returned by `createSelfCheckStabilizer`, which declares exactly these two properties and no other |

## Edge Cases

- **Null and empty input**: `stabilize([], nowMs)` returns `[]` with no synthetic `connectivity` entry, since a confirmed count of `0` is below `CORRELATED_MIN` — MUST (see status-server-monitor-self-check-stability-008). A check whose `detail` is an empty string is preserved as-is by suppressed-output-shape, producing `detail: "recheck pending — "` with nothing after the dash — MUST, a direct consequence of plain string concatenation.
- **Boundary values**: a tracked run count of exactly `CONFIRM_RUNS` (2) together with an elapsed time of exactly `CONFIRM_WINDOW_MS` (90,000ms) or more confirms the failure; a run count one short, or the same two runs closer together than 90,000ms, leaves it suppressed — MUST (confirmation-threshold uses `>=` on both sides). A confirmed count of exactly `CORRELATED_MIN` (2) triggers correlated-downgrade and the synthetic check; a confirmed count of exactly `1` never does, staying a single uncorrelated red error — MUST.
- **Concurrent access**: `stabilize` performs no `await` and no asynchronous step between reading and writing the failure-tracking map, so within a single JavaScript thread two calls into the SAME `SelfCheckStabilizer` cannot interleave their reads and writes — this ordering is a fact of the single-threaded runtime, not a race requiring a lock, and this file provides no synchronization primitive of its own for that reason — MUST. This file's factory produces one independent, non-shared map per call (independent-per-call-state); the actual production topology — one `SelfCheckStabilizer` constructed exactly once at module scope in `integrations.ts` and shared by every `/integrations` request for the life of the process — is a fact about that OTHER file's wiring, external to this one, and is documented on `status-server-monitor-integrations` rather than repeated here. A `checks` array that names the SAME `id` more than once within one call is not guarded against: the second occurrence's tracked-entry read observes the write the first occurrence already made earlier in the same synchronous pass, so a duplicate id inflates its run count by 2 in one call instead of 1 — a direct, deterministic consequence of the map being written imperatively inside a single left-to-right pass, not a race. No given call site produces a duplicate id: the one production caller (`integrations.ts`) always supplies seven statically distinct ids (`stats`, `cron`, `vercel`, `cloudflare`, `railway`, `glitchtip`, `posthog`).
- **Error states**: Not applicable — this file performs no network call, file I/O, or database access of any kind, and its own body contains no `throw` and no `try`/`catch`; it is a total function over an already-computed `IntegrationCheck[]` and a numeric clock reading, with no dependency of its own that can fail or return an error.
- **Offline or disconnected state**: Not applicable — this file has no network connectivity of its own to lose; it consumes only the already-decided `unreachable` outcome of network probes performed elsewhere (`integrations.ts`'s provider checks), and decides nothing about whether those probes themselves succeed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `checks` (parameter of `stabilize`) | `IntegrationCheck[]` | none — required on every call | The current run's per-provider results; each entry's `id` is treated as its own independent debounce identity across calls. |
| `nowMs` (parameter of `stabilize`) | `number \| undefined` | `Date.now()` | The current time used for streak arithmetic and the `CONFIRM_WINDOW_MS` comparison; the sole production caller (`integrations.ts`'s `runIntegrationsCheck`) forwards its own `nowMs` argument here unchanged. |
| `CONFIRM_RUNS` (module constant) | `number` | `2` | Not configurable at runtime — a compile-time constant; changing the debounce run count requires editing the source. |
| `CONFIRM_WINDOW_MS` (module constant) | `number` | `90_000` | Same as above, for the wall-clock span. |
| `CORRELATED_MIN` (module constant) | `number` | `2` | Same as above, for the correlation threshold. |

`createSelfCheckStabilizer()` itself takes no configuration of any kind — its entire tunable surface is the three module constants above plus the two `stabilize` parameters.

## Deep Linking

Not applicable: this file defines no application URL scheme, route, or navigable target of any kind — it is a pure function over already-computed check results, returned to its in-process caller.

## Localization

This file uses no localization mechanism; it produces two hardcoded English string fragments that become part of an `IntegrationCheck`'s `detail` value returned in the `/integrations` API response and rendered on the integrations panel for any authenticated user — a user-facing string, not a server log line.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — recheck pending prefix | `recheck pending — <original detail>` | Prepended by suppressed-output-shape whenever a debounce-eligible failure has not yet met confirmation-threshold; `<original detail>` is the input check's own `detail`, produced elsewhere (e.g. `integrations.ts`'s provider checks). |
| n/a — connectivity detail | `<n> providers unreachable at once — likely monitor-side connectivity, not provider outages` | The synthetic `connectivity` check's `detail`, whenever correlated-downgrade applies; `<n>` is the confirmed count. |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; its only behavioral levers are `CONFIRM_RUNS`, `CONFIRM_WINDOW_MS`, and `CORRELATED_MIN`, already documented under Configuration, none of which is read from a flag service.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only output is the `IntegrationCheck[]` array it returns to its caller.

## Privacy

Not applicable: this file collects, stores, or transmits no credential or user data of any kind — it retains only an in-memory failure-tracking map keyed by check `id` (a fixed provider name) holding a run count and a millisecond timestamp, and it passes through or rewraps each check's own `label`/`detail` text without ever inspecting it for sensitive content; any credential a check's `detail` might incidentally reference originates and is handled entirely outside this file, in the calling package's own provider checks.

## Logging

Not applicable: this file contains no `console.*` call or structured-logger call of any kind; `stabilize`'s array return value is its only signal, consumed entirely by its in-process caller.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this pattern would model the failure-tracking entry as a small `struct FailTrack { var runs: Int; var firstFailedAtMs: Int64 }`, held in a `[String: FailTrack]` dictionary inside a type conforming to a `SelfCheckStabilizer` protocol (`func stabilize(_ checks: [IntegrationCheck], now: Int64) -> [IntegrationCheck]`, `func reset()`); Swift's value semantics make independent-per-call-state free for a `struct`-backed implementation constructed per caller, the same way `createSelfCheckStabilizer`'s closure gives each call its own map.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the tracking store as a `MutableMap<String, FailTrack>` (a small `data class FailTrack(val runs: Int, val firstFailedAtMs: Long)`) inside a class implementing the equivalent interface, using `Clock.System.now()` (kotlinx-datetime) or an injected `() -> Instant` in place of the `nowMs` parameter here so tests can drive time deterministically the way `self-check-stability.test.ts` does with its own `T0`/`LATER` constants.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/self-check-stability.ts` as a plain factory function on the Node status backend, with no framework dependency of its own. `integrations.ts` is its only consumer, constructing one `SelfCheckStabilizer` at module scope and forwarding it the same `checks` array and `nowMs` value `runIntegrationsCheck` itself received or defaulted.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern for a shared, multi-threaded caller (unlike this file's single-threaded Node runtime) would prefer wrapping the tracking dictionary in a Swift `actor` rather than a plain `struct`/`class`, giving every caller on any thread the same serialized access this file gets for free from the Node event loop.
- **WinUI 3**: a .NET port models `SelfCheckStabilizer` as a class implementing an interface with `IReadOnlyList<IntegrationCheck> Stabilize(IReadOnlyList<IntegrationCheck> checks, DateTimeOffset? now = null)` and `void Reset()`, backed by a `Dictionary<string, FailTrack>` where `FailTrack` is a `readonly record struct FailTrack(int Runs, long FirstFailedAtMs)` — mirroring the run-count-and-timestamp pair this file tracks per id. `Stabilize` defaults its `now` parameter to `DateTimeOffset.UtcNow` exactly as this file defaults `nowMs` to `Date.now()`. If a WinUI process's UI thread and a background polling `Task` might call `Stabilize` concurrently — a real possibility this file's single-threaded Node runtime never has to consider — the backing dictionary should be a `ConcurrentDictionary<string, FailTrack>` with the read-increment-write sequence performed under a `lock` (or via `AddOrUpdate`'s atomic update delegate), since C# offers no run-to-completion guarantee equivalent to the event loop this file relies on implicitly. `CONFIRM_RUNS`, `CONFIRM_WINDOW_MS`, and `CORRELATED_MIN` port as `public const int`/`public static readonly TimeSpan` fields on the same class, exactly as this file exports them as top-level constants.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/self-check-stability.ts` |

## Design Decisions

- **Decision**: confirm a failure only when both the run count AND the wall-clock window are satisfied, rather than either alone.
  **Rationale**: stated directly in the module's own doc comment — "the check runs on demand (every /integrations request), so a run count alone could be satisfied by two polls seconds apart inside one blip — the failure must also span real time."
  **Approved**: pending
- **Decision**: make recovery immediate (a single non-debounce-eligible run clears the streak) while confirmation is debounced across `CONFIRM_RUNS` runs and `CONFIRM_WINDOW_MS`.
  **Rationale**: stated directly in the module's own doc comment — "Recovery is not debounced — one good run clears the streak." Demonstrated by status-server-monitor-self-check-stability-004.
  **Approved**: pending
- **Decision**: correlate simultaneous confirmed failures into one synthetic Connectivity warning instead of leaving each provider red.
  **Rationale**: stated directly in the module's own doc comment — "When several providers are confirmed-unreachable in the SAME run, the outage is almost certainly ours, not theirs... a single synthetic Connectivity check names the real suspect, so the banner shows one amber chip instead of a wall of red provider errors." Demonstrated by status-server-monitor-self-check-stability-005.
  **Approved**: pending
- **Decision**: leave duplicate ids within one `checks` array unvalidated and unguarded.
  **Rationale**: not stated in an inline comment; the one production caller (`integrations.ts`) always supplies seven statically distinct ids, so no shipped call site can trigger the duplicate-id, sequential-double-counting fact recorded under Edge Cases. Recorded here per source fidelity as fact, not endorsement.
  **Approved**: pending
- **Decision**: keep this recipe's own Behavioral Requirements scoped to `self-check-stability.ts`'s contract, and cross-reference — rather than repeat — how `status-server-monitor-integrations` wires and shares one instance of it.
  **Rationale**: `self-check-stability.ts` is a small, self-contained factory (three constants, one factory function, roughly forty lines); the module-level-singleton topology that shares one `SelfCheckStabilizer` across every `/integrations` request belongs to `integrations.ts`'s own wiring and is already documented on `status-server-monitor-integrations` under its "Cross-Run Stabilization" section, so restating it here would let the two recipes drift out of sync on the same fact.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | failed | Reliability |

`unit-test-coverage` passes: `self-check-stability.test.ts` exercises first-run suppression, window-not-yet-elapsed suppression, single-provider confirmation, recovery-resets-the-streak, correlated multi-provider downgrade, real-HTTP-error passthrough, and warn-level passthrough — seven `it` blocks covering every branch except the empty-array, `reset()`, and multi-instance-independence facts this recipe traces directly to source (status-server-monitor-self-check-stability-008, -009, -011). `separation-of-concerns` passes: this file's only concern is cross-run debounce and correlation arithmetic over an already-computed `IntegrationCheck[]`; it performs no network I/O, no probing, and has no knowledge of what a provider check actually does, leaving that entirely to its sole consumer, `integrations.ts`. `good-test-properties` passes: every test in `self-check-stability.test.ts` drives an explicit `nowMs` argument instead of real timers, constructs a fresh stabilizer per `it` block via its own `createSelfCheckStabilizer()` call, and asserts with plain `expect` calls against concrete return values — fast, isolated, repeatable, and self-validating. `fault-tolerance` passes: the function is total over any well-typed `IntegrationCheck[]` input, including an empty array and, per the recorded Design Decision, a duplicate id — it never throws and never crashes on any input this recipe or its test file exercises. `health-observability` fails: `SelfCheckStabilizer` exposes no way for any caller to read a given id's current run count, its first-failed time, or how close it is to confirmation — a long-lived process using this stabilizer has no observability into a pending streak other than by waiting for `stabilize`'s own suppressed or confirmed output to change.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
