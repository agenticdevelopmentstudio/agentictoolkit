<!-- leaf: implement-general-2/notes-and-history--part-2 · source: notes-and-history.md -->

# Notes and History — continued (part 2)

## Platform Notes

- **SwiftUI**: A `VStack(alignment: .leading, spacing: 16)` holding two
  child `VStack`s (one per section), each starting with a small,
  semibold, uppercase `Text` header. Within each child, switch on
  (loading, isEmpty) the same way the source's ternary does: a literal
  "Loading…" `Text` for the loading case, a muted "No admin notes."/"No
  history." `Text` for the empty case, and otherwise a `ForEach` over
  `Identifiable` note/history models rendering each item's fields — use a
  plain `ForEach` inside the `VStack`, not `List`, to avoid `List`'s row
  chrome and keep history rows as flat, unstyled lines like the source.
- **Compose**: A `Column(verticalArrangement = Arrangement.spacedBy(16.dp))`
  with a nested `Column` per section, each headed by a small, semibold,
  uppercase `Text`. Mirror the source's three-way branch with a `when` on
  (loading, list.isEmpty()): a "Loading…" `Text`, a "No admin notes."/"No
  history." `Text`, or a `Column` (or `LazyColumn` for very large lists)
  built with `items(notes)`/`items(history)` rendering each row.
- **React/Web**: Source file
  `packages/web/packages/adh-ui/src/blocks/notes-and-history.tsx`. A plain
  function component (`ReactElement`, no `"use client"` directive, no
  hooks) that consumes `AdminNote`/`HistoryEntry` from `../lib/
  invitations-types`. Two sibling `<section>`s in a `flex flex-col gap-4`
  container; each section is a ternary chain (`loading ? … : empty ? … :
  list`) styled with Tailwind utilities and the `apt-*` design-token
  vocabulary — no CSS modules, no styled-components.
- **AppKit/UIKit**: A vertical `UIStackView` (spacing 16) with two child
  stack views, each headed by a `UILabel` styled as small, semibold,
  uppercase (UIKit has no built-in `text-transform`, so uppercase the
  string directly or via `NSAttributedString`). Body content mirrors the
  source's flat, unvirtualized rendering: build a child `UIStackView` of
  one row view per note/history entry (a bordered/background view for
  notes, a plain `UILabel` line for history) rather than a `UITableView`,
  since the source never recycles rows or lazily loads.
- **WinUI 3** (the reason this recipe exists): Root `StackPanel
  Orientation="Vertical" Spacing="16"` with two child `StackPanel`s, each
  headed by a `TextBlock` using `Style="{StaticResource
  CaptionTextBlockStyle}"` plus `Foreground="{ThemeResource
  TextFillColorSecondaryBrush}"` — uppercase the header string in
  code-behind/x:Bind converter, since XAML has no CSS-style text
  transform. Bind an `ItemsRepeater` (not `ListView`, to avoid selection
  and virtualization chrome the source never has) to the notes/history
  collection inside each `StackPanel`; give each `StackPanel`/
  `ItemsRepeater` pair two independent `VisualStateGroup`s
  ("NotesState"/"HistoryState" with states "Loading"/"Empty"/"Populated"),
  driven by two independent `bool` `x:Bind` properties (`NotesLoading`,
  `HistoryLoading`) — mirroring the source's two separate loading flags
  rather than one shared loading state. Loading and empty `TextBlock`s use
  `Foreground="{ThemeResource TextFillColorTertiaryBrush}"` (mapping the
  source's dim `apt-text-dim`), and body-content `TextBlock`s use
  `Foreground="{ThemeResource TextFillColorPrimaryBrush}"` (mapping
  `apt-text`). Note item template: a `Border CornerRadius="6"
  BorderThickness="1" Padding="8"
  BorderBrush="{ThemeResource CardStrokeColorDefaultBrush}"
  Background="{ThemeResource CardBackgroundFillColorSecondaryBrush}"`
  wrapping a `StackPanel` with the content `TextBlock`
  (`TextFillColorPrimaryBrush`) and a secondary, muted `TextBlock`
  (`TextFillColorSecondaryBrush`, mapping `apt-text-muted`) reading
  "author · modifiedDate". History item template: a single `TextBlock`
  with a muted (`TextFillColorSecondaryBrush`) inline `Run` for the
  timestamp followed by a plain (`TextFillColorPrimaryBrush`) run reading
  " — actor action" — no `Border`, matching the source's unstyled history
  rows.

## Design Decisions

- **Decision**: Give notes and history independent loading flags
  (`notesLoading`, `historyLoading`) rather than one combined loading
  flag.
  **Rationale**: The source comment states each section "has its own loading
  flag — a slow history fetch never withholds already-loaded notes." A
  single shared flag would force both sections to wait on the slower of
  the two fetches.
  **Approved**: pending
- **Decision**: Keep the component purely presentational, with no internal
  data fetching, caching, or state management.
  **Rationale**: The source comment states "the caller fetches the data
  (react-query lives in the app, never here)." This keeps the block reusable
  by any caller regardless of its data-fetching strategy.
  **Approved**: pending
- **Decision**: Render admin notes as bordered/background cards
  (`rounded-md border ... bg-apt-surface-2/40 p-2`) while history entries
  render as plain, unstyled text lines.
  **Rationale**: Notes carry free-form, user-authored content that benefits
  from a visually distinct container; history entries are terse, uniform
  log lines that read better as a compact, unadorned list.
  **Approved**: pending
- **Decision**: Fix each section's heading at `<h4>` rather than exposing a
  configurable heading-level prop.
  **Rationale**: Source hardcodes `<h4>` for both "Admin notes" and
  "History" with no prop controlling it; `NotesAndHistory` is always
  composed as a sub-section of a larger detail panel, so its heading depth
  is assumed rather than negotiated with the caller. Accessibility
  tradeoff: a caller whose surrounding structure doesn't already place an
  `<h3>` (or shallower) immediately above this block will produce a
  skipped heading level for assistive-technology heading navigation — see
  **renders-notes-section**/**renders-history-section**.
  **Approved**: pending
