<!-- leaf: implement-extension-host-vs-1/code-api-host-diagnostic-sink--logging · source: extension-host-vs-code-api-host-diagnostic-sink.md -->

# HostDiagnosticSink

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `HostDiagnosticSink` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `diagnosticsChanged(for:)` is called | debug | `diagnostics changed for \(uris.count) uri(s)` |

No other event in this file is logged: `diagnosticsChanged(for:)` has exactly one statement before `emitter.fire(uris)`, and it is this one.
