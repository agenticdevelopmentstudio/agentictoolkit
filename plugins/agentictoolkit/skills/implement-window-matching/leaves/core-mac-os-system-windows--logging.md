<!-- leaf: implement-window-matching/core-mac-os-system-windows--logging · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `SystemWindowObserver`

| Event | Level | Message |
|-------|-------|---------|
| Observation started | info | `SystemWindowObserver started, monitoring <count> applications` |
| Observation stopped | info | `SystemWindowObserver stopped` |
| App launched | info | `App launched: <appName> (PID <pid>)` |
| App terminated | info | `App terminated: <appName> (PID <pid>)` |
| Window created | info | `Window created: <app> — '<title>' (ID <id>)` |
| Window destroyed | info | `Window destroyed: ID <windowID>` |
| Title changed | debug | `Title changed: <app> — '<newTitle>' (ID <id>)` |

Interpolated strings (app names, titles) use the unified log's default private redaction; integers are public. `SystemWindowManager`, `SystemWindowAXHelper` and `SystemAccessibilityPermission` do not log, and observer creation or registration failures are not logged.
