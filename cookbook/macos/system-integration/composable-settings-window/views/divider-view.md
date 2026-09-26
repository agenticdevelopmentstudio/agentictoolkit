---
id: 18ad68ea-187b-463d-9f5c-b855b9bc36a9
title: Divider View
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/divider-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A fixed-height, layer-backed AppKit divider line for ComposableSettingsWindow,
  colored from the theme's dividerColor and kept live on every repaint.
platforms:
- swift
- macos
tags:
- ui
- divider
- macos
- settings
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/button-view
references: []
approved-by: ''
approved-date: ''
---

# Divider View

## Overview

`ComposableSettings.DividerView`, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DividerView.swift`, is a fixed-height, theme-colored hairline separator for the ComposableSettingsWindow system integration. It is an AppKit `NSView` nested in the `ComposableSettings` namespace, conforms to `SettingsViewProtocol` (the marker protocol every settings-row view in this system adopts, alongside its sibling `ButtonView`), and draws a single divider line wherever a settings panel places it. It has no caller-configurable options: its only public initializer is a parameterless `convenience init()`, its height is fixed to `SettingsLayout.default[.dividerThickness]`, and its color always tracks the current theme's `dividerColor` through a `ThemePaletteObserver` plus a redundant `updateLayer()` override.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on itself.
- **enables-layer-backing**: The component MUST set `wantsLayer = true` so it can be colored via its backing layer.
- **constrains-height-to-divider-thickness**: The component MUST activate a height constraint equal to `SettingsLayout.default[.dividerThickness]` (1.0pt, per `ViewLayout.swift`'s `SettingsLayout.default` values) at initialization.
- **ignores-explicit-frame**: Constructing a `DividerView` via `init(frame frameRect: NSRect)` MUST yield a view whose `frame` is `.zero` immediately after initialization, regardless of the `frameRect` argument's value; the caller-supplied rect has no effect on the constructed view.
- **convenience-init-uses-zero-frame**: The public `convenience init()` MUST call `self.init(frame: .zero)`.
- **applies-divider-color-on-init**: The component MUST set `layer?.backgroundColor` to the resolved palette's `dividerColor.cgColor` immediately upon construction, via `ThemePaletteObserver`'s synchronous initial apply.
- **resolves-color-through-nearest-theme-scope**: Whenever the component applies its divider color (on initialization, on a theme change, on its own scope's change, or during `updateLayer()`), it MUST resolve the color from `resolvedThemeScope.palette.dividerColor`, where `resolvedThemeScope` walks the view's superview chain to the nearest `ThemeScopeProviding` ancestor and falls back to `ThemeScope.app` when none exists.
- **reapplies-divider-color-on-theme-change**: The component MUST reapply `layer?.backgroundColor` from the resolved palette's `dividerColor` whenever `ThemeManager` posts `didChangeNotification`.
- **reapplies-divider-color-on-own-scope-change**: The component MUST reapply `layer?.backgroundColor` from the resolved palette's `dividerColor` when `ThemeScope` posts `didChangeNotification` for the component's own resolved scope.
- **ignores-other-scope-change-notifications**: The component MUST NOT reapply its divider color when `ThemeScope` posts `didChangeNotification` for a scope other than the component's own resolved scope.
- **retains-theme-observer-for-view-lifetime**: The component's theme-change and scope-change repaint subscriptions MUST remain active for as long as the view exists, with no separate reference to an observer required from the caller.
- **reapplies-divider-color-on-layer-update**: The component MAY reapply `layer?.backgroundColor` from `resolvedThemeScope.palette.dividerColor` whenever AppKit invokes `updateLayer()`; the source does this on every call, redundantly overlapping the notification-driven repaint paths above (see Design Decisions).
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST trap via `fatalError` rather than return a usable instance; the source's trap message is `init(coder:) has not been implemented`.
- **conforms-to-settings-view-protocol**: The component MUST conform to `SettingsViewProtocol`.
- **ignores-settings-layout-changes**: The component's height constraint MUST NOT update after initialization if `SettingsLayout.default[.dividerThickness]` changes later; the constraint's constant is fixed to the value read once at `init` time.

## Appearance

- **Corner radius**: None; the source never sets `layer?.cornerRadius`.
- **Padding**: Not set by `DividerView` itself; it has no internal content to pad. The space around the line is entirely up to whatever container lays it out — no padding-related code appears in this file.
- **Font**: Not applicable — `DividerView` renders no text or other font-dependent content.
- **Background**: `layer?.backgroundColor` is set to `palette.dividerColor.cgColor`, where `palette` is `resolvedThemeScope.palette` (a `SemanticPalette`) and `dividerColor` maps to the palette's `.divider` `ThemeRole` (`nsColor(.divider)` in `SemanticPalette+NSColor.swift`). This is reapplied on initialization, on every theme change, on the view's own scope change, and on every `updateLayer()` call.
- **Foreground/Text**: Not applicable — `DividerView` has no text or foreground content; its layer's background fill is its only visual surface.
- **Border**: None; the source never sets `layer?.borderWidth` or `layer?.borderColor`.
- **Shadow**: None; the source never sets `layer?.shadowOpacity`, `shadowColor`, `shadowOffset`, or `shadowRadius`.
- **Min/Max size**: Height fixed at 1.0pt (`SettingsLayout.default[.dividerThickness]`) via an activated `NSLayoutConstraint`; no width constraint of its own — width is determined entirely by whatever Auto Layout constraints the container applies (none appear in this file).

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as a solid-fill layer, 1.0pt tall, colored `resolvedThemeScope.palette.dividerColor`; there is no other state. |
| Pressed | Not applicable: `DividerView` sets no target/action, gesture recognizer, or tracking area — it cannot receive or respond to a press. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `DividerView` has no enabled/disabled concept. |
| Focused | Not applicable: `DividerView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `DividerView` performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — `DividerView` is a purely decorative separator; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override, so it exposes nothing distinguishable to VoiceOver beyond the visual boundary it draws.
- **Accessibility exposure**: Not exposed — `DividerView` (DividerView.swift) is a plain `NSView` that never overrides `isAccessibilityElement`, and a plain `NSView` is not an accessibility element by default, so VoiceOver skips the decorative hairline.
- **Label requirements**: Not applicable — `DividerView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `DividerView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `DividerView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| divider-view-001 | confines-to-main-actor | Attempt to construct or mutate a `DividerView` from off the main actor | Static/compile-time check, not executable at runtime: the compiler rejects the call under Swift's `@MainActor` isolation checking |
| divider-view-002 | disables-autoresizing-mask-translation | Any initialized `DividerView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| divider-view-003 | enables-layer-backing | Any initialized `DividerView` | `view.wantsLayer == true` and `view.layer` is non-nil |
| divider-view-004 | constrains-height-to-divider-thickness | Any initialized `DividerView`, laid out in a window | The view's active height constraint resolves to `1.0` (`SettingsLayout.default[.dividerThickness]`) |
| divider-view-005 | ignores-explicit-frame | Construct via `DividerView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init` returns |
| divider-view-006 | convenience-init-uses-zero-frame | Construct via `DividerView()` | `view.frame == .zero`, the height constraint's constant equals `1.0`, and `view.wantsLayer == true` |
| divider-view-007 | applies-divider-color-on-init | Construct a `DividerView` while a known palette is active, before adding it to any window | `view.layer?.backgroundColor == palette.dividerColor.cgColor` immediately after `init` returns |
| divider-view-008 | resolves-color-through-nearest-theme-scope | Add a `DividerView` as a descendant of a view conforming to `ThemeScopeProviding` whose scope's palette differs from `ThemeScope.app`'s | The divider's applied color matches the ancestor scope's `palette.dividerColor`, not `ThemeScope.app`'s |
| divider-view-009 | reapplies-divider-color-on-theme-change | Construct a `DividerView`, switch the active theme, then post `ThemeManager.didChangeNotification` | `view.layer?.backgroundColor` updates to the new theme's `dividerColor` |
| divider-view-010 | reapplies-divider-color-on-own-scope-change | Construct a `DividerView` resolved to scope A; change scope A's underlying theme/palette to one whose `dividerColor` differs from its previous value, then post `ThemeScope.didChangeNotification` with `object` set to scope A | `view.layer?.backgroundColor` updates to scope A's new `dividerColor` |
| divider-view-011 | ignores-other-scope-change-notifications | Construct a `DividerView` resolved to scope A; post `ThemeScope.didChangeNotification` with `object` set to a different scope B | `view.layer?.backgroundColor` does not change |
| divider-view-012 | retains-theme-observer-for-view-lifetime | Construct a `DividerView`, keep only the view (no separate reference to any observer), then post `ThemeManager.didChangeNotification` | `view.layer?.backgroundColor` still updates, showing the observer's subscriptions survived |
| divider-view-013 | reapplies-divider-color-on-layer-update | Construct a `DividerView`, swap the ancestor scope's theme/palette to a different `dividerColor` without posting any notification, then invoke `updateLayer()` directly (e.g. via `setNeedsDisplay` + a display pass, or a direct call) | `view.layer?.backgroundColor` matches the new `dividerColor` after `updateLayer()` runs |
| divider-view-014 | rejects-coder-initializer | Construct via `DividerView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| divider-view-015 | conforms-to-settings-view-protocol | Any initialized `DividerView` | `view is SettingsViewProtocol` is `true` |
| divider-view-016 | ignores-settings-layout-changes | Construct a `DividerView`, add it to a window, then mutate `SettingsLayout.default`'s `.dividerThickness` value | The view's existing height constraint constant remains unchanged at the value read during `init`; it does not update to the new value |

## Edge Cases

- **Null/empty input**: Not applicable — `DividerView`'s only public initializer, `convenience init()`, takes no parameters; the inherited `init(frame:)` parameter is accepted but discarded (see **ignores-explicit-frame**), so there is no caller-supplied value to be null or empty.
- **Boundary values**: `SettingsLayout.default[.dividerThickness]` (1.0pt) is read exactly once, into an activated `NSLayoutConstraint`, at `init` time. `SettingsLayout` is `Observable`/`@Published`, but `DividerView` never subscribes to it, so if a caller mutates `SettingsLayout.default`'s underlying value after a `DividerView` already exists, that instance's height constraint does not update — it stays at whatever `.dividerThickness` was when it was constructed (see **ignores-settings-layout-changes**). This staleness is a genuine, source-grounded limitation, also recorded in Design Decisions.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and all four color-repaint paths are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `DividerView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `DividerView` performs no networking.
- **No `ThemeManager` available**: `ThemeScope.palette` (which every repaint path reads through, directly or via `ThemePaletteObserver`) falls back to `SemanticPalette(theme: BuiltInThemes.solarizedDark)` when `ThemeManager.shared` is `nil` (e.g. a preview or a unit test with no app host) — `DividerView` paints with that fallback's divider color rather than crashing or leaving its layer transparent.
- **No `ThemeScopeProviding` ancestor**: `resolvedThemeScope`'s superview walk finds no ancestor declaring a scope and falls back to `ThemeScope.app`, so `DividerView` paints with the app-wide palette rather than failing to resolve a color.

## Configuration

Not applicable: `DividerView` exposes no caller-configurable options. Its only public initializer is the parameterless `convenience init()`; `init(frame:)` accepts but discards its argument (see **ignores-explicit-frame**), and `init?(coder:)` fatal-errors unconditionally.

## Deep Linking

Not applicable: `DividerView` is a decorative layout element with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

Not applicable: `DividerView` renders no text and defines no string keys of its own.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `DividerView` applies no animation, transition, or motion effect of its own; each of its four repaint paths (init, theme change, scope change, `updateLayer()`) assigns `layer?.backgroundColor` directly, with no animator proxy or `CATransaction` animation wrapping it. |
| Increase Contrast | Not applicable: `DividerView` sets no custom Increase Contrast handling of its own; the color it paints comes entirely from `palette.dividerColor`, and any Increase Contrast adaptation is the `SemanticPalette`/`ThemeManager`'s responsibility, not something this file could opt into or out of. |
| Differentiate Without Color | Not applicable: `DividerView` conveys no state or meaning through color — it renders exactly one visual presentation, a colored hairline, with no color-coded distinction for an alternate cue to replace. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `DividerView` always constructs and applies its layer color unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry calls, and `DividerView` has no user interaction to report.

## Privacy

- **Data collected**: None. `DividerView`'s only stored property is `themeObserver`, an internal `ThemePaletteObserver` instance; it holds no caller-supplied data at all.
- **Storage**: Not applicable — `DividerView` performs no persistence of any kind.
- **Transmission**: Not applicable — `DividerView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print`).

## Platform Notes

- **SwiftUI**: `Divider()` is the built-in equivalent for the common case, but it paints the system separator color rather than a theme-supplied one. To match this source's per-theme `dividerColor`, use a `Rectangle().fill(...).frame(height: 1)` sized from the equivalent of `SettingsLayout.default[.dividerThickness]`, reading the fill color from the app's own palette environment value (SwiftUI's `@Environment` mechanism is the natural analog of this source's superview-walking `resolvedThemeScope`) so the color updates automatically when that environment value changes, with no manual notification subscription needed.
- **Compose**: Use `HorizontalDivider()` — Material 3's replacement for the deprecated `Divider()` — (or a plain `Box(Modifier.height(1.dp).fillMaxWidth().background(...))` for full control over the fixed thickness) reading its color from a `CompositionLocal` exposing the current palette. Compose's own recomposition on `CompositionLocal` change is the equivalent of this source's four manual repaint paths (init, theme change, scope change, `updateLayer()`) — no observer object or notification bookkeeping is needed.
- **React/Web**: An `<hr>` styled with `border: none; height: 1px; background-color: var(--divider-color);` (or a plain `<div>` of the same height), where `--divider-color` is set by whatever theme-provider component wraps the tree. A CSS custom property's cascade already repaints on a theme-class change with no JS callback required, standing in for both the notification-driven repaint and the `updateLayer()` override in the source.
- **AppKit / UIKit (source)**: `DividerView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DividerView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is a layer-backed `NSView` whose only content is a solid-fill `CALayer.backgroundColor`, sized by one Auto Layout height constraint and never given a width constraint of its own, repainted through `ThemePaletteObserver` plus a redundant `updateLayer()` override, and blocked from `NSCoder` construction entirely. A UIKit port to `UIView`/`CALayer` would use `UIView.layer` directly (always present, unlike `NSView.layer?`) and needs no Dynamic Type accommodation, since a divider has no text.
- **WinUI 3**: Use a `Rectangle` (or a `Border` with only a bottom `BorderThickness`) with `Height="1"` bound to the equivalent of `SettingsLayout.Default[LayoutKey.DividerThickness]`, and `Fill`/`BorderBrush` bound to a `SolidColorBrush` `ThemeResource` keyed to the app's current theme's divider color — either adopting Fluent 2's own `DividerStrokeColorDefaultBrush` token, or a custom resource mirroring `palette.dividerColor` if the port keeps its own palette abstraction. Repaint on theme change by handling `FrameworkElement.ActualThemeChanged` (WinUI's per-element equivalent of `ThemeManager.didChangeNotification`) rather than a global notification; there is no WinUI analog to the source's `updateLayer()` override, since a `ThemeResource` brush lookup already re-resolves automatically when the active theme or resource dictionary changes, so that second repaint path can be dropped as redundant in the port.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DividerView.swift` |

## Design Decisions

**Decision**: `init(frame frameRect: NSRect)` discards its `frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: `DividerView` positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated height constraint). The inherited frame-based initializer exists only so `DividerView` can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward.
**Approved**: pending

**Decision**: The divider color is applied through two independent paths — once via `ThemePaletteObserver`'s notification-driven callback, and again via an `updateLayer()` override that re-reads `resolvedThemeScope.palette.dividerColor` on every AppKit-triggered layer update.
**Rationale**: Not explained in source comments; there are none on this override. The two paths are not mutually exclusive — `updateLayer()` covers any AppKit-invoked layer refresh that does not route through either of `ThemePaletteObserver`'s two notifications, at the cost of reassigning `backgroundColor` a second time on paths that do overlap (e.g. a theme change that also triggers `updateLayer()`). This redundancy is real technical debt in the source, recorded here rather than smoothed into a single described path; **reapplies-divider-color-on-layer-update** states it as a MAY rather than a MUST so a port is not obligated to reproduce the redundancy.
**Approved**: pending

**Decision**: `SettingsLayout.default[.dividerThickness]` is read exactly once, into an `NSLayoutConstraint` activated at `init` time, even though `SettingsLayout` is `Observable`/`@Published`.
**Rationale**: Not explained in source comments. `DividerView` never subscribes to `SettingsLayout.default`'s publisher, so an existing `DividerView` does not resize if that value is later changed at runtime (see **ignores-settings-layout-changes** and Edge Cases → Boundary values). Recorded here as a known staleness limitation rather than an intended contract, since nothing in the source suggests it was deliberate.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`contrast-ratio` is partial: `DividerView` applies `dividerColor` exactly as the palette defines it and never computes a color itself, but this file contains no measured contrast ratio of `dividerColor` against the settings background it is drawn over — that verification is the palette/theme's responsibility, not something confirmable from `DividerView.swift` alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated three implementation-detail requirements as observable outcomes, weakened the redundant layer-update repaint to a MAY, added an ignores-settings-layout-changes requirement with a matching vector, tightened four ambiguous test vectors and labeled one as a static/compile-time check, fixed Design Decisions approval formatting, marked contrast-ratio partial, swapped the deprecated Compose Divider() for HorizontalDivider(), added the sibling Button View recipe to related, and stated that the decorative hairline stays out of the accessibility tree; removed Compliance rows for checks absent from the cookbook catalog |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
