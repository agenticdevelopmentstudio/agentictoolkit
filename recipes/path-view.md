---
id: c7201487-b696-43b9-a4f9-d1a9e6141f7c
title: PathView
domain: agentictoolkit://recipes/path-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A single-line settings row that shows a filesystem path, truncated in the
  middle, with the full path preserved for its tooltip, accessibility value, and selectable
  text.
platforms:
- swift
- macos
tags:
- settings
- static-text
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/explanation-view
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
approved-by: ''
approved-date: ''
---

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
[ExplanationView](agentictoolkit://recipes/explanation-view) word-wraps,
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

## States

| State | Appearance change |
|-------|------------------|
| Default | Displays `path` (or `"<caption>: <path>"` when `caption` is supplied), on one line, truncated in the middle if it does not fit. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `PathView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| path-view-001 | renders-path-non-wrapping-single-line | Construct the view | `label.cell?.wraps == false`; `label.maximumNumberOfLines == 1`; `label.cell?.usesSingleLineMode == false` |
| path-view-002 | truncates-middle | Construct the view | `label.lineBreakMode == .byTruncatingMiddle` |
| path-view-003 | retains-untruncated-path | `PathView(withPath: "/very/long/path/that/does/not/fit")`, constrain the view to a narrow width, and lay it out | The label's displayed glyphs are visibly truncated (the rendered string differs from `label.stringValue`, e.g. contains an ellipsis), while `view.path == "/very/long/path/that/does/not/fit"` and `label.toolTip == "/very/long/path/that/does/not/fit"` remain the full, untruncated string |
| path-view-004 | prefixes-optional-caption | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.stringValue == "Folder: /tmp/x"` |
| path-view-005 | omits-caption-when-absent | `PathView(withPath: "/tmp/x")` | `label.stringValue == "/tmp/x"` |
| path-view-006 | exposes-raw-path-as-tooltip | `PathView(withPath: "/tmp/x")` | `label.toolTip == "/tmp/x"` |
| path-view-007 | exposes-raw-path-as-tooltip | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.toolTip == "/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-008 | exposes-raw-path-as-accessibility-value | `PathView(withPath: "/tmp/x")` | `label.accessibilityValue() as? String == "/tmp/x"` |
| path-view-009 | exposes-raw-path-as-accessibility-value | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.accessibilityValue() as? String == "/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-010 | supports-text-selection | Construct the view, then inspect the label | `label.isSelectable == true`; `label.stringValue` equals the full display string (the caption-prefixed string when a caption is supplied, `path` alone otherwise) |
| path-view-011 | yields-width-to-container | Construct the view | `label.contentCompressionResistancePriority(for: .horizontal) == .defaultLow`; `label.contentHuggingPriority(for: .horizontal) == .defaultLow` |
| path-view-012 | fills-container-bounds | Construct the view, then lay it out inside a fixed-size superview | The label's resolved frame has zero inset from `PathView`'s frame on all four edges |
| path-view-013 | exposes-label-property | Construct the view, then access `.label` from outside the type | The property is accessible and returns the same `NSTextField` instance built during init |
| path-view-014 | exposes-path-property | Construct the view, then access `.path` from outside the type | The property is accessible and equals the string passed to `init(withPath:)` |
| path-view-015 | styles-as-secondary-caption | Construct the view | `label.font` equals the active theme's `.caption` font; `label.textColor` equals the active theme's `.secondaryText` color |
| path-view-016 | conforms-to-settings-view-protocol | Construct the view | The instance can be assigned to a `SettingsViewProtocol`-typed variable without a cast |
| path-view-017 | rejects-frame-only-initialization | Attempt `PathView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| path-view-018 | rejects-storyboard-instantiation | Attempt `PathView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| path-view-019 | prefixes-optional-caption | `PathView(withPath: "/tmp/x", caption: "")` | `label.stringValue == ": /tmp/x"` |
| path-view-020 | truncates-middle | `PathView(withPath: "/tmp/x", caption: "AVeryLongCaptionThatAloneExceedsTheAvailableWidth")`, then constrain the view narrower than the caption's own rendered width | The displayed, truncated glyphs elide into the caption itself, not only the path portion; `label.lineBreakMode == .byTruncatingMiddle` |

A UI-test note: verifying that selecting all and copying yields the full
label text on the system pasteboard requires pasteboard or UI-automation
access and cannot be asserted deterministically in a unit test; cover it in a
UI/integration test suite instead of a conformance vector.

## Edge Cases

- **Null/empty input**: `path` is a non-optional `String` constructor
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty (or, with a caption, `"<caption>: "`-only) label with no
  guard against it in source (MUST, per `retains-untruncated-path` and
  `prefixes-optional-caption`).
- **Empty, non-nil caption**: `caption` is `String?`, and `caption.map { … }`
  treats `Optional("")` as present, not absent. Passing `caption: ""`
  produces the displayed and stored string `": <path>"` — a leading
  colon-space with nothing before it — since the source guards only against
  `caption == nil`, not `caption == ""` (MAY: this is observed behavior of
  `caption.map`'s emptiness-blind check, not a MUST asserted by
  `prefixes-optional-caption`, which only distinguishes nil from non-nil).
- **Boundary values**: Not applicable in the numeric-input sense —
  `PathView`'s inputs are caller-supplied strings; it has no length limit,
  minimum, or maximum for a numeric boundary to test.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`label` from
  off the main actor, so there is no concurrent-access surface to define
  behavior for.
- **Error states (dependency/network failure)**: Not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind; it does
  not validate that `path` refers to anything that exists on disk.
- **Offline/disconnected state**: Not applicable — `PathView` performs no
  network operation of its own.
- **Caption alone exceeds the available width**: `byTruncatingMiddle`
  truncates the whole rendered string (`"<caption>: <path>"`) uniformly, not
  the path portion specifically. The source's doc comment describes the
  caption as sitting at "the head, which middle truncation never eats" — true
  whenever there is enough width to preserve some of the head, but at a
  width narrower than the caption text itself, `byTruncatingMiddle` will
  begin eliding characters from within the caption too, since no code in
  `PathView.swift` treats the caption boundary specially (MAY: this is
  observed fallthrough behavior of `byTruncatingMiddle` at extreme widths,
  not a MUST that `truncates-middle` itself asserts — the requirement only
  names which `lineBreakMode` is set).
- **Very long path with no width constraint**: with both horizontal
  priorities set to `.defaultLow` and no minimum width declared, a superview
  or stack view that constrains the view's width forces the label to
  truncate further; if nothing constrains the view's width, layout falls
  back to whatever the container gives it, since neither the label nor the
  view expresses a preferred or maximum width of its own in source (MUST,
  per `yields-width-to-container`).

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

## Deep Linking

Not applicable: `PathView` is a display-only row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `PathView.swift`.

## Localization

`path` and `caption` are entirely caller-supplied at the call site as
`String`/`String?` parameters, not literals owned by this type. But
`PathView.swift:35` (`caption.map { "\($0): \(path)" }`) hardcodes the `": "`
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

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; the view renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

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

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in `PathView.swift`).

## Platform Notes

- **SwiftUI**: Compose a `Text(path)` (or `Text("\(caption): \(path)")`) with
  `.font(.caption)`, `.foregroundStyle(.secondary)`, `.lineLimit(1)`, and
  `.truncationMode(.middle)` — SwiftUI's direct analog of `.byTruncatingMiddle`
  with `maximumNumberOfLines == 1`. Add `.help(path)` for the tooltip and
  `.accessibilityValue(path)` for the accessibility-value analogs of
  `exposes-raw-path-as-tooltip`/`exposes-raw-path-as-accessibility-value`, and
  `.textSelection(.enabled)` for `supports-text-selection`. Give the view no
  fixed frame so it shrinks to the width its container provides, mirroring
  `yields-width-to-container`.
- **Compose**: Use `Text(path, style = MaterialTheme.typography.labelSmall,
  color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
  overflow = TextOverflow.MiddleEllipsis)` — Compose 1.8+'s built-in
  middle-ellipsis overflow, the nearest analog to `.byTruncatingMiddle`,
  inside a layout slot with no fixed width so it shrinks like
  `yields-width-to-container`. Compose has no separate tooltip API on plain
  `Text`; expose the full `path` via `Modifier.semantics { stateDescription =
  path }` — `stateDescription` supplements what's announced the way AppKit's
  `setAccessibilityValue` does, where `contentDescription` would instead
  replace the accessible name — for the accessibility-value analog, and a
  `TooltipBox` wrapper for the visual tooltip analog.
- **React/Web**: A `<span title={path}>` (the tooltip analog) styled with
  `white-space: nowrap; overflow: hidden;` and a CSS-only end-ellipsis is not
  enough, since CSS `text-overflow` has no middle-ellipsis value; either
  split the string into head/tail segments sized against the container's
  measured width in script (recomputed on resize, the web analog of AppKit's
  cell recomputing on layout) or use a small middle-truncation utility.
  `aria-label` would replace the element's accessible name rather than add a
  value the way AppKit's `setAccessibilityValue` does; instead pair
  `aria-describedby` with a visually-hidden (`sr-only`) span holding the full
  `path` for the accessibility-value analog, make the text selectable (the
  CSS default, unless a parent sets
  `user-select: none`) for `supports-text-selection`, and `width: 100%` with
  no `min-width` so it shrinks with its container, mirroring
  `yields-width-to-container`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, wrapping one
  `ComposableSettings.makeValueLabel`-built `ThemedLabel` reconfigured for
  middle-truncating, single-line display and pinned edge-to-edge. A UIKit
  port replaces `NSView`/`NSTextField` (`ThemedLabel`) with `UIView`/`UILabel`,
  sets `numberOfLines = 1` and `lineBreakMode = .byTruncatingMiddle` (`UILabel`'s
  direct analogs of `maximumNumberOfLines`/`lineBreakMode`), keeps the same
  horizontal-compressible priorities via
  `setContentCompressionResistancePriority(_:for:)`/
  `setContentHuggingPriority(_:for:)`, sets `accessibilityValue = path` and
  exposes the tooltip only via a custom hover/hold affordance since UIKit has
  no `NSView.toolTip` equivalent, and enables selection with
  `isUserInteractionEnabled = true` plus a `UILongPressGestureRecognizer`
  driving a `UIEditMenuInteraction` (the iOS 16 API that superseded the
  deprecated `UIMenuController`) presented via `presentEditMenu(with:)`,
  since `UILabel` has no built-in `isSelectable`. `UIView` has the same
  `init(frame:)`/`init(coder:)` initializer split as `NSView`, so a UIKit
  port can fatal-error from both exactly as `rejects-frame-only-initialization`
  and `rejects-storyboard-instantiation` require.
- **WinUI 3**: Build this as a `TextBlock`
  bound to the full `path` string through a value converter (or a small
  behavior) that performs the middle truncation itself, since XAML's
  `TextTrimming` enum (`None`, `CharacterEllipsis`, `WordEllipsis`, `Clip`)
  only trims at the trailing edge — there is no WinUI equivalent of
  `NSLineBreakMode.byTruncatingMiddle`. Recompute the head/tail split on
  `SizeChanged` (measuring candidate substrings against the `TextBlock`'s own
  `ActualWidth`, the way AppKit's cell recomputes truncation on layout), and
  keep the untruncated string separately (a bound property mirroring `path`)
  for `ToolTipService.ToolTip` and `AutomationProperties.HelpText` (or a
  custom `ValuePattern` automation peer) — WinUI's nearest analogs of
  `toolTip` and `setAccessibilityValue`; `AutomationProperties.Name` would
  replace the accessible name the way `aria-label` does elsewhere, so leave
  it to default from the bound (caption-prefixed) `TextBlock.Text`, mirroring
  AppKit's reliance on the visible string as the accessible name since no
  label override is set in source. Set `IsTextSelectionEnabled="true"` (the analog of
  `isSelectable`) so the bound `TextBlock.Text` — the full string, not the
  elided glyphs — can be selected and copied, matching
  `supports-text-selection`. Use `HorizontalAlignment="Stretch"` with no
  fixed `Width` and no `MinWidth`, the analog of `yields-width-to-container`,
  and style `Foreground`/`FontSize` from the app's secondary-text/caption
  resource keys, since WinUI 3 has no single built-in "secondary text"
  system brush the way `SemanticPalette.secondaryText` derives one.

## Design Decisions

- **Decision**: `PathView`'s label overrides `ThemedLabel`'s default
  single-line, clipped configuration by setting `usesSingleLineMode = false`
  while keeping `maximumNumberOfLines = 1`, rather than leaving
  `usesSingleLineMode = true`.
  **Rationale**: source comments state directly that "`wraps = false` rather
  than `usesSingleLineMode = true`: single-line mode is what makes the cell
  ignore `lineBreakMode`, and the line break is the whole point here" — with
  `usesSingleLineMode` left `true`, `lineBreakMode = .byTruncatingMiddle`
  would be silently ignored.
  **Approved**: pending
- **Decision**: an optional `caption` is placed at the head of the displayed
  string (`"<caption>: <path>"`), rather than after the path or in a separate
  label.
  **Rationale**: source comments explain that the head is "which middle
  truncation never eats," so placing the caption there means "the row still
  says what it is at any width" — a caption placed at the tail or the middle
  would be the first thing lost as the view narrows.
  **Approved**: pending
- **Decision**: `label.toolTip` and `label.setAccessibilityValue` are both
  set to the raw `path`, never the caption-prefixed display string, while
  selecting and copying the label's text yields the full `label.stringValue`
  (caption-prefixed, when a caption is supplied).
  **Rationale**: documented here as a source quirk rather than smoothed over.
  The source's own doc comment frames this as one guarantee — "the drawn
  text is lossy by design, so the three ways of asking for it all answer with
  the path itself" — but the three ways do not, in fact, answer identically:
  tooltip and accessibility value strip the caption while copy-via-selection
  keeps it, because copying reads `NSTextField.stringValue` (the full
  `shown` string) rather than a separately-tracked "path" value. This
  asymmetry is unchanged for this recipe; per Accessibility above, the
  caption is not exposed through any accessibility label, so the accessible
  representation carries the same gap tooltip and accessibility value do.
  **Approved**: pending
- **Decision**: the label's horizontal content-compression-resistance and
  content-hugging priorities are both lowered to `.defaultLow`.
  **Rationale**: source comments state that "a path yields its width to the
  panel instead of widening the window to stay whole — the same bargain
  every truncating label here makes," so the label is deliberately let to
  shrink to the available width instead of forcing the settings panel wider.
  **Approved**: pending
- **Decision**: force a fatal error from both `init(frame:)` and
  `init(coder:)`, leaving `init(withPath:caption:)` as the only usable
  initializer.
  **Rationale**: the view has no meaningful default state — it cannot render
  anything without a `path` string — so both inherited `NSView` initializers
  that could construct it without one are intentionally disabled rather than
  left to produce a blank row.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Statuses rest on: the label's font tracking the theme's `.caption` role and
`sizeScale` (`dynamic-type-support`, per Appearance above); the enforced
3.0-minimum `.secondaryText` contrast that cannot be confirmed at 4.5:1 for
every theme (`contrast-ratio`, per the open question on
minimum-contrast-ratio in Accessibility above); the caption-prefixed visible
text versus the raw-`path`-only accessibility value, with no accessibility
label filling the gap (`screen-reader-support`, per the Accessibility
section's Label requirements above); and the hardcoded `": "`
separator literal at `PathView.swift:35` (`no-hardcoded-strings`, per
Localization above).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the unsupported WinUI-3 motivation claim and the accessibility-value platform mappings (Compose, React/Web, WinUI 3) to use value analogs instead of name/label analogs; added a WCAG 2.1 SC 1.4.3 reference; downgraded two accidental Edge Cases from MUST to MAY; reformatted Design Decisions' Approved syntax and dropped the requirement-count-comparison decision; flagged the caption separator as an open localization gap; revised test vectors 003 and 010 and added two edge-case vectors; corrected the UIKit edit-menu API and initializer-split platform notes and the Compose version claim; and rebuilt the Compliance table against the real catalog, dropping checks with no catalog category and fixing statuses/category casing. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `PathView` (AppKit, macOS) source. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
