<!-- leaf: implement-general-view-3/theme-preview-view--part-2 · source: theme-preview-view.md -->

# ThemePreviewView — continued (part 2)

## Appearance

- **Corner radius**: `self` has none. Every sample card box (`roundedBox`) has
  an 8pt corner radius. The controls sample's two simulated text fields
  override this to 5pt. List rows and status badges use 5pt. ANSI swatches
  (in the embedded `SwatchGridView`) use 3pt — see that recipe.
- **Padding**: Card content is inset 10pt top / 12pt leading / ≤12pt trailing
  (may be narrower) / 10pt bottom, per `card-content-insets`. The
  terminal sample instead insets by the theme's resolved terminal padding
  (default 10pt on all four sides, per `TerminalAppearance`/`UserSettings`
  defaults) rather than the fixed 10/12/12/10 shape.
- **Font**: `title`, `body`, `caption` and `button` `TextRole` styles from
  `theme.typography`, resolved via `palette.font(_:)`. The terminal sample
  uses the theme's resolved monospaced terminal font
  (`TerminalAppearance.resolvedFont(theme:)`) instead of any `TextRole`.
- **Background**: `self` — the theme's `windowBackground`. Chrome, list,
  controls and status cards — `surface`. The terminal card —
  `windowBackground` (see `terminal-box-background`). The
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
- **Min/Max size**: Every card box and the terminal
  box each carry a `widthAnchor >= 280` constraint; `self` and `container`
  have no explicit min/max size of their own — the view's overall size is
  driven by its arranged content plus whatever constraints a host applies to
  `self`.

## Accessibility

- **Role/trait**: Every `NSTextField(labelWithString:)` label exposes itself
  to VoiceOver as static text by AppKit's own default; no other view (`box`,
  `pill`, `badge`, `row`, the caret, the hairline) has `setAccessibilityRole`,
  `setAccessibilityElement`, or any similar call anywhere in
  `ThemePreviewView.swift`, so none of those containers expose a semantic
  grouping of their own. Neither the whole preview nor any sample card is
  combined into a single accessibility element with a summarizing label;
  VoiceOver reads roughly twenty individual demo labels one at a time, with
  no indication they belong to a "theme preview" rather than live
  application state.
- **Label requirements**: All visible text is the literal English demo
  strings itemized in Behavioral Requirements (see also Localization); no
  `accessibilityLabel`/`accessibilityValue` override is set anywhere, so
  VoiceOver reads exactly that literal text. Nothing in source distinguishes
  illustrative sample text ("Window Title", "Success", "Documents") from a
  real value a user could act on — VoiceOver has only that literal demo
  string to read either way.
- **Announce state changes**: Not applicable — `show(_:)` is the only
  mutating entry point, runs synchronously to completion on the main actor,
  and there is no loading indicator or asynchronous transition to announce
  (see States/Loading).
- **Minimum tap target**: Not applicable — this is a macOS, pointer/trackpad
  composition with no interactive element anywhere in source (see
  States/Pressed), so there is no touch target to size. The embedded
  `SwatchGridView`'s own accessibility posture is documented in its own
  recipe (`agentictoolkit://recipes/swatch-grid-view`), not repeated here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `theme` | `ColorTheme?` | `nil` | Passed to `init(theme:)`; when non-nil, `show(_:)` is called immediately during initialization. When `nil`, the view starts empty (`empty-initial-state`). |

The only other entry point is the public method `show(_ theme: ColorTheme)`,
which fully tears down and rebuilds the preview for a new theme (see
Behavioral Requirements); it is not an initializer option and so is
documented there rather than in this table.

## Localization

None of the keys below exist in source — `ThemePreviewView.swift` makes no
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

Every string above is a literal passed to `NSTextField(labelWithString:)` (an
AppKit `stringValue` set from a literal, not SwiftUI's
`Text`/`LocalizedStringKey`), and none of it is routed through
`NSLocalizedString` or any localization table anywhere in
`ThemePreviewView.swift`. Source gives no localization path today for any of
these illustrative demo strings.

## Accessibility Options

- **Reduce Motion**: Not applicable — `show(_:)` and every `make*Sample`
  helper perform an instantaneous full teardown and rebuild
  (`removeFromSuperview()`/`addArrangedSubview(_:)`); no `NSAnimationContext`,
  animator proxy, or transition of any kind appears anywhere in
  `ThemePreviewView.swift`, so there is no motion for Reduce Motion to
  substitute for.
- **Increase Contrast**: Not applicable at this component's own level — every
  color is read through `SemanticPalette`'s role API
  (`semantic-palette-derivation`); `ThemePreviewView`
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

