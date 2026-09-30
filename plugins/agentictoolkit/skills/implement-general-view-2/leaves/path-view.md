<!-- leaf: implement-general-view-2/path-view · source: path-view.md -->

**Rules** (cite as `implement-general-view-2/path-view#<slug>`):

- `renders-path-non-wrapping-single-line` MUST
- `truncates-middle` MUST
- `retains-untruncated-path` MUST
- `prefixes-optional-caption` MUST
- `omits-caption-when-absent` MUST
- `exposes-raw-path-as-tooltip` MUST
- `exposes-raw-path-as-accessibility-value` MUST
- `supports-text-selection` MUST
- `yields-width-to-container` MUST
- `fills-container-bounds` MUST
- `exposes-label-property` MUST
- `exposes-path-property` MUST
- `styles-as-secondary-caption` MUST
- `conforms-to-settings-view-protocol` MUST
- `rejects-frame-only-initialization` MUST
- `rejects-storyboard-instantiation` MUST

# PathView

## Overview

`PathView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift`,
is a macOS `ComposableSettings` row: a single label showing one filesystem
path "as a path rather than as prose," per the type's own doc comment. It is
`@MainActor`-isolated, subclasses `NSView`, and conforms to
`SettingsViewProtocol` (an empty marker protocol every `ComposableSettings`
row view conforms to, with no requirements of its own). The source's doc
comment explains the design directly: the sibling row
ExplanationView word-wraps,
which is right for a sentence and wrong for a path — a real path wrapped
inside a settings panel's ~134pt content column broke across nine hyphenated
lines, long enough to push the group heading off the bottom of the pane.
`PathView` instead keeps its label to one line and truncates in the middle,
so the head (where the path lives) and the tail (which one it is) both
survive and only the middle — the part every sibling path tends to share —
is dropped. The full, untruncated path stays reachable through the label's
tooltip and accessibility value, and the label is selectable so its text can
be copied.

## Behavioral Requirements

- **renders-path-non-wrapping-single-line**: The label MUST render its text
  as non-wrapping (`cell?.wraps = false`) and limited to one line
  (`maximumNumberOfLines = 1`), with `usesSingleLineMode = false` so the
  label's `lineBreakMode` is honored during layout instead of being ignored
  the way `NSTextField`'s single-line mode ignores it.
- **truncates-middle**: The label MUST truncate its displayed text in the
  middle (`lineBreakMode = .byTruncatingMiddle`) when the text does not fit
  the available width.
- **retains-untruncated-path**: The view MUST retain the full, untruncated
  path string in its public `path` property, independent of the view's width
  or the label's truncated display.
- **prefixes-optional-caption**: The view MUST prefix the displayed text with
  `"<caption>: "` when a non-nil `caption` argument is supplied to
  `init(withPath:caption:)`.
- **omits-caption-when-absent**: The view MUST display only `path`, with no
  prefix, when `caption` is nil (the default).
- **exposes-raw-path-as-tooltip**: The label's tooltip MUST be set to the raw
  `path` string, never the caption-prefixed string, even when a caption is
  supplied.
- **exposes-raw-path-as-accessibility-value**: The label's accessibility
  value MUST be set to the raw `path` string, never the caption-prefixed
  string, even when a caption is supplied.
- **supports-text-selection**: The label MUST be selectable
  (`isSelectable = true`), so a caller can select and copy the label's full
  backing string.
- **yields-width-to-container**: The label MUST carry a horizontal
  content-compression-resistance priority and a horizontal content-hugging
  priority of `.defaultLow`, so it shrinks rather than forcing its container
  wider.
- **fills-container-bounds**: The view MUST pin the label's top, leading,
  trailing, and bottom edges directly to its own corresponding edges, with no
  additional inset or margin.
- **exposes-label-property**: The view MUST expose its label as a public,
  directly accessible `label` property, typed `NSTextField`.
- **exposes-path-property**: The view MUST expose the path it was
  constructed with as a public, directly accessible, immutable `path`
  property typed `String`.
- **styles-as-secondary-caption**: The label MUST be styled with the theme's
  `.secondaryText` color role and `.caption` text role, via
  `ComposableSettings.makeValueLabel`.
- **conforms-to-settings-view-protocol**: The view MUST conform to
  `SettingsViewProtocol`.
- **rejects-frame-only-initialization**: The view MUST NOT support
  construction via `init(frame:)`; that initializer MUST trigger a fatal
  error.
- **rejects-storyboard-instantiation**: The view MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.

## Appearance

- **Corner radius**: Not applicable — `PathView` is a plain `NSView` with no
  `CALayer`, `wantsLayer`, or corner-radius code anywhere in source.
- **Padding**: 0 — the label is pinned directly to all four edges with no
  additional constant (`fills-container-bounds`).
- **Font**: the theme's `.caption` text role
  (`ComposableSettings.makeValueLabel` → `ThemedLabel(textRole: .caption)` →
  `palette.font(.caption)`), which defaults to 11pt regular
  (`ThemeTypography.defaultStyle(.caption)`) and scales with the active
  theme's `sizeScale`; not monospaced, since `makeValueLabel`'s
  `monospacedDigits` parameter is not passed by `PathView` and defaults to
  `false`.
- **Background**: None/transparent — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false` on
  the label, and `PathView` sets no background of its own.
- **Foreground/Text**: the theme's `.secondaryText` color role, which
  `SemanticPalette` derives as the foreground color dimmed 32% toward the
  background, with a minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`).
- **Border**: None — no border is drawn or configured anywhere in
  `PathView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `PathView.swift`.
- **Min/Max size**: None declared — no explicit width/height constraint is
  set on the label or the view. The label's `.defaultLow` horizontal
  content-hugging and compression-resistance priorities (`yields-width-to-
  container`) let it shrink to whatever width its container gives it, with
  no floor; at a small enough width, `byTruncatingMiddle` will begin
  truncating into the caption prefix itself, not only the path (see Edge
  Cases).

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no explicit
  accessibility role override appears in source, on either `PathView` itself
  or its `label`. The label is AppKit's standard read-only `NSTextField`
  (`isEditable = false`, set by `ThemedLabel.init`), which AppKit exposes to
  assistive technology as static text by default.
- **Label requirements**: `PathView.swift` sets no accessibility label; no
  `setAccessibilityLabel` call appears anywhere in the file. The visible text
  puts `caption` at the head (`prefixes-optional-caption`) so a sighted user
  reading a captioned row sees `"Folder: /Users/…"`, but
  `setAccessibilityValue(path)` exposes only the raw `path`
  (`exposes-raw-path-as-accessibility-value`), so VoiceOver announces only
  `"/Users/…"` with nothing filling in what that path is.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — `path`
  and `label` are both `let` properties assigned once in
  `init(withPath:caption:)`; `PathView` performs no reassignment after
  construction and defines no state to announce (see States).
- **Minimum tap target**: Not applicable — the source defines no
  target/action or click handler. `label.isSelectable = true` enables
  standard `NSTextField` text selection (click-drag, double-click-word-select)
  across the label's full displayed area, which is a text-selection
  affordance, not a discrete tap target subject to a minimum size.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `.secondaryText` is derived with only an enforced *minimum* contrast ratio of 3.0 against the background (`SemanticPalette`'s `dimmed(towards:by:minContrast:)`), below the 4.5:1 that [WCAG 2.1 SC 1.4.3](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html) requires for the 11pt regular `.caption` text role this label uses (too small for the relaxed 3:1 large-text ratio); whether any given theme's actual resolved `secondaryText`-on-background ratio reaches 4.5:1 depends on that theme's concrete foreground/background pair and cannot be determined from `PathView.swift` or `SemanticPalette.swift` alone.

## Configuration

`PathView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | `String` | — (required) | The path itself, kept whole for the tooltip, accessibility value, and the `path` property; passed to `init(withPath:)` |
| `caption` | `String?` | `nil` | An optional name for what the path is (e.g. `"Folder"`), drawn ahead of it at the head of the displayed text |

```swift
public init(withPath path: String, caption: String? = nil)
```

## Localization

`path` and `caption` are entirely caller-supplied at the call site as
`String`/`String?` parameters, not literals owned by this type. But
`PathView.swift` (`caption.map { "\($0): \(path)" }`) hardcodes the `": "`
separator as a literal, user-visible glue string, not routed through
`String(localized:)`/`NSLocalizedString`. Its punctuation is locale-sensitive
— French convention inserts a space before the colon (`" : "`), and an RTL
locale would need the caption/path order and punctuation to mirror rather
than simply concatenate left-to-right — and the source does nothing to
account for either.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call; `path`, `caption`, and `label` are all assigned once, synchronously, in `init(withPath:caption:)`. |
| Increase Contrast | Not applicable to this component directly — `PathView.swift` sets no custom `NSColor`; its coloring comes entirely from the theme's `.secondaryText` role, resolved through `SemanticPalette`. Whether the resulting per-theme contrast is sufficient is tracked once under Accessibility above, not duplicated here — see the open question on minimum-contrast-ratio there. |
| Differentiate Without Color | Not applicable — the view conveys no state through color at all; it renders only `path` (and an optional caption) in a single, fixed secondary-text color, with no color-coded meaning to differentiate. |

## Privacy

- **Data collected**: None — `PathView` holds only the `path` and `caption`
  strings passed to it by the caller; it originates no data of its own. The
  caller determines what `path` refers to and whether that value is
  sensitive.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its `label` subview
  and the `path`/`caption` it was constructed with, for its own lifetime.

