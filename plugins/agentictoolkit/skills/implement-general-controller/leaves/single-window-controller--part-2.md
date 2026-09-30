<!-- leaf: implement-general-controller/single-window-controller--part-2 · source: single-window-controller.md -->

# SingleWindowController — continued (part 2)

**Rules** (cite as `implement-general-controller/single-window-controller--part-2#<slug>`):

- `main-actor-isolation` MUST
- `init-argument-storage` MUST
- `coder-init-unavailable` MUST
- `default-size` MUST
- `forces-window-front` MUST
- `window-title` MUST
- `default-content-rect` MUST
- `window-style-mask` MUST
- `min-size` MUST
- `configure-window-hook` MUST
- `lazy-window-build` MUST
- `panel-selection` MUST
- `window-construction` MUST
- `title-on-build` MUST
- `content-view-controller-on-build` MUST
- `min-size-on-build` MUST
- `accessibility-identifier` MUST
- `toolbar-button-mask` MUST
- `toolbar-button-mask-default` MUST
- `build-sequence` MUST
- `registry-registration` MUST
- `registry-registration-empty-id` MUST
- `forces-front-ordering` MUST
- `quiet-presentation` MUST
- `show-window-convenience` MUST
- `visibility-persist-on-show` MUST
- `dismiss-method` MUST
- `visibility-persist-on-dismiss` MUST
- `is-visible` MUST
- `content-fit` MUST
- `content-fit-bail` MUST
- `fit-anchor-stability` MUST
- `reentrant-fit-guard` MUST
- `content-size-provider` MUST
- `content-refit-gate` MUST
- `move-refit-debounce` MUST

## Behavioral Requirements

- **main-actor-isolation**: The type and every one of its members MUST be
  confined to the main actor (`@MainActor` on the class declaration).
- **init-argument-storage**: `init(windowID:contentViewController:)` MUST
  store the given `windowID` and content view controller for use when the
  window is later built. Neither argument is validated for emptiness or
  content at construction time; an empty `windowID` is accepted and stored
  as-is (see **registry-registration** for what an empty ID means
  downstream).
- **coder-init-unavailable**: The class MUST NOT support `NSCoder`-based
  initialization; `init?(coder:)` MUST be unavailable (marked
  `@available(*, unavailable)`, fatal if reached).
- **default-size**: The class MUST expose a `class` (type-level) `defaultSize`
  of `NSSize(width: 600, height: 480)` that subclasses may override to change
  the fallback window size used when no persisted frame exists.
- **forces-window-front**: The class MUST expose an overridable `class var
  forcesWindowFront: Bool` that subclasses set to `true` to request that
  `showWindow(_:)` additionally bring the window fully to the front (see
  **forces-front-ordering**) even when quiet presentation would otherwise
  keep it out of the way (see **quiet-presentation**).
- **window-title**: `windowTitle` MUST be an overridable computed property
  (default empty string `""`) that subclasses override to supply the
  window's title.
- **default-content-rect**: `defaultContentRect` MUST be an overridable
  computed property that returns an `NSRect` whose origin is `.zero` and
  whose size is `Self.defaultSize`, used only when no persisted frame is
  available.
- **window-style-mask**: `windowStyleMask` MUST be an overridable computed
  property (default `[.titled, .closable, .miniaturizable, .resizable]`)
  that subclasses override to change the window's chrome, e.g. to add
  `.utilityWindow` or `.hudWindow` for HUD panels.
- **min-size**: `minSize` MUST be an overridable computed property (default
  `NSSize(width: 200, height: 150)`) that subclasses override to change the
  window's minimum content size.
- **configure-window-hook**: `configureWindow(_:)` MUST be an overridable,
  no-op-by-default hook called once, after the window is built and before it
  is returned from `loadWindow()`, so subclasses can perform one-time
  additional window setup (toolbar items, appearance, etc.).
- **lazy-window-build**: The controller MUST NOT build its `NSWindow` in
  `init`; it MUST build it the first time `loadWindow()` is invoked (i.e.,
  the first time AppKit or a caller accesses `window`).
- **panel-selection**: `loadWindow()` MUST construct an `NSPanel` when
  `windowStyleMask` contains `.utilityWindow` or `.hudWindow`, and a plain
  `NSWindow` otherwise.
- **window-construction**: `loadWindow()` MUST construct the window with
  `defaultContentRect` as its content rect, `windowStyleMask` as its style
  mask, `.buffered` backing, and `deferCreation: false`.
- **title-on-build**: `loadWindow()` MUST set the built window's `title` to
  `windowTitle`.
- **content-view-controller-on-build**: `loadWindow()` MUST set the built
  window's `contentViewController` to the controller supplied at `init`.
- **min-size-on-build**: `loadWindow()` MUST set the built window's `minSize`
  to `minSize`.
- **accessibility-identifier**: `loadWindow()` MUST assign the window an
  accessibility identifier derived by slugifying `windowID` through
  `AccessibilityID.slug(_:)`, so windows are addressable in UI tests.
  Slugification splits camelCase boundaries, lowercases, and joins
  non-alphanumeric runs with hyphens.
- **toolbar-button-mask**: `loadWindow()` MUST, when a `WindowSpec` is
  registered for `windowID` (exposed through the `windowSpec` computed
  property that `WindowFrameManager.swift` adds to this class), mask the
  window's `standardWindowButton` visibility for close/miniaturize/zoom
  according to `windowSpec.toolbarButtons`, hiding any button whose
  corresponding `ToolbarButtons` option is absent from the mask.
- **toolbar-button-mask-default**: `loadWindow()` MUST leave all three
  standard window buttons at their AppKit default visibility when no
  `WindowSpec` is registered for `windowID` (the `windowSpec` computed
  property returns `nil` until one is registered).
- **build-sequence**: `loadWindow()` MUST run its steps in this order, after
  constructing the `NSWindow`/`NSPanel` and setting its title, minimum size,
  accessibility identifier, and content view controller: (1) assign the
  constructed window to `self.window`; (2) apply the toolbar button mask
  and, if HUD-configured, the HUD chrome; (3) invoke `configureWindow(_:)`
  exactly once; (4) ask `WindowFrameManager` to restore any persisted frame
  for `windowID` and apply it to the window; (5) assign `self` as the
  window's delegate. Restoring the frame before delegate assignment (step 4
  before step 5) keeps the restore from itself triggering
  `windowDidMove`/`windowDidResize` bookkeeping through the delegate.
  Running `configureWindow(_:)` before the frame restore (step 3 before step
  4) lets subclass-installed chrome — a toolbar, for instance, which changes
  how tall the title bar is — finish shaping the window before geometry is
  restored onto it. `self.window` is assigned early (step 1), not as a final
  step: registry registration is a separate, earlier event — see
  **registry-registration**, which happens in
  `init(windowID:contentViewController:)`, not as part of this sequence.
- **registry-registration**: `init(windowID:contentViewController:)` MUST
  register `self` with `WindowManager.shared.registry` under `windowID`,
  unconditionally, before any `NSWindow` is built — registration does not
  wait for `loadWindow()` or for the window to first be shown.
- **registry-registration-empty-id**: Registration with `WindowRegistry`
  MUST be a silent no-op when `windowID` is empty (the registry's own
  `register(_:)` guards on a non-empty ID); `init(windowID:contentViewController:)`
  MUST NOT crash or otherwise special-case an empty `windowID` beyond that.
  This is verified in `WindowRegistry`; `SingleWindowController` supplies no
  additional guard because none is needed.
- **forces-front-ordering**: `showWindow(_:)` MUST call `super.showWindow(sender)`
  first — which brings the window to key and orders it front through
  AppKit's standard `NSWindowController` behavior — and then, when
  `Self.forcesWindowFront` is `true`, additionally call
  `window?.orderFrontRegardless()` so the window is pulled above other
  applications' windows too. No explicit `NSApp.activate(ignoringOtherApps:)`
  call is made by this method.
- **quiet-presentation**: `showWindow(_:)` MUST, when `Self.forcesWindowFront`
  is `false`, leave the window ordered by `super.showWindow(sender)` alone
  and additionally sink it behind the desktop and order it back
  (`window.sinkBehindDesktop()`, then `window.orderBack(nil)`), so the
  window stays a real, laid-out, visible `NSWindow` — satisfying assertions
  on `isVisible`, its restored frame, and `window.screen` — without
  appearing to the person at the keyboard.
- **show-window-convenience**: The class MUST expose a parameterless
  `showWindow()` convenience that forwards to `showWindow(_:)` with a `nil`
  sender, for call sites that have no natural sender.
- **visibility-persist-on-show**: `showWindow(_:)` MUST record the window as
  visible through `WindowFrameManager.saveVisibility` when the window's
  `windowSpec.persistsVisibility` is `true`.
- **dismiss-method**: The class MUST expose a `dismiss()` method that closes
  the window (via `window?.close()` or equivalent) rather than requiring
  callers to reach through to the underlying `NSWindow`.
- **visibility-persist-on-dismiss**: `dismiss()` MUST record the window as
  hidden through `WindowFrameManager.saveVisibility` when the window's
  `windowSpec.persistsVisibility` is `true`, mirroring the `showWindow(_:)`
  behavior on the closing path.
- **is-visible**: The class MUST expose a computed `isVisible: Bool` that
  reflects the underlying window's `isVisible`, returning `false` when no
  window has been built yet.
- **content-fit**: `fitWindow(toContentSize:)` MUST resize the window's
  content area to the given size using `FrameCalculator
  .contentHuggingFrame(currentFrame:desiredFrameSize:screenVisibleFrame:
  minSize:anchors:)`, which keeps one edge of the window anchored (by default
  top-left) while the opposite edges move to accommodate the new content
  size.
- **content-fit-bail**: `fitWindow(toContentSize:)` MUST compare the
  requested size and anchor state against the last applied `ContentFit` and
  skip re-applying the frame when both are unchanged, to avoid redundant
  frame-setting work and redundant `windowDidResize` notifications on
  repeated calls with identical inputs.
- **fit-anchor-stability**: `fitWindow(toContentSize:)` MUST reuse the
  anchor point computed on the first fit for subsequent fits, rather than
  recomputing an anchor point from the window's current frame on every call,
  so the anchor edge stays stable across a sequence of content-size changes.
- **reentrant-fit-guard**: `fitWindow(toContentSize:)` MUST guard its own
  frame application so that a `windowDidResize` delegate callback triggered
  by that very frame change does not re-enter the content-refit machinery.
- **content-size-provider**: The class MUST expose a settable
  `contentSizeProvider: (() -> NSSize)?` closure property that, when set,
  supplies the desired content size for `performContentRefit()` to apply via
  `fitWindow(toContentSize:)`.
- **content-refit-gate**: `performContentRefit()` MUST be a no-op when
  `contentSizeProvider` is `nil`, and otherwise MUST call the provider and
  pass its result to `fitWindow(toContentSize:)`.
- **move-refit-debounce**: After a window move, the controller MUST debounce
  refitting by waiting 200 milliseconds before performing the refit,
  canceling and restarting that wait on every subsequent move so only the
  most recently moved-to position's timer ever fires.
