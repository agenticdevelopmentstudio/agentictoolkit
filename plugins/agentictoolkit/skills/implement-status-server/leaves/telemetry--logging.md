<!-- leaf: implement-status-server/telemetry--logging · source: status-server-telemetry.md -->

# Status Server Telemetry

## Logging

Subsystem: (no fixed subsystem; uses `console.error()`)

| Event | Level | Message |
|-------|-------|---------|
| Errors fetcher collection failure | error | `"[telemetry] errors collection failed"` |
| Analytics fetcher collection failure | error | `"[telemetry] analytics collection failed"` |
| Platform health observation recording failure | error | `"[telemetry] recording GlitchTip platform health failed"` |
