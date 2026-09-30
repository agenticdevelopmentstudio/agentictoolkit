<!-- leaf: implement-general-view-1/chat-day-banner-view · source: chat-day-banner-view.md -->

**Rules** (cite as `implement-general-view-1/chat-day-banner-view#<slug>`):

- `day-text-rendered` MUST
- `day-normalized-to-start-of-day` MUST
- `label-centered` MUST
- `rules-flank-label` MUST
- `rules-equal-width` MUST
- `vertical-insets` MUST
- `rule-thickness` MUST
- `static-text-role` MUST
- `label-accessibility-label` MUST
- `label-accessibility-identifier` MUST
- `theme-responsive-styling` MUST
- `day-and-title-exposed` MUST
- `coder-init-unavailable` MUST

# ChatDayBannerView

## Overview

`ChatDayBannerView` is a macOS, AppKit view that announces a calendar day once, centered above the first message of that day in a chat transcript, and flanked by a horizontal rule on each side. A per-message timestamp says *when in the day* a message was sent; nothing else in a scrolled transcript says *which day* it was, so this banner supplies that context exactly once per day rather than on every message. It is theme-aware — it recolors its label and rules when the active theme's palette changes — and exposes the day it is showing and its rendered title text for a caller that needs to read either back.

## Behavioral Requirements

- **day-text-rendered**: The component MUST render, as the label's text, the day spelled out in full — full weekday name, full month name, unpadded day number, four-digit year — using the same day-formatting pattern applied elsewhere to message-timestamp day banners, e.g. "Wednesday, June 3 2026" for June 3, 2026 (see the AppKit/UIKit Platform Note for the concrete formatter).
- **day-normalized-to-start-of-day**: The component MUST normalize the `day` value it is given to `calendar.startOfDay(for: day)` at construction time, using the caller-supplied `calendar` (default `.current`), before formatting or exposing it.
- **label-centered**: The component MUST center the date label horizontally within the view, so the label's horizontal center coincides with the view's horizontal center regardless of the view's width (see the AppKit/UIKit Platform Note for the concrete constraint).
- **rules-flank-label**: The component MUST render one horizontal rule to each side of the label, with each rule's inner edge separated from the label by 10pt, so the rules occupy all remaining horizontal space between the label and the view's edges.
- **rules-equal-width**: The component MUST constrain the two rules to equal width to each other, so the label stays on the view's horizontal center line regardless of how wide the formatted date string is.
- **vertical-insets**: The component MUST reserve 16pt of space between the view's top edge and the label's top edge, and 8pt of space between the label's bottom edge and the view's bottom edge.
- **rule-thickness**: Each rule MUST be exactly 1pt tall and vertically centered on the label's own center line.
- **static-text-role**: The component MUST expose an accessibility role of static text (`.staticText`) on itself.
- **label-accessibility-label**: The component MUST set the label's accessibility label to the label's own rendered string value.
- **label-accessibility-identifier**: The component MUST set the label's accessibility identifier to `chat-day-banner`.
- **theme-responsive-styling**: The component MUST update the label's font, the label's text color, and both rules' colors whenever the active theme's palette changes, without being re-created.
- **day-and-title-exposed**: The component MUST expose the normalized day and the label's current rendered string as read-only public properties (`day` and `title` respectively).
- **coder-init-unavailable**: The component MUST NOT support construction from a coder; `init(coder:)` MUST be unavailable at compile time and MUST terminate the process via `fatalError` if invoked.

## Appearance

- **Corner radius**: None; the view itself has no background shape.
- **Padding**: 16pt above the label, 8pt below it (see **vertical-insets**); no horizontal padding on the view's own edges — the rules run flush to the leading and trailing edges.
- **Font**: Label uses the active theme's caption font (`palette.font(.caption)`).
- **Background**: None; the view has no background fill or layer color of its own.
- **Foreground/Text**: Label text color is the theme's `timestampText` role color.
- **Border**: None on the view; the two 1pt rule lines are filled with the theme's `divider` role color.
- **Shadow**: None.
- **Min/Max size**: None declared; the view's width is whatever its superview gives it (the rules stretch to absorb it), and its height is fixed to the label's own height plus the 16pt/8pt vertical insets.

## Accessibility

- **Role**: Static text (`.staticText`), set on the container view itself via `setAccessibilityRole(.staticText)` (see **static-text-role**).
- **Label**: The date label's accessibility label is explicitly set to its own rendered text via `label.setAccessibilityLabel(label.stringValue)` (see **label-accessibility-label**); the underlying `NSTextField(labelWithString:)` would already expose that text, so this call is redundant but present in source. The label is never removed from the accessibility tree (no `setAccessibilityElement(false)` call in source), so alongside the container's own `.staticText` role and label, VoiceOver may expose the label as a second element rather than treating the banner as one merged announcement; the source does not resolve which happens (see Compliance).
- **Identifier**: The label carries the accessibility identifier `chat-day-banner` (see **label-accessibility-identifier**), for UI-test targeting rather than for assistive technology.
- **Announce state changes**: Not applicable — the banner has no state that changes after construction other than its colors on theme change (see **theme-responsive-styling**), and a color-only change is not announced through any accessibility notification in the source.
- **Minimum tap target**: Not applicable — this is a non-interactive display element with no tap or click target.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `day` | `Date` | required, no default | Any instant on the day to announce; normalized internally to `calendar.startOfDay(for: day)` (see **day-normalized-to-start-of-day**) |
| `calendar` | `Calendar` | `.current` | Determines the day boundary (time zone, calendar system) used to normalize `day` and to decide which side of midnight an instant falls on |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (no string key; value is computed) | e.g. "Wednesday, June 3 2026" | Full date text using the shared day-format pattern (see **day-text-rendered**); this file does not own the format pattern, locale, or calendar handling for that string — see Design Decisions and the AppKit/UIKit Platform Note |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the view has no animation or transition; the label and rules are laid out once at init and only recolor on theme change, which is a static style change, not a motion effect. |
| Increase Contrast | Not applicable in this file: colors come entirely from the active `SemanticPalette` (`.timestampText`, `.divider`); if Increase Contrast should raise these colors' contrast, that is the palette's responsibility, not this view's. |
| Differentiate Without Color | Not applicable: the banner conveys a single day value through text alone; it has no state or category communicated through color that would need a non-color alternative. |

