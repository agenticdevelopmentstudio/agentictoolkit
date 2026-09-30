<!-- leaf: implement-general-controller/multi-tabbed-view-controller--part-3 · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController — continued (part 3)

## Appearance

- **Corner radius**: `4pt` on each `TabButton`'s background pill
  (`backgroundView.layer?.cornerRadius`).
- **Padding**: Inside a `TabButton`: `10pt` leading from the background to the
  title label, `4pt` top/bottom between the label and the background, `6pt`
  between the label and the close button, `6pt` from the close button to the
  background's trailing edge, and the background itself is inset `2pt` from
  the button's own top/bottom. Inside `TabBarView`: `6pt` (`outerPadding`)
  between an item and the bar's outer (window) side only — the content
  (workspace) side is flush; `8pt` (`endPadding`) at each end of the bar along
  its length, overridable per edge via `setTabStartInset(_:for:)`; `4pt`
  (`itemSpacing`) between items on a horizontal bar, or `-16pt`
  (`cardOverlap`, a negative gap) between items on a vertical bar.
- **Font**: `.caption` text role (size and weight resolved by the active
  theme's typography, not a fixed point size in source) for a `TabButton`'s
  title label.
- **Background**: `TabBarView` fills with the `.windowBackground` palette
  role. The shared content area (`centerContainer`) fills with
  `centerBackgroundColor` when set, or the `.windowBackground` role when
  `nil`. A `TabButton`'s background is the `.selection` role when selected,
  or transparent (`NSColor.clear`) when not.
- **Foreground/Text**: A `TabButton`'s title label uses the `.selectionText`
  role when selected or `.secondaryText` when not; its close icon tints
  `.selectionText` when selected or `.tertiaryText` when not.
- **Border**: The shared content area draws a `1pt` border
  (`centerContainer.layer?.borderWidth`) in `centerOutlineColor` when set, or
  the resolved palette's `.outline` role when `nil`. No `TabButton` or bar
  itself draws a border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or `140pt`
  (left/right), and grows to the largest hosted item's `preferredContentSize`
  on that axis plus `6pt` when that is larger. The close button's hit area is
  a fixed `14×14pt`; its glyph (`xmark.circle.fill`) renders at `10pt`,
  `.regular` weight.

## Accessibility

- **Role/trait**: `TabButton` sets `accessibilityRole = .button` and
  `setAccessibilityElement(true)`, which stops AppKit from hoisting its
  subviews into the tree in its place (`TabButton.init`, `TabBarView.swift`).
  The controller's own view and `centerContainer` set no accessibility role —
  not applicable, they are plain layout containers, not controls.
- **Label requirements**: A `.title` tab exposes its title text via
  `setAccessibilityTitle(title)`; its close button carries its own identifier
  (`tab-bar.close.<uuid>`, distinct per tab since several bars can be on
  screen at once) and description ("Close Tab"), and is the sole entry
  `TabButton.accessibilityChildren()` republishes once the tab becomes its own
  element. A `.viewController` tab's own accessible content is entirely the
  hosted controller's concern — this component only forwards `isHighlighted`
  and `onClose` through `TabBarHostedItem` when the controller opts in.
- **Announce state changes**: `TabButton.isHighlighted`'s `didSet` updates
  that button's own `accessibilityValue`, so a click-driven selection is
  reflected on the pressed element itself, but nothing in
  `MultiTabbedViewController.swift` or `TabBarView.swift` posts an
  `NSAccessibility.post(element:notification:)` (or any other accessibility
  notification) when the active tab changes programmatically — a fallback
  activation after `removeTab`, `setEdgeEnabled`, or the sibling-selection
  update in `setSelected(_:)` across an edge's other tabs. A VoiceOver user
  tracking a different element is not told the active tab changed when no
  click of their own caused it.
- **Keyboard / assistive-technology navigation**: `TabButton` and
  `TabItemHostView` (`TabBarView.swift`) are plain `NSView` subclasses with no
  `acceptsFirstResponder`, `keyDown`, or key-view-loop wiring; a tab is
  reachable only by a pointer click (`mouseDown`) or an existing VoiceOver
  cursor's `accessibilityPerformPress()`. There is no way for a keyboard-only
  or Full Keyboard Access user to move focus onto a tab and activate it
  without a pointer or VoiceOver already positioned there.
- **Minimum tap target**: The close button's hit area is a fixed `14×14pt`
  (`TabButton.init`); the tab body (background, label, close button) is
  larger than that and is clickable everywhere outside the close button's own
  frame. macOS is a pointer-driven desktop platform; the `44×44pt` (iOS) /
  `48×48dp` (Android) touch-target minimums do not apply directly to this
  source and instead inform the touch-platform translations in Platform
  Notes.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `delegate` | `MultiTabbedViewControllerDelegate?` (weak) | `nil` | Receives tab lifecycle callbacks: new-tab request, select, active-tab change, close request, reorder. |
| `mainContentViewController` | `NSViewController?` | `nil` | Shown in the shared content area while no tab is active. |
| `contentInsets` | `NSEdgeInsets` | `NSEdgeInsetsZero` | Gap held between the mounted content and the tab bars/edges around it. |
| `centerBackgroundColor` | `NSColor?` | `nil` | Overrides the shared content area's fill; `nil` falls back to the `.windowBackground` role. |
| `centerOutlineColor` | `NSColor?` | `nil` | Overrides the shared content area's `1pt` border color; `nil` falls back to the palette's `.outline` role. |
| Tab start inset (`setTabStartInset(_:for:)` / `tabStartInset(for:)`) | `CGFloat` per `Edge` | `8` (`TabBarView.endPadding`) | Where a bar's first tab begins, measured along the bar from its start. |
| Edge enabled state (`setEdgeEnabled(_:_:)` / `isEdgeEnabled(_:)`) | `Bool` per `Edge` | `true` for `.top`; `false` for `.right`/`.bottom`/`.left` | Whether an edge's tab bar and tabs are shown at all. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for a `TabButton`'s close icon (`TabBarView.swift`) |

"Close Tab" is a hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file — it is the one non-data-driven,
user/AT-facing string this component itself owns (a tab's own title text is
always supplied by the caller, so it carries no localization concern of this
component's making).

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call anywhere in
  `MultiTabbedViewController.swift` or `TabBarView.swift`; every appearance
  change (selection restyle, thickness change, layout rebuild) applies
  immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`.selection`, `.selectionText`, `.secondaryText`, `.tertiaryText`,
  `.windowBackground`, `.outline`) is a semantic palette role; Increase
  Contrast handling, if any, belongs entirely to the theme/palette system this
  component defers to, not to this file.
- **Differentiate Without Color**: `TabButton.updateAppearance()`
  distinguishes selected from unselected purely by fill color (`.selection`
  vs. transparent) and a text-role swap (`.selectionText` vs.
  `.secondaryText`); no border, icon, weight, or other non-color cue
  accompanies the change. A `.viewController` item on a vertical edge gets a
  color-independent stacking/overlap cue from its `stackDepth`, but a
  `.title` tab never gets one, on any edge.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  list of tab ids, group ids, display titles, and view-controller references
  describing *how* tabs are arranged — never content the host chooses to
  display inside a hosted view controller.
- **Storage**: In-memory only, for the life of the controller (`edgeStates`,
  `tabBars`, `activeTabID`). Nothing in this source persists tab state to disk;
  any such persistence is entirely the host's own responsibility, outside this
  file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the controller's own lifetime; all tab and edge
  state is discarded when the controller is deallocated.

