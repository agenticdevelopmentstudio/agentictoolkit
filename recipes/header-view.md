---
id: d908b337-53ba-4a29-8288-4601b12a4bb7
title: Header View
domain: agentictoolkit://recipes/header-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS AppKit NSView wrapping a single secondary/caption-styled ThemedLabel,
  pinned to all four edges, used as the caption above a ComposableSettings group card.
platforms:
- swift
- macos
tags:
- ui
- header
- macos
- settings
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Header View

## Overview

`ComposableSettings.HeaderView`, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HeaderView.swift`, is a minimal AppKit `NSView` nested in the `ComposableSettings` namespace that wraps a single `ThemedLabel` (`titleLabel`) pinned flush to all four of its own edges. It conforms to `SettingsViewProtocol`, the marker protocol every settings-row view in this system adopts (alongside its siblings `DividerView` and `ButtonView`). `GroupView.swift` documents its role directly: `GroupView`'s `convenience init(withTitle:)` builds `HeaderView(title:)` as "a caption *outside* and above a rounded card" — the label naming a settings group, sitting above the group's card rather than inside it as a row. `KeyCommandsSettingsPanelViewController.swift` also constructs it directly to caption a settings subview. `HeaderView` itself draws nothing and holds no theming logic of its own; all appearance (color, font, single-line clipping) comes from the `ThemedLabel` it wraps.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **exposes-title-label**: The component MUST expose its label as a public, immutable stored property `titleLabel: ThemedLabel`.
- **conforms-to-settings-view-protocol**: The component MUST conform to `SettingsViewProtocol`.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on itself during initialization.
- **creates-title-label-with-secondary-caption-style**: The component MUST construct `titleLabel` as a `ThemedLabel` with `role: .secondaryText` and `textRole: .caption`.
- **sets-title-label-initial-text**: The component MUST initialize `titleLabel`'s displayed text to the caller-supplied `title: String` parameter, unmodified.
- **disables-title-label-autoresizing-mask-translation**: The component MUST set `titleLabel.translatesAutoresizingMaskIntoConstraints = false` before activating any layout constraint on it.
- **adds-title-label-as-subview**: The component MUST add `titleLabel` as a subview of itself.
- **pins-title-label-to-all-four-edges**: The component MUST activate four `NSLayoutConstraint`s pinning `titleLabel`'s top, leading, trailing, and bottom anchors to the matching anchors of the component itself, each with a zero constant, so the component's bounds and the label's bounds coincide exactly.
- **rejects-frame-initializer**: The designated `init(frame frameRect: NSRect)` initializer MUST fatal-error unconditionally, regardless of the supplied `frameRect`'s value, with the message `init(frame frameRect: NSRect` (verbatim, including the source's unmatched opening parenthesis).
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

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `titleLabel`'s text in the `secondaryText` role at the `.caption` font, filling `HeaderView`'s bounds exactly; there is no other state. |
| Pressed | Not applicable: `HeaderView` sets no target/action, gesture recognizer, or tracking area, and `ThemedLabel` sets `isEditable = false` — neither can receive or respond to a press. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance on either `HeaderView` or `titleLabel` — there is no enabled/disabled concept here. |
| Focused | Not applicable: `HeaderView` never overrides `acceptsFirstResponder` and participates in no key view loop; `titleLabel` is a non-editable, non-selectable text field with no focus ring behavior coded. |
| Loading | Not applicable: `HeaderView` performs no asynchronous work of any kind and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not set explicitly — the source overrides no `accessibilityRole` on either `HeaderView` or `titleLabel`. AppKit's default for a non-editable `NSTextField` (which `ThemedLabel` is, with `isEditable = false`) is a static-text accessibility element, so VoiceOver exposes `titleLabel`'s text as static text without any code in this file. NEEDS REVIEW: the label captions a settings group, yet it is not exposed as a heading, so VoiceOver users cannot jump between groups by heading; whether the component should set a heading role is an open question.
- **Label requirements**: `titleLabel.stringValue` (set from the caller-supplied `title` parameter) is both the visible text and, via `NSTextField`'s default accessibility behavior, the accessible name — there is no separate `accessibilityLabel` set, and none is needed since the visible text and the accessible content are the same string.
- **Announce state changes**: Not applicable — `HeaderView` defines no state that changes (see States); there is nothing for VoiceOver to announce.
- **Minimum tap target**: Not applicable — `HeaderView` is not an interactive control. The source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| header-view-001 | confines-to-main-actor | Attempt to construct or mutate a `HeaderView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| header-view-002 | exposes-title-label | Construct `HeaderView(title: "Section")` | `view.titleLabel` is accessible from outside the class and is a `ThemedLabel` instance |
| header-view-003 | conforms-to-settings-view-protocol | Any initialized `HeaderView` | `view is SettingsViewProtocol` is `true` |
| header-view-004 | disables-autoresizing-mask-translation | Any initialized `HeaderView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| header-view-005 | creates-title-label-with-secondary-caption-style | Construct `HeaderView(title: "Section")` | `view.titleLabel.role == .secondaryText` and `view.titleLabel.textRole == .caption` |
| header-view-006 | sets-title-label-initial-text | Construct `HeaderView(title: "General")` | `view.titleLabel.stringValue == "General"` |
| header-view-007 | disables-title-label-autoresizing-mask-translation | Any initialized `HeaderView` | `view.titleLabel.translatesAutoresizingMaskIntoConstraints == false` |
| header-view-008 | adds-title-label-as-subview | Any initialized `HeaderView` | `view.subviews.contains(view.titleLabel)` is `true` |
| header-view-009 | pins-title-label-to-all-four-edges | Add `HeaderView` to a window with a known frame and force a layout pass | `view.titleLabel.frame` equals `view.bounds` exactly (top, leading, trailing, and bottom all at zero offset) |
| header-view-010 | rejects-frame-initializer | Construct via `HeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect` |
| header-view-011 | rejects-coder-initializer | Construct via `HeaderView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |

## Edge Cases

- **Null/empty input**: `title` is a required, non-optional `String` parameter with no default value. Passing `""` is valid and produces a `HeaderView` whose `titleLabel.stringValue == ""` — an empty-but-present label with a near-zero intrinsic width. The source has no guard against this and needs none, since a non-optional `String` cannot be null.
- **Boundary values**: Very long `title` strings. Because `titleLabel` sets `usesSingleLineMode = true` and `lineBreakMode = .byClipping` (`ThemedViews.swift`), a title too wide for its container is drawn clipped at the edge, not wrapped or truncated with an ellipsis; `HeaderView` activates no `widthAnchor` of its own, so the label's actual display width is bounded only by whatever ancestor view constrains `HeaderView`'s width.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and every property mutation are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `HeaderView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `HeaderView` performs no networking.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | none (required) | The text displayed by `titleLabel`; passed straight through to `ThemedLabel(string:role:textRole:)`'s `string` argument with no transformation, truncation, or validation. |

## Deep Linking

Not applicable: `HeaderView` is a decorative caption label with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

Not applicable: `HeaderView` defines no string key or localization lookup of its own. `title` is an opaque, caller-supplied `String` displayed verbatim via `titleLabel.stringValue`; unlike a SwiftUI `Text` initialized from a string literal, an AppKit `NSTextField`'s `stringValue` performs no automatic localized-key lookup, so producing a localized caption (e.g., via `NSLocalizedString`) is entirely the caller's responsibility before it reaches this initializer.

## Accessibility Options

Document which accessibility display options (Rule 15) this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `HeaderView` applies no animation, transition, or motion effect of its own — it is built once, at `init`, with no animator proxy or `CATransaction` anywhere in the source. |
| Increase Contrast | NEEDS REVIEW: `HeaderView` sets no Increase Contrast handling of its own. Its text is 11pt caption type in the `secondaryText` role, whose derivation guarantees only a 3.0 minimum contrast (`SemanticPalette.derive`, case `.secondaryText`) — below the 4.5:1 WCAG AA figure for text this small. Whether the role should raise its floor, or respond to Increase Contrast, is an open question. |
| Differentiate Without Color | Not applicable: `HeaderView` conveys no state or meaning through color — it renders exactly one presentation, a caption-styled label, with no color-coded distinction for an alternate cue to replace. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `HeaderView` always constructs and lays out `titleLabel` unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry calls, and `HeaderView` has no user interaction to report — it is a static, non-interactive label.

## Privacy

- **Data collected**: None. `HeaderView`'s only stored property is `titleLabel`, and the only caller-supplied data is the `title` string used to build it; nothing beyond what is already visibly displayed on screen is held or derived.
- **Storage**: Not applicable — `HeaderView` performs no persistence of any kind.
- **Transmission**: Not applicable — `HeaderView` performs no network or IPC calls.
- **Retention**: Not applicable — the `title` text lives only in `titleLabel.stringValue` for as long as the view instance exists; nothing is retained beyond that.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print`).

## Platform Notes

- **SwiftUI**: Use `Text(title)` with `.font(.caption)` and `.foregroundStyle(.secondary)` (or the app's own semantic secondary-text color token), stretched to fill its container with `.frame(maxWidth: .infinity, alignment: .leading)` and no padding, reproducing the zero-padding, edge-pinned layout `HeaderView` builds with Auto Layout. SwiftUI's environment-based theming (`@Environment`) replaces this source's manual `ThemedLabel` construction, and `.lineLimit(1)` with the default `.truncationMode` (rather than a bespoke clipping mode) is the closest match to the source's single-line, `.byClipping` label.
- **Compose**: Use `Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Clip)` inside a `Box`/`Column` with no padding of its own, reading the type scale and color from a `CompositionLocal`-backed theme so Compose recomposes automatically on theme change, the way this source's `ThemePaletteObserver` (on `ThemedLabel`, not `HeaderView` itself) drives repaint.
- **React/Web**: A `<span>` or `<div>` styled `font-size: 11px` (or the app's caption-scale CSS variable), `color: var(--secondary-text-color)`, `white-space: nowrap`, and `overflow: hidden` (matching the source's clip-without-ellipsis behavior — omit `text-overflow: ellipsis`), filling its parent with no margin or padding of its own. A CSS custom property already repaints on a theme-class change with no JS callback required, standing in for `ThemedLabel`'s notification-driven repaint.
- **AppKit / UIKit (source)**: `HeaderView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HeaderView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is a plain `NSView` with no layer or drawing code of its own, wrapping a single `ThemedLabel` pinned to all four edges by Auto Layout, and blocked from both frame-based and `NSCoder` construction. A UIKit port would use `UILabel` with `numberOfLines = 1` and `lineBreakMode = .byClipping`, pinned to its container's edges via `NSLayoutConstraint` or an equivalent Auto Layout API; unlike this AppKit source (which relies on `ThemeTypography`'s own `sizeScale` rather than the OS text-size setting), a `UILabel` would additionally need `adjustsFontForContentSizeCategory` decided explicitly if Dynamic Type support is wanted.
- **WinUI 3**: Use a `TextBlock` styled `Style="{StaticResource CaptionTextBlockStyle}"` (or a custom style matching the port's caption type ramp) with `Foreground` bound to a `ThemeResource` brush equivalent to `secondaryText` — Fluent 2's built-in `TextFillColorSecondaryBrush` is the closest stock token — and `TextWrapping="NoWrap"` with `TextTrimming="Clip"` (not `CharacterEllipsis`, since the source never shows an ellipsis) to match `.byClipping`. Stretch the `TextBlock` to fill its container (`HorizontalAlignment="Stretch"`, `VerticalAlignment="Stretch"`, `Margin="0"`) to reproduce the zero-padding, edge-pinned layout `HeaderView` builds with `NSLayoutConstraint`. Repaint on theme change by binding to a `ThemeResource` (which WinUI re-resolves automatically on `FrameworkElement.ActualThemeChanged`) rather than porting a manual observer. Neither of `HeaderView`'s two blocked initializers (`init(frame:)`, `init(coder:)`) needs a WinUI analog; a `UserControl`/custom-control constructor that takes the title `string` directly is the equivalent of `init(title:)`.

## Design Decisions

**Decision**: `init(frame frameRect: NSRect)` is overridden to unconditionally `fatalError("init(frame frameRect: NSRect")` instead of accepting the supplied frame.
**Rationale**: Not explained in source comments. Recorded verbatim as a source quirk: the `fatalError` message string is itself malformed — it reads `init(frame frameRect: NSRect` with no closing parenthesis, unlike the coder initializer's correctly formatted message on the next line. This does not change behavior (the call still traps unconditionally); only the printed diagnostic text is affected.
**Approved: pending**

**Decision**: `titleLabel` is created with `role: .secondaryText, textRole: .caption` rather than a heading-weight role.
**Rationale**: Not explained in source comments. Consistent with `GroupView.swift`'s own description of `HeaderView` as "a caption *outside* and above a rounded card" — a de-emphasized label naming a settings group, not a prominent section title.
**Approved: pending**

**Decision**: `titleLabel` is pinned to all four edges of `HeaderView` with a zero constant on every constraint, so `HeaderView`'s bounds are exactly `titleLabel`'s bounds.
**Rationale**: Not explained in source comments. `HeaderView` contributes no visual chrome of its own — no background, border, or padding — so every pixel a caller sees is the label's, and any spacing around the caption is left entirely to the caller's own layout (e.g., `GroupView`'s `outerStack.spacing`).
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | Architecture |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | UI Tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`main-actor-confined` passes because the class is declared `@MainActor` (see **confines-to-main-actor**). `no-raw-hex` passes because the only color `HeaderView` displays comes from `titleLabel`'s `secondaryText` role, never a literal `NSColor` or hex value. `differentiate-without-color` passes because `HeaderView` conveys no state through color at all — it has exactly one presentation. `contrast-ratio` passes because `secondaryText`'s derivation enforces a 3.0 minimum-contrast floor as a single, app-wide semantic token, not an arbitrary value this file computes or could get wrong independently of the palette it draws from.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
