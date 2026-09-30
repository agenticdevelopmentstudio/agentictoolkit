<!-- leaf: implement-extension-host-vs-1/code-api-extension-event--logging · source: extension-host-vs-code-api-extension-event.md -->

# ExtensionEvent

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `ExtensionEventEmitter` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `map(payload, context)` returns `nil` for a registration's context during delivery | error | `<path> could not build its event value in context '<context name>'; this listener is skipped` |
| A listener throws during delivery | error | `A <path> listener threw: <exception description or "<unprintable>">` |
| A listener's context cannot dispatch (`.unavailable`) during delivery | error | `A <path> listener could not be invoked: <VSCodeAPI.dispatchUnavailableMessage(for:)>` |

No other event in this file is logged: `subscribe`'s two refusals (non-function listener, disposable-creation failure) are surfaced to the extension as thrown/raised errors instead of being logged, per **subscribe-rejects-non-function-listener** and **disposable-creation-failure-rolls-back**.
