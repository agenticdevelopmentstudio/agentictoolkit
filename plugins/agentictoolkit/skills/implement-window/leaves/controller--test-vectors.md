<!-- leaf: implement-window/controller--test-vectors · source: window-controller.md -->

# WindowController

## Conformance Test Vectors

| ID | Requirements | Input | Action | Expected |
|----|-------------|-------|--------|----------|
| window-controller-001 | inherits-single-window-controller-lifecycle | a `WindowController<SomeVC>` subclass instance | `showWindow()` is called | the window builds, shows, and persists frame/visibility exactly as `SingleWindowController` specifies |
| window-controller-002 | exposes-typed-view-controller-accessor | a `WindowController<SomeVC>` whose `contentViewController` is a `SomeVC` instance | `viewController` is read | the same instance is returned, typed as `SomeVC` |
| window-controller-003 | returns-nil-for-non-matching-content-view-controller | a `WindowController<SomeVC>` whose `contentViewController` is `nil` or a different `NSViewController` subclass | `viewController` is read | `nil` is returned |
| window-controller-004 | declares-no-additional-initializer | any `WindowController<T>` subclass | attempt to call `init(windowID:contentViewController:)`, and separately attempt to call `init?(coder:)` | the `init(windowID:contentViewController:)` call compiles and constructs the instance; the `init?(coder:)` call does not compile, since `WindowController` declares no initializer of its own and inherits `SingleWindowController`'s `@available(*, unavailable)` `init?(coder:)` |
| window-controller-005 | exposes-typed-content-view-property | a `WindowContentViewController<NSView>` built with `init(contentView:)` | `contentView` is read | it returns the exact instance passed to `init` |
| window-controller-006 | initializes-view-controller-with-supplied-content-view | a view instance `v` | `WindowContentViewController(contentView: v)` is constructed | `contentView === v` and the instance is a fully initialized `NSViewController` |
| window-controller-007 | provides-parameterless-convenience-initializer | a `ViewType` with a working parameterless initializer | `WindowContentViewController<ViewType>()` is constructed | `contentView` is a freshly constructed `ViewType()` instance |
| window-controller-008 | fails-at-runtime-on-coder-initialization | a `WindowContentViewController<ViewType>` type | `init?(coder:)` is invoked from a death test run in a separate process (an in-process `XCTest` cannot assert a process trap; treat as review-only where a death-test harness is unavailable) | the process traps with `fatalError("init(coder:) has not been implemented")` |
| window-controller-009 | installs-content-view-directly-in-load-view | a constructed `WindowContentViewController` | `loadView()` runs (triggered by first access to `view`) | `self.view === contentView`, with no nib loaded |
