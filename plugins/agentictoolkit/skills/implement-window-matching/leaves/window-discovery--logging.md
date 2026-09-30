<!-- leaf: implement-window-matching/window-discovery--logging · source: window-matching-window-discovery.md -->

# WindowDiscoveryViewModel

## Logging

Subsystem: main bundle identifier (`"nil"` when absent) | Category: `WindowDiscoveryViewModel`

| Event | Level | Message |
|-------|-------|---------|
| Activation attempt | info | `WindowDiscovery: activating '<title>' (PID <pid>)` — title marked public |
| Focus failure | error | `WindowDiscovery: focus failed (PID <pid>): <localizedDescription>` — reason marked public |

Discovery itself logs nothing, including the permission-denied path, which is signalled through `accessibilityDenied`.
