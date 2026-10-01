---
id: c7201487-b696-43b9-a4f9-d1a9e6141f7c
title: Path View
domain: agentictoolkit://cookbook/ui/settings/rows/path-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
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
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/explanation-view
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
approved-by: ''
approved-date: ''
---

# Path View

## Overview

The Path View is a settings row: a single label showing one filesystem
path "as a path rather than as prose." It conforms to the settings row
interface every settings row implements, with no requirements of its own.
The design rationale: the sibling row
[Explanation View](agentictoolkit://cookbook/ui/settings/layout/explanation-view)
word-wraps, which is right for a sentence and wrong for a path — a real
path wrapped inside a settings panel's ~134pt content column broke across
nine hyphenated lines, long enough to push the group heading off the bottom
of the pane. The Path View instead keeps its label to one line and
truncates in the middle, so the head (where the path lives) and the tail
(which one it is) both survive and only the middle — the part every
sibling path tends to share — is dropped. The full, untruncated path stays
reachable through the label's tooltip and accessibility value, and the
label is selectable so its text can be copied.

## Behavioral Requirements

- **renders-path-non-wrapping-single-line**: The label MUST render its text
  as non-wrapping and limited to one line, honoring its truncation mode
  during layout instead of that mode being ignored, the way some
  single-line text rendering modes ignore it.
- **truncates-middle**: The label MUST truncate its displayed text in the
  middle when the text does not fit the available width.
- **retains-untruncated-path**: The view MUST retain the full, untruncated
  path string in its public `path` property, independent of the view's
  width or the label's truncated display.
- **prefixes-optional-caption**: The view MUST prefix the displayed text
  with `"<caption>: "` when a caption is supplied at construction.
- **omits-caption-when-absent**: The view MUST display only the path, with
  no prefix, when no caption is supplied (the default).
- **exposes-raw-path-as-tooltip**: The label's tooltip MUST be set to the
  raw path string, never the caption-prefixed string, even when a caption
  is supplied.
- **exposes-raw-path-as-accessibility-value**: The label's accessibility
  value MUST be set to the raw path string, never the caption-prefixed
  string, even when a caption is supplied.
- **supports-text-selection**: The label MUST be selectable, so a caller
  can select and copy the label's full backing string.
- **yields-width-to-container**: The label MUST be permitted to shrink
  below its natural width rather than forcing its container wider.
- **fills-container-bounds**: The view MUST pin the label's top, leading,
  trailing, and bottom edges directly to its own corresponding edges, with
  no additional inset or margin.
- **exposes-label-property**: The view MUST expose its label as a public,
  directly accessible property.
- **exposes-path-property**: The view MUST expose the path it was
  constructed with as a public, directly accessible, immutable property.
- **styles-as-secondary-caption**: The label MUST be styled with the
  theme's `.secondaryText` color role and `.caption` text role.
- **conforms-to-settings-view-protocol**: The view MUST conform to the
  settings row interface.

## Appearance

- **Corner radius**: Not applicable — the component is a plain view with no
  custom layer, or corner-radius code, anywhere in source.
- **Padding**: 0 — the label is pinned directly to all four edges with no
  additional constant (**fills-container-bounds**).
- **Font**: the theme's `.caption` text role, which defaults to 11pt
  regular and scales with the active theme's size scale; not monospaced
  digits, since that option is not requested by this component and
  defaults to off.
- **Background**: None/transparent — the label draws no background or
  border of its own, and the view sets no background of its own.
- **Foreground/Text**: the theme's `.secondaryText` color role, which the
  theme derives as the foreground color dimmed 32% toward the background,
  with a minimum contrast ratio of 3.0 enforced.
- **Border**: None — no border is drawn or configured anywhere in this
  component.
- **Shadow**: None — no shadow is drawn or configured anywhere in this
  component.
- **Min/Max size**: None declared — no explicit width/height constraint is
  set on the label or the view. The label's shrink-to-fit behavior
  (**yields-width-to-container**) lets it shrink to whatever width its
  container gives it, with no floor; at a small enough width, the middle
  truncation will begin truncating into the caption prefix itself, not only
  the path (see Edge Cases).

## States

| State | Appearance change |
|-------|------------------|
| Default | Displays the path (or `"<caption>: <path>"` when a caption is supplied), on one line, truncated in the middle if it does not fit. |
| Pressed | Not applicable: the component defines no click or press interaction — there is no pressed interaction to represent. |
| Disabled | Not applicable: the component exposes no enabled/disabled state or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes focused; it accepts no keyboard focus by default. |
| Loading | Not applicable: the component performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  explicit accessibility role override appears in source, on either the
  view itself or its label. The label is the platform's standard read-only
  text control, exposed to assistive technology as static text by default.
- **Label requirements**: The component sets no accessibility label of its
  own. The visible text puts the caption at the head
  (**prefixes-optional-caption**) so a sighted user reading a captioned row
  sees `"Folder: /Users/…"`, but the accessibility value exposes only the
  raw path (**exposes-raw-path-as-accessibility-value**), so a screen
  reader announces only `"/Users/…"` with nothing filling in what that
  path is.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the path, caption, and label are all assigned once at construction; the
  component performs no reassignment afterward and defines no state to
  announce (see States).
- **Minimum tap target**: Not applicable — the component defines no click
  handler. The label's selectability enables standard text selection
  (click-drag, double-click-word-select) across the label's full displayed
  area, which is a text-selection affordance, not a discrete tap target
  subject to a minimum size.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source.
  `.secondaryText` is derived with only an enforced *minimum* contrast
  ratio of 3.0 against the background, below the 4.5:1 that [WCAG 2.1 SC
  1.4.3](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
  requires for the 11pt regular `.caption` text role this label uses (too
  small for the relaxed 3:1 large-text ratio); whether any given theme's
  actual resolved `secondaryText`-on-background ratio reaches 4.5:1 depends
  on that theme's concrete foreground/background pair and cannot be
  determined from this component's definition alone.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| path-view-001 | renders-path-non-wrapping-single-line | Construct the view | The label does not wrap its text, is limited to one line, and honors its truncation mode during layout |
| path-view-002 | truncates-middle | Construct the view | The label's truncation mode is set to middle truncation |
| path-view-003 | retains-untruncated-path | Construct with path `"/very/long/path/that/does/not/fit"`, constrain the view to a narrow width, and lay it out | The label's displayed glyphs are visibly truncated (the rendered string differs from the label's full text, e.g. contains an ellipsis), while the view's path property and the label's tooltip remain the full, untruncated string `"/very/long/path/that/does/not/fit"` |
| path-view-004 | prefixes-optional-caption | Construct with path `"/tmp/x"` and caption `"Folder"` | The label's text == `"Folder: /tmp/x"` |
| path-view-005 | omits-caption-when-absent | Construct with path `"/tmp/x"` | The label's text == `"/tmp/x"` |
| path-view-006 | exposes-raw-path-as-tooltip | Construct with path `"/tmp/x"` | The label's tooltip == `"/tmp/x"` |
| path-view-007 | exposes-raw-path-as-tooltip | Construct with path `"/tmp/x"` and caption `"Folder"` | The label's tooltip == `"/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-008 | exposes-raw-path-as-accessibility-value | Construct with path `"/tmp/x"` | The label's accessibility value == `"/tmp/x"` |
| path-view-009 | exposes-raw-path-as-accessibility-value | Construct with path `"/tmp/x"` and caption `"Folder"` | The label's accessibility value == `"/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-010 | supports-text-selection | Construct the view, then inspect the label | The label is selectable; its text equals the full display string (the caption-prefixed string when a caption is supplied, the path alone otherwise) |
| path-view-011 | yields-width-to-container | Construct the view | The label is permitted to shrink below its natural width rather than forcing its container wider |
| path-view-012 | fills-container-bounds | Construct the view, then lay it out inside a fixed-size superview | The label's resolved frame has zero inset from the view's frame on all four edges |
| path-view-013 | exposes-label-property | Construct the view, then access the label property from outside the type | The property is accessible and returns the same label instance built during construction |
| path-view-014 | exposes-path-property | Construct the view, then access the path property from outside the type | The property is accessible and equals the string passed at construction |
| path-view-015 | styles-as-secondary-caption | Construct the view | The label's font equals the active theme's `.caption` font; the label's text color equals the active theme's `.secondaryText` color |
| path-view-016 | conforms-to-settings-view-protocol | Construct the view | The instance satisfies the settings row interface without a cast |
| path-view-019 | prefixes-optional-caption | Construct with path `"/tmp/x"` and caption `""` | The label's text == `": /tmp/x"` |
| path-view-020 | truncates-middle | Construct with path `"/tmp/x"` and caption `"AVeryLongCaptionThatAloneExceedsTheAvailableWidth"`, then constrain the view narrower than the caption's own rendered width | The displayed, truncated glyphs elide into the caption itself, not only the path portion; the label's truncation mode remains middle truncation |

A UI-test note: verifying that selecting all and copying yields the full
label text on the system clipboard requires platform UI-automation access
and cannot be asserted deterministically in a unit test; cover it in a
UI/integration test suite instead of a conformance vector.

## Edge Cases

- **Null/empty input**: The path is a required, non-optional constructor
  parameter, so a missing value is not possible. An empty string (`""`)
  renders an empty (or, with a caption, `"<caption>: "`-only) label with no
  guard against it in source (MUST, per **retains-untruncated-path** and
  **prefixes-optional-caption**).
- **Empty, non-nil caption**: The caption is an optional value, and the
  code that builds the prefix treats an empty string as present, not
  absent. Passing an empty caption produces the displayed and stored
  string `": <path>"` — a leading colon-space with nothing before it —
  since the source guards only against a missing caption, not an empty one
  (MAY: this is observed behavior of an emptiness-blind check, not a MUST
  asserted by **prefixes-optional-caption**, which only distinguishes
  missing from supplied).
- **Boundary values**: Not applicable in the numeric-input sense — this
  component's inputs are caller-supplied strings; it has no length limit,
  minimum, or maximum for a numeric boundary to test.
- **Concurrent access**: Not applicable — the component is confined to a
  single execution context (see Platform Notes); there is no
  concurrent-access surface to define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  component performs no I/O, network call, or dependency lookup of any
  kind; it does not validate that the path refers to anything that exists
  on disk.
- **Offline/disconnected state**: Not applicable — the component performs
  no network operation of its own.
- **Caption alone exceeds the available width**: Middle truncation
  truncates the whole rendered string (`"<caption>: <path>"`) uniformly,
  not the path portion specifically. The design rationale describes the
  caption as sitting at "the head, which middle truncation never eats" —
  true whenever there is enough width to preserve some of the head, but at
  a width narrower than the caption text itself, truncation will begin
  eliding characters from within the caption too, since no code in this
  component treats the caption boundary specially (MAY: this is observed
  fallthrough behavior at extreme widths, not a MUST that
  **truncates-middle** itself asserts — the requirement only names which
  truncation mode is set).
- **Very long path with no width constraint**: with the label permitted to
  shrink and no minimum width declared, a container that constrains the
  view's width forces the label to truncate further; if nothing constrains
  the view's width, layout falls back to whatever the container gives it,
  since neither the label nor the view expresses a preferred or maximum
  width of its own in source (MUST, per **yields-width-to-container**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | text | — (required) | The path itself, kept whole for the tooltip, accessibility value, and the `path` property. |
| `caption` | text or none | none | An optional name for what the path is (e.g. `"Folder"`), drawn ahead of it at the head of the displayed text. |

## Deep Linking

Not applicable: this component is a display-only row inside a composable
settings window, not a navigable screen; no URL scheme, route, or
deep-link handler applies.

## Localization

The path and caption are entirely caller-supplied at the call site, not
literals owned by this component. But the code that builds the caption
prefix hardcodes the `": "` separator as a literal, user-visible glue
string, not routed through a localization API. Its punctuation is
locale-sensitive — French convention inserts a space before the colon
(`" : "`), and a right-to-left locale would need the caption/path order and
punctuation to mirror rather than simply concatenate left-to-right — and
the component does nothing to account for either.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the component performs no animation or transition; the path, caption, and label are all assigned once, synchronously, at construction. |
| Increase Contrast | Not applicable to this component directly — it sets no custom color; its coloring comes entirely from the theme's `.secondaryText` role. Whether the resulting per-theme contrast is sufficient is tracked once under Accessibility above, not duplicated here — see the open question on minimum-contrast-ratio there. |
| Differentiate Without Color | Not applicable — the view conveys no state through color at all; it renders only the path (and an optional caption) in a single, fixed secondary-text color, with no color-coded meaning to differentiate. |

## Feature Flags

Not applicable: this component contains no feature-flag lookup or
conditional gate; the view renders unconditionally whenever constructed.

## Analytics

Not applicable: this component contains no analytics, tracking, or
telemetry call.

## Privacy

- **Data collected**: None — this component holds only the path and
  caption strings passed to it by the caller; it originates no data of its
  own. The caller determines what the path refers to and whether that
  value is sensitive.
- **Storage**: Not applicable — this component performs no persistence of
  any kind.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its label subview
  and the path/caption it was constructed with, for its own lifetime.

## Logging

Not applicable: this component contains no logging call (no print, log, or
logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose a `Text(path)` (or `Text("\(caption): \(path)")`) with
  `.font(.caption)`, `.foregroundStyle(.secondary)`, `.lineLimit(1)`, and
  `.truncationMode(.middle)` — SwiftUI's direct analog of `.byTruncatingMiddle`
  with `maximumNumberOfLines == 1`. Add `.help(path)` for the tooltip and
  `.accessibilityValue(path)` for the accessibility-value analogs of
  exposes-raw-path-as-tooltip/exposes-raw-path-as-accessibility-value, and
  `.textSelection(.enabled)` for supports-text-selection. Give the view no
  fixed frame so it shrinks to the width its container provides, mirroring
  yields-width-to-container.
- **Compose**: Use `Text(path, style = MaterialTheme.typography.labelSmall,
  color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
  overflow = TextOverflow.MiddleEllipsis)` — Compose 1.8+'s built-in
  middle-ellipsis overflow, the nearest analog to `.byTruncatingMiddle`,
  inside a layout slot with no fixed width so it shrinks like
  yields-width-to-container. Compose has no separate tooltip API on plain
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
  `user-select: none`) for supports-text-selection, and `width: 100%` with
  no `min-width` so it shrinks with its container, mirroring
  yields-width-to-container.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, wrapping one
  `ComposableSettings.makeValueLabel`-built `ThemedLabel` reconfigured for
  middle-truncating, single-line display (`cell?.wraps = false`,
  `maximumNumberOfLines = 1`, `usesSingleLineMode = false` so
  `lineBreakMode = .byTruncatingMiddle` is honored rather than ignored) and
  pinned edge-to-edge, with the horizontal content-compression-resistance
  and content-hugging priorities both lowered to `.defaultLow`. It
  supports construction only through `init(withPath:caption:)`: both the
  frame-only `init(frame:)` and `init(coder:)` trigger a fatal error rather
  than producing an instance, and the type is `@MainActor`-isolated, so the
  compiler rejects construction or mutation of `self`/`label` from off the
  main actor. A UIKit port replaces `NSView`/`NSTextField` (`ThemedLabel`)
  with `UIView`/`UILabel`, sets `numberOfLines = 1` and `lineBreakMode =
  .byTruncatingMiddle` (`UILabel`'s direct analogs of
  `maximumNumberOfLines`/`lineBreakMode`), keeps the same
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
  port can fatal-error from both exactly as this source's
  designated-initializer-only construction rule does.
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
  supports-text-selection. Use `HorizontalAlignment="Stretch"` with no
  fixed `Width` and no `MinWidth`, the analog of yields-width-to-container,
  and style `Foreground`/`FontSize` from the app's secondary-text/caption
  resource keys, since WinUI 3 has no single built-in "secondary text"
  system brush the way `SemanticPalette.secondaryText` derives one.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift` |

## Design Decisions

- **Decision**: Override the label's default single-line, clipped
  configuration so it stays limited to one line while still honoring its
  truncation mode, rather than using the platform default that makes a
  single-line control ignore truncation mode (AppKit/UIKit source: sets
  `usesSingleLineMode = false` while keeping `maximumNumberOfLines = 1`).
  **Rationale**: source comments state directly that "`wraps = false` rather
  than `usesSingleLineMode = true`: single-line mode is what makes the cell
  ignore `lineBreakMode`, and the line break is the whole point here" — with
  `usesSingleLineMode` left `true`, `lineBreakMode = .byTruncatingMiddle`
  would be silently ignored.
  **Approved**: pending
- **Decision**: an optional caption is placed at the head of the displayed
  string (`"<caption>: <path>"`), rather than after the path or in a
  separate label.
  **Rationale**: source comments explain that the head is "which middle
  truncation never eats," so placing the caption there means "the row still
  says what it is at any width" — a caption placed at the tail or the middle
  would be the first thing lost as the view narrows.
  **Approved**: pending
- **Decision**: the label's tooltip and accessibility value are both set
  to the raw path, never the caption-prefixed display string, while
  selecting and copying the label's text yields the full display string
  (caption-prefixed, when a caption is supplied).
  **Rationale**: documented here as a source quirk rather than smoothed
  over. The design rationale frames this as one guarantee — "the drawn
  text is lossy by design, so the three ways of asking for it all answer
  with the path itself" — but the three ways do not, in fact, answer
  identically: tooltip and accessibility value strip the caption while
  copy-via-selection keeps it, because copying reads the label's full
  displayed text (AppKit/UIKit source: `NSTextField.stringValue`) rather
  than a separately-tracked "path" value. This asymmetry is unchanged for
  this recipe; per Accessibility above, the caption is not exposed through
  any accessibility label, so the accessible representation carries the
  same gap tooltip and accessibility value do.
  **Approved**: pending
- **Decision**: the label's horizontal content-compression-resistance and
  content-hugging priorities are both lowered to allow it to shrink
  (AppKit/UIKit source: both set to `.defaultLow`).
  **Rationale**: source comments state that "a path yields its width to the
  panel instead of widening the window to stay whole — the same bargain
  every truncating label here makes," so the label is deliberately let to
  shrink to the available width instead of forcing the settings panel wider.
  **Approved**: pending
- **Decision**: force a construction failure from both out-of-band
  initialization paths, leaving the path/caption initializer as the only
  usable way to construct the view (AppKit/UIKit source: `init(frame:)` and
  `init(coder:)` both trigger a fatal error).
  **Rationale**: the view has no meaningful default state — it cannot render
  anything without a path string — so both inherited initializers that
  could construct it without one are intentionally disabled rather than
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
separator literal at `PathView.swift` (`no-hardcoded-strings`, per
Localization above).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the unsupported WinUI-3 motivation claim and the accessibility-value platform mappings (Compose, React/Web, WinUI 3) to use value analogs instead of name/label analogs; added a WCAG 2.1 SC 1.4.3 reference; downgraded two accidental Edge Cases from MUST to MAY; reformatted Design Decisions' Approved syntax and dropped the requirement-count-comparison decision; flagged the caption separator as an open localization gap; revised test vectors 003 and 010 and added two edge-case vectors; corrected the UIKit edit-menu API and initializer-split platform notes and the Compose version claim; and rebuilt the Compliance table against the real catalog, dropping checks with no catalog category and fixing statuses/category casing. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `PathView` (AppKit, macOS) source. |
