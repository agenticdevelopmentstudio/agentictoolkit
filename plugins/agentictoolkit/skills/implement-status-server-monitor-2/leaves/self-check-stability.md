<!-- leaf: implement-status-server-monitor-2/self-check-stability · source: status-server-monitor-self-check-stability.md -->

**Rules** (cite as `implement-status-server-monitor-2/self-check-stability#<slug>`):

- `confirm-runs-constant` MUST
- `confirm-window-constant` MUST
- `correlated-min-constant` MUST
- `self-check-stabilizer-shape` MUST
- `stateless-construction` MUST
- `independent-per-call-state` MUST
- `default-clock-per-call` MUST
- `debounce-eligibility` MUST
- `recovery-clears-streak` MUST
- `streak-continuation` MUST
- `confirmation-threshold` MUST
- `suppressed-output-shape` MUST
- `output-array-shape-below-correlation` MUST
- `correlated-downgrade` MUST
- `synthetic-connectivity-check` MUST
- `non-confirmed-ids-unaffected-by-correlation` MUST
- `reset-clears-all-streaks` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `checks` (parameter of `stabilize`) | `IntegrationCheck[]` | none — required on every call | The current run's per-provider results; each entry's `id` is treated as its own independent debounce identity across calls. |
| `nowMs` (parameter of `stabilize`) | `number \| undefined` | `Date.now()` | The current time used for streak arithmetic and the `CONFIRM_WINDOW_MS` comparison; the sole production caller (`integrations.ts`'s `runIntegrationsCheck`) forwards its own `nowMs` argument here unchanged. |
| `CONFIRM_RUNS` (module constant) | `number` | `2` | Not configurable at runtime — a compile-time constant; changing the debounce run count requires editing the source. |
| `CONFIRM_WINDOW_MS` (module constant) | `number` | `90_000` | Same as above, for the wall-clock span. |
| `CORRELATED_MIN` (module constant) | `number` | `2` | Same as above, for the correlation threshold. |

`createSelfCheckStabilizer()` itself takes no configuration of any kind — its entire tunable surface is the three module constants above plus the two `stabilize` parameters.

## Localization

This file uses no localization mechanism; it produces two hardcoded English string fragments that become part of an `IntegrationCheck`'s `detail` value returned in the `/integrations` API response and rendered on the integrations panel for any authenticated user — a user-facing string, not a server log line.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — recheck pending prefix | `recheck pending — <original detail>` | Prepended by suppressed-output-shape whenever a debounce-eligible failure has not yet met confirmation-threshold; `<original detail>` is the input check's own `detail`, produced elsewhere (e.g. `integrations.ts`'s provider checks). |
| n/a — connectivity detail | `<n> providers unreachable at once — likely monitor-side connectivity, not provider outages` | The synthetic `connectivity` check's `detail`, whenever correlated-downgrade applies; `<n>` is the confirmed count. |

