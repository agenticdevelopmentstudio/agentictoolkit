<!-- leaf: implement-composable-tabs/view-registry--logging · source: composable-tabs-view-registry.md -->

# ComposableTabsViewRegistry

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`) | Category: `ComposableTabsViewRegistry`

| Event | Level | Message |
|-------|-------|---------|
| `unregister(.placeholder)` called | error | `Refusing to unregister {viewID} — every registry resolves it` |
| `makeContentViewController(for:...)` called with an unregistered view id | error | `No view registered for {viewID} — showing a placeholder` |

Both messages interpolate the view id's `rawValue` with `privacy: .public`,
per `Self.logger.error(...)`. `Loggable`'s default (used unmodified here)
derives the subsystem from `Bundle.main.bundleIdentifier` and the category
from the conforming type's name, `ComposableTabsViewRegistry`.
