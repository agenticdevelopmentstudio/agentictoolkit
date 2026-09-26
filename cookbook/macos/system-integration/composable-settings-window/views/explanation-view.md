---
id: 25046f90-559d-4e32-8516-b5dae5f09c43
title: ExplanationView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/explanation-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A static, word-wrapping caption label used beneath a setting or panel heading in AppKit's ComposableSettings rows.
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
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/panel-heading-view
references:
- https://www.w3.org/TR/WCAG21/#contrast-minimum
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Displays `text` from `init(withText:)`, wrapped across as many lines as the container's width requires. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `ExplanationView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| explanation-view-001 | renders-caller-text | `ExplanationView(withText: "Some text")` | `label.stringValue == "Some text"` |
| explanation-view-002 | wraps-across-lines | Construct the view | `label.cell?.wraps == true`; `label.cell?.usesSingleLineMode == false`; `label.lineBreakMode == .byWordWrapping`; `label.maximumNumberOfLines == 0` |
| explanation-view-003 | compresses-and-hugs-loosely-horizontally | Construct the view | `label.contentCompressionResistancePriority(for: .horizontal) == .defaultLow`; `label.contentHuggingPriority(for: .horizontal) == .defaultLow` |
| explanation-view-004 | resists-vertical-compression | Construct the view | `label.contentCompressionResistancePriority(for: .vertical) == .required` |
| explanation-view-005 | fills-view-edge-to-edge | Construct the view, then lay it out inside a fixed-size superview | The label's resolved frame has zero inset from `ExplanationView`'s frame on all four edges |
| explanation-view-006 | exposes-label-property | Construct the view, then access `.label` from outside the type | The property is accessible and returns the same `NSTextField` instance built during init |
| explanation-view-007 | styles-as-secondary-caption | Construct the view | `label.font` equals the active theme's `.caption` font; `label.textColor` equals the active theme's `.secondaryText` color |
| explanation-view-008 | requires-text-at-construction | Attempt `ExplanationView(frame: .zero)` | The call traps with a fatal error; no instance is returned. Unavailable as a normal in-process assertion — XCTest cannot catch a Swift `fatalError`; this requires a crash-test harness or a compile-time/unavailable check instead. |
| explanation-view-009 | requires-text-at-construction | Attempt `ExplanationView(coder: someCoder)` | The call traps with a fatal error; no instance is returned. Unavailable as a normal in-process assertion — XCTest cannot catch a Swift `fatalError`; this requires a crash-test harness or a compile-time/unavailable check instead. |

## Edge Cases

- **Null/empty input**: `text` is a non-optional `String` constructor
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty label with no guard against it in source.
- **Boundary values**: Not applicable in the numeric-input sense —
  `ExplanationView`'s only input is a caller-supplied string; it has no
  length limit, minimum/maximum, or other caller-configurable numeric range
  for a boundary to test.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`label` from
  off the main actor, so there is no concurrent-access surface to define
  behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `ExplanationView`
  performs no network operation of its own.
- **Very long text with no width constraint**: with both horizontal
  priorities set to `.defaultLow` and vertical compression-resistance set
  to `.required`, the label wraps and grows taller only once something
  constrains `ExplanationView`'s own width (a superview's width constraint,
  or a stack/grid cell) — `fills-view-edge-to-edge`'s edge-to-edge pins carry
  that width straight through to the label. The source sets no
  `preferredMaxLayoutWidth` and no width constraint of its own
  (`compresses-and-hugs-loosely-horizontally`), so Auto Layout has no
  authoritative width to wrap against until the container supplies one: a
  container that does not constrain the view's width leaves the label's
  wrapped height ambiguous at that layout pass. The container MUST constrain
  the view's width for `wraps-across-lines`/`resists-vertical-compression`
  to produce a determinate multi-line height.
- **Text reassigned after construction**: callers mutate `label.stringValue`
  directly (e.g. `ExtensionsBrowsePanel.swift`'s
  `selectionName.label.stringValue = ...`); each reassignment triggers
  `NSTextField`'s standard intrinsic-content-size invalidation, which
  re-wraps and re-measures the label at its next layout pass — this is
  standard `NSTextField` behavior reached through the public `label`
  property, not custom code in `ExplanationView.swift` itself (see
  Configuration).

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

## Deep Linking

Not applicable: `ExplanationView` is a display-only row inside a composable
settings window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in `ExplanationView.swift`.

## Localization

Not applicable: `text` is entirely caller-supplied at the call site as a
`String` parameter, not a literal owned by this type. `ExplanationView.swift`
defines no string literal of its own that would need translation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call; text assignment is a synchronous property set. |
| Increase Contrast | `ExplanationView.swift` sets no custom `NSColor` — its coloring comes entirely from the theme's `.secondaryText` role, resolved through `SemanticPalette` — and no code in `ExplanationView.swift` or `SemanticPalette.swift` observes or reacts to the system's Increase Contrast setting; the color choice is unconditional. Whether the resulting per-theme contrast is sufficient at all is the open question on minimum-contrast-ratio, not duplicated here. |
| Differentiate Without Color | Not applicable — the view conveys no state through color at all; it renders only the caller-supplied text in a single, fixed secondary-text color, with no color-coded meaning to differentiate. |

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; the view renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the view holds only the `text` string passed to
  it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its `label` subview
  and the `text` it was constructed with, for its own lifetime.

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in source).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ExplanationView.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | failed | Accessibility |

Both statuses rest on `ExplanationView.swift`'s reliance on the theme's
`.secondaryText`/`.caption` roles: contrast is partial because
`SemanticPalette` enforces only a 3.0 minimum ratio (see Accessibility
above), and dynamic-type-support fails because
`ThemeTypography+NSFont.swift`'s `nsFont(scaledSize:)` builds fonts through
fixed-point-size calls (`NSFont.systemFont(ofSize:weight:)` or a named-family
lookup at an explicit size) rather than `NSFont.preferredFont(forTextStyle:)`
or any observation of the system's content-size-category setting.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded the `init(frame:)` typo design decision as a known issue instead of behavior to reproduce; moved AppKit implementation mechanics (`ComposableSettings.makeValueLabel`, the fatal-error initializers) out of Behavioral Requirements and into the AppKit Platform Note; merged the two initializer-rejection requirements into a single cross-platform `requires-text-at-construction` requirement and corrected the UIKit note's false claim about `init(frame:)`/`init(coder:)`; moved the caller text-update guidance from a SHOULD requirement into Configuration usage notes; reformatted Design Decisions into the three-line Decision/Rationale/Approved form and dropped the authoring-scope-comparison entry; rebuilt the Compliance table to cite only checks that exist in the compliance catalog, with corrected statuses; added `related`/`references` frontmatter entries; reworded the contrast-ratio and Increase Contrast accessibility text to state what is and isn't implemented; clarified that a container must constrain the view's width for correct wrapped height; flagged the two fatal-error test vectors as requiring a crash-test harness; switched the Compose mapping from `labelSmall` to `bodySmall`; and dropped the ad hoc MUST/SHOULD tags on Edge Cases bullets and the WinUI 3 Platform Note's editorial aside. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `ExplanationView` (AppKit, macOS) source. |
