---
id: 653874b6-86c4-41cb-9350-5f61bb5fca85
title: TypingIndicatorView
domain: agentictoolkit://recipes/typing-indicator-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An animated three-dot AppKit view that pulses in sequence to signal the assistant
  is composing a reply.
platforms:
- swift
- macos
tags:
- chat
- messaging
- ui-component
- typing-indicator
depends-on: []
related:
- agentictoolkit://recipes/chat-transcript-row-view
- agentictoolkit://recipes/chat-view
references:
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/documentation/foundation/runloop/mode-swift.struct/default
- https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.uisettings.animationsenabled
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Constructed but `startAnimating()` not yet called: every dot sits at `NSView`'s default `alphaValue` of 1.0, since alpha is only ever set inside `startAnimating()`/`tick()`. |
| Pressed | Not applicable: the view has no target-action, tracking area, or button subview — nothing in the source responds to a press. |
| Disabled | Not applicable: the source has no `isEnabled`-driven appearance change; nothing disables the indicator. |
| Focused | Not applicable: the source gives the view no focus ring, key-view-loop participation, or focus-driven appearance change. |
| Loading | This is the component's entire purpose: after `startAnimating()`, the dots pulse in the left-to-right chase pattern (see **single-dot-highlighted-per-tick**) until the view is removed from its superview (see **timer-invalidated-on-removal**). |

## Accessibility

- **Role**: Neither the container nor any dot subview has an accessibility role set (contrast with sibling `ChatDayBannerView`, which explicitly sets `.staticText`); nothing identifies this element to a screen reader.
- **Label**: No accessibility label describing the indicator's meaning (e.g. "Assistant is typing") is set anywhere in `setup()`, `startAnimating()`, or `tick()`.
- **Announce state changes**: Neither `startAnimating()` nor `tick()` nor `removeFromSuperview()` posts any `NSAccessibility` notification, so a VoiceOver user is given no indication that the assistant has started or stopped composing a reply.
- **Minimum tap target**: Not applicable — the view has no target-action or click handling of any kind, so Apple's [44×44pt tap-target guidance](https://developer.apple.com/design/human-interface-guidelines/layout) does not apply.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| typing-indicator-001 | three-dot-layout | Inspect a constructed instance's view tree | The container holds a horizontal row of exactly 3 dot elements, with 4pt spacing between each |
| typing-indicator-002 | pill-container-shape | Any constructed instance | The container's own corner radius equals 12pt; its width and height resolve to 48pt and 28pt respectively |
| typing-indicator-003 | stack-centered-in-container | Any constructed instance placed in a superview | The row of dots is centered within the container on both the horizontal and vertical axes |
| typing-indicator-004 | dot-size-and-shape | Any dot element | Width and height both equal 7pt; corner radius equals 3.5pt |
| typing-indicator-005 | container-fill-tracks-theme | Construct under theme A, then switch the active theme to theme B | Container background color equals theme A's `secondaryText` at 0.08 alpha immediately at construction, then updates to theme B's equivalent color after the switch, with no view re-creation |
| typing-indicator-006 | dot-color-tracks-theme | Construct under theme A, then switch the active theme to theme B | Every dot's background color equals theme A's `secondaryText` at full alpha immediately at construction, then updates to theme B's equivalent color after the switch |
| typing-indicator-007 | start-resets-dot-alpha | Call `startAnimating()` on a freshly constructed instance | All three dots' opacity equal 0.3 synchronously, before the first tick |
| typing-indicator-008 | start-schedules-repeating-timer | Call `startAnimating()`, then allow exactly one tick to fire | Dot 0 is the dot animated to opacity 1.0 on that first tick, and the interval from the call to that tick, and between each subsequent tick, is 0.35 seconds |
| typing-indicator-009 | single-dot-highlighted-per-tick | `startAnimating()`, then allow one tick | Exactly one dot animates opacity to 1.0 over 0.2 seconds while the other two animate to 0.3 over the same 0.2 seconds |
| typing-indicator-010 | single-dot-highlighted-per-tick | `startAnimating()`, then allow three consecutive ticks | The highlighted dot index advances 0 → 1 → 2 → 0, wrapping modulo 3 |
| typing-indicator-011 | timer-invalidated-on-removal | `startAnimating()`, then remove the view from its superview, then wait longer than one tick interval | No dot's opacity changes after removal; the highlight animation does not continue |
| typing-indicator-012 | start-schedules-repeating-timer, timer-invalidated-on-removal | Call `startAnimating()` twice in a row without an intervening removal from the view hierarchy | The second call replaces the animation timer without invalidating the first one, which remains scheduled independently; both timers then drive the tick against the shared highlight state, roughly doubling the effective tick rate — well-defined by the source, not a crash (see Edge Cases) |

## Edge Cases

- **Null/empty input**: Not applicable — the only initializer parameter is the inherited `frame: NSRect` from `NSView`; there is no optional or caller-supplied business input to guard against being null or empty.
- **Boundary values**: Not applicable in the sense of caller-facing constrained inputs — there are no numeric or string inputs. The view's own dimensional constants (48×28pt container, 7×7pt dots, 12pt/3.5pt corner radii, 4pt spacing) are fixed values set in `setup()`, not caller-supplied boundaries.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated, so Swift's concurrency checking confines `dots`, `timer`, and `step` to main-actor access; the timer's fire callback re-enters via `MainActor.assumeIsolated`.
- **Error states**: Not applicable — construction, `startAnimating()`, `tick()`, and `removeFromSuperview()` are all synchronous with no throwing or failable call anywhere in the source.
- **Offline/disconnected state**: Not applicable — the source performs no networking of any kind.
- **Repeated calls to `startAnimating()` while already animating**: The source does not guard against this. Calling it a second time overwrites the `timer` property with a new `Timer.scheduledTimer(...)` without invalidating the previous one; because the prior timer was already added to the run loop independently of that property reference, it keeps firing. Both timers then call `tick()` against the same shared `step` counter, so the highlighted dot advances roughly twice as fast as intended (see vector typing-indicator-012). This is well-defined, traceable behavior, not a crash, but it is very likely unintended.
- **View hidden but not removed**: Setting `isHidden = true` while animating does not stop the timer — the only path that invalidates it is `removeFromSuperview()` (see **timer-invalidated-on-removal**). An indicator that is hidden rather than removed keeps its timer firing and its animation running invisibly.
- **Timer suspended during UI event tracking**: `Timer.scheduledTimer(withTimeInterval:repeats:block:)` schedules the timer on the current run loop's `.default` mode only (it is not added to `.common` modes). Per Apple's documented [RunLoop.Mode.default](https://developer.apple.com/documentation/foundation/runloop/mode-swift.struct/default) behavior, a timer scheduled this way is suspended while the main run loop is servicing a tracking loop elsewhere in the same app — an interactive window drag, a live/continuous slider drag, or a modal panel — so the pulse can visibly pause during that kind of input and resume once it ends.

## Configuration

Not applicable: `TypingIndicatorView` exposes no caller-configurable options. Its only initializer parameter is the inherited `frame: NSRect`, and every appearance and timing constant — dot count, dot and container size, corner radii, spacing, tick interval, animation duration, and the two alpha levels — is fixed in `setup()`/`tick()`.

## Deep Linking

Not applicable: `TypingIndicatorView` is a transient, decorative status element embedded inside a chat transcript row, not a navigable screen or standalone destination; the source contains no URL scheme or route handling.

## Localization

Not applicable: the component renders no text or string content of any kind — three colored dot views and a rounded container, with no labels, titles, or other user-facing strings anywhere in the source.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | The pulsing alpha animation in `tick()` runs unconditionally once `startAnimating()` is called; nothing in `setup()`, `startAnimating()`, or `tick()` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` or observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, so a user with Reduce Motion enabled sees the same continuous looping pulse as everyone else. |
| Increase Contrast | The container fill (0.08 alpha) and the dimmed dot state (0.3 alpha) are both deliberately low-contrast by design, and the component does not respond to Increase Contrast: nothing in the source reads `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` to raise either value; see the open question on low-alpha-contrast. |
| Differentiate Without Color | Not applicable: the indicator conveys no state through color — every dot and the container share the same `secondaryText` hue throughout, and which dot is "active" is conveyed by opacity/brightness within that single hue, not by a color-coded distinction that would need a non-color alternative. |

- **low-alpha-contrast**: NEEDS REVIEW: Not implemented in source. The container fill (0.08 alpha) and the dimmed dot state (0.3 alpha) are fixed alpha multipliers this component applies over a host-supplied background, and the dot color itself comes from the active `SemanticPalette`; the source defines no contrast floor for either, so whether the dimmed dots and container remain distinguishable against a given host background requires a human judging the rendered contrast in the running UI.

## Feature Flags

Not applicable: the source contains no feature-flag conditional; the view is unconditionally constructed by its caller.

## Analytics

Not applicable: the source contains no analytics or event-tracking calls.

## Privacy

Not applicable: the component collects, stores, and transmits nothing. Its only in-memory state — the three dot views, the timer, and the step counter — is transient view state that exists solely to run the animation and holds no caller data.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print` statements).

## Platform Notes

- **SwiftUI**: Build an `HStack(spacing: 4)` of three `Circle().fill(color).frame(width: 7, height: 7)` views inside a `RoundedRectangle(cornerRadius: 12).fill(fillColor).frame(width: 48, height: 28)` background. Drive the wave with a `TimelineView(.periodic(from: .now, by: 0.35))` (or an owning view model's own repeating `Timer`) that advances an `activeIndex` and wraps each dot's `.opacity(index == activeIndex ? 1.0 : 0.3)` in `withAnimation(.easeInOut(duration: 0.2))`, matching **single-dot-highlighted-per-tick**. Read `@Environment(\.accessibilityReduceMotion)` to substitute a static state when true — SwiftUI makes that check easy where this source has none (see the Reduce Motion gap above). Source `fillColor`/dot color the same way `agentictoolkit://recipes/ai-chat-bubble-view#platforms/swiftui` sources its own theme colors.
- **Compose**: Build a `Row(horizontalArrangement = Arrangement.spacedBy(4.dp))` of three `Box` circles (`Modifier.size(7.dp).background(color, CircleShape)`) inside a `Modifier.background(fillColor, RoundedCornerShape(12.dp)).size(48.dp, 28.dp)` container. Drive the wave with a coroutine `while (isActive) { delay(350); ... }` loop (or `rememberInfiniteTransition`) advancing an active index, animating each dot's alpha with `animateFloatAsState(targetValue = ..., animationSpec = tween(200))`, matching **single-dot-highlighted-per-tick**. Gate the animation on `LocalContext.current`'s `Settings.Global.ANIMATOR_DURATION_SCALE` (Android's reduced-motion equivalent) before starting it, since the source has no such gate. Source `fillColor`/dot color from the same custom `CompositionLocal` palette holder documented at `agentictoolkit://recipes/ai-chat-bubble-view#platforms/compose`.
- **React/Web**: Render a flex row (`display: flex; align-items: center; gap: 4px`) of three `<span class="dot">` elements (`width: 7px; height: 7px; border-radius: 50%`) inside a container styled `border-radius: 12px; width: 48px; height: 28px`. Drive the wave with a `setInterval(350)` that advances an active index and toggles a CSS class per dot, with `.dot { opacity: 0.3; transition: opacity 200ms; } .dot.active { opacity: 1; }`, matching **single-dot-highlighted-per-tick**. Honor the `prefers-reduced-motion: reduce` media query by skipping the `transition` (or the interval entirely, holding one static state) — this source has no equivalent check at all. Source dot/container color from CSS custom properties tied to the active theme.
- **AppKit / UIKit**: Source: `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/TypingIndicatorView.swift`. Implemented as a `@MainActor`, `final` `NSView` subclass holding three plain `NSView`s (`wantsLayer = true`) inside an `NSStackView`, laid out entirely with `NSLayoutConstraint.activate` — the stack is centered with `centerXAnchor`/`centerYAnchor` constraints equal to the container's own (see **pill-container-shape**, **stack-centered-in-container**). The wave is driven by a private `Timer?` (`timer`) and a private `Int` step counter (`step`): `startAnimating()` resets `step` to zero and reschedules `timer` via `Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true)` (see **start-schedules-repeating-timer**); each fire re-enters via `MainActor.assumeIsolated` and animates each dot's `alphaValue` through `NSAnimationContext.runAnimationGroup` (see **single-dot-highlighted-per-tick**); `removeFromSuperview()` invalidates `timer` and sets it to `nil` (see **timer-invalidated-on-removal**). `init?(coder:)` is marked `@available(*, unavailable)` and calls `fatalError()` if reached at runtime regardless — a Swift/AppKit compile-time constraint with no equivalent construction path on the other platforms, so it carries no conformance vector of its own. Theme changes are observed via `observeTheme { view, palette in ... }`, the same pattern documented at `agentictoolkit://recipes/ai-chat-bubble-view#platforms/appkit-uikit` and `agentictoolkit://recipes/chat-day-banner-view#platforms/appkit-uikit`. This file targets macOS only — it lives under `macOS/Features` and uses `NSView`/`NSStackView`/`NSAnimationContext`, none of which exist in UIKit; an iOS port would substitute `UIView`/`UIStackView` and drive the pulse with `UIView.animate(withDuration:)` (or a `CADisplayLink`) on a `Timer`-driven or display-link-driven cadence, and would need its own theme-observation hook and its own Reduce Motion check via `UIAccessibility.isReduceMotionEnabled`, since this source has neither.
- **WinUI 3**: This is the platform with no direct analogue in the source, so start from first principles. Use a horizontal `StackPanel Orientation="Horizontal" Spacing="4"` holding three `Ellipse Width="7" Height="7" Fill="{ThemeResource SecondaryTextBrush}"`, placed as a sibling inside a `Grid` alongside a background `Border CornerRadius="12" Width="48" Height="28" Background="{ThemeResource SecondaryTextBrush}" Opacity="0.08"` — setting `Opacity` directly on that `Border` reproduces the fixed 0.08-alpha fill from **container-fill-tracks-theme** without inventing a separate low-alpha brush resource, and because the `Border` and the `StackPanel` are siblings rather than parent and child, the `Border`'s `Opacity` affects only the `Border` itself, not the ellipses. Drive the wave with a `DispatcherTimer` ticking every 350ms that advances an active index and starts a `Storyboard`/`DoubleAnimation` on the active `Ellipse.Opacity` from 0.3 to 1.0 over 200ms while animating the previously-active ellipse back to 0.3, matching **single-dot-highlighted-per-tick**. Before starting or resuming that `DispatcherTimer`, check `new Windows.UI.ViewManagement.UISettings().AnimationsEnabled` ([UISettings.AnimationsEnabled](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.uisettings.animationsenabled), WinUI's Reduce Motion analogue) and hold a static opacity state when it is false — a check this source does not have (see the Reduce Motion gap above). Bind `Ellipse.Fill` and the background `Border.Background` to the same `{ThemeResource SecondaryTextBrush}` entry so a `RequestedTheme`/high-contrast dictionary swap recolors both live, mirroring **container-fill-tracks-theme**/**dot-color-tracks-theme**: unlike this source's `observeTheme` callback, which pushes the new palette to the view explicitly, a `{ThemeResource}` binding re-resolves itself automatically when the app's theme or high-contrast dictionary changes, so no equivalent push mechanism is needed on this platform.

## Design Decisions

**Decision**: The container's fill color is the theme's `secondaryText` color at 0.08 alpha rather than a dedicated "indicator" color role.
**Rationale**: Per the source's own inline comment, this "matches the assistant bubble's fill, so the indicator reads as the message that is about to appear rather than a separate control." The exact shared role or value the assistant bubble itself uses is outside this file and is not verified here.
**Approved**: pending

**Decision**: Exactly one dot is fully opaque at a time, cycling in a fixed 0 → 1 → 2 order, rather than all three dots fading in and out together.
**Rationale**: Traceable to `tick()`'s `index == active` conditional. This produces the familiar left-to-right "chase" read as typing, rather than a synchronized pulse. Because the dots sit in a horizontal `NSStackView`, their visual left-to-right order follows the layout direction, so the chase direction would mirror automatically in a right-to-left layout; the source does not special-case this.
**Approved**: pending

**Decision**: The animation has no `stopAnimating()` counterpart to `startAnimating()`; the only thing that halts it is `removeFromSuperview()`.
**Rationale**: Not explained in source comments. This is consistent with how the component is used elsewhere in the chat feature — inserted while a message is sending and removed once it is not — so removal doubles as the stop signal in that usage. It does mean a caller that wants to keep the view in the hierarchy but pause the animation (e.g. hide it) has no API for that; see the "View hidden but not removed" and "Repeated calls to `startAnimating()`" edge cases.
**Approved**: pending

**Decision**: Reduce Motion and Increase Contrast are left unhandled in this file.
**Rationale**: Not explained in source comments; recorded here as known technical debt affecting behavioral correctness for users with either preference enabled — the component does not respond to Increase Contrast, and the rendered contrast is the open question on low-alpha-contrast.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | failed | Accessibility |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | partial | Platform Compliance |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | partial | Platform Compliance |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |

`failed` rows rest on a total absence in source: no accessibility role, label, or state-change notification exists anywhere (screen-reader-support), and no Reduce Motion check of any kind gates the looping pulse (reduced-motion). `partial` rows reflect what the source only partly addresses: the dot and container colors resolve from the active `SemanticPalette`, which this file neither defines nor can verify for contrast, but the two alpha multipliers (0.08, 0.3) are this component's own deliberately low-contrast choices with no Increase Contrast accommodation (contrast-ratio); the view follows AppKit layer/Auto Layout conventions and theme-driven color throughout, but the fixed 12pt corner radius on a 28pt pill does not fully round its ends the way a stadium shape would, with no rationale given in source (platform-design-language); and a custom three-dot widget was built rather than reusing a stock control such as `NSProgressIndicator`, which has no built-in equivalent of this specific chase pattern (native-controls-preference). The `passed` row rests on the `observeTheme` registration applying the palette immediately at construction and again on every subsequent theme change, recoloring both the container fill and the dots (platform-theming).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial creation from the macOS/AppKit source (TypingIndicatorView.swift) |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: fixed Design Decisions' `**Approved**: pending` formatting; renamed `dots-centered-in-stack` to `stack-centered-in-container` and updated its citations and vector; replaced named cross-recipe mentions of Message Bubble and Chat Day Banner with domain URL fragments (and their current `AIChatBubbleView` name); rewrote AppKit-specific requirement wording (`NSStackView`, `alphaValue`, layer `cornerRadius`) into platform-neutral behavior and moved the private `timer`/`step` identifiers and the `init(coder:)` compile-time constraint into the AppKit/UIKit Platform Note, dropping its untestable conformance vector; rewrote the vectors for the timer-schedule and timer-invalidation requirements to assert observable dot behavior instead of private state; corrected the WinUI 3 note's invented brush resource, simplified its sibling-Border reasoning, and fixed its `ThemeResource` live-refresh contradiction; added references for the tap-target guidance, `RunLoop.Mode.default` suspension, and WinUI `AnimationsEnabled` and cited them inline; and removed source-audit phrasing ("per the class's own doc comment", "the source gives no rationale") from the Overview, Appearance, and conformance vectors, stating the behavior directly |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
