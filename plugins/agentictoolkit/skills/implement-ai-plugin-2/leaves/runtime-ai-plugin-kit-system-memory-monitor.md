<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-system-memory-monitor · source: ai-plugin-runtime-ai-plugin-kit-system-memory-monitor.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-system-memory-monitor#<slug>`):

- `monitoring-protocol-shape` MUST
- `physical-ram-source` MUST
- `initial-pressure-level` MUST
- `pressure-level-is-latched` MUST
- `event-mask-subscription` MUST
- `dedicated-event-queue` MUST
- `latch-write-serialization` MUST
- `coalesced-normal-precedence` MUST
- `critical-precedence-over-warning` MUST
- `warning-when-only-warning-set` MUST
- `unmatched-mask-defaults-normal` MUST
- `level-mapping-internal-visibility` MUST
- `shared-singleton-instance` MUST
- `public-constructibility` MUST
- `unchecked-sendable-declaration` MUST
- `weak-self-in-event-handler` MUST
- `decision` MAY — init() is left public and unconstrained, so a caller MAY construct additional SystemMemoryMonitor instances beyond …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemMemoryMonitor.init()` parameters | — | none | The initializer takes no parameters; there is nothing for a caller to configure at construction time. |
| Event mask (internal) | `DispatchSource.MemoryPressureEvent` | `[.normal, .warning, .critical]` | Hardcoded in `init()`; not exposed for a caller to narrow or widen. |
| Event queue label (internal) | `String` | `"aipluginkit.memory-pressure"` | Hardcoded in `init()`; not exposed as a parameter. |
| `SystemMemoryMonitoring` (injection seam) | protocol | `SystemMemoryMonitor.shared` (at each consumer's own call site, e.g. `LocalInferenceGuard.init(memory:)`) | Consumers depend on the protocol, not the concrete type, so a test or alternate host MAY substitute a fixed-value conformer. |

`SystemMemoryMonitor.swift` reads no environment variable and no settings
key of its own.

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
