---
id: 3f6268b8-410d-4d3c-979c-2a9f9f1534f3
title: SingleWindowController
domain: agentictoolkit://recipes/single-window-controller
type: ingredient
version: 1.0.0
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
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
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
constructor argument. This recipe describes the implementation as it actually
behaves; the doc-comment/API mismatch is recorded as a source quirk in Design
Decisions rather than reproduced as behavior.

## Behavioral Requirements

- **main-actor-isolation**: The type and every one of its members MUST be
  confined to the main actor (`@MainActor` on the class declaration).
- **requires-non-empty-window-id-and-content-view-controller-at-init**: `init(windowID:contentViewController:)`
  MUST store the given `windowID` and content view controller for use when the
  window is later built, without validating that `windowID` is non-empty at
  construction time (validation happens later, at registry registration).
- **rejects-coder-initialization**: The class MUST NOT support `NSCoder`-based
  initialization; `init?(coder:)` MUST be unavailable (marked
  `@available(*, unavailable)`, fatal if reached).
- **exposes-overridable-default-size**: The class MUST expose a `class`
  (type-level) `defaultSize` of `NSSize(width: 600, height: 480)` that
  subclasses may override to change the fallback window size used when no
  persisted frame exists.
- **exposes-overridable-forces-window-front**: The class MUST expose an
  overridable `class var forcesWindowFront: Bool` (default `false`) that
  subclasses set to `true` to request that `showWindow(_:)` bring the window
  fully to the front and make the app active even when quiet presentation
  would otherwise suppress activation.
- **exposes-overridable-window-title**: `windowTitle` MUST be an overridable
  computed property (default empty string `""`) that subclasses override to
  supply the window's title.
- **exposes-overridable-default-content-rect**: `defaultContentRect` MUST be
  an overridable computed property that returns an `NSRect` whose origin is
  `.zero` and whose size is `Self.defaultSize`, used only when no persisted
  frame is available.
- **exposes-overridable-window-style-mask**: `windowStyleMask` MUST be an
  overridable computed property (default `[.titled, .closable, .miniaturizable,
  .resizable]`) that subclasses override to change the window's chrome, e.g.
  to add `.utilityWindow` or `.hudWindow` for HUD panels.
- **exposes-overridable-min-size**: `minSize` MUST be an overridable computed
  property (default `NSSize(width: 200, height: 150)`) that subclasses
  override to change the window's minimum content size.
- **exposes-configure-window-hook**: `configureWindow(_:)` MUST be an
  overridable, no-op-by-default hook called once, after the window is built
  and before it is returned from `loadWindow()`, so subclasses can perform
  one-time additional window setup (toolbar items, appearance, etc.).
- **builds-window-lazily-on-first-access**: The controller MUST NOT build its
  `NSWindow` in `init`; it MUST build it the first time `loadWindow()` is
  invoked (i.e., the first time AppKit or a caller accesses `window`).
- **selects-panel-class-for-utility-or-hud-style-mask**: `loadWindow()` MUST
  construct an `NSPanel` when `windowStyleMask` contains `.utilityWindow` or
  `.hudWindow`, and a plain `NSWindow` otherwise.
- **constructs-window-from-default-content-rect-and-style-mask**: `loadWindow()`
  MUST construct the window with `defaultContentRect` as its content rect,
  `windowStyleMask` as its style mask, `.buffered` backing, and
  `deferCreation: false`.
- **sets-window-title-on-build**: `loadWindow()` MUST set the built window's
  `title` to `windowTitle`.
- **sets-content-view-controller-on-build**: `loadWindow()` MUST set the built
  window's `contentViewController` to the controller supplied at `init`.
- **applies-min-size-on-build**: `loadWindow()` MUST set the built window's
  `minSize` to `minSize`.
- **sets-accessibility-identifier-from-window-id**: `loadWindow()` MUST assign
  the window an accessibility identifier derived by slugifying `windowID`
  through `AccessibilityID.slug(_:)`, so windows are addressable in UI tests.
  Slugification splits camelCase boundaries, lowercases, and joins
  non-alphanumeric runs with hyphens.
- **applies-toolbar-button-mask-from-window-spec**: `loadWindow()` MUST, when
  a persisted `windowSpec` exists for `windowID`, mask the window's
  `standardWindowButton` visibility for close/miniaturize/zoom according to
  `windowSpec.toolbarButtons`, hiding any button whose corresponding
  `ToolbarButtons` option is absent from the mask.
- **skips-toolbar-button-mask-without-window-spec**: `loadWindow()` MUST leave
  all three standard window buttons at their AppKit default visibility when no
  persisted `windowSpec` exists for `windowID` (no spec has been registered
  for this window yet).
- **restores-persisted-frame-before-delegate-assignment**: `loadWindow()` MUST
  ask `WindowFrameManager` to restore any persisted frame for `windowID` and
  apply it to the built window before assigning `self` as the window's
  delegate, so the restore does not itself trigger `windowDidMove`/
  `windowDidResize` bookkeeping through the delegate.
- **assigns-self-as-window-delegate-after-restore**: `loadWindow()` MUST set
  the built window's `delegate` to `self` only after frame restoration, and
  before `configureWindow(_:)` runs, so all delegate callbacks from that point
  forward (including any triggered by `configureWindow(_:)`) are observed.
- **invokes-configure-window-hook-once-per-build**: `loadWindow()` MUST call
  `configureWindow(_:)` with the newly built window exactly once, after the
  window is fully assembled (title, content, min size, accessibility
  identifier, toolbar mask, frame restore, delegate) and before assigning it
  to `self.window`.
- **assigns-built-window-to-window-property**: `loadWindow()` MUST set
  `self.window` to the constructed, fully configured window as its final
  step.
- **registers-with-window-registry-on-build**: `loadWindow()` MUST register
  `self` with `WindowManager.shared.registry` under `windowID` once the window
  is built.
- **skips-registry-registration-for-empty-window-id**: Registration with
  `WindowRegistry` MUST be a silent no-op when `windowID` is empty (the
  registry's own `register(_:)` guards on a non-empty ID); `loadWindow()`
  MUST NOT crash or otherwise special-case an empty `windowID` beyond that.
  This is verified in `WindowRegistry`; `SingleWindowController` supplies no
  additional guard because none is needed.
- **overrides-show-window-with-forces-front-branch**: `showWindow(_:)` MUST
  be overridden so that when `Self.forcesWindowFront` is `true`, it calls
  `NSApp.activate(ignoringOtherApps: true)` and brings the window fully to
  the front before calling through to `super.showWindow(_:)`.
- **defers-to-quiet-activation-when-not-forcing-front**: `showWindow(_:)`
  MUST, when `Self.forcesWindowFront` is `false`, activate the app through
  `NSApplication.activateUnlessQuiet()` rather than unconditionally calling
  `activate(ignoringOtherApps:)`, so activation is suppressed under
  `QuietWindowPresentation` (XCTest runs, or a Debug build launched with
  `-QuietWindowPresentation YES`).
- **provides-parameterless-show-window-convenience**: The class MUST expose a
  parameterless `showWindow()` convenience that forwards to
  `showWindow(_:)` with a `nil` sender, for call sites that have no natural
  sender.
- **persists-visibility-on-show-when-opted-in**: `showWindow(_:)` MUST record
  the window as visible through `WindowFrameManager.saveVisibility` when the
  window's `windowSpec.persistsVisibility` is `true`.
- **provides-dismiss-method**: The class MUST expose a `dismiss()` method that
  closes the window (via `window?.close()` or equivalent) rather than
  requiring callers to reach through to the underlying `NSWindow`.
- **persists-visibility-on-dismiss-when-opted-in**: `dismiss()` MUST record the
  window as hidden through `WindowFrameManager.saveVisibility` when the
  window's `windowSpec.persistsVisibility` is `true`, mirroring the
  `showWindow(_:)` behavior on the closing path.
- **exposes-is-visible**: The class MUST expose a computed `isVisible: Bool`
  that reflects the underlying window's `isVisible`, returning `false` when no
  window has been built yet.
- **fits-window-to-content-size**: `fitWindow(toContentSize:)` MUST resize the
  window's content area to the given size using `FrameCalculator
  .contentHuggingFrame(currentFrame:desiredFrameSize:screenVisibleFrame:
  minSize:anchors:)`, which keeps one edge of the window anchored (by default
  top-left) while the opposite edges move to accommodate the new content
  size.
- **bails-out-when-fit-size-and-anchors-are-unchanged**: `fitWindow(toContentSize:)`
  MUST compare the requested size and anchor state against the last applied
  `ContentFit` and skip re-applying the frame when both are unchanged, to
  avoid redundant frame-setting work and redundant `windowDidResize`
  notifications on repeated calls with identical inputs.
- **holds-anchors-across-repeated-fit-calls**: `fitWindow(toContentSize:)` MUST
  reuse the previously computed `FrameAnchors` for subsequent fits after the
  first, rather than recomputing an anchor point from the window's current
  frame on every call, so the anchor edge stays stable across a sequence of
  content-size changes.
- **guards-against-reentrant-fit-application**: `fitWindow(toContentSize:)`
  MUST set an `isApplyingContentFit` guard flag while it applies the computed
  frame to the window, so a `windowDidResize` delegate callback triggered by
  that very frame change does not re-enter the content-refit machinery.
- **exposes-content-size-provider-hook**: The class MUST expose a settable
  `contentSizeProvider: (() -> NSSize)?` closure property that, when set,
  supplies the desired content size for `performContentRefit()` to apply via
  `fitWindow(toContentSize:)`.
- **performs-content-refit-only-with-provider-set**: `performContentRefit()`
  MUST be a no-op when `contentSizeProvider` is `nil`, and otherwise MUST call
  the provider and pass its result to `fitWindow(toContentSize:)`.
- **schedules-refit-after-window-move-with-settle-delay**: `scheduleContentRefitAfterMove()`
  MUST debounce refitting after a window move by waiting
  `moveRefitSettleDelay` (200 milliseconds) via `Task.sleep` before calling
  `refitContentAfterMove()`, canceling and replacing any previously scheduled
  `moveRefitSettleTask` so only the most recent move's timer fires.
- **defers-refit-while-mouse-button-is-held**: `refitContentAfterMove()` MUST
  check `NSEvent.pressedMouseButtons` and, if a mouse button is currently
  held (the user is still dragging the window), reschedule itself rather than
  performing the refit immediately, so a refit does not fight an in-progress
  drag.
- **marks-refit-wanted-after-move-when-provider-present**: `windowDidMove(_:)`
  MUST set `wantsRefitAfterMove = true` and call
  `scheduleContentRefitAfterMove()` only when `contentSizeProvider` is
  non-nil; with no provider set, a move MUST NOT schedule any refit work.
- **saves-frame-on-move-when-opted-in**: `windowDidMove(_:)` MUST persist the
  window's new frame through `WindowFrameManager.saveFrame` when
  `windowSpec.persistsFrame` is `true`.
- **saves-frame-on-resize-when-opted-in**: `windowDidResize(_:)` MUST persist
  the window's new frame through `WindowFrameManager.saveFrame` when
  `windowSpec.persistsFrame` is `true`, mirroring the move-triggered save.
- **skips-resize-driven-refit-while-applying-own-fit**: `windowDidResize(_:)`
  MUST check `isApplyingContentFit` and skip triggering
  `performContentRefit()` when the resize was caused by the controller's own
  `fitWindow(toContentSize:)` call, so the refit path does not recursively
  re-trigger itself.
- **persists-hidden-visibility-on-window-will-close**: `windowWillClose(_:)`
  MUST record the window as hidden through `WindowFrameManager.saveVisibility`
  when `windowSpec.persistsVisibility` is `true`, so closing the window via
  its own close button (not just via `dismiss()`) is captured.
- **restores-visibility-on-request-when-opted-in**: `restoreVisibilityIfNeeded()`
  MUST call `showWindow()` when `windowSpec.persistsVisibility` is `true` and
  the persisted visibility state (`WindowFrameManager.loadVisibility`) is
  `true`; otherwise it MUST leave the window unshown.
- **exposes-hud-configuration-struct**: The class MUST define a nested
  `HUDConfiguration` struct capturing whether the window floats and its
  transparency level, used by `configureAsHUD(floating:transparency:)`.
- **configures-hud-chrome-only-when-requested**: `configureAsHUD(floating:transparency:)`
  MUST be the only entry point that applies HUD-specific chrome (background
  translucency and, when floating, a floating window level); a window that
  never calls it MUST render with ordinary opaque, non-floating chrome.
- **clamps-hud-transparency-to-a-visible-range**: `configureAsHUD(floating:transparency:)`
  MUST clamp the given transparency value into a range that keeps the window
  visibly present rather than invisible-but-clickable (the source comment
  documents a floor above fully transparent), rather than accepting an
  arbitrary caller-supplied alpha unclamped.
- **applies-floating-level-through-set-floating**: `setFloating(_:)` MUST set
  the window's level to a floating level (e.g. `.floating`) when `true`, and
  restore the normal window level when `false`.
- **applies-transparency-through-set-transparency**: `setTransparency(_:)`
  MUST set the window's background/alpha to reflect the given transparency
  value, independent of the floating level set by `setFloating(_:)`.
- **conforms-window-controller-to-singleton-protocol-when-adopted**: A
  subclass that adopts `SingletonWindowController` MUST get `ensureCurrent()`,
  `present()`, and `isOpen()` from the protocol extension without additional
  implementation, provided it supplies `static var current`  and
  `static func makeShared()`.
- **ensures-current-creates-shared-instance-lazily**: `ensureCurrent()` MUST
  create the shared instance via `makeShared()` and assign it to `current`
  only when `current` is `nil`, and MUST leave an existing `current` instance
  untouched otherwise (i.e., only one shared instance is created per process,
  reused across calls).
- **present-shows-the-singleton-instance**: `present()` MUST call
  `ensureCurrent()` and then call `showWindow()` on the resulting instance.
- **is-open-reflects-singleton-visibility**: `isOpen()` MUST return `false`
  when `current` is `nil`, and otherwise MUST return the current instance's
  `isVisible`.

## Appearance

| Element | Value | Source |
|---|---|---|
| Default window size | 600 × 480 pt | `Self.defaultSize` |
| Default minimum size | 200 × 150 pt | `minSize` |
| Default style mask | titled, closable, miniaturizable, resizable | `windowStyleMask` default |
| HUD style mask | adds `.utilityWindow` / `.hudWindow` | subclass override, detected by `loadWindow()`'s panel-class check |
| HUD transparency | subclass-supplied value, clamped to a visible floor | `configureAsHUD(floating:transparency:)` |
| Background color | Not applicable — the base class sets no explicit background color; a HUD window's translucency is the only appearance concern this class owns, and it is described above. Any theme-token background belongs to the hosted content view controller, not to this class. | `SingleWindowController.swift`; contrast with content-view-level theme observers such as `ThemePaletteObserver` |

## States

| State | Behavior | Source |
|---|---|---|
| Not yet built (`window` never accessed) | No `NSWindow` exists; `isVisible` returns `false`; registry has no entry for `windowID` | `loadWindow()` is lazy; `isVisible` |
| Built, hidden | Window exists, registered, but not on screen | default post-`loadWindow()` state before `showWindow` |
| Built, visible | Window on screen; frame/visibility persisted on further move/resize/close when opted in | `showWindow(_:)`, delegate methods |
| Built, HUD-configured | Translucent, optionally floating, chrome applied once via `configureAsHUD` | `configureAsHUD(floating:transparency:)` |
| Applying a content fit | `isApplyingContentFit` true; concurrent `windowDidResize`-driven refit suppressed | `fitWindow(toContentSize:)`, `windowDidResize(_:)` |
| Awaiting move-settle | `moveRefitSettleTask` pending; refit deferred while mouse button held | `scheduleContentRefitAfterMove()`, `refitContentAfterMove()` |
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
| single-window-controller-001 | main-actor-isolation | any instance | any member is accessed | access occurs on the main actor; a compiler diagnostic results from off-main-actor access |
| single-window-controller-002 | requires-non-empty-window-id-and-content-view-controller-at-init | a `windowID` and content view controller | `init(windowID:contentViewController:)` is called | both are stored for later use in `loadWindow()` |
| single-window-controller-003 | rejects-coder-initialization | any | `init?(coder:)` is invoked | a fatal/unavailable-API error occurs, not a working instance |
| single-window-controller-004 | exposes-overridable-default-size | a subclass overriding `defaultSize` | no persisted frame exists | `loadWindow()` uses the overridden size |
| single-window-controller-005 | exposes-overridable-forces-window-front | a subclass with `forcesWindowFront == true` | `showWindow(_:)` is called | the app activates and the window comes fully to the front regardless of quiet-presentation |
| single-window-controller-006 | exposes-overridable-window-title | a subclass overriding `windowTitle` | `loadWindow()` runs | the built window's `title` equals the overridden value |
| single-window-controller-007 | exposes-overridable-default-content-rect | a subclass overriding `defaultContentRect`, no persisted frame | `loadWindow()` runs | the window is created with the overridden rect |
| single-window-controller-008 | exposes-overridable-window-style-mask | a subclass overriding `windowStyleMask` to include `.hudWindow` | `loadWindow()` runs | an `NSPanel` is constructed instead of `NSWindow` |
| single-window-controller-009 | exposes-overridable-min-size | a subclass overriding `minSize` | `loadWindow()` runs | the built window's `minSize` equals the overridden value |
| single-window-controller-010 | exposes-configure-window-hook | a subclass overriding `configureWindow(_:)` | `loadWindow()` runs | the override is invoked exactly once with the fully assembled window |
| single-window-controller-011 | builds-window-lazily-on-first-access | a freshly initialized controller | `init` completes but `window` is not accessed | no `NSWindow` has been constructed |
| single-window-controller-012 | selects-panel-class-for-utility-or-hud-style-mask | `windowStyleMask` contains `.utilityWindow` | `loadWindow()` runs | the constructed object is an `NSPanel` |
| single-window-controller-013 | constructs-window-from-default-content-rect-and-style-mask | default configuration | `loadWindow()` runs | the window's content rect, style mask, backing, and defer flag match the documented values |
| single-window-controller-014 | sets-window-title-on-build | `windowTitle` overridden to `"Example"` | `loadWindow()` runs | `window.title == "Example"` |
| single-window-controller-015 | sets-content-view-controller-on-build | a content view controller supplied at init | `loadWindow()` runs | `window.contentViewController` is that instance |
| single-window-controller-016 | applies-min-size-on-build | `minSize` overridden | `loadWindow()` runs | `window.minSize` equals the overridden value |
| single-window-controller-017 | sets-accessibility-identifier-from-window-id | `windowID == "mySettings"` | `loadWindow()` runs | the window's accessibility identifier equals `AccessibilityID.slug("mySettings")` |
| single-window-controller-018 | applies-toolbar-button-mask-from-window-spec | a persisted `windowSpec` with `toolbarButtons == [.close]` | `loadWindow()` runs | only the close button is visible; miniaturize and zoom are hidden |
| single-window-controller-019 | skips-toolbar-button-mask-without-window-spec | no persisted `windowSpec` for `windowID` | `loadWindow()` runs | all three standard buttons keep AppKit's default visibility |
| single-window-controller-020 | restores-persisted-frame-before-delegate-assignment | a persisted frame for `windowID` | `loadWindow()` runs | the frame is applied before `delegate` is set, so no `windowDidMove`/`windowDidResize` bookkeeping fires from the restore |
| single-window-controller-021 | assigns-self-as-window-delegate-after-restore | any | `loadWindow()` runs | `window.delegate === self` after frame restoration and before `configureWindow(_:)` |
| single-window-controller-022 | invokes-configure-window-hook-once-per-build | any | `loadWindow()` runs | `configureWindow(_:)` is called exactly once per build |
| single-window-controller-023 | assigns-built-window-to-window-property | any | `loadWindow()` completes | `self.window` is the constructed, fully configured window |
| single-window-controller-024 | registers-with-window-registry-on-build | a non-empty `windowID` | `loadWindow()` runs | `WindowManager.shared.registry.controller(forID: windowID) === self` |
| single-window-controller-025 | skips-registry-registration-for-empty-window-id | `windowID == ""` | `loadWindow()` runs | the registry has no entry for the empty ID; no crash occurs |
| single-window-controller-026 | overrides-show-window-with-forces-front-branch | `forcesWindowFront == true` | `showWindow(_:)` is called | `NSApp.activate(ignoringOtherApps: true)` is invoked and the window is ordered fully to front |
| single-window-controller-027 | defers-to-quiet-activation-when-not-forcing-front | `forcesWindowFront == false`, running under XCTest | `showWindow(_:)` is called | `activateUnlessQuiet()` suppresses activation; the window still shows |
| single-window-controller-028 | provides-parameterless-show-window-convenience | any | `showWindow()` is called | it behaves identically to `showWindow(nil)` |
| single-window-controller-029 | persists-visibility-on-show-when-opted-in | `windowSpec.persistsVisibility == true` | `showWindow(_:)` is called | `WindowFrameManager.saveVisibility` records the window visible |
| single-window-controller-030 | provides-dismiss-method | a visible window | `dismiss()` is called | the window closes |
| single-window-controller-031 | persists-visibility-on-dismiss-when-opted-in | `windowSpec.persistsVisibility == true` | `dismiss()` is called | `WindowFrameManager.saveVisibility` records the window hidden |
| single-window-controller-032 | exposes-is-visible | no window built yet | `isVisible` is read | it returns `false` |
| single-window-controller-033 | fits-window-to-content-size | a built window | `fitWindow(toContentSize:)` is called with a new size | the window's frame changes to accommodate the content size, anchored per `FrameAnchors` |
| single-window-controller-034 | bails-out-when-fit-size-and-anchors-are-unchanged | a prior fit already applied for a given size/anchor pair | `fitWindow(toContentSize:)` is called again with the same size | the frame is not re-applied |
| single-window-controller-035 | holds-anchors-across-repeated-fit-calls | two consecutive fits with different sizes | the second `fitWindow` call runs | the anchor used is the one computed on the first call, not recomputed from the current frame |
| single-window-controller-036 | guards-against-reentrant-fit-application | `fitWindow(toContentSize:)` in progress | the resulting frame change triggers `windowDidResize` | the refit machinery does not re-enter itself |
| single-window-controller-037 | exposes-content-size-provider-hook | a closure assigned to `contentSizeProvider` | the property is read back | the same closure is returned |
| single-window-controller-038 | performs-content-refit-only-with-provider-set | `contentSizeProvider == nil` | `performContentRefit()` is called | no frame change occurs |
| single-window-controller-039 | schedules-refit-after-window-move-with-settle-delay | a provider set, then two moves in quick succession | `scheduleContentRefitAfterMove()` is called twice | only one refit occurs, 200ms after the second move |
| single-window-controller-040 | defers-refit-while-mouse-button-is-held | a scheduled refit fires while `NSEvent.pressedMouseButtons != 0` | `refitContentAfterMove()` runs | the refit reschedules itself instead of applying immediately |
| single-window-controller-041 | marks-refit-wanted-after-move-when-provider-present | `contentSizeProvider` set | `windowDidMove(_:)` fires | `wantsRefitAfterMove` becomes `true` and a refit is scheduled |
| single-window-controller-042 | saves-frame-on-move-when-opted-in | `windowSpec.persistsFrame == true` | `windowDidMove(_:)` fires | `WindowFrameManager.saveFrame` is called with the new frame |
| single-window-controller-043 | saves-frame-on-resize-when-opted-in | `windowSpec.persistsFrame == true` | `windowDidResize(_:)` fires | `WindowFrameManager.saveFrame` is called with the new frame |
| single-window-controller-044 | skips-resize-driven-refit-while-applying-own-fit | `isApplyingContentFit == true` | `windowDidResize(_:)` fires | `performContentRefit()` is not triggered |
| single-window-controller-045 | persists-hidden-visibility-on-window-will-close | `windowSpec.persistsVisibility == true` | the user clicks the window's close button | `WindowFrameManager.saveVisibility` records the window hidden |
| single-window-controller-046 | restores-visibility-on-request-when-opted-in | `windowSpec.persistsVisibility == true` and persisted visibility is `true` | `restoreVisibilityIfNeeded()` is called | `showWindow()` is invoked |
| single-window-controller-047 | exposes-hud-configuration-struct | any | `HUDConfiguration` is constructed | it captures floating and transparency values |
| single-window-controller-048 | configures-hud-chrome-only-when-requested | `configureAsHUD` never called | the window is inspected | chrome is ordinary opaque, non-floating |
| single-window-controller-049 | clamps-hud-transparency-to-a-visible-range | a caller-supplied transparency below the documented floor | `configureAsHUD(floating:transparency:)` is called | the applied transparency is clamped to the floor, not the raw value |
| single-window-controller-050 | applies-floating-level-through-set-floating | any | `setFloating(true)` is called | the window's level becomes a floating level |
| single-window-controller-051 | applies-transparency-through-set-transparency | any | `setTransparency(_:)` is called | the window's background alpha reflects the given value |
| single-window-controller-052 | conforms-window-controller-to-singleton-protocol-when-adopted | a subclass adopting `SingletonWindowController` supplying `current`/`makeShared()` | the protocol extension methods are called | `ensureCurrent()`, `present()`, `isOpen()` all work without further overrides |
| single-window-controller-053 | ensures-current-creates-shared-instance-lazily | `current == nil` | `ensureCurrent()` is called twice | `makeShared()` runs once; the second call reuses the first instance |
| single-window-controller-054 | present-shows-the-singleton-instance | `current == nil` | `present()` is called | a shared instance is created and shown |
| single-window-controller-055 | is-open-reflects-singleton-visibility | `current == nil` | `isOpen()` is called | it returns `false` |

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
  `FrameCalculator.contentHuggingFrame` operates on whatever `NSSize` it is
  given; the class applies no additional lower-bound guard beyond the
  window's own `minSize`, so a degenerate size is subject to the same
  `minSize` clamping AppKit already enforces on the resulting frame.
- **Concurrent access from multiple threads**: Not applicable — the whole
  class is `@MainActor`-isolated, so the compiler prevents concurrent access
  from another thread; there is no runtime race to defend against.
- **Error/failure states**: Not applicable — none of this class's APIs are
  throwing or failable; `NSWindow` construction itself cannot fail with the
  parameters used here, so there is no error path to define.
- **Offline/disconnected state**: Not applicable — this class has no network
  dependency.
- **Unbounded settle-wait while the mouse button is held**: `refitContentAfterMove()`
  reschedules itself indefinitely as long as `NSEvent.pressedMouseButtons`
  reports a held button, with no maximum retry count; a pathologically long
  drag defers the refit for the duration of the drag rather than firing
  early with a stale frame. This is a deliberate tradeoff (see Design
  Decisions), not an unhandled failure.
- **`configureWindow(_:)` mutates the delegate or frame**: Because the hook
  runs after delegate assignment and frame restoration, any delegate-firing
  change `configureWindow(_:)` makes (e.g. resizing the window) is observed
  by `windowDidResize(_:)` like any other resize, including its
  `windowSpec.persistsFrame` save path.

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
| `forcesWindowFront` (class override) | `Bool` | Whether `showWindow` forces activation/front regardless of quiet presentation | class var |
| `configureAsHUD(floating:transparency:)` | `(Bool, CGFloat)` | Opts the window into translucent/floating HUD chrome | method call |

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
- **Reduce Transparency**: Not applicable to the base (non-HUD) configuration,
  since no window built without `configureAsHUD` has any translucency to
  reduce. For a HUD-configured window, `setTransparency(_:)` sets translucency
  unconditionally from the caller-supplied value with no observation of
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency`; whether the HUD
  should re-clamp toward opaque under Reduce Transparency is the open
  question, since the setting does apply to a HUD window and the source
  simply has no code path for it.

  NEEDS REVIEW: Not implemented in source. Behavior undefined.

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
  API surface (`NSWindowController`, `NSWindowDelegate`, `NSPanel`).
- **WinUI 3 / Windows App SDK**: This recipe exists specifically to give the
  Windows port a `SingleWindowController`-equivalent base. A `Microsoft
  .UI.Xaml.Window` subclass would map `defaultSize`/`minSize` to
  `AppWindow.Resize`/`AppWindow.MinSize` (or `OverlappedPresenter`
  constraints), frame persistence to `ApplicationData.LocalSettings` keyed by
  `windowID`, HUD-style translucency to a `SystemBackdrop`
  (`MicaBackdrop`/`DesktopAcrylicBackdrop`) rather than raw alpha, and the
  toolbar-button mask to `AppWindowTitleBar` button-visibility properties.

## Design Decisions

Decision: Treat the class's own header doc comment (`super.init(windowID:)`,
`makeContentViewController()`, `makeContentView()`) as stale documentation
rather than as behavior to reproduce, since none of those symbols exist in
the implementation, which instead requires the two-argument
`init(windowID:contentViewController:)` with no content-factory override
point.
Rationale: source-fidelity requires describing what the code actually does;
reproducing a doc comment's invented API surface would document behavior
that cannot be exercised.
Approved: pending

Decision: Restore the persisted frame and assign `self` as the window's
delegate only afterward, then run `configureWindow(_:)` last.
Rationale: this ordering keeps the delegate from observing the restore itself
as a user-driven move/resize (which would otherwise re-save the just-restored
frame redundantly), while still letting `configureWindow(_:)` trigger normal
delegate bookkeeping for any changes a subclass makes.
Approved: pending

Decision: Guard `fitWindow(toContentSize:)` with an `isApplyingContentFit`
reentrancy flag and a last-applied-fit cache (size + anchors), bailing out
when a new request repeats the last one.
Rationale: applying a computed frame triggers `windowDidResize`, which could
otherwise re-enter the content-refit path; the cache additionally avoids
redundant frame-setting work when content size hasn't actually changed.
Approved: pending

Decision: Defer a scheduled move-refit indefinitely while
`NSEvent.pressedMouseButtons` reports a held button, rather than capping the
number of reschedules.
Rationale: refitting mid-drag would fight the user's in-progress window
placement; deferring until the drag ends (however long that takes) is
preferable to firing a refit against a frame the user hasn't finished
choosing.
Approved: pending

Decision: Route activation through `NSApplication.activateUnlessQuiet()` by
default, with `forcesWindowFront` as an explicit per-subclass opt-out.
Rationale: automated tests and quiet Debug launches must not steal focus from
whatever the developer is doing, while a subclass that genuinely needs
guaranteed front presentation (e.g. an alert-like window) can still request
it explicitly.
Approved: pending

Decision: Give this recipe a substantially larger requirement count than
sibling `ingredient` recipes such as `panel-view`.
Rationale: `SingleWindowController` genuinely combines five separable
concerns in one class — window lifecycle/build sequencing, frame/visibility
persistence triggering, content-hugging refit with move-debounce, HUD chrome,
and the `SingletonWindowController` protocol extension — each of which
carries its own observable, testable behavior; splitting the count would
misrepresent the component's actual scope.
Approved: pending

## Compliance

| Check | Status | Notes |
|---|---|---|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | The entire class is `@MainActor`-isolated; no member can be reached off the main actor. |
| [local-persistence-durability](agenticdevelopercookbook://compliance/data#local-persistence-durability) | passed | Frame and visibility are durably persisted via `WindowFrameManager` on every move/resize/show/dismiss/close, gated by `windowSpec` opt-in flags. |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | The class sets no raw hex colors; its only appearance concern (HUD transparency) is a translucency level, not a literal color value. |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Built entirely from `NSWindow`/`NSPanel`/`NSWindowController`, with no custom-drawn chrome replacing standard AppKit window elements. |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | No state in this class is conveyed by color alone; toolbar-button visibility and HUD chrome are structural, not color-coded, distinctions. |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | The window receives an explicit accessibility identifier derived from `windowID`; VoiceOver navigation of the window's contents is the hosted content view controller's responsibility, which this class does not obstruct. |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | partial | The base class introduces no string literal of its own, but `windowTitle`'s default AppKit `String` property offers no built-in localization path, leaving it fully on the subclass to localize. |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Repeated `fitWindow` calls with unchanged size/anchors are a no-op; repeated `showWindow`/`ensureCurrent` calls reuse the existing window/instance rather than rebuilding it. |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `SingleWindowController` (AppKit, macOS) source. |
