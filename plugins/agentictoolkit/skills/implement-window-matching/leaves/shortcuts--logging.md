<!-- leaf: implement-window-matching/shortcuts--logging · source: window-matching-shortcuts.md -->

# Window Matching Shortcuts

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`) | Category: `SystemWindowShortcutManager`

| Event | Level | Message |
|-------|-------|---------|
| Manager constructed and all handlers registered | info | `SystemWindowShortcutManager initialized, all handlers registered` |

No other event is logged: individual key-downs, out-of-range index no-ops and ignored add/remove results produce no log line from the manager (the model logs its own thrown errors).
