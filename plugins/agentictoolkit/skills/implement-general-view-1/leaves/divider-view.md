<!-- leaf: implement-general-view-1/divider-view · source: divider-view.md -->

**Rules** (cite as `implement-general-view-1/divider-view#<slug>`):

- `confines-to-main-actor` MUST
- `disables-autoresizing-mask-translation` MUST
- `enables-layer-backing` MUST
- `constrains-height-to-divider-thickness` MUST
- `ignores-explicit-frame` MUST
- `convenience-init-uses-zero-frame` MUST
- `applies-divider-color-on-init` MUST
- `resolves-color-through-nearest-theme-scope` MUST
- `reapplies-divider-color-on-theme-change` MUST
- `reapplies-divider-color-on-own-scope-change` MUST
- `ignores-other-scope-change-notifications` MUST
- `retains-theme-observer-for-view-lifetime` MUST
- `reapplies-divider-color-on-layer-update` MAY
- `rejects-coder-initializer` MUST
- `conforms-to-settings-view-protocol` MUST
- `ignores-settings-layout-changes` MUST

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

## Accessibility

- **Role/trait**: Not applicable — `DividerView` is a purely decorative separator; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override, so it exposes nothing distinguishable to VoiceOver beyond the visual boundary it draws.
- **Accessibility exposure**: Not exposed — `DividerView` (DividerView.swift) is a plain `NSView` that never overrides `isAccessibilityElement`, and a plain `NSView` is not an accessibility element by default, so VoiceOver skips the decorative hairline.
- **Label requirements**: Not applicable — `DividerView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `DividerView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `DividerView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `DividerView` applies no animation, transition, or motion effect of its own; each of its four repaint paths (init, theme change, scope change, `updateLayer()`) assigns `layer?.backgroundColor` directly, with no animator proxy or `CATransaction` animation wrapping it. |
| Increase Contrast | Not applicable: `DividerView` sets no custom Increase Contrast handling of its own; the color it paints comes entirely from `palette.dividerColor`, and any Increase Contrast adaptation is the `SemanticPalette`/`ThemeManager`'s responsibility, not something this file could opt into or out of. |
| Differentiate Without Color | Not applicable: `DividerView` conveys no state or meaning through color — it renders exactly one visual presentation, a colored hairline, with no color-coded distinction for an alternate cue to replace. |

## Privacy

- **Data collected**: None. `DividerView`'s only stored property is `themeObserver`, an internal `ThemePaletteObserver` instance; it holds no caller-supplied data at all.
- **Storage**: Not applicable — `DividerView` performs no persistence of any kind.
- **Transmission**: Not applicable — `DividerView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

