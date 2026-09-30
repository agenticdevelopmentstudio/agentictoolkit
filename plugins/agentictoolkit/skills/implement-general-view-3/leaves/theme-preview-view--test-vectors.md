<!-- leaf: implement-general-view-3/theme-preview-view--test-vectors · source: theme-preview-view.md -->

# ThemePreviewView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-preview-view-001 | container-pinning | Construct the view and inspect its subviews/constraints | `self` has exactly one direct subview, `container`, whose top/leading/trailing/bottom anchors equal `self`'s with no constant |
| theme-preview-view-002 | empty-initial-state | `ThemePreviewView()` (no `theme` argument) | `container.arrangedSubviews` is empty and `self.layer?.backgroundColor` is unset |
| theme-preview-view-003 | coder-init-trap | Attempt `ThemePreviewView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| theme-preview-view-004 | show-teardown-and-rebuild | Call `show(themeA)`, note the 6 arranged subviews, then call `show(themeB)` | None of the original 6 subview instances remain in `container`; a fresh 6 are present |
| theme-preview-view-005 | self-background-paint | Call `show(theme)` | `self.layer?.backgroundColor == SemanticPalette(theme: theme).nsColor(.windowBackground).cgColor` |
| theme-preview-view-006 | card-order | Call `show(theme)` and inspect `container.arrangedSubviews` | Exactly 6 items, in order: chrome, list, controls, status, terminal, swatch grid |
| theme-preview-view-007 | card-width-stretch | Call `show(theme)` inside a wide host and inspect constraints | Each of the first 5 arranged subviews has an active `widthAnchor == container.widthAnchor` constraint |
| theme-preview-view-008 | card-minimum-width | Call `show(theme)` and inspect constraints on each of the 5 sample-card boxes | Each has an active `widthAnchor >= 280` constraint |
| theme-preview-view-009 | card-content-insets | Inspect the chrome card's content-stack constraints after `show(theme)` | Top offset 10, leading offset 12, bottom offset -10, trailing constrained `lessThanOrEqualTo` -12 |
| theme-preview-view-010 | chrome-title | Call `show(theme)` and read the chrome card's first label | Text is "Window Title", color equals `palette.nsColor(.primaryText)`, font equals `palette.font(.title)` |
| theme-preview-view-011 | chrome-body-and-caption | Read the chrome card's second and third labels | "Body text in the body font." in `primaryText`/`body`; "Secondary caption text" in `secondaryText`/`caption` |
| theme-preview-view-012 | chrome-controls-row | Read the chrome card's controls row | Two pills, "Button" (fill `accent`, text `onAccentText`) and "Selected" (fill `selection`, text `selectionText`), both `button` font, row spacing 8 |
| theme-preview-view-013 | chrome-divider | Inspect the chrome card's hairline view | Height constraint == 1, background color == `palette.nsColor(.divider)`, width == card width - 24 |
| theme-preview-view-014 | chrome-outlined-panel | Inspect the chrome card's inner panel | 8pt corner radius, fill `elevatedSurface`, 1pt border `outline`, containing a "Panel · outline" label in `tertiaryText`/`caption` |
| theme-preview-view-015 | list-tab-strip | Read the list card's tab row | Three pills "Notes"/"Chat"/"Terminal"; "Notes" fill `elevatedSurface` text `primaryText`, the other two fill `surface` text `secondaryText`; 4pt spacing |
| theme-preview-view-016 | list-row-set | Read the list card's rows in order | ("Release notes","Yesterday",unselected), ("Design review","2 days ago",selected), ("Scratch","Last week",unselected) |
| theme-preview-view-017 | selected-list-row-style | Inspect the "Design review" row | Background `selection`, 5pt corner radius, both labels colored `selectionText` |
| theme-preview-view-018 | unselected-list-row-style | Inspect the "Release notes" row | Background transparent, title `primaryText`, detail `tertiaryText` |
| theme-preview-view-019 | list-row-content-layout | Inspect any row's label constraints | Title leading offset 8, detail trailing offset -8, both centered vertically, detail's leading >= title's trailing + 8 |
| theme-preview-view-020 | controls-text-field-pair | Read the controls card's two fields | "Typed text" in `primaryText`, "Placeholder" in `placeholderText`; both `controlBackground` fill, 5pt corner radius, 1pt `border` outline, equal width, 8pt spacing |
| theme-preview-view-021 | controls-checkbox-line | Read the controls card's third element | Text "☑︎ Enabled    ☐ Disabled", color `secondaryText`, font `body` |
| theme-preview-view-022 | status-badge-set | Read the status card's badges in order | "Success"(`success`), "Warning"(`warning`), "Error"(`danger`), "Info"(`info`); row spacing 6 |
| theme-preview-view-023 | status-badge-style | Inspect the "Success" badge's layer | 5pt corner radius, background = `success` at 22% alpha, border 1pt = `success` at 55% alpha, text = `success` at full opacity, `caption` font |
| theme-preview-view-024 | terminal-box-background | Inspect the terminal card's box | Fill = `palette.nsColor(.windowBackground)`, 1pt border = `palette.nsColor(.border)` |
| theme-preview-view-025 | terminal-appearance-resolution | Call `show(theme)` where `theme.terminal` overrides font/padding/cursor | The terminal sample's font, insets, and caret shape match `TerminalAppearance.resolvedFont/resolvedPadding/resolvedCursor(theme:)`, not the `UserSettings` defaults |
| theme-preview-view-026 | terminal-sample-content | Read the terminal card's content | Line 1: "user@mac ~ % ls" (`primaryText`) + caret; line 2: "Documents" (`accent`) and "README.md" (`secondaryText`), 10pt apart, 2pt below line 1 |
| theme-preview-view-027 | terminal-content-insets | Set a theme with `terminal.paddingLeading = 40` and call `show(theme)` | The terminal content stack's leading offset from the box is 40, not the 10pt default |
| theme-preview-view-028 | cursor-shape | Set `theme.terminal.cursorShape = .bar` and call `show(theme)` | The caret view is 2pt wide, `font.pointSize + 3` pt tall (the resolved terminal font's cell height, unchanged by `.bar`), filled with `palette.nsColor(.cursor)` |
| theme-preview-view-029 | ansi-swatch-grid | Call `show(theme)` and inspect the 6th arranged subview | It is a `ComposableSettings.SwatchGridView` constructed with `palette.ansiColors` (16 colors) and `columns: 8` |
| theme-preview-view-030 | semantic-palette-derivation | Call `show(themeA)` then `show(themeB)` with two themes differing only in `roleOverrides` | Every sample-card color equals what `SemanticPalette(theme: themeB)` resolves for its role (roles neither theme overrides may equal the `themeA` value; only an override-driven mismatch fails the vector) |
