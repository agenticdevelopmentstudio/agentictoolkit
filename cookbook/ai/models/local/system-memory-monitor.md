---
id: d766c910-c7ec-4163-94a6-599cf103e85a
title: System Memory Monitor
domain: agentictoolkit://cookbook/ai/models/local/system-memory-monitor
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Live source of a host machine's total physical RAM and a latched OS
  memory-pressure signal, where a coalesced normal bit always wins.
platforms:
  - swift
  - macos
tags:
  - ai-plugin
  - memory-guard
  - memory-pressure
  - singleton
depends-on: []
related:
  - agentictoolkit://cookbook/ai/models/local/local-inference-guard
  - agentictoolkit://cookbook/ai/models/local/model-fit-policy
references:
  - packages/apple/AgenticToolkit/AIPluginKit/SystemMemoryMonitor.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AIPluginKitTests/SystemMemoryMonitorTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# System Memory Monitor

## Overview

This is a shared source of the two facts an inference guard and a fit
policy need about the host machine: total physical RAM and the OS's own
memory-pressure signal. An injectable monitoring interface is the seam a
guard's constructor depends on by default; the concrete implementation
reads physical RAM once at construction and latches the OS's
memory-pressure notifications behind a lock-guarded field, so any caller
can read the current pressure level from any thread without touching the
underlying notification mechanism or its queue itself.

## Behavioral Requirements

- **monitoring-protocol-shape**: The monitoring interface MUST declare
  exactly two read-only properties — physical RAM (an unsigned integer)
  and pressure level (a memory pressure level) — and MUST be safe to pass
  across concurrent boundaries.
- **physical-ram-source**: The physical RAM property MUST be initialized
  once, from the OS's reported total physical memory, and MUST return
  that same value for the instance's entire lifetime rather than
  re-querying the OS on each access.
- **initial-pressure-level**: A newly constructed monitor MUST report a
  `normal` pressure level until its underlying subscription delivers its
  first event, per the latch's `normal` default.
- **pressure-level-is-latched**: The pressure level property MUST return
  the most recently latched value from the last delivered memory-pressure
  event, not a live re-read of OS state on each access.
- **event-mask-subscription**: Construction MUST subscribe to exactly the
  `normal`, `warning`, and `critical` memory-pressure events, and MUST
  activate that subscription so it is live for the instance's lifetime.
- **dedicated-event-queue**: The memory-pressure subscription's event
  handling MUST run on a dedicated serial queue labeled
  `"aipluginkit.memory-pressure"`, distinct from the queue of any caller
  reading the pressure level.
- **latch-write-serialization**: Every write to the latched value MUST
  occur under the same lock that guards every read of it through the
  pressure level property, so a concurrent read from one thread and a
  write from the event-handling queue are serialized by that one lock.
- **coalesced-normal-precedence**: The level-mapping computation MUST
  return `normal` whenever the delivered event set contains the `normal`
  bit, regardless of whether `warning` or `critical` bits are also set in
  the same coalesced delivery — a fall is always the later event when a
  raise and a fall coalesce into one delivery, so `normal` MUST win the
  latch (per the component's own documented rationale).
- **critical-precedence-over-warning**: When the delivered event set does
  not contain `normal`, the level-mapping computation MUST return
  `critical` if the set contains `critical`, even when `warning` is also
  set.
- **warning-when-only-warning-set**: When the delivered event set contains
  `warning` but neither `normal` nor `critical`, the level-mapping
  computation MUST return `warning`.
- **unmatched-mask-defaults-normal**: When the delivered event set
  contains none of `normal`, `warning`, or `critical`, the level-mapping
  computation MUST return `normal`.
- **shared-singleton-instance**: A single shared instance MUST exist
  process-wide, constructed exactly once, providing one default instance
  for every consumer.
- **public-constructibility**: Construction MUST remain unconstrained and
  available to callers, so a caller MAY create additional, independent
  instances beyond the shared one.
- **concurrency-safety-is-manually-asserted**: This component MUST be safe
  to share and access concurrently across threads, backed entirely by the
  lock-guarded serialization of its latched value rather than by any
  automatic, structurally-verified guarantee — a fact the component must
  assert explicitly, since the guarantee rests on manual locking rather
  than immutability.
- **event-handler-guards-against-deallocated-instance**: The event-handling
  callback MUST hold no reference to the monitor that would extend its
  lifetime past the point the monitor is otherwise deallocated, and MUST
  return without updating the latched value once the monitor has already
  been deallocated.

## Appearance

Not applicable — this is a memory-pressure and RAM data source, not a
visual component.

## States

Not applicable — this is a memory-pressure and RAM data source, not a
visual component.

## Accessibility

Not applicable — this is a memory-pressure and RAM data source, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| system-memory-monitor-001 | critical-precedence-over-warning | Compute the pressure level for a delivered event set containing only `critical`. | Returns `critical`. |
| system-memory-monitor-002 | critical-precedence-over-warning | Compute the pressure level for a delivered event set containing `warning` and `critical` (no `normal`). | Returns `critical` — critical wins over warning when both bits are set without `normal`. |
| system-memory-monitor-003 | warning-when-only-warning-set | Compute the pressure level for a delivered event set containing only `warning`. | Returns `warning`. |
| system-memory-monitor-004 | coalesced-normal-precedence | Compute the pressure level for a delivered event set containing only `normal`. | Returns `normal`. |
| system-memory-monitor-005 | coalesced-normal-precedence | Compute the pressure level for a delivered event set containing `warning` and `normal`. | Returns `normal` — a coalesced raise+fall latches the later, normal event rather than the raise. |
| system-memory-monitor-006 | coalesced-normal-precedence | Compute the pressure level for a delivered event set containing `critical` and `normal`. | Returns `normal`. |
| system-memory-monitor-007 | coalesced-normal-precedence | Compute the pressure level for a delivered event set containing `warning`, `critical`, and `normal`. | Returns `normal` even with all three bits set. |
| system-memory-monitor-008 | physical-ram-source | Construct a monitor and read its physical RAM. | Returns a value greater than `1,000,000,000` (the real host's physical RAM in bytes). |
| system-memory-monitor-009 | initial-pressure-level | Construct a fresh monitor and read its pressure level before any memory-pressure event has been delivered. | Returns `normal`, from the latch's default (not directly asserted by the test file but the sole possible value before the underlying subscription delivers its first event). |
| system-memory-monitor-010 | shared-singleton-instance | Read the shared instance twice from different call sites. | Both reads yield the identical instance, since the shared instance is created exactly once. |
| system-memory-monitor-011 | unmatched-mask-defaults-normal | Compute the pressure level for an empty delivered event set (not exercised by the test file; derived directly from the source). | Returns `normal`, the function's final fallthrough case. |

## Edge Cases

- **Null and empty input**: The level-mapping computation takes a
  non-optional set of memory-pressure events, so there is no null case;
  an empty set matches none of `normal`/`critical`/`warning` and MUST
  fall through to a final `normal` result (MUST, see
  `unmatched-mask-defaults-normal`).
- **Boundary values**: The three-bit set `{warning, critical, normal}`
  MUST still resolve to `normal`, because the `normal` check is evaluated
  first and unconditionally short-circuits the other two (MUST, see
  `coalesced-normal-precedence`). The two-bit set `{warning, critical}`
  (no `normal`) MUST resolve to `critical`, because that check runs before
  the `warning` check (MUST, see `critical-precedence-over-warning`).
- **Concurrent access**: The pressure level MAY be read from any thread
  while the event-handling queue concurrently writes a new latched value;
  both paths MUST take the same lock, so no read observes a partially
  written value and no two writes race (MUST, see
  `latch-write-serialization`). Physical RAM is immutable, initialized
  once at construction, so concurrent reads require no synchronization and
  MUST always return the same value (MUST, see `physical-ram-source`).
  Two independently constructed monitor instances (e.g. the shared
  instance plus one created directly in a test) each own an independent
  latch and an independent underlying subscription; an event delivered to
  one instance's queue has no effect on another instance's pressure
  level.
- **Error states**: The underlying subscription-creation and activation
  calls are not failable in this component, and construction has no error
  path — there is no dependency (network, database, file system) for this
  component to report as unavailable.
- **Offline or disconnected state**: Not applicable — this component makes
  no network call; its only external dependency is the OS kernel's
  memory-pressure notification mechanism, which this component does not
  model as a connectivity state.
- **Repeated construction**: Construction MAY be invoked any number of
  times beyond the shared instance, and each instance allocates its own
  dedicated queue and memory-pressure subscription for the process's
  lifetime; the source contains no explicit teardown operation to release
  either (SHOULD, see Design Decisions — repeated ad hoc construction
  accumulates one live queue and one live pressure subscription per
  instance for as long as that instance is retained).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Constructor parameters | — | none | The constructor takes no parameters; there is nothing for a caller to configure at construction time. |
| Event set (internal) | set of memory-pressure events | `{normal, warning, critical}` | Hardcoded at construction; not exposed for a caller to narrow or widen. |
| Event queue label (internal) | string | `"aipluginkit.memory-pressure"` | Hardcoded at construction; not exposed as a parameter. |
| Monitoring interface (injection seam) | interface | the shared instance (at each consumer's own call site, e.g. an inference guard's constructor) | Consumers depend on the interface, not the concrete type, so a test or alternate host MAY substitute a fixed-value conformer. |

This component reads no environment variable and no settings key of its
own.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination — it is a process-internal data source, not app navigation.

## Localization

Not applicable: this component produces no user-facing string — it
exposes only a byte count and a memory pressure level case, neither of
which this component formats or localizes.

## Accessibility Options

Not applicable: this component presents no UI, so it responds to no
Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this component defines no feature-flag or on/off
settings-key gate; its event set and queue label (see Configuration) are
fixed constants, not toggles.

## Analytics

Not applicable: this component contains no analytics or event-tracking
call.

## Privacy

Not applicable: this component exposes only the host machine's total
physical RAM and a coarse three-value memory-pressure indicator; neither
value is user-generated, personal, or credential data, and the component
performs no storage or transmission of its own.

## Logging

Not applicable: this component contains no logging call of its own.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/SystemMemoryMonitor.swift`,
  alongside the `MemoryPressureLevel` enum it depends on
  (`ModelFitPolicy.swift`) and its consumer `LocalInferenceGuard.swift`. It
  uses `ProcessInfo.processInfo.physicalMemory` for RAM,
  `DispatchSource.makeMemoryPressureSource` plus a dedicated
  `DispatchQueue` for the OS pressure signal, and `NSLock` to guard the
  latched value read from arbitrary threads. Nothing here is
  SwiftUI-specific — any host consumes it identically through
  `SystemMemoryMonitoring`. The level-mapping helper (`level(for:)`)
  carries no access modifier (Swift's default `internal`), so it is
  reachable from the event handler and from `@testable import
  AIPluginKit` tests, but is not part of the type's public API. The type
  is declared `final class SystemMemoryMonitor: SystemMemoryMonitoring,
  @unchecked Sendable`, asserting the cross-actor safety described by
  `concurrency-safety-is-manually-asserted` explicitly, since the compiler
  cannot verify a hand-rolled `NSLock` on its own; the event handler
  closure captures `self` weakly and returns without updating `latched`
  when `self` has already been deallocated, per
  `event-handler-guards-against-deallocated-instance`.
- **Compose**: `ActivityManager.MemoryInfo` (for total/available RAM) and
  `ComponentCallbacks2.onTrimMemory(level)` are the Android analogues of
  `ProcessInfo.physicalMemory` and the latched `DispatchSourceMemoryPressure`
  signal respectively; `onTrimMemory`'s `TRIM_MEMORY_*` levels would need
  the same collapse-to-three-tiers mapping `level(for:)` performs, and a
  `kotlinx.atomicfu`-backed field or a `synchronized` block stands in for
  `NSLock`. A plain `object` singleton stands in for `SystemMemoryMonitor.shared`.
- **React/Web**: Neither Node.js nor the browser exposes an OS memory-pressure
  latch analogous to `DispatchSourceMemoryPressure`; a Node host can read
  `os.totalmem()` for the RAM figure but has no `.warning`/`.critical`
  equivalent to subscribe to. The browser's non-standard
  `navigator.deviceMemory` gives only a coarse RAM estimate, and there is no
  standardized pressure-event API to poll or subscribe to in its place.
- **AppKit / UIKit**: Identical to the SwiftUI note — this type is
  UI-framework-agnostic; only the host application embedding `AIPluginKit`
  differs, never this contract.
- **WinUI 3**: Model `SystemMemoryMonitor` as a plain C# class exposing
  `ulong PhysicalRam` (read once via `GlobalMemoryStatusEx`, P/Invoke, or
  `Windows.System.MemoryManager.AppMemoryUsage`) and a `MemoryPressureLevel
  PressureLevel` property backed by a `lock`-guarded field (or a `volatile`
  field with `Interlocked` if only reads/writes of a single enum value are
  needed). Subscribe to
  `Windows.System.MemoryManager.AppMemoryUsageIncreased`/`AppMemoryUsageDecreased`
  events, or poll `AppMemoryUsageLevel` (`Low`/`Medium`/`High`/`OverLimit`)
  on a dedicated background `Task`/timer in place of the GCD event queue,
  and collapse that four-value enum to the three-value `MemoryPressureLevel`
  the way `level(for:)` collapses a coalesced `OptionSet` mask — deciding
  which WinUI level maps to `.warning` versus `.critical` is a new mapping
  decision this source does not answer for Windows. Use a static
  `readonly` singleton field, initialized once, for `SystemMemoryMonitor.Shared`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/SystemMemoryMonitor.swift` |

## Design Decisions

**Decision**: `level(for:)` checks `.normal` before `.critical` and
`.warning`, so a coalesced mask containing `.normal` alongside either or
both of the other bits still resolves to `.normal`.
**Rationale**: Per the type's doc comment: the pressure source fires on
transitions, so when several transitions coalesce into one delivered mask,
the `.normal` bit means the window *ended* at normal — a fall is always the
later event when a raise and a fall coalesce — so `.normal` must win the
latch, or a raise-then-fall pair would latch `.warning`/`.critical` forever.
**Approved**: pending

**Decision**: In the Swift implementation, `SystemMemoryMonitor` is
declared `@unchecked Sendable` rather than relying on the compiler's
automatic `Sendable` inference.
**Rationale**: The type's only mutable state, `latched`, is manually
serialized behind `NSLock` (`lock.withLock` on every read and write); the
compiler cannot verify that a hand-rolled lock provides the same guarantee a
`Sendable` conformance implies, so the author asserts it explicitly with
`@unchecked`. A port on a platform without an equivalent compiler-checked
concurrency-safety marker has nothing to assert or omit here; the
underlying requirement, `concurrency-safety-is-manually-asserted`, is what
carries the behavior forward.
**Approved**: pending

**Decision**: `init()` is left `public` and unconstrained, so a caller MAY
construct additional `SystemMemoryMonitor` instances beyond
`SystemMemoryMonitor.shared`, each with its own `DispatchQueue` and
`DispatchSourceMemoryPressure`, with no `deinit` or `source.cancel()` to
release either.
**Rationale**: The source provides no lifecycle management beyond ARC
deallocation of the instance and its stored `source` property; this is
acceptable for the production singleton (`.shared`, alive for the process's
lifetime) and for short-lived test instances (e.g.
`SystemMemoryMonitorTests.liveMonitorReportsRealRAM`), but the source itself
does not document or bound how many independent subscriptions repeated ad
hoc construction would accumulate.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | partial | Performance |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | failed | Reliability |

Notes: separation-of-concerns passes because the `SystemMemoryMonitoring` protocol is the injectable seam consumers such as `LocalInferenceGuard` depend on, keeping the concrete `DispatchSourceMemoryPressure`/`NSLock` plumbing behind that protocol so a test or alternate host can substitute a fixed value. unit-test-coverage passes because `SystemMemoryMonitorTests.swift` exercises `level(for:)`'s precedence rules directly and constructs a live monitor to check `physicalRAM`. resource-efficiency is partial because the shared `.shared` singleton itself is cheap at idle, but `init()` remains public and unconstrained with no `deinit` or `source.cancel()`, so each additional ad hoc instance accumulates its own `DispatchQueue` and `DispatchSourceMemoryPressure` for as long as it is retained, per the "Repeated construction" edge case. health-observability fails because `SystemMemoryMonitor.shared` is a process-lifetime component that contains no `Logger`, `print`, or other logging call of its own — its pressure state is only ever exposed passively to a caller that reads `pressureLevel`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
