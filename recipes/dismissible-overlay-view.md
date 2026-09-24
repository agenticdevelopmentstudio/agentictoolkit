---
id: 0bc93127-4078-4bc6-a250-04dde181788b
title: DismissibleOverlayView
domain: agentictoolkit://recipes/dismissible-overlay-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
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
- macos
- appkit
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/motion
approved-by: ''
approved-date: ''
---

# DismissibleOverlayView

## Overview

`DismissibleOverlayView`, at
`packages/apple/AgenticToolkit/CoreUI/DismissibleOverlayView.swift`, is an
`open`, `@MainActor`-isolated `NSView` subclass that lays a blurred backdrop
over another view and blends itself in and out. Per the type's own doc
comment, it exists because two overlays in the toolkit share the same
"manners" though not the same content — "one conversation lifted out of a
merged feed, and one message opened to its full length" — and those manners
(cover the host entirely, fade rather than appear, and go away on Escape, on
Return, or on a press no control took) live here so a fix to any of them
lands in every overlay built on it. A subclass adds its own content as
ordinary subviews above the backdrop and overrides `willDismiss()` for
whatever it has running that needs to stop.

## Behavioral Requirements

- **main-actor-isolation**: Component MUST only be constructed or
  mutated from the main actor; the class is declared `@MainActor`.
- **coder-init**: Component MUST fail with a fatal
  error if constructed via `init?(coder:)`, since it provides no Interface
  Builder/`NSCoding` support.
- **auto-layout-participation**: Component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on both itself and its
  backdrop, and MUST set `wantsLayer = true` on itself, at construction.
- **blurred-backdrop**: Component MUST add an `NSVisualEffectView`
  backdrop, pinned to its own top, leading, trailing, and bottom anchors,
  with `blendingMode == .withinWindow` and `state == .active`.
- **backdrop-subview-order**: The backdrop MUST be added as this view's
  subview during `DismissibleOverlayView`'s own `init`, before any
  subclass's designated initializer can add subviews of its own, so the
  backdrop is always the first (bottommost) subview.
- **backdrop-material-default**: Component MUST use
  `.hudWindow` as the backdrop's `material` when no `material` argument is
  supplied to `init`.
- **backdrop-material-override**: Component MUST use the
  caller-supplied `material` value for the backdrop's `material` when one is
  passed to `init`.
- **host-coverage**: `present(in:)` MUST add itself as a
  subview of `host` and constrain its top, leading, trailing, and bottom
  anchors equal to `host`'s corresponding anchors.
- **present-layout-order**: `present(in:)` MUST set `alphaValue`
  to 0, then call `host.layoutSubtreeIfNeeded()` and its own
  `displayIfNeeded()`, before starting the fade-in animation.
- **present-fade**: `present(in:)` MUST animate `alphaValue` from 0 to
  1 over `fadeDuration` (0.2 seconds).
- **dismiss-fade**: `dismiss()` MUST animate `alphaValue` to 0 over
  `fadeDuration` (0.2 seconds).
- **post-fade-removal**: `dismiss()` MUST remove the
  view from its superview once the fade-out animation's completion handler
  runs.
- **dismiss-idempotency**: `dismiss()` MUST have no further effect on any
  call after the first — an observable consequence of `dismissing-flag-timing`,
  since `dismiss()` returns immediately whenever `isDismissing` is already
  `true`.
- **dismissing-flag-timing**: `dismiss()` MUST set `isDismissing`
  to `true` synchronously, before calling `willDismiss()`, invoking
  `onDismissed`, or starting the fade-out animation.
- **will-dismiss-timing**: `dismiss()` MUST call
  `willDismiss()` before starting the fade-out animation.
- **dismissed-callback-timing**: `dismiss()` MUST
  invoke `onDismissed`, when set, synchronously, immediately after
  `willDismiss()` and before the fade-out animation's completion handler
  runs.
- **default-will-dismiss**: `willDismiss()` MUST do nothing in the
  base class implementation.
- **mouse-down-dismissal**: `mouseDown(with:)` MUST call
  `dismiss()` whenever the event reaches this view (i.e. no subview claimed
  it first).
- **key-equivalent-subview-priority**: `performKeyEquivalent(with:)`
  MUST return `true` without calling `dismiss()` when
  `super.performKeyEquivalent(with:)` (a subview) already handled the event.
- **escape-return-dismissal**: `performKeyEquivalent(with:)` MUST call
  `dismiss()` and return `true` when the event's `keyCode` is 53 (Escape), 36
  (Return), or 76 (keypad Enter), `isDismissing` is `false`, and no subview
  handled the event first.
- **non-dismiss-key-equivalents**: `performKeyEquivalent(with:)`
  MUST return `false` for a key event whose `keyCode` is not 53, 36, or 76,
  when no subview handled the event first.
- **key-equivalents-during-dismissal**: `performKeyEquivalent(with:)`
  MUST return `false` for a dismiss-key event when `isDismissing` is already
  `true`.
- **open-subclassing**: The class, `present(in:)`, `willDismiss()`,
  `mouseDown(with:)`, and `performKeyEquivalent(with:)` MUST be declared
  `open`, so a subclass can override presentation, add its own content above
  the backdrop, and extend dismissal handling.
- **will-dismiss-cleanup**: Subclasses SHOULD override
  `willDismiss()` to stop any timers, polling, or other ongoing work they
  own, since it is called once, before the fade-out begins, and the base
  class stops nothing on a subclass's behalf. A subclass with nothing
  running MAY leave the default no-op override in place; this is a
  recommendation for subclass authors, not a behavior this component can
  itself verify (see Design Decisions).
- **optional-dismissed-callback**: Callers MAY leave `onDismissed` as `nil`,
  in which case `dismiss()` performs no additional callback work beyond the
  fade-out animation and removal from superview.

## Appearance

- **Corner radius**: None — the source sets no `cornerRadius` on either
  itself or the backdrop.
- **Padding**: None — `present(in:)` constrains all four of the overlay's
  edges equal (not inset) to the corresponding host edges.
- **Font**: Not applicable — this base view renders no text of its own; any
  text belongs to whatever content a subclass adds above the backdrop.
- **Background**: An `NSVisualEffectView` backdrop with a caller-selectable
  `material` (default `.hudWindow`), `blendingMode == .withinWindow`, and
  `state == .active`.
- **Foreground/Text**: Not applicable — no label or text-rendering view
  exists in the source.
- **Border**: None — no border is configured on the view or the backdrop.
- **Shadow**: None — no shadow-related layer property is set anywhere in
  source.
- **Min/Max size**: None declared. The overlay has no intrinsic size of its
  own; `present(in:)`'s four edge-pinned constraints size it to exactly fill
  `host`.

## States

| State | Appearance change |
|-------|------------------|
| Default (idle, fully presented) | `alphaValue == 1`; backdrop fully applies its `material`; `isDismissing == false` |
| Presenting (during `present(in:)`) | `alphaValue` animates from 0 to 1 over `fadeDuration` (0.2s) |
| Dismissing (from the first `dismiss()` call) | `isDismissing == true`; `alphaValue` animates from its current value to 0 over `fadeDuration` (0.2s); the view remains in the hierarchy, still swallowing an unclaimed click or dismiss key, until the fade completes |
| Removed (after fade-out completes) | The view has been removed from its superview and no longer draws or receives events |
| Pressed | Not applicable: the source defines no separate pressed-state styling; a press either reaches `mouseDown` (triggering dismissal, not a visual change) or is claimed by a subview's own control. |
| Disabled | Not applicable: the source exposes no `isEnabled` property or disabled-state styling. |
| Focused | Not applicable: per the source doc comment on `performKeyEquivalent(with:)` (see `key-equivalent-subview-priority`), the overlay deliberately never becomes first responder — `performKeyEquivalent` catches Escape/Return without requiring key/focus status, so it defines no focused appearance. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: Not explicitly set — the source calls no
  `setAccessibilityRole`/`accessibilityRole` override anywhere; `NSView`'s
  own AppKit default applies unmodified.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. Nothing in `DismissibleOverlayView` sets an accessibility label
  or description on itself or the backdrop, so a VoiceOver user has no
  announced description that this is a dismissible overlay or of how to
  dismiss it (click anywhere unclaimed, Escape, or Return). What is missing:
  an accessibility label communicating the overlay's presence and dismissal
  affordance. What would settle it: a decision from the design/accessibility
  owner on the wording, since the base class owns no fixed content to
  describe but the dismissal gesture itself is common to every subclass and
  currently unaddressed by any of them.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. Neither `present(in:)` nor `dismiss()` calls
  `NSAccessibility.post(element:notification:)` when the overlay appears or
  disappears, so a VoiceOver user is not told a new layer just covered the
  screen, nor that it went away. What is missing: an accessibility
  notification posted at the start of `present(in:)` and once `dismiss()`
  removes the view. What would settle it: a VoiceOver pass presenting and
  dismissing an overlay, to confirm whether AppKit's default
  subview-added/removed handling already surfaces this or an explicit post
  is required.
- **Keyboard focus containment**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. `performKeyEquivalent` only intercepts Escape, Return,
  and keypad Enter; nothing in source restricts Tab-key focus traversal to
  the overlay's own content while it is presented, so a keyboard user could
  Tab focus onto a control in the host view underneath the (visually
  blocking, but not focus-blocking) backdrop. What is missing: whether Tab
  focus is meant to be trapped inside the overlay while presented. What
  would settle it: a keyboard-only pass tabbing through a presented overlay
  to confirm whether the host's underlying controls remain reachable, and
  whether that is acceptable given they are also visually hidden.
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
| dismissible-overlay-001 | main-actor-isolation | Attempt to call `init` or any public method from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| dismissible-overlay-002 | coder-init | `DismissibleOverlayView(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |
| dismissible-overlay-003 | auto-layout-participation | Inspect a freshly constructed instance and its backdrop | `translatesAutoresizingMaskIntoConstraints == false` on both self and the backdrop; `wantsLayer == true` on self |
| dismissible-overlay-004 | blurred-backdrop | Inspect the backdrop after construction | An `NSVisualEffectView` subview exists with `blendingMode == .withinWindow` and `state == .active` |
| dismissible-overlay-005 | backdrop-subview-order | Construct a subclass that adds one content subview after calling `super.init` | `subviews.first` is the backdrop; the content subview appears after it |
| dismissible-overlay-006 | backdrop-material-default | `DismissibleOverlayView()` (no `material` argument) | Backdrop's `material == .hudWindow` |
| dismissible-overlay-007 | backdrop-material-override | `DismissibleOverlayView(material: .sidebar)` | Backdrop's `material == .sidebar` |
| dismissible-overlay-008 | host-coverage | `present(in: host)` | Overlay is a subview of `host`, with top/leading/trailing/bottom anchors each constrained equal to the matching host anchor |
| dismissible-overlay-009 | present-layout-order | Call `present(in: host)`, then synchronously (before the next run-loop turn) inspect `host`'s subview layout and the overlay's `frame` | `host`'s subtree is already laid out and the overlay's `frame` already reflects its final host-pinned size at the moment `present(in:)` returns, before any animation frame renders |
| dismissible-overlay-010 | present-fade | Call `present(in: host)`, inspecting `NSAnimationContext.current.duration` from inside an injected/overridden animation hook (e.g. a test subclass that captures the context passed to `runAnimationGroup`) | `NSAnimationContext.current.duration == fadeDuration` (0.2s) while the group runs; `alphaValue` reaches `1` once the animation completes |
| dismissible-overlay-011 | dismiss-fade | Call `dismiss()` on a fully presented overlay, inspecting `NSAnimationContext.current.duration` from the same injected/overridden animation hook | `NSAnimationContext.current.duration == fadeDuration` (0.2s) while the group runs; `alphaValue` reaches `0` once the completion handler runs |
| dismissible-overlay-012 | post-fade-removal | Call `dismiss()` and wait for the fade-out animation to complete | The overlay's `superview` becomes `nil` once the completion handler runs |
| dismissible-overlay-013 | dismiss-idempotency | Call `dismiss()` twice in immediate succession | `willDismiss()` and `onDismissed` are each invoked exactly once; exactly one fade-out animation runs |
| dismissible-overlay-014 | dismissing-flag-timing | Call `dismiss()`; read `isDismissing` synchronously, before the animation completes | `isDismissing == true` immediately |
| dismissible-overlay-015 | will-dismiss-timing | Override `willDismiss()` to record a timestamp, then call `dismiss()` | The recorded timestamp precedes any change to `alphaValue` |
| dismissible-overlay-016 | dismissed-callback-timing | Set `onDismissed` to record a timestamp, then call `dismiss()` | The recorded timestamp precedes the fade-out animation's completion handler |
| dismissible-overlay-017 | default-will-dismiss | Call `dismiss()` on a plain (non-subclassed) instance | No observable side effect beyond the fade-out and removal; no crash |
| dismissible-overlay-018 | mouse-down-dismissal | Deliver a `mouseDown` event to the overlay itself, unclaimed by any subview | `dismiss()` is invoked |
| dismissible-overlay-019 | key-equivalent-subview-priority | Add a subview whose own `performKeyEquivalent` returns `true` for Return, then send a Return key event | `performKeyEquivalent` returns `true`; `dismiss()` is NOT invoked |
| dismissible-overlay-020 | escape-return-dismissal | Send a key event with `keyCode == 53` (Escape), unclaimed by any subview | `performKeyEquivalent` returns `true`; `dismiss()` is invoked |
| dismissible-overlay-020b | escape-return-dismissal | Same as above with `keyCode == 36` (Return) | Same as above |
| dismissible-overlay-020c | escape-return-dismissal | Same as above with `keyCode == 76` (keypad Enter) | Same as above |
| dismissible-overlay-021 | non-dismiss-key-equivalents | Send a key event with `keyCode == 49` (Space), unclaimed by any subview | `performKeyEquivalent` returns `false`; `dismiss()` is NOT invoked |
| dismissible-overlay-022 | key-equivalents-during-dismissal | Call `dismiss()`, then immediately send `keyCode == 53` before the fade-out completes | `performKeyEquivalent` returns `false`; `dismiss()` is not invoked a second time |
| dismissible-overlay-023 | open-subclassing | Define a subclass overriding `present(in:)`, `willDismiss()`, `mouseDown(with:)`, and `performKeyEquivalent(with:)` | Code compiles; the subclass's overrides run in place of the base implementation |
| dismissible-overlay-024 | optional-dismissed-callback | Leave `onDismissed` as `nil`, then call `dismiss()` | No crash; the fade-out animation and removal from superview still proceed |
| dismissible-overlay-025 | key-equivalent-subview-priority | Present one `DismissibleOverlayView` in `host`, then present a second instance as a subview added above the first (mirroring "a message expanded over a conversation"); send a key event with `keyCode == 53` (Escape) | `performKeyEquivalent` on the outer (first-presented) overlay returns `true` via its `super.performKeyEquivalent(with:)` call reaching the inner overlay first; only the inner (topmost) overlay's `dismiss()` is invoked, not the outer one's |

`will-dismiss-cleanup` has no test vector: it is guidance for
what a subclass author puts inside their own override, not a behavior
`DismissibleOverlayView` itself performs or can verify at the component
level (see Design Decisions).

## Edge Cases

- **Null/empty input** (SHOULD/MUST): `onDismissed` defaults to `nil`, and
  `dismiss()` on an instance with `onDismissed == nil` proceeds identically
  minus the callback (MUST, per `optional-dismissed-callback`). `material`
  is a required, typed parameter with a default value (`.hudWindow`), so
  there is no null/empty case for it to guard.
- **Boundary values** (MUST): `dismissKeyCodes` is a fixed three-value set
  (`{53, 36, 76}`); a `keyCode` either is or is not a member — there is no
  partial match, range, or near-miss behavior (per
  `escape-return-dismissal` / `non-dismiss-key-equivalents`).
  `fadeDuration` is a single fixed 0.2s value with no configurable minimum
  or maximum.
- **`present(in:)` called on a momentarily zero-sized host**: because layout
  and drawing are forced before the fade starts (per
  `present-layout-order`), a host that is still zero-sized at the moment of
  the call produces a zero-sized first frame; once `host` is later given a
  real size, the overlay's own edge-pinned constraints (per `host-coverage`)
  resize it to match — nothing in source detects or defers the zero-sized
  first frame itself.
- **`dismiss()` called on an instance never passed to `present(in:)`**:
  `removeFromSuperview()` on a view with no superview is a harmless AppKit
  no-op; `willDismiss()` and `onDismissed` still fire (per
  `will-dismiss-timing` and
  `dismissed-callback-timing`) — `dismiss()` has no
  guard requiring the view to have been presented first.
- **Concurrent access**: Not applicable — the class is `@MainActor`; the
  Swift compiler confines every stored-property read/write and UI mutation
  to the main actor, so there is no path for two threads to call
  `present`/`dismiss` on the same instance simultaneously. The one
  non-isolated closure in source — `dismiss()`'s fade-out completion handler
  — is asserted back onto the main actor via `MainActor.assumeIsolated`
  before touching `self`.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no network call, database access, or file I/O; every
  operation (mutating `alphaValue`, adding/removing subviews, invoking
  closures) is synchronous, in-process, and non-throwing.
- **Offline/disconnected state**: Not applicable — no networking exists
  anywhere in this file.
- **Escape and an unclaimed click arriving in the same runloop turn**
  (MUST): because `isDismissing` flips to `true` synchronously on the first
  call to `dismiss()` (per `dismissing-flag-timing`), whichever
  gesture is processed second sees `isDismissing == true` and is a
  guaranteed no-op — this is not a race that depends on animation timing.
- **A second overlay presented on top of the first** (MUST, per the class
  doc comment's "a message expanded over a conversation"): because
  `performKeyEquivalent` offers the event to subviews first (per
  `key-equivalent-subview-priority`), the topmost overlay — being the nearer
  subview in the responder chain — is the one Escape dismisses, not the one
  underneath it; see `dismissible-overlay-025` for the two-overlay vector
  this rests on.

## Configuration

`DismissibleOverlayView`
(`packages/apple/AgenticToolkit/CoreUI/DismissibleOverlayView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `material` | `NSVisualEffectView.Material` | `.hudWindow` | Backdrop blur material, set once at `init` and never reassigned afterward |
| `onDismissed` | `(() -> Void)?` | `nil` | Invoked synchronously once `dismiss()` begins, before the fade-out animation completes |
| `isDismissing` | `Bool` | `false` | `public private(set)` — readable by any caller, but only `dismiss()` itself can set it; `true` from the first `dismiss()` call onward |

```swift
public static let fadeDuration: TimeInterval = 0.2
public static let dismissKeyCodes: Set<UInt16> = [53, 36, 76]

public init(material: NSVisualEffectView.Material = .hudWindow)
open func present(in host: NSView)
public func dismiss()
open func willDismiss()
```

`fadeDuration` and `dismissKeyCodes` are fixed `static let` constants, not
per-instance options — Swift does not allow a stored `static let` to be
overridden by a subclass, so every instance and subclass shares exactly the
same 0.2 second fade and the same three dismiss key codes.

## Deep Linking

Not applicable: this is an internal, presentation-only view with no URL
scheme, route, or deep-link handler anywhere in the source; a caller
constructs it and calls `present(in:)` directly.

## Localization

Not applicable: `DismissibleOverlayView` renders no text and defines no
string literal of its own — no button titles, labels, or copy appear
anywhere in the source. Any strings belong to whatever content a subclass
adds above the backdrop, which is out of scope for this recipe.

## Accessibility Options

- **Reduce Motion**: Supported: `present(in:)` and `dismiss()` animate only
  `alphaValue` (a 0.2s opacity fade via `NSAnimationContext`, duration
  `fadeDuration`); nothing moves, scales, or slides. A cross-fade is the
  substitute the [Apple Human Interface Guidelines' Motion
  page](https://developer.apple.com/design/human-interface-guidelines/motion)
  recommends when Reduce Motion is on, so no separate Reduce Motion path is
  needed. A port keeps the fade opacity-only.
- **Increase Contrast**: Not applicable — this file chooses no color values
  of its own; the backdrop's appearance is entirely AppKit's system
  `NSVisualEffectView.Material` rendering, not anything this view controls.
- **Differentiate Without Color**: Not applicable — the base view conveys no
  state (presented, dismissing) via color at all; presence or absence from
  the view hierarchy and the alpha fade are its only signals, neither of
  which is a color distinction.

## Feature Flags

Not applicable: the source contains no feature-flag or config-gating
lookup. The overlay always presents and dismisses unconditionally when its
methods are called.

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
  once `dismiss()` removes it from its superview and the caller releases
  its reference.

## Logging

Not applicable: the source contains no logging call (no `os_log`, `Logger`,
or `print`).

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
manages dismissal focus-independently, but the "Keyboard focus containment"
open question under Accessibility is unresolved in source — nothing traps
Tab focus to the overlay's own content. `screen-reader-support` fails for
the "Label requirements" open question: no accessibility label describes
the overlay's presence or dismissal affordance. `reduced-motion` passes
because the only animation is an opacity fade (see Accessibility Options).
`platform-theming` passes because the backdrop's appearance comes entirely
from a system `NSVisualEffectView.Material` value, not a raw color this
view chooses itself.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case; reformatted Design Decisions to bold three-line form; moved the internal cross-reference from `references` to `related` and added the HIG Motion URL; corrected Compliance to real catalog checks and categories; added a two-overlay conformance vector and an `isDismissing` Configuration row; qualified the WinUI 3 accelerator-precedence claim; tightened animation-timing conformance vectors for XCTest executability; trimmed edge-case RFC tags and fixed the zero-sized-host accuracy issue. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DismissibleOverlayView` (AppKit, macOS) source. |
