<!-- leaf: implement-general-view-2/tab-pane-view--part-3 · source: tab-pane-view.md -->

# TabPaneView — continued (part 3)

## Appearance

- **Corner radius**: Not applicable — `TabCardBackgroundView.corners(of:)`
  traces straight line segments only; no rounded-rect or arc API is used
  anywhere in source, so every corner is square.
- **Padding**: `content.edgeInsets`: `top: 12, left: 14, bottom: 12, right:
  14` (`TabPaneView.padding`). `content.spacing`: `6pt` between arranged
  subviews. `statusStack.spacing`: `2pt` between status symbols. The header's
  own `NSStackView` spacing: `6pt` between the agent label, status stack,
  gap, and close button.
- **Font**: `agentLabel` and `sessionLabel` use `TextRole.body` (base `13pt`,
  `.regular` weight, per `ThemeTypography.font(for:)` — scales with the
  active theme's `sizeScale`). `directoryLabel`, `branchLabel`, and
  `summaryLabel` use `TextRole.caption` (base `11pt`, `.regular` weight, same
  scaling).
- **Background**: `isFrontCard == true`: the resolved palette's
  `projectPaneBackdrop` color. `isFrontCard == false`: the `windowBackground`
  role.
- **Foreground/Text**: `isFrontCard == true`: `agentLabel` in `.accent`;
  `sessionLabel` in `.primaryText`; `directoryLabel`/`branchLabel`/
  `summaryLabel` in `.secondaryText`; `closeButton.contentTintColor` in
  `.secondaryText`. `isFrontCard == false`: `agentLabel` in `.primaryText`;
  `sessionLabel` in `.secondaryText`; the remaining three labels and
  `closeButton.contentTintColor` in `.tertiaryText`.
- **Border**: `1pt` stroke (`TabCardBackgroundView.draw(_:)`,
  `path.lineWidth = 1`) in `projectPaneOutline` (front) or `border` (behind),
  traced along three sides only — the side facing the workspace is left open.
- **Shadow**: Not applicable — `TabCardBackgroundView.draw(_:)` only fills and
  strokes a path; no `NSShadow` or layer shadow property is set anywhere in
  source.
- **Min/Max size**: Card width: `240pt`–`340pt` (`minWidth`/`maxWidth`).
  Card height: `≥ 136pt` (`minHeight`), unbounded above. `closeButton` and
  each status `NSImageView`: fixed `14×14pt` frame. Status symbol glyphs
  render at `11pt`, `.regular` weight (`symbolConfiguration`); `closeButton`'s
  glyph carries no explicit `symbolConfiguration` and renders at AppKit's
  default button-image size within its `14×14pt` frame.

## Accessibility

- **Role/trait**: `TabPaneView` sets an `accessibilityIdentifier` on itself
  and on each subview (for UI-test addressing) but sets no `accessibilityRole`
  and does not mark itself an accessibility element or group its children
  into one (as `TabButton` does in `TabBarView.swift`, per the
  `multi-tabbed-view-controller` recipe). VoiceOver reads the card as five
  separate, individually-focused static-text elements in sequence, with no
  indication that they describe one tab.
- **Label requirements**: `closeButton`'s image carries `accessibilityDescription:
  "Close"` (see Localization). Each status `NSImageView` carries the caller-supplied
  `TabPaneStatusSymbol.accessibilityLabel` via `setAccessibilityLabel(_:)`.
  `agentLabel`, `sessionLabel`, `directoryLabel`, `branchLabel`, and
  `summaryLabel` receive no explicit `accessibilityLabel` call in this file;
  VoiceOver falls back to each `NSTextField`'s own `stringValue`, AppKit's
  default for a plain label control.
- **Announce state changes**: `applyDepth()` recolors and repositions the
  card whenever it becomes or stops being the front card, but nothing in
  `TabPaneView.swift` posts an `NSAccessibility.post(element:notification:)`
  (or any other accessibility notification) when that happens; a VoiceOver
  user tracking a different element is not told this card's selection state
  changed when no click of their own caused it.
- **Minimum tap target**: `closeButton`'s hit area is a fixed `14×14pt`
  (`closeButton.widthAnchor`/`heightAnchor`). macOS is a pointer-driven
  desktop platform; the `44×44pt` (iOS) / `48×48dp` (Android) touch-target
  minimums do not apply directly to this source and instead inform the
  touch-platform translations in Platform Notes.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stackDepth` | `Int` | `1` | How far back in the stack this card is drawn; `0` means the front (selected) card. |
| `onClose` | `(() -> Void)?` | `nil` | Called when `closeButton`'s action fires. |
| `contextMenuProvider` | `((NSEvent) -> NSMenu?)?` | `nil` | Supplies the menu `menu(for:)` returns; falls back to `super.menu(for:)` when `nil` or when it returns `nil`. |

`setStatusSymbols(_:)` takes `[TabPaneStatusSymbol]` (defined in the sibling
file `TabPaneStatusSymbol.swift`, same directory): a small `Equatable`,
`Sendable` struct pairing an SF Symbol name with an accessibility label.
Source defines one value, `.idle` (`symbolName: "moon.zzz"`,
`accessibilityLabel: "Idle"` — the value tab-pane-041 exercises); callers may
construct others directly via `TabPaneStatusSymbol(symbolName:accessibilityLabel:)`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for `closeButton`'s `xmark.circle.fill` glyph |

"Close" is a hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file. (The status symbols'
`accessibilityLabel` values, and every label's displayed text, are
caller-supplied data from `TabPaneDataSource`/`TabPaneStatusSymbol` — like a
tab's own title in the `multi-tabbed-view-controller` recipe, they carry no
localization concern of this view's own making.)

## Accessibility Options

- **Reduce Motion**: `place(animated:)` slides and resizes the card's paint
  and text boxes (a position *and* size change, not a plain opacity
  cross-fade) over `0.16s` whenever `stackDepth` changes on a windowed view;
  nothing in `TabPaneView.swift` checks
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (or any Reduce
  Motion signal) before running that animation, so a Reduce Motion user sees
  the same slide as anyone else.
- **Increase Contrast**: Not applicable — every color this component draws
  (`projectPaneBackdrop`, `projectPaneOutline`, `windowBackground`, `border`,
  `.accent`, `.primaryText`, `.secondaryText`, `.tertiaryText`) is a semantic
  palette role; Increase Contrast handling, if any, belongs to the
  theme/palette system this component defers to, not to this file.
- **Differentiate Without Color**: Supported. The front/behind distinction is
  never carried by color alone: a behind card is also drawn smaller and
  further from the workspace (`recession`, `≥ 4pt` on every side) and never
  overhangs the workspace's outline (`workspaceOverhang`), while the front
  card does both — a geometry-based cue that accompanies every color change
  `applyDepth()` makes.

## Privacy

- **Data collected**: None by this view itself. It renders caller-supplied
  display strings (agent/model name, session name, working-directory path,
  branch name, summary) and caller-supplied status symbols; it does not
  capture, log, or forward any of it elsewhere.
- **Storage**: In-memory only (`NSTextField.stringValue`, `NSImageView.image`)
  for the life of the view. Nothing in this source persists to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view's own lifetime.

