<!-- leaf: implement-extension-host-vs-1/code-api-host-diagnostic-sink--test-vectors · source: extension-host-vs-code-api-host-diagnostic-sink.md -->

# HostDiagnosticSink

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| host-diagnostic-sink-001 | fire-forwards-uris-unchanged, fire-called-unconditionally | Construct `HostDiagnosticSink(emitter: e)` where `e` has zero listeners; call `diagnosticsChanged(for: [URL(fileURLWithPath: "/one.txt")])` | `e.fire` runs with exactly `[URL(fileURLWithPath: "/one.txt")]`; end to end, this is `MainThreadDiagnosticsTests.eachOfTheFiveMutatingOperationsProducesAnEvent`'s step 1 (`c.set(vscode.Uri.file('/one.txt'), d)`), which reaches the real `HostDiagnosticSink` and records `/one.txt` at the listener |
| host-diagnostic-sink-002 | fire-called-unconditionally, log-before-fire | Call `diagnosticsChanged(for: [])` directly | `Self.logger.debug` logs `"diagnostics changed for 0 uri(s)"` and `emitter.fire([])` is still called once; no early return on an empty array |
| host-diagnostic-sink-003 | log-before-fire | Call `diagnosticsChanged(for: [urlA, urlB])` | `Self.logger.debug` runs (message `"diagnostics changed for 2 uri(s)"`) before `emitter.fire([urlA, urlB])` runs — traced to the method body's statement order |
| host-diagnostic-sink-004 | one-emitter-shared-across-adaptors, fire-forwards-uris-unchanged | Build a `HostDiagnosticSink` and a `MainThreadDiagnostics` sharing one `ExtensionEventEmitter<[URL]>` (the `makeEventWiring(store:)` pattern); install an `onDidChangeDiagnostics` listener; call `c.set(vscode.Uri.file('/a.txt'), d)` then `c.delete(vscode.Uri.file('/b.txt'))` inside one window, then close the window | The listener receives one event whose `uris` are `["/a.txt", "/b.txt"]` — `MainThreadDiagnosticsTests.twoMutationsInOneWindowArriveAsOneEventCarryingBothUris`, which exercises `HostDiagnosticSink.diagnosticsChanged(for:)` twice and the shared emitter's coalescing once |
| host-diagnostic-sink-005 | emitter-required-no-default | Attempt `HostDiagnosticSink()` with no arguments | Fails to compile: `init(emitter:)` declares no default for `emitter` |
| host-diagnostic-sink-006 | main-actor-isolation, non-sendable-confinement | Attempt to call `diagnosticsChanged(for:)` on a `HostDiagnosticSink` instance from a context not already isolated to `@MainActor`, with no `await` | Fails to compile: the call crosses actor isolation without a hop, since neither `HostDiagnosticSink` nor `ExtensionDiagnosticSink` is `Sendable` and both are `@MainActor` |
| host-diagnostic-sink-007 | protocol-conformance, loggable-conformance | Inspect `HostDiagnosticSink`'s declared conformances | Declares exactly `ExtensionDiagnosticSink` (in the primary declaration) and `Loggable` (in its own extension), satisfied by `diagnosticsChanged(for:)` and `static nonisolated let logger` respectively |
