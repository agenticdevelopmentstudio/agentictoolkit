<!-- leaf: implement-general-view-1/explanation-view--part-2 · source: explanation-view.md -->

# ExplanationView — continued (part 2)

**Rules** (cite as `implement-general-view-1/explanation-view--part-2#<slug>`):

- `appkit-uikit` SHOULD (source platform) — Source at packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ExplanationView.swift …
- `decision` SHOULD — init(frame frameRect: NSRect)'s fatal-error message in source is the literal string "init(frame frameRect: NSRect", …

## Platform Notes

- **SwiftUI**: Compose a `Text(text)` with `.font(.caption)` and
  `.foregroundStyle(.secondary)` for the caption/secondary-text role
  pairing, and `.fixedSize(horizontal: false, vertical: true)` so the view
  wraps across lines and grows vertically rather than truncating — SwiftUI's
  analog of `wraps-across-lines` and `resists-vertical-compression`. Place
  it directly in the parent's layout with no fixed frame so it shrinks and
  wraps to the width it's given, mirroring
  `compresses-and-hugs-loosely-horizontally`.
- **Compose**: Use a `Text(text, style = MaterialTheme.typography.bodySmall,
  color = MaterialTheme.colorScheme.onSurfaceVariant)` — `bodySmall` is
  Material's regular-weight small body style, the closer fit for a wrapping
  paragraph than the medium-weight `labelSmall` style, which pairs a
  secondary-text color role with a caption-equivalent size — inside a layout
  slot with no fixed width, letting it wrap naturally; Compose `Text` wraps
  across lines and grows its own height by default, mirroring
  `wraps-across-lines` and `resists-vertical-compression` without extra
  configuration.
- **React/Web**: A `<p>`/`<span>` with `white-space: normal;
  overflow-wrap: break-word` (mirroring word-wrapping with no maximum line
  count) styled from the equivalent caption/secondary-text CSS custom
  properties, with `width: 100%` if it needs to fill its container
  edge-to-edge like `fills-view-edge-to-edge`, and no `max-height`/
  `-webkit-line-clamp` so it grows to fit like `resists-vertical-compression`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ExplanationView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, wrapping one label
  built through the shared value-label factory
  (`ComposableSettings.makeValueLabel`, styled with the theme's
  `.secondaryText`/`.caption` roles per `styles-as-secondary-caption`) and
  reconfigured for multi-line wrapping and pinned edge-to-edge. The source
  satisfies `requires-text-at-construction` by making `init(withText:)` the
  only usable initializer: both `override init(frame:)` and
  `required init?(coder:)` call `fatalError` instead of returning a usable
  instance — `init(frame:)`'s fatal-error message is a known source quirk
  (see Design Decisions) that a well-formed implementation should not
  reproduce. A UIKit port replaces `NSView`/`NSTextField` (`ThemedLabel`)
  with `UIView`/`UILabel`, sets `numberOfLines = 0` and
  `lineBreakMode = .byWordWrapping` (`UILabel`'s direct analogs of
  `maximumNumberOfLines`/`lineBreakMode`), and keeps the same
  horizontal-compressible/vertical-required priorities via
  `setContentCompressionResistancePriority(_:for:)`/
  `setContentHuggingPriority(_:for:)`. Unlike `NSView`, `UIView` does carry
  both a frame initializer and `init?(coder:)` — a UIKit port SHOULD mark
  both unavailable or fatal the same way to preserve
  `requires-text-at-construction`.
- **WinUI 3**: Build this as a `TextBlock`
  with `TextWrapping="WrapWholeWords"` (the analog of `lineBreakMode =
  .byWordWrapping` with `wraps = true`) and no `MaxLines` set (the analog of
  `maximumNumberOfLines = 0`, i.e. unlimited). Bind `TextBlock.Text` to the
  caller-supplied string (the analog of the `text` parameter and
  `renders-caller-text`), and set `HorizontalAlignment="Stretch"` with no
  fixed `Width` so the `TextBlock` shrinks and wraps to whatever column or
  panel width it's given, mirroring
  `compresses-and-hugs-loosely-horizontally`; leave height unconstrained
  (`Auto`-sized, the `Grid`/`StackPanel` default) so the control's height
  grows to fit its wrapped line count, mirroring
  `resists-vertical-compression`. Style `TextBlock.Foreground` and
  `TextBlock.FontSize`/`FontWeight` from the app's secondary-text/caption
  resource keys — WinUI 3 has no single built-in "secondary text" system
  brush the way `SemanticPalette.secondaryText` derives one, so a Fluent app
  typically defines an equivalent style (e.g. a
  `CaptionTextBlockStyle`-derived resource with a muted foreground brush) in
  its resource dictionary rather than hardcoding a gray. There is no WinUI
  equivalent of `NSLayoutConstraint`-based edge pinning beyond placing the
  `TextBlock` alone in its `Grid`/`StackPanel` cell with no `Margin`, which
  reproduces `fills-view-edge-to-edge` directly.

## Design Decisions

**Decision**: `ExplanationView`'s label overrides `ThemedLabel`'s default
single-line, clipped, non-wrapping configuration (`cell?.wraps = true`,
`cell?.usesSingleLineMode = false`, `lineBreakMode = .byWordWrapping`,
`maximumNumberOfLines = 0`) instead of accepting `ThemedLabel`'s defaults.
**Rationale**: source comments explain that `ThemedLabel` is deliberately
single-line by default "so a caption in a toolbar doesn't ask for two
lines' height," and that "a blurb is the other case, and has to say so" —
without these overrides, `lineBreakMode`/`maximumNumberOfLines` are ignored
while the cell is in single-line mode, and the label would (per the source
comment) "set its wrap policy and then [run] off the right edge anyway."
**Approved**: pending

**Decision**: The label's horizontal content-compression-resistance and
content-hugging priorities are both lowered to `.defaultLow`.
**Rationale**: source comments state that "a wrapping label still reports
its one-line intrinsic width unless it is allowed to yield
horizontally — otherwise a long blurb forces the whole panel (and the
settings window) as wide as the text," so the label is deliberately let to
compress and wrap to the available width instead.
**Approved**: pending

**Decision**: Force a fatal error from both `init(frame:)` and
`init(coder:)`, leaving `init(withText:)` as the only usable initializer.
**Rationale**: the view has no meaningful default state — it cannot render
anything without a `text` string — so both inherited `NSView` initializers
that could construct it without one are intentionally disabled rather than
left to produce a blank row (`requires-text-at-construction`).
**Approved**: pending

**Decision**: `init(frame frameRect: NSRect)`'s fatal-error message in
source is the literal string `"init(frame frameRect: NSRect"`, missing a
closing parenthesis and not following the `"init(coder:) has not been
implemented"` sentence form the sibling `init?(coder:)` message uses.
**Rationale**: a known issue, documented here rather than smoothed over —
the string reads as a truncated fragment of the initializer's own signature
rather than a complete sentence, and is very likely an unintentional typo.
The source is unchanged for this recipe, but this is not a decision worth
reproducing: a well-formed message (following the sibling `init?(coder:)`
sentence form) is the correct target, and any implementation — including a
future fix upstream — SHOULD use one rather than copying this exact
malformed string.
**Approved**: pending

**Decision**: `ExplanationView` provides no `update`/`setText` method;
callers that need to change the text after construction reassign
`label.stringValue` directly (see Configuration).
**Rationale**: every existing call site that updates an `ExplanationView`'s
text after construction already does this (e.g.
`ExtensionsBrowsePanel.swift`), and `NSTextField.stringValue`'s setter
already triggers the intrinsic-size invalidation a wrapping label needs —
an added `update(text:)` wrapper would only duplicate behavior
`NSTextField` already provides for free.
**Approved**: pending
