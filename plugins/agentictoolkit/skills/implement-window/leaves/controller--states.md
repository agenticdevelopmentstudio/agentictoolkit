<!-- leaf: implement-window/controller--states · source: window-controller.md -->

# WindowController

## States

| State | Behavior |
|-------|------------------|
| Default (matching content type) | `viewController` returns `contentViewController` downcast to `ViewControllerType` |
| Mismatched or absent content view controller | `viewController` returns `nil` |
| `WindowContentViewController` constructed, view not yet loaded | `contentView` already exists (set at `init`); `view` has not been created yet — AppKit's normal lazy `NSViewController.loadView()` timing applies |
| `WindowContentViewController` view loaded | `self.view === contentView` |
| Pressed | Not applicable — neither type is an interactive control; the component renders nothing and has no press-state code. |
| Disabled | Not applicable — neither type has an enabled/disabled state of its own. |
| Focused | Not applicable — neither class overrides key-view or first-responder handling. |
| Loading | Not applicable — `viewController`'s cast and `loadView()`'s view assignment are both synchronous; there is no asynchronous loading state. |
