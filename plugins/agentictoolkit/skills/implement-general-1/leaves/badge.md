<!-- leaf: implement-general-1/badge · source: badge.md -->

**Rules** (cite as `implement-general-1/badge#<slug>`):

- `renders-rounded-pill` MUST
- `displays-caller-text` MUST
- `defaults-to-filled-style` MUST
- `paints-filled-background` MUST
- `computes-contrasting-text-color` MUST
- `falls-back-to-white-on-unconvertible-color` MUST
- `paints-outlined-appearance` MUST
- `supports-in-place-restyle` MUST
- `resets-style-to-filled-by-default-on-update` MUST
- `applies-fixed-content-padding` MUST
- `centers-label-text` MUST
- `tracks-theme-caption-font` MUST
- `sizes-to-fit-content` MUST
- `confines-mutation-to-main-actor` MUST
- `rejects-storyboard-instantiation` MUST
- `prefers-semantic-palette-colors` SHOULD

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

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or motion of any kind — `applyStyle()` reassigns layer and text properties synchronously, with no animator proxy or `CATransaction`. |
| Increase Contrast | Not applicable to this component directly: Badge reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`); whether the resulting per-instance contrast is sufficient is tracked once under Accessibility above, not duplicated here. |
| Differentiate Without Color | Satisfied: Badge always pairs its color with the caller's `text` label (`displays-caller-text`) — the source never conveys status by color alone. |

## Privacy

- **Data collected**: None. Badge holds only the `text`, `color`, and `style`
  values passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — Badge performs no persistence of any kind.
- **Transmission**: Not applicable — Badge performs no network I/O.
- **Retention**: Not applicable — Badge retains no data beyond the lifetime
  of the view instance itself.

