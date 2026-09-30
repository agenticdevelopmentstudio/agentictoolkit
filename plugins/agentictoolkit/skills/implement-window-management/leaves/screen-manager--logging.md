<!-- leaf: implement-window-management/screen-manager--logging · source: window-management-screen-manager.md -->

# ScreenManager

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `ScreenManager`

| Event | Level | Message |
|-------|-------|---------|
| Delivered screen change | info | `ScreenManager: <change> → set '<currentSetID>'` (both values public) |

Spurious notifications, touches, reconciles, loads and saves are not logged.
