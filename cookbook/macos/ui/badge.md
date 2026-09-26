---
id: 2cfe57f0-cdd4-4723-a6e0-2ce4f136ce7f
title: Badge
domain: agentictoolkit://cookbook/macos/ui/badge
type: ingredient
version: 1.1.3
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A small rounded pill label for a status or category chip, in filled or outlined
  style, with caller-supplied color and automatic black/white contrasting text.
platforms:
- swift
- macos
tags:
- ui
- badge
- status-indicator
depends-on: []
related:
- agentictoolkit://cookbook/macos/ui/badge
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- https://developer.apple.com/design/human-interface-guidelines/color
approved-by: ''
approved-date: ''
---

# Badge

## Overview

`Badge`, at `packages/apple/AgenticToolkit/macOS/UI/Badge/Badge.swift`, is a small
rounded "pill" label for a status or category chip (e.g. "dev", "stopped", "3").
It is `@MainActor`-isolated and subclasses `NSView`. It is theme-agnostic for
color: the caller supplies the tint (typically drawn from a `SemanticPalette`)
and `Badge` owns only the pill shape, padding, and text styling, so it is
reusable across apps that build list rows and status chips. It renders in one
of two styles — `.filled` (solid `color` background with automatically
contrasting text) or `.outlined` (clear background with a `color` border and
text) — and can be restyled in place via `update(text:color:style:)`, e.g. when
the app's theme changes.

## Behavioral Requirements

- **renders-rounded-pill**: Badge MUST render its background as a rounded
  rectangle with a corner radius of 5pt (`layer?.cornerRadius = 5`).
- **displays-caller-text**: Badge MUST display the exact `text` string passed
  to `init` or `update` as the label's content.
- **defaults-to-filled-style**: Badge MUST use `.filled` style when no `style`
  argument is supplied to `init`.
- **paints-filled-background**: In `.filled` style, Badge MUST set its
  background to the caller-supplied `color` and its border width to 0.
- **computes-contrasting-text-color**: In `.filled` style, Badge MUST set the
  label's text color to black when the background color's luminance
  (`0.299·R + 0.587·G + 0.114·B` in the sRGB color space) is greater than 0.6,
  and to white otherwise. This heuristic does not compute a WCAG contrast
  ratio and is not guaranteed to meet any minimum numeric ratio against an
  arbitrary caller-supplied `color` — see the open question on
  minimum-contrast-ratio and the related Design Decision.
- **falls-back-to-white-on-unconvertible-color**: Badge MUST use white as the
  filled-style label text color when the caller-supplied `color` cannot be
  converted to the sRGB color space (`NSColor.usingColorSpace(.sRGB)` returns
  `nil`).
- **paints-outlined-appearance**: In `.outlined` style, Badge MUST use a clear
  (transparent) background, a 1pt border in the caller-supplied `color`, and
  set the label's text color to that same `color`.
- **supports-in-place-restyle**: Badge MUST update its displayed text, color,
  and style when `update(text:color:style:)` is called on an existing
  instance, without requiring a new instance.
- **resets-style-to-filled-by-default-on-update**: Calling
  `update(text:color:)` without an explicit `style` argument MUST reset the
  badge to `.filled`, regardless of the badge's current style, because
  `update`'s `style` parameter defaults to `.filled` independently of any
  stored state. This is a documented footgun (see Design Decisions): callers
  SHOULD NOT rely on `update` preserving the badge's current style, and
  SHOULD pass `style` explicitly on every call where a non-default style must
  be kept.
- **applies-fixed-content-padding**: Badge MUST inset its label by 6pt from
  the leading and trailing edges and 2pt from the top and bottom edges.
- **centers-label-text**: Badge MUST center-align the label's text within the
  badge (`label.alignment = .center`).
- **tracks-theme-caption-font**: Badge MUST keep the label's font
  synchronized with the current theme's caption font (`palette.font(.caption)`
  via `observeTheme`), updating it whenever the theme changes.
- **sizes-to-fit-content**: Badge MUST size itself to its content's intrinsic
  width rather than stretching to fill available horizontal space — both the
  badge and its label carry a required horizontal content-hugging priority.
- **confines-mutation-to-main-actor**: Badge MUST only be constructed or
  mutated from the main actor; the class and its public API are declared
  `@MainActor`.
- **rejects-storyboard-instantiation**: Badge MUST fail with a fatal error if
  constructed via `init?(coder:)`, since it provides no Interface
  Builder/`NSCoding` support.
- **prefers-semantic-palette-colors**: Callers SHOULD supply `color` values
  drawn from a `SemanticPalette` rather than arbitrary raw colors, per the
  type's documented intent ("typically drawn from a `SemanticPalette`"). This
  is a usage guideline for callers, not behavior Badge itself can enforce or
  verify — no test vector applies (see Design Decisions).

## Appearance

- **Corner radius**: 5pt (`layer?.cornerRadius = 5`).
- **Padding**: 2pt (top/bottom) × 6pt (leading/trailing).
- **Font**: the current theme's caption style (`palette.font(.caption)`),
  kept in sync via `observeTheme`; weight/size are not literal in `Badge.swift`
  itself — they come from the palette's `.caption` definition.
- **Background**: `.filled` → the caller-supplied `color`; `.outlined` →
  clear/transparent.
- **Foreground/Text**: `.filled` → computed black or white (see
  `computes-contrasting-text-color`); `.outlined` → the caller-supplied
  `color`.
- **Border**: `.filled` → none (width 0); `.outlined` → 1pt solid,
  caller-supplied `color`.
- **Shadow**: none — the source sets no shadow-related layer properties.
- **Min/Max size**: none declared. The badge has no explicit width/height
  constraints; it sizes to fit its label via required horizontal
  content-hugging on both the label and the container view.

## States

| State | Appearance change |
|-------|------------------|
| Default (`style: .filled`, the default for both `init` and `update`) | Solid `color` background; border width 0; label text color computed by `computes-contrasting-text-color` |
| Outlined (`style: .outlined`) | Clear background; 1pt border in `color`; label text color equals `color` |
| Pressed | Not applicable: Badge is a plain `NSView` with no target/action, gesture recognizer, or tracking area in the source — it has no pressed interaction to represent. |
| Disabled | Not applicable: Badge exposes no enabled/disabled API; the source defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: Badge never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- Role: Badge itself is a plain `NSView` with no explicit accessibility role
  override in the source. Its child, `NSTextField(labelWithString:)`, is
  AppKit's standard read-only label control, which AppKit exposes to
  assistive technology as static text by default.
- Label requirement: satisfied unconditionally — the label always carries the
  `text` argument passed to `init`/`update` (`displays-caller-text`); the only
  way the label reads empty is if the caller passes an empty string.
- Announce state changes: not applicable beyond the label's own text — Badge
  has no loading or disabled state to announce (see States); `update(...)`
  re-assigns `label.stringValue` synchronously, and AppKit's standard
  `NSTextField` accessibility support reflects `stringValue` changes without
  any custom code in `Badge`.
- Minimum tap target: Not applicable — Badge defines no target/action,
  gesture recognizer, or click handling in the source; it is a purely visual,
  non-interactive display element with no tap target to size.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `contrastingTextColor(on:)` picks black/white via a BT.601 luminance heuristic (`0.299·R + 0.587·G + 0.114·B` > 0.6) instead of the WCAG contrast-ratio formula, and `.outlined` style assigns `color` directly to text/border with no contrast check against the host background; whether either meets a specific WCAG ratio (e.g. 4.5:1) depends on each app's actual `SemanticPalette` colors and can't be settled from `Badge.swift` alone.

## Conformance Test Vectors

Vectors that reference dynamic system colors (`.systemGreen`, `.systemRed`,
`.systemGray`, `.systemBlue`) assume tests run under a fixed `NSAppearance`
(e.g. `.aqua`), since these colors resolve to different `CGColor` values under
light vs. dark appearance.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| badge-001 | renders-rounded-pill | Any `init(text:color:)` call | The badge's layer has `cornerRadius == 5` |
| badge-002 | displays-caller-text | `init(text: "dev", color: .systemGreen)` | The label's `stringValue` is exactly `"dev"` |
| badge-003 | defaults-to-filled-style | `init(text: "dev", color: .systemGreen)` (no `style`), under a fixed `NSAppearance` | Background is `.systemGreen`; border width is 0 |
| badge-004 | paints-filled-background | `init(text: "dev", color: .systemGreen, style: .filled)`, under a fixed `NSAppearance` | `layer.backgroundColor == NSColor.systemGreen.cgColor`; `layer.borderWidth == 0` |
| badge-005 | computes-contrasting-text-color | `color` = light gray, RGB (230, 230, 230) i.e. (0.902, 0.902, 0.902) in sRGB 0–1 — luminance ≈ 0.902 | Label text color is black |
| badge-005b | computes-contrasting-text-color | `color` = dark navy, RGB (0, 0, 128) i.e. (0, 0, 0.502) in sRGB 0–1 — luminance ≈ 0.057 | Label text color is white |
| badge-005c | computes-contrasting-text-color | `color` = mid-gray, RGB (153, 153, 153) i.e. (0.6, 0.6, 0.6) in sRGB 0–1 — luminance exactly 0.6 (boundary: the comparison is `>` 0.6, not `>=`) | Label text color is white |
| badge-006 | falls-back-to-white-on-unconvertible-color | `color` for which `usingColorSpace(.sRGB)` returns `nil` (e.g. a pattern-image `NSColor`), `style: .filled` | Label text color is white |
| badge-007 | paints-outlined-appearance | `init(text: "3", color: .systemRed, style: .outlined)`, under a fixed `NSAppearance` | `layer.backgroundColor == NSColor.clear.cgColor`; `layer.borderWidth == 1`; `layer.borderColor == NSColor.systemRed.cgColor`; label text color equals `.systemRed` |
| badge-008 | supports-in-place-restyle | Existing badge, then `update(text: "stopped", color: .systemGray, style: .outlined)`, under a fixed `NSAppearance` | Label reads `"stopped"`; background/border/text reflect `.outlined` with `.systemGray` |
| badge-009 | resets-style-to-filled-by-default-on-update | Badge currently `.outlined`, then `update(text: "3", color: .systemBlue)` (no `style`) | Badge renders `.filled` (solid `.systemBlue` background, border width 0), not `.outlined` |
| badge-010 | applies-fixed-content-padding | Any badge | Label's leading/trailing constraints resolve to 6pt insets; top/bottom resolve to 2pt insets |
| badge-011 | centers-label-text | Any badge | `label.alignment == .center` |
| badge-012 | tracks-theme-caption-font | Theme change while a badge is on screen | Label's font updates to the new theme's `.caption` font |
| badge-013 | sizes-to-fit-content | Badge placed with no explicit width constraint | Badge's fitting width equals the label's intrinsic width plus 12pt (6pt × 2) horizontal padding; badge does not stretch to fill a wider container |
| badge-014 | confines-mutation-to-main-actor | Attempt to call `Badge.init`/`update` from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| badge-015 | rejects-storyboard-instantiation | `Badge(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |

`badge-014` is a static, compile-time check (the Swift concurrency checker
rejects the offending code at build time), not a vector observed by running
the program; a port on a platform without an equivalent compile-time
enforcement should verify this as a build-verification note rather than a
runtime test.

`prefers-semantic-palette-colors` has no test vector: it is a SHOULD
constraining what colors a caller chooses to pass in, not an observable
behavior of `Badge` itself, so no component-level test can verify it (see
Design Decisions).

## Edge Cases

- **Empty `text`** (`""`): renders an empty label; the badge still lays out
  with its fixed 6pt/2pt padding around a zero-width label, producing a small
  pill (see `#requirements/displays-caller-text` — the source has no guard
  against an empty string).
- **Very long `text`**: no maximum width, line-wrap mode, or truncation is
  configured in the source. Because both the label and the badge carry
  required horizontal content-hugging, the badge grows to fit the full string
  unless a caller externally constrains its width (e.g. inside a stack view)
  (see `#requirements/sizes-to-fit-content`).
- **Non-sRGB-convertible `color`** (e.g. a pattern-image `NSColor`, or one
  from a color space `usingColorSpace(.sRGB)` cannot represent):
  `contrastingTextColor(on:)` falls back to white in `.filled` style; in
  `.outlined` style the same color is still assigned directly to the border
  and text regardless of convertibility, since that path never calls
  `usingColorSpace(.sRGB)` (see
  `#requirements/falls-back-to-white-on-unconvertible-color` and
  `#requirements/paints-outlined-appearance`).
- **Repeated `update` calls**: each call fully re-evaluates `applyStyle()`
  from the just-assigned `color`/`style`, so no stale visual state persists
  between calls (see `#requirements/supports-in-place-restyle`).
- **Omitting `style` on `update`**: silently resets a previously `.outlined`
  badge back to `.filled` (see
  `#requirements/resets-style-to-filled-by-default-on-update`) — see also
  Design Decisions.
- **Concurrent access**: not applicable — `Badge` is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation from off the main
  actor, so there is no concurrent-access surface for this component to
  define behavior for.
- **Error states (dependency/network failure)**: not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: not applicable — Badge performs no network
  operation of its own.
- **Boundary values**: not applicable in the numeric-input sense — Badge's
  only inputs are a caller-supplied string and color. Its fixed constants
  (5pt radius, 6pt/2pt padding) are literals in the source, not
  caller-configurable ranges with a boundary to test.

## Configuration

`Badge` (`packages/apple/AgenticToolkit/macOS/UI/Badge/Badge.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | — (required) | Text rendered as the badge's label |
| `color` | `NSColor` | — (required) | The badge's tint; controls the background (`.filled`) or border and text (`.outlined`) |
| `style` | `Badge.Style` | `.filled` | Visual treatment: `.filled` (solid background) or `.outlined` (bordered) |

```swift
public enum Style: Sendable {
    case filled
    case outlined
}

public init(text: String, color: NSColor, style: Style = .filled)
public func update(text: String, color: NSColor, style: Style = .filled)
```

## Deep Linking

Not applicable: Badge is a display-only `NSView` subclass with no route, URL
scheme handling, or navigable identity anywhere in the source.

## Localization

Not applicable: `text` is entirely caller-supplied at the call site; Badge
defines no string literals of its own that would need translation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or motion of any kind — `applyStyle()` reassigns layer and text properties synchronously, with no animator proxy or `CATransaction`. |
| Increase Contrast | Not applicable to this component directly: Badge reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`); whether the resulting per-instance contrast is sufficient is tracked once under Accessibility above, not duplicated here. |
| Differentiate Without Color | Satisfied: Badge always pairs its color with the caller's `text` label (`displays-caller-text`) — the source never conveys status by color alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. Badge renders
unconditionally whenever it is constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
calls.

## Privacy

- **Data collected**: None. Badge holds only the `text`, `color`, and `style`
  values passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — Badge performs no persistence of any kind.
- **Transmission**: Not applicable — Badge performs no network I/O.
- **Retention**: Not applicable — Badge retains no data beyond the lifetime
  of the view instance itself.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`,
or `print`).

## Platform Notes

- **SwiftUI**: Start from a small container view (or `ViewModifier`) wrapping
  a `Text`, applying `.padding(.horizontal, 6).padding(.vertical, 2)` and
  `.background(color, in: RoundedRectangle(cornerRadius: 5))` for the
  `.filled` background — `.clipShape(RoundedRectangle(cornerRadius: 5))`
  alone only clips, it paints no fill — or `.overlay(RoundedRectangle(cornerRadius: 5).stroke(color,
  lineWidth: 1))` for `.outlined`. SwiftUI has no built-in equivalent of
  `contrastingTextColor(on:)`, so port the same luminance formula as a small
  helper function, and reconcile the caption font with SwiftUI's Dynamic Type
  system rather than a raw `.caption` font size.
- **Compose**: Start from a `Box`/`Surface` with `shape =
  RoundedCornerShape(5.dp)` and a centered `Text` inset by
  `Modifier.padding(horizontal = 6.dp, vertical = 2.dp)`. Material 3's
  `AssistChip`/`SuggestionChip` are the nearest built-in analogs but carry
  interaction states (ripple, enabled/disabled) that Badge does not have, so a
  plain `Box` + `Text` composition matches Badge's non-interactive nature more
  faithfully. Reimplement the luminance-based text-color choice, since
  Compose's `contentColorFor` derives from the Material color scheme rather
  than computing per-arbitrary-color contrast.
- **React/Web**: Use an inline-block `<span>` with `border-radius: 5px`,
  `padding: 2px 6px`, background/border/color driven by the equivalent style
  prop, and a `getContrastingTextColor` helper reimplementing the same
  0.299/0.587/0.114 luminance weights and 0.6 threshold. The sibling web
  Badge recipe (`agentictoolkit://cookbook/macos/ui/badge`) already implements
  this on the web; reuse its formula so filled-style contrast decisions agree
  across platforms rather than re-deriving a possibly different threshold.
- **AppKit / UIKit**: Source at
  `packages/apple/AgenticToolkit/macOS/UI/Badge/Badge.swift` (this recipe's
  source): an `NSView` subclass owning an `NSTextField(labelWithString:)`,
  styled via `CALayer` (`cornerRadius`, `backgroundColor`, `borderWidth`,
  `borderColor`) and `NSColor`. A UIKit port replaces `NSView`/`NSTextField`/
  `NSColor` with `UIView`/`UILabel`/`UIColor`, uses `layer.cornerRadius` the
  same way, and must re-derive the `.caption`-equivalent font from whatever
  theme abstraction the iOS app uses, since this source's `observeTheme`
  extension is macOS-only (`AgenticToolkitCoreMacOS`). The
  Interface-Builder-rejecting `init?(coder:)` pattern carries over unchanged.
- **WinUI 3**: Start from a `Border` wrapping a `TextBlock`, since WinUI 3 has
  no single control offering both filled and outlined chip states for
  arbitrary text (`InfoBadge` is numeric/dot-only and cannot host a text label
  like `"dev"` or `"stopped"`). Set `Border.CornerRadius="5"` to match the 5px
  radius and `Border.Padding="6,2,6,2"` to match the leading/trailing-6,
  top/bottom-2 padding. Bind `Border.Background`, `Border.BorderBrush`,
  `Border.BorderThickness`, and the inner `TextBlock.Foreground` to the same
  two branches `applyStyle()` switches on: filled sets `Background=color`,
  `BorderThickness=0`, `TextBlock.Foreground` to the computed black/white;
  outlined sets `Background=Transparent`, `BorderThickness=1`,
  `BorderBrush=color`, `TextBlock.Foreground=color`. WinUI 3 has no built-in
  API for computing contrasting text color from an arbitrary `Color`, so port
  `contrastingTextColor(on:)` as a small static helper using the same
  0.299/0.587/0.114 weights and 0.6 threshold. Give the `Border`
  `HorizontalAlignment="Left"` (or wrap it in a `StackPanel`) so it hugs its
  content instead of stretching, matching Badge's required horizontal
  content-hugging (`sizes-to-fit-content`).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/Badge/Badge.swift` |

## Design Decisions

- **Decision**: `update`'s `style` parameter defaults to `.filled`
  independently of the badge's current, already-stored style.
  **Rationale**: This is documented here because it produces a surprising
  reset: a caller that calls `update(text:color:)` on a previously
  `.outlined` badge, intending only to change its text or color, silently
  flips it back to `.filled`. There is no state read-back in `update` to
  preserve the existing style, so callers that want to keep `.outlined` MUST
  pass `style: .outlined` explicitly on every `update` call.
  **Approved**: pending
- **Decision**: `contrastingTextColor(on:)` returns white, rather than
  throwing or reusing the current text color, when the background cannot be
  converted to sRGB.
  **Rationale**: Keeps Badge always renderable for any `NSColor` a caller
  passes in (never crashes on an exotic color space, such as a pattern
  image), at the cost of a potentially poor contrast choice for those
  unusual colors.
  **Approved**: pending
- **Decision**: The caller supplies `color` directly instead of Badge
  deriving it from a semantic status enum of its own.
  **Rationale**: Per the type's own doc comment, Badge is "theme-agnostic:
  the caller supplies the color... and the badge owns the pill shape,
  padding, and text styling" — this keeps Badge reusable across apps with
  different `SemanticPalette`s rather than baking one app's status vocabulary
  into the shared component.
  **Approved**: pending
- **Decision**: `contrastingTextColor(on:)` picks black or white using the
  perceptual-luminance formula `0.299·R + 0.587·G + 0.114·B` (the ITU-R
  BT.601 luma weights) against a 0.6 threshold, rather than the WCAG 2.x
  relative-luminance formula (which linearizes sRGB and weights channels
  0.2126/0.7152/0.0722) or a full WCAG contrast-ratio computation.
  **Rationale**: The BT.601 weights are a cheap, well-known heuristic for
  perceived brightness that needs no gamma-linearization step, so a black/
  white choice can be computed inline for any arbitrary caller-supplied
  color. The tradeoff is that, unlike a WCAG contrast-ratio check, this
  heuristic makes no guarantee about a specific minimum numeric contrast
  ratio against the chosen color — see the open question on
  minimum-contrast-ratio.
  **Approved**: pending
- **Decision**: Badge exposes no accessibility role or label context beyond
  AppKit's default static-text exposure of its `NSTextField` label — there is
  no code in the source that would let VoiceOver announce, for example, that
  a badge reading "3" is a count versus a badge reading "dev" being a status.
  **Rationale**: Badge is a plain, non-interactive label; the surrounding
  call site (e.g. a list row's other accessible elements) is expected to
  supply that context, consistent with Badge owning only pill shape, padding,
  and text styling and not caller semantics.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |

This status rests on `Badge.swift`: `contrastingTextColor(on:)` uses an
unverified perceptual-luminance heuristic rather than a WCAG contrast-ratio
computation, so a specific minimum ratio cannot be confirmed from the source
alone (`contrast-ratio`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `Badge` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: qualify the luminance-based contrasting-text-color and update-style-reset requirements against their open questions; fix `**Approved**:` formatting and edge-case `(MUST, per …)` tags to `#requirements/<name>` citations; correct badge-005/005b RGB values and add a luminance-0.6 boundary vector; note fixed-appearance test assumption and mark badge-014 as a compile-time check; fix the SwiftUI `.background`/`.clipShape` note; move the cookbook guideline citation from `references` to `related` and add external WCAG/HIG references; set `contrast-ratio` compliance status to `partial`; add Design Decisions for the luminance-heuristic choice and the lack of a distinguishing accessibility role. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
