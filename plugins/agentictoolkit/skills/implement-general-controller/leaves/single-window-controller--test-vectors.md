<!-- leaf: implement-general-controller/single-window-controller--test-vectors · source: single-window-controller.md -->

# SingleWindowController

## Conformance Test Vectors

| ID | Requirement | Given | When | Then |
|---|---|---|---|---|
| single-window-controller-001 | main-actor-isolation | any instance | a method is invoked while already confined to the main actor (e.g. via `MainActor.assertIsolated()`) | the assertion succeeds; no isolation violation occurs |
| single-window-controller-002 | init-argument-storage | a `windowID` and content view controller | `init(windowID:contentViewController:)` is called | both are stored for later use in `loadWindow()`, with no validation of `windowID`'s emptiness |
| single-window-controller-003 | coder-init-unavailable | any | `init?(coder:)` is invoked | a fatal/unavailable-API error occurs, not a working instance |
| single-window-controller-004 | default-size | a subclass overriding `defaultSize` | no persisted frame exists | `loadWindow()` uses the overridden size |
| single-window-controller-005 | forces-window-front, forces-front-ordering | a subclass with `forcesWindowFront == true` | `showWindow(_:)` is called | `super.showWindow(sender)` runs first, then `window?.orderFrontRegardless()` additionally pulls the window above other applications' windows |
| single-window-controller-006 | window-title | a subclass overriding `windowTitle` | `loadWindow()` runs | the built window's `title` equals the overridden value |
| single-window-controller-007 | default-content-rect | a subclass overriding `defaultContentRect`, no persisted frame | `loadWindow()` runs | the window is created with the overridden rect |
| single-window-controller-008 | window-style-mask | a subclass overriding `windowStyleMask` to include `.hudWindow` | `loadWindow()` runs | an `NSPanel` is constructed instead of `NSWindow` |
| single-window-controller-009 | min-size | a subclass overriding `minSize` | `loadWindow()` runs | the built window's `minSize` equals the overridden value |
| single-window-controller-010 | configure-window-hook | a subclass overriding `configureWindow(_:)` | `loadWindow()` runs | the override is invoked exactly once with the fully assembled window |
| single-window-controller-011 | lazy-window-build | a freshly initialized controller | `init` completes but `window` is not accessed | no `NSWindow` has been constructed |
| single-window-controller-012 | panel-selection | `windowStyleMask` contains `.utilityWindow` | `loadWindow()` runs | the constructed object is an `NSPanel` |
| single-window-controller-013 | window-construction | default configuration | `loadWindow()` runs | the window's content rect, style mask, backing, and defer flag match the documented values |
| single-window-controller-014 | title-on-build | `windowTitle` overridden to `"Example"` | `loadWindow()` runs | `window.title == "Example"` |
| single-window-controller-015 | content-view-controller-on-build | a content view controller supplied at init | `loadWindow()` runs | `window.contentViewController` is that instance |
| single-window-controller-016 | min-size-on-build | `minSize` overridden | `loadWindow()` runs | `window.minSize` equals the overridden value |
| single-window-controller-017 | accessibility-identifier | `windowID == "mySettings"` | `loadWindow()` runs | the window's accessibility identifier equals `AccessibilityID.slug("mySettings")` |
| single-window-controller-018 | toolbar-button-mask | a `WindowSpec` registered for `windowID` with `toolbarButtons == [.close]` | `loadWindow()` runs | only the close button is visible; miniaturize and zoom are hidden |
| single-window-controller-019 | toolbar-button-mask-default | no `WindowSpec` registered for `windowID` | `loadWindow()` runs | all three standard buttons keep AppKit's default visibility |
| single-window-controller-020 | build-sequence | a persisted frame for `windowID` | `loadWindow()` runs | the frame is restored and applied before `delegate` is set (so the restore does not itself trigger `windowDidMove`/`windowDidResize` bookkeeping), and `configureWindow(_:)` has already run by this point |
| single-window-controller-021 | build-sequence | any | `loadWindow()` runs | `self.window` is assigned right after `contentViewController` is set — before the toolbar button mask, HUD chrome, `configureWindow(_:)`, frame restore, and delegate assignment all run — and `configureWindow(_:)` is invoked exactly once, after the toolbar/HUD chrome steps and before the frame restore |
| single-window-controller-022 | registry-registration | any `windowID` | `init(windowID:contentViewController:)` is called | `WindowManager.shared.registry.controller(forID: windowID) === self`, even before `loadWindow()` ever runs |
| single-window-controller-023 | registry-registration-empty-id | `windowID == ""` | `init(windowID:contentViewController:)` is called | no crash occurs; the registry has no entry for the empty ID |
| single-window-controller-024 | quiet-presentation | `forcesWindowFront == false` | `showWindow(_:)` is called | the window is sunk behind the desktop and ordered back (`sinkBehindDesktop()` + `orderBack(nil)`) rather than being pulled to the front; it remains `isVisible` and keeps its restored frame |
| single-window-controller-025 | show-window-convenience | any | `showWindow()` is called | it behaves identically to `showWindow(nil)` |
| single-window-controller-026 | visibility-persist-on-show | `windowSpec.persistsVisibility == true` | `showWindow(_:)` is called | `WindowFrameManager.saveVisibility` records the window visible |
| single-window-controller-027 | dismiss-method | a visible window | `dismiss()` is called | the window closes |
| single-window-controller-028 | visibility-persist-on-dismiss | `windowSpec.persistsVisibility == true` | `dismiss()` is called | `WindowFrameManager.saveVisibility` records the window hidden |
| single-window-controller-029 | is-visible | no window built yet | `isVisible` is read | it returns `false` |
| single-window-controller-030 | content-fit | a built window | `fitWindow(toContentSize:)` is called with a new size | the window's frame changes to accommodate the content size, anchored per the current anchor |
| single-window-controller-031 | content-fit-bail | a prior fit already applied for a given size/anchor pair | `fitWindow(toContentSize:)` is called again with the same size | the frame is not re-applied |
| single-window-controller-032 | fit-anchor-stability | two consecutive fits with different sizes, the window unmoved between them | the second `fitWindow` call runs | the second fit anchors to the same edge the first fit chose, rather than recomputing the anchor from the window's current frame |
| single-window-controller-033 | reentrant-fit-guard | `fitWindow(toContentSize:)` is applying a computed frame | that frame change triggers `windowDidResize` | the resize does not trigger a nested call back into the content-refit machinery |
| single-window-controller-034 | content-size-provider | `contentSizeProvider` set to a closure returning a fixed `NSSize` | `performContentRefit()` is called | `fitWindow(toContentSize:)` is invoked with that size and the window's frame changes to match |
| single-window-controller-035 | content-refit-gate | `contentSizeProvider == nil` | `performContentRefit()` is called | no frame change occurs |
| single-window-controller-036 | move-refit-debounce | a provider set, then two moves in quick succession | the second move's notification fires | only one refit occurs, timed 200ms after the second move (the first move's pending wait is canceled and restarted, not stacked) |
| single-window-controller-037 | refit-drag-deferral | a scheduled refit fires while `NSEvent.pressedMouseButtons != 0` | the refit runs | the refit reschedules itself instead of applying immediately |
| single-window-controller-038 | move-triggers-refit | `contentSizeProvider` set | `windowDidMove(_:)` fires | a refit is scheduled; with no provider set, the same move schedules no refit |
| single-window-controller-039 | frame-persist-on-move | `windowSpec.persistsFrame == true` | `windowDidMove(_:)` fires | `WindowFrameManager.saveFrame` is called with the new frame |
| single-window-controller-040 | frame-persist-on-resize | `windowSpec.persistsFrame == true` | `windowDidResize(_:)` fires | `WindowFrameManager.saveFrame` is called with the new frame |
| single-window-controller-041 | resize-refit-guard | a resize caused by the controller's own `fitWindow(toContentSize:)` call | `windowDidResize(_:)` fires | `performContentRefit()` is not triggered |
| single-window-controller-042 | visibility-persist-on-close | `windowSpec.persistsVisibility == true` | the user clicks the window's close button | `WindowFrameManager.saveVisibility` records the window hidden |
| single-window-controller-043 | visibility-restore | `windowSpec.persistsVisibility == true` and persisted visibility is `true` | `restoreVisibilityIfNeeded()` is called | `showWindow()` is invoked |
| single-window-controller-044 | hud-configuration | any | `HUDConfiguration(floating:transparency:)` is constructed | it captures a `Bool` floating value (default `true`) and a `Double` transparency value (default `1.0`) |
| single-window-controller-045 | hud-chrome-opt-in | `configureAsHUD` never called | the window is inspected | chrome is ordinary opaque, non-floating |
| single-window-controller-046 | hud-transparency-floor | a caller-supplied transparency below `0.3` | `configureAsHUD(floating:transparency:)` or `setTransparency(_:)` is called | the applied `alphaValue` is clamped to `0.3`, not the raw value |
| single-window-controller-047 | set-floating | any | `setFloating(true)` is called | the window's `level` becomes `.floating` |
| single-window-controller-048 | set-floating | any | `setFloating(false)` is called | the window's `level` becomes `.normal` |
| single-window-controller-049 | set-transparency | any | `setTransparency(_:)` is called | `window.alphaValue` is set to the given value, clamped to `0.3...1.0`, independent of the level set by `setFloating(_:)` |
| single-window-controller-050 | singleton-protocol-conformance | a subclass adopting `SingletonWindowController` supplying `current`/`makeShared()` | the protocol extension methods are called | `ensureCurrent()`, `present()`, `isOpen()` all work without further overrides |
