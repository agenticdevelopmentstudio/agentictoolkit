<!-- leaf: implement-extension/webview-view-controller--test-vectors · source: extension-webview-view-controller.md -->

# ExtensionWebviewViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ewvc-001 | placeholder-shown-on-load | Construct the component with a `.webview` `ContributedView` and force `loadView()` to run | The view hierarchy shows an `ExtensionViewPlaceholderViewController` displaying the view's `name` and the given `extensionDisplayName`; `resolve` has not been called |
| ewvc-002 | resolve-called-once-on-first-display | Supply a `resolve` closure that records its call count; load the component's view | `resolve` was called exactly once, with the constructor's `contributedView` |
| ewvc-003 | panel-adopted-when-resolved | Supply a `resolve` closure that builds a panel and calls its completion closure before returning | After `viewDidLoad()` returns, the panel's view is the on-screen content, not the placeholder |
| ewvc-004 | panel-swap-is-idempotent | With a panel already adopted, invoke the completion closure a second time | The on-screen content is unchanged — the same view instance, not reparented |
| ewvc-005 | remains-on-placeholder-when-unresolved | Supply a `resolve` closure that returns `nil` and never calls its completion closure | After `viewDidLoad()` returns and after further run-loop turns, the content is still the initial placeholder |
| ewvc-006 | panel-removal-reverts-to-placeholder | With a resolved and adopted panel, invoke that panel's `onRemovalRequested` | The content becomes a new `ExtensionViewPlaceholderViewController` instance, distinct from the original |
| ewvc-007 | no-revert-once-discarding | With a resolved and adopted panel, call `paneContentWillBeDiscarded()`, then invoke the panel's `onRemovalRequested` | No new placeholder is built; the content is unchanged |
| ewvc-008 | teardown-forwarded-to-panel | Supply a panel that is never adopted (its completion closure is never called, so content stays the placeholder); call `paneContentWillBeDiscarded()` | The panel instance's own `paneContentWillBeDiscarded()` was called exactly once, despite never having been on screen |
| ewvc-009 | teardown-sets-discard-flag-first | Supply a panel whose `paneContentWillBeDiscarded()` synchronously invokes its own `onRemovalRequested` before returning | No new placeholder is built during or after that call; the content is unchanged |
| ewvc-010 | outgoing-title-callback-cleared | Adopt a panel conforming to `PaneTitleProviding`, then trigger a swap back to a placeholder via `onRemovalRequested` | The panel's `onPaneTitleChange` is `nil` immediately after the swap |
| ewvc-011 | incoming-title-callback-installed | Adopt a panel conforming to `PaneTitleProviding` | The panel's `onPaneTitleChange` is non-nil, and invoking it calls the component's own `onPaneTitleChange` |
| ewvc-012 | title-change-notified-on-swap | Install an `onPaneTitleChange` callback on the component, then let a panel resolve and be adopted | The component's `onPaneTitleChange` callback fires during the swap |
| ewvc-013 | pane-title-delegates-to-content | Read `paneTitle` before any panel is adopted; then adopt a panel whose `title` is "Extension Page" and read again | First read equals `contributedView.name`; second read equals "Extension Page" |
| ewvc-014 | child-view-fills-container | Load the view; inspect the constraints `show(_:)` installed on the current child's view | Exactly four constraints pin leading, trailing, top, and bottom to the container, each with a constant of 0 |
| ewvc-015 | background-tracks-theme-surface | Load the view under one active theme, read the container layer's background color; then switch the active theme | The color equals the first theme's `.surface` color immediately after load, and equals the second theme's `.surface` color after the switch, with no further action taken |
| ewvc-016 | explicit-construction-only | Call `ExtensionWebviewViewController(coder:)` | The process traps (`fatalError`); no instance is returned |
| ewvc-017 | main-actor-confined | Inspect the class declaration and its stored properties and methods | The class declaration and every one of its stored properties and methods is isolated to `@MainActor`; no member of the class is reachable off the main actor |
| ewvc-018 | no-adoption-without-completion | Supply a `resolve` closure that builds and returns a non-nil panel but never calls its completion closure | After `viewDidLoad()` returns and after further run-loop turns, the panel's view never appears in the hierarchy; the content is still the initial placeholder |
