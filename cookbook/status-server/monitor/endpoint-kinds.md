---
id: 990362d5-9c3a-4263-828f-a174b2dd2134
title: Status Server Monitor Endpoint Kinds
domain: agentictoolkit://cookbook/status-server/monitor/endpoint-kinds
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The canonical six-member endpoint-kind vocabulary and its type guard, sharing
  NON_DEPLOY_KINDS with the deploy-platform engine so validation, auto-wire, and the
  frontend twin agree.
platforms:
- typescript
- web
tags:
- monitor
- server
- vocabulary
- validation
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/monitor/endpoint-kinds.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/engine/classify.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/engine/classify.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Endpoint Kinds

## Overview

`endpoint-kinds.ts` (`packages/web/packages/status-server/src/monitor/endpoint-kinds.ts`) is the status backend's copy of the canonical endpoint-kind vocabulary: the fixed set of six string values (`http`, `frontend`, `admin`, `health`, `custom`, `dns`) that every monitored endpoint's `kind` field is drawn from. Per its own header comment, it is meant to be the ONE source that the endpoints routes' server-side validation and the auto-wire logic (both external to this file) agree on, and it is deliberately kept in step with an identical copy on the status site's frontend, `packages/web/packages/status-web/src/lib/endpoint-kinds.ts`. The file exports three things of its own — the `ENDPOINT_KINDS` tuple, the derived `EndpointKind` union type, and the `isEndpointKind` type-guard function — and re-exports a fourth, `NON_DEPLOY_KINDS`, from `@agentic-toolkit/deploy-platform/engine`'s `classify.ts` rather than restating which of the six kinds are backend-infra kinds with no deploy project of their own. The module's own comment recalls that this used to be three separate literal sets (here, in the browser, and in the engine) that could disagree with each other, most concretely over whether `dns` belonged in the non-deploy set.

## Behavioral Requirements

### Vocabulary

- **endpoint-kind-vocabulary**: `ENDPOINT_KINDS` MUST be declared as `['http', 'frontend', 'admin', 'health', 'custom', 'dns'] as const` — exactly these six distinct string literals, in this exact order.
- **endpoint-kind-type**: `EndpointKind` MUST be exported as the type `(typeof ENDPOINT_KINDS)[number]`, the union derived from `ENDPOINT_KINDS`'s own element type, rather than a hand-written union literal maintained separately from the array.
- **compile-time-immutability**: `ENDPOINT_KINDS` MUST carry the `as const` assertion, giving it a readonly-tuple type that TypeScript code MUST NOT reassign or mutate without a type error; the module MUST NOT call `Object.freeze` or any other runtime-freezing mechanism on the array, so this immutability is enforced by the type checker only, not by the JavaScript runtime.

### Type Guard

- **type-guard-membership**: `isEndpointKind(k)` MUST return `true` when, and only when, `k` is exactly equal to one of the six string values in `ENDPOINT_KINDS`; for any other input — a different casing, an empty string, or a string that merely contains one of the six values as a substring — it MUST return `false`.
- **type-guard-narrowing**: `isEndpointKind` MUST be declared with the type-predicate return type `k is EndpointKind`, so a call site that checks `isEndpointKind(k)` and receives `true` has `k`'s static type narrowed to `EndpointKind` for the remainder of that branch.
- **type-guard-synchronous**: `isEndpointKind` MUST resolve its check synchronously via a single `Array.prototype.includes` lookup against `ENDPOINT_KINDS` (read through a `readonly string[]` cast), performing no I/O and throwing for no input, including a non-string value reaching it at runtime.

### Shared Classification

- **non-deploy-kinds-reexport**: The module MUST re-export the identical `NON_DEPLOY_KINDS` value from `@agentic-toolkit/deploy-platform/engine` (a `ReadonlySet<string>` containing `'health'`, `'custom'`, and `'dns'`, constructed once in that package's `classify.ts`) rather than declaring a separate set of its own, so this module, the auto-wire logic, and the engine behind `POST /auto-configure` (all external to this file) read the same object and cannot come to disagree about which kinds are deploy-backed.
- **non-deploy-kinds-type-narrowing**: `NON_DEPLOY_KINDS` is typed `ReadonlySet<string>` in `classify.ts`, not `ReadonlySet<EndpointKind>`, and nothing checks at compile time or runtime that every member of `NON_DEPLOY_KINDS` also appears in `ENDPOINT_KINDS`. Keeping the two in step is left to whoever edits them; if one changes without the other, `isEndpointKind` and the "needs wiring" classification can disagree about that kind.

### Cross-File Consistency

- **vocabulary-sync-with-status-web**: The module's header comment says this vocabulary is kept in step with the status site's separate `src/lib/endpoint-kinds.ts` copy, so that the backend and frontend agree on the vocabulary the editor offers. That sync is done by hand: each package holds its own literal `ENDPOINT_KINDS` array, and no import, shared package or cross-package test ties the two together. Any edit to one array has to be copied to the other in the same change.

### Side Effects

- **no-side-effects**: The module MUST perform no I/O, network call, file access, or persistence of any kind, at import time or whenever any of its exported values is used; `ENDPOINT_KINDS`, `EndpointKind`, and `isEndpointKind` are pure and synchronous, and the re-exported `NON_DEPLOY_KINDS` object is likewise constructed once, synchronously, with no I/O, inside `classify.ts`.

## Appearance

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component.

## States

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component; it holds no runtime state of its own to enumerate.

## Accessibility

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-endpoint-kinds-001 | endpoint-kind-vocabulary | Read `ENDPOINT_KINDS` | `.length === 6`; `.join(',') === 'http,frontend,admin,health,custom,dns'` |
| status-server-monitor-endpoint-kinds-002 | endpoint-kind-type | `const k: EndpointKind = 'http'`; `const bad: EndpointKind = 'staging'` | The first assignment compiles; the second fails to type-check because `'staging'` is not a member of `EndpointKind` |
| status-server-monitor-endpoint-kinds-003 | compile-time-immutability | `(ENDPOINT_KINDS as unknown as string[]).push('extra')`, then read `ENDPOINT_KINDS.length` | The direct call `ENDPOINT_KINDS.push('extra')` fails to type-check (`push` does not exist on the readonly tuple type); the cast version compiles, and `ENDPOINT_KINDS.length` is `7` afterward, confirming the underlying array is not frozen at runtime |
| status-server-monitor-endpoint-kinds-004 | type-guard-membership | `isEndpointKind('dns')`; `isEndpointKind('http')` | Both resolve `true` |
| status-server-monitor-endpoint-kinds-005 | type-guard-membership | `isEndpointKind('DNS')`; `isEndpointKind('')`; `isEndpointKind('unknown')` | All resolve `false` |
| status-server-monitor-endpoint-kinds-006 | type-guard-membership | `isEndpointKind('httpz')`; `isEndpointKind('adminx')` | Both resolve `false` — a superstring of a valid kind is not itself a valid kind |
| status-server-monitor-endpoint-kinds-007 | type-guard-narrowing | `const k: string = 'admin'; if (isEndpointKind(k)) { const narrowed: EndpointKind = k; }` | The assignment to `narrowed` compiles only inside the `if` branch; assigning the still-`string`-typed `k` to an `EndpointKind` outside that branch fails to type-check |
| status-server-monitor-endpoint-kinds-008 | non-deploy-kinds-reexport | Import `NON_DEPLOY_KINDS` from this file and separately from `@agentic-toolkit/deploy-platform/engine`, compare with `===`; then check `.has('health')`, `.has('custom')`, `.has('dns')`, `.has('http')`, `.has('frontend')`, `.has('admin')` | The two imports are reference-equal (the same `Set` object); the first three checks resolve `true` and the last three resolve `false` — the same six kinds `classify.test.ts`'s `endpointNeedsWiring` cases exercise against the identical `NON_DEPLOY_KINDS` |
| status-server-monitor-endpoint-kinds-009 | no-side-effects | Import the module with global `fetch`, `console.*`, and `fs` spied, then call `isEndpointKind` several times | Zero recorded calls on any spy, both at import time and after every `isEndpointKind` call |

## Edge Cases

- **Null and empty input**: `isEndpointKind('')` MUST return `false` — an empty string is not one of the six literals — MUST. Nothing in this file guards against a non-string value reaching `isEndpointKind` at runtime through an untyped caller or an unchecked cast; `Array.prototype.includes` compares by strict equality against each of the six string literals, so a non-string argument (`null`, `undefined`, a number) simply fails every comparison and returns `false` rather than throwing — MUST.
- **Boundary values**: the vocabulary has no numeric minimum or maximum to bound; the closest analogue is membership at either edge of the array — the first element `'http'` and the last `'dns'` — both of which test vectors 004 and 006 exercise directly — MUST.
- **Concurrent access**: not a synchronization concern by construction — `ENDPOINT_KINDS`, `EndpointKind`, and `isEndpointKind` involve no mutable state of this module's own creation, so any number of concurrent callers, on one thread or many, read the same values with no possibility of interleaved corruption — MUST. The one caveat traces to `compile-time-immutability`: because ECMAScript modules are cached singletons, if any caller anywhere in the process bypasses the type system and mutates the underlying `ENDPOINT_KINDS` array (test vector 003), every other importer sharing that module instance observes the mutated array from that point on — MUST.
- **Error states**: not applicable — this module has no dependency (network, database, file system) that can fail; every exported value is computed once at module load from literals already present in source, and the sole exception, `NON_DEPLOY_KINDS`, is likewise a synchronous literal `Set` constructed in `classify.ts` with no dependency of its own to fail.
- **Offline / disconnected state**: not applicable — this module issues no network call and has no connectivity of its own to lose.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| n/a | n/a | n/a | This file defines no configurable option, parameter, or environment variable of its own; `ENDPOINT_KINDS`, `EndpointKind`, and `isEndpointKind` are fixed at compile time, and the re-exported `NON_DEPLOY_KINDS` is likewise a fixed literal defined in `classify.ts`, external to this file. |

## Deep Linking

Not applicable: this file defines a vocabulary and a type guard, not an application route or deep-link target of any kind — the six kind values are internal identifiers compared programmatically, never a URL path.

## Localization

Not applicable: this file renders no text to any user and calls no logging or console function of its own; its six literal strings (`http`, `frontend`, `admin`, `health`, `custom`, `dns`) are compared programmatically inside `isEndpointKind` and looked up in `NON_DEPLOY_KINDS`, never displayed. The same literal words are shown, unlocalized, in the separate frontend copy's editor dropdown (`status-web/src/lib/endpoint-kinds.ts` and its consumers), but that is a different file, outside this recipe's given source.

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; every exported value is unconditionally available with no flag gating any of it.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: None. `ENDPOINT_KINDS`, `EndpointKind`, `NON_DEPLOY_KINDS`, and `isEndpointKind` describe endpoint infrastructure metadata — which of six category labels an endpoint carries — never end-user or credential data.
- **Storage**: None. The module holds no state beyond its own literal constants; it neither reads from nor writes to any store.
- **Transmission**: None. This file makes no network call and transmits nothing of its own; how a `kind` value travels over the network (for example, in a route's request or response body) is entirely the concern of the external routes that consume this vocabulary.
- **Retention**: Not applicable — there is nothing this file collects or stores to retain.

## Logging

This file makes no logging or console call of any kind.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log line at any level; `ENDPOINT_KINDS`, `EndpointKind`, `NON_DEPLOY_KINDS`, and `isEndpointKind` produce no observable output beyond their own return values. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this vocabulary would model `EndpointKind` as a Swift `enum EndpointKind: String, CaseIterable` with the same six lowercase raw values, a `static let nonDeployKinds: Set<EndpointKind>` mirroring `NON_DEPLOY_KINDS`, and would get the type-guard's job for free from `EndpointKind(rawValue:)`'s failable initializer rather than writing a separate membership check.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `EndpointKind` as an `enum class` with the six cases and a companion `nonDeployKinds: Set<EndpointKind>`; the `isEndpointKind` membership check becomes `EndpointKind.entries.any { it.name.equals(k, ignoreCase = false) }` or a `runCatching { enumValueOf<EndpointKind>(k) }.isSuccess`, matching this file's exact-match, non-throwing contract.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/endpoint-kinds.ts` on the Node status backend, re-exporting `NON_DEPLOY_KINDS` from `packages/web/packages/deploy-platform/src/engine/classify.ts`; its near-identical twin sits at `packages/web/packages/status-web/src/lib/endpoint-kinds.ts` on the frontend, consumed there by `status-web/src/api/monitored-sites.ts`'s `ENDPOINT_KINDS` re-export. Both copies are plain ESM modules with a readonly `as const` tuple and no runtime freeze, relying on each bundler's/Node's own per-module-instance ESM caching for the singleton behavior described under Concurrent access.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this vocabulary has no windowing or view-layer concern of its own; it would reuse the same Swift `enum` described under SwiftUI regardless of whether the surrounding app is AppKit- or UIKit-based.
- **WinUI 3**: a .NET port models `EndpointKind` as a `public enum EndpointKind { Http, Frontend, Admin, Health, Custom, Dns }`, serialized to and from the lowercase literals this file uses via a `System.Text.Json` `JsonStringEnumConverter` configured with `JsonNamingPolicy.CamelCase`-style lowercasing (or an explicit `[JsonPropertyName]`-style mapping per case, since the TS literals are all-lowercase single words); `NON_DEPLOY_KINDS` becomes `internal static readonly IReadOnlySet<EndpointKind> NonDeployKinds = new HashSet<EndpointKind> { EndpointKind.Health, EndpointKind.Custom, EndpointKind.Dns };`, and the `isEndpointKind` guard becomes `Enum.TryParse<EndpointKind>(k, ignoreCase: false, out _)` or a `HashSet<string>`-backed lookup if the enum's case sensitivity needs to match this file's exact-match contract precisely. None of `HttpClient`, `Task`/`async`, `Windows.Storage`, `ObservableCollection`, or `INotifyPropertyChanged` is needed for this specific file: it has no I/O, no asynchronous operation, no persistence, and no live-updating collection to bind to — it is a static, compile-time-fixed vocabulary, not a data source a view would observe.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/endpoint-kinds.ts` |

## Design Decisions

- **Decision**: re-export `NON_DEPLOY_KINDS` from `@agentic-toolkit/deploy-platform/engine` rather than declaring a separate literal set in this file.
  **Rationale**: stated directly in the source comment — "they used to be three separate literal Sets, here, in the browser, and in the engine" and could "come to disagree" over which kinds are non-deploy-backed, most concretely `dns`. Re-exporting one shared object removes the possibility of the three call sites drifting apart on that specific question.
  **Approved**: pending
- **Decision**: derive `EndpointKind` from `ENDPOINT_KINDS` via `(typeof ENDPOINT_KINDS)[number]` instead of a hand-written union type declared independently of the array.
  **Rationale**: not spelled out in an inline comment, but demonstrated as deliberate by the type declaration itself — deriving the type from the runtime array is the idiom that keeps a literal-union type and its backing array from drifting apart, the identical failure mode the module's other comment describes for the pre-re-export `NON_DEPLOY_KINDS` history.
  **Approved**: pending
- **Decision**: give `ENDPOINT_KINDS` an `as const` assertion without also calling `Object.freeze` on the resulting array.
  **Rationale**: not stated in the source; recorded here as a fact of the code per this recipe's authoring rules, not a defended choice — the immutability this file relies on is a compile-time-only guarantee (`compile-time-immutability`), so a caller that bypasses the type system can still mutate the shared array at runtime, for every subsequent importer of the same module instance.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`unit-test-coverage` fails as written: no test file in the given source tree exercises `ENDPOINT_KINDS`, `EndpointKind`, or `isEndpointKind` directly — there is no dedicated test file for this module anywhere in `status-server` or `status-web`. The only test coverage touching this module's contents is indirect: `deploy-platform`'s `classify.test.ts` exercises `endpointNeedsWiring` (which reads the re-exported `NON_DEPLOY_KINDS`'s three members) against the same six kind strings this file's vocabulary defines, but that suite tests `classify.ts`'s own function, not anything exported from this file. `separation-of-concerns` passes: this file owns exactly one concern — the endpoint-kind vocabulary and a membership guard over it — and explicitly delegates the separate concern of which kinds are deploy-backed to the imported `NON_DEPLOY_KINDS`/`classify.ts`, per its own header comment that this list's knowledge stops short of the classifier's. `input-sanitization` is `partial`: `isEndpointKind` is exactly the validation primitive the module's header comment describes as backing "server-side validation (the endpoints routes)," but the given source tree has no call site anywhere that actually invokes `isEndpointKind` against an incoming `kind` value — whether any route currently performs that validation is unverified from this file alone, so the primitive exists and is correct on its own terms, but its wiring into an accept boundary cannot be confirmed as passing rather than merely available.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
