<!-- leaf: implement-extension-host-vs-2/code-api-uri--logging · source: extension-host-vs-code-api-uri.md -->

# Uri

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol `VSCodeAPI` conforms to) | Category: `VSCodeAPI`

| Event | Level | Message |
|-------|-------|---------|
| `installUriClass(in:)` failure | error | `Could not install the 'vscode.Uri' class in context '<name(of: context)>'; it stays the shim's not-implemented stub` |

This is the one logging call `Uri.swift` makes (**class-install-failure-returns-nil-and-logs**); no other member of this file writes to `VSCodeAPI.logger`, and `url(from:in:)`/`uriValue(for:in:)` return `nil` on every failure path with no log call of their own.
