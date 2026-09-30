<!-- leaf: implement-general-controller/floating-chooser-panel-controller--test-vectors · source: floating-chooser-panel-controller.md -->

# FloatingChooserPanelController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| floating-chooser-panel-controller-001 | hosts-content-as-child-controller | Construct the controller with a content VC and any `contentRect` | `window.contentViewController` is the container controller; the content VC appears in the container's `children`. |
| floating-chooser-panel-controller-002 | pins-content-to-container-edges | Inspect the container's view constraints after `init` | The content view's top, leading, trailing, and bottom anchors are each pinned to the container view's matching anchor with constant 0. |
| floating-chooser-panel-controller-003 | uses-titled-panel-style-mask | Inspect `window.styleMask` after `init` | `styleMask == [.titled, .closable, .fullSizeContentView]`. |
| floating-chooser-panel-controller-004 | hides-title-text | Inspect `window.titleVisibility` and `titlebarAppearsTransparent` | `titleVisibility == .hidden`; `titlebarAppearsTransparent == true`. |
| floating-chooser-panel-controller-005 | hides-standard-window-buttons | Inspect `window.standardWindowButton(_:)` for `.closeButton`, `.miniaturizeButton`, `.zoomButton` | Each returns a button with `isHidden == true`. |
| floating-chooser-panel-controller-006 | floats-above-normal-windows | Inspect `window.level` | `level == .floating`. |
| floating-chooser-panel-controller-007 | joins-all-spaces-and-full-screen-auxiliary | Inspect `window.collectionBehavior` | Contains `.canJoinAllSpaces` and `.fullScreenAuxiliary`. |
| floating-chooser-panel-controller-008 | is-not-user-resizable | Inspect `window.styleMask`; attempt to drag-resize the shown window | `styleMask` does not contain `.resizable`; the drag has no effect. |
| floating-chooser-panel-controller-009 | survives-close-without-releasing | Call `close()`, then reuse the same controller instance in a later `show()` | `window.isReleasedWhenClosed == false`; the same instance reopens successfully. |
| floating-chooser-panel-controller-010 | rejects-coder-initialization | Attempt to construct via `init?(coder:)` | Unavailable at compile time; a forced runtime call traps via `fatalError()`. |
| floating-chooser-panel-controller-011 | positions-on-pointer-screen | Two-screen setup, mouse over screen B; call `show()` | Panel is positioned relative to screen B's visible frame. |
| floating-chooser-panel-controller-012 | falls-back-to-main-screen | Mouse location outside every screen's frame; call `show()` | Panel positions relative to `NSScreen.main`'s visible frame. |
| floating-chooser-panel-controller-013 | falls-back-to-centering-without-visible-frame | Resolved screen's `visibleFrame` is unavailable; call `show()` | `window.center()` runs instead of the pointer-relative calculation. |
| floating-chooser-panel-controller-014 | centers-horizontally-on-screen | Visible frame width 1000pt, window width 400pt; call `show()` | Window `origin.x == visibleFrame.midX - 200`. |
| floating-chooser-panel-controller-015 | offsets-top-edge-by-fixed-fraction | Visible frame height 1000pt; call `show()` | Window's top edge (`origin.y + height`) equals `visibleFrame.maxY - 200`. |
| floating-chooser-panel-controller-016 | activates-app-before-showing | Call `show()` with another app frontmost | `NSApp.activateUnlessQuiet()` runs before `showWindow(nil)`/`makeKeyAndOrderFront(nil)`. Manual/integration-only: the recipe names no injected seam for observing `NSApp.activateUnlessQuiet()`, so this requires swizzling to verify. |
| floating-chooser-panel-controller-017 | respects-quiet-activation | `QuietWindowPresentation.isEnabled == true`; call `show()` | `activate(ignoringOtherApps:)` is not invoked; the window still shows and orders front. Manual/integration-only: the recipe names no injected seam for replacing the static `QuietWindowPresentation.isEnabled`, so this requires swizzling to verify. |
| floating-chooser-panel-controller-018 | shows-and-takes-key-before-initial-focus | Subclass overrides `takeInitialFocus()` to record `window.isKeyWindow` | Recorded value is `true`. |
| floating-chooser-panel-controller-019 | reshows-idempotently | Call `show()` twice in succession | Exactly one window exists; the second call repositions/refocuses it. |
| floating-chooser-panel-controller-020 | defaults-initial-focus-hook-to-no-op | Call `show()` on the base class directly (no override); record the first responder immediately before and after the call | First responder after `show()` is whatever AppKit's own `makeKeyAndOrderFront(nil)` set it to; it is unchanged from that value once `takeInitialFocus()` returns, since the base hook has an empty body. No crash. |
| floating-chooser-panel-controller-021 | dismisses-on-focus-loss-by-default | Read `dismissesOnFocusLoss` on the base class with no override | Returns `true`. |
| floating-chooser-panel-controller-022 | closes-on-focus-loss-when-enabled | `dismissesOnFocusLoss == true`, window visible, `isDismissing == false`; window resigns key | `close()` is invoked and the window closes. |
| floating-chooser-panel-controller-023 | ignores-focus-loss-when-disabled | Subclass overrides `dismissesOnFocusLoss` to `false`; window resigns key | `close()` is not invoked; window remains open. |
| floating-chooser-panel-controller-024 | ignores-focus-loss-while-already-dismissing | `isDismissing == true`; window resigns key while it is still `true` | `close()` is not invoked a second time. |
| floating-chooser-panel-controller-025 | ignores-focus-loss-when-not-visible | `window.isVisible == false`; simulate `windowDidResignKey` | `close()` is not invoked. |
| floating-chooser-panel-controller-026 | guards-close-against-reentrancy | Call `close()` re-entrantly from within `panelWillClose()` | The nested call returns immediately without a second `super.close()`. |
| floating-chooser-panel-controller-027 | resets-dismissing-flag-after-close | Call `close()` to completion, then call `close()` again | The second call proceeds normally (`isDismissing` was reset to `false`). |
| floating-chooser-panel-controller-028 | calls-panel-will-close-on-window-close | Subclass overrides `panelWillClose()` with a counter; dismiss the panel once | Counter equals 1. |
| floating-chooser-panel-controller-029 | defaults-panel-will-close-hook-to-no-op | Close the base class directly (no override); compare controller state before and after | `isDismissing` ends `false` and the window ends closed, with no other controller state changed beyond that; no crash. |
| floating-chooser-panel-controller-030 | decides-size-via-subclass-content-rect | Construct two instances with `contentRect` A (200×100) and B (400×300) | Each window's initial frame size matches its own `contentRect`, independent of the other. |
| floating-chooser-panel-controller-031 | guards-show-against-missing-window | Set `window` to `nil` on a constructed controller, then call `show()` | `position(_:)`, `NSApp.activateUnlessQuiet()`, `showWindow(nil)`, and `takeInitialFocus()` are not invoked; `show()` returns immediately with no effect. |
| floating-chooser-panel-controller-032 | falls-back-to-centering-without-visible-frame | No screen's frame contains the mouse location, and `NSScreen.main` is also `nil`; call `show()` | `window.center()` runs instead of the pointer-relative calculation; no crash from the nil screen. |
