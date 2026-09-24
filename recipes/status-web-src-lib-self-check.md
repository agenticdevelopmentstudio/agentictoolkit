---
id: 85301350-d3d3-4b0d-a2f7-b13936d9ddf6
title: Self-Check View Model
domain: agentictoolkit://recipes/status-web-src-lib-self-check
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure view-model that derives the status board's self-check error bar (missing
  env vars, issue chips, severity) from the /integrations report.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-integrations
- agentictoolkit://recipes/status-server-monitor-integrations
references: []
approved-by: ''
approved-date: ''
---

# Self-Check View Model

## Overview

`packages/web/packages/status-web/src/lib/self-check.ts` turns the status server's `/integrations` report (`IntegrationsResponse`) into the `SelfCheckView` that the `SelfCheckBanner` component renders. It exports:

- `SelfCheckView` — the view shape: `missingEnv`, `missingEnvError`, `issues`, `hasError`.
- `computeSelfCheck(data)` — the pure derivation. It returns `null` when there is nothing to show, "so the bar can render exactly when `computeSelfCheck(...) !== null`".

The doc comment says the function is "kept separate from the component so the (slightly fiddly) filtering rules are unit-tested without a DOM". Two consumers call it: `SelfCheckBanner.tsx`, which renders the bar, and `Dashboard.tsx`, which counts issues "the SAME way the SelfCheckBanner does ... so the pill and the bar never disagree".

Input types come from `src/types.ts`: `IntegrationsResponse` is `{ generatedAt: string; overall: CheckState; checks: IntegrationCheck[] }`, and `IntegrationCheck` carries `id`, `label`, `configured`, `ok`, `state: CheckState` (`"ok" | "warn" | "error"`), `detail`, and the optional `missingEnv?: string[]`, `unreachable?: boolean` and `correlated?: boolean`. The report itself is produced by the status server (see [Status Server Monitor Integrations](agentictoolkit://recipes/status-server-monitor-integrations)) and fetched by [useIntegrations](agentictoolkit://recipes/status-web-hooks-use-integrations).

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

## Appearance

Not applicable — this is a pure view-model function, not a visual component.

## States

Not applicable — this is a pure view-model function, not a visual component.

## Accessibility

Not applicable — this is a pure view-model function, not a visual component.

## Conformance Test Vectors

Checks below default to `configured: true`, `ok: true`, `state: "ok"`, `detail: ""`, as the test fixture `check(...)` in `self-check.test.ts` does.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| self-check-001 | undefined-input-null | `computeSelfCheck(undefined)` | `null` |
| self-check-002 | nothing-to-show-null | checks `stats` and `vercel`, both `state: "ok"` | `null` |
| self-check-003 | missing-env-flatten, missing-env-dedup, missing-env-order, missing-env-warn-not-error, issues-exclude-missing-env, has-error-otherwise-false | `cloudflare` warn missingEnv `["CLOUDFLARE_ACCOUNT_ID"]`; `vercel` warn missingEnv `["VERCEL_API_TOKEN"]`; `railway` warn missingEnv `["VERCEL_API_TOKEN"]` | `missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID", "VERCEL_API_TOKEN"]`; `missingEnvError` false; `hasError` false; `issues` empty |
| self-check-004 | missing-env-error-flag, has-error-missing-env, issues-exclude-missing-env | `cloudflare` `state: "error"` missingEnv `["CLOUDFLARE_ACCOUNT_ID"]` | `missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID"]`; `missingEnvError` true; `hasError` true; `issues` empty |
| self-check-005 | issues-exclude-cron, has-error-issue, non-null-when-content | `cron` warn "first poll pending"; `railway` `state: "error"` "HTTP 500" | `missingEnv` empty; issue ids `["railway"]`; `hasError` true |
| self-check-006 | issues-exclude-correlated, excluded-errors-do-not-escalate | `cloudflare` warn correlated; `posthog` warn correlated; `connectivity` warn | issue ids `["connectivity"]`; `hasError` false |
| self-check-007 | issues-non-ok, has-error-otherwise-false | `railway` warn "slow" | issue ids `["railway"]`; `hasError` false |
| self-check-008 | missing-env-check-selection | `vercel` warn with `missingEnv: []` | `missingEnv` empty; issue ids `["vercel"]` (an empty list does not make it a missing-env check) |
| self-check-009 | missing-env-regardless-of-state, nothing-to-show-null | `stats` `state: "ok"` missingEnv `["X"]` | non-null view; `missingEnv` equals `["X"]`; `missingEnvError` false; `hasError` false; `issues` empty |
| self-check-010 | excluded-errors-do-not-escalate | `cron` `state: "error"` only | `null` |
| self-check-011 | issues-ignore-ok-flag | `stats` with `ok: false`, `state: "ok"` | `null` |
| self-check-012 | issues-order, issues-are-source-checks | `b` error, `a` warn, in that order | issue ids `["b", "a"]`; each entry is the same object reference passed in |
| self-check-013 | no-input-mutation, pure-synchronous | any report, called twice | both results deep-equal; `data.checks` unchanged in length and content |

Vectors 001 to 007 are the assertions of `self-check.test.ts`; 008 to 013 follow directly from the filter expressions in `computeSelfCheck`.

## Edge Cases

- **Undefined report**: `data` is `undefined` while the fetch is loading. `computeSelfCheck` MUST return `null` (vector 001).
- **Empty checks array**: `data.checks` is `[]`. Both lists are empty, so the function MUST return `null`.
- **Empty `missingEnv` array**: a check with `missingEnv: []` MUST be treated as having no missing env and MAY appear in `issues` if its state is not `"ok"` (vector 008).
- **Missing env on an ok check**: a check with `state: "ok"` and a non-empty `missingEnv` MUST still produce a non-null view with that name in `missingEnv` (vector 009).
- **Duplicate names within one check**: a check with `missingEnv: ["A", "A"]` MUST yield `["A"]`, because deduplication covers the whole flattened list.
- **Correlated check that also lists missing env**: it MUST contribute its names to `missingEnv`, since missing-env selection does not look at `correlated`.
- **Errored cron or correlated check alone**: MUST produce `null` and MUST NOT turn the bar red (vector 010).
- **`missingEnvError` implies non-null**: `missingEnvError` can only be `true` when `missingEnv` is non-empty, so a returned view with `missingEnvError: true` MUST have at least one name.
- **Malformed report**: a defined `data` without a `checks` array, or a `missingEnv` that is not an array, violates the typed precondition; the function performs no runtime check and a missing `checks` would throw a `TypeError` to the caller. This is a documented precondition (no-validation), not a handled path.
- **Network failure, timeout, offline**: not applicable to this function; it does no I/O. Fetch failures belong to [useIntegrations](agentictoolkit://recipes/status-web-hooks-use-integrations), which passes `undefined` or the last good report.
- **Concurrent calls**: not applicable; the function is pure and synchronous in single-threaded JavaScript, so concurrent callers (the banner and the dashboard pill) always get the same result for the same report.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` | `IntegrationsResponse \| undefined` | none (required argument) | The `/integrations` report; `undefined` means not yet loaded. |
| `"cron"` check id | string constant | `"cron"` | Hardcoded id excluded from `issues`; not configurable. |

The function reads no environment variables, settings or injected dependencies.

## Deep Linking

Not applicable: `computeSelfCheck` is a pure function with no route or URL of its own.

## Localization

Not applicable: the module produces no user-facing strings; the variable names and checks it returns are rendered (with the hardcoded "MISSING ENV:" label) by `SelfCheckBanner.tsx`, outside this source.

## Accessibility Options

Not applicable: the module has no visual output, so Reduce Motion, Increase Contrast and Differentiate Without Color do not affect it.

## Feature Flags

Not applicable: `computeSelfCheck` reads no flags and always applies the same rules.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only environment variable names (never their values) and check status already in memory, and it stores and transmits nothing.

## Logging

Not applicable: `computeSelfCheck` makes no log calls; it has no error path to report.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

The module passes separation-of-concerns: it holds only the derivation from report to view, with rendering in `SelfCheckBanner.tsx` and fetching in the integrations hook. `self-check.test.ts` covers the loading null, the all-ok null, warn and error missing env with dedupe, the cron exclusion, the correlated collapse and a lone warning, so unit-test-coverage passes; the empty-array and ok-state-with-missing-env paths are untested but follow directly from the filter. The tests are small, deterministic and independent, each built from the `check` and `report` fixture factories, so good-test-properties passes. explicit-error-handling passes because the function is total over its typed input and has no error path to swallow; a malformed report is a typed caller precondition.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
