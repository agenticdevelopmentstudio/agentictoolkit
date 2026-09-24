---
id: d766c910-c7ec-4163-94a6-599cf103e85a
title: SystemMemoryMonitor
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-system-memory-monitor
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Live RAM and latched OS memory-pressure source for AIPluginKit: a DispatchSourceMemoryPressure
  latch where a coalesced .normal bit always wins.'
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
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-inference-guard
  - agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-model-fit-policy
references:
  - packages/apple/AgenticToolkit/AIPluginKit/SystemMemoryMonitor.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AIPluginKitTests/SystemMemoryMonitorTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# SystemMemoryMonitor

## Overview

`SystemMemoryMonitor` is `AIPluginKit`'s source of the two facts
`LocalInferenceGuard` and `ModelFitPolicy` need about the host machine: total
physical RAM and the OS's own memory-pressure signal. The
`SystemMemoryMonitoring` protocol is the injectable seam
(`LocalInferenceGuard.init(catalog:memory:)` defaults its `memory` parameter
to `SystemMemoryMonitor.shared`); the concrete `SystemMemoryMonitor` reads
`physicalRAM` once from `ProcessInfo` and latches the OS's memory-pressure
notifications, delivered on a private `DispatchSourceMemoryPressure`, behind
an `NSLock`-guarded `latched` field so any caller can read the current
pressure level from any thread without touching GCD or the lock's queue
itself.

## Behavioral Requirements

- **monitoring-protocol-shape**: `SystemMemoryMonitoring` MUST declare exactly
  two read-only properties, `physicalRAM: UInt64` and `pressureLevel:
  MemoryPressureLevel`, and MUST conform to `Sendable`.
- **physical-ram-source**: `SystemMemoryMonitor.physicalRAM` MUST be
  initialized from `ProcessInfo.processInfo.physicalMemory` and, being
  declared `public let`, MUST return that same value for the instance's
  entire lifetime rather than re-querying `ProcessInfo` on each access.
- **initial-pressure-level**: A newly constructed `SystemMemoryMonitor`
  MUST report `pressureLevel == .normal` until its `DispatchSourceMemoryPressure`
  delivers its first event, per the `latched` field's `.normal` default.
- **pressure-level-is-latched**: `SystemMemoryMonitor.pressureLevel` MUST
  return the most recently latched value from the last delivered memory-pressure
  event, not a live re-read of OS state on each access.
- **event-mask-subscription**: `SystemMemoryMonitor.init()` MUST create its
  `DispatchSourceMemoryPressure` with an event mask of exactly `.normal`,
  `.warning`, and `.critical`, and MUST call `source.activate()` so the
  subscription is live for the instance's lifetime.
- **dedicated-event-queue**: The memory-pressure source's event handler MUST
  run on a dedicated serial `DispatchQueue` labeled
  `"aipluginkit.memory-pressure"`, distinct from the queue of any caller of
  `pressureLevel`.
- **latch-write-serialization**: Every write to `latched` MUST occur inside
  `lock.withLock`, and every read of `latched` via `pressureLevel` MUST occur
  inside `lock.withLock`, so a concurrent read from one thread and a write
  from the event-handler queue are serialized by the same `NSLock`.
- **coalesced-normal-precedence**: `SystemMemoryMonitor.level(for:)` MUST
  return `.normal` whenever the event mask contains the `.normal` bit,
  regardless of whether `.warning` or `.critical` bits are also set in the
  same coalesced mask — a fall is always the later event when a raise and a
  fall coalesce into one delivery, so `.normal` MUST win the latch (per the type's doc comment).
- **critical-precedence-over-warning**: When the event mask does not contain
  `.normal`, `level(for:)` MUST return `.critical` if the mask contains
  `.critical`, even when `.warning` is also set.
- **warning-when-only-warning-set**: When the event mask contains `.warning`
  but neither `.normal` nor `.critical`, `level(for:)` MUST return `.warning`.
- **unmatched-mask-defaults-normal**: When the event mask contains none of
  `.normal`, `.warning`, or `.critical`, `level(for:)` MUST return `.normal`.
- **level-mapping-internal-visibility**: `level(for:)` MUST carry no access
  modifier (Swift's default `internal`), so it is reachable from the event
  handler and from `@testable import AIPluginKit` tests, but is not part of
  the type's public API.
- **shared-singleton-instance**: `SystemMemoryMonitor.shared` MUST provide
  one process-wide default instance, constructed with `SystemMemoryMonitor()`
  exactly once as a `static let`.
- **public-constructibility**: `SystemMemoryMonitor.init()` MUST remain
  `public` and parameterless, so a caller MAY construct additional,
  independent instances beyond `.shared`.
- **unchecked-sendable-declaration**: `SystemMemoryMonitor` MUST be declared
  `final class SystemMemoryMonitor: SystemMemoryMonitoring, @unchecked
  Sendable`, asserting cross-actor safety that the compiler cannot verify on
  its own, backed by the manual `NSLock` serialization of `latched`.
- **weak-self-in-event-handler**: The event handler closure MUST capture
  `self` weakly and MUST return without updating `latched` when `self` has
  already been deallocated.

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
| system-memory-monitor-001 | critical-precedence-over-warning | `SystemMemoryMonitor.level(for: .critical)` (`SystemMemoryMonitorTests.swift`). | Returns `.critical`. |
| system-memory-monitor-002 | critical-precedence-over-warning | `SystemMemoryMonitor.level(for: [.warning, .critical])`. | Returns `.critical` — critical wins over warning when both bits are set without `.normal`. |
| system-memory-monitor-003 | warning-when-only-warning-set | `SystemMemoryMonitor.level(for: .warning)`. | Returns `.warning`. |
| system-memory-monitor-004 | coalesced-normal-precedence | `SystemMemoryMonitor.level(for: .normal)`. | Returns `.normal`. |
| system-memory-monitor-005 | coalesced-normal-precedence | `SystemMemoryMonitor.level(for: [.warning, .normal])`. | Returns `.normal` — a coalesced raise+fall latches the later, normal event rather than the raise. |
| system-memory-monitor-006 | coalesced-normal-precedence | `SystemMemoryMonitor.level(for: [.critical, .normal])`. | Returns `.normal`. |
| system-memory-monitor-007 | coalesced-normal-precedence | `SystemMemoryMonitor.level(for: [.warning, .critical, .normal])`. | Returns `.normal` even with all three bits set. |
| system-memory-monitor-008 | physical-ram-source | Construct `SystemMemoryMonitor()` and read `.physicalRAM` (`SystemMemoryMonitorTests.swift`). | Returns a value greater than `1_000_000_000` (the real host's physical RAM in bytes). |
| system-memory-monitor-009 | initial-pressure-level | Construct a fresh `SystemMemoryMonitor()` and read `.pressureLevel` before any memory-pressure event has been delivered. | Returns `.normal`, from the `latched` field's default (not directly asserted by the test file but the sole possible value before the source's queue delivers its first event). |
| system-memory-monitor-010 | shared-singleton-instance | Read `SystemMemoryMonitor.shared` twice from different call sites. | Both reads yield the identical instance, since `shared` is a `static let` evaluated exactly once. |
| system-memory-monitor-011 | unmatched-mask-defaults-normal | `SystemMemoryMonitor.level(for: [])` (an empty `DispatchSource.MemoryPressureEvent` mask; not exercised by `SystemMemoryMonitorTests.swift`, derived directly from the source). | Returns `.normal`, the function's final fallthrough case. |

## Edge Cases

- **Null and empty input**: `level(for:)` takes a non-optional
  `DispatchSource.MemoryPressureEvent` `OptionSet`, so there is no null case;
  an empty mask (`[]`) matches none of `.normal`/`.critical`/`.warning` and
  MUST fall through to the final `return .normal` (MUST, see
  `unmatched-mask-defaults-normal`).
- **Boundary values**: The three-bit mask `[.warning, .critical, .normal]`
  MUST still resolve to `.normal`, because the `.normal` check is evaluated
  first and unconditionally short-circuits the other two (MUST, see
  `coalesced-normal-precedence`). The two-bit mask `[.warning, .critical]`
  (no `.normal`) MUST resolve to `.critical`, because that check runs before
  the `.warning` check (MUST, see `critical-precedence-over-warning`).
- **Concurrent access**: `pressureLevel` MAY be read from any thread while
  the event-handler queue concurrently writes a new `latched` value; both
  paths MUST take the same `NSLock` via `lock.withLock`, so no read observes
  a partially written value and no two writes race (MUST, see
  `latch-write-serialization`). `physicalRAM` is an immutable `let`
  initialized once at construction, so concurrent reads require no
  synchronization and MUST always return the same value (MUST, see
  `physical-ram-source`). Two independently constructed `SystemMemoryMonitor`
  instances (e.g., `.shared` plus one created via `SystemMemoryMonitor()` in
  a test) each own an independent `latched` field and an independent
  `DispatchSourceMemoryPressure`; an event delivered to one instance's queue
  has no effect on another instance's `pressureLevel`.
- **Error states**: `DispatchSource.makeMemoryPressureSource` and
  `source.activate()` are not `throws` APIs in this source file, and
  `SystemMemoryMonitor.init()` has no error path — there is no dependency
  (network, database, file system) for this component to report as
  unavailable.
- **Offline or disconnected state**: Not applicable — `SystemMemoryMonitor.swift`
  makes no network call; its only external dependency is the OS kernel's
  memory-pressure notification mechanism, which this file does not model as
  a connectivity state.
- **Repeated construction**: `SystemMemoryMonitor.init()` is `public` and
  parameterless, so a caller MAY construct any number of instances beyond
  `.shared` (as `SystemMemoryMonitorTests.liveMonitorReportsRealRAM` does);
  each instance allocates its own dedicated `DispatchQueue` and
  `DispatchSourceMemoryPressure` for the process's lifetime, and the source
  contains no explicit `source.cancel()` or `deinit` to tear either down
  (SHOULD, see Design Decisions — repeated ad hoc construction accumulates
  one live queue and one live pressure subscription per instance for as long
  as that instance is retained).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemMemoryMonitor.init()` parameters | — | none | The initializer takes no parameters; there is nothing for a caller to configure at construction time. |
| Event mask (internal) | `DispatchSource.MemoryPressureEvent` | `[.normal, .warning, .critical]` | Hardcoded in `init()`; not exposed for a caller to narrow or widen. |
| Event queue label (internal) | `String` | `"aipluginkit.memory-pressure"` | Hardcoded in `init()`; not exposed as a parameter. |
| `SystemMemoryMonitoring` (injection seam) | protocol | `SystemMemoryMonitor.shared` (at each consumer's own call site, e.g. `LocalInferenceGuard.init(memory:)`) | Consumers depend on the protocol, not the concrete type, so a test or alternate host MAY substitute a fixed-value conformer. |

`SystemMemoryMonitor.swift` reads no environment variable and no settings
key of its own.

## Deep Linking

Not applicable: `SystemMemoryMonitor.swift` defines no URL scheme, route, or
navigation destination — it is a process-internal data source, not app
navigation.

## Localization

Not applicable: `SystemMemoryMonitor.swift` produces no user-facing string —
it exposes only a byte count and a `MemoryPressureLevel` enum case, neither
of which this file formats or localizes.

## Accessibility Options

Not applicable: `SystemMemoryMonitor.swift` presents no UI, so it responds
to no Reduce Motion, Increase Contrast, or Differentiate Without Color
setting.

## Feature Flags

Not applicable: `SystemMemoryMonitor.swift` defines no feature-flag or
on/off settings-key gate; its event mask and queue label (see Configuration)
are fixed constants, not toggles.

## Analytics

Not applicable: `SystemMemoryMonitor.swift` contains no analytics or
event-tracking call.

## Privacy

Not applicable: `SystemMemoryMonitor.swift` exposes only the host machine's
total physical RAM and a coarse three-value memory-pressure enum; neither
value is user-generated, personal, or credential data, and the file performs
no storage or transmission of its own.

## Logging

Not applicable: `SystemMemoryMonitor.swift` contains no `Logger`, `print`, or
other logging call.

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
  `SystemMemoryMonitoring`.
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

**Decision**: `SystemMemoryMonitor` is declared `@unchecked Sendable` rather
than relying on the compiler's automatic `Sendable` inference.
**Rationale**: The type's only mutable state, `latched`, is manually
serialized behind `NSLock` (`lock.withLock` on every read and write); the
compiler cannot verify that a hand-rolled lock provides the same guarantee a
`Sendable` conformance implies, so the author asserts it explicitly with
`@unchecked`.
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
