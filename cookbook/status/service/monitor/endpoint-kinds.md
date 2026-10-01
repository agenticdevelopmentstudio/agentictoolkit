---
id: 990362d5-9c3a-4263-828f-a174b2dd2134
title: Monitor Endpoint Kinds
domain: agentictoolkit://cookbook/status/service/monitor/endpoint-kinds
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The canonical six-member endpoint-kind vocabulary and its membership check,
  sharing the non-deploy kind set with the deploy-platform engine so validation,
  auto-wire, and the frontend twin agree.
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

# Monitor Endpoint Kinds

## Overview

This module is the status backend's copy of the canonical endpoint-kind vocabulary: the fixed set of six string values (`http`, `frontend`, `admin`, `health`, `custom`, `dns`) that every monitored endpoint's `kind` field is drawn from. It is meant to be the ONE source that the endpoints routes' server-side validation and the auto-wire logic (both external to this module) agree on, and it is deliberately kept in step with an identical copy on the status site's frontend. The module exports three things of its own — the ordered vocabulary, the derived kind type, and a membership-checking function — and re-exports a fourth, the non-deploy kind set, from the deploy-platform engine's classifier rather than restating which of the six kinds are backend-infra kinds with no deploy project of their own. This used to be three separate literal sets (here, in the browser, and in the engine) that could disagree with each other, most concretely over whether `dns` belonged in the non-deploy set.

## Behavioral Requirements

### Vocabulary

- **endpoint-kind-vocabulary**: The endpoint-kind vocabulary MUST be exactly these six distinct string literals, in this exact order: `'http'`, `'frontend'`, `'admin'`, `'health'`, `'custom'`, `'dns'`.
- **endpoint-kind-type**: The endpoint-kind type MUST be derived from the vocabulary's own elements, rather than a hand-written union maintained separately from it.
- **compile-time-immutability**: The vocabulary MUST be declared immutable, such that code MUST NOT reassign or mutate it without a type-checking error; the module MUST NOT additionally enforce this immutability at runtime, so it is enforced by the type checker only, not by the running program.

### Type Guard

- **type-guard-membership**: The membership check MUST return `true` when, and only when, its input is exactly equal to one of the six string values in the vocabulary; for any other input — a different casing, an empty string, or a string that merely contains one of the six values as a substring — it MUST return `false`.
- **type-guard-narrowing**: The membership check MUST be declared so that a call site which checks it and receives `true` has the checked value's static type narrowed to the endpoint-kind type for the remainder of that branch.
- **type-guard-synchronous**: The membership check MUST resolve synchronously via a single lookup against the vocabulary, performing no I/O and throwing for no input, including a non-string value reaching it at runtime.

### Shared Classification

- **non-deploy-kinds-reexport**: The module MUST re-export the identical non-deploy kind set from the deploy-platform engine's classifier (a read-only set of strings containing `'health'`, `'custom'`, and `'dns'`, constructed once in that engine) rather than declaring a separate set of its own, so this module, the auto-wire logic, and the engine behind `POST /auto-configure` (all external to this module) read the same object and cannot come to disagree about which kinds are deploy-backed.
- **non-deploy-kinds-type-narrowing**: The non-deploy kind set is typed as a read-only set of strings, not of endpoint kinds specifically, and nothing checks at compile time or runtime that every member of the non-deploy kind set also appears in the endpoint-kind vocabulary. Keeping the two in step is left to whoever edits them; if one changes without the other, the membership check and the "needs wiring" classification can disagree about that kind.

### Cross-File Consistency

- **vocabulary-sync-with-status-web**: This vocabulary is kept in step with the status site's separate frontend copy, so that the backend and frontend agree on the vocabulary the editor offers. That sync is done by hand: each package holds its own literal vocabulary, and no import, shared package or cross-package test ties the two together. Any edit to one has to be copied to the other in the same change.

### Side Effects

- **no-side-effects**: The module MUST perform no I/O, network call, file access, or persistence of any kind, at load time or whenever any of its exported values is used; the vocabulary, its derived type, and the membership check are pure and synchronous, and the re-exported non-deploy kind set is likewise constructed once, synchronously, with no I/O, inside the classifier.

## Appearance

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component.

## States

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component; it holds no runtime state of its own to enumerate.

## Accessibility

Not applicable — this is an endpoint-kind vocabulary module and type guard, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-endpoint-kinds-001 | endpoint-kind-vocabulary | Read the endpoint-kind vocabulary | Length 6; joined as `'http,frontend,admin,health,custom,dns'` |
| status-server-monitor-endpoint-kinds-002 | endpoint-kind-type | Assign a value of `'http'` to the endpoint-kind type; assign a value of `'staging'` to it | The first assignment is accepted; the second is rejected because `'staging'` is not a member of the endpoint-kind vocabulary |
| status-server-monitor-endpoint-kinds-003 | compile-time-immutability | Attempt to append `'extra'` to the vocabulary through the ordinary typed interface, then bypass the type system and append it anyway, then read the vocabulary's length | The ordinary attempt is rejected at construction time; the bypassed attempt succeeds, and the vocabulary's length is `7` afterward, confirming the underlying value is not frozen at runtime |
| status-server-monitor-endpoint-kinds-004 | type-guard-membership | Check membership for `'dns'`; for `'http'` | Both resolve `true` |
| status-server-monitor-endpoint-kinds-005 | type-guard-membership | Check membership for `'DNS'`; for an empty string; for `'unknown'` | All resolve `false` |
| status-server-monitor-endpoint-kinds-006 | type-guard-membership | Check membership for `'httpz'`; for `'adminx'` | Both resolve `false` — a superstring of a valid kind is not itself a valid kind |
| status-server-monitor-endpoint-kinds-007 | type-guard-narrowing | Hold a plain string value of `'admin'`; check its membership, and only within that passing branch, treat it as the narrowed endpoint-kind type | The narrowed use is accepted only inside the passing branch; the same use outside that branch, on the still-plain-string value, is rejected |
| status-server-monitor-endpoint-kinds-008 | non-deploy-kinds-reexport | Read the non-deploy kind set from this module and separately from the deploy-platform engine's classifier, compare identity; then check membership of `'health'`, `'custom'`, `'dns'`, `'http'`, `'frontend'`, `'admin'` | The two reads are the same object; the first three checks resolve `true` and the last three resolve `false` — the same six kinds the classifier's own "needs wiring" cases exercise against the identical non-deploy kind set |
| status-server-monitor-endpoint-kinds-009 | no-side-effects | Load the module with the network, logging, and file-system facilities spied, then check membership several times | Zero recorded calls on any spy, both at load time and after every membership check |

## Edge Cases

- **Null and empty input**: checking membership for an empty string MUST return `false` — an empty string is not one of the six literals — MUST. Nothing in this module guards against a non-string value reaching the membership check at runtime through an untyped caller or an unchecked cast; the check compares by strict equality against each of the six string literals, so a non-string argument (an absent value, a number) simply fails every comparison and returns `false` rather than throwing — MUST.
- **Boundary values**: the vocabulary has no numeric minimum or maximum to bound; the closest analogue is membership at either edge of the ordering — the first element `'http'` and the last `'dns'` — both of which test vectors 004 and 006 exercise directly — MUST.
- **Concurrent access**: not a synchronization concern by construction — the vocabulary, its derived type, and the membership check involve no mutable state of this module's own creation, so any number of concurrent callers, in any execution context, read the same values with no possibility of interleaved corruption — MUST. The one caveat traces to `compile-time-immutability`: because the module is a cached singleton, if any caller anywhere in the process bypasses the type system and mutates the underlying vocabulary (test vector 003), every other importer sharing that module instance observes the mutated value from that point on — MUST.
- **Error states**: not applicable — this module has no dependency (network, database, file system) that can fail; every exported value is computed once at load time from literals already present in source, and the sole exception, the non-deploy kind set, is likewise a synchronous literal set constructed in the classifier with no dependency of its own to fail.
- **Offline / disconnected state**: not applicable — this module issues no network call and has no connectivity of its own to lose.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| n/a | n/a | n/a | This module defines no configurable option, parameter, or environment variable of its own; the vocabulary, its derived type, and the membership check are fixed at compile time, and the re-exported non-deploy kind set is likewise a fixed literal defined in the classifier, external to this module. |

## Deep Linking

Not applicable: this module defines a vocabulary and a membership check, not an application route or deep-link target of any kind — the six kind values are internal identifiers compared programmatically, never a URL path.

## Localization

Not applicable: this module renders no text to any user and calls no logging function of its own; its six literal strings (`http`, `frontend`, `admin`, `health`, `custom`, `dns`) are compared programmatically inside the membership check and looked up in the non-deploy kind set, never displayed. The same literal words are shown, unlocalized, in the separate frontend copy's editor dropdown, but that is a different module, outside this recipe's given source.

## Accessibility Options

Not applicable: this module has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system; every exported value is unconditionally available with no flag gating any of it.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: None. The vocabulary, its derived type, the non-deploy kind set, and the membership check describe endpoint infrastructure metadata — which of six category labels an endpoint carries — never end-user or credential data.
- **Storage**: None. The module holds no state beyond its own literal constants; it neither reads from nor writes to any store.
- **Transmission**: None. This module makes no network call and transmits nothing of its own; how a kind value travels over the network (for example, in a route's request or response body) is entirely the concern of the external routes that consume this vocabulary.
- **Retention**: Not applicable — there is nothing this module collects or stores to retain.

## Logging

This module makes no logging call of any kind.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This module emits no log line at any level; the vocabulary, its derived type, the non-deploy kind set, and the membership check produce no observable output beyond their own return values. |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
