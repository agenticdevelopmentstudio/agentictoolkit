<!-- leaf: implement-general-view-1/header-view · source: header-view.md -->

**Rules** (cite as `implement-general-view-1/header-view#<slug>`):

- `confines-to-main-actor` MUST
- `exposes-title-label` MUST
- `conforms-to-settings-view-protocol` MUST
- `disables-autoresizing-mask-translation` MUST
- `creates-title-label-with-secondary-caption-style` MUST
- `sets-title-label-initial-text` MUST
- `pins-title-label-to-all-four-edges` MUST
- `rejects-frame-initializer` MUST
- `rejects-coder-initializer` MUST

# Header View

## Overview

`ComposableSettings.HeaderView`, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HeaderView.swift`, is a minimal AppKit `NSView` nested in the `ComposableSettings` namespace that wraps a single `ThemedLabel` (`titleLabel`) pinned flush to all four of its own edges. It conforms to `SettingsViewProtocol`, a marker protocol every settings-row view in this system adopts (alongside its siblings `DividerView` and `ButtonView`). `GroupView.swift` documents its role directly: `GroupView`'s `convenience init(withTitle:)` builds `HeaderView(title:)` as "a caption *outside* and above a rounded card" — the label naming a settings group, sitting above the group's card rather than inside it as a row. `KeyCommandsSettingsPanelViewController.swift` also constructs it directly to caption a settings subview. `HeaderView` itself draws nothing and holds no theming logic of its own; all appearance (color, font, single-line clipping) comes from the `ThemedLabel` it wraps.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **exposes-title-label**: The component MUST expose its label as a public, immutable stored property `titleLabel: ThemedLabel`.
- **conforms-to-settings-view-protocol**: The component MUST conform to `SettingsViewProtocol`.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on itself during initialization.
- **creates-title-label-with-secondary-caption-style**: The component MUST construct `titleLabel` as a `ThemedLabel` with `role: .secondaryText` and `textRole: .caption`.
- **sets-title-label-initial-text**: The component MUST initialize `titleLabel`'s displayed text to the caller-supplied `title: String` parameter, unmodified.
- **pins-title-label-to-all-four-edges**: The component MUST set `titleLabel.translatesAutoresizingMaskIntoConstraints = false`, add `titleLabel` as a subview of itself, and activate four `NSLayoutConstraint`s pinning `titleLabel`'s top, leading, trailing, and bottom anchors to the matching anchors of the component itself, each with a zero constant, so the component's bounds and the label's bounds coincide exactly.
- **rejects-frame-initializer**: The designated `init(frame frameRect: NSRect)` initializer MUST fatal-error unconditionally, regardless of the supplied `frameRect`'s value. (The source's diagnostic message text is malformed — see **Design Decisions** — and is not itself part of the contract.)
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST fatal-error with the message `init(coder:) has not been implemented`.

## Appearance

- **Corner radius**: None; `HeaderView` never sets `wantsLayer` or any `layer?.cornerRadius` — it has no layer of its own.
- **Padding**: Zero on all sides. `titleLabel` is pinned to `HeaderView`'s top, leading, trailing, and bottom anchors with no constant offset, so `HeaderView` contributes no padding around its label; any surrounding space is entirely the calling container's responsibility (e.g., `GroupView`'s `outerStack.spacing`).
- **Font**: Caption text role — per `ThemeTypography.defaultStyle(.caption)` (`ThemeTypography.swift`), 11pt, `.regular` weight, system font family (`family: nil`), scaled by the active theme's `sizeScale`, unless the active theme overrides the `.caption` style in `ThemeTypography.styles`.
- **Background**: None; `HeaderView` draws no background of its own (no `wantsLayer`, no `drawRect` override, no background-filled subview besides the label, and `ThemedLabel` itself sets `drawsBackground = false`).
- **Foreground/Text**: `titleLabel`'s text color tracks the `secondaryText` `ThemeRole`. Per `SemanticPalette.derive(_:theme:)` (`SemanticPalette.swift`), the default derivation is the theme's foreground color dimmed 32% toward its background color with a 3.0 minimum-contrast floor (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`), unless the active `ColorTheme` supplies an explicit `roleOverrides["secondaryText"]` entry.
- **Border**: None; the source sets no `layer?.borderWidth` or `borderColor`, and `ThemedLabel` sets `isBordered = false` and `isBezeled = false`.
- **Shadow**: None; no shadow property is set anywhere in the source.
- **Min/Max size**: `HeaderView` sets no explicit size constraint of its own. Its effective size is the label's intrinsic content size: `ThemedLabel` sets `cell?.wraps = false`, `cell?.usesSingleLineMode = true`, and `lineBreakMode = .byClipping`, so the label (and therefore `HeaderView`, whose bounds equal the label's) sizes to a single, non-wrapping line, clipped rather than truncated when it exceeds the width its container allows.

## Accessibility

- **Role/trait**: Not set explicitly — the source overrides no `accessibilityRole` on either `HeaderView` or `titleLabel`. AppKit's default for a non-editable `NSTextField` (which `ThemedLabel` is, with `isEditable = false`) is a static-text accessibility element, so VoiceOver exposes `titleLabel`'s text as static text without any code in this file; the label captions a settings group but is not exposed as a heading, so VoiceOver users cannot jump between groups by heading.
- **Label requirements**: `titleLabel.stringValue` (set from the caller-supplied `title` parameter) is both the visible text and, via `NSTextField`'s default accessibility behavior, the accessible name — there is no separate `accessibilityLabel` set, and none is needed since the visible text and the accessible content are the same string.
- **Announce state changes**: Not applicable — `HeaderView` defines no state that changes (see States); there is nothing for VoiceOver to announce.
- **Minimum tap target**: Not applicable — `HeaderView` is not an interactive control. The source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | none (required) | The text displayed by `titleLabel`; passed straight through to `ThemedLabel(string:role:textRole:)`'s `string` argument with no transformation, truncation, or validation. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `HeaderView` applies no animation, transition, or motion effect of its own — it is built once, at `init`, with no animator proxy or `CATransaction` anywhere in the source. |
| Increase Contrast | `HeaderView` sets no Increase Contrast handling of its own. Its text is 11pt caption type in the `secondaryText` role, whose derivation guarantees only a 3.0 minimum contrast (`SemanticPalette.derive`, case `.secondaryText`) — below the 4.5:1 WCAG AA figure for text this small; see the open question on minimum-contrast-ratio. |
| Differentiate Without Color | Not applicable: `HeaderView` conveys no state or meaning through color — it renders exactly one presentation, a caption-styled label, with no color-coded distinction for an alternate cue to replace. |

- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `secondaryText`'s derivation (`SemanticPalette.derive`, case `.secondaryText`) guarantees only a 3.0 minimum contrast, but this 11pt caption text needs 4.5:1 for WCAG AA; whether each shipped theme's resolved `secondaryText`-on-background pair reaches 4.5:1 depends on the concrete theme colors and needs a human audit of the running UI per theme.

## Privacy

- **Data collected**: None. `HeaderView`'s only stored property is `titleLabel`, and the only caller-supplied data is the `title` string used to build it; nothing beyond what is already visibly displayed on screen is held or derived.
- **Storage**: Not applicable — `HeaderView` performs no persistence of any kind.
- **Transmission**: Not applicable — `HeaderView` performs no network or IPC calls.
- **Retention**: Not applicable — the `title` text lives only in `titleLabel.stringValue` for as long as the view instance exists; nothing is retained beyond that.

