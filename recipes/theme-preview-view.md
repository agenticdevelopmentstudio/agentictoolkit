---
id: 15e66a2e-9ee1-4f5f-aeb0-c804078b4f78
title: ThemePreviewView
domain: agentictoolkit://recipes/theme-preview-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS settings NSView that renders a live sample of a ColorTheme as real
  app chrome - window, sidebar, controls, status badges, ANSI swatches and a terminal.
platforms:
- swift
- macos
tags:
- settings
- theme
- preview
- macos
- appkit
depends-on:
- agentictoolkit://recipes/swatch-grid-view
related:
- agentictoolkit://recipes/swatch-grid-view
- agentictoolkit://recipes/badge
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# ThemePreviewView

## Overview

`ComposableSettings.ThemePreviewView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePreviewView.swift`,
is an AppKit `NSView` (`@MainActor`, conforming to `SettingsViewProtocol`) that
answers "what will this theme look like?" without switching to it first. Per
its doc comment, it is a live sample of a `ColorTheme` drawn as the app's own
UI rather than as a row of color chips: window chrome and type, a sidebar with
a selected row, form controls, status badges, the 16 ANSI swatches, and a
terminal that honors the theme's terminal font, padding and cursor overrides.
Every sample is built from a real component's shape — a list row really is a
rounded selection fill under `selectionText`, a badge really is
`success`/`warning`/`danger`/`info` — so the preview exercises the same
`SemanticPalette` role lookups the rest of the app uses, rather than a
parallel, idealized set of demo colors.

The view starts empty; calling `show(_:)` with a `ColorTheme` resolves a
`SemanticPalette(theme:)` and fully rebuilds five sample cards (chrome, list,
sidebar tabs, controls, status badges, terminal) plus an embedded
`ComposableSettings.SwatchGridView` of the theme's 16 ANSI colors. It composes
the sibling `SwatchGridView` ingredient directly rather than re-implementing a
swatch grid, but implements its own private, structurally similar "badge"
capsule for the status row rather than reusing the shared `Badge` ingredient
(see Design Decisions).

## Behavioral Requirements

- **pins-container-to-self**: Component MUST maintain a single vertical
  `NSStackView` (`container`, leading-aligned, 10pt spacing) as its only direct
  subview, pinned to all four edges of `self` with no additional constant, via
  `Self.pinToEdges`.
- **starts-empty-without-theme**: Component MUST NOT add any content to
  `container` when constructed via `init(theme:)` with the default `nil`
  argument; content appears only once `show(_:)` is called.
- **traps-on-coder-init**: Component MUST NOT support construction via
  `init(coder:)`; that initializer MUST trigger a fatal error.
- **clears-and-rebuilds-on-each-show**: On every call to `show(_:)`, the
  component MUST remove every existing arranged subview from `container`
  (`arrangedSubviews.forEach { $0.removeFromSuperview() }`) before adding the
  new set of sample cards, rather than diffing or reusing any existing card.
- **paints-self-with-window-background**: On every call to `show(_:)`, the
  component MUST set its own `wantsLayer`-backed background color to the
  resolved `SemanticPalette`'s `windowBackground` role color.
- **renders-cards-in-fixed-order**: `show(_:)` MUST append exactly six items to
  `container`, in this fixed order: the chrome sample, the list sample, the
  controls sample, the status sample, the terminal sample, then the ANSI
  swatch grid.
- **stretches-sample-cards-to-container-width**: The component MUST activate a
  width constraint equal to `container`'s width on each of the five sample
  cards (chrome, list, controls, status, terminal), so that the
  leading-aligned, content-sized stack view does not let them collapse to
  their intrinsic content width.
- **constrains-cards-to-minimum-width**: Each of the four cards built through
  the shared `fill(_:with:)` helper (chrome, list, controls, status) and the
  terminal sample's box MUST each carry an activated
  `widthAnchor >= 280` constraint, independent of their content.
- **insets-card-content-consistently**: The `fill(_:with:)` helper used by the
  chrome, list, controls and status cards MUST inset its vertical content
  stack from the card by exactly 10pt from the top, 12pt from the leading
  edge, and 10pt from the bottom, and MUST constrain the trailing edge to at
  most 12pt from the card's trailing edge (the content may be narrower, never
  wider).
- **renders-chrome-title**: The chrome sample MUST include a label reading
  "Window Title" in the `primaryText` color and the `title` text style.
- **renders-chrome-body-and-caption**: The chrome sample MUST include a body
  label reading "Body text in the body font." in `primaryText`/`body` style,
  and a caption label reading "Secondary caption text" in
  `secondaryText`/`caption` style.
- **renders-chrome-controls-row**: The chrome sample MUST include a horizontal
  row (8pt spacing) of two pill-shaped controls, both set in the `button` text
  style: a "Button" pill filled with `accent` and text colored
  `onAccentText`, and a "Selected" pill filled with `selection` and text
  colored `selectionText`.
- **renders-chrome-divider**: The chrome sample MUST include a 1pt-tall
  hairline view filled with the `divider` role color, constrained to the
  card's width minus 24pt.
- **renders-chrome-outlined-panel**: The chrome sample MUST include an inner
  rounded (8pt corner radius) panel filled with `elevatedSurface`, with a 1pt
  border in the `outline` role color, containing a caption-styled label
  reading "Panel · outline" in `tertiaryText`, constrained to the card's width
  minus 24pt.
- **renders-tab-strip**: The list sample MUST render a horizontal row (4pt
  spacing) of three pills in the `button` text style: "Notes" filled with
  `elevatedSurface` and text in `primaryText`, and "Chat" and "Terminal" each
  filled with `surface` and text in `secondaryText`.
- **renders-three-list-rows**: The list sample MUST render exactly three rows,
  in this order: ("Release notes", "Yesterday", unselected), ("Design
  review", "2 days ago", selected), ("Scratch", "Last week", unselected).
- **styles-selected-list-row**: A selected list row MUST fill its background
  with the `selection` role color (5pt corner radius) and render both its
  title and detail text in `selectionText`.
- **styles-unselected-list-row**: An unselected list row MUST leave its
  background transparent and render its title in `primaryText` and its detail
  text in `tertiaryText`.
- **lays-out-list-row-content**: Each list row MUST place its title label
  leading-aligned with an 8pt inset and its detail label trailing-aligned with
  an 8pt inset, both vertically centered, with the detail label's leading edge
  held at least 8pt from the title label's trailing edge.
- **renders-two-equal-width-text-fields**: The controls sample MUST render two
  side-by-side, equal-width (`fillEqually`, 8pt spacing) simulated text
  fields, each a 5pt-corner-radius box filled with `controlBackground` and
  outlined with a 1pt `border`-colored stroke: one showing "Typed text" in
  `primaryText`, the other showing "Placeholder" in `placeholderText`.
- **renders-checkbox-sample-line**: The controls sample MUST render a single
  line of text reading "☑︎ Enabled    ☐ Disabled" in `secondaryText`/`body`
  style, as a static representation of a checkbox's checked and unchecked
  appearance.
- **renders-four-status-badges**: The status sample MUST render exactly four
  badges, in this order and color: "Success" (`success`), "Warning"
  (`warning`), "Error" (`danger`), "Info" (`info`), in a horizontal row with
  6pt spacing.
- **styles-status-badge**: Each status badge MUST be a 5pt-corner-radius
  capsule whose background is its status color at 22% alpha, whose border is
  the same status color at 55% alpha (1pt), and whose text is the same status
  color at full opacity in the `caption` text style.
- **renders-terminal-box-on-window-background**: The terminal sample's box
  MUST be filled with the `windowBackground` role color (unlike the other four
  cards, which use `surface`) and outlined with a 1pt `border`-colored stroke.
- **resolves-terminal-appearance-from-theme**: The terminal sample MUST
  resolve its font, padding and cursor shape by calling
  `TerminalAppearance.resolvedFont(theme:)`, `resolvedPadding(theme:)` and
  `resolvedCursor(theme:)` — the same resolution a live terminal session
  uses — rather than hardcoding any of the three.
- **renders-terminal-sample-content**: Using the resolved terminal font, the
  terminal sample MUST render a prompt line reading "user@mac ~ % ls" in
  `primaryText` followed immediately by the caret, and a second line (2pt
  below the first) of "Documents" in `accent` and "README.md" in
  `secondaryText`, 10pt apart.
- **insets-terminal-content-by-resolved-padding**: The terminal sample MUST
  inset its content stack from the box's top, leading and bottom edges by
  exactly the theme's resolved terminal padding on that side, and MUST
  constrain the trailing edge to at most the box's trailing edge minus the
  resolved trailing padding.
- **draws-cursor-shape**: The terminal sample MUST render a one-cell caret,
  sized off the resolved font (width = `max(font.pointSize * 0.6, 5)`, height
  = `font.pointSize + 3`, except height 2 for `.underline` and width 2 for
  `.bar`), filled or outlined with the `cursor` role color, in the shape given
  by the resolved `TerminalCursorShape` (`.block` filled, `.hollowBlock`
  1pt-bordered, `.underline` a 2pt-tall bar, `.bar` a 2pt-wide bar).
- **renders-swatch-grid-of-ansi-colors**: `show(_:)` MUST construct and append
  a `ComposableSettings.SwatchGridView` populated with the resolved palette's
  16 `ansiColors`, at 8 columns, as the final item in `container`.
- **derives-appearance-entirely-from-semantic-palette**: Every color and font
  value the five sample cards use MUST come from a single
  `SemanticPalette(theme:)` constructed once at the top of `show(_:)`, read
  through its role-based `color(_:)`/`nsColor(_:)`/`font(_:)` API — never a
  raw, theme-independent color or font literal.

## Appearance

- **Corner radius**: `self` has none. Every sample card box (`roundedBox`) has
  an 8pt corner radius. The controls sample's two simulated text fields
  override this to 5pt. List rows and status badges use 5pt. ANSI swatches
  (in the embedded `SwatchGridView`) use 3pt — see that recipe.
- **Padding**: Card content is inset 10pt top / 12pt leading / ≤12pt trailing
  (may be narrower) / 10pt bottom, per `insets-card-content-consistently`. The
  terminal sample instead insets by the theme's resolved terminal padding
  (default 10pt on all four sides, per `TerminalAppearance`/`UserSettings`
  defaults) rather than the fixed 10/12/12/10 shape.
- **Font**: `title`, `body`, `caption` and `button` `TextRole` styles from
  `theme.typography`, resolved via `palette.font(_:)`. The terminal sample
  uses the theme's resolved monospaced terminal font
  (`TerminalAppearance.resolvedFont(theme:)`) instead of any `TextRole`.
- **Background**: `self` — the theme's `windowBackground`. Chrome, list,
  controls and status cards — `surface`. The terminal card —
  `windowBackground` (see `renders-terminal-box-on-window-background`). The
  chrome sample's inner panel — `elevatedSurface`. Text field simulations —
  `controlBackground`. Status badges — their status color at 22% alpha.
- **Foreground/Text**: Role-specific per element — `primaryText`,
  `secondaryText`, `tertiaryText`, `placeholderText`, `onAccentText`,
  `selectionText`, `accent`, and the four status colors — as itemized in
  Behavioral Requirements.
- **Border**: The chrome sample's inner panel — 1pt, `outline`. The controls
  sample's two text-field simulations — 1pt, `border`. The terminal sample's
  box — 1pt, `border`. Status badges — 1pt, their status color at 55% alpha.
  No border on `self`, `container`, any card's outer box, or list rows/pills.
- **Shadow**: Not applicable — no `NSShadow`, `shadowOpacity`, or similar
  layer-shadow property is set anywhere in `ThemePreviewView.swift`.
- **Min/Max size**: Every card box (via `fill(_:with:)`) and the terminal
  box each carry a `widthAnchor >= 280` constraint; `self` and `container`
  have no explicit min/max size of their own — the view's overall size is
  driven by its arranged content plus whatever constraints a host applies to
  `self`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Before `show(_:)` is called, `container` is empty and `self` has no background paint (`starts-empty-without-theme`). After `show(_:)`, the view fully repaints as described in Overview/Behavioral Requirements; calling `show(_:)` again with a different (or the same) theme tears down and rebuilds every card from that theme. |
| Pressed | Not applicable: no `NSControl`, target-action, or click-handling code exists anywhere in `ThemePreviewView.swift`; every element (boxes, pills, rows, badges, the caret) is a plain, non-interactive `NSView`/`NSStackView`/`NSTextField(labelWithString:)`. |
| Disabled | Not applicable: `isEnabled` is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no `NSControl`, so it never becomes first responder or shows a focus ring. |
| Loading | Not applicable: `show(_:)` and every `make*Sample` helper it calls are synchronous, non-throwing property assignments and view constructions; there is no asynchronous operation and no loading indicator anywhere in source. |

## Accessibility

- **Role/trait**: Every `NSTextField(labelWithString:)` label exposes itself
  to VoiceOver as static text by AppKit's own default; no other view (`box`,
  `pill`, `badge`, `row`, the caret, the hairline) has `setAccessibilityRole`,
  `setAccessibilityElement`, or any similar call anywhere in
  `ThemePreviewView.swift`, so none of those containers expose a semantic
  grouping of their own. NEEDS REVIEW: Not implemented in source. Behavior
  undefined. Whether the whole preview, or each sample card, should be
  grouped as a single accessibility element with a summarizing label — versus
  leaving VoiceOver to read roughly twenty individual demo labels one at a
  time with no indication they belong to a "theme preview" rather than live
  application state — is undefined. What would settle it: a VoiceOver pass
  over an instantiated `ThemePreviewView`, or an explicit grouping decision.
- **Label requirements**: All visible text is the literal English demo
  strings itemized in Behavioral Requirements (see also Localization); no
  `accessibilityLabel`/`accessibilityValue` override is set anywhere, so
  VoiceOver reads exactly that literal text. NEEDS REVIEW: Not implemented in
  source. Behavior undefined. Nothing distinguishes illustrative sample text
  ("Window Title", "Success", "Documents") from a real value a user could act
  on; what would settle it is the same grouping/labeling decision named above.
- **Announce state changes**: Not applicable — `show(_:)` is the only
  mutating entry point, runs synchronously to completion on the main actor,
  and there is no loading indicator or asynchronous transition to announce
  (see States/Loading).
- **Minimum tap target**: Not applicable — this is a macOS, pointer/trackpad
  composition with no interactive element anywhere in source (see
  States/Pressed), so there is no touch target to size. The embedded
  `SwatchGridView`'s own accessibility posture is documented in its own
  recipe (`agentictoolkit://recipes/swatch-grid-view`), not repeated here.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-preview-view-001 | pins-container-to-self | Construct the view and inspect its subviews/constraints | `self` has exactly one direct subview, `container`, whose top/leading/trailing/bottom anchors equal `self`'s with no constant |
| theme-preview-view-002 | starts-empty-without-theme | `ThemePreviewView()` (no `theme` argument) | `container.arrangedSubviews` is empty and `self.layer?.backgroundColor` is unset |
| theme-preview-view-003 | traps-on-coder-init | Attempt `ThemePreviewView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| theme-preview-view-004 | clears-and-rebuilds-on-each-show | Call `show(themeA)`, note the 6 arranged subviews, then call `show(themeB)` | None of the original 6 subview instances remain in `container`; a fresh 6 are present |
| theme-preview-view-005 | paints-self-with-window-background | Call `show(theme)` | `self.layer?.backgroundColor == SemanticPalette(theme: theme).nsColor(.windowBackground).cgColor` |
| theme-preview-view-006 | renders-cards-in-fixed-order | Call `show(theme)` and inspect `container.arrangedSubviews` | Exactly 6 items, in order: chrome, list, controls, status, terminal, swatch grid |
| theme-preview-view-007 | stretches-sample-cards-to-container-width | Call `show(theme)` inside a wide host and inspect constraints | Each of the first 5 arranged subviews has an active `widthAnchor == container.widthAnchor` constraint |
| theme-preview-view-008 | constrains-cards-to-minimum-width | Call `show(theme)` and inspect constraints on each of the 5 sample-card boxes | Each has an active `widthAnchor >= 280` constraint |
| theme-preview-view-009 | insets-card-content-consistently | Inspect the chrome card's content-stack constraints after `show(theme)` | Top offset 10, leading offset 12, bottom offset -10, trailing constrained `lessThanOrEqualTo` -12 |
| theme-preview-view-010 | renders-chrome-title | Call `show(theme)` and read the chrome card's first label | Text is "Window Title", color equals `palette.nsColor(.primaryText)`, font equals `palette.font(.title)` |
| theme-preview-view-011 | renders-chrome-body-and-caption | Read the chrome card's second and third labels | "Body text in the body font." in `primaryText`/`body`; "Secondary caption text" in `secondaryText`/`caption` |
| theme-preview-view-012 | renders-chrome-controls-row | Read the chrome card's controls row | Two pills, "Button" (fill `accent`, text `onAccentText`) and "Selected" (fill `selection`, text `selectionText`), both `button` font, row spacing 8 |
| theme-preview-view-013 | renders-chrome-divider | Inspect the chrome card's hairline view | Height constraint == 1, background color == `palette.nsColor(.divider)`, width == card width - 24 |
| theme-preview-view-014 | renders-chrome-outlined-panel | Inspect the chrome card's inner panel | 8pt corner radius, fill `elevatedSurface`, 1pt border `outline`, containing a "Panel · outline" label in `tertiaryText`/`caption` |
| theme-preview-view-015 | renders-tab-strip | Read the list card's tab row | Three pills "Notes"/"Chat"/"Terminal"; "Notes" fill `elevatedSurface` text `primaryText`, the other two fill `surface` text `secondaryText`; 4pt spacing |
| theme-preview-view-016 | renders-three-list-rows | Read the list card's rows in order | ("Release notes","Yesterday",unselected), ("Design review","2 days ago",selected), ("Scratch","Last week",unselected) |
| theme-preview-view-017 | styles-selected-list-row | Inspect the "Design review" row | Background `selection`, 5pt corner radius, both labels colored `selectionText` |
| theme-preview-view-018 | styles-unselected-list-row | Inspect the "Release notes" row | Background transparent, title `primaryText`, detail `tertiaryText` |
| theme-preview-view-019 | lays-out-list-row-content | Inspect any row's label constraints | Title leading offset 8, detail trailing offset -8, both centered vertically, detail's leading >= title's trailing + 8 |
| theme-preview-view-020 | renders-two-equal-width-text-fields | Read the controls card's two fields | "Typed text" in `primaryText`, "Placeholder" in `placeholderText`; both `controlBackground` fill, 5pt corner radius, 1pt `border` outline, equal width, 8pt spacing |
| theme-preview-view-021 | renders-checkbox-sample-line | Read the controls card's third element | Text "☑︎ Enabled    ☐ Disabled", color `secondaryText`, font `body` |
| theme-preview-view-022 | renders-four-status-badges | Read the status card's badges in order | "Success"(`success`), "Warning"(`warning`), "Error"(`danger`), "Info"(`info`); row spacing 6 |
| theme-preview-view-023 | styles-status-badge | Inspect the "Success" badge's layer | 5pt corner radius, background = `success` at 22% alpha, border 1pt = `success` at 55% alpha, text = `success` at full opacity, `caption` font |
| theme-preview-view-024 | renders-terminal-box-on-window-background | Inspect the terminal card's box | Fill = `palette.nsColor(.windowBackground)`, 1pt border = `palette.nsColor(.border)` |
| theme-preview-view-025 | resolves-terminal-appearance-from-theme | Call `show(theme)` where `theme.terminal` overrides font/padding/cursor | The terminal sample's font, insets, and caret shape match `TerminalAppearance.resolvedFont/resolvedPadding/resolvedCursor(theme:)`, not the `UserSettings` defaults |
| theme-preview-view-026 | renders-terminal-sample-content | Read the terminal card's content | Line 1: "user@mac ~ % ls" (`primaryText`) + caret; line 2: "Documents" (`accent`) and "README.md" (`secondaryText`), 10pt apart, 2pt below line 1 |
| theme-preview-view-027 | insets-terminal-content-by-resolved-padding | Set a theme with `terminal.paddingLeading = 40` and call `show(theme)` | The terminal content stack's leading offset from the box is 40, not the 10pt default |
| theme-preview-view-028 | draws-cursor-shape | Set `theme.terminal.cursorShape = .bar` and call `show(theme)` | The caret view is 2pt wide, full cell height, filled with `palette.nsColor(.cursor)` |
| theme-preview-view-029 | renders-swatch-grid-of-ansi-colors | Call `show(theme)` and inspect the 6th arranged subview | It is a `ComposableSettings.SwatchGridView` constructed with `palette.ansiColors` (16 colors) and `columns: 8` |
| theme-preview-view-030 | derives-appearance-entirely-from-semantic-palette | Call `show(themeA)` then `show(themeB)` with two themes differing only in `roleOverrides` | Every sample-card color changes to match `themeB`'s resolved `SemanticPalette`; no color remains fixed across the two calls |

## Edge Cases

- Null/empty input: `theme` defaults to `nil` in `init(theme:)`. When `nil`,
  `container` remains empty and `self`'s background is never painted until
  `show(_:)` is called explicitly with a concrete `ColorTheme` — this is a
  MUST (`starts-empty-without-theme`), not a crash or a placeholder theme.
- Boundary values — repeated/idempotent `show(_:)`: calling `show(_:)`
  multiple times, including twice with the same theme, produces the same
  visual result each time because every call tears down all existing
  arranged subviews before rebuilding (`clears-and-rebuilds-on-each-show`).
  This is a MUST, traceable to the unconditional
  `arrangedSubviews.forEach { $0.removeFromSuperview() }` at the top of
  `show(_:)`.
- Boundary values — long or narrow content: cards are forced to exactly
  `container`'s width (`stretches-sample-cards-to-container-width`), but no
  label anywhere in `ThemePreviewView.swift` sets `lineBreakMode`,
  `maximumNumberOfLines`, or `usesSingleLineMode` — every label is a plain
  `NSTextField(labelWithString:)` left at its AppKit default. In a very
  narrow host, or with a theme whose typography scale enlarges text
  substantially, list-row detail labels, badge text, or the chrome sample's
  content (whose stack is only `lessThanOrEqualTo`-constrained on its
  trailing edge, per `insets-card-content-consistently`) can be clipped or
  compressed rather than reflowed; this is a SHOULD-level design gap the
  source does not otherwise handle, and is captured for completeness though
  it does not rise to an open question because the label defaults themselves
  are unambiguous AppKit behavior, not an unresolved question.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated, so
  Swift's concurrency checker serializes every call to `show(_:)` and every
  private `make*Sample` helper; there is no code path by which two threads
  mutate `container` simultaneously.
- Error states: Not applicable — every operation in `show(_:)` and its
  helpers is a synchronous, non-throwing property assignment or view
  construction. `TerminalAppearance.resolvedFont(theme:)`,
  `resolvedPadding(theme:)` and `resolvedCursor(theme:)` are non-throwing,
  total functions over `theme` and `UserSettings` defaults (verified in
  `TerminalAppearance.swift`) and always resolve to a concrete value; no
  `try`, `Result`, or optional is propagated to `ThemePreviewView` from any
  of them.
- Offline/disconnected state: Not applicable — the component performs no
  networking of its own; it only renders values resolved from the supplied
  `ColorTheme` and local `UserSettings` defaults.
- Quirk — swatch grid excluded from the width stretch: `show(_:)` activates
  the `widthAnchor == container.widthAnchor` constraint only over the `cards`
  array (the five sample boxes); the `SwatchGridView` appended afterward is
  never included in that `.map`, so it is left at its own content-driven
  width. With the hardcoded `columns: 8` and exactly 16 ANSI colors this
  always renders two full rows regardless, so the omission has no visible
  effect today, but it is a documented, source-traceable asymmetry rather
  than something this recipe assumes is intentional design.
- Quirk — chrome sample's divider/inner-panel width constraints reference
  the outer `box`: `fill(box, with: [...])` returns the same `box` instance
  it was given (not a wrapper), which is what lets
  `divider.widthAnchor.constraint(equalTo: box.widthAnchor, constant: -24)`
  and the equivalent `inner` constraint — both activated *after* `fill(...)`
  returns — resolve correctly against the final card width.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `theme` | `ColorTheme?` | `nil` | Passed to `init(theme:)`; when non-nil, `show(_:)` is called immediately during initialization. When `nil`, the view starts empty (`starts-empty-without-theme`). |

The only other entry point is the public method `show(_ theme: ColorTheme)`,
which fully tears down and rebuilds the preview for a new theme (see
Behavioral Requirements); it is not an initializer option and so is
documented there rather than in this table.

## Deep Linking

Not applicable: `ThemePreviewView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `ThemePreviewView.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `theme_preview.chrome.title` | Window Title | Chrome sample's title label |
| `theme_preview.chrome.body` | Body text in the body font. | Chrome sample's body label |
| `theme_preview.chrome.caption` | Secondary caption text | Chrome sample's caption label |
| `theme_preview.chrome.button` | Button | Chrome sample's accent-filled pill |
| `theme_preview.chrome.selected` | Selected | Chrome sample's selection-filled pill |
| `theme_preview.chrome.panel_caption` | Panel · outline | Chrome sample's outlined inner panel |
| `theme_preview.list.tab_notes` | Notes | List sample's first tab |
| `theme_preview.list.tab_chat` | Chat | List sample's second tab |
| `theme_preview.list.tab_terminal` | Terminal | List sample's third tab |
| `theme_preview.list.row1_title` / `row1_detail` | Release notes / Yesterday | List sample's first row |
| `theme_preview.list.row2_title` / `row2_detail` | Design review / 2 days ago | List sample's selected row |
| `theme_preview.list.row3_title` / `row3_detail` | Scratch / Last week | List sample's third row |
| `theme_preview.controls.typed` | Typed text | Controls sample's filled field |
| `theme_preview.controls.placeholder` | Placeholder | Controls sample's placeholder field |
| `theme_preview.controls.checkbox_line` | ☑︎ Enabled    ☐ Disabled | Controls sample's checkbox line |
| `theme_preview.status.success` / `warning` / `error` / `info` | Success / Warning / Error / Info | Status sample's four badges |
| `theme_preview.terminal.prompt` | user@mac ~ % ls | Terminal sample's prompt line |
| `theme_preview.terminal.dir` | Documents | Terminal sample's directory entry |
| `theme_preview.terminal.file` | README.md | Terminal sample's file entry |

NEEDS REVIEW: Not implemented in source. Behavior undefined. Every string
above is a literal passed to `NSTextField(labelWithString:)` (an AppKit
`stringValue` set from a literal, not SwiftUI's `Text`/`LocalizedStringKey`),
and none of it is routed through `NSLocalizedString` or any localization
table anywhere in `ThemePreviewView.swift`. Because these strings are
themselves illustrative demo content rather than data the app produces, it is
an open question whether they should be localized like real UI text or
intentionally left as an English-only illustrative sample; either way source
gives no localization path today. What would settle it: a decision on
whether the theme-preview demo content is localized, and if so, a pass
replacing each literal with `NSLocalizedString` and a corresponding
`.strings`/String Catalog entry per the key above.

## Accessibility Options

- **Reduce Motion**: Not applicable — `show(_:)` and every `make*Sample`
  helper perform an instantaneous full teardown and rebuild
  (`removeFromSuperview()`/`addArrangedSubview(_:)`); no `NSAnimationContext`,
  animator proxy, or transition of any kind appears anywhere in
  `ThemePreviewView.swift`, so there is no motion for Reduce Motion to
  substitute for.
- **Increase Contrast**: Not applicable at this component's own level — every
  color is read through `SemanticPalette`'s role API
  (`derives-appearance-entirely-from-semantic-palette`); `ThemePreviewView`
  itself contains no separate Increase Contrast branch, so it inherits
  whatever contrast behavior the active `SemanticPalette`/theme provides
  without any code of its own to adjust.
- **Differentiate Without Color**: Supported for the status sample — each of
  the four badges pairs its status color with an explicit text label
  ("Success"/"Warning"/"Error"/"Info"), so status is never conveyed by hue
  alone (contrast this with the embedded `SwatchGridView`'s raw color
  swatches, which carry no label — see that recipe's own note). The chrome
  sample's "Button" vs. "Selected" pills are likewise distinguished by their
  own text, not color alone.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `ThemePreviewView.swift`; the preview always renders once `show(_:)` is
called.

## Analytics

Not applicable: `ThemePreviewView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only renders the `ColorTheme` value it is given.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; `TerminalAppearance`'s fallback to
  `UserSettings` is a read-only lookup for its own defaults.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains the resolved
  `SemanticPalette` and its own subviews only for its own lifetime; it
  persists nothing beyond that.

## Logging

Not applicable: `ThemePreviewView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose a `VStack(spacing: 10)` of five card `View`s (each a
  `RoundedRectangle(cornerRadius: 8).fill(...)` background with a `VStack`
  of its own content, `.frame(minWidth: 280, maxWidth: .infinity)`) followed
  by a swatch grid (`LazyVGrid`), all reading colors and fonts from an
  `@Environment` or `@ObservedObject` wrapping the same `SemanticPalette`
  role API this source uses, so a theme change recomposes every sample the
  same way `show(_:)` rebuilds it.
- **Compose**: A `Column` of `Card` composables (`Modifier.fillMaxWidth()`,
  `Modifier.widthIn(min = 280.dp)`, `shape = RoundedCornerShape(8.dp)`,
  `backgroundColor` bound to the theme role), each containing a `Column`/`Row`
  of `Text`/`Box` elements styled from `MaterialTheme.colors`/`typography`
  mapped from the same semantic roles, plus a `LazyVerticalGrid` for the
  ANSI swatches (see the `SwatchGridView` recipe's own Compose note).
- **React/Web**: A flex column of five `<div class="card">` blocks (
  `border-radius: 8px`, `min-width: 280px`, `width: 100%`, background from a
  `--surface`/`--window-background` CSS custom property) each laid out with
  `padding: 10px 12px`, followed by a CSS Grid of ANSI swatches (`gap` and
  `grid-template-columns: repeat(8, ...)`, mirroring the `SwatchGridView`
  recipe). All colors and fonts bind to the same theme custom properties the
  rest of the web app's theme system exposes, so the preview updates
  reactively on a theme change exactly as `show(_:)` does imperatively here.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePreviewView.swift`.
  A macOS-only (`import AppKit`), `@MainActor` `NSView` subclass in the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes a single vertical `NSStackView` of five hand-built card views
  (each an `NSView` with a `CALayer` background, built from nested
  `NSStackView`s of `NSTextField(labelWithString:)` labels and plain
  layer-backed `NSView`s for pills/badges/rows/the caret) plus one embedded
  `ComposableSettings.SwatchGridView`. There is no UIKit code path in
  source; a UIKit port has no direct `NSStackView`-of-cards equivalent and
  would instead compose a vertical `UIStackView` of card `UIView`s (each
  `layer.cornerRadius`/`backgroundColor` styled the same way), with
  `UILabel`s in place of `NSTextField(labelWithString:)` and the same
  `SwatchGridView`-equivalent grid embedded at the end.
- **WinUI 3** (the reason this recipe exists): Compose a vertical
  `StackPanel` (`Spacing="10"`) of five `Border` "card" elements
  (`CornerRadius="8"`, `MinWidth="280"`, `HorizontalAlignment="Stretch"`,
  `Background` bound to a `{ThemeResource}` brush that mirrors the
  corresponding semantic role — e.g. `CardBackgroundFillColorDefaultBrush`
  for `surface`, `LayerFillColorDefaultBrush` for `elevatedSurface`), each
  containing a `StackPanel` of `TextBlock`/`Border` children styled per the
  requirements above (a "pill" is a `Border` with `CornerRadius="5"` around a
  `TextBlock`; a status badge is the same shape with its `Background`/
  `BorderBrush` bound through a converter to the status color at 22%/55%
  opacity). Terminal padding maps to the `Border`'s `Padding` property bound
  directly to the four resolved padding values; the caret maps to a small
  `Border`/`Rectangle` whose `Width`/`Height`/`CornerRadius`/fill-vs-outline
  are chosen from a `VisualStateManager` group with one state per
  `TerminalCursorShape` case (Block/HollowBlock/Underline/Bar), each setter
  matching the width/height math in `draws-cursor-shape`. The ANSI swatch
  grid maps to an `ItemsRepeater` with a `UniformGridLayout`, exactly as in
  the `SwatchGridView` recipe's own WinUI 3 note. Because every brush is a
  `{ThemeResource}` rather than a literal `Color`, swapping the app's active
  `ResourceDictionary` (WinUI's analogue of calling `show(_:)` with a new
  `ColorTheme`) repaints the whole preview automatically through XAML's own
  theme-resource resolution, without an explicit rebuild pass.

## Design Decisions

- Decision: Document `ThemePreviewView` with 30 behavioral requirements,
  well above sibling ingredients such as `SwatchGridView` (12) or `Badge`
  (7).
  Rationale: `ThemePreviewView` genuinely composes five distinct
  sample-card builders plus an embedded `SwatchGridView` and a live
  `TerminalAppearance` resolution, each with its own layout, color and font
  rules traceable to source — matching a sibling's requirement count here
  would either omit real, independently testable behavior or artificially
  merge unrelated behaviors into compound requirements.
  Approved: pending
- Decision: Treat the `SwatchGridView` being excluded from the
  `cards.map { widthAnchor... }` width stretch as a documented source
  quirk, not a defect this recipe silently corrects.
  Rationale: `show(_:)` builds the width-stretch constraints only from the
  `cards` array of five sample boxes; the `SwatchGridView` appended
  afterward is never included in that array or its `.map`. The recipe
  describes this exactly as source does, in Edge Cases, rather than
  assuming the intended behavior was to stretch every appended view.
  Approved: pending
- Decision: Document that the status sample's badge capsule is a private,
  structurally similar re-implementation, not a reuse of the shared `Badge`
  ingredient, without treating that as a defect.
  Rationale: `ThemePreviewView.swift` defines its own `private static func
  badge(_:_:_:)` building a tinted capsule inline; it never references
  `AgenticToolkit`'s `Badge` type. The recipe records this exactly as source
  does — the two happen to look alike, but that is not evidence they are the
  same component, and unifying them is outside this file's actual behavior.
  Approved: pending
- Decision: Leave both Accessibility bullets and the Localization section as
  open questions rather than assuming a specific grouping,
  labeling, or localization strategy.
  Rationale: `ThemePreviewView.swift` contains zero accessibility API calls
  and zero localization calls of any kind, and there is no comparable
  `ThemePreviewView`-family sibling recipe to pattern-match a grouping,
  labeling, or localization decision against — only `SwatchGridView`, whose
  own gaps (per-swatch color labels) are a different question already
  documented in its own recipe, and are cross-referenced rather than
  repeated here.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | platform-compliance |
| [theme-token-only-colors](agenticdevelopercookbook://compliance/ui#theme-token-only-colors) | passed | ui |
| [no-raw-hex-tokens-only](agenticdevelopercookbook://compliance/ui#no-raw-hex-tokens-only) | passed | ui |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [meaningful-labels](agenticdevelopercookbook://compliance/accessibility#meaningful-labels) | partial | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | passed | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ThemePreviewView, covering the chrome/list/controls/status/terminal sample builders, the embedded SwatchGridView composition, TerminalAppearance resolution, and open questions on accessibility grouping and demo-content localization for review. |
