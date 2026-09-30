<!-- leaf: implement-extension-host-core-1/extensions-extension-update-check--logging · source: extension-host-core-extensions-extension-update-check.md -->

# ExtensionUpdateCheck

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via
the shared `Loggable` protocol) | Category: `ExtensionUpdateCheck`

| Event | Level | Message |
|-------|-------|---------|
| `update(for:)` throws inside `outcome(for:)`, for any reason (no publisher, incomparable versions, or any `OpenVSXClient` failure) | debug | `No update answer for <identifier>: <String(describing: error)>` |
