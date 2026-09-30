<!-- leaf: implement-general-view-1/explanation-view · source: explanation-view.md -->

**Rules** (cite as `implement-general-view-1/explanation-view#<slug>`):

- `renders-caller-text` MUST
- `wraps-across-lines` MUST
- `compresses-and-hugs-loosely-horizontally` MUST
- `resists-vertical-compression` MUST
- `fills-view-edge-to-edge` MUST
- `exposes-label-property` MUST
- `styles-as-secondary-caption` MUST
- `requires-text-at-construction` MUST
- `usage-notes` SHOULD — ExplanationView provides no update/setText method. Callers that need to change the displayed text after construction …

# ExplanationView

## Overview

`ExplanationView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ExplanationView.swift`,
is a macOS `ComposableSettings` row: a single label showing the "small
descriptive blurb rendered beneath a setting" that the type's own doc comment
describes. It is `@MainActor`-isolated, subclasses `NSView`, and conforms to
`SettingsViewProtocol` (an empty marker protocol every `ComposableSettings`
row view conforms to, with no requirements of its own). Unlike the single-line,
clipped label `ThemedLabel` builds by default, `ExplanationView` explicitly
reconfigures its label to wrap across as many lines as the caller's text
needs and to yield horizontal space rather than force its container wider —
the source's own inline comments describe these as the two properties "a
blurb" needs that "a caption in a toolbar" does not. It is used throughout
the app as a settings-panel help/status line (e.g. help topic bodies,
extension descriptions, key-command captions, plugin failure messages) and,
via `PanelHeadingView`, as a panel's own caption — `PanelHeadingView`'s source
comment states its caption is "an `ExplanationView` rather than a label of
its own, so it wraps inside the panel by the one policy every settings blurb
shares instead of a copy of it."

## Behavioral Requirements

- **renders-caller-text**: The label MUST display the exact `text` string
  passed to `init(withText:)`.
- **wraps-across-lines**: The label MUST wrap by word (`cell?.wraps = true`,
  `lineBreakMode = .byWordWrapping`) with multi-line mode enabled
  (`cell?.usesSingleLineMode = false`) and no maximum line count
  (`maximumNumberOfLines = 0`), overriding `ThemedLabel`'s single-line,
  clipped default.
- **compresses-and-hugs-loosely-horizontally**: The label MUST carry a
  horizontal content-compression-resistance priority of `.defaultLow` and a
  horizontal content-hugging priority of `.defaultLow`, so it shrinks and
  wraps to the width its container gives it instead of forcing that
  container wider.
- **resists-vertical-compression**: The label MUST carry a vertical
  content-compression-resistance priority of `.required`, so a wrapped,
  multi-line label is never compressed shorter than the height its line
  count requires.
- **fills-view-edge-to-edge**: The view MUST pin the label's top, leading,
  trailing, and bottom edges directly to its own corresponding edges, with
  no additional inset or margin.
- **exposes-label-property**: The view MUST expose its label as a public,
  directly accessible `label` property, typed `NSTextField`.
- **styles-as-secondary-caption**: The label MUST be styled with the theme's
  `.secondaryText` color role and `.caption` text role (see the AppKit
  Platform Note for the source's factory method).
- **requires-text-at-construction**: The view MUST require a `text` value to
  construct a usable instance; no construction path may produce a usable
  instance without one (see the AppKit Platform Note for how the source
  enforces this on this platform).

## Appearance

- **Corner radius**: Not applicable — `ExplanationView` is a plain `NSView`
  with no `CALayer`, `wantsLayer`, or corner-radius code anywhere in source.
- **Padding**: 0 — the label is pinned directly to all four edges with no
  additional constant (`fills-view-edge-to-edge`).
- **Font**: the theme's `.caption` text role
  (`ComposableSettings.makeValueLabel` → `ThemedLabel(textRole: .caption)` →
  `palette.font(.caption)`), which defaults to 11pt regular
  (`ThemeTypography.defaultStyle(.caption)`) and scales with the active
  theme's `sizeScale`; not monospaced, since `makeValueLabel`'s
  `monospacedDigits` parameter defaults to `false` in
  `ExplanationView.createLabel`.
- **Background**: None/transparent — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false` on
  the label, and `ExplanationView` sets no background of its own.
- **Foreground/Text**: the theme's `.secondaryText` color role, which
  `SemanticPalette` derives as the foreground color dimmed 32% toward the
  background, with a minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`).
- **Border**: None — no border is drawn or configured anywhere in
  `ExplanationView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `ExplanationView.swift`.
- **Min/Max size**: None declared — no explicit width/height constraint is
  set. The label's `.defaultLow` horizontal content-hugging and
  compression-resistance priorities let its width shrink to whatever the
  container gives it, while its `.required` vertical compression-resistance
  lets its height grow to fit however many lines wrapping produces.

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no explicit
  accessibility role override appears in source. The label is AppKit's
  standard read-only `NSTextField` (`isEditable = false`, set by
  `ThemedLabel.init`), which AppKit exposes to assistive technology as
  static text by default.
- **Label requirements**: Satisfied unconditionally — the label always
  carries the exact `text` argument passed to `init(withText:)`
  (`renders-caller-text`); it reads empty only if the caller passes an
  empty string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading or disabled state to announce (see States).
  Callers reassign `label.stringValue` directly, and AppKit's standard
  `NSTextField` accessibility support reflects that change without any
  further code in `ExplanationView`.
- **Minimum tap target**: Not applicable — the source defines no
  target/action, gesture recognizer, or click handling; this is a purely
  visual, non-interactive display element with no tap target to size.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `SemanticPalette`'s `dimmed(towards:by:minContrast:)` enforces only a 3.0 minimum contrast ratio for `.secondaryText`, but the `.caption` role this label uses defaults to 11pt regular — small text under WCAG 2.1's size threshold for the relaxed 3:1 large-text ratio (WCAG 1.4.3) — so the guaranteed floor of 3.0 does not by itself establish the 4.5:1 the WCAG AA small-text criterion calls for; whether any given theme's actual resolved `secondaryText`-on-background ratio reaches 4.5:1 depends on each theme's concrete foreground/background color pair and cannot be determined from `ExplanationView.swift` or `SemanticPalette.swift` alone.

## Configuration

`ExplanationView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ExplanationView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | — (required) | The text rendered by the view's label; passed to `init(withText:)` |

```swift
public init(withText text: String)
```

**Usage notes**: `ExplanationView` provides no `update`/`setText` method.
Callers that need to change the displayed text after construction SHOULD
assign `label.stringValue` directly — every call site in the codebase that
changes an `ExplanationView`'s text after construction does so this way
(e.g. `ExtensionsBrowsePanel.swift`). This is guidance for how a caller
chooses to update the view, not behavior `ExplanationView` itself enforces
or verifies, so no conformance test vector applies to it (see Design
Decisions).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call; text assignment is a synchronous property set. |
| Increase Contrast | `ExplanationView.swift` sets no custom `NSColor` — its coloring comes entirely from the theme's `.secondaryText` role, resolved through `SemanticPalette` — and no code in `ExplanationView.swift` or `SemanticPalette.swift` observes or reacts to the system's Increase Contrast setting; the color choice is unconditional. Whether the resulting per-theme contrast is sufficient at all is the open question on minimum-contrast-ratio, not duplicated here. |
| Differentiate Without Color | Not applicable — the view conveys no state through color at all; it renders only the caller-supplied text in a single, fixed secondary-text color, with no color-coded meaning to differentiate. |

## Privacy

- **Data collected**: None — the view holds only the `text` string passed to
  it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its `label` subview
  and the `text` it was constructed with, for its own lifetime.

