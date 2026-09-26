---
id: ce1cec62-6244-4d1c-89db-cf31dea0f0be
title: ChatDayBannerView
domain: agentictoolkit://cookbook/macos/features/ai-chat-window/chat-day-banner-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Displays the calendar day once, centered above that day's first chat message,
  flanked by two horizontal rule lines.
platforms:
- swift
- macos
tags:
- chat
- messaging
- ui-component
- banner
depends-on:
- agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view
related:
- agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

Not applicable: `ChatDayBannerView` is a static, non-interactive display element — an `NSView` with no target-action, tracking area, button, or other control subview. It has exactly one visual configuration per active theme; the only thing that changes it post-construction is a theme change (see **theme-responsive-styling**), not a pressed, disabled, focused, or loading interaction state.

## Accessibility

- **Role**: Static text (`.staticText`), set on the container view itself via `setAccessibilityRole(.staticText)` (see **static-text-role**).
- **Label**: The date label's accessibility label is explicitly set to its own rendered text via `label.setAccessibilityLabel(label.stringValue)` (see **label-accessibility-label**); the underlying `NSTextField(labelWithString:)` would already expose that text, so this call is redundant but present in source. The label is never removed from the accessibility tree (no `setAccessibilityElement(false)` call in source), so alongside the container's own `.staticText` role and label, VoiceOver may expose the label as a second element rather than treating the banner as one merged announcement; the source does not resolve which happens (see Compliance).
- **Identifier**: The label carries the accessibility identifier `chat-day-banner` (see **label-accessibility-identifier**), for UI-test targeting rather than for assistive technology.
- **Announce state changes**: Not applicable — the banner has no state that changes after construction other than its colors on theme change (see **theme-responsive-styling**), and a color-only change is not announced through any accessibility notification in the source.
- **Minimum tap target**: Not applicable — this is a non-interactive display element with no tap or click target.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-day-banner-001 | day-text-rendered | `day` = an instant on June 3, 2026 | Label text equals "Wednesday, June 3 2026", the day-formatted string for June 3, 2026 |
| chat-day-banner-002 | day-normalized-to-start-of-day | `day` = 2026-06-03T23:59:59, `calendar` = a `Calendar` pinned to a fixed time zone (e.g. UTC) | The `day` property equals `calendar.startOfDay(for:)` of that instant (midnight of June 3 in the pinned time zone), not the raw instant passed in |
| chat-day-banner-003 | day-normalized-to-start-of-day, day-text-rendered | Two instances constructed with `day` = 2026-06-03T00:05:00 and `day` = 2026-06-03T23:50:00, both against the same `calendar` pinned to a fixed time zone (e.g. UTC) | Both instances' `day` property and label text are identical |
| chat-day-banner-004 | label-centered | Any `day`, view given a fixed width | Label's horizontal center coincides with the view's horizontal center |
| chat-day-banner-005 | rules-flank-label | Any `day` | `leadingRule`'s trailing edge sits exactly 10pt from the label's leading edge; `trailingRule`'s leading edge sits exactly 10pt from the label's trailing edge |
| chat-day-banner-006 | rules-equal-width | Two banners with very different label widths (short vs. long formatted date) | In both cases `leadingRule` and `trailingRule` have equal width, and the label remains centered |
| chat-day-banner-007 | vertical-insets | Any `day` | Label's top edge is 16pt from the view's top edge; the view's bottom edge is 8pt below the label's bottom edge |
| chat-day-banner-008 | rule-thickness | Any `day` | Both rules are exactly 1pt tall and vertically centered on the label |
| chat-day-banner-009 | static-text-role | Any `day` | The view's accessibility role is `.staticText` |
| chat-day-banner-010 | label-accessibility-label | `day` = an instant on June 3, 2026 | The label's accessibility label equals its rendered string, "Wednesday, June 3 2026" |
| chat-day-banner-011 | label-accessibility-identifier | Any `day` | The label's accessibility identifier equals `chat-day-banner` |
| chat-day-banner-012 | theme-responsive-styling | View constructed under theme A, then the active theme changes to theme B | Label font becomes theme B's caption font; label text color becomes theme B's `timestampText` color; both rules' color becomes theme B's `divider` color — the view is not re-created |
| chat-day-banner-013 | day-and-title-exposed | `day` = an instant on June 3, 2026, `calendar` pinned to a fixed time zone (e.g. UTC) | `banner.day` equals the normalized start-of-day date; `banner.title` equals the label's current string value |
| chat-day-banner-014 | coder-init-unavailable | Attempt to construct via `ChatDayBannerView(coder:)` (e.g. storyboard/XIB unarchiving) | Calling it is a compile error (`@available(*, unavailable)`); if reached at runtime regardless, the process terminates via `fatalError` |
| chat-day-banner-015 | rules-equal-width | A `day`/locale combination producing an unusually long formatted date string, in a narrow view | Label stays on one line (no wrap); both rules narrow together to absorb the remaining width, staying equal to each other for as long as their combined required width is non-negative |

## Edge Cases

- **Null/empty input**: Not applicable — `day` is a non-optional Swift `Date`, so the type system guarantees a value is always supplied; there is no null or empty case for the component to guard against.
- **Boundary values (day boundary)**: Two instants on either side of local midnight, as defined by `calendar`, MUST normalize to different `day` values via `calendar.startOfDay(for:)`, even when they are only seconds apart; conversely, two instants many hours apart but on the same calendar day MUST normalize to the same `day` value and render identical banners (see **day-normalized-to-start-of-day**, vector chat-day-banner-003).
- **Concurrent access**: Not applicable — the view is `@MainActor`-isolated; Swift's concurrency checking prevents `day`, the label, and the rules from being read or mutated off the main actor, so there is no concurrent-access case to define.
- **Error states**: Not applicable — construction and theme application are synchronous with no throwing or failable call in `init` or `apply(_:)`; there is nothing in this source that can fail.
- **Offline/disconnected state**: Not applicable — the component performs no networking; its only inputs are the `day`/`calendar` constructor parameters and the current theme palette.
- **Very long formatted date text**: The label has no explicit line-wrap or truncation configured — it uses the default behavior of `NSTextField(labelWithString:)`, a single-line, non-wrapping field. A very long localized date string stays on one line and instead narrows the two rule lines, since the rules (not the label) absorb the remaining horizontal space (see **rules-equal-width**, vector chat-day-banner-015); see the open question on **rule-width-priority**.
- **rule-width-priority**: NEEDS REVIEW: Not implemented in source. No constraint priority is set on the rules' equal-width, leading-gap, or trailing-gap constraints (the `NSLayoutConstraint.activate` call in `init`, all default to required/1000), so a formatted date long enough to force `leadingRule`/`trailingRule` toward negative width has no defined outcome — Auto Layout will break one of several equal-priority required constraints without a specified winner; settling it needs either an explicit priority decision on the rule-width/gap constraints, or a guaranteed maximum width from `AIChatBubbleView.dayFormatter`'s output.
- **Theme change while visible**: Recolors in place via `apply(_:)` (see **theme-responsive-styling**); the day text itself is unaffected, since only font and color are set by `apply(_:)`, not the label's string value.
- **Multiple messages on the same day**: The view itself does not deduplicate or decide when a new day boundary has been reached across a transcript — each instance simply displays the `day` it was constructed with. Per the class's own doc comment ("it is said where it changes and nowhere else"), avoiding duplicate banners for messages that share a day is the caller's responsibility, not this component's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `day` | `Date` | required, no default | Any instant on the day to announce; normalized internally to `calendar.startOfDay(for: day)` (see **day-normalized-to-start-of-day**) |
| `calendar` | `Calendar` | `.current` | Determines the day boundary (time zone, calendar system) used to normalize `day` and to decide which side of midnight an instant falls on |

## Deep Linking

Not applicable: `ChatDayBannerView` is a decorative divider within a chat transcript, not a navigable screen or standalone destination; the source contains no URL scheme or route handling.

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

## Feature Flags

Not applicable: the source contains no feature-flag conditional; the view is unconditionally constructed and shown by its caller.

## Analytics

Not applicable: the source contains no analytics or event-tracking calls.

## Privacy

Not applicable: the view only formats and displays a `Date` supplied by its caller; the source neither collects, stores, transmits, nor retains any data beyond holding the normalized value in the `day` property for the view's lifetime.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print` statements).

## Platform Notes

- **SwiftUI**: Build an `HStack` with a `Rectangle().frame(height: 1)` divider on each side of a centered `Text`, using `.frame(maxWidth: .infinity)` on each divider so they share remaining width equally, matching **rules-equal-width**. Apply `.padding(.top, 16)`/`.padding(.bottom, 8)` for **vertical-insets**. Render the date with a `DateFormatter` using the full-weekday/full-month pattern (`EEEE, MMMM d yyyy`, matching **day-text-rendered**). Observe palette changes the way `agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view#platforms/swiftui` does (a `ThemePaletteObserver`, since SwiftUI has no `@Themeable` attribute) and drive divider/text colors and caption font from it. Expose `day`/`title` as `let` properties on the wrapping view struct or its view model.

- **Compose**: Build a `Row` with two `Divider()`/`HorizontalDivider`-style composables, each with `Modifier.weight(1f)` so they share remaining width equally (the Compose analogue of **rules-equal-width**), flanking a `Text` with `Modifier.padding(horizontal = 10.dp)`. Apply `Modifier.padding(top = 16.dp, bottom = 8.dp)` on the row for **vertical-insets**. Format the date with `java.time.format.DateTimeFormatter` using the equivalent full-weekday/full-month pattern (matching **day-text-rendered**). Source divider and caption-text colors from the same custom `CompositionLocal` palette holder documented at `agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view#platforms/compose`, not Material 3's own color roles.

- **React/Web**: Render a flex container (`display: flex; align-items: center`) with two `<div>` "rule" elements using `flex: 1` (so they share remaining width equally) around a centered `<span>` for the date text, each rule separated from the text by `margin: 0 10px`. Apply `padding-top: 16px; padding-bottom: 8px` on the container. Format the date string with `Intl.DateTimeFormat(locale, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })`, the web equivalent of the shared day-format pattern in **day-text-rendered**, and drive the rule/text colors from CSS custom properties tied to the active theme, updating on a theme-class change on the root element.

- **AppKit / UIKit**: Source: `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatDayBannerView.swift`. Implemented as a `@MainActor`, `final` `NSView` subclass using `NSTextField(labelWithString:)` for the label and two plain `NSView`s (`wantsLayer = true`) as the rule lines, laid out entirely with `NSLayoutConstraint.activate` (no explicit priorities — see Design Decisions and the unresolved gap noted under Edge Cases), centering the label by pinning `label.centerXAnchor` to the view's own `centerXAnchor` (see **label-centered**). The label's text comes from the private `AIChatBubbleView.dayFormatter` (`EEEE, MMMM d yyyy`), shared with that view's inline-timestamp banner — see **day-text-rendered**. Theme changes are observed via `observeTheme { banner, palette in banner.apply(palette) }`, the same pattern documented at `agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view#platforms/appkit-uikit`. This file targets macOS only — it lives under `macOS/Features` and uses `NSView`/`NSTextField`, which have no direct UIKit equivalent in this source; an iOS port would substitute `UILabel` and two plain `UIView`s for the rules, driven by the equivalent `NSLayoutConstraint` (UIKit) relationships, and would need its own theme-observation hook (iOS message bubbles use `MobileMessageBubbleView` for that role).

- **WinUI 3**: Use a `Grid` with three columns defined `*, Auto, *` so the two flanking columns share remaining width equally — the WinUI analogue of **rules-equal-width** — placing a `Rectangle` (or a `Border` with `Height="1"`, `VerticalAlignment="Center"`) in column 0 and column 2, and a `TextBlock` in column 1 with `Margin="10,0,10,0"` for the 10pt gap on each side. Set `Margin="0,16,0,8"` on the root `Grid` for **vertical-insets**. Bind `TextBlock.Text` to a day-formatted string using the equivalent long-weekday/long-month pattern (matching **day-text-rendered**), and bind `Rectangle.Fill`/`TextBlock.Foreground` to theme resource-dictionary entries for the divider and timestamp-text roles, updating them when the app's theme dictionary swaps (WinUI has no live palette-observer callback, so this typically means re-evaluating `ThemeResource` bindings on a theme-changed event). Set `AutomationProperties.Name` on the root `Grid` to the date text (or mark the two `Rectangle`s `AutomationProperties.AccessibilityView="Raw"`) so Narrator reaches a single static-text element, mirroring **static-text-role**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatDayBannerView.swift` |

## Design Decisions

**Decision**: The date banner renders its text using `AIChatBubbleView.dayFormatter` rather than owning its own `DateFormatter`.
**Rationale**: Keeps the date shown at the top of each day consistent with whatever format the message-timestamp UI uses elsewhere in the chat transcript, and centralizes locale/calendar formatting policy in one place. This recipe therefore does not itself define the exact format pattern, locale rules, or calendar system used beyond the pattern `EEEE, MMMM d yyyy` — the only evidence available is the class's own doc-comment example, which itself misstates the weekday for June 3, 2026 as "Saturday" (June 3, 2026 is in fact a Wednesday); this recipe corrects the example to "Wednesday, June 3 2026" everywhere it is quoted.
**Approved: pending**

**Decision**: The `day` value is normalized to `calendar.startOfDay(for:)` at construction time, rather than stored as the raw `Date` the caller passed in.
**Rationale**: Two messages posted at different times on the same calendar day must produce the same banner. Normalizing once at init — using an injectable `calendar` that defaults to `.current` — keeps the day-boundary decision testable, letting a test pin the time zone that decides which side of midnight an instant falls on, per the initializer's own doc comment.
**Approved: pending**

**Decision**: The two rule lines are constrained to equal width to each other, rather than each being pinned with a fixed margin from the view's own edges.
**Rationale**: Keeps the date label on the view's horizontal center line regardless of how wide the formatted date string is — per the source comment, the rules are "equal to each other rather than each pinned to a margin, which is what keeps the date itself on the centre line whatever it says." No priority is set on this constraint pair, which is the source of the open question on **rule-width-priority** for very long date text.
**Approved: pending**

**Decision**: Vertical spacing around the label is asymmetric — 16pt above, 8pt below.
**Rationale**: Per the source's doc comment, "the gap is what separates yesterday's last message from today's first, and it belongs to the break, not to the day it opens" — more space is reserved above the banner than below it so the visual break reads as belonging to the transition between days, not to the day being announced.
**Approved: pending**

**Decision**: `init(coder:)` is marked `@available(*, unavailable)` and calls `fatalError()` if reached.
**Rationale**: The view is only ever meant to be constructed programmatically with a `day` (and optional `calendar`); Interface Builder/storyboard unarchiving has no way to supply those parameters, so the source forecloses that construction path entirely rather than leaving it partially working.
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [locale-aware-formatting](agenticdevelopercookbook://compliance/internationalization#locale-aware-formatting) | partial | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | partial | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |

Statuses rest on: the explicit `.staticText` accessibility role and accessibility label on the container, though the child `NSTextField` is never excluded from the accessibility tree (no `setAccessibilityElement(false)` call in source) and carries its own accessibility label too, so whether VoiceOver announces the banner as one merged element or as the container plus a separate label is not resolved by this source (screen-reader-support, semantic-markup); the label's font and color being resolved entirely from the active `SemanticPalette`, which this source neither defines nor can verify for contrast or Dynamic Type scaling (contrast-ratio, dynamic-type-support); the rendered date string being fully delegated to the shared day-formatting pattern named in **day-text-rendered** (see the AppKit/UIKit Platform Note), whose locale/calendar behavior is not in this source (locale-aware-formatting); the component rendering arbitrary caller-provided Unicode text (via the formatter's output) without special-casing (unicode-support); the absence of any literal user-facing string in this file — the accessibility identifier `chat-day-banner` is an internal test hook, not user-facing text (no-hardcoded-strings); the label's single-line, non-wrapping default with no truncation configured, which narrows the rule lines for a long date but has an undefined limit (text-expansion-tolerance, see the open question on rule-width-priority); the layout using `leadingAnchor`/`trailingAnchor` (logical, RTL-aware) throughout rather than fixed left/right anchors (rtl-layout-support); and the `observeTheme` registration that recolors the label and rules on every theme change (platform-theming).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial creation from the macOS/AppKit source (ChatDayBannerView.swift) |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: fixed related/depends-on to cite this repo's AI chat bubble recipe instead of ADT's, corrected the "Saturday" day-formatting example to "Wednesday" throughout, pinned the calendar to a fixed time zone in the non-deterministic test vectors, moved AppKit-private identifiers out of requirements into the AppKit/UIKit Platform Note, replaced named cross-recipe citations with domain URLs, named concrete Compose/web date-formatting equivalents, and downgraded screen-reader-support/semantic-markup to partial pending resolution of the label's accessibility-tree exposure |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
