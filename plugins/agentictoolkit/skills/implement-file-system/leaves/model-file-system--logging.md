<!-- leaf: implement-file-system/model-file-system--logging · source: file-system-model-file-system.md -->

# File Browser FileSystem Model

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol) |
Category: `DirectoryWatchCoordinator` or `FileSystemWatcher`, one category
per conforming type — `Loggable.category` derives it from the type name.

| Event | Level | Message | Category |
|-------|-------|---------|----------|
| Sync applied | info | `Sync complete for <rootURL.lastPathComponent>` | `DirectoryWatchCoordinator` |
| Change batch received | debug | `FS changes: <count> path(s) in <rootURL.lastPathComponent>` | `DirectoryWatchCoordinator` |
| Watcher started | info | `Started file system watcher for <rootPath>` (path logged with `privacy: .public`) | `FileSystemWatcher` |
| Watcher stopped | info | `Stopped file system watcher` | `FileSystemWatcher` |
| Stream creation failed | error | `Failed to create FSEvent stream for <rootPath>` | `FileSystemWatcher` |
