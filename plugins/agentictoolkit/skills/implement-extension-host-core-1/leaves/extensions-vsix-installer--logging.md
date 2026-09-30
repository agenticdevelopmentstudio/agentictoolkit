<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer--logging · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `VSIXInstaller`

| Event | Level | Message |
|-------|-------|---------|
| A superseded directory was left on disk because it could not be removed after an otherwise successful install | warning | `Installed <identifier> but could not remove the superseded copy at <path>: <reason>` |
| `moveIntoPlace`'s rollback (moving the aside back to `destination`) failed after the payload move into `destination` had also failed | error | `Could not put the previous <destination.lastPathComponent> back from <aside.lastPathComponent>: <reason>` |
| `recoverInterruptedInstalls()` failed to restore or discard a crash-orphaned aside | error | `Could not finish the interrupted replacement of <replaced>: <reason>` |
