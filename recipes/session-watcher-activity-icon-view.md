---
id: 1cecd319-1cc2-40a5-8ef0-56267eb78b89
title: SessionWatcherActivityIconView
domain: agentictoolkit://recipes/session-watcher-activity-icon-view
type: ingredient
version: 1.1.1
status: review
language: en
created: 2026-09-23
modified: '2026-09-24'
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
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
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
- **horizontal-compression-resistance**: The component MUST set a required
  horizontal content-compression-resistance priority on itself
  (`setContentCompressionResistancePriority(.required, for: .horizontal)`).
- **state-based-symbol-selection**: The component MUST use the `sparkles` SF
  Symbol whenever `isSummarizing` is `true`, regardless of `activity`; and
  otherwise MUST use `arrow.triangle.2.circlepath` for `activity == .working`,
  `circle.fill` for `activity == .idle`, and `exclamationmark.circle.fill`
  for `activity == .waiting`.
- **idle-visibility-suppression**: The component MUST set
  `isHidden = true` only when `activity == .idle` and `isSummarizing ==
  false`, and MUST be visible (`isHidden = false`) for every other
  combination of `activity` and `isSummarizing`. This is the same
  condition under which **state-based-symbol-selection** selects
  `circle.fill`, **state-based-tint** selects the tertiary text color, and
  **state-based-label-and-tooltip** selects `"Idle"`; because the view is
  hidden whenever that combination holds, none of those three idle values
  is ever seen or announced by a user — they exist only so the glyph
  layer and accessibility state are well-defined (and inspectable in
  tests) while hidden, not because anyone perceives them.
- **state-based-tint**: The component MUST tint the glyph with the active
  theme's accent color when `isSummarizing` is `true` or `activity ==
  .working`, with the theme's tertiary text color when `activity == .idle`
  and `isSummarizing` is `false`, and with the theme's warning color when
  `activity == .waiting` and `isSummarizing` is `false`.
- **pre-theme-tint-default**: The component MUST use
  `NSColor.tertiaryLabelColor` as the glyph's tint until `applyTheme(_:)` is
  called for the first time.
- **symbol-layer-distinction**: When recoloring a multi-layer SF Symbol (for
  example `exclamationmark.circle.fill`), the component MUST keep the
  symbol's layers visually distinct from one another after tinting — the
  exclamation mark MUST stay visually distinct from its enclosing circle,
  rather than the tint collapsing every layer into a single flat-colored
  silhouette. See the AppKit / UIKit Platform Notes bullet and Design
  Decisions for the mechanism this source uses to satisfy it.
- **unresolvable-symbol-fallback**: The component MUST set the
  glyph layer's `contents` to `nil` when `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for the currently selected symbol name.
- **in-place-state-update**: The component MUST update an existing instance's
  displayed state through `update(activity:isSummarizing:)` rather than
  requiring callers to construct a new instance for a state change.
- **redundant-update-guard**: The component MUST return from
  `update(activity:isSummarizing:)` without redrawing, re-describing
  accessibility, or touching any animation when neither `activity` nor
  `isSummarizing` differs from the view's current values.
- **animation-restart-on-change**: The component MUST stop any running
  glyph animation and, only if it is currently in a window, start the
  animation appropriate to the new state, whenever
  `update(activity:isSummarizing:)` is called with a value that actually
  changes `activity` or `isSummarizing`.
- **waiting-or-summarizing-pulse**: The component MUST animate the
  glyph layer's opacity from `1.0` to `0.25` and back (autoreversing) over
  0.7 seconds, repeating indefinitely, whenever `isSummarizing` is `true` or
  `activity == .waiting`.
- **working-state-spin**: The component MUST rotate the glyph layer one full
  turn clockwise on screen (`transform.rotation.z` from `0` to `-2π`) over
  1.1 seconds with a linear timing function, repeating indefinitely, when
  `activity == .working` and `isSummarizing == false`.
- **animation-install-idempotence**: The component MUST NOT add a new
  pulse or rotation animation for a key that already has an animation
  installed on the glyph layer.
- **off-window-animation-removal**: The component MUST remove both the
  rotation and the pulse animation from the glyph layer when the view moves
  to a `nil` window.
- **window-attach-animation-reinstall**: The component MUST re-render
  the glyph and start its state-appropriate animation whenever the view
  moves into a non-`nil` window.
- **appearance-change-rerender**: The component MUST re-render the glyph
  whenever the view's effective appearance changes, so that a dynamic tint
  color resolves against the new appearance.
- **display-scale-rerender**: The component MUST keep the rasterized glyph
  matching the display's current pixel density, re-rendering whenever that
  density changes, defaulting to a 2x density when it cannot otherwise be
  determined. See the AppKit / UIKit Platform Notes bullet for the API this
  source uses to read and react to that density.
- **glyph-bounds-layout**: The component MUST keep the glyph
  sublayer's `bounds` equal to the view's own `bounds` and its `position`
  centered in the view on every layout pass, with no animated transition
  for that resize/reposition. See the AppKit / UIKit Platform Notes bullet
  for the mechanism (disabling implicit layer actions) this source uses to
  suppress that animation.
- **image-accessibility-role**: The component MUST expose itself to
  assistive technology as an accessibility element with the `.image` role.
- **state-based-label-and-tooltip**: The component MUST set both its
  accessibility label and its `toolTip` to `"Working"`, `"Idle"`, `"Waiting
  for you"`, or `"Summarizing"`, selected by the exact same `isSummarizing`/
  `activity` logic as **state-based-symbol-selection**.
- **state-based-accessibility-identifier**: The component MUST set its accessibility
  identifier to `session-panel.activity.summarizing` when `isSummarizing` is
  `true`, or to `session-panel.activity.working` / `session-panel.activity.idle`
  / `session-panel.activity.waiting` otherwise, matching `activity`.
- **programmatic-construction-only**: The component MUST only be
  constructible through its programmatic initializer; it MUST NOT support
  instantiation from a serialized archive (for example, an Interface
  Builder storyboard or nib). See the AppKit / UIKit Platform Notes bullet
  for the API this source uses to enforce that.

## Appearance

- **Corner radius**: None — neither the view's own layer nor the glyph
  sublayer sets a `cornerRadius`.
- **Padding**: None — the glyph layer fills the view's bounds exactly (see
  **glyph-bounds-layout**); there is no internal inset.
- **Font**: Not applicable in the text sense — the component renders an SF
  Symbol image, not text. The symbol is rasterized at `NSImage.SymbolConfiguration(pointSize:
  11, weight: .semibold)`.
- **Background**: None/transparent — the view has `wantsLayer = true` but no
  `backgroundColor` is set on either its own layer or the glyph sublayer.
- **Foreground/Text**: The glyph's tint — the active theme's accent,
  tertiary-text, or warning color (see **state-based-tint**), or
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
| Waiting, not summarizing (`activity: .waiting, isSummarizing: false`) | Visible; `exclamationmark.circle.fill` tinted with the theme's warning color; opacity pulses 1.0→0.25 and back, 0.7s each way (1.4s full cycle), indefinitely. |
| Summarizing (`isSummarizing: true`, any `activity`) | Visible; `sparkles` tinted with the theme's accent color; opacity pulses 1.0→0.25 and back, 0.7s each way (1.4s full cycle), indefinitely — the same pulse as Waiting, regardless of the underlying `activity`. |
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
  `"Summarizing"` (see **state-based-label-and-tooltip**) every time the
  state is established (`init`) or actually changed (`update`), so the
  label never describes a stale state. The same text is mirrored into
  `toolTip`.
- **Announce state changes**: `describeState()` reassigns the accessibility
  label, `toolTip`, and accessibility identifier whenever `activity` or
  `isSummarizing` actually changes, but no
  `NSAccessibility.post(element:notification:)` call (e.g. `.titleChanged` or
  `.valueChanged`) accompanies that reassignment anywhere in the source — the
  change reaches VoiceOver only through AppKit's own default handling of a
  reassigned accessibility label, never through an explicit posted
  notification.
- **Minimum tap target**: Not applicable in the iOS/touch sense — this is a
  macOS, pointer-driven `NSView` with no target/action, gesture recognizer,
  or click handling of any kind in the source; Apple's 44×44pt minimum
  applies to touch targets, not to a static AppKit image view.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The glyph's tint (theme accent/tertiary-text/warning color, or the `tertiaryLabelColor` system fallback) is rasterized as an opaque fill over whatever background sits behind this 13×13pt view — a session row in a list — with no contrast check against that background anywhere in this file; settling it needs a contrast audit of each tint against the session row background across the app's shipped themes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| activity-icon-001 | fixed-glyph-size | Any constructed instance | Both `widthAnchor` and `heightAnchor` resolve to exactly 13pt |
| activity-icon-002 | horizontal-compression-resistance | Any constructed instance, placed in a horizontally-constrained stack view | The view's horizontal content-compression-resistance priority reads `.required`; it does not shrink below 13pt |
| activity-icon-003 | state-based-symbol-selection | `init(activity: .working, isSummarizing: true)` | The glyph is drawn from the `sparkles` symbol, not `arrow.triangle.2.circlepath` |
| activity-icon-003b | state-based-symbol-selection | `init(activity: .waiting, isSummarizing: false)` | The glyph is drawn from `exclamationmark.circle.fill` |
| activity-icon-003c | state-based-symbol-selection | `init(activity: .idle, isSummarizing: false)` | The glyph is drawn from `circle.fill` |
| activity-icon-003d | state-based-symbol-selection | `init(activity: .working, isSummarizing: false)` | The glyph is drawn from `arrow.triangle.2.circlepath` |
| activity-icon-004 | idle-visibility-suppression | `init(activity: .idle, isSummarizing: false)` | `isHidden == true` |
| activity-icon-004b | idle-visibility-suppression | `init(activity: .idle, isSummarizing: true)` | `isHidden == false` |
| activity-icon-005 | state-based-tint | `applyTheme(palette)` with `activity == .waiting, isSummarizing == false` | The glyph is filled with `palette.warningColor` |
| activity-icon-005b | state-based-tint | `applyTheme(palette)` with `activity == .idle, isSummarizing == false` | The glyph is filled with `palette.tertiaryTextColor` |
| activity-icon-005c | state-based-tint | `applyTheme(palette)` with `activity == .working, isSummarizing == false` | The glyph is filled with `palette.accentColor` |
| activity-icon-005d | state-based-tint | `applyTheme(palette)` with `isSummarizing == true` (any `activity`) | The glyph is filled with `palette.accentColor` |
| activity-icon-006 | pre-theme-tint-default | Newly constructed instance, `applyTheme` never called | The glyph is filled with `NSColor.tertiaryLabelColor` |
| activity-icon-007 | symbol-layer-distinction | `applyTheme(palette)` with `activity == .waiting` | Sampling the rendered raster at the glyph's center (the exclamation mark) yields a pixel outside the fill's solid color (e.g. transparent or antialiased against the surrounding fill), distinct from a sample taken on the surrounding ring — the tint did not collapse both layers into one flat silhouette |
| activity-icon-008 | unresolvable-symbol-fallback | The global/class-level `NSImage(systemSymbolName:accessibilityDescription:)` lookup intercepted (e.g. via method swizzling or an equivalent test double substituted for the system symbol lookup, since the source exposes no injectable seam for it) to return `nil` for the selected symbol name | `glyph.contents == nil` |
| activity-icon-009 | in-place-state-update | Existing instance, `update(activity: .waiting, isSummarizing: false)` called | The same instance now renders the waiting glyph; no new instance was created |
| activity-icon-010 | redundant-update-guard | Existing instance at `activity: .working, isSummarizing: false`, then `update(activity: .working, isSummarizing: false)` | No re-render, no `describeState()` call, and the running spin animation is left untouched (does not restart) |
| activity-icon-011 | animation-restart-on-change | Existing instance in a window at `activity: .idle, isSummarizing: false` (hidden), then `update(activity: .working, isSummarizing: false)` | `isHidden` becomes `false`; a new `rotationKey` animation is installed |
| activity-icon-012 | waiting-or-summarizing-pulse | Instance in a window, `update(activity: .waiting, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-pulse")` is non-nil, opacity animates 1.0→0.25→1.0, 0.7s each way (1.4s full cycle), repeating |
| activity-icon-012b | waiting-or-summarizing-pulse | Instance in a window, `update(activity: .idle, isSummarizing: true)` | `glyph.animation(forKey: "session-activity-pulse")` is non-nil (the pulse fires for the summarizing-and-idle combination the same as any other summarizing case) |
| activity-icon-013 | working-state-spin | Instance in a window, `update(activity: .working, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-rotation")` is non-nil, `transform.rotation.z` animates 0→−2π over 1.1s linear, repeating |
| activity-icon-014 | animation-install-idempotence | Instance already spinning (`working`), `startAnimation()` invoked again without an intervening `stopAnimation()` | `glyph.animation(forKey: "session-activity-rotation")` is unchanged (no duplicate animation added) |
| activity-icon-015 | off-window-animation-removal | Instance in a window and spinning (`working`), then removed from its superview (`window == nil`) | `glyph.animation(forKey: "session-activity-rotation")` becomes `nil` |
| activity-icon-016 | window-attach-animation-reinstall | Freshly constructed `activity: .working` instance, not yet in any window, then added to a window | The glyph re-renders and `glyph.animation(forKey: "session-activity-rotation")` becomes non-nil |
| activity-icon-017 | appearance-change-rerender | Instance on screen, `viewDidChangeEffectiveAppearance()` invoked (e.g. system switches light/dark) | `glyph.contents` is regenerated with a fill color equal to `tint.resolvedColor(in: newAppearance)`, not the color that had been resolved against the previous appearance |
| activity-icon-018 | display-scale-rerender | Instance moved to a window with a different `backingScaleFactor`, `viewDidChangeBackingProperties()` invoked | `glyph.contentsScale` matches the new window's `backingScaleFactor` |
| activity-icon-019 | glyph-bounds-layout | View resized, `layout()` invoked | `glyph.bounds == view.bounds`; `glyph.position == (bounds.midX, bounds.midY)`; no implicit layer animation plays for the change |
| activity-icon-020 | image-accessibility-role | Any constructed instance | `accessibilityRole() == .image`; `isAccessibilityElement() == true` |
| activity-icon-021 | state-based-label-and-tooltip | `init(activity: .waiting, isSummarizing: false)` | Accessibility label and `toolTip` both read `"Waiting for you"` |
| activity-icon-021b | state-based-label-and-tooltip | `init(activity: .working, isSummarizing: true)` | Accessibility label and `toolTip` both read `"Summarizing"` (summarizing overrides activity) |
| activity-icon-022 | state-based-accessibility-identifier | `init(activity: .idle, isSummarizing: false)` | `accessibilityIdentifier() == "session-panel.activity.idle"` |
| activity-icon-022b | state-based-accessibility-identifier | `init(activity: .idle, isSummarizing: true)` | `accessibilityIdentifier() == "session-panel.activity.summarizing"` |
| activity-icon-023 | programmatic-construction-only | `SessionWatcherActivityIconView(coder:)` invoked (e.g. nib/storyboard unarchiving) | Process traps with a fatal error |

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
  crash (MUST, per **unresolvable-symbol-fallback**). All four
  symbol names the source actually selects (`sparkles`,
  `arrow.triangle.2.circlepath`, `circle.fill`,
  `exclamationmark.circle.fill`) are real system symbols, so this path is
  unreached in normal operation but is still defined, source-observed
  behavior.
- **`update` called with a real change while off-window**: `stopAnimation()`
  still runs, but `startAnimation()` is gated on `window != nil`, so the new
  animation does not begin until the view is later added to a window
  (`viewDidMoveToWindow` re-renders and starts it then) (MUST, per
  **animation-restart-on-change** and
  **window-attach-animation-reinstall**).
- **Rapid repeated `update` calls with unchanged values**: Each call is a
  no-op past the initial equality guard — no redraw, no
  `describeState()`, no animation churn — which is what keeps a
  continuously-polled "working" spin visually smooth rather than restarting
  from zero on every poll (MUST, per **redundant-update-guard**).

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

The source performs no such lookup, so all four reach VoiceOver and the
tooltip in English only.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not handled: the rotation (`working`'s spin) and the opacity pulse (`waiting`/summarizing) both repeat indefinitely (`repeatCount = .greatestFiniteMagnitude`), and no code in this file checks `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (or any other Reduce Motion signal) before starting either, nor is a static substitute offered for either animated state. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`); the tint always comes from the active `SemanticPalette` (or the `NSColor.tertiaryLabelColor` system fallback before the first theme apply), so whether the resulting contrast is adequate is tracked once under the open question on minimum-contrast-ratio above, not duplicated here. |
| Differentiate Without Color | Supported: each state's SF Symbol shape (`arrow.triangle.2.circlepath`, `circle.fill`, `exclamationmark.circle.fill`, `sparkles`) differs from every other state's shape independently of the tint color `applyTheme` assigns (see **state-based-symbol-selection** and **state-based-tint**), so state is never conveyed by color alone. |

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
  between 1 and 0.25 over 0.7s per direction (`animation-duration: 0.7s` with
  `alternate`, so a full up-and-back cycle is 1.4s), infinite — both wrapped in
  `@media (prefers-reduced-motion: reduce)` guards, the concrete fix for the
  Reduce Motion gap noted above. Use `role="img"` and `aria-label` for the
  four state strings, and re-render the fill color from CSS custom
  properties bound to the active theme rather than hardcoding it.
- **AppKit / UIKit**: Source at
  `packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionListWindow/SessionWatcherActivityIconView.swift`
  (this recipe's source): a macOS-only `NSView` subclass drawing into a
  private `CALayer` sublayer rather than the view's own backing layer,
  specifically to avoid AppKit re-centering the view's own layer's anchor
  point on every frame change (see Design Decisions). It satisfies
  **symbol-layer-distinction** by drawing the raw SF Symbol image and then
  filling the tint color over it with `.sourceAtop` compositing (see Design
  Decisions), rather than an `NSImage.SymbolConfiguration` color option; it
  satisfies **glyph-bounds-layout** by wrapping each layout pass's
  `bounds`/`position` assignment in a `CATransaction` with
  `setDisableActions(true)`, so no implicit layer animation plays for the
  resize/reposition; it satisfies **display-scale-rerender** by reading
  `backingScaleFactor` from the view's window, falling back to
  `NSScreen.main`, falling back to `2`; and it satisfies
  **programmatic-construction-only** by marking `init?(coder:)`
  `@available(*, unavailable)` and having it `fatalError()`. A UIKit port
  replaces `NSView`/`NSColor`/`NSImage` with `UIView`/`UIColor`/`UIImage`,
  uses `CALayer` sublayer animation the same way, and must re-derive
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
  **idle-visibility-suppression**, and bind the icon's
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
  **Rationale**: Per the source's own doc comment on `renderGlyph()`
  (`SessionWatcherActivityIconView.swift`), a palette-based symbol color
  configuration paints every layer of a multi-layer symbol the same single
  color; for `exclamationmark.circle.fill` that would erase the exclamation
  mark into its own circle. Filling over the rendered raster preserves the
  visual distinction between the symbol's layers. This file does not record
  which specific `NSImage.SymbolConfiguration` color option was tried before
  landing on the fill approach — only the source's own stated reason for
  rejecting that family of API.
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
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | failed | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |

`screen-reader-support` is `passed` because `describeState()` unconditionally
sets a meaningful accessibility label for every state (see
**state-based-label-and-tooltip**). `contrast-ratio` is `partial` because
the tint's contrast against a session row's background cannot be computed
from this file alone (see the open question on minimum-contrast-ratio).
`reduced-motion` is `failed` because no code path here checks a Reduce
Motion signal before starting the spin or pulse animation (see
Accessibility Options → Reduce Motion). `no-hardcoded-strings` is `failed`
because the four accessibility label/tooltip strings are plain `String`
literals with no localization key (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated four AppKit-mechanism MUSTs as observable outcomes and moved their mechanisms into the AppKit/UIKit Platform Notes bullet and Design Decisions; simplified the working-state-spin guard condition; noted that the idle symbol/tint/label are never seen or announced while the view is hidden; documented the missing symbol-provider seam for the unresolvable-symbol test vector instead of inventing one; renamed every requirement to a subject-noun name and updated all cross-references; moved the internal cookbook reference from `references` to `related`; corrected the pulse's per-direction/full-cycle timing; added test vectors for the working/summarizing tint, idle symbol, and summarizing-while-idle pulse; made the two flagged vectors mechanically checkable; grounded the `.sourceAtop` rationale in the source's own doc comment; unquoted the frontmatter dates; and rebuilt the Compliance table to cite only checks that exist in the catalog with rulings-consistent statuses. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
