---
id: 728521cd-aaaa-48bb-92b3-273c8467cee8
title: Config Status Opt-Out Fold
domain: agentictoolkit://recipes/status-web-src-lib-config-status
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Status board wrapper over the shared endpoint classifier that folds isActive
  false (monitoring paused) into the engine's single ignoreProjectWarning opt-out.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-src-lib-auto-configure
- agentictoolkit://recipes/status-web-hooks-use-config-status
references: []
approved-by: ''
approved-date: ''
---

# Config Status Opt-Out Fold

## Overview

`packages/web/packages/status-web/src/lib/config-status.ts` is the status board's one addition to the shared configuration-status model. The model itself (`endpointConfigStatus`, `projectStatus`, `partitionPending`, `ConfigStatus`) lives in `@agentic-toolkit/deploy-platform/engine` (`src/engine/classify.ts`), the same classifier the Hono server runs behind `POST /auto-configure`. The header comment says a second copy is "how the front page's banner and the Config badges came to count different things in the first place", so this module does not restate the classification rules.

What the module adds is the board's second way for an operator to say "leave this monitor alone": `isActive: false`, the site's master monitoring switch (the editor's "Monitoring enabled"). It folds that into the engine's single `ignoreProjectWarning` flag at the boundary where the app's rows meet the engine's view of an endpoint. It exports:

- `EndpointLike` — the engine's `EndpointLike` plus an optional `isActive?: boolean`.
- `autoConfigureOptedOut(e)` — the fold itself, shared with the auto-configure adapter.
- `endpointConfigStatus(e)` — the engine's three-way classification of the folded endpoint.
- `endpointUnconfigured(e)` — the boolean "should be wired but isn't, and not dismissed" predicate, derived from the wrapper above.

Use it wherever the board classifies an endpoint row (for example the Sites editor's config filter in `EndpointsSection.tsx`) instead of calling the engine's classifier on the raw row.

## Behavioral Requirements

**Data shape**

- **endpoint-like-shape**: `EndpointLike` MUST carry the engine's fields `kind: string`, `platform: string | null`, `deployProject: string | null` and optional `ignoreProjectWarning?: boolean`, plus an optional `isActive?: boolean`.
- **is-active-optional**: `isActive` MUST be optional, so that a caller that does not carry the field (the engine's `EndpointLite`, a test fixture) type-checks as an `EndpointLike`.

**autoConfigureOptedOut**

- **opt-out-ignore-flag**: `autoConfigureOptedOut` MUST return `true` when `ignoreProjectWarning === true`.
- **opt-out-paused**: `autoConfigureOptedOut` MUST return `true` when `isActive === false`.
- **opt-out-strict-false**: `autoConfigureOptedOut` MUST treat only an explicit `false` in `isActive` as paused; an absent or `undefined` `isActive` MUST NOT count as an opt-out.
- **opt-out-strict-true**: `autoConfigureOptedOut` MUST treat only an explicit `true` in `ignoreProjectWarning` as an opt-out; `false` or absent MUST NOT count.
- **opt-out-default**: `autoConfigureOptedOut` MUST return `false` in every case not covered by opt-out-ignore-flag or opt-out-paused.
- **opt-out-minimal-input**: `autoConfigureOptedOut` MUST read only `ignoreProjectWarning` and `isActive`; its parameter type is `Pick<EndpointLike, "ignoreProjectWarning" | "isActive">`.

**endpointConfigStatus**

- **status-folds-before-classify**: `endpointConfigStatus` MUST classify a copy of the endpoint whose `ignoreProjectWarning` is replaced by `autoConfigureOptedOut(e)`, with every other field passed through unchanged.
- **status-no-mutation**: `endpointConfigStatus` MUST NOT modify the caller's endpoint object; the fold is applied to a shallow spread copy.
- **status-delegates-to-engine**: `endpointConfigStatus` MUST return exactly what the engine's `endpointConfigStatus` returns for the folded copy; the result type is `EndpointConfigStatus` (`"configured" | "unconfigured" | "ignored"`).
- **status-infra-kind**: An endpoint whose `kind` is in the engine's `NON_DEPLOY_KINDS` (`health`, `custom`, `dns`) MUST classify as `configured`, whatever its wiring or opt-out fields.
- **status-wired**: A deploy-backed endpoint with a truthy `platform` and a truthy `deployProject` MUST classify as `configured`.
- **status-paused-wired-stays-configured**: A wired deploy-backed endpoint with `isActive: false` MUST classify as `configured`, not `ignored`; the opt-out is consulted only in the engine's unwired branch, so pausing a site does not un-configure it.
- **status-unwired-opted-out**: A deploy-backed endpoint missing its platform or deploy project MUST classify as `ignored` when `autoConfigureOptedOut` is `true`.
- **status-unwired-not-opted-out**: A deploy-backed endpoint missing its platform or deploy project MUST classify as `unconfigured` when `autoConfigureOptedOut` is `false`.
- **status-empty-string-unwired**: An empty-string `platform` or `deployProject` MUST count as missing, because the engine tests them by truthiness.

**endpointUnconfigured**

- **unconfigured-derived**: `endpointUnconfigured` MUST return `true` exactly when this module's `endpointConfigStatus(e)` returns `"unconfigured"`.
- **unconfigured-uses-wrapper**: `endpointUnconfigured` MUST derive from this module's wrapper, not from the engine's own `endpointUnconfigured`, so that the two predicates agree about a paused endpoint.

**Execution and side effects**

- **pure-synchronous**: Every export MUST be a pure, synchronous function: same input, same output, no I/O, no network, no storage, no logging.
- **no-validation**: The functions MUST NOT validate their input at runtime; the `EndpointLike` type signature is the caller's precondition, and the engine applies the same assumption.
- **no-errors**: Every export MUST return without throwing for any input that satisfies `EndpointLike`; there is no error return path.
- **server-twin**: `autoConfigureOptedOut` MUST give the same answer as the server's adapter function of the same name (`src/routes/auto-configure.ts`); the name is shared so a divergence shows up as two answers to one question. The server's behavior is owned by that route, outside this module.

## Appearance

Not applicable — this is a pure classification helper module, not a visual component.

## States

Not applicable — this is a pure classification helper module, not a visual component.

## Accessibility

Not applicable — this is a pure classification helper module, not a visual component.

## Conformance Test Vectors

Vectors 001–005 come from `config-status.test.ts`; its fixture defaults to `kind: "frontend"`, `platform: null`, `deployProject: null`, `ignoreProjectWarning: false`. The rest follow from `autoConfigureOptedOut` and the engine's `endpointConfigStatus` in `classify.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| config-status-001 | opt-out-paused, status-unwired-opted-out, unconfigured-derived | `endpointUnconfigured` on the fixture with `isActive: false` | `false` |
| config-status-002 | opt-out-strict-false, status-unwired-not-opted-out, is-active-optional | `endpointUnconfigured` on the fixture with `isActive: undefined`, then with `isActive: true` | `true` both times |
| config-status-003 | status-folds-before-classify, status-unwired-opted-out | `endpointConfigStatus` on the fixture with `isActive: false` | `"ignored"` |
| config-status-004 | status-paused-wired-stays-configured, status-wired | `endpointConfigStatus` on the fixture with `platform: "vercel"`, `deployProject: "p"`, `isActive: false` | `"configured"` |
| config-status-005 | unconfigured-uses-wrapper, unconfigured-derived | For each of: fixture with `isActive: false`; with `isActive: true`; wired with `isActive: false` — compare `endpointUnconfigured(c)` with `endpointConfigStatus(c) === "unconfigured"` | Equal for all three |
| config-status-006 | opt-out-ignore-flag | `autoConfigureOptedOut({ ignoreProjectWarning: true, isActive: true })` | `true` |
| config-status-007 | opt-out-default, opt-out-strict-true | `autoConfigureOptedOut({})` and `autoConfigureOptedOut({ ignoreProjectWarning: false, isActive: true })` | `false` both times |
| config-status-008 | status-infra-kind | `endpointConfigStatus({ kind: "health", platform: null, deployProject: null, isActive: true })` | `"configured"` |
| config-status-009 | status-unwired-opted-out, opt-out-ignore-flag | `endpointConfigStatus` on the fixture with `ignoreProjectWarning: true` and no `isActive` | `"ignored"` |
| config-status-010 | status-empty-string-unwired | `endpointConfigStatus({ kind: "frontend", platform: "vercel", deployProject: "", isActive: true })` | `"unconfigured"` |
| config-status-011 | status-no-mutation | Call `endpointConfigStatus` on an object with `ignoreProjectWarning: false`, `isActive: false`; then read the object's `ignoreProjectWarning` | Still `false` |
| config-status-012 | pure-synchronous, no-errors | Call each export twice with the same fixture | Same return value both times, returned synchronously, no exception |
| config-status-013 | endpoint-like-shape | Assign an object with only `kind`, `platform`, `deployProject` to `EndpointLike` | Compiles |
| config-status-014 | opt-out-minimal-input | Call `autoConfigureOptedOut({ isActive: false })` with no other fields | Compiles and returns `true` |
| config-status-015 | server-twin | Run the same `{ ignoreProjectWarning, isActive }` combinations through this function and the server's `autoConfigureOptedOut` | Identical results for every combination |
| config-status-016 | status-delegates-to-engine | For any endpoint, compare this `endpointConfigStatus(e)` with the engine's `endpointConfigStatus({ ...e, ignoreProjectWarning: autoConfigureOptedOut(e) })` | Equal |
| config-status-017 | no-validation | Pass an endpoint with an unknown `kind` such as `"frontend"` or `"xyz"` and no wiring | Treated as deploy-backed, `"unconfigured"`, no error |

## Edge Cases

- **Absent `isActive`**: An endpoint without the field MUST be treated as active, keeping its warning (MUST; config-status-002).
- **Absent `ignoreProjectWarning`**: Treated as not opted out (MUST; config-status-007).
- **Both opt-outs set**: `ignoreProjectWarning: true` together with `isActive: false` yields `true` from the fold and `"ignored"` for an unwired endpoint, the same as either alone (MUST).
- **Paused and wired**: Classifies `configured`; pausing never downgrades a wired endpoint (MUST; config-status-004).
- **Infra kinds**: `health`, `custom` and `dns` classify `configured` even when paused or unwired (MUST; config-status-008).
- **Half-wired endpoint**: A `platform` without a `deployProject`, or the reverse, counts as unwired (MUST).
- **Empty strings**: `""` for `platform` or `deployProject` counts as missing (MUST; config-status-010).
- **Non-boolean values at runtime**: A value such as `isActive: 0` or `ignoreProjectWarning: "yes"` from untyped JSON is not `=== false` or `=== true`, so it is not an opt-out. The `boolean` type is the caller's precondition; no runtime check exists (MUST, as stated in no-validation).
- **Null or undefined endpoint**: Passing `null` would throw a `TypeError` on property access; the type signature forbids it and there is no guard (fact, not a handled case).
- **Concurrent access**: Not applicable — the functions are pure and synchronous in single-threaded JavaScript and share no state, so calls cannot interleave.
- **Error states and offline**: Not applicable — the module performs no I/O, so there is no dependency that can fail or go offline.
- **Engine rule changes**: Any change to the engine's classifier (for example a new member of `NON_DEPLOY_KINDS`) applies here unchanged, because this module only delegates (MUST, per status-delegates-to-engine).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `e` (every export) | `EndpointLike` (or the two-field `Pick` for `autoConfigureOptedOut`) | none (required) | The endpoint row to fold or classify |
| `e.isActive` | `boolean \| undefined` | `undefined` (treated as active) | The site's master monitoring switch; only `false` means paused |
| `e.ignoreProjectWarning` | `boolean \| undefined` | `undefined` (treated as not ignored) | The per-endpoint "Ignore" opt-out |
| engine classifier | module import `@agentic-toolkit/deploy-platform/engine` | the shared engine | Supplies `endpointConfigStatus`, `EndpointConfigStatus` and the base `EndpointLike`; not injectable |

No environment variables, settings keys or injected dependencies are read.

## Deep Linking

Not applicable: the module exports pure functions and a type, and registers no route or URL.

## Localization

Not applicable: the module returns string-literal status codes (`"configured"`, `"unconfigured"`, `"ignored"`) and booleans, never user-facing text; display wording belongs to the calling components.

## Accessibility Options

Not applicable: the module renders nothing, so it cannot respond to display options such as Reduce Motion or Increase Contrast.

## Feature Flags

Not applicable: no flag is read; the fold is unconditional.

## Analytics

Not applicable: the module emits no analytics events.

## Privacy

Not applicable: the module handles only monitoring configuration fields (kind, platform, deploy-project name, two booleans), and stores or transmits nothing.

## Logging

Not applicable: the module makes no log calls and has no failure path to report.

## Platform Notes

- **SwiftUI**: No UI is involved. Port `EndpointLike` as a `Sendable` struct with `isActive: Bool?` and `ignoreProjectWarning: Bool?`, and write the fold as `ignoreProjectWarning == true || isActive == false` so `nil` keeps its warning. Return an `enum EndpointConfigStatus: String { case configured, unconfigured, ignored }`. Build the folded copy with a `var copy = e` value copy rather than a spread.
- **Compose**: No UI is involved. Use a Kotlin `data class` with nullable `Boolean?` fields, `copy(ignoreProjectWarning = autoConfigureOptedOut(e))` for the folded view, and an `enum class` for the status. Kotlin's `== true` / `== false` on `Boolean?` reproduces the strict checks.
- **React/Web**: Source platform. `config-status.ts` is plain TypeScript with no React; it imports `endpointConfigStatus` (renamed `classifyEndpoint`), `EndpointConfigStatus` and `EndpointLike` from `@agentic-toolkit/deploy-platform/engine`. The fold uses an object spread. Consumers include `components/configure/EndpointsSection.tsx` and the auto-configure adapter in `lib/auto-configure.ts`. Tests use Vitest in `config-status.test.ts`.
- **AppKit / UIKit**: Same as SwiftUI — a plain Swift value type and free functions in a shared framework, with no AppKit or UIKit dependency.
- **WinUI 3**: No XAML control is involved. Port `EndpointLike` as a C# `record` with `bool? IsActive` and `bool? IgnoreProjectWarning`, and produce the folded view with a `with` expression (`e with { IgnoreProjectWarning = AutoConfigureOptedOut(e) }`), which also leaves the original unmodified. Write the fold as `e.IgnoreProjectWarning == true || e.IsActive == false` so `null` is not an opt-out. Return an `enum EndpointConfigStatus { Configured, Unconfigured, Ignored }`; if the rows arrive as JSON, map the lowercase strings with `System.Text.Json` and a `JsonStringEnumConverter` using a camel-case naming policy. Keep the functions synchronous and static — no `Task`/`async` is needed. A view model that shows the status in a filtered `ObservableCollection` recomputes it through this function rather than storing a second copy, and raises `INotifyPropertyChanged` when `IsActive` or the wiring fields change.

## Design Decisions

**Decision**: The paused switch folds into the engine's single `ignoreProjectWarning` flag at the app boundary, not as a new field in the engine.
**Rationale**: The header comment says `isActive` "means nothing to the engine's other consumers; giving the classifier a field per host vocabulary is how a shared model stops being shared." Paused means out of the auto-configure conversation, which is exactly what the per-endpoint opt-out means.
**Approved**: pending

**Decision**: `isActive` is optional and checked with `=== false`, not by falsiness.
**Rationale**: The field comment says a caller that does not carry it "must not have `undefined` read as 'disabled' and silently lose its warning". The test "an ABSENT isActive is not read as disabled" pins it.
**Approved**: pending

**Decision**: `endpointUnconfigured` delegates to this module's wrapper rather than the engine's predicate of the same name.
**Rationale**: The engine's predicate "would classify the raw row and miss the paused fold, so the two predicates would disagree about the same endpoint."
**Approved**: pending

**Decision**: The fold is exported as `autoConfigureOptedOut`, named after the server's twin.
**Rationale**: One expression of the fold serves both the classifier here and the auto-configure adapter's `EndpointLite` mapping, and sharing the server function's name makes a divergence "visible as two different answers to one question rather than two unrelated helpers."
**Approved**: pending

**Decision**: A paused but wired site stays `configured`.
**Rationale**: The engine reads the opt-out only in its unwired branch, so "pausing a site does not un-configure it"; the test says downgrading it "would misreport a healthy setup" in the Config badge. Its deploy project likewise stays claimed (the backend's `listEndpointsForWiring`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

The module passes separation-of-concerns: classification rules stay in the shared engine, and this file holds only the host-specific fold at the boundary. `config-status.test.ts` exercises every case that turns on `isActive` (paused, absent, true, paused and wired, and agreement of the two predicates), while the rules themselves are tested in the engine's `classify.test.ts`, so unit-test-coverage passes. The tests are small, deterministic and independent, each built from one fixture factory, so good-test-properties passes. explicit-error-handling passes because the functions are total over their typed input and have no error path to swallow; the one untyped risk (non-boolean values from untyped JSON) is a documented caller precondition.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from status-web `src/lib/config-status.ts` |
