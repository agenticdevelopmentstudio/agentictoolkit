<!-- leaf: implement-general-view-3/typing-indicator-view · source: typing-indicator-view.md -->

**Rules** (cite as `implement-general-view-3/typing-indicator-view#<slug>`):

- `three-dot-layout` MUST
- `pill-container-shape` MUST
- `stack-centered-in-container` MUST
- `dot-size-and-shape` MUST
- `container-fill-tracks-theme` MUST
- `dot-color-tracks-theme` MUST
- `start-resets-dot-alpha` MUST
- `start-schedules-repeating-timer` MUST
- `single-dot-highlighted-per-tick` MUST
- `timer-invalidated-on-removal` MUST

# TypingIndicatorView

## Overview

`TypingIndicatorView` is a macOS, AppKit view that shows three small dots inside a rounded pill and, once started, pulses them one at a time in a left-to-right chase to signal that the assistant is composing a reply — an animated typing indicator built from three pulsing dots. It is theme-aware — the pill's fill and the dots' color are resolved from the active `SemanticPalette` and reapplied on every theme change — and it owns no state beyond what it needs to run and stop that animation: the caller starts it explicitly with `startAnimating()`, and it stops implicitly when removed from its superview.

## Behavioral Requirements

- **three-dot-layout**: The component MUST render exactly three dot elements arranged in a horizontal row with 4pt spacing between them.
- **pill-container-shape**: The component MUST render itself as a fixed 48×28pt container with a 12pt corner radius on its own background.
- **stack-centered-in-container**: The component MUST center the row of dots within the container on both the horizontal and vertical center lines.
- **dot-size-and-shape**: Each dot MUST be exactly 7×7pt with a corner radius of 3.5pt, rendering as a circle.
- **container-fill-tracks-theme**: The component MUST set its own background color to the active theme's `secondaryText` color at 0.08 alpha, applied immediately when the view is constructed and reapplied every time the active theme's palette changes.
- **dot-color-tracks-theme**: The component MUST set every dot's background color to the active theme's `secondaryText` color at full alpha, applied immediately when the view is constructed and reapplied every time the active theme's palette changes.
- **start-resets-dot-alpha**: When `startAnimating()` is called, the component MUST set every dot's opacity to 0.3 before scheduling the animation timer.
- **start-schedules-repeating-timer**: When `startAnimating()` is called, the component MUST make dot 0 the next dot to be highlighted and MUST schedule a repeating tick every 0.35 seconds thereafter.
- **single-dot-highlighted-per-tick**: On each tick, the component MUST animate exactly one dot's opacity to 1.0 over 0.2 seconds while animating the other two dots' opacity to 0.3 over the same 0.2 seconds, and MUST advance which dot is highlighted by one position (wrapping modulo 3) on every subsequent tick.
- **timer-invalidated-on-removal**: The component MUST stop its animation timer when it is removed from the view hierarchy.

## Appearance

- **Corner radius**: 12pt on the container's own background; 3.5pt on each 7×7pt dot, which is exactly half the dot's side length and so renders a true circle (see **dot-size-and-shape**). The container's 12pt radius on a 28pt-tall pill is less than the 14pt a fully rounded ("stadium") end would need.
- **Padding**: None defined as edge insets. The row of dots is positioned by centering rather than pinned to the container's edges (see **stack-centered-in-container**).
- **Font**: Not applicable; the component renders no text.
- **Background**: Container fill is the active theme's `secondaryText` color at 0.08 alpha (see **container-fill-tracks-theme**); there is no separate "indicator background" role.
- **Foreground/Text**: Not applicable; the component renders no text.
- **Border**: None.
- **Shadow**: None.
- **Min/Max size**: Fixed at 48×28pt via `widthAnchor`/`heightAnchor` constant constraints (see **pill-container-shape**); no minimum or maximum range is declared, so an external constraint or superview requesting a different size will conflict with these default-priority (required) constraints (see Edge Cases).

## Accessibility

- **Role**: Neither the container nor any dot subview has an accessibility role set (contrast with sibling `ChatDayBannerView`, which explicitly sets `.staticText`); nothing identifies this element to a screen reader.
- **Label**: No accessibility label describing the indicator's meaning (e.g. "Assistant is typing") is set anywhere in `setup()`, `startAnimating()`, or `tick()`.
- **Announce state changes**: Neither `startAnimating()` nor `tick()` nor `removeFromSuperview()` posts any `NSAccessibility` notification, so a VoiceOver user is given no indication that the assistant has started or stopped composing a reply.
- **Minimum tap target**: Not applicable — the view has no target-action or click handling of any kind, so Apple's [44×44pt tap-target guidance](https://developer.apple.com/design/human-interface-guidelines/layout) does not apply.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | The pulsing alpha animation in `tick()` runs unconditionally once `startAnimating()` is called; nothing in `setup()`, `startAnimating()`, or `tick()` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` or observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, so a user with Reduce Motion enabled sees the same continuous looping pulse as everyone else. |
| Increase Contrast | The container fill (0.08 alpha) and the dimmed dot state (0.3 alpha) are both deliberately low-contrast by design, and the component does not respond to Increase Contrast: nothing in the source reads `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` to raise either value; see the open question on low-alpha-contrast. |
| Differentiate Without Color | Not applicable: the indicator conveys no state through color — every dot and the container share the same `secondaryText` hue throughout, and which dot is "active" is conveyed by opacity/brightness within that single hue, not by a color-coded distinction that would need a non-color alternative. |

- **low-alpha-contrast**: NEEDS REVIEW: Not implemented in source. The container fill (0.08 alpha) and the dimmed dot state (0.3 alpha) are fixed alpha multipliers this component applies over a host-supplied background, and the dot color itself comes from the active `SemanticPalette`; the source defines no contrast floor for either, so whether the dimmed dots and container remain distinguishable against a given host background requires a human judging the rendered contrast in the running UI.

