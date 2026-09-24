---
id: 1cecd319-1cc2-40a5-8ef0-56267eb78b89
title: SessionWatcherActivityIconView
domain: agentictoolkit://recipes/session-watcher-activity-icon-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Fixed-size AppKit glyph showing a session row's activity — spinning arrows
  while working, a pulsing warning icon while waiting, sparkles while summarizing,
  and nothing while idle.
platforms:
- swift
- macos
tags:
- ui
- status-indicator
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# SessionWatcherActivityIconView

## Overview

`SessionWatcherActivityIconView`, at
`packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionListWindow/SessionWatcherActivityIconView.swift`,
is a nested type — `SessionWatcher.SessionWatcherActivityIconView` — implemented
as a `final` `NSView` subclass conforming to `Themeable`. It is the single
glyph a session list row shows at the end of its header line to say what that
session is doing right now: chasing arrows while the agent is working, a
pulsing exclamation badge while it is waiting on the user, sparkles while a
summarization is running over the session, or nothing at all while the
session is simply idle. It owns a small, fixed-size (13×13pt) `CALayer`
sublayer that it recolors and animates in place as `update(activity:isSummarizing:)`
is called on every poll of the session list, rather than being torn down and
rebuilt, so a running spin or pulse survives repeated polling without
stuttering.

## Behavioral Requirements

- **fixed-glyph-size**: The component MUST constrain both its width and
  height to a fixed 13pt (`Self.side`), regardless of `activity` or
  `isSummarizing`.
- **resists-horizontal-compression**: The component MUST set a required
  horizontal content-compression-resistance priority on itself
  (`setContentCompressionResistancePriority(.required, for: .horizontal)`).
- **selects-symbol-by-state**: The component MUST use the `sparkles` SF
  Symbol whenever `isSummarizing` is `true`, regardless of `activity`; and
  otherwise MUST use `arrow.triangle.2.circlepath` for `activity == .working`,
  `circle.fill` for `activity == .idle`, and `exclamationmark.circle.fill`
  for `activity == .waiting`.
- **hides-when-idle-and-not-summarizing**: The component MUST set
  `isHidden = true` only when `activity == .idle` and `isSummarizing ==
  false`, and MUST be visible (`isHidden = false`) for every other
  combination of `activity` and `isSummarizing`.
- **tints-by-state**: The component MUST tint the glyph with the active
  theme's accent color when `isSummarizing` is `true` or `activity ==
  .working`, with the theme's tertiary text color when `activity == .idle`
  and `isSummarizing` is `false`, and with the theme's warning color when
  `activity == .waiting` and `isSummarizing` is `false`.
- **defaults-tint-before-first-theme-apply**: The component MUST use
  `NSColor.tertiaryLabelColor` as the glyph's tint until `applyTheme(_:)` is
  called for the first time.
- **rasterizes-tint-via-fill**: The component MUST recolor the SF Symbol by
  drawing the raw symbol image and then filling the tint color over it with
  `.sourceAtop` compositing, rather than by an `NSImage.SymbolConfiguration`
  color configuration.
- **renders-nothing-for-unresolvable-symbol**: The component MUST set the
  glyph layer's `contents` to `nil` when `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for the currently selected symbol name.
- **updates-in-place**: The component MUST update an existing instance's
  displayed state through `update(activity:isSummarizing:)` rather than
  requiring callers to construct a new instance for a state change.
- **skips-redundant-updates**: The component MUST return from
  `update(activity:isSummarizing:)` without redrawing, re-describing
  accessibility, or touching any animation when neither `activity` nor
  `isSummarizing` differs from the view's current values.
- **restarts-animation-on-real-change**: The component MUST stop any running
  glyph animation and, only if it is currently in a window, start the
  animation appropriate to the new state, whenever
  `update(activity:isSummarizing:)` is called with a value that actually
  changes `activity` or `isSummarizing`.
- **pulses-for-waiting-or-summarizing**: The component MUST animate the
  glyph layer's opacity from `1.0` to `0.25` and back (autoreversing) over
  0.7 seconds, repeating indefinitely, whenever `isSummarizing` is `true` or
  `activity == .waiting`.
- **spins-for-working**: The component MUST rotate the glyph layer one full
  turn clockwise on screen (`transform.rotation.z` from `0` to `-2π`) over
  1.1 seconds with a linear timing function, repeating indefinitely, when
  `activity == .working` and neither `isSummarizing` is `true` nor `activity
  == .waiting`.
- **installs-animations-idempotently**: The component MUST NOT add a new
  pulse or rotation animation for a key that already has an animation
  installed on the glyph layer.
- **drops-animations-off-window**: The component MUST remove both the
  rotation and the pulse animation from the glyph layer when the view moves
  to a `nil` window.
- **reinstalls-animations-on-window-attach**: The component MUST re-render
  the glyph and start its state-appropriate animation whenever the view
  moves into a non-`nil` window.
- **tracks-appearance-changes**: The component MUST re-render the glyph
  whenever the view's effective appearance changes, so that a dynamic tint
  color resolves against the new appearance.
- **tracks-backing-scale-changes**: The component MUST re-render the glyph
  whenever the view's backing properties change, rasterizing at the window's
  current `backingScaleFactor`, falling back to the main screen's
  `backingScaleFactor`, falling back to `2` if neither is available.
- **lays-out-glyph-layer-to-bounds**: The component MUST keep the glyph
  sublayer's `bounds` equal to the view's own `bounds` and its `position`
  centered in the view on every layout pass, with implicit layer actions
  disabled for that update.
- **exposes-image-accessibility-role**: The component MUST expose itself to
  assistive technology as an accessibility element with the `.image` role.
- **labels-and-tooltips-by-state**: The component MUST set both its
  accessibility label and its `toolTip` to `"Working"`, `"Idle"`, `"Waiting
  for you"`, or `"Summarizing"`, selected by the exact same `isSummarizing`/
  `activity` logic as **selects-symbol-by-state**.
- **identifies-itself-per-state**: The component MUST set its accessibility
  identifier to `session-panel.activity.summarizing` when `isSummarizing` is
  `true`, or to `session-panel.activity.working` / `session-panel.activity.idle`
  / `session-panel.activity.waiting` otherwise, matching `activity`.
- **rejects-storyboard-instantiation**: The component MUST fail with a fatal
  error if constructed via `init?(coder:)`, since it provides no Interface
  Builder/`NSCoding` support.

## Appearance

- **Corner radius**: None — neither the view's own layer nor the glyph
  sublayer sets a `cornerRadius`.
- **Padding**: None — the glyph layer fills the view's bounds exactly (see
  **lays-out-glyph-layer-to-bounds**); there is no internal inset.
- **Font**: Not applicable in the text sense — the component renders an SF
  Symbol image, not text. The symbol is rasterized at `NSImage.SymbolConfiguration(pointSize:
  11, weight: .semibold)`.
- **Background**: None/transparent — the view has `wantsLayer = true` but no
  `backgroundColor` is set on either its own layer or the glyph sublayer.
- **Foreground/Text**: The glyph's tint — the active theme's accent,
  tertiary-text, or warning color (see **tints-by-state**), or
  `NSColor.tertiaryLabelColor` before the first `applyTheme(_:)` call.
- **Border**: None — no `borderWidth`/`borderColor` is set on either layer.
- **Shadow**: None — no shadow-related layer property is set.
- **Min/Max size**: Fixed, not a range — both width and height are pinned to
  exactly 13pt (see **fixed-glyph-size**). The glyph layer's
  `contentsGravity` is `.resizeAspect`, so the rasterized symbol image scales
  to fit that fixed 13×13pt box without distortion.

## States

| State | Appearance change |
|-------|------------------|
| Idle, not summarizing (`activity: .idle, isSummarizing: false`) | View is hidden (`isHidden = true`); no glyph is drawn and no animation runs. |
| Working, not summarizing (`activity: .working, isSummarizing: false`) | Visible; `arrow.triangle.2.circlepath` tinted with the theme's accent color; spins one full clockwise turn every 1.1s, indefinitely. |
| Waiting, not summarizing (`activity: .waiting, isSummarizing: false`) | Visible; `exclamationmark.circle.fill` tinted with the theme's warning color; opacity pulses 1.0→0.25 and back every 0.7s, indefinitely. |
| Summarizing (`isSummarizing: true`, any `activity`) | Visible; `sparkles` tinted with the theme's accent color; opacity pulses 1.0→0.25 and back every 0.7s, indefinitely — the same pulse as Waiting, regardless of the underlying `activity`. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — this is a purely visual, non-interactive display element with no pressed state to represent. |
| Disabled | Not applicable: the source defines no `isEnabled` property or dimmed-appearance branch. |
| Focused | Not applicable: the view never becomes key/first responder; the source does not override `acceptsFirstResponder`, so `NSView`'s default (`false`) applies unmodified. |
| Loading | Not applicable: the view performs no asynchronous operation of its own and defines no loading flag; the "Working"/"Waiting" rows above are externally supplied state this view renders, not a loading operation this view performs. |

## Accessibility

- **Role/trait**: `NSAccessibilityRole.image`, set explicitly via
  `setAccessibilityRole(.image)` alongside `setAccessibilityElement(true)` in
  `init`.
- **Label requirements**: Satisfied unconditionally — `describeState()` sets
  the accessibility label to `"Working"`, `"Idle"`, `"Waiting for you"`, or
  `"Summarizing"` (see **labels-and-tooltips-by-state**) every time the
  state is established (`init`) or actually changed (`update`), so the
  label never describes a stale state. The same text is mirrored into
  `toolTip`.
- **Announce state changes**: `describeState()` reassigns the accessibility
  label, `toolTip`, and accessibility identifier whenever `activity` or
  `isSummarizing` actually changes, but no `NSAccessibility.post(element:notification:)`
  call accompanies that reassignment anywhere in the source.
  **NEEDS REVIEW: Not implemented in source. Behavior undefined.** Whether
  VoiceOver reliably announces the new label to a user already focused on
  this glyph when its underlying value reassigns — without an explicit posted
  notification — cannot be determined from this file alone. Settling this
  needs either an `NSAccessibility.post(element:notification: .titleChanged)`
  (or `.valueChanged`) call in `describeState()`, or a VoiceOver-pass
  confirmation that AppKit's default handling already surfaces the change.
- **Minimum tap target**: Not applicable in the iOS/touch sense — this is a
  macOS, pointer-driven `NSView` with no target/action, gesture recognizer,
  or click handling of any kind in the source; Apple's 44×44pt minimum
  applies to touch targets, not to a static AppKit image view.
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source. The
  glyph's tint (theme accent/tertiary-text/warning color, or the
  `tertiaryLabelColor` system fallback) is rasterized as an opaque fill over
  whatever background sits behind this 13×13pt view — a session row in a
  list — with no contrast check against that background anywhere in this
  file. Whether any tint/background pairing meets a specific contrast ratio
  cannot be determined from `SessionWatcherActivityIconView.swift` alone; it
  depends on the actual `SemanticPalette` colors and the row background it
  is placed against. Settling this needs a contrast audit of each tint
  against the session row background across the app's shipped themes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| activity-icon-001 | fixed-glyph-size | Any constructed instance | Both `widthAnchor` and `heightAnchor` resolve to exactly 13pt |
| activity-icon-002 | resists-horizontal-compression | Any constructed instance, placed in a horizontally-constrained stack view | The view's horizontal content-compression-resistance priority reads `.required`; it does not shrink below 13pt |
| activity-icon-003 | selects-symbol-by-state | `init(activity: .working, isSummarizing: true)` | The glyph is drawn from the `sparkles` symbol, not `arrow.triangle.2.circlepath` |
| activity-icon-003b | selects-symbol-by-state | `init(activity: .waiting, isSummarizing: false)` | The glyph is drawn from `exclamationmark.circle.fill` |
| activity-icon-004 | hides-when-idle-and-not-summarizing | `init(activity: .idle, isSummarizing: false)` | `isHidden == true` |
| activity-icon-004b | hides-when-idle-and-not-summarizing | `init(activity: .idle, isSummarizing: true)` | `isHidden == false` |
| activity-icon-005 | tints-by-state | `applyTheme(palette)` with `activity == .waiting, isSummarizing == false` | The glyph is filled with `palette.warningColor` |
| activity-icon-005b | tints-by-state | `applyTheme(palette)` with `activity == .idle, isSummarizing == false` | The glyph is filled with `palette.tertiaryTextColor` |
| activity-icon-006 | defaults-tint-before-first-theme-apply | Newly constructed instance, `applyTheme` never called | The glyph is filled with `NSColor.tertiaryLabelColor` |
| activity-icon-007 | rasterizes-tint-via-fill | `applyTheme(palette)` with `activity == .waiting` | The rendered raster shows the exclamation mark distinct from its surrounding circle (not a single flat-colored silhouette) |
| activity-icon-008 | renders-nothing-for-unresolvable-symbol | `NSImage(systemSymbolName:accessibilityDescription:)` stubbed/mocked to return `nil` for the selected symbol name | `glyph.contents == nil` |
| activity-icon-009 | updates-in-place | Existing instance, `update(activity: .waiting, isSummarizing: false)` called | The same instance now renders the waiting glyph; no new instance was created |
| activity-icon-010 | skips-redundant-updates | Existing instance at `activity: .working, isSummarizing: false`, then `update(activity: .working, isSummarizing: false)` | No re-render, no `describeState()` call, and the running spin animation is left untouched (does not restart) |
| activity-icon-011 | restarts-animation-on-real-change | Existing instance in a window at `activity: .idle, isSummarizing: false` (hidden), then `update(activity: .working, isSummarizing: false)` | `isHidden` becomes `false`; a new `rotationKey` animation is installed |
| activity-icon-012 | pulses-for-waiting-or-summarizing | Instance in a window, `update(activity: .waiting, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-pulse")` is non-nil, opacity animates 1.0→0.25→1.0 over 0.7s, repeating |
| activity-icon-013 | spins-for-working | Instance in a window, `update(activity: .working, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-rotation")` is non-nil, `transform.rotation.z` animates 0→−2π over 1.1s linear, repeating |
| activity-icon-014 | installs-animations-idempotently | Instance already spinning (`working`), `startAnimation()` invoked again without an intervening `stopAnimation()` | `glyph.animation(forKey: "session-activity-rotation")` is unchanged (no duplicate animation added) |
| activity-icon-015 | drops-animations-off-window | Instance in a window and spinning (`working`), then removed from its superview (`window == nil`) | `glyph.animation(forKey: "session-activity-rotation")` becomes `nil` |
| activity-icon-016 | reinstalls-animations-on-window-attach | Freshly constructed `activity: .working` instance, not yet in any window, then added to a window | The glyph re-renders and `glyph.animation(forKey: "session-activity-rotation")` becomes non-nil |
| activity-icon-017 | tracks-appearance-changes | Instance on screen, `viewDidChangeEffectiveAppearance()` invoked (e.g. system switches light/dark) | The glyph re-renders (raster contents regenerate) reflecting the new appearance's resolved tint |
| activity-icon-018 | tracks-backing-scale-changes | Instance moved to a window with a different `backingScaleFactor`, `viewDidChangeBackingProperties()` invoked | `glyph.contentsScale` matches the new window's `backingScaleFactor` |
| activity-icon-019 | lays-out-glyph-layer-to-bounds | View resized, `layout()` invoked | `glyph.bounds == view.bounds`; `glyph.position == (bounds.midX, bounds.midY)`; no implicit layer animation plays for the change |
| activity-icon-020 | exposes-image-accessibility-role | Any constructed instance | `accessibilityRole() == .image`; `isAccessibilityElement() == true` |
| activity-icon-021 | labels-and-tooltips-by-state | `init(activity: .waiting, isSummarizing: false)` | Accessibility label and `toolTip` both read `"Waiting for you"` |
| activity-icon-021b | labels-and-tooltips-by-state | `init(activity: .working, isSummarizing: true)` | Accessibility label and `toolTip` both read `"Summarizing"` (summarizing overrides activity) |
| activity-icon-022 | identifies-itself-per-state | `init(activity: .idle, isSummarizing: false)` | `accessibilityIdentifier() == "session-panel.activity.idle"` |
| activity-icon-022b | identifies-itself-per-state | `init(activity: .idle, isSummarizing: true)` | `accessibilityIdentifier() == "session-panel.activity.summarizing"` |
| activity-icon-023 | rejects-storyboard-instantiation | `SessionWatcherActivityIconView(coder:)` invoked (e.g. nib/storyboard unarchiving) | Process traps with a fatal error |

## Edge Cases

- **Null/empty input**: Not applicable — `activity`
  (`SessionWatcher.SessionWatcherActivity`, a 3-case, non-optional enum) and
  `isSummarizing` (`Bool`) are both required, non-optional, typed
  constructor/`update` parameters; there is no null or empty variant for
  either to guard against.
- **Boundary values**: Not applicable — the component's only inputs are the
  fixed 3-case `activity` enum and a `Bool`; there is no numeric or
  range-bound input with a minimum/maximum boundary to test. The layout
  constant (13pt) and animation durations (0.7s, 1.1s) are literals in the
  source, not caller-configurable ranges.
- **Concurrent access**: The source defines no lock, queue, or explicit
  actor isolation of its own (unlike some sibling AppKit types, it carries
  no `@MainActor` attribute in this file). All of its mutable state
  (`activity`, `isSummarizing`, `tint`, `palette`) is touched only from
  `init`, `update(activity:isSummarizing:)`, and AppKit's own
  main-thread-invoked view-lifecycle callbacks (`viewDidMoveToWindow`,
  `viewDidChangeEffectiveAppearance`, `viewDidChangeBackingProperties`,
  `layout()`); nothing in the source itself prevents `update` from being
  called off the main thread, so the safety of concurrent access rests on
  AppKit's general view-mutation convention rather than a guarantee this
  file enforces.
- **Error states (dependency/network/filesystem failure)**: Not applicable
  — the source performs no I/O, network call, or dependency lookup of any
  kind; its only external input is the `activity`/`isSummarizing` values a
  caller passes in directly.
- **Offline/disconnected state**: Not applicable — the component performs
  no network operation of its own.
- **Missing/unresolvable SF Symbol**: If `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for the selected symbol name, `renderGlyph()` sets
  `glyph.contents = nil` and returns — no fallback image, placeholder, or
  crash (MUST, per **renders-nothing-for-unresolvable-symbol**). All four
  symbol names the source actually selects (`sparkles`,
  `arrow.triangle.2.circlepath`, `circle.fill`,
  `exclamationmark.circle.fill`) are real system symbols, so this path is
  unreached in normal operation but is still defined, source-observed
  behavior.
- **`update` called with a real change while off-window**: `stopAnimation()`
  still runs, but `startAnimation()` is gated on `window != nil`, so the new
  animation does not begin until the view is later added to a window
  (`viewDidMoveToWindow` re-renders and starts it then) (MUST, per
  **restarts-animation-on-real-change** and
  **reinstalls-animations-on-window-attach**).
- **Rapid repeated `update` calls with unchanged values**: Each call is a
  no-op past the initial equality guard — no redraw, no
  `describeState()`, no animation churn — which is what keeps a
  continuously-polled "working" spin visually smooth rather than restarting
  from zero on every poll (MUST, per **skips-redundant-updates**).

## Configuration

`SessionWatcherActivityIconView` (`packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionListWindow/SessionWatcherActivityIconView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `activity` | `SessionWatcher.SessionWatcherActivity` (`.working` / `.idle` / `.waiting`) | — (required) | Which activity state the glyph, its tint, and its animation represent |
| `isSummarizing` | `Bool` | — (required) | Whether a summarization is running over the session; overrides the symbol to `sparkles` and the tint to the accent color regardless of `activity`, and forces the pulse animation |

```swift
public init(activity: SessionWatcherActivity, isSummarizing: Bool)
public func update(activity: SessionWatcherActivity, isSummarizing: Bool)
public func applyTheme(_ palette: SemanticPalette)
```

## Deep Linking

Not applicable: `SessionWatcherActivityIconView` is a display-only `NSView`
subclass with no route, URL scheme handling, or navigable identity anywhere
in the source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | `Working` | Accessibility label and `toolTip` when `activity == .working` and `isSummarizing == false` |
| — (hardcoded literal, no key) | `Idle` | Accessibility label and `toolTip` when `activity == .idle` and `isSummarizing == false` |
| — (hardcoded literal, no key) | `Waiting for you` | Accessibility label and `toolTip` when `activity == .waiting` and `isSummarizing == false` |
| — (hardcoded literal, no key) | `Summarizing` | Accessibility label and `toolTip` when `isSummarizing == true`, regardless of `activity` |

These four strings are assigned through `setAccessibilityLabel(_:)` and the
`NSView.toolTip` setter, both of which take a plain `String` — not a
SwiftUI `LocalizedStringKey` — so, unlike a string literal handed to a
SwiftUI `Text`/`Label`/`Button`, none of these four are localized by the
platform automatically; each needs an explicit lookup (e.g.
`NSLocalizedString` or a String Catalog entry) to translate.

NEEDS REVIEW: Not implemented in source. The source performs no such lookup,
so all four reach VoiceOver and the tooltip in English only.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | NEEDS REVIEW: Not implemented in source. The rotation (`working`'s spin) and the opacity pulse (`waiting`/summarizing) both repeat indefinitely (`repeatCount = .greatestFiniteMagnitude`), and no code in this file checks `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (or any other Reduce Motion signal) before starting either, nor is a static substitute offered for either animated state. Settling this needs either a Reduce-Motion-gated static-icon substitution inside `startAnimation()`, or confirmation from the design/accessibility team that always-on animation here is an accepted exception. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`); the tint always comes from the active `SemanticPalette` (or the `NSColor.tertiaryLabelColor` system fallback before the first theme apply), so whether the resulting contrast is adequate is tracked once under Accessibility → Minimum contrast ratio above, not duplicated here. |
| Differentiate Without Color | Supported: each state's SF Symbol shape (`arrow.triangle.2.circlepath`, `circle.fill`, `exclamationmark.circle.fill`, `sparkles`) differs from every other state's shape independently of the tint color `applyTheme` assigns (see **selects-symbol-by-state** and **tints-by-state**), so state is never conveyed by color alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. The view renders
unconditionally, driven only by the `activity`/`isSummarizing` values its
caller supplies.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
calls.

## Privacy

- **Data collected**: None. The component holds only the `activity` and
  `isSummarizing` values passed to it by its caller; it originates no data
  of its own.
- **Storage**: Not applicable — the component performs no persistence of
  any kind.
- **Transmission**: Not applicable — the component performs no network I/O.
- **Retention**: Not applicable — the component retains state only for the
  lifetime of the view instance itself.

## Logging

Not applicable: the source contains no logging calls (no `os_log`,
`Logger`, or `print`).

## Platform Notes

- **SwiftUI**: Compose a small `View` wrapping `Image(systemName:)` sized to
  a fixed `13x13` frame, choosing the symbol name and a
  `.symbolRenderingMode(.monochrome).foregroundStyle(tint)` the same way
  `symbolName`/`applyTheme` switch here (SwiftUI's own single-fill monochrome
  mode reproduces the `.sourceAtop` fill trick without hand-rolling it).
  Drive the spin with `.rotationEffect` inside
  `.animation(.linear(duration: 1.1).repeatForever(autoreverses: false))`
  and the pulse with `.opacity` inside
  `.animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true))`,
  and gate both behind `@Environment(\.accessibilityReduceMotion)` — the
  concrete fix for the Reduce Motion gap noted above. Toggle visibility with
  a conditional view rather than `isHidden` so a `Group`/stack containing it
  collapses the same way the AppKit stack does when it is hidden.
- **Compose**: Start from an `Icon` inside a `Modifier.size(13.dp)` box,
  wrapped in `AnimatedVisibility` for the idle-and-not-summarizing hide.
  Drive the spin with `rememberInfiniteTransition` animating
  `Modifier.graphicsLayer { rotationZ = angle }` linearly over 1100ms, and
  the pulse with a second `rememberInfiniteTransition` animating
  `Modifier.alpha` between 1f and 0.25f with a `RepeatMode.Reverse` tween
  over 700ms; read the system's reduced-motion signal
  (`Settings.Global.ANIMATOR_DURATION_SCALE` or the platform's accessibility
  API) before starting either, mirroring the Reduce Motion gap noted above.
  Map the three theme tints to `MaterialTheme.colorScheme` roles (e.g.
  `primary` for accent, `onSurfaceVariant` for tertiary text, `error` or a
  custom warning role for warning).
- **React/Web**: Render the glyph as an inline SVG or icon-font element
  inside a fixed `13px × 13px` box, toggling `display: none` for the
  idle-and-not-summarizing state so the row collapses around it the way the
  AppKit stack does when the view is hidden. Drive the spin with a CSS
  `@keyframes` rule animating `transform: rotate(...)` linearly over 1.1s,
  infinite, and the pulse with a `@keyframes` rule animating `opacity`
  between 1 and 0.25 over 0.7s, alternating, infinite — both wrapped in
  `@media (prefers-reduced-motion: reduce)` guards, the concrete fix for the
  Reduce Motion gap noted above. Use `role="img"` and `aria-label` for the
  four state strings, and re-render the fill color from CSS custom
  properties bound to the active theme rather than hardcoding it.
- **AppKit / UIKit**: Source at
  `packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionListWindow/SessionWatcherActivityIconView.swift`
  (this recipe's source): a macOS-only `NSView` subclass drawing into a
  private `CALayer` sublayer rather than the view's own backing layer,
  specifically to avoid AppKit re-centering the view's own layer's anchor
  point on every frame change (see Design Decisions). A UIKit port replaces
  `NSView`/`NSColor`/`NSImage` with `UIView`/`UIColor`/`UIImage`, uses
  `CALayer` sublayer animation the same way, and must re-derive
  `viewDidMoveToWindow`'s "animations are dropped when leaving a window"
  handling and `viewDidChangeBackingProperties`'s scale handling from
  `traitCollectionDidChange`/`UIScreen.scale`, since this source's window-
  and appearance-observing overrides are AppKit-specific. Substitute
  `UIAccessibility.isReduceMotionEnabled` for the Reduce Motion check this
  source lacks.
- **WinUI 3**: Start from a `FontIcon` (or a small `Viewbox` wrapping a
  `PathIcon`) inside a fixed `Width="13" Height="13"` container, since WinUI
  3 has no single control that both switches glyph *and* spins/pulses
  on demand the way this source's `CALayer` does — `ProgressRing`/`ProgressBar`
  are indeterminate-progress controls, not arbitrary-glyph animators.
  Bind `Visibility` to a converter reproducing
  **hides-when-idle-and-not-summarizing**, and bind the icon's
  `Foreground` `SolidColorBrush` to theme resources matching the three
  tints (e.g. `AccentTextFillColorPrimaryBrush` for accent,
  `TextFillColorTertiaryBrush` for tertiary text, `SystemFillColorCautionBrush`
  for warning). Drive the spin with a `Storyboard` containing a
  `DoubleAnimation` on a `RotateTransform.Angle` from 0 to 360 over
  `Duration="0:0:1.1"` with `RepeatBehavior="Forever"`, and the pulse with a
  `DoubleAnimation` on `Opacity` from 1.0 to 0.25 with `AutoReverse="True"`
  and `RepeatBehavior="Forever"` over `Duration="0:0:0.7"`. Check
  `new Windows.UI.ViewManagement.UISettings().AnimationsEnabled` before
  starting either `Storyboard`, mirroring the Reduce Motion gap noted
  above. Set `AutomationProperties.Name` to the same four state strings this
  source uses, and attach a matching `ToolTipService.ToolTip` for the visual
  tooltip.

## Design Decisions

- **Decision**: The glyph is drawn and animated on a dedicated `CALayer`
  sublayer rather than on the view's own backing layer.
  **Rationale**: AppKit keeps a view's backing layer's frame (and re-centers
  its anchor point to the corner) in step with the view's own frame on every
  change; a rotation installed on that layer therefore orbited the glyph
  down over the output line beneath it instead of spinning in place. AppKit
  never touches a sublayer's geometry, so a spin installed on the dedicated
  `glyph` sublayer keeps its centered anchor and spins in place.
  **Approved: pending**
- **Decision**: Idle sessions with no summarization in progress hide the
  view entirely (`isHidden = true`) instead of showing a quiet resting dot
  or other neutral glyph.
  **Rationale**: Idle is the state a session row is in most of the time, so
  marking every idle row would make the marks say nothing and compete with
  the two states actually worth noticing (working, waiting); an empty slot
  accurately renders "nothing is happening" and makes any visible glyph in
  the list mean something. Summarizing overrides this even while idle,
  because the sparkles glyph reports work happening *about* the session,
  which a blank slot would deny.
  **Approved: pending**
- **Decision**: Recoloring draws the raw symbol image and then fills the
  tint color over it with `.sourceAtop` compositing, instead of using
  `NSImage.SymbolConfiguration`'s own color options.
  **Rationale**: A palette-based symbol color configuration paints every
  layer of a multi-layer symbol the same single color; for
  `exclamationmark.circle.fill` that would erase the exclamation mark into
  its own circle. Filling over the rendered raster preserves the visual
  distinction between the symbol's layers.
  **Approved: pending**
- **Decision**: CoreAnimation (`CABasicAnimation`) drives the spin and pulse
  rather than a newer SF Symbol content-transition/variable-rotation
  effect.
  **Rationale**: The SF Symbol `.rotate` content-transition effect requires
  macOS 15, and this framework ships to macOS 14; CoreAnimation is the
  compatible substitute available on the framework's minimum deployment
  target.
  **Approved: pending**
- **Decision**: `update(activity:isSummarizing:)` returns immediately,
  performing no redraw or animation change, when neither argument differs
  from the view's current stored values.
  **Rationale**: A session's activity is re-supplied on every poll of the
  session list, including polls where nothing actually changed. Without
  this guard, a running "working" spin restarted from its initial angle on
  every poll and visibly stuttered instead of spinning continuously;
  returning early for an unchanged value is what keeps it smooth.
  **Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | ui-tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [meaningful-labels](agenticdevelopercookbook://compliance/accessibility#meaningful-labels) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | needs-review | accessibility |
| [reduce-motion-support](agenticdevelopercookbook://compliance/accessibility#reduce-motion-support) | needs-review | accessibility |
| [live-region-announcements](agenticdevelopercookbook://compliance/accessibility#live-region-announcements) | needs-review | accessibility |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
