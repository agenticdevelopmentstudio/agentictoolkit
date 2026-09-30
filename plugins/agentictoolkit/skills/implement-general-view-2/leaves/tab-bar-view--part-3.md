<!-- leaf: implement-general-view-2/tab-bar-view--part-3 · source: tab-bar-view.md -->

# TabBarView — continued (part 3)

- **onreorder-never-fires**: NEEDS REVIEW: Not implemented in source. `TabBarView.swift` declares `onReorder` and documents it, in a doc comment, as firing "after the user finishes dragging a tab to a new index," and `MultiTabbedViewController.swift` wires that closure straight to a delegate callback — but nothing in `TabBarView.swift` itself ever calls `onReorder`; there is no `NSDraggingSource` conformance, pasteboard registration, or other drag-and-drop or keyboard-driven reordering mechanism anywhere in the file, and `items`' only path to a new order is a caller directly calling `setItems(_:selectedID:)`, which does not go through `onReorder` at all. What is missing: the interaction — mouse drag or a keyboard equivalent — that determines a target index and invokes `onReorder(id, newIndex)`. What would settle it: an implementation of a drag session in `TabBarView.swift`, or confirmation that reordering is a future, not-yet-built feature and the callback exists ahead of it.
## Appearance

- **Corner radius**: `4pt` on `TabButton`'s `backgroundView` pill
  (`backgroundView.layer?.cornerRadius`). `TabBarView` and `TabItemHostView`
  set no corner radius of their own.
- **Padding**: Inside `TabButton`: `10pt` from `backgroundView`'s leading
  edge to `titleLabel`; `4pt` between `titleLabel` and `backgroundView`'s
  top/bottom; `6pt` between `titleLabel` and `closeButton`; `6pt` from
  `closeButton` to `backgroundView`'s trailing edge; `backgroundView` itself
  is inset `2pt` from `TabButton`'s own top and bottom. Inside `TabBarView`:
  `6pt` (`outerPadding`) between an item and the bar's outer (window) side
  only — the workspace side is flush; `8pt` (`endPadding`) at each end of the
  bar along its length, overridable per instance via `startInset`; `4pt`
  (`itemSpacing`) between items on a horizontal bar, or `-16pt`
  (`cardOverlap`, a negative gap) on a vertical bar.
- **Font**: `.caption` text role for `TabButton.titleLabel` (a `ThemedLabel`)
  — resolved size and weight come from the active theme's typography
  (`ThemeTypography.defaultStyle(.caption)` is `11pt`/`.regular` absent a
  theme override), not a literal point size in `TabBarView.swift` itself; the
  role does not change with selection, only the label's color role does (see
  Foreground/Text).
- **Background**: `TabBarView` fills with the `.windowBackground` palette
  role. `TabButton.backgroundView` fills with the `.selection` role when
  `isHighlighted` and `NSColor.clear` otherwise. `TabItemHostView` draws no
  background of its own.
- **Foreground/Text**: `TabButton.titleLabel.role` is `.selectionText` when
  highlighted, `.secondaryText` otherwise; `closeButton.contentTintColor`
  follows the same pair (`.selectionText` / `.tertiaryText`). Both roles are
  resolved by `SemanticPalette`, which is outside this file's own source.
- **Border**: Not drawn — no border width, color, or `bezelStyle` other than
  `closeButton`'s own `.inline`/`isBordered = false` (a borderless icon
  button) appears anywhere in `TabBarView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or `140pt`
  (left/right), growing to the largest hosted item's `preferredContentSize`
  on that axis plus `6pt` when that sum is larger (**thickness-grows-with-hosted-content**).
  `TabButton` has no explicit width/height constraint of its own; its size is
  whatever its content and fixed insets produce. `closeButton`'s hit area is
  a fixed `14×14pt`; its glyph (`xmark.circle.fill`) renders at `10pt`,
  `.regular` weight.

## Accessibility

- **Role/trait**: `TabButton` sets `accessibilityRole = .button` and
  `setAccessibilityElement(true)`, which stops AppKit from hoisting its
  subviews into the tree in its place (**tab-button-is-accessible-element**).
  `TabItemHostView` and `TabBarView` itself set no accessibility role of
  their own — they are plain layout/click-forwarding containers, not
  controls; a `.viewController` item's own accessible content is entirely
  the hosted controller's concern.
- **Label requirements**: A `.title` tab exposes its title text via
  `accessibilityTitle` (**tab-button-title-updates-accessibility**); its
  close button carries its own identifier (`tab-bar.close.<uuid>`, distinct
  per tab since several bars can be on screen at once) and the description
  "Close Tab", and is the sole entry `accessibilityChildren()` republishes
  once the tab button becomes its own element
  (**close-button-republished-as-sole-child**).
- **Announce state changes**: `TabButton.isHighlighted`'s `didSet` updates
  that button's own `accessibilityValue` on every change, whether it
  originates from a click or from a caller's `setSelected(_:)`
  (**tab-button-highlight-updates-accessibility-value**) — so, unlike a
  purely click-driven implementation, this file's own value updates are
  consistent for both origins. `TabBarView.swift` posts no explicit
  `NSAccessibility.post(element:notification:)` announcement anywhere;
  a VoiceOver user whose cursor is positioned elsewhere is not told that a
  different tab became selected — the update relies entirely on the moved
  focus element's own `accessibilityValue` being read if and when the
  cursor lands there.
- **Keyboard / assistive-technology navigation**: `TabButton` and
  `TabItemHostView` are plain `NSView` subclasses with no
  `acceptsFirstResponder`, `keyDown`, or key-view-loop wiring; a tab is
  reachable only by a pointer click (`mouseDown`) or an existing VoiceOver
  cursor's `accessibilityPerformPress()`. `closeButton` is a real `NSButton`
  and so remains independently reachable through the ordinary AppKit
  key-view loop (Full Keyboard Access), meaning a keyboard-only user may be
  able to close a tab yet has no way at all to select one — there is no
  keyboard-only or Full Keyboard Access path to move focus onto a tab and
  activate it without a pointer or VoiceOver cursor already positioned
  there.
- **Minimum tap target**: `closeButton`'s hit area is a fixed `14×14pt`; the
  rest of `TabButton` (background, label) is clickable everywhere outside
  that frame. macOS is a pointer-driven desktop platform; the `44×44pt`
  (iOS) / `48×48dp` (Android) touch-target minimums do not apply directly to
  this source and instead inform the touch-platform translations in
  Platform Notes.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `edge` | `Edge` | (required, set at init) | Which side of the container this bar is docked to; fixed for the bar's lifetime. |
| `startInset` | `CGFloat` | `8` (`TabBarView.endPadding`) | Where the first item begins, measured along the bar from its start. |
| `hostController` | `NSViewController?` (weak) | `nil` | Parent a `.viewController` item's controller is added to; unset means hosted controllers are never parented (see Edge Cases). |
| `onSelect` | `((UUID) -> Void)?` | `nil` | Invoked when a tab is clicked, or when an assistive-technology press activates one. |
| `onClose` | `((UUID) -> Void)?` | `nil` | Invoked when a tab's close control is activated. |
| `onReorder` | `((UUID, Int) -> Void)?` | `nil` | Declared for a caller to observe reordering; never invoked by this file itself (see the open question on onreorder-never-fires). |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for `TabButton`'s close icon |

"Close Tab" is a hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file — it is the one non-data-driven,
user/AT-facing string this component owns (a tab's own title text is always
supplied by the caller, so it carries no localization concern of this
component's making). No translated string table entry exists for it.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call anywhere in
  `TabBarView.swift`; every appearance change (selection restyle, thickness
  change, layout rebuild) applies immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`.selection`, `.selectionText`, `.secondaryText`, `.tertiaryText`,
  `.windowBackground`) is a semantic palette role; Increase Contrast
  handling, if any, belongs to the theme/palette system this file defers to,
  not to `TabBarView.swift` itself.
- **Differentiate Without Color**: `TabButton.updateAppearance()`
  distinguishes selected from unselected purely by fill color (`.selection`
  vs. transparent) and a text/icon color-role swap (`.selectionText` vs.
  `.secondaryText`/`.tertiaryText`); `titleLabel`'s `textRole` (and therefore
  its font) never changes, so no weight, size, border, or icon accompanies
  the change, and the component does not implement Differentiate Without
  Color support. A `.viewController` item on a vertical bar gets a
  color-independent stacking/overlap cue from its `stackDepth`, but a
  `.title` tab never gets one, on any edge.

## Privacy

- **Data collected**: None by this component itself. It holds only the tab
  ids, titles, and view-controller references it is given, describing how
  tabs are arranged — never content a hosted view controller chooses to
  display.
- **Storage**: In-memory only, for the life of the `TabBarView` instance
  (`items`, `buttons`, `hostedControllers`, `hostViews`). Nothing in this
  source persists tab state to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view's own lifetime; all state is discarded
  when the `TabBarView` is deallocated.

