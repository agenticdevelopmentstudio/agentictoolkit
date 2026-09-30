<!-- leaf: implement-window-management/window-manager--logging · source: window-management-window-manager.md -->

# WindowManager

## Logging

Subsystem: `com.agentic-cookbook.agentictoolkit` | Category: `WindowManager`

| Event | Level | Message |
|-------|-------|---------|
| Persisted-visible window with no factory and no live controller during `restoreOnLaunch()` | error | `restoreOnLaunch: visible window '<id>' has no registered factory` (ID public) |

Registry changes, storage reads and writes, codec failures, reopen decisions, document-open failures and screenshot failures are not logged.
