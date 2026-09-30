<!-- leaf: implement-foundation/diagnostics--logging · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default,
`Loggable.swift`) | Category: `JITAvailability` and
`UpstreamDivergenceLedger` respectively (`Loggable`'s default per-type
category).

| Event | Level | Message |
|-------|-------|---------|
| Degraded JIT availability, first detection in the process | error | The full `diagnosis` sentence (`JITAvailability.swift`), marked `privacy: .public`. |
| Healthy JIT availability | — | No log line is written (`jit-no-log-when-healthy`). |
| A divergence's first-ever hit for a given key | info | `"Divergence from VS Code first seen: \(divergence.id) — \(divergence.ourBehaviour)"` (`UpstreamDivergenceLedger.swift`), marked `privacy: .public`. |
| A repeat hit for a key already recorded | — | No log line is written (`ledger-first-hit-logs-once`). |
