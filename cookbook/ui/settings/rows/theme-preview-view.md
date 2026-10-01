---
id: 15e66a2e-9ee1-4f5f-aeb0-c804078b4f78
title: Theme Preview View
domain: agentictoolkit://cookbook/ui/settings/rows/theme-preview-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings view that renders a live sample of a color theme as real
  app chrome - window, sidebar, controls, status badges, ANSI swatches and a
  terminal.
platforms:
- swift
- macos
tags:
- settings
- theme
- preview
depends-on:
- agentictoolkit://cookbook/ui/settings/rows/swatch-grid-view
related:
- agentictoolkit://cookbook/ui/controls/badge
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Theme Preview View

## Overview

The Theme Preview View is a view, confined to a single, serialized execution
context, that answers "what will this theme look like?" without switching to
it first. Per its own description, it is a live sample of a color theme
drawn as the app's own UI rather than as a row of color chips: window chrome
and type, a sidebar with a selected row, form controls, status badges, the
16 ANSI swatches, and a terminal that honors the theme's terminal font,
padding and cursor overrides. Every sample is built from a real component's
shape — a list row really is a rounded selection fill under the
selection-text role, a badge really is success/warning/danger/info — so the
preview exercises the same semantic-palette role lookups the rest of the app
uses, rather than a parallel, idealized set of demo colors.

The view starts empty; calling the show operation with a color theme
resolves a semantic palette and fully rebuilds five sample cards (chrome,
list with its tab strip, controls, status badges, terminal) plus an embedded
swatch grid of the theme's 16 ANSI colors. It composes the sibling Swatch
Grid View ingredient directly rather than re-implementing a swatch grid, but
implements its own private, structurally similar "badge" capsule for the
status row rather than reusing the shared Badge ingredient (see Design
Decisions).

## Behavioral Requirements

- **container-pinning**: Component MUST maintain a single vertical
  container (leading-aligned, 10pt spacing) as its only direct content
  holder, pinned to all four of its own edges with no additional constant.
- **empty-initial-state**: Component MUST NOT add any content to that
  container, and MUST NOT paint its own background, when constructed with
  no theme supplied; content and the background paint appear only once the
  show operation is called.
- **show-teardown-and-rebuild**: On every call to the show operation, the
  component MUST remove every existing sample from its container before
  adding the new set of sample cards, rather than diffing or reusing any
  existing card.
- **self-background-paint**: On every call to the show operation, the
  component MUST set its own background color to the resolved palette's
  window-background role color.
- **card-order**: The show operation MUST append exactly six items to the
  container, in this fixed order: the chrome sample, the list sample, the
  controls sample, the status sample, the terminal sample, then the ANSI
  swatch grid.
- **card-width-stretch**: The component MUST size each of the five sample
  cards (chrome, list, controls, status, terminal) to the container's own
  width, so that the leading-aligned, content-sized container does not let
  them collapse to their intrinsic content width.
- **card-minimum-width**: Each of the four cards whose content follows
  card-content-insets (chrome, list, controls, status) and the terminal
  sample's box MUST each enforce a minimum width of 280pt, independent of
  their content.
- **card-content-insets**: The content shared by the chrome, list,
  controls and status cards MUST be inset from the card by exactly 10pt
  from the top, 12pt from the leading edge, and 10pt from the bottom, and
  MUST constrain the trailing edge to at most 12pt from the card's trailing
  edge (the content may be narrower, never wider).
- **chrome-title**: The chrome sample MUST include a label reading
  "Window Title" in the primary-text color and the title text style.
- **chrome-body-and-caption**: The chrome sample MUST include a body
  label reading "Body text in the body font." in primary-text/body style,
  and a caption label reading "Secondary caption text" in
  secondary-text/caption style.
- **chrome-controls-row**: The chrome sample MUST include a horizontal
  row (8pt spacing) of two pill-shaped controls, both set in the button
  text style: a "Button" pill filled with the accent color and text
  colored with the on-accent-text role, and a "Selected" pill filled with
  the selection color and text colored with the selection-text role.
- **chrome-divider**: The chrome sample MUST include a 1pt-tall hairline
  filled with the divider role color, constrained to the card's width
  minus 24pt.
- **chrome-outlined-panel**: The chrome sample MUST include an inner
  rounded (8pt corner radius) panel filled with the elevated-surface color,
  with a 1pt border in the outline role color, containing a caption-styled
  label reading "Panel · outline" in the tertiary-text role, constrained to
  the card's width minus 24pt.
- **list-tab-strip**: The list sample MUST render a horizontal row (4pt
  spacing) of three pills in the button text style: "Notes" filled with
  the elevated-surface color and text in primary-text, and "Chat" and
  "Terminal" each filled with the surface color and text in secondary-text.
- **list-row-set**: The list sample MUST render exactly three rows, in
  this order: ("Release notes", "Yesterday", unselected), ("Design
  review", "2 days ago", selected), ("Scratch", "Last week", unselected).
- **selected-list-row-style**: A selected list row MUST fill its
  background with the selection role color (5pt corner radius) and render
  both its title and detail text in the selection-text role.
- **unselected-list-row-style**: An unselected list row MUST leave its
  background transparent and render its title in primary-text and its
  detail text in tertiary-text.
- **list-row-content-layout**: Each list row MUST place its title label
  leading-aligned with an 8pt inset and its detail label trailing-aligned
  with an 8pt inset, both vertically centered, with the detail label's
  leading edge held at least 8pt from the title label's trailing edge.
- **controls-text-field-pair**: The controls sample MUST render two
  side-by-side, equal-width (8pt spacing) simulated text fields, each a
  5pt-corner-radius box filled with the control-background color and
  outlined with a 1pt border-colored stroke: one showing "Typed text" in
  primary-text, the other showing "Placeholder" in placeholder-text.
- **controls-checkbox-line**: The controls sample MUST render a single
  line of text reading "☑︎ Enabled    ☐ Disabled" in secondary-text/body
  style, as a static representation of a checkbox's checked and unchecked
  appearance.
- **status-badge-set**: The status sample MUST render exactly four
  badges, in this order and color: "Success" (success), "Warning"
  (warning), "Error" (danger), "Info" (info), in a horizontal row with 6pt
  spacing.
- **status-badge-style**: Each status badge MUST be a 5pt-corner-radius
  capsule whose background is its status color at 22% alpha, whose border
  is the same status color at 55% alpha (1pt), and whose text is the same
  status color at full opacity in the caption text style.
- **terminal-box-background**: The terminal sample's box MUST be filled
  with the window-background role color (unlike the other four cards,
  which use the surface color) and outlined with a 1pt border-colored
  stroke.
- **terminal-appearance-resolution**: The terminal sample MUST resolve
  its font, padding and cursor shape from the theme's own terminal-
  appearance resolution — the same resolution a live terminal session
  uses — rather than hardcoding any of the three.
- **terminal-sample-content**: Using the resolved terminal font, the
  terminal sample MUST render a prompt line reading "user@mac ~ % ls" in
  primary-text followed immediately by the caret, and a second line (2pt
  below the first) of "Documents" in the accent color and "README.md" in
  secondary-text, 10pt apart.
- **terminal-content-insets**: The terminal sample MUST inset its
  content from the box's top, leading and bottom edges by exactly the
  theme's resolved terminal padding on that side, and MUST constrain the
  trailing edge to at most the box's trailing edge minus the resolved
  trailing padding.
- **cursor-shape**: The terminal sample MUST render a one-cell caret,
  sized off the resolved font (width = the greater of the font's point
  size times 0.6 or 5, height = the font's point size plus 3, except
  height 2 for the underline shape and width 2 for the bar shape), filled
  or outlined with the cursor role color, in the shape given by the
  resolved cursor shape (block filled, hollow block 1pt-bordered,
  underline a 2pt-tall bar, bar a 2pt-wide bar).
- **ansi-swatch-grid**: The show operation MUST construct and append a
  swatch grid populated with the resolved palette's 16 ANSI colors, at 8
  columns, as the final item in the container.
- **semantic-palette-derivation**: Every color value, and every font
  value except the terminal sample's (which instead resolves via
  terminal-appearance-resolution), MUST come from a single semantic
  palette constructed once at the top of the show operation, read through
  its role-based lookup, never a raw, theme-independent color or font
  literal.

## Appearance

- **Corner radius**: The component itself has none. Every sample card box
  has an 8pt corner radius. The controls sample's two simulated text
  fields override this to 5pt. List rows and status badges use 5pt. ANSI
  swatches (in the embedded swatch grid) use 3pt — see that recipe.
- **Padding**: Card content is inset 10pt top / 12pt leading / ≤12pt
  trailing (may be narrower) / 10pt bottom, per card-content-insets. The
  terminal sample instead insets by the theme's resolved terminal padding
  (default 10pt on all four sides) rather than the fixed 10/12/12/10
  shape.
- **Font**: The title, body, caption and button text-style roles from the
  theme's typography, resolved through the palette's role lookup. The
  terminal sample uses the theme's resolved monospaced terminal font
  instead of any text-style role.
- **Background**: The component itself — the theme's window-background
  role. Chrome, list, controls and status cards — the surface role. The
  terminal card — window-background (see terminal-box-background). The
  chrome sample's inner panel — elevated-surface. Text field simulations —
  control-background. Status badges — their status color at 22% alpha.
- **Foreground/Text**: Role-specific per element — primary-text,
  secondary-text, tertiary-text, placeholder-text, on-accent-text,
  selection-text, accent, and the four status colors — as itemized in
  Behavioral Requirements.
- **Border**: The chrome sample's inner panel — 1pt, outline. The controls
  sample's two text-field simulations — 1pt, border. The terminal sample's
  box — 1pt, border. Status badges — 1pt, their status color at 55%
  alpha. No border on the component, its container, any card's outer box,
  or list rows/pills.
- **Shadow**: Not applicable — no shadow or layer-shadow property is set
  anywhere in the component.
- **Min/Max size**: Every card box and the terminal box each carry a
  minimum-width constraint of 280pt; the component and its container have
  no explicit min/max size of their own — the view's overall size is
  driven by its arranged content plus whatever constraints a host applies
  to it.

## States

| State | Appearance change |
|-------|------------------|
| Default | Before the show operation is called, the container is empty and the component has no background paint (empty-initial-state). After it, the view fully repaints as described in Overview/Behavioral Requirements; calling it again with a different (or the same) theme tears down and rebuilds every card from that theme. |
| Pressed | Not applicable: no interactive control, action-target wiring, or click-handling exists anywhere in the component; every element (boxes, pills, rows, badges, the caret) is a plain, non-interactive view. |
| Disabled | Not applicable: an enabled/disabled property is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no interactive control, so it never becomes focused or shows a focus ring. |
| Loading | Not applicable: the show operation and every sample-building helper it calls are synchronous, non-throwing property assignments and view constructions; there is no asynchronous operation and no loading indicator anywhere in source. |

## Accessibility

- **Role/trait**: Every label exposes itself to a screen reader as static
  text by the platform's own default; no other element (box, pill, badge,
  row, the caret, the hairline) sets an accessibility role, marks itself
  as an accessibility element, or makes any similar call anywhere in
  source, so none of those containers expose a semantic grouping of their
  own. Neither the whole preview nor any sample card is combined into a
  single accessibility element with a summarizing label; a screen reader
  reads roughly twenty individual demo labels one at a time, with no
  indication they belong to a "theme preview" rather than live application
  state.
- **Label requirements**: All visible text is the literal English demo
  strings itemized in Behavioral Requirements (see also Localization); no
  accessible-label/accessible-value override is set anywhere, so a screen
  reader reads exactly that literal text. Nothing in source distinguishes
  illustrative sample text ("Window Title", "Success", "Documents") from a
  real value a user could act on — a screen reader has only that literal
  demo string to read either way.
- **Announce state changes**: Not applicable — the show operation is the
  only mutating entry point, runs synchronously to completion on a single,
  serialized execution context, and there is no loading indicator or
  asynchronous transition to announce (see States/Loading).
- **Minimum tap target**: Not applicable — this is a pointer/trackpad
  composition with no interactive element anywhere in source (see
  States/Pressed), so there is no touch target to size. The embedded
  swatch grid's own accessibility posture is documented in its own recipe
  (`agentictoolkit://cookbook/ui/settings/rows/swatch-grid-view`), not
  repeated here.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-preview-view-001 | container-pinning | Construct the view and inspect its structure | The component has exactly one direct content container, whose top/leading/trailing/bottom edges equal the component's own with no offset |
| theme-preview-view-002 | empty-initial-state | Construct the component with no theme argument | The container holds no samples and the component's background is unset |
| theme-preview-view-004 | show-teardown-and-rebuild | Call show(themeA), note the 6 samples, then call show(themeB) | None of the original 6 sample instances remain in the container; a fresh 6 are present |
| theme-preview-view-005 | self-background-paint | Call show(theme) | The component's background color equals the resolved palette's window-background role color for that theme |
| theme-preview-view-006 | card-order | Call show(theme) and inspect the container's contents | Exactly 6 items, in order: chrome, list, controls, status, terminal, swatch grid |
| theme-preview-view-007 | card-width-stretch | Call show(theme) inside a wide host and inspect sizing | Each of the first 5 samples is sized to the container's own width |
| theme-preview-view-008 | card-minimum-width | Call show(theme) and inspect sizing on each of the 5 sample-card boxes | Each has an enforced minimum width of 280pt |
| theme-preview-view-009 | card-content-insets | Inspect the chrome card's content layout after show(theme) | Content is inset 10pt from the top, 12pt from the leading edge, 10pt from the bottom, and constrained to at most 12pt from the trailing edge |
| theme-preview-view-010 | chrome-title | Call show(theme) and read the chrome card's first label | Text is "Window Title", color equals the palette's primary-text role color, font equals the palette's title-role font |
| theme-preview-view-011 | chrome-body-and-caption | Read the chrome card's second and third labels | "Body text in the body font." in primary-text/body; "Secondary caption text" in secondary-text/caption |
| theme-preview-view-012 | chrome-controls-row | Read the chrome card's controls row | Two pills, "Button" (fill accent, text on-accent-text) and "Selected" (fill selection, text selection-text), both button font, row spacing 8 |
| theme-preview-view-013 | chrome-divider | Inspect the chrome card's hairline element | Its thickness is 1pt, its color equals the palette's divider role color, and its width equals the card's width minus 24pt |
| theme-preview-view-014 | chrome-outlined-panel | Inspect the chrome card's inner panel | 8pt corner radius, fill elevated-surface, 1pt border outline, containing a "Panel · outline" label in tertiary-text/caption |
| theme-preview-view-015 | list-tab-strip | Read the list card's tab row | Three pills "Notes"/"Chat"/"Terminal"; "Notes" fill elevated-surface text primary-text, the other two fill surface text secondary-text; 4pt spacing |
| theme-preview-view-016 | list-row-set | Read the list card's rows in order | ("Release notes","Yesterday",unselected), ("Design review","2 days ago",selected), ("Scratch","Last week",unselected) |
| theme-preview-view-017 | selected-list-row-style | Inspect the "Design review" row | Background selection, 5pt corner radius, both labels colored selection-text |
| theme-preview-view-018 | unselected-list-row-style | Inspect the "Release notes" row | Background transparent, title primary-text, detail tertiary-text |
| theme-preview-view-019 | list-row-content-layout | Inspect any row's label layout | Title leading offset 8, detail trailing offset -8, both centered vertically, detail's leading >= title's trailing + 8 |
| theme-preview-view-020 | controls-text-field-pair | Read the controls card's two fields | "Typed text" in primary-text, "Placeholder" in placeholder-text; both control-background fill, 5pt corner radius, 1pt border outline, equal width, 8pt spacing |
| theme-preview-view-021 | controls-checkbox-line | Read the controls card's third element | Text "☑︎ Enabled    ☐ Disabled", color secondary-text, font body |
| theme-preview-view-022 | status-badge-set | Read the status card's badges in order | "Success"(success), "Warning"(warning), "Error"(danger), "Info"(info); row spacing 6 |
| theme-preview-view-023 | status-badge-style | Inspect the "Success" badge's rendering | 5pt corner radius, background = success color at 22% alpha, border 1pt = success color at 55% alpha, text = success color at full opacity, caption-role font |
| theme-preview-view-024 | terminal-box-background | Inspect the terminal card's box | Fill = the palette's window-background role color, 1pt border = the palette's border role color |
| theme-preview-view-025 | terminal-appearance-resolution | Call show(theme) where the theme's terminal settings override font/padding/cursor | The terminal sample's font, insets, and caret shape match the theme's resolved terminal-appearance values, not the app's stored defaults |
| theme-preview-view-026 | terminal-sample-content | Read the terminal card's content | Line 1: "user@mac ~ % ls" (primary-text) + caret; line 2: "Documents" (accent) and "README.md" (secondary-text), 10pt apart, 2pt below line 1 |
| theme-preview-view-027 | terminal-content-insets | Set a theme with a terminal leading padding of 40 and call show(theme) | The terminal content's leading offset from the box is 40, not the 10pt default |
| theme-preview-view-028 | cursor-shape | Set the theme's terminal cursor shape to bar and call show(theme) | The caret is 2pt wide, the resolved terminal font's cell height tall (point size plus 3, unchanged by the bar shape), filled with the palette's cursor role color |
| theme-preview-view-029 | ansi-swatch-grid | Call show(theme) and inspect the 6th item in the container | It is a swatch grid constructed with the palette's 16 ANSI colors and 8 columns |
| theme-preview-view-030 | semantic-palette-derivation | Call show(themeA) then show(themeB) with two themes differing only in their role overrides | Every sample-card color equals what the palette resolves for themeB's role overrides (roles neither theme overrides may equal the themeA value; only an override-driven mismatch fails the vector) |

## Edge Cases

- Null/empty input: the theme defaults to none in the component's
  construction. When none is given, the container remains empty and the
  component's background is never painted until the show operation is
  called explicitly with a concrete theme — this is a MUST
  (empty-initial-state), not a crash or a placeholder theme.
- Boundary values — repeated/idempotent show: calling the show operation
  multiple times, including twice with the same theme, produces the same
  visual result each time because every call tears down all existing
  samples before rebuilding (show-teardown-and-rebuild). This is a MUST,
  traceable to an unconditional teardown-then-rebuild step at the top of
  the operation.
- Boundary values — long or narrow content: cards are forced to exactly
  the container's width (card-width-stretch), but no label anywhere in
  source sets line-wrapping, a maximum line count, or single-line-only
  behavior, so in a very narrow host or with an enlarged typography
  scale, list-row detail labels, badge text, or the chrome sample's
  content can be clipped or compressed rather than reflowed, per each
  plain label's platform default.
- Concurrent access: Not applicable — the component is confined to a
  single, serialized execution context, so every call to the show
  operation and every private sample-building helper is serialized; there
  is no code path by which two threads mutate the container simultaneously.
- Error states: Not applicable — every operation in the show operation and
  its helpers is a synchronous, non-throwing property assignment or view
  construction. The theme's terminal-appearance resolution (font, padding,
  cursor) is non-throwing and total over the theme and the app's stored
  defaults, and always resolves to a concrete value; no error or optional
  is propagated to this component from any of it.
- Offline/disconnected state: Not applicable — the component performs no
  networking of its own; it only renders values resolved from the supplied
  theme and local stored defaults.
- Quirk — swatch grid excluded from the width stretch: the show operation
  applies the width-stretch sizing only over the five sample boxes; the
  swatch grid appended afterward is never included in that sizing pass, so
  it is left at its own content-driven width. With the fixed 8-column
  layout and exactly 16 ANSI colors this always renders two full rows
  regardless, so the omission has no visible effect today, but it is a
  documented, source-traceable asymmetry rather than something this
  recipe assumes is intentional design.
- Quirk — chrome sample's divider/inner-panel width sizing references the
  outer box: the card-content-fill step returns the same box instance it
  was given (not a wrapper), which is what lets the divider's and the
  inner panel's width sizing — both applied after that fill step returns
  — resolve correctly against the final card width.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `theme` | Color theme (optional) | none | Passed at construction; when given, the show operation is called immediately during initialization. When omitted, the view starts empty (empty-initial-state). |

The only other entry point is the public show operation, which fully tears
down and rebuilds the preview for a new theme (see Behavioral Requirements);
it is not a construction option and so is documented there rather than in
this table.

## Deep Linking

Not applicable: the component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

None of the keys below exist in source — the component makes no
localization call of any kind. They are proposed keys for the localization
pass named in the open question below, not an inventory of what is
implemented.

| Proposed Key | Default (en) | Context |
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

Every string above is a literal set directly as a label's text (not routed
through any state/binding-driven text mechanism), and none of it is routed
through a localization table anywhere in source. Source gives no
localization path today for any of these illustrative demo strings.

## Accessibility Options

- **Reduce Motion**: Not applicable — the show operation and every
  sample-building helper perform an instantaneous full teardown and
  rebuild; no animation context, animator, or transition of any kind
  appears anywhere in source, so there is no motion for Reduce Motion to
  substitute for.
- **Increase Contrast**: Not applicable at this component's own level —
  every color is read through the palette's role lookup
  (semantic-palette-derivation); the component itself contains no separate
  Increase Contrast branch, so it inherits whatever contrast behavior the
  active palette/theme provides without any code of its own to adjust.
- **Differentiate Without Color**: Supported for the status sample — each
  of the four badges pairs its status color with an explicit text label
  ("Success"/"Warning"/"Error"/"Info"), so status is never conveyed by hue
  alone (contrast this with the embedded swatch grid's raw color swatches,
  which carry no label — see that recipe's own note). The chrome sample's
  "Button" vs. "Selected" pills are likewise distinguished by their own
  text, not color alone.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in the component; the preview always renders once the show
operation is called.

## Analytics

Not applicable: the component contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only renders the color theme value it is given.
- **Storage**: Not applicable — source performs no read/write to disk,
  persistent storage, or any other store; the terminal-appearance
  resolution's fallback to the app's stored defaults is a read-only
  lookup for its own defaults.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains the resolved palette
  and its own subviews only for its own lifetime; it persists nothing
  beyond that.

## Logging

Not applicable: the component contains no logging call anywhere in
source.

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
  `--surface`/`--window-background` custom property) each laid out with
  `padding: 10px 12px`, followed by a CSS Grid of ANSI swatches (`gap` and
  `grid-template-columns: repeat(8, ...)`, mirroring the `SwatchGridView`
  recipe). Because the preview must show the given `theme` prop rather than
  whichever theme is currently active app-wide, every custom property is set
  inline on the preview's own root element (`style={{ '--surface':
  theme.surface, ... }}`) from that prop, not read from the document-level
  theme class/attribute the rest of the app uses — so passing a different
  `theme` repaints only the preview, exactly as the show operation does
  imperatively here.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePreviewView.swift`.
  A macOS-only (`import AppKit`), `@MainActor` `NSView` subclass in the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. The
  component is constructed only via `init(theme:)`; the fatal-erroring
  `init?(coder:)` traps at runtime, so a caller cannot construct one
  through that path. It composes a single vertical `NSStackView` of five
  hand-built card views (each an `NSView` with a `CALayer` background,
  built from nested `NSStackView`s of `NSTextField(labelWithString:)`
  labels and plain layer-backed `NSView`s for pills/badges/rows/the caret)
  plus one embedded `ComposableSettings.SwatchGridView`. There is no UIKit
  code path in source; a UIKit port has no direct `NSStackView`-of-cards
  equivalent and would instead compose a vertical `UIStackView` of card
  `UIView`s (each `layer.cornerRadius`/`backgroundColor` styled the same
  way), with `UILabel`s in place of `NSTextField(labelWithString:)` and the
  same `SwatchGridView`-equivalent grid embedded at the end. Implementation
  detail: `container` is pinned to `self` via the shared `Self.pinToEdges`
  helper; each card's content stack is built by the private
  `fill(_:with:)` helper; and `show(_:)` tears down the prior cards with
  `container.arrangedSubviews.forEach { $0.removeFromSuperview() }` before
  rebuilding.
- **WinUI 3**: Compose a vertical `StackPanel` (`Spacing="10"`) of five
  `Border` "card" elements (`CornerRadius="8"`, `MinWidth="280"`,
  `HorizontalAlignment="Stretch"`), each containing a `StackPanel` of
  `TextBlock`/`Border` children styled per the requirements above (a "pill" is
  a `Border` with `CornerRadius="5"` around a `TextBlock`; a status badge is
  the same shape with its `Background`/`BorderBrush` bound through a converter
  to the status color at 22%/55% opacity). Because the preview must render the
  `ColorTheme` it is given rather than the app's currently active theme, every
  `Background`/`Foreground`/`BorderBrush` binds to a `ResourceDictionary` built
  at preview-construction time from that `ColorTheme` and merged only into the
  preview's own subtree (for example via `FrameworkElement.Resources` on the
  container) — never to the app-wide `{ThemeResource}` brushes (such as
  `CardBackgroundFillColorDefaultBrush`) that repaint with whichever theme is
  currently active. Terminal padding maps to the `Border`'s `Padding` property
  bound directly to the four resolved padding values; the caret maps to a
  small `Border`/`Rectangle` whose `Width`/`Height`/`CornerRadius`/
  fill-vs-outline are chosen from a `VisualStateManager` group with one state
  per cursor-shape case (Block/HollowBlock/Underline/Bar), each setter
  matching the width/height math in `cursor-shape`. The ANSI swatch grid
  maps to an `ItemsRepeater` with a `UniformGridLayout`, exactly as in the
  `SwatchGridView` recipe's own WinUI 3 note. Rebuilding that scoped
  `ResourceDictionary` from a new `ColorTheme` (WinUI's analogue of calling
  the show operation with a new theme) repaints the whole preview without
  touching the app's own active theme resources.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePreviewView.swift` |

## Design Decisions

**Decision**: Treat the `SwatchGridView` being excluded from the
`cards.map { widthAnchor... }` width stretch as a documented source quirk,
not a defect this recipe silently corrects. (AppKit source.)
**Rationale**: `show(_:)` builds the width-stretch constraints only from the
`cards` array of five sample boxes; the `SwatchGridView` appended afterward
is never included in that array or its `.map`. The recipe describes this
exactly as source does, in Edge Cases, rather than assuming the intended
behavior was to stretch every appended view.
**Approved**: pending

**Decision**: Document that the status sample's badge capsule is a private,
structurally similar re-implementation of the shared `Badge` ingredient — a
known DRY gap, recorded as built rather than corrected. (AppKit source.)
**Rationale**: `ThemePreviewView.swift` defines its own `private static func
badge(_:_:_:)` building a tinted capsule inline; it never references
`AgenticToolkit`'s `Badge` type. The two happen to look alike, which is
exactly the duplication a shared-components policy exists to prevent; this
recipe records that duplication as source built it rather than assuming an
unmade refactor, since composing `Badge` here is a source change this recipe
cannot make.
**Approved**: pending

**Decision**: State the missing accessibility grouping/labeling and the
missing localization as plain facts about source, not open questions,
without assuming a specific grouping, labeling, or localization strategy for
the eventual fix. (AppKit source.)
**Rationale**: `ThemePreviewView.swift` contains zero accessibility API
calls and zero localization calls of any kind, and there is no comparable
`ThemePreviewView`-family sibling recipe to pattern-match a grouping,
labeling, or localization decision against — only `SwatchGridView`, whose
own gaps (per-swatch color labels) are a different question already
documented in its own recipe, and are cross-referenced rather than repeated
here.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

`keyboard-navigable` and `reduced-motion` are omitted: `ThemePreviewView.swift`
has no `NSControl`, target-action, or interactive element of any kind (see
States/Pressed) and no `NSAnimationContext`/animator proxy or transition of
any kind (see Accessibility Options/Reduce Motion), so neither check applies.
The remaining statuses rest on `ThemePreviewView.swift` itself: every color
and role-styled font is read through `SemanticPalette`/`TerminalAppearance`
role lookups, never a raw literal (the passed checks above); no
`setAccessibilityRole`/`setAccessibilityElement`/label override is set on any
container view, leaving VoiceOver labeling only partially met by AppKit's
default static-text role on each label (`screen-reader-support`, partial);
and every visible string is a
literal passed to `NSTextField(labelWithString:)`, never routed through
`NSLocalizedString` (`no-hardcoded-strings`, failed).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ThemePreviewView, covering the chrome/list/controls/status/terminal sample builders, the embedded SwatchGridView composition, TerminalAppearance resolution, and open questions on accessibility grouping and demo-content localization for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed all 30 requirements to subject-only kebab-case; moved private-implementation citations (`Self.pinToEdges`, `fill(_:with:)`, the arranged-subview teardown call) out of requirements and into AppKit Platform Notes; fixed the Overview's sample-card count and the terminal-font exemption in semantic-palette-derivation; corrected test vectors 028 and 030 and grounded empty-initial-state to cover the background paint for vector 002; reformatted Design Decisions to the bold three-line convention, dropped the requirement-count decision, and reworded the badge decision to record the Badge-ingredient duplication as a known DRY gap; relabeled Localization as proposed keys; rewrote the WinUI 3 and React/Web platform notes to scope theming to the given ColorTheme instead of the app's active theme; moved the misplaced cookbook `references` entry to `related` and deduped `swatch-grid-view`; and reworked Compliance to title-case categories, drop the two inapplicable accessibility checks, and add a sourcing sentence. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped meaningful-labels to screen-reader-support |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
