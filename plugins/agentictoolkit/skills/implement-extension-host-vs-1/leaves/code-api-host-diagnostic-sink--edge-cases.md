<!-- leaf: implement-extension-host-vs-1/code-api-host-diagnostic-sink--edge-cases · source: extension-host-vs-code-api-host-diagnostic-sink.md -->

# HostDiagnosticSink

**Rules** (cite as `implement-extension-host-vs-1/code-api-host-diagnostic-sink--edge-cases#<slug>`):

- `null-empty-input` MUST — diagnosticsChanged(for: []) MUST still log ("diagnostics changed for 0 uri(s)") and MUST still call emitter.fire([]); …
- `boundary-values` MUST — HostDiagnosticSink enforces no minimum or maximum on uris.count; a single-element array and an array of many thousands …
- `concurrent-access` MUST — HostDiagnosticSink is @MainActor-isolated with no locking of its own; two MainThreadDiagnostics adaptors (each backing …
- `error-states` MUST — diagnosticsChanged(for:) has no dependency (no I/O, no network, no throwing call) that can fail; it cannot itself …

## Edge Cases

- **Null/empty input**: `diagnosticsChanged(for: [])` MUST still log (`"diagnostics changed for 0 uri(s)"`) and MUST still call `emitter.fire([])`; when the shared emitter has at least one live listener, that empty array is queued as one entry (per `ExtensionEventEmitter.fire`'s queue-before-open behavior — see the `extension-host-vs-code-api-extension-event` ingredient), so a window whose only fire was empty still delivers an empty `uris` array to listeners rather than delivering nothing (MUST).
- **Boundary values**: `HostDiagnosticSink` enforces no minimum or maximum on `uris.count`; a single-element array and an array of many thousands of `URL`s are logged and forwarded identically, with no truncation or batching (MUST).
- **Concurrent access**: `HostDiagnosticSink` is `@MainActor`-isolated with no locking of its own; two `MainThreadDiagnostics` adaptors (each backing a different extension's `DiagnosticCollection`) calling `diagnosticsChanged(for:)` "at the same time" from JavaScript are always serialized onto the main actor by the extension host, so there is no data race for this type to define behavior for (MUST).
- **Error states**: `diagnosticsChanged(for:)` has no dependency (no I/O, no network, no throwing call) that can fail; it cannot itself raise, throw, or return an error, so there is no failure path in this file to communicate (MUST — a fact about the source, not a gap: error handling for a failed delivery belongs to `ExtensionEventEmitter.deliver(_:)`, per the ingredient this recipe depends on).
- **Offline or disconnected state**: Not applicable — `HostDiagnosticSink` performs no network access of its own; it relays an already-in-process `[URL]` value to an in-process emitter, so there is no connectivity-loss case to define.
