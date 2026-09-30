<!-- leaf: implement-general-view-1/dismissible-overlay-view · source: dismissible-overlay-view.md -->

**Rules** (cite as `implement-general-view-1/dismissible-overlay-view#<slug>`):

- `main-actor-isolation` MUST
- `coder-init` MUST
- `auto-layout-participation` MUST
- `blurred-backdrop` MUST
- `backdrop-subview-order` MUST
- `backdrop-material-default` MUST
- `backdrop-material-override` MUST
- `host-coverage` MUST
- `present-layout-order` MUST
- `present-fade` MUST
- `dismiss-fade` MUST
- `post-fade-removal` MUST
- `dismiss-idempotency` MUST
- `dismissing-flag-timing` MUST
- `will-dismiss-timing` MUST
- `dismissed-callback-timing` MUST
- `default-will-dismiss` MUST
- `mouse-down-dismissal` MUST
- `key-equivalent-subview-priority` MUST
- `escape-return-dismissal` MUST
- `non-dismiss-key-equivalents` MUST
- `key-equivalents-during-dismissal` MUST
- `open-subclassing` MUST
- `will-dismiss-cleanup` SHOULD
- `optional-dismissed-callback` MAY

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

## Accessibility

- **Role/trait**: Not explicitly set — the source calls no
  `setAccessibilityRole`/`accessibilityRole` override anywhere; `NSView`'s
  own AppKit default applies unmodified.
- **Label requirements**: Not implemented in source. Nothing in
  `DismissibleOverlayView` sets an accessibility label or description on
  itself or the backdrop, so a VoiceOver user gets no announced description
  that this is a dismissible overlay or of how to dismiss it (click anywhere
  unclaimed, Escape, or Return); any such label would have to come from a
  subclass or caller, and none of the toolkit's current subclasses supplies
  one.
- **Announce state changes**: Not implemented in source. Neither
  `present(in:)` nor `dismiss()` calls
  `NSAccessibility.post(element:notification:)` when the overlay appears or
  disappears, so no explicit VoiceOver notification is posted at either
  transition — only whatever AppKit's own default view-hierarchy handling
  provides applies.
- **keyboard-focus-containment**: NEEDS REVIEW: Not implemented in source. `performKeyEquivalent` only intercepts Escape, Return, and keypad Enter; nothing restricts Tab-key focus traversal to the overlay's own content while presented, so a keyboard user could Tab onto a host control underneath the backdrop, and whether that is acceptable can only be settled by a keyboard-only pass tabbing through a presented overlay with the running UI.
- **Minimum tap target**: Not applicable in the small-target sense — per
  `mouse-down-dismissal` and `host-coverage`,
  the dismiss gesture's target is the overlay's entire frame, which itself
  covers the host entirely; there is no small tap target to size.
- **Minimum contrast ratio**: Not applicable to this base view — it renders
  no text or foreground content of its own (see Appearance). Contrast is
  the responsibility of whatever content a subclass adds above the
  backdrop, which is out of scope for this recipe.

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

