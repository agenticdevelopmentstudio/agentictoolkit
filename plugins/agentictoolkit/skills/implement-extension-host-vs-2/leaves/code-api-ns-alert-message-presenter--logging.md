<!-- leaf: implement-extension-host-vs-2/code-api-ns-alert-message-presenter--logging · source: extension-host-vs-code-api-ns-alert-message-presenter.md -->

# NSAlertMessagePresenter

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `NSAlertMessagePresenter`

| Event | Level | Message |
|-------|-------|---------|
| `sheetWindow()` returns `nil` while presenting a message | error | `Dropped a show*Message; no window for its sheet: ` followed by `alert.messageText`, logged with `privacy: .public` |
