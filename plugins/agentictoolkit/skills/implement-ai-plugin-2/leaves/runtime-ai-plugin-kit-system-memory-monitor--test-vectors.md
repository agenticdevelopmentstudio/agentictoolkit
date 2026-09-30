<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-system-memory-monitor--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-system-memory-monitor.md -->

# SystemMemoryMonitor

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
