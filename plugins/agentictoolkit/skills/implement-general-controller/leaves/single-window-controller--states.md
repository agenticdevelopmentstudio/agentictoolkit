<!-- leaf: implement-general-controller/single-window-controller--states · source: single-window-controller.md -->

# SingleWindowController

## States

| State | Behavior | Source |
|---|---|---|
| Not yet built (`window` never accessed) | No `NSWindow` exists; `isVisible` returns `false`; registry already has an entry for `windowID` from `init` | `loadWindow()` is lazy; `isVisible`; **registry-registration** |
| Built, hidden | Window exists, but not on screen | default post-`loadWindow()` state before `showWindow` |
| Built, visible | Window on screen; frame/visibility persisted on further move/resize/close when opted in | `showWindow(_:)`, delegate methods |
| Built, HUD-configured | Translucent, optionally floating, chrome applied once via `configureAsHUD` | `configureAsHUD(floating:transparency:)` |
| Applying a content fit | Concurrent `windowDidResize`-driven refit suppressed | `fitWindow(toContentSize:)`, `windowDidResize(_:)`, **reentrant-fit-guard** |
| Awaiting move-settle | A debounced refit is pending; refit deferred while mouse button held | **move-refit-debounce**, **refit-drag-deferral** |
| Pressed | Not applicable — this class manages a window shell, not a pressable control; press-state feedback belongs to whatever control the hosted content view controller renders. | `SingleWindowController.swift` has no control-rendering code |
| Disabled | Not applicable — a window controller has no enabled/disabled state of its own; if the app wants to disable interaction it disables specific controls in the content view controller. | same |
| Focused | Not applicable at this layer beyond ordinary AppKit key-window handling, which this class does not customize. | `SingleWindowController.swift` overrides no key-window/first-responder logic |
| Loading | Not applicable — window construction in `loadWindow()` is synchronous; there is no asynchronous loading state to represent. | `loadWindow()` |
