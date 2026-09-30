<!-- leaf: implement-status-web-src-lib-1/self-check · source: status-web-src-lib-self-check.md -->

**Rules** (cite as `implement-status-web-src-lib-1/self-check#<slug>`):

- `view-shape` MUST
- `issues-are-source-checks` MUST
- `undefined-input-null` MUST
- `nothing-to-show-null` MUST
- `non-null-when-content` MUST
- `missing-env-check-selection` MUST
- `missing-env-regardless-of-state` MUST
- `missing-env-flatten` MUST
- `missing-env-dedup` MUST
- `missing-env-order` MUST
- `missing-env-error-flag` MUST
- `missing-env-warn-not-error` MUST
- `issues-non-ok` MUST
- `issues-exclude-cron` MUST
- `issues-exclude-missing-env` MUST
- `issues-exclude-correlated` MUST
- `issues-order` MUST
- `issues-ignore-ok-flag` MUST
- `has-error-missing-env` MUST
- `has-error-issue` MUST
- `has-error-otherwise-false` MUST
- `excluded-errors-do-not-escalate` MUST
- `pure-synchronous` MUST
- `no-input-mutation` MUST
- `no-validation` MUST
- `thread-model` MUST

# Self-Check View Model

## Overview

`packages/web/packages/status-web/src/lib/self-check.ts` turns the status server's `/integrations` report (`IntegrationsResponse`) into the `SelfCheckView` that the `SelfCheckBanner` component renders. It exports:

- `SelfCheckView` — the view shape: `missingEnv`, `missingEnvError`, `issues`, `hasError`.
- `computeSelfCheck(data)` — the pure derivation. It returns `null` when there is nothing to show, "so the bar can render exactly when `computeSelfCheck(...) !== null`".

The doc comment says the function is "kept separate from the component so the (slightly fiddly) filtering rules are unit-tested without a DOM". Two consumers call it: `SelfCheckBanner.tsx`, which renders the bar, and `Dashboard.tsx`, which counts issues "the SAME way the SelfCheckBanner does ... so the pill and the bar never disagree".

Input types come from `src/types.ts`: `IntegrationsResponse` is `{ generatedAt: string; overall: CheckState; checks: IntegrationCheck[] }`, and `IntegrationCheck` carries `id`, `label`, `configured`, `ok`, `state: CheckState` (`"ok" | "warn" | "error"`), `detail`, and the optional `missingEnv?: string[]`, `unreachable?: boolean` and `correlated?: boolean`. The report itself is produced by the status server (see Status Server Monitor Integrations) and fetched by useIntegrations.

## Behavioral Requirements

**Data shape**

- **view-shape**: `SelfCheckView` MUST carry exactly four fields: `missingEnv: string[]`, `missingEnvError: boolean`, `issues: IntegrationCheck[]` and `hasError: boolean`.
- **issues-are-source-checks**: Each entry of `issues` MUST be the original `IntegrationCheck` object from `data.checks`, not a copy or projection.

**Null result**

- **undefined-input-null**: `computeSelfCheck` MUST return `null` when `data` is `undefined` (the loading state, per the test "returns null when data is undefined (loading)").
- **nothing-to-show-null**: `computeSelfCheck` MUST return `null` when, after filtering, `missingEnv` is empty and `issues` is empty.
- **non-null-when-content**: `computeSelfCheck` MUST return a `SelfCheckView` whenever `missingEnv` or `issues` is non-empty.

**Missing-env classification**

- **missing-env-check-selection**: A check MUST count as a missing-env check exactly when its `missingEnv` is present and has length greater than zero; an absent or empty `missingEnv` MUST NOT count.
- **missing-env-regardless-of-state**: A missing-env check MUST contribute its variable names whatever its `state` is, including `"ok"`.
- **missing-env-flatten**: `missingEnv` MUST contain every variable name from every missing-env check.
- **missing-env-dedup**: `missingEnv` MUST contain each variable name at most once.
- **missing-env-order**: `missingEnv` MUST keep first-occurrence order: checks in `data.checks` order, then names in each check's `missingEnv` order.
- **missing-env-error-flag**: `missingEnvError` MUST be `true` exactly when at least one missing-env check has `state === "error"`.
- **missing-env-warn-not-error**: A missing-env check with `state === "warn"` MUST NOT set `missingEnvError`; the doc comment says a "merely-recoverable missing env (a 'warn') keeps the bar amber so it doesn't cry wolf".

**Issue selection**

- **issues-non-ok**: `issues` MUST include only checks whose `state` is not `"ok"`.
- **issues-exclude-cron**: `issues` MUST exclude any check whose `id` is `"cron"` (the internal check, "wallboard noise").
- **issues-exclude-missing-env**: `issues` MUST exclude every missing-env check, so a check is never shown in both the env chip and an issue chip.
- **issues-exclude-correlated**: `issues` MUST exclude any check whose `correlated` is truthy, because the backend collapses those into its single Connectivity check.
- **issues-order**: `issues` MUST keep the order of `data.checks`.
- **issues-ignore-ok-flag**: Issue selection MUST read `state`, not the boolean `ok` field; a check with `ok: false` and `state: "ok"` MUST NOT be an issue.

**Severity**

- **has-error-missing-env**: `hasError` MUST be `true` when `missingEnvError` is `true`.
- **has-error-issue**: `hasError` MUST be `true` when any entry in `issues` has `state === "error"`.
- **has-error-otherwise-false**: `hasError` MUST be `false` in every other case; the source comment says severity "follows actual check state — never forced red just because a var is unset".
- **excluded-errors-do-not-escalate**: An errored check that is excluded from `issues` (a `cron` check or a `correlated` check) MUST NOT set `hasError`.

**Execution and side effects**

- **pure-synchronous**: `computeSelfCheck` MUST be a pure, synchronous function: same input, same output, no I/O, no network, no storage, no logging.
- **no-input-mutation**: `computeSelfCheck` MUST NOT modify `data`, `data.checks` or any check; it builds new arrays by filtering and flattening.
- **no-validation**: `computeSelfCheck` MUST NOT validate `data` at runtime; the `IntegrationsResponse | undefined` signature is the caller's precondition, so a defined `data` is assumed to carry a `checks` array.
- **thread-model**: `computeSelfCheck` MUST run synchronously on the caller's thread; single-threaded JavaScript leaves no interleaving to order.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` | `IntegrationsResponse \| undefined` | none (required argument) | The `/integrations` report; `undefined` means not yet loaded. |
| `"cron"` check id | string constant | `"cron"` | Hardcoded id excluded from `issues`; not configurable. |

The function reads no environment variables, settings or injected dependencies.

## Platform Notes

- **SwiftUI**: Model `SelfCheckView` as a `Sendable` struct and `computeSelfCheck` as a pure function returning `SelfCheckView?`. Deduplicate with an ordered approach (a `Set<String>` for seen names plus an `Array` for output, or `OrderedSet` from swift-collections), because `Set` alone loses the first-occurrence order that missing-env-order requires. The view calls it inside `body` or a computed property.
- **Compose**: A Kotlin `data class SelfCheckView` and a top-level function returning `SelfCheckView?`. `flatMap { it.missingEnv.orEmpty() }.distinct()` preserves first-occurrence order like JavaScript's `Set`. Treat `missingEnv.isNullOrEmpty()` as "no missing env" and `correlated == true` as the correlated test.
- **React/Web**: The source platform. `self-check.ts` is framework-free TypeScript; `new Set(...)` spread back into an array gives the insertion-ordered dedupe, and optional chaining with a truthy length test (`c.missingEnv?.length`) covers absent and empty lists. `SelfCheckBanner.tsx` and `Dashboard.tsx` both call it on the `useIntegrations` data, so the pill count and the bar share one rule set. Tests are in `self-check.test.ts` (Vitest).
- **AppKit / UIKit**: Same pure Swift function as the SwiftUI note; call it when the integrations report updates and reload the banner view from the result, or hide the banner on `nil`.
- **WinUI 3**: Implement `SelfCheckView` as a C# `record` (`IReadOnlyList<string> MissingEnv`, `bool MissingEnvError`, `IReadOnlyList<IntegrationCheck> Issues`, `bool HasError`) and `ComputeSelfCheck(IntegrationsResponse? data)` as a static method returning `SelfCheckView?`. Deserialize the report with `System.Text.Json` (`JsonSerializer.Deserialize<IntegrationsResponse>` with camelCase naming and `JsonStringEnumConverter` for `CheckState`); `MissingEnv` and `Correlated` map to `List<string>?` and `bool?`. Use LINQ `SelectMany(...).Distinct()`, which preserves first-occurrence order in practice, and `Where(...)` for issues. A view model implementing `INotifyPropertyChanged` recomputes the result when the report arrives (from an `HttpClient` fetch awaited with `Task`/`async`) and exposes a `bool IsBannerVisible` bound to the banner's `Visibility` (through a converter) or `InfoBar.IsOpen`. `hasError` maps to `InfoBarSeverity.Error` versus `InfoBarSeverity.Warning`. Unlike the source, C# nullable reference types make the null checks explicit.

## Design Decisions

**Decision**: Return `null` rather than an empty view when there is nothing to show.
**Rationale**: The doc comment states the bar "can render exactly when `computeSelfCheck(...) !== null`", giving the banner and the dashboard pill one visibility test.
**Approved**: pending

**Decision**: Severity follows each check's own `state`; an unset variable alone never forces red.
**Rationale**: The source comment "never forced red just because a var is unset" and the `SelfCheckView` doc say a recoverable missing env stays amber "so it doesn't cry wolf"; only an error-state check (for example one where the account could not auto-discover) goes red.
**Approved**: pending

**Decision**: Exclude the `cron` check, missing-env checks and `correlated` checks from `issues`.
**Rationale**: Per the `issues` doc comment, missing-env checks are already shown in the env chip, `cron` is "wallboard noise", and correlated provider failures are "collapsed into the backend's single Connectivity chip". The consequence, stated as excluded-errors-do-not-escalate, is that an errored excluded check cannot turn the bar red.
**Approved**: pending

**Decision**: Keep the filtering in a pure module separate from the component.
**Rationale**: The doc comment says the rules are "slightly fiddly" and are "unit-tested without a DOM"; `Dashboard.tsx` reuses the same function so its pill count matches the bar.
**Approved**: pending
