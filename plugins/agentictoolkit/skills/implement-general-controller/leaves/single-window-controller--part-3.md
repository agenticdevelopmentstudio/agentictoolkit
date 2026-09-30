<!-- leaf: implement-general-controller/single-window-controller--part-3 · source: single-window-controller.md -->

# SingleWindowController — continued (part 3)

**Rules** (cite as `implement-general-controller/single-window-controller--part-3#<slug>`):

- `refit-drag-deferral` MUST
- `move-triggers-refit` MUST
- `frame-persist-on-move` MUST
- `frame-persist-on-resize` MUST
- `resize-refit-guard` MUST
- `visibility-persist-on-close` MUST
- `visibility-restore` MUST
- `hud-configuration` MUST
- `hud-chrome-opt-in` MUST
- `hud-transparency-floor` MUST
- `set-floating` MUST
- `set-transparency` MUST
- `singleton-protocol-conformance` MUST
- `singleton-ensure-current` MUST
- `singleton-present` MUST
- `singleton-is-open` MUST

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
  unconditionally from the caller-supplied value; the class does not observe
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency`, so a HUD
  window's `alphaValue` is never re-clamped toward opaque when the system
  setting is enabled.

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

