---
id: 0bc93127-4078-4bc6-a250-04dde181788b
title: Dismissible Overlay View
domain: agentictoolkit://cookbook/ui/containers/dismissible-overlay-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Covers its host with a blurred, fading backdrop and dismisses itself on
  an unclaimed click, Escape, or Return.
platforms:
- swift
- macos
tags:
- ui
- overlay
- dismissible
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/motion
approved-by: ''
approved-date: ''
---

# Dismissible Overlay View

## Overview

A view that lays a blurred backdrop over another view and blends itself in
and out. Per the concept's own rationale, it exists because two overlays in
the toolkit share the same "manners" though not the same content — "one
conversation lifted out of a merged feed, and one message opened to its full
length" — and those manners (cover the host entirely, fade rather than
appear, and go away on Escape, on Return, or on a press no control took) live
here so a fix to any of them lands in every overlay built on it. A subclass
adds its own content as ordinary subviews above the backdrop and overrides
the pre-dismissal hook for whatever it has running that needs to stop.

## Behavioral Requirements

- **blurred-backdrop**: Component MUST add a blurred backdrop view, pinned
  to its own top, leading, trailing, and bottom anchors, using a
  within-window blending behavior and kept in its active (not inactive)
  appearance state.
- **backdrop-subview-order**: The backdrop MUST be added as this view's
  subview during construction, before any subclass's own initialization can
  add subviews of its own, so the backdrop is always the first (bottommost)
  subview.
- **backdrop-material-default**: Component MUST use its platform's default
  backdrop material when no `material` argument is supplied at
  construction.
- **backdrop-material-override**: Component MUST use the caller-supplied
  `material` value for the backdrop when one is passed at construction.
- **host-coverage**: Presenting the overlay in a host MUST add it as a
  subview of that host and constrain its top, leading, trailing, and
  bottom anchors equal to the host's corresponding anchors.
- **present-layout-order**: Presenting the overlay MUST set its opacity to
  0, then force the host and the overlay to lay out and draw
  synchronously, before starting the fade-in animation.
- **present-fade**: Presenting the overlay MUST animate its opacity from 0
  to 1 over `fadeDuration` (0.2 seconds).
- **dismiss-fade**: Dismissing the overlay MUST animate its opacity to 0
  over `fadeDuration` (0.2 seconds).
- **post-fade-removal**: Dismissing the overlay MUST remove it from its
  superview once the fade-out animation's completion handler runs.
- **dismiss-idempotency**: Dismissing the overlay MUST have no further
  effect on any call after the first — an observable consequence of
  `dismissing-flag-timing`, since dismissal returns immediately whenever
  `isDismissing` is already `true`.
- **dismissing-flag-timing**: Dismissing the overlay MUST set
  `isDismissing` to `true` synchronously, before running the pre-dismissal
  hook, invoking `onDismissed`, or starting the fade-out animation.
- **will-dismiss-timing**: Dismissing the overlay MUST run the
  pre-dismissal hook before starting the fade-out animation.
- **dismissed-callback-timing**: Dismissing the overlay MUST invoke
  `onDismissed`, when set, synchronously, immediately after the
  pre-dismissal hook and before the fade-out animation's completion
  handler runs.
- **default-will-dismiss**: The pre-dismissal hook MUST do nothing in the
  base implementation.
- **mouse-down-dismissal**: Component MUST dismiss itself whenever an
  unclaimed press reaches it directly (i.e. no subview claimed it first).
- **key-equivalent-subview-priority**: Component's key-equivalent handling
  MUST report the event as handled without dismissing itself when a
  subview already handled the event first.
- **escape-return-dismissal**: Component's key-equivalent handling MUST
  dismiss itself and report the event as handled when the event is Escape,
  Return, or keypad Enter, `isDismissing` is `false`, and no subview
  handled the event first.
- **non-dismiss-key-equivalents**: Component's key-equivalent handling MUST
  report an event that is not Escape, Return, or keypad Enter as
  unhandled, when no subview handled the event first.
- **key-equivalents-during-dismissal**: Component's key-equivalent handling
  MUST report a dismiss-key event as unhandled when `isDismissing` is
  already `true`.
- **open-subclassing**: The component's presentation, its pre-dismissal
  hook, and its press- and key-equivalent-handling entry points MUST all be
  overridable by a subclass, so a subclass can override presentation, add
  its own content above the backdrop, and extend dismissal handling.
- **will-dismiss-cleanup**: Subclasses SHOULD override the pre-dismissal
  hook to stop any timers, polling, or other ongoing work they own, since
  it runs once, before the fade-out begins, and the base implementation
  stops nothing on a subclass's behalf. A subclass with nothing running
  MAY leave the default no-op override in place; this is a recommendation
  for subclass authors, not a behavior this component can itself verify
  (see Design Decisions).
- **optional-dismissed-callback**: Callers MAY leave `onDismissed` as
  `nil`, in which case dismissal performs no additional callback work
  beyond the fade-out animation and removal from superview.

## Appearance

- **Corner radius**: None — the source sets no corner radius on either
  itself or the backdrop.
- **Padding**: None — presenting the overlay constrains all four of its
  edges equal (not inset) to the corresponding host edges.
- **Font**: Not applicable — this base view renders no text of its own; any
  text belongs to whatever content a subclass adds above the backdrop.
- **Background**: A blurred backdrop view with a caller-selectable
  material (default: the platform's hud-style material), a within-window
  blending behavior, and an active (not inactive) appearance state.
- **Foreground/Text**: Not applicable — no label or text-rendering view
  exists in the source.
- **Border**: None — no border is configured on the view or the backdrop.
- **Shadow**: None — no shadow-related layer property is set anywhere in
  source.
- **Min/Max size**: None declared. The overlay has no intrinsic size of its
  own; presenting it pins all four edges to exactly fill the host.

## States

| State | Appearance change |
|-------|------------------|
| Default (idle, fully presented) | Opacity `== 1`; backdrop fully applies its material; `isDismissing == false` |
| Presenting (during presentation) | Opacity animates from 0 to 1 over `fadeDuration` (0.2s) |
| Dismissing (from the first dismissal call) | `isDismissing == true`; opacity animates from its current value to 0 over `fadeDuration` (0.2s); the view remains in the hierarchy, still swallowing an unclaimed click or dismiss key, until the fade completes |
| Removed (after fade-out completes) | The view has been removed from its superview and no longer draws or receives events |
| Pressed | Not applicable: the source defines no separate pressed-state styling; a press either reaches the overlay directly (triggering dismissal, not a visual change) or is claimed by a subview's own control. |
| Disabled | Not applicable: the source exposes no enabled/disabled property or disabled-state styling. |
| Focused | Not applicable: per the concept's own rationale (see `key-equivalent-subview-priority`), the overlay deliberately never becomes first responder — its key-equivalent handling catches Escape/Return without requiring key/focus status, so it defines no focused appearance. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: Not explicitly set — the source sets no accessibility
  role override anywhere; the platform's own default view role applies
  unmodified.
- **Label requirements**: Not implemented in source. Nothing in this
  component sets an accessibility label or description on itself or the
  backdrop, so a screen reader user gets no announced description that
  this is a dismissible overlay or of how to dismiss it (click anywhere
  unclaimed, Escape, or Return); any such label would have to come from a
  subclass or caller, and none of the toolkit's current subclasses supplies
  one.
- **Announce state changes**: Not implemented in source. Neither
  presenting nor dismissing the overlay posts an explicit accessibility
  notification when it appears or disappears, so no notification is posted
  at either transition — only whatever the platform's own default
  view-hierarchy handling provides applies.
- **keyboard-focus-containment**: NEEDS REVIEW: Not implemented in source. Key-equivalent handling only intercepts Escape, Return, and keypad Enter; nothing restricts Tab-key focus traversal to the overlay's own content while presented, so a keyboard user could Tab onto a host control underneath the backdrop, and whether that is acceptable can only be settled by a keyboard-only pass tabbing through a presented overlay with the running UI.
- **Minimum tap target**: Not applicable in the small-target sense — per
  `mouse-down-dismissal` and `host-coverage`,
  the dismiss gesture's target is the overlay's entire frame, which itself
  covers the host entirely; there is no small tap target to size.
- **Minimum contrast ratio**: Not applicable to this base view — it renders
  no text or foreground content of its own (see Appearance). Contrast is
  the responsibility of whatever content a subclass adds above the
  backdrop, which is out of scope for this recipe.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-overlay-004 | blurred-backdrop | Inspect the backdrop after construction | A blurred backdrop subview exists, using a within-window blending behavior and kept in its active appearance state |
| dismissible-overlay-005 | backdrop-subview-order | Construct a subclass that adds one content subview after calling the base initializer | The first (bottommost) subview is the backdrop; the content subview appears after it |
| dismissible-overlay-006 | backdrop-material-default | Constructed with no `material` argument | The backdrop uses the platform's default material |
| dismissible-overlay-007 | backdrop-material-override | Constructed with a caller-supplied `material` value | The backdrop uses that caller-supplied material value |
| dismissible-overlay-008 | host-coverage | Present the overlay in a host view | Overlay is a subview of the host, with top/leading/trailing/bottom anchors each constrained equal to the matching host anchor |
| dismissible-overlay-009 | present-layout-order | Present the overlay in a host, then synchronously (before the next run-loop turn) inspect the host's subview layout and the overlay's frame | The host's subtree is already laid out and the overlay's frame already reflects its final host-pinned size at the moment presentation returns, before any animation frame renders |
| dismissible-overlay-010 | present-fade | Present the overlay in a host, inspecting the fade animation's duration from an injected/overridden animation hook | The fade animation's duration `== fadeDuration` (0.2s) while it runs; opacity reaches `1` once the animation completes |
| dismissible-overlay-011 | dismiss-fade | Dismiss a fully presented overlay, inspecting the fade animation's duration from the same injected/overridden animation hook | The fade animation's duration `== fadeDuration` (0.2s) while it runs; opacity reaches `0` once the completion handler runs |
| dismissible-overlay-012 | post-fade-removal | Dismiss the overlay and wait for the fade-out animation to complete | The overlay's superview becomes absent once the completion handler runs |
| dismissible-overlay-013 | dismiss-idempotency | Dismiss the overlay twice in immediate succession | The pre-dismissal hook and `onDismissed` are each invoked exactly once; exactly one fade-out animation runs |
| dismissible-overlay-014 | dismissing-flag-timing | Dismiss the overlay; read `isDismissing` synchronously, before the animation completes | `isDismissing == true` immediately |
| dismissible-overlay-015 | will-dismiss-timing | Override the pre-dismissal hook to record a timestamp, then dismiss the overlay | The recorded timestamp precedes any change to opacity |
| dismissible-overlay-016 | dismissed-callback-timing | Set `onDismissed` to record a timestamp, then dismiss the overlay | The recorded timestamp precedes the fade-out animation's completion handler |
| dismissible-overlay-017 | default-will-dismiss | Dismiss a plain (non-subclassed) instance | No observable side effect beyond the fade-out and removal; no crash |
| dismissible-overlay-018 | mouse-down-dismissal | Deliver an unclaimed press directly to the overlay | The overlay dismisses itself |
| dismissible-overlay-019 | key-equivalent-subview-priority | Add a subview whose own key-equivalent handling reports Return as handled, then send a Return key event | The event is reported as handled; the overlay does NOT dismiss itself |
| dismissible-overlay-020 | escape-return-dismissal | Send an Escape key event, unclaimed by any subview | The event is reported as handled; the overlay dismisses itself |
| dismissible-overlay-020b | escape-return-dismissal | Same as above, with a Return key event | Same as above |
| dismissible-overlay-020c | escape-return-dismissal | Same as above, with a keypad Enter key event | Same as above |
| dismissible-overlay-021 | non-dismiss-key-equivalents | Send a Space key event, unclaimed by any subview | The event is reported as unhandled; the overlay does NOT dismiss itself |
| dismissible-overlay-022 | key-equivalents-during-dismissal | Dismiss the overlay, then immediately send an Escape key event before the fade-out completes | The event is reported as unhandled; the overlay is not dismissed a second time |
| dismissible-overlay-023 | open-subclassing | Define a subclass overriding presentation, the pre-dismissal hook, and the press- and key-equivalent-handling entry points | Code compiles; the subclass's overrides run in place of the base implementation |
| dismissible-overlay-024 | optional-dismissed-callback | Leave `onDismissed` as `nil`, then dismiss the overlay | No crash; the fade-out animation and removal from superview still proceed |
| dismissible-overlay-025 | key-equivalent-subview-priority | Present one overlay in a host, then present a second instance as a subview added above the first (mirroring "a message expanded over a conversation"); send an Escape key event | The outer (first-presented) overlay's key-equivalent handling reports the event as handled via reaching the inner overlay first; only the inner (topmost) overlay dismisses itself, not the outer one |

`will-dismiss-cleanup` has no test vector: it is guidance for
what a subclass author puts inside their own override, not a behavior
the component itself performs or can verify at the component
level (see Design Decisions).

## Edge Cases

- **Null/empty input** (SHOULD/MUST): `onDismissed` defaults to `nil`, and
  dismissing an instance with `onDismissed == nil` proceeds identically
  minus the callback (MUST, per `optional-dismissed-callback`). `material`
  is a required, typed parameter with a default value, so
  there is no null/empty case for it to guard.
- **Boundary values** (MUST): the set of dismiss keys is a fixed
  three-value set (Escape, Return, keypad Enter); a key event either is or
  is not a member — there is no partial match, range, or near-miss
  behavior (per `escape-return-dismissal` / `non-dismiss-key-equivalents`).
  `fadeDuration` is a single fixed 0.2s value with no configurable minimum
  or maximum.
- **Presenting the overlay on a momentarily zero-sized host**: because
  layout and drawing are forced before the fade starts (per
  `present-layout-order`), a host that is still zero-sized at the moment of
  presenting produces a zero-sized first frame; once the host is later
  given a real size, the overlay's own edge-pinned constraints (per
  `host-coverage`) resize it to match — nothing in source detects or
  defers the zero-sized first frame itself.
- **Dismissing an instance never presented**: removing a view with no
  superview is a harmless no-op; the pre-dismissal hook and `onDismissed`
  still fire (per `will-dismiss-timing` and `dismissed-callback-timing`) —
  dismissal has no guard requiring the view to have been presented first.
- **Concurrent access**: Not applicable — this component is confined to a
  single thread of execution for its entire lifetime, so there is no path
  for two threads to call present/dismiss on the same instance
  simultaneously. See Platform Notes for how that
  confinement is enforced, including how the one non-isolated closure in
  source (the fade-out completion handler) re-establishes that confinement
  before touching itself.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no network call, database access, or file I/O; every
  operation (mutating opacity, adding/removing subviews, invoking
  closures) is synchronous, in-process, and non-throwing.
- **Offline/disconnected state**: Not applicable — no networking exists
  anywhere in this file.
- **Escape and an unclaimed click arriving in the same runloop turn**
  (MUST): because `isDismissing` flips to `true` synchronously on the first
  call to dismiss (per `dismissing-flag-timing`), whichever gesture is
  processed second sees `isDismissing == true` and is a guaranteed no-op —
  this is not a race that depends on animation timing.
- **A second overlay presented on top of the first** (MUST, per the
  concept's own rationale of "a message expanded over a conversation"):
  because key-equivalent handling offers the event to subviews first (per
  `key-equivalent-subview-priority`), the topmost overlay — being the
  nearer subview in the responder chain — is the one Escape dismisses, not
  the one underneath it; see `dismissible-overlay-025` for the two-overlay
  vector this rests on.

## Configuration

Construction options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `material` | `Material` | platform's hud-style default | Backdrop blur material, set once at construction and never reassigned afterward |
| `onDismissed` | `(() -> Void)?` | `nil` | Invoked synchronously once dismissal begins, before the fade-out animation completes |
| `isDismissing` | `Bool` | `false` | Readable by any caller, but settable only internally by the dismiss operation; `true` from the first dismissal call onward |

Beyond construction, the component exposes: a fixed fade duration
(`fadeDuration`, 0.2 seconds) and a fixed three-value set of dismiss keys
(`dismissKeyCodes`) shared by every instance and subclass; an operation to
present the overlay in a host view; an operation to dismiss it; and an
overridable pre-dismissal hook.

`fadeDuration` and `dismissKeyCodes` are fixed constants, not per-instance
options — they cannot be overridden by a subclass, so every instance and
subclass shares exactly the same 0.2 second fade and the same three dismiss
keys (Escape, Return, keypad Enter).

## Deep Linking

Not applicable: this is an internal, presentation-only view with no URL
scheme, route, or deep-link handler anywhere in the source; a caller
constructs it and presents it directly.

## Localization

Not applicable: the component renders no text and defines no string literal
of its own — no button titles, labels, or copy appear anywhere in the
source. Any strings belong to whatever content a subclass adds above the
backdrop, which is out of scope for this recipe.

## Accessibility Options

- **Reduce Motion**: Supported: presenting and dismissing the overlay
  animate only opacity (a 0.2s fade), duration `fadeDuration`; nothing
  moves, scales, or slides. A cross-fade is the substitute [the Motion
  guidance for reduced
  motion](https://developer.apple.com/design/human-interface-guidelines/motion)
  recommends when Reduce Motion is on, so no separate Reduce Motion path is
  needed. A port keeps the fade opacity-only.
- **Increase Contrast**: Not applicable — this file chooses no color values
  of its own; the backdrop's appearance is entirely the platform's own
  system material rendering, not anything this view controls.
- **Differentiate Without Color**: Not applicable — the base view conveys no
  state (presented, dismissing) via color at all; presence or absence from
  the view hierarchy and the alpha fade are its only signals, neither of
  which is a color distinction.

## Feature Flags

Not applicable: the source contains no feature-flag or config-gating
lookup. The overlay always presents and dismisses unconditionally when its
operations are called.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call. `onDismissed` is a plain consumer-supplied callback with no tracking
of its own.

## Privacy

- **Data collected**: None. The instance retains only the caller-supplied
  `material` and `onDismissed` closure; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no network I/O appears anywhere in
  this file.
- **Retention**: None beyond the view's own lifetime; state is discarded
  once dismissal removes it from its superview and the caller releases its
  reference.

## Logging

Not applicable: the source contains no logging call.

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
  source. `@MainActor` isolation means the class MUST only be constructed
  or mutated from the main actor — a non-main-actor call site fails to
  compile rather than throwing or asserting at runtime; this is verified as
  a compile-fail check (e.g. a test target file that must not build), not
  an XCTest runtime assertion. The class fails with a fatal error if
  constructed via `init?(coder:)`, since it provides no Interface
  Builder/`NSCoding` support. At construction it sets
  `translatesAutoresizingMaskIntoConstraints = false` on both itself and
  its backdrop, and sets `wantsLayer = true` on itself. The backdrop is an
  `NSVisualEffectView` with `blendingMode == .withinWindow` and
  `state == .active`; its default `material` is `.hudWindow`, overridable
  via the `material` argument to `init`. Presenting and dismissing use
  `NSAnimationContext` to animate `alphaValue`; the dismiss-key set
  (`dismissKeyCodes`) is `Set<UInt16>` `[53, 36, 76]` (Escape, Return,
  keypad Enter, respectively). The public operations are
  `present(in host: NSView)` (`open`), `dismiss()`, and the overridable
  `willDismiss()` (`open`); the press- and key-equivalent-handling entry
  points are `mouseDown(with:)` and `performKeyEquivalent(with:)` (both
  `open`). Neither `present(in:)` nor `dismiss()` calls
  `NSAccessibility.post(element:notification:)`. A UIKit port would replace
  `NSVisualEffectView` with `UIVisualEffectView`/`UIBlurEffect` (the closest
  style to `.hudWindow` is one of the dark, high-opacity system materials),
  replace `mouseDown` with a `UITapGestureRecognizer` on the backdrop with
  `cancelsTouchesInView = false` so a content subview's own gesture
  recognizer can still claim the touch first, and replace
  `performKeyEquivalent` with `UIKeyCommand` registrations for Escape and
  Return (hardware-keyboard only) — with no equivalent affordance for a
  touch-only device, a UIKit port would need an explicit on-screen dismiss
  control (e.g. a close button) that this macOS source has no need for.

  Public API surface:
  ```swift
  public static let fadeDuration: TimeInterval = 0.2
  public static let dismissKeyCodes: Set<UInt16> = [53, 36, 76]

  public init(material: NSVisualEffectView.Material = .hudWindow)
  open func present(in host: NSView)
  public func dismiss()
  open func willDismiss()
  ```
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/CoreUI/DismissibleOverlayView.swift` |

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
first responder. (Applies to the AppKit/UIKit implementation.)
**Rationale**: Per the method's doc comment, AppKit offers every key-down to
this subtree via `performKeyEquivalent` before the responder chain sees it,
so Escape/Return dismiss without the overlay taking first-responder
status — which would otherwise cost the overlay's own content (e.g. a
scrollable transcript) the arrow keys and page keys it needs to stay
readable while presented.
**Approved**: pending

**Decision**: `mouseDown(with:)` unconditionally calls `dismiss()`, with no
check of what was clicked, relying entirely on the AppKit responder chain
to keep the call from firing when a control did claim the click. (Applies
to the AppKit/UIKit implementation.)
**Rationale**: Per the method's doc comment, this "works by not being
reached": a scroller, button, or selectable text a reader is interacting
with handles its own `mouseDown` and stops the event there, so this
override only ever runs for a press nothing else wanted — hit-testing
subviews manually would duplicate logic the responder chain already
provides.
**Approved**: pending

**Decision**: The backdrop's `blendingMode` is fixed to `.withinWindow` and is
not exposed as an `init` parameter the way `material` is. (Applies to the
AppKit/UIKit implementation.)
**Rationale**: Per the inline comment in `init`, what is being blurred is "the
view directly behind this one, not the desktop — this is a layer over a
window, not a window over a screen"; every overlay built on this class
shares that same relationship to its host, so there is no legitimate
caller-supplied alternative to expose.
**Approved**: pending

**Decision**: Main-actor isolation (see Platform Notes) is verified at compile time by the
Swift concurrency checker, not by an XCTest runtime assertion — a
non-main-actor call site fails to compile rather than throwing or asserting
at runtime. (Applies to the AppKit/UIKit implementation, which is written
in Swift.)
**Rationale**: `@MainActor` isolation is a type-system property; there is no
way to construct or call a member of `DismissibleOverlayView` from
off-actor code that still compiles, so the isolation check is executed as a
compile-fail check (e.g. a test target file that must not build) rather
than a normal test-runner assertion.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | partial | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | passed | Accessibility |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |

`keyboard-navigable` passes because Escape, Return, and keypad Enter all
dismiss the overlay without requiring it to become first responder (see
`escape-return-dismissal`). `focus-management` is `partial`: the overlay
manages dismissal focus-independently, but the open question on
`keyboard-focus-containment` is unresolved in source — nothing traps
Tab focus to the overlay's own content. `screen-reader-support` fails
because the source sets no accessibility label describing the overlay's
presence or dismissal affordance and posts no VoiceOver notification when
it appears or disappears (see "Label requirements" and "Announce state
changes" under Accessibility). `reduced-motion` passes
because the only animation is an opacity fade (see Accessibility Options).
`platform-theming` passes because the backdrop's appearance comes entirely
from a system `NSVisualEffectView.Material` value, not a raw color this
view chooses itself.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/containers/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case; reformatted Design Decisions to bold three-line form; moved the internal cross-reference from `references` to `related` and added the HIG Motion URL; corrected Compliance to real catalog checks and categories; added a two-overlay conformance vector and an `isDismissing` Configuration row; qualified the WinUI 3 accelerator-precedence claim; tightened animation-timing conformance vectors for XCTest executability; trimmed edge-case RFC tags and fixed the zero-sized-host accuracy issue. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DismissibleOverlayView` (AppKit, macOS) source. |
