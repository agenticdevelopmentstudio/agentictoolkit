<!-- leaf: implement-file-system/git--logging · source: file-system-git.md -->

# GitStatusProvider

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset,
via the shared `Loggable` protocol) | Category: `GitStatusProvider`

| Event | Level | Message |
|-------|-------|---------|
| `client.status(in:)` succeeds | info | `Git status: <fileCount> files, <dirCount> directories` |
| `client.status(in:)` throws any error other than `CancellationError` | error | `Git status failed for <repoRoot.path>: <logDescription or type name>` |

`GitFileStatus+Color.swift` performs no logging of its own.
