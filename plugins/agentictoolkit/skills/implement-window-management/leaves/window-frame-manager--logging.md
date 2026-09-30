<!-- leaf: implement-window-management/window-frame-manager--logging · source: window-management-window-frame-manager.md -->

# WindowFrameManager

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `WindowFrameManager`

| Event | Level | Message |
|-------|-------|---------|
| Restore with no registered spec | warning | `WindowFrameManager: no spec for '<id>'` |
| Restore from a same-set placement | debug | `WindowFrameManager: restored '<id>' exact=<Bool>` |
| Restore into a new screen set | debug | `WindowFrameManager: placed '<id>' in new set '<setID>'` |
| Legacy v1 migration | debug | `WindowFrameManager: migrated legacy state for '<id>'` |
| Reposition after a screen change | debug | `WindowFrameManager: repositioned '<id>' after screen change` |

Ids and set ids are logged with public privacy. Saves, resets, visibility calls and storage failures are not logged.
