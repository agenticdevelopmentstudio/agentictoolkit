<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client--logging · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `OpenVSXClient`

| Event | Level | Message |
|-------|-------|---------|
| — | — | Not emitted: `OpenVSXClient` conforms to `Loggable` and declares `public static nonisolated let logger = makeLogger()`, but no method in the source calls `logger` — every failure is communicated to the caller as a thrown `OpenVSXError` case instead of a log line. |
