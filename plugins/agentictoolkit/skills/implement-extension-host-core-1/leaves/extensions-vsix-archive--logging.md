<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive--logging · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `VSIXArchive`

| Event | Level | Message |
|-------|-------|---------|
| — | — | Not emitted: `VSIXArchive` conforms to `Loggable` and declares `public static nonisolated let logger = makeLogger()`, but no function in the source calls `logger` — every failure is communicated to the caller as a thrown `VSIXVerificationError` or `VSIXArchiveError` case instead of a log line. |
