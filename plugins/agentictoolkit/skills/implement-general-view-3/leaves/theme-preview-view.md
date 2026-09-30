<!-- leaf: implement-general-view-3/theme-preview-view · source: theme-preview-view.md -->

**Rules** (cite as `implement-general-view-3/theme-preview-view#<slug>`):

- `container-pinning` MUST
- `empty-initial-state` MUST
- `coder-init-trap` MUST
- `show-teardown-and-rebuild` MUST
- `self-background-paint` MUST
- `card-order` MUST
- `card-width-stretch` MUST
- `card-minimum-width` MUST
- `card-content-insets` MUST
- `chrome-title` MUST
- `chrome-body-and-caption` MUST
- `chrome-controls-row` MUST
- `chrome-divider` MUST
- `chrome-outlined-panel` MUST
- `list-tab-strip` MUST
- `list-row-set` MUST
- `selected-list-row-style` MUST
- `unselected-list-row-style` MUST
- `list-row-content-layout` MUST
- `controls-text-field-pair` MUST
- `controls-checkbox-line` MUST
- `status-badge-set` MUST
- `status-badge-style` MUST
- `terminal-box-background` MUST
- `terminal-appearance-resolution` MUST
- `terminal-sample-content` MUST
- `terminal-content-insets` MUST
- `cursor-shape` MUST
- `ansi-swatch-grid` MUST
- `semantic-palette-derivation` MUST

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
`SemanticPalette(theme:)` and fully rebuilds five sample cards (chrome, list
with its tab strip, controls, status badges, terminal) plus an embedded
`ComposableSettings.SwatchGridView` of the theme's 16 ANSI colors. It composes
the sibling `SwatchGridView` ingredient directly rather than re-implementing a
swatch grid, but implements its own private, structurally similar "badge"
capsule for the status row rather than reusing the shared `Badge` ingredient
(see Design Decisions).

## Behavioral Requirements

- **container-pinning**: Component MUST maintain a single vertical
  `NSStackView` (`container`, leading-aligned, 10pt spacing) as its only direct
  subview, pinned to all four edges of `self` with no additional constant.
- **empty-initial-state**: Component MUST NOT add any content to
  `container`, and MUST NOT paint `self`'s background, when constructed via
  `init(theme:)` with the default `nil` argument; content and the background
  paint appear only once `show(_:)` is called.
- **coder-init-trap**: Component MUST NOT support construction via
  `init(coder:)`; that initializer MUST trigger a fatal error.
- **show-teardown-and-rebuild**: On every call to `show(_:)`, the
  component MUST remove every existing arranged subview from `container`
  before adding the new set of sample cards, rather than diffing or reusing
  any existing card.
- **self-background-paint**: On every call to `show(_:)`, the
  component MUST set its own `wantsLayer`-backed background color to the
  resolved `SemanticPalette`'s `windowBackground` role color.
- **card-order**: `show(_:)` MUST append exactly six items to
  `container`, in this fixed order: the chrome sample, the list sample, the
  controls sample, the status sample, the terminal sample, then the ANSI
  swatch grid.
- **card-width-stretch**: The component MUST activate a
  width constraint equal to `container`'s width on each of the five sample
  cards (chrome, list, controls, status, terminal), so that the
  leading-aligned, content-sized stack view does not let them collapse to
  their intrinsic content width.
- **card-minimum-width**: Each of the four cards whose content stack follows
  `card-content-insets` (chrome, list, controls, status) and the
  terminal sample's box MUST each carry an activated
  `widthAnchor >= 280` constraint, independent of their content.
- **card-content-insets**: The vertical content stack shared by the
  chrome, list, controls and status cards MUST be inset from the card by
  exactly 10pt from the top, 12pt from the leading edge, and 10pt from the
  bottom, and MUST constrain the trailing edge to at most 12pt from the
  card's trailing edge (the content may be narrower, never wider).
- **chrome-title**: The chrome sample MUST include a label reading
  "Window Title" in the `primaryText` color and the `title` text style.
- **chrome-body-and-caption**: The chrome sample MUST include a body
  label reading "Body text in the body font." in `primaryText`/`body` style,
  and a caption label reading "Secondary caption text" in
  `secondaryText`/`caption` style.
- **chrome-controls-row**: The chrome sample MUST include a horizontal
  row (8pt spacing) of two pill-shaped controls, both set in the `button` text
  style: a "Button" pill filled with `accent` and text colored
  `onAccentText`, and a "Selected" pill filled with `selection` and text
  colored `selectionText`.
- **chrome-divider**: The chrome sample MUST include a 1pt-tall
  hairline view filled with the `divider` role color, constrained to the
  card's width minus 24pt.
- **chrome-outlined-panel**: The chrome sample MUST include an inner
  rounded (8pt corner radius) panel filled with `elevatedSurface`, with a 1pt
  border in the `outline` role color, containing a caption-styled label
  reading "Panel · outline" in `tertiaryText`, constrained to the card's width
  minus 24pt.
- **list-tab-strip**: The list sample MUST render a horizontal row (4pt
  spacing) of three pills in the `button` text style: "Notes" filled with
  `elevatedSurface` and text in `primaryText`, and "Chat" and "Terminal" each
  filled with `surface` and text in `secondaryText`.
- **list-row-set**: The list sample MUST render exactly three rows,
  in this order: ("Release notes", "Yesterday", unselected), ("Design
  review", "2 days ago", selected), ("Scratch", "Last week", unselected).
- **selected-list-row-style**: A selected list row MUST fill its background
  with the `selection` role color (5pt corner radius) and render both its
  title and detail text in `selectionText`.
- **unselected-list-row-style**: An unselected list row MUST leave its
  background transparent and render its title in `primaryText` and its detail
  text in `tertiaryText`.
- **list-row-content-layout**: Each list row MUST place its title label
  leading-aligned with an 8pt inset and its detail label trailing-aligned with
  an 8pt inset, both vertically centered, with the detail label's leading edge
  held at least 8pt from the title label's trailing edge.
- **controls-text-field-pair**: The controls sample MUST render two
  side-by-side, equal-width (`fillEqually`, 8pt spacing) simulated text
  fields, each a 5pt-corner-radius box filled with `controlBackground` and
  outlined with a 1pt `border`-colored stroke: one showing "Typed text" in
  `primaryText`, the other showing "Placeholder" in `placeholderText`.
- **controls-checkbox-line**: The controls sample MUST render a single
  line of text reading "☑︎ Enabled    ☐ Disabled" in `secondaryText`/`body`
  style, as a static representation of a checkbox's checked and unchecked
  appearance.
- **status-badge-set**: The status sample MUST render exactly four
  badges, in this order and color: "Success" (`success`), "Warning"
  (`warning`), "Error" (`danger`), "Info" (`info`), in a horizontal row with
  6pt spacing.
- **status-badge-style**: Each status badge MUST be a 5pt-corner-radius
  capsule whose background is its status color at 22% alpha, whose border is
  the same status color at 55% alpha (1pt), and whose text is the same status
  color at full opacity in the `caption` text style.
- **terminal-box-background**: The terminal sample's box
  MUST be filled with the `windowBackground` role color (unlike the other four
  cards, which use `surface`) and outlined with a 1pt `border`-colored stroke.
- **terminal-appearance-resolution**: The terminal sample MUST
  resolve its font, padding and cursor shape by calling
  `TerminalAppearance.resolvedFont(theme:)`, `resolvedPadding(theme:)` and
  `resolvedCursor(theme:)` — the same resolution a live terminal session
  uses — rather than hardcoding any of the three.
- **terminal-sample-content**: Using the resolved terminal font, the
  terminal sample MUST render a prompt line reading "user@mac ~ % ls" in
  `primaryText` followed immediately by the caret, and a second line (2pt
  below the first) of "Documents" in `accent` and "README.md" in
  `secondaryText`, 10pt apart.
- **terminal-content-insets**: The terminal sample MUST
  inset its content stack from the box's top, leading and bottom edges by
  exactly the theme's resolved terminal padding on that side, and MUST
  constrain the trailing edge to at most the box's trailing edge minus the
  resolved trailing padding.
- **cursor-shape**: The terminal sample MUST render a one-cell caret,
  sized off the resolved font (width = `max(font.pointSize * 0.6, 5)`, height
  = `font.pointSize + 3`, except height 2 for `.underline` and width 2 for
  `.bar`), filled or outlined with the `cursor` role color, in the shape given
  by the resolved `TerminalCursorShape` (`.block` filled, `.hollowBlock`
  1pt-bordered, `.underline` a 2pt-tall bar, `.bar` a 2pt-wide bar).
- **ansi-swatch-grid**: `show(_:)` MUST construct and append
  a `ComposableSettings.SwatchGridView` populated with the resolved palette's
  16 `ansiColors`, at 8 columns, as the final item in `container`.
- **semantic-palette-derivation**: Every color value, and every font value
  except the terminal sample's (which instead resolves via
  `terminal-appearance-resolution`), MUST come from a single
  `SemanticPalette(theme:)` constructed once at the top of `show(_:)`, read
  through its role-based `color(_:)`/`nsColor(_:)`/`font(_:)` API — never a
  raw, theme-independent color or font literal.

