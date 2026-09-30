<!-- leaf: implement-general-view-1/dismissible-overlay-view--part-2 · source: dismissible-overlay-view.md -->

# DismissibleOverlayView — continued (part 2)

**Rules** (cite as `implement-general-view-1/dismissible-overlay-view--part-2#<slug>`):

- `winui-3` MUST — Build the backdrop as a full-bleed Border behind the content, with Background="{ThemeResource …

## Privacy

- **Data collected**: None. The instance retains only the caller-supplied
  `material` and `onDismissed` closure; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no network I/O appears anywhere in
  this file.
- **Retention**: None beyond the view's own lifetime; state is discarded
  once `dismiss()` removes it from its superview and the caller releases
  its reference.

## Platform Notes

- **SwiftUI**: Layer a `ZStack` with a blur behind the content — the
  nearest built-in analog to `.hudWindow` is a `Material` value such as
  `.ultraThinMaterial`/`.thickMaterial` applied via `.background(...)`, since
  SwiftUI has no direct `NSVisualEffectView.Material` equivalent. Drive the
  fade with `withAnimation(.easeInOut(duration: 0.2))` around an `opacity`
  toggle rather than a separate present/dismiss animation API. Dismiss on an
  unclaimed tap via `.onTapGesture` on the backdrop layer only (placed
  beneath, not around, the content, so a content control's own gesture
  claims the touch first). SwiftUI has no direct equivalent of
  `performKeyEquivalent`'s free "offer to subviews first" behavior;
  reproduce `key-equivalent-subview-priority` with `.onExitCommand`
  (Escape) plus a hidden default-action `Button` (Return) attached at the
  overlay's own level, and make sure any focused child control that wants
  Return/Escape for itself (e.g. a multiline text editor) is given priority
  via SwiftUI's own responder/focus precedence rather than relying on
  automatic bubbling.
- **Compose**: Use a `Box` whose bottom layer is the host content and whose
  top layer is the overlay; real backdrop blur (as opposed to blurring the
  overlay's own drawing) needs `Modifier.graphicsLayer` with a
  `RenderEffect` on API 31+, or a blur library on older API levels — there
  is no single built-in analog to `NSVisualEffectView.Material`. Fade with
  `AnimatedVisibility(enter = fadeIn(tween(200)), exit = fadeOut(tween(200)))`
  to match `fadeDuration`. Dismiss on an unclaimed tap via a
  `pointerInput { detectTapGestures { dismiss() } }` modifier on the
  backdrop `Box` placed beneath any content `Box`es, so content added on top
  intercepts first (mirroring `mouse-down-dismissal`). There is
  no Escape/Return key-equivalent on a touch-first platform; map the
  system Back gesture/button via `BackHandler { dismiss() }` instead.
- **React/Web**: Use an absolutely positioned, full-container `<div>` with
  `backdrop-filter: blur(...)` as the closest CSS analog to
  `NSVisualEffectView`, and a CSS `opacity` transition over `200ms` toggled
  by a mounted/unmounted class (mirroring the `NSAnimationContext` fade).
  Attach the dismiss `onClick` handler to that backdrop `<div>` itself, not
  to an ancestor wrapping the content, so a content control's own `onClick`
  with `stopPropagation()` claims the click first (mirroring
  `mouse-down-dismissal`). Attach a `keydown` listener for
  `Escape`/`Enter` at the overlay's own container and have any content
  control that wants those keys for itself call `stopPropagation()`, so the
  overlay's own listener — running last via normal DOM bubbling — only fires
  when nothing else claimed the key (mirroring
  `key-equivalent-subview-priority`).
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/CoreUI/DismissibleOverlayView.swift` as an
  `open`, `@MainActor`, `NSView` subclass; the only import is `AppKit`, and
  every API it uses (`NSVisualEffectView`, `NSAnimationContext`, `NSEvent`,
  `performKeyEquivalent`) is macOS-only, so there is no UIKit code path in
  source. A UIKit port would replace `NSVisualEffectView` with
  `UIVisualEffectView`/`UIBlurEffect` (the closest style to `.hudWindow` is
  one of the dark, high-opacity system materials), replace `mouseDown` with
  a `UITapGestureRecognizer` on the backdrop with `cancelsTouchesInView =
  false` so a content subview's own gesture recognizer can still claim the
  touch first, and replace `performKeyEquivalent` with `UIKeyCommand`
  registrations for Escape and Return (hardware-keyboard only) — with no
  equivalent affordance for a touch-only device, a UIKit port would need an
  explicit on-screen dismiss control (e.g. a close button) that this macOS
  source has no need for.
- **WinUI 3**: Build the backdrop as a
  full-bleed `Border` behind the content, with `Background="{ThemeResource
  AcrylicInAppFillColorDefaultBrush}"` (an `AcrylicBrush`) as the platform's
  real backdrop-blur primitive — the nearest analog to `.hudWindow`, unlike
  a plain semi-opaque `SolidColorBrush`. Animate presentation and dismissal
  with a `Storyboard` driving a `DoubleAnimation` on `Opacity` from 0→1
  (present) and 1→0 (dismiss) over `Duration="0:0:0.2"`, matching
  `fadeDuration`; on the dismiss storyboard's `Completed` event, remove the
  element from its parent panel's `Children`, mirroring
  `post-fade-removal`. Attach a `Tapped` handler to the
  backdrop `Border` itself, not to a `Grid` that also hosts the content, so
  a content `Button`'s own `Click`/`Tapped` event (which WinUI marks handled
  by default) never reaches it, mirroring
  `mouse-down-dismissal`. Register `KeyboardAccelerator`s for
  `VirtualKey.Escape` and `VirtualKey.Enter` on the overlay's root element,
  which is meant to mirror `performKeyEquivalent`'s "offer to subviews
  first" behavior, but `KeyboardAccelerator` precedence relative to a
  focused control varies by control and is not guaranteed the way
  `performKeyEquivalent`'s subview-first traversal is — a `TextBox` a reader
  is typing into does not automatically consume the accelerator, so a porter
  MUST explicitly mark the key handled (e.g. set `Handled = true` on the
  `TextBox`'s own `KeyDown`) for any content control that wants Return or
  Escape for itself, mirroring `key-equivalent-subview-priority`. Guard the
  accelerator's `Invoked` handler with an `isDismissing`-style boolean field,
  since `KeyboardAccelerator.Invoked` has no built-in idempotency the way
  `dismiss()`'s own guard provides.

## Design Decisions

**Decision**: `onDismissed` is invoked synchronously inside `dismiss()`,
immediately after `willDismiss()` and before the fade-out animation
finishes, rather than from the animation's completion handler.
**Rationale**: Per the property's own doc comment, this lets "the owner drop
its reference without waiting out the fade" — an owner that releases its
only strong reference to the overlay the moment `onDismissed` fires does
not have to keep it alive for the 0.2s fade, since the fade-out's
completion closure only touches `self` via a weak reference.
**Approved**: pending

**Decision**: `dismiss()` sets `isDismissing = true` synchronously, before
calling `willDismiss()`, invoking `onDismissed`, or starting the fade-out
animation.
**Rationale**: Per the property's doc comment, "a reader can press Escape and
click in the same breath" — both `mouseDown` and `performKeyEquivalent`
route through the same `dismiss()`, and flipping the flag before anything
else runs is what makes the second of two near-simultaneous dismissal
gestures a guaranteed no-op rather than a race dependent on animation
timing.
**Approved**: pending

**Decision**: Dismissal on Escape/Return is implemented via
`performKeyEquivalent`, not `keyDown`, and the overlay never makes itself
first responder.
**Rationale**: Per the method's doc comment, AppKit offers every key-down to
this subtree via `performKeyEquivalent` before the responder chain sees it,
so Escape/Return dismiss without the overlay taking first-responder
status — which would otherwise cost the overlay's own content (e.g. a
scrollable transcript) the arrow keys and page keys it needs to stay
readable while presented.
**Approved**: pending

**Decision**: `mouseDown(with:)` unconditionally calls `dismiss()`, with no
check of what was clicked, relying entirely on the AppKit responder chain
to keep the call from firing when a control did claim the click.
**Rationale**: Per the method's doc comment, this "works by not being
reached": a scroller, button, or selectable text a reader is interacting
with handles its own `mouseDown` and stops the event there, so this
override only ever runs for a press nothing else wanted — hit-testing
subviews manually would duplicate logic the responder chain already
provides.
**Approved**: pending

**Decision**: The backdrop's `blendingMode` is fixed to `.withinWindow` and is
not exposed as an `init` parameter the way `material` is.
**Rationale**: Per the inline comment in `init`, what is being blurred is "the
view directly behind this one, not the desktop — this is a layer over a
window, not a window over a screen"; every overlay built on this class
shares that same relationship to its host, so there is no legitimate
caller-supplied alternative to expose.
**Approved**: pending

**Decision**: `main-actor-isolation` is verified at compile time by the
Swift concurrency checker, not by an XCTest runtime assertion — a
non-main-actor call site fails to compile rather than throwing or asserting
at runtime.
**Rationale**: `@MainActor` isolation is a type-system property; there is no
way to construct or call a member of `DismissibleOverlayView` from
off-actor code that still compiles, so `dismissible-overlay-001` is
executed as a compile-fail check (e.g. a test target file that must not
build) rather than a normal test-runner assertion.
**Approved**: pending
