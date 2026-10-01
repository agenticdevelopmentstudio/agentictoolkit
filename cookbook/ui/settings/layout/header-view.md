---
id: d908b337-53ba-4a29-8288-4601b12a4bb7
title: Header View
domain: agentictoolkit://cookbook/ui/settings/layout/header-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A minimal view wrapping a caption-styled label, used as the caption above
  a settings group.
platforms:
- swift
- macos
tags:
- ui
- header
- settings
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/group-view
references: []
approved-by: ''
approved-date: ''
---

# Header View

## Overview

The Header View is a minimal view that wraps a single caption-styled label
pinned flush to all four of its own edges. It fulfills the same settings-
row-view contract as its siblings in this system. The sibling Group View
recipe documents its role directly: constructing a settings group from a
title builds a Header View as "a caption *outside* and above a rounded
card" — the label naming a settings group, sitting above the group's card
rather than inside it as a row. It is also constructed directly elsewhere in
the app to caption a settings subview. The Header View itself draws nothing
and holds no theming logic of its own; all appearance (color, font,
single-line clipping) comes from the label it wraps.

## Behavioral Requirements

- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **exposes-title-label**: The component MUST expose its label as a public,
  immutable property, so a caller can read or observe its title.
- **creates-title-label-with-secondary-caption-style**: The component MUST
  style its label with the theme's `.secondaryText` color role and
  `.caption` text role.
- **sets-title-label-initial-text**: The component MUST initialize its
  label's displayed text to the caller-supplied `title` string,
  unmodified.
- **pins-title-label-to-all-four-edges**: The component MUST make its label
  fill its own bounds exactly, pinned to its top, leading, trailing, and
  bottom edges with no additional inset, so the component's bounds and the
  label's bounds coincide (see Platform Notes for the mechanics the source
  uses).
- **requires-title-at-construction**: The component MUST require a `title`
  value to construct a usable instance; no construction path may produce a
  usable instance without one (see Platform Notes for how the
  source enforces this on this platform).

## Appearance

- **Corner radius**: None; the component has no layer or shape of its own.
- **Padding**: Zero on all sides. The label is pinned to the component's
  top, leading, trailing, and bottom edges with no constant offset, so the
  component contributes no padding around its label; any surrounding space
  is entirely the calling container's responsibility (e.g. the Group
  View's header-to-card spacing).
- **Font**: Caption text role — 11pt, regular weight, system font family,
  scaled by the active theme's size scale, unless the active theme
  overrides the caption style.
- **Background**: None; the component draws no background of its own, and
  its label draws no background of its own either.
- **Foreground/Text**: The label's text color tracks the theme's
  `.secondaryText` role. The default derivation is the theme's foreground
  color dimmed 32% toward its background color with a 3.0 minimum-contrast
  floor, unless the active theme supplies an explicit override for that
  role.
- **Border**: None; the component and its label draw no border of their own.
- **Shadow**: None; no shadow property is set anywhere.
- **Min/Max size**: The component sets no explicit size constraint of its
  own. Its effective size is the label's intrinsic content size: the label
  does not wrap, uses single-line mode, and clips rather than truncates
  when it exceeds the width its container allows, so the component (whose
  bounds equal the label's) sizes to a single, non-wrapping, clipped line.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders the label's text in the `secondaryText` role at the `.caption` font, filling the component's bounds exactly; there is no other state. |
| Pressed | Not applicable: the component sets no target/action, gesture recognizer, or tracking area, and its label is not editable — neither can receive or respond to a press. |
| Disabled | Not applicable: the source never reads or sets an enabled state or any dimmed appearance on either the component or its label — there is no enabled/disabled concept here. |
| Focused | Not applicable: the component never accepts keyboard focus and participates in no focus/key-view loop; its label is a non-editable, non-selectable text element with no focus ring behavior coded. |
| Loading | Not applicable: the component performs no asynchronous work of any kind and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not set explicitly — no accessibility role override is
  applied to either the component or its label. The platform's default for
  a non-editable text element is a static-text accessibility element, so a
  screen reader exposes the label's text as static text without any
  additional code; the label captions a settings group but is not exposed
  as a heading, so a screen-reader user cannot jump between groups by
  heading.
- **Label requirements**: The label's displayed text (set from the
  caller-supplied `title` parameter) is both the visible text and, via the
  platform's default accessibility behavior, the accessible name — there is
  no separate accessible label set, and none is needed since the visible
  text and the accessible content are the same string.
- **Announce state changes**: Not applicable — the component defines no
  state that changes (see States); there is nothing for a screen reader to
  announce.
- **Minimum tap target**: Not applicable — the component is not an
  interactive control. It wires no target/action or gesture recognizer to
  it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| header-view-001 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |
| header-view-002 | exposes-title-label | Construct the component with title "Section" | Its label is accessible from outside the type and is the same label instance the component displays |
| header-view-005 | creates-title-label-with-secondary-caption-style | Construct the component with title "Section" | The label's color role is the theme's `.secondaryText` role and its text role is `.caption` |
| header-view-006 | sets-title-label-initial-text | Construct the component with title "General" | The label displays "General" |
| header-view-007 | pins-title-label-to-all-four-edges | Construct the component with title "Section", add it inside a fixed 200×20-point container, and force a layout pass | The label's resolved bounds equal the component's bounds exactly (top, leading, trailing, and bottom all at zero offset) |
| header-view-008 | requires-title-at-construction | Attempt to construct the component via a bare/default construction path that supplies no title | Construction is rejected; no usable instance is produced. Not testable as an ordinary in-process assertion on every platform — where the failure mode is a runtime trap rather than a thrown/returned error, this requires a crash-test harness or a compile-time/unavailable check instead. |
| header-view-009 | requires-title-at-construction | Attempt to construct the component via a serialization/decoding-based construction path that supplies no title | Construction is rejected; no usable instance is produced. Same testing caveat as above. |

## Edge Cases

- **Null/empty input**: `title` is a required, non-optional string
  parameter with no default value. Passing an empty string is valid and
  produces a component whose label displays an empty string — an
  empty-but-present label with a near-zero intrinsic width. No guard exists
  against this and none is needed, since a required string value cannot be
  missing.
- **Boundary values**: Very long `title` strings. Because the label uses
  single-line mode with clipping rather than wrapping or truncation, a
  title too wide for its container is drawn clipped at the edge, not
  wrapped or truncated with an ellipsis; the component activates no width
  constraint of its own, so the label's actual display width is bounded
  only by whatever ancestor view constrains the component's width.
- **Concurrent access**: Not applicable — the component is confined to the
  UI thread, so construction and every property mutation are serialized to
  that thread.
- **Error states**: Not applicable — the component has no dependency on
  network, database, or file-system access, and the source shows no error
  path of any kind.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | string | none (required) | The text displayed by the label; passed straight through with no transformation, truncation, or validation. |

## Deep Linking

Not applicable: the component is a decorative caption label with no
navigable identity of its own — it has no route, screen, or resource that a
deep link could target.

## Localization

Not applicable: the component defines no string key or localization lookup
of its own. `title` is an opaque, caller-supplied string displayed
verbatim; the component performs no automatic localized-key lookup, so
producing a localized caption is entirely the caller's responsibility
before it reaches construction.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component applies no animation, transition, or motion effect of its own — it is built once, at construction, with no animation wrapping any of it. |
| Increase Contrast | The component sets no Increase Contrast handling of its own. Its text is 11pt caption type in the `secondaryText` role, whose derivation guarantees only a 3.0 minimum contrast — below the 4.5:1 WCAG AA figure for text this small; see the open question on minimum-contrast-ratio. |
| Differentiate Without Color | Not applicable: the component conveys no state or meaning through color — it renders exactly one presentation, a caption-styled label, with no color-coded distinction for an alternate cue to replace. |

- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The
  `secondaryText` role's derivation guarantees only a 3.0 minimum contrast,
  but this 11pt caption text needs 4.5:1 for WCAG AA; whether each shipped
  theme's resolved secondary-text-on-background pair reaches 4.5:1 depends
  on the concrete theme colors and needs a human audit of the running UI
  per theme.

## Feature Flags

Not applicable: the source contains no feature-flag check; the component
always constructs and lays out its label unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry
calls, and the component has no user interaction to report — it is a
static, non-interactive label.

## Privacy

- **Data collected**: None. The component's only stored property is its
  label, and the only caller-supplied data is the `title` string used to
  build it; nothing beyond what is already visibly displayed on screen is
  held or derived.
- **Storage**: Not applicable — the component performs no persistence of
  any kind.
- **Transmission**: Not applicable — the component performs no network or
  IPC calls.
- **Retention**: Not applicable — the `title` text lives only in the
  label's displayed text for as long as the view instance exists; nothing
  is retained beyond that.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: Use `Text(title)` with `.font(.caption)` and `.foregroundStyle(.secondary)` (or the app's own semantic secondary-text color token), stretched to fill its container with `.frame(maxWidth: .infinity, alignment: .leading)` and no padding, reproducing the zero-padding, edge-pinned layout this component builds with Auto Layout. SwiftUI's environment-based theming (`@Environment`) replaces this source's manual `ThemedLabel` construction. `.lineLimit(1)` alone applies SwiftUI's default truncation mode, which adds a tail ellipsis and does not match the source's `.byClipping` behavior; use `.lineLimit(1).fixedSize(horizontal: true, vertical: false)` inside a frame with `.clipped()` to reproduce the source's clip-without-ellipsis behavior instead.
- **Compose**: Use `Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Clip)` inside a `Box`/`Column` with no padding of its own, reading the type scale and color from a `CompositionLocal`-backed theme so Compose recomposes automatically on theme change, the way this source's `ThemePaletteObserver` (on `ThemedLabel`, not the component itself) drives repaint.
- **React/Web**: A `<span>` or `<div>` styled `font-size: 11px` (or the app's caption-scale CSS variable), `color: var(--secondary-text-color)`, `white-space: nowrap`, and `overflow: hidden` (matching the source's clip-without-ellipsis behavior — omit `text-overflow: ellipsis`), filling its parent with no margin or padding of its own. A CSS custom property already repaints on a theme-class change with no JS callback required, standing in for `ThemedLabel`'s notification-driven repaint.
- **AppKit / UIKit (source)**: `HeaderView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HeaderView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is nested in the `ComposableSettings` namespace and conforms to `SettingsViewProtocol`, a marker protocol with no requirements of its own that every settings-row view in this system adopts. It is a plain `NSView` with no layer or drawing code of its own, sets `translatesAutoresizingMaskIntoConstraints = false` on itself during initialization, and wraps a single `ThemedLabel` (`titleLabel`) added as a subview and pinned to all four edges via four activated `NSLayoutConstraint`s (top, leading, trailing, and bottom anchors, each with a zero constant), satisfying `pins-title-label-to-all-four-edges`. `requires-title-at-construction` is satisfied by blocking both frame-based and `NSCoder` construction: the designated `init(frame frameRect: NSRect)` initializer fatal-errors unconditionally regardless of the supplied frame (the diagnostic message text is malformed — see Design Decisions — and is not itself part of the contract), and `required init?(coder: NSCoder)` fatal-errors with the message `init(coder:) has not been implemented`. A UIKit port would use `UILabel` with `numberOfLines = 1` and `lineBreakMode = .byClipping`, pinned to its container's edges via `NSLayoutConstraint` or an equivalent Auto Layout API; unlike this AppKit source (which relies on `ThemeTypography`'s own `sizeScale` rather than the OS text-size setting), a `UILabel` would additionally need `adjustsFontForContentSizeCategory` decided explicitly if Dynamic Type support is wanted.
- **WinUI 3**: Use a `TextBlock` styled `Style="{StaticResource CaptionTextBlockStyle}"` (or a custom style matching the port's caption type ramp) with `Foreground` bound to a `ThemeResource` brush equivalent to `secondaryText` — Fluent 2's built-in `TextFillColorSecondaryBrush` is the closest stock token — and `TextWrapping="NoWrap"` with `TextTrimming="Clip"` (not `CharacterEllipsis`, since the source never shows an ellipsis) to match `.byClipping`. Stretch the `TextBlock` to fill its container (`HorizontalAlignment="Stretch"`, `VerticalAlignment="Stretch"`, `Margin="0"`) to reproduce the zero-padding, edge-pinned layout this component builds with `NSLayoutConstraint`. Repaint on theme change by binding to a `ThemeResource` (which WinUI re-resolves automatically on `FrameworkElement.ActualThemeChanged`) rather than porting a manual observer. Neither of the source's two blocked initializers (`init(frame:)`, `init(coder:)`) needs a WinUI analog; a `UserControl`/custom-control constructor that takes the title `string` directly is the equivalent of `init(title:)`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HeaderView.swift` |

## Design Decisions

**Decision** (AppKit): `init(frame frameRect: NSRect)` is overridden to
unconditionally `fatalError("init(frame frameRect: NSRect")` instead of
accepting the supplied frame.
**Rationale**: Not explained in source comments. Recorded verbatim as a source quirk: the `fatalError` message string is itself malformed — it reads `init(frame frameRect: NSRect` with no closing parenthesis, unlike the coder initializer's correctly formatted message on the next line. This does not change behavior (the call still traps unconditionally); only the printed diagnostic text is affected.
**Approved**: pending

**Decision** (AppKit/UIKit): `titleLabel` is created with
`role: .secondaryText, textRole: .caption` rather than a heading-weight
role.
**Rationale**: Not explained in source comments. Consistent with the Group View recipe's own description of this component as "a caption *outside* and above a rounded card" — a de-emphasized label naming a settings group, not a prominent section title.
**Approved**: pending

**Decision** (AppKit/UIKit): `titleLabel` is pinned to all four edges of
the component with a zero constant on every constraint, so the component's
bounds are exactly `titleLabel`'s bounds.
**Rationale**: Not explained in source comments. The component contributes no visual chrome of its own — no background, border, or padding — so every pixel a caller sees is the label's, and any spacing around the caption is left entirely to the caller's own layout (e.g. the Group View's header-to-card spacing).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`contrast-ratio` is `partial`, not passed: `secondaryText`'s derivation enforces only a 3.0 minimum-contrast floor (`SemanticPalette.derive`, case `.secondaryText`) — below the 4.5:1 WCAG AA figure required for 11pt text — as a single, app-wide semantic token this file draws from rather than a value it computes itself (see Increase Contrast in **Accessibility Options**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: fold title-label subview/autoresizing requirements into the pinning requirement and give it a concrete test setup; stop asserting the frame-initializer's malformed message text as part of the contract; fix contrast-ratio Compliance status/prose mismatch and drop the inapplicable differentiate-without-color check; fix Design Decisions `**Approved**:` formatting; add a related cross-reference to group-view; shorten the summary; mark the main-actor test vector as a static/compile-time check; correct the SwiftUI clip-without-ellipsis guidance; remove leftover template boilerplate from Accessibility Options |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
