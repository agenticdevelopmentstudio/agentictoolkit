<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-system-memory-monitor--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-system-memory-monitor.md -->

# SystemMemoryMonitor

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-system-memory-monitor--edge-cases#<slug>`):

- `null-and-empty-input` MUST — level(for:) takes a non-optional DispatchSource.MemoryPressureEvent OptionSet, so there is no null case; an empty mask …
- `boundary-values` MUST — The three-bit mask [.warning, .critical, .normal] MUST still resolve to .normal, because the .normal check is evaluated …
- `concurrent-access` MUST — pressureLevel MAY be read from any thread while the event-handler queue concurrently writes a new latched value; both …
- `repeated-construction` SHOULD — SystemMemoryMonitor.init() is public and parameterless, so a caller MAY construct any number of instances beyond …

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
