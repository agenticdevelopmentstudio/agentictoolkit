<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-diagnostics--logging · source: extension-host-vs-code-api-main-thread-diagnostics.md -->

# MainThreadDiagnostics

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| An array passed to `VSCodeAPI.arrayLength(of:)` (via `diagnosticArray`/`setEntriesArray`) reports a length over 100,000 | error | (logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this file is logged: this file itself contains no direct `logger.debug`/`logger.error` call. `VSCodeAPI.raise(_:in:)` — which every raised message above goes through — logs only in the extremely rare case that `JSValue(newErrorFromMessage:in:)` itself returns `nil`, not on the ordinary path of raising a message; every other decode failure surfaces to the caller as a thrown JS error or a `nil`/`undefined` return rather than a log line. `HostDiagnosticSink.diagnosticsChanged(for:)` (not part of this file's given source) logs its own `"diagnostics changed for <count> uri(s)"` debug line on every mutation this file reports to it; that log site belongs to the sink, not to this file.
