---
id: 3f6268b8-410d-4d3c-979c-2a9f9f1534f3
title: SingleWindowController
domain: agentictoolkit://recipes/single-window-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit NSWindowController base that lazily builds a single NSWindow from
  subclass configuration, persists its frame and visibility, and supports quiet presentation
  and HUD chrome.
platforms:
- swift
- macos
tags:
- window-controller
- frame-persistence
- hud
- singleton
- appkit
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
- agentictoolkit://recipes/window-controller
- agentictoolkit://recipes/composable-tabs-window-controller
references: []
approved-by: ''
approved-date: ''
---

# SingleWindowController

## Overview

`SingleWindowController` is an `open`, `@MainActor`-isolated `NSWindowController` /
`NSWindowDelegate` base class for AppKit apps that manage exactly one live
`NSWindow` per logical `windowID`. A subclass supplies a `windowID` and a
content view controller at `init`, and may override `windowTitle`,
`defaultContentRect`, `windowStyleMask`, `minSize`, and `configureWindow(_:)`
to shape the window before it is first shown. The window itself is not built
in `init` — it is built lazily, the first time AppKit calls `loadWindow()`
(driven by the first access to `window` — typically the first `showWindow`
call), from an `NSPanel` if `windowStyleMask` includes `.utilityWindow` or
`.hudWindow`, otherwise a plain `NSWindow`.

Once built, the controller wires itself to two toolkit-wide subsystems: the
`WindowFrameManager` (via the `windowSpec` computed property that
`WindowFrameManager.swift` adds to this class in an extension), which restores
and re-saves the window's frame and visibility, and the `WindowRegistry`
(`WindowManager.shared.registry`), which tracks one live controller per
`windowID` so callers can look an open window up by ID. The controller also
supports "content-hugging" resizing through `fitWindow(toContentSize:)`, an
optional `HUDConfiguration` for translucent floating utility windows, and
conformance to `SingletonWindowController` for call sites that want a single
shared instance addressable as `Self.current`.

The class's own header doc comment shows a `Usage` example that calls
`super.init(windowID:)` with a single argument and overrides a
`makeContentViewController() -> NSViewController?` factory method (also
mentioning a `makeContentView()`). Neither of those exists anywhere in the
implementation below: the only initializer is the two-argument
`init(windowID:contentViewController:)`, and there is no content-factory
override point at all — the content view controller is a fixed, required
constructor argument (see Design Decisions for how this recipe treats the
mismatch).

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
- **refit-drag-deferral**: The debounced refit MUST check
  `NSEvent.pressedMouseButtons` and, if a mouse button is currently held
  (the user is still dragging the window), reschedule itself rather than
  performing the refit immediately, so a refit does not fight an
  in-progress drag.
- **move-triggers-refit**: `windowDidMove(_:)` MUST schedule a refit (see
  **move-refit-debounce**) only when `contentSizeProvider` is non-nil; with
  no provider set, a move MUST NOT schedule any refit work.
- **frame-persist-on-move**: `windowDidMove(_:)` MUST persist the window's
  new frame through `WindowFrameManager.saveFrame` when
  `windowSpec.persistsFrame` is `true`.
- **frame-persist-on-resize**: `windowDidResize(_:)` MUST persist the
  window's new frame through `WindowFrameManager.saveFrame` when
  `windowSpec.persistsFrame` is `true`, mirroring the move-triggered save.
- **resize-refit-guard**: `windowDidResize(_:)` MUST skip triggering
  `performContentRefit()` when the resize was caused by the controller's own
  `fitWindow(toContentSize:)` call (see **reentrant-fit-guard**), so the
  refit path does not recursively re-trigger itself.
- **visibility-persist-on-close**: `windowWillClose(_:)` MUST record the
  window as hidden through `WindowFrameManager.saveVisibility` when
  `windowSpec.persistsVisibility` is `true`, so closing the window via its
  own close button (not just via `dismiss()`) is captured.
- **visibility-restore**: `restoreVisibilityIfNeeded()` MUST call
  `showWindow()` when `windowSpec.persistsVisibility` is `true` and the
  persisted visibility state (`WindowFrameManager.loadVisibility`) is
  `true`; otherwise it MUST leave the window unshown.
- **hud-configuration**: The class MUST define a nested `HUDConfiguration`
  struct with a `floating: Bool` field (default `true`) and a
  `transparency: Double` field (default `1.0`), captured by
  `configureAsHUD(floating:transparency:)`.
- **hud-chrome-opt-in**: `configureAsHUD(floating:transparency:)` MUST be the
  only entry point that applies HUD-specific chrome (background translucency
  and, when floating, a floating window level); a window that never calls it
  MUST render with ordinary opaque, non-floating chrome.
- **hud-transparency-floor**: `configureAsHUD(floating:transparency:)` and
  `setTransparency(_:)` MUST clamp the given transparency value to the range
  `0.3...1.0` before applying it as `alphaValue`, so a HUD window can never
  be set fully transparent (invisible but still clickable).
- **set-floating**: `setFloating(_:)` MUST set the window's `level` to
  `.floating` when `true`, and to `.normal` when `false`.
- **set-transparency**: `setTransparency(_:)` MUST set the window's
  `alphaValue` (not `backgroundColor`) to the given value clamped per
  **hud-transparency-floor**, independent of the floating level set by
  `setFloating(_:)`.
- **singleton-protocol-conformance**: A subclass that adopts
  `SingletonWindowController` MUST get `ensureCurrent()`, `present()`, and
  `isOpen()` from the protocol extension without additional implementation,
  provided it supplies `static var current` and `static func makeShared()`.
- **singleton-ensure-current**: `ensureCurrent()` MUST create the shared
  instance via `makeShared()` and assign it to `current` only when `current`
  is `nil`, and MUST leave an existing `current` instance untouched
  otherwise (i.e., only one shared instance is created per process, reused
  across calls).
- **singleton-present**: `present()` MUST call `ensureCurrent()` and then
  call `showWindow()` on the resulting instance.
- **singleton-is-open**: `isOpen()` MUST return `false` when `current` is
  `nil`, and otherwise MUST return the current instance's `isVisible`.

## Appearance

| Element | Value | Source |
|---|---|---|
| Default window size | 600 × 480 pt | `Self.defaultSize` |
| Default minimum size | 200 × 150 pt | `minSize` |
| Default style mask | titled, closable, miniaturizable, resizable | `windowStyleMask` default |
| HUD style mask | adds `.utilityWindow` / `.hudWindow` | subclass override, detected by `loadWindow()`'s panel-class check |
| HUD transparency | subclass-supplied value, clamped to `0.3...1.0` | `configureAsHUD(floating:transparency:)` |
| Background color | Not applicable — the base class sets no explicit background color; a HUD window's translucency is the only appearance concern this class owns, and it is described above. Any theme-token background belongs to the hosted content view controller, not to this class. | `SingleWindowController.swift`; contrast with content-view-level theme observers such as `ThemePaletteObserver` |

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

## Accessibility

- **Role**: Not applicable beyond AppKit's own default window role; the class
  does not set or alter `accessibilityRole`.
- **Label**: The window's accessibility identifier (not label) is set
  explicitly, to `AccessibilityID.slug(windowID)`, in `loadWindow()`, so UI
  tests can address the window by a stable, derived identifier. The window's
  human-facing title (used as its accessible name by AppKit's own window
  accessibility support) is `windowTitle`, supplied by the subclass.
- **Announcements**: Not applicable — the base class performs no
  `NSAccessibility.post(element:notification:)` calls of its own; window
  appearance/disappearance announcements are handled by AppKit's standard
  window-server behavior, not by this class.
- **Keyboard navigation**: Not applicable at this layer — key-view loops and
  first-responder handling belong to the hosted content view controller, not
  to `SingleWindowController`, which never overrides `NSResponder` key
  handling.
- **Touch target size**: Not applicable — this class manages a window, not a
  tappable control; standard title-bar buttons keep AppKit's own built-in
  target sizes, which this class does not adjust (see `applyToolbarButtonMask`
  below, which only hides/shows the standard buttons, never resizes them).

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
| single-window-controller-051 | singleton-ensure-current | `current == nil` | `ensureCurrent()` is called twice | `makeShared()` runs once; the second call reuses the first instance |
| single-window-controller-052 | singleton-present | `current == nil` | `present()` is called | a shared instance is created and shown |
| single-window-controller-053 | singleton-is-open | `current == nil` | `isOpen()` is called | it returns `false` |

## Edge Cases

- **Empty `windowID`**: `WindowRegistry.register(_:)` silently skips
  registration when `windowID` is empty; the controller still builds and
  shows a window, it simply cannot be looked up by ID afterward. This is a
  deliberate no-op guard in `WindowRegistry`, not an error path.
- **Duplicate `windowID` across two live controllers**: `WindowRegistry`'s own
  documentation states its "one live controller per ID" assumption;
  registering a second controller under an ID already in use replaces the
  prior registry entry, so `controller(forID:)` returns only the most
  recently registered instance. The prior controller's window is unaffected
  by the replacement — the registry simply stops tracking it.
- **`fitWindow(toContentSize:)` called with a zero or negative dimension**:
  `fitWindow(toContentSize:)` guards against a non-positive width or height
  by returning immediately without applying any frame change; a degenerate
  size therefore never reaches `FrameCalculator.contentHuggingFrame` or
  AppKit's own `minSize` clamping (`minSize: windowSpec?.minSize ??
  window.minSize` is only ever threaded into a fit that actually runs).
- **Concurrent access from multiple threads**: Not applicable — the whole
  class is `@MainActor`-isolated, so the compiler prevents concurrent access
  from another thread; there is no runtime race to defend against.
- **Error/failure states**: Not applicable — none of this class's APIs are
  throwing or failable; `NSWindow` construction itself cannot fail with the
  parameters used here, so there is no error path to define.
- **Offline/disconnected state**: Not applicable — this class has no network
  dependency.
- **Unbounded settle-wait while the mouse button is held**: the debounced
  refit (see **move-refit-debounce**, **refit-drag-deferral**) reschedules
  itself indefinitely as long as `NSEvent.pressedMouseButtons` reports a
  held button, with no maximum retry count; a pathologically long drag
  defers the refit for the duration of the drag rather than firing early
  with a stale frame. This is a deliberate tradeoff (see Design Decisions),
  not an unhandled failure.
- **`configureWindow(_:)` mutates the delegate or frame**: Because the hook
  runs before delegate assignment and frame restoration (see
  **build-sequence**), any delegate-firing change `configureWindow(_:)`
  makes (e.g. resizing the window) is observed by `windowDidResize(_:)` like
  any other resize, including its `windowSpec.persistsFrame` save path.

## Configuration

| Option | Type | Effect | Source |
|---|---|---|---|
| `windowID` | `String` | Init-time identity used for registry lookup and frame/visibility persistence keying | `init(windowID:contentViewController:)` |
| `contentViewController` | `NSViewController` | Init-time, fixed content of the window | `init(windowID:contentViewController:)` |
| `windowTitle` (override) | `String` | Window's title bar text | computed property |
| `defaultContentRect` (override) | `NSRect` | Fallback frame when nothing is persisted | computed property |
| `windowStyleMask` (override) | `NSWindow.StyleMask` | Chrome and, via `.utilityWindow`/`.hudWindow`, whether an `NSPanel` is built | computed property |
| `minSize` (override) | `NSSize` | Window's minimum content size | computed property |
| `configureWindow(_:)` (override) | `(NSWindow) -> Void` | One-time additional setup after full assembly | overridable method |
| `contentSizeProvider` | `(() -> NSSize)?` | Enables content-hugging refit after moves | settable property |
| `forcesWindowFront` (class override) | `Bool` | Whether `showWindow` additionally orders the window fully to front regardless of quiet presentation | class var |
| `configureAsHUD(floating:transparency:)` | `(Bool, Double)` | Opts the window into translucent/floating HUD chrome | method call |

## Deep Linking

Not applicable — `SingleWindowController` has no URL-scheme or deep-link
handling of its own; a subclass that wants deep-link-driven presentation
would call `present()`/`showWindow()` from its own link handler, which is
outside this class's responsibility.

## Localization

- `windowTitle` is an overridable AppKit `String` property, not a SwiftUI
  `Text`/`LocalizedStringKey` binding. The base class supplies only the
  empty-string default; whichever plain `String` a subclass returns from its
  override is assigned directly to `NSWindow.title` and is therefore
  unlocalized unless the subclass itself localizes it (e.g. via
  `NSLocalizedString`). This is the subclass's responsibility, not this
  class's — the base class introduces no localizable or unlocalized string
  literal of its own.

## Accessibility Options

- **Reduce Motion**: Not applicable — the class has no animation code path;
  window moves/resizes it performs (`fitWindow(toContentSize:)`, frame
  restoration) are instantaneous frame assignments, not animated transitions.
- **Increase Contrast**: Not applicable — the base class sets no colors of
  its own beyond HUD transparency, which is a deliberate translucency effect
  rather than a contrast-relevant foreground/background pairing.
- **Reduce Transparency**: NEEDS REVIEW: Not implemented in source. Not
  applicable to the base (non-HUD) configuration,
  since no window built without `configureAsHUD` has any translucency to
  reduce. For a HUD-configured window, `setTransparency(_:)` sets translucency
  unconditionally from the caller-supplied value with no observation of
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency`; whether the HUD
  should re-clamp toward opaque under Reduce Transparency is the open
  question, since the setting does apply to a HUD window and the source
  simply has no code path for it. Settling it needs a decision on whether a
  HUD window observes that setting and forces an opaque background.

## Feature Flags

Not applicable — the class reads no feature-flag system; all behavior is
governed by subclass overrides and directly-called configuration methods.

## Analytics

Not applicable — `SingleWindowController` emits no analytics events of its
own. Window interaction tracking for recents is delegated entirely to
`WindowManager.windowDidInteract(_:kind:)`, which itself calls only
`NSDocumentController.shared.noteNewRecentDocumentURL` for document windows
(a system API, not an analytics call) and is a documented no-op for
non-document windows.

## Privacy

The frame (position and size) and visibility of each window are persisted to
disk by `WindowFrameManager`, keyed by `windowID`, whenever the corresponding
`windowSpec.persistsFrame`/`persistsVisibility` flags are enabled (the
`WindowSpec.Behavior.default` set enables both). `SingleWindowController`
itself does not choose the storage location or retention policy — it is the
trigger point (via `windowDidMove`, `windowDidResize`, `windowWillClose`,
`showWindow(_:)`, `dismiss()`) that calls into `WindowFrameManager`'s
persistence, which retains the last-known frame and visibility indefinitely
until a caller outside this class clears it. No content, document data, or
personally identifying information is captured by this class; only window
geometry and shown/hidden state are stored.

## Logging

Not applicable — `SingleWindowController.swift` contains no logging calls of
its own.

## Platform Notes

- **SwiftUI (`WindowGroup`/`Window` scenes)**: SwiftUI's native window scenes
  handle lazy creation and frame restoration declaratively; a SwiftUI
  equivalent would express `windowID` as a scene identifier and rely on
  `@SceneStorage`/`defaultPosition`/`defaultSize` modifiers rather than an
  imperative `NSWindowController` subclass.
- **Jetpack Compose (Desktop)**: `Window`/`DialogWindow` composables with
  `rememberWindowState` provide the closest analog to persisted frame state;
  content-hugging resize would be expressed by observing content size in a
  `SubcomposeLayout` and calling `WindowState.size = ...`.
- **React / Web**: Not applicable in the same sense — a browser tab/window is
  not directly resizable or positionable by page script in the general case;
  an Electron/Tauri shell would map this recipe onto `BrowserWindow`
  geometry-persistence APIs instead.
- **AppKit (source platform)**: This recipe is extracted directly from the
  AppKit implementation; see Behavioral Requirements above for the concrete
  API surface (`NSWindowController`, `NSWindowDelegate`, `NSPanel`). The
  content-refit machinery's private implementation names —
  `isApplyingContentFit` (reentrancy guard), `wantsRefitAfterMove` (computed
  gate), `moveRefitSettleTask` / `scheduleContentRefitAfterMove()` (the
  debounce timer), and the reused `FrameAnchors` (anchor-hold state) — are
  internal to this class; only their observable effects are asserted above.
- **WinUI 3 / Windows App SDK**: This recipe exists specifically to give the
  Windows port a `SingleWindowController`-equivalent base. A `Microsoft
  .UI.Xaml.Window` subclass would map `defaultSize`/`minSize` to
  `AppWindow.Resize`/`AppWindow.MinSize` (or `OverlappedPresenter`
  constraints), frame persistence to `ApplicationData.LocalSettings` keyed by
  `windowID`, HUD-style translucency to a `SystemBackdrop`
  (`MicaBackdrop`/`DesktopAcrylicBackdrop`) rather than raw alpha, and the
  toolbar-button mask to `AppWindowTitleBar` button-visibility properties.

## Design Decisions

**Decision**: Treat the class's own header doc comment (`super.init(windowID:)`,
`makeContentViewController()`, `makeContentView()`) as stale documentation
rather than as behavior to reproduce, since none of those symbols exist in
the implementation, which instead requires the two-argument
`init(windowID:contentViewController:)` with no content-factory override
point.
**Rationale**: source-fidelity requires describing what the code actually
does; reproducing a doc comment's invented API surface would document
behavior that cannot be exercised.
**Approved**: pending

**Decision**: Apply the toolbar button mask and HUD chrome, then run
`configureWindow(_:)`, then restore the persisted frame, and only then
assign `self` as the window's delegate.
**Rationale**: chrome installed by `configureWindow(_:)` (e.g. a toolbar)
changes how much of the window is title bar, so the frame has to be
restored onto the window only after that chrome has finished shaping it;
restoring the frame before the delegate is attached keeps the delegate from
observing the restore itself as a user-driven move/resize, which would
otherwise re-save the just-restored frame redundantly.
**Approved**: pending

**Decision**: Guard `fitWindow(toContentSize:)` with an `isApplyingContentFit`
reentrancy flag and a last-applied-fit cache (size + anchors), bailing out
when a new request repeats the last one.
**Rationale**: applying a computed frame triggers `windowDidResize`, which
could otherwise re-enter the content-refit path; the cache additionally
avoids redundant frame-setting work when content size hasn't actually
changed.
**Approved**: pending

**Decision**: Defer a scheduled move-refit indefinitely while
`NSEvent.pressedMouseButtons` reports a held button, rather than capping the
number of reschedules.
**Rationale**: refitting mid-drag would fight the user's in-progress window
placement; deferring until the drag ends (however long that takes) is
preferable to firing a refit against a frame the user hasn't finished
choosing.
**Approved**: pending

**Decision**: When `forcesWindowFront` is `false`, sink the shown window
behind the desktop and order it back (`sinkBehindDesktop()` + `orderBack(nil)`)
rather than suppressing activation alone, with `forcesWindowFront` as the
per-class opt-in that instead orders the window fully to front via
`orderFrontRegardless()`.
**Rationale**: automated tests and quiet Debug launches must not throw an
opaque, fully-drawn window over whatever the developer is doing, but the
suite still asserts `isVisible`, the restored frame, and `window.screen` —
all of which a genuinely ordered-out window would fail. Sinking behind the
desktop keeps the window real and on-screen to AppKit while invisible to the
person at the keyboard; `NSApplication.activateUnlessQuiet()` is used
separately, by `SingletonWindowController.present()`, to avoid stealing
app-wide focus.
**Approved**: pending

**Decision**: Document `SingleWindowController` as a single ingredient
covering all five of its concerns — window lifecycle/build sequencing,
frame/visibility persistence triggering, content-hugging refit with
move-debounce, HUD chrome, and the `SingletonWindowController` protocol
extension — rather than splitting each into its own ingredient recipe, even
though this gives it a larger requirement count than a typical sibling
ingredient.
**Rationale**: the five concerns are combined in one class in the source as
built, so describing them as one ingredient is source-fidelity, not a
stylistic choice; the larger count is deliberate coupling debt inherited
from the source, not a justification for scope creep in future ingredients
modeled on this one. A future split into separate ingredients — HUD chrome,
content-fit refit, and the singleton protocol extension, each referencing
this one — would need `SingleWindowController.swift` itself decomposed
first; until then this recipe carries the debt rather than hiding it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|---|---|---|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

Statuses rest on direct inspection of `SingleWindowController.swift`: native
`NSWindow`/`NSPanel` construction with no custom-drawn chrome
(native-controls-preference), an explicit accessibility identifier derived
from `windowID` (screen-reader-support), and no-op repeats of
`fitWindow`/`showWindow`/`ensureCurrent` when nothing has changed
(idempotent-operations).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `SingleWindowController` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reframed the requirement-count design decision as deliberate coupling debt rather than scope justification; merged the loadWindow build-order requirements into one build-sequence requirement and corrected registry-registration timing to init(); renamed init-argument-storage to describe storage only; renamed all requirements to subject-only kebab-case; reworded windowSpec citations as "a registered WindowSpec"; corrected the forces-front/quiet-presentation, HUD transparency/floating/transparency-property wording; moved private refit-machinery names out of requirements and test vectors into Platform Notes; replaced test vectors 001 and 037 with behavioral vectors, added a setFloating(false) vector, and merged the forces-front vectors; corrected the fitWindow zero/negative-size edge case against the real guard clause; moved the platform-design-languages reference into related and added sibling recipe links; removed the macos tag; reformatted Compliance to Check/Status/Category and Design Decisions to bold labels; ran compliance_fix.py to drop uncataloged Compliance checks; rejected the default-placement, double-persist, and compliance-coverage findings against current source. |
