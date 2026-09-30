<!-- leaf: implement-panel/scroll-view · source: panel-scroll-view.md -->

**Rules** (cite as `implement-panel/scroll-view#<slug>`):

- `document-view-flipped` MUST
- `content-top-leading-anchored` MUST
- `content-width-matches-viewport` MUST
- `content-min-height-viewport` MUST
- `content-fills-document-edges` MUST
- `content-replacement-removes-previous` MUST
- `content-replacement-resets-scroll-position` SHOULD
- `vertical-scroller-enabled` MUST
- `horizontal-scroller-enabled` MAY
- `scrollers-autohide` MUST
- `background-transparent` MUST
- `autoresizing-mask-disabled` MUST
- `main-actor-isolated` MUST
- `programmatic-instantiation-only` MUST

# PanelScrollView

## Overview

`PanelScrollView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelScrollView.swift`)
is the canonical `NSScrollView` host for panel content inside `ComposableSettings`.
It wraps a private, flipped document view so hosted content top-anchors (settings
read top-to-bottom) instead of using AppKit's default bottom-up document origin.
Content installed through `setContent(_:)` has its width pinned to exactly the
scroll view's viewport width and its height constrained to at least the viewport
height, so the content's own fitting size never drives the size of the panel or
its containing window. Per the source's own doc comment, `SplitViewController`
wraps every non-self-scrolling panel in one, and master/detail pickers host their
detail panes in one, so rebuilt content can never tug a split view's divider.

## Behavioral Requirements

- **document-view-flipped**: The document view MUST report a flipped coordinate
  system (`isFlipped == true`) so hosted content top-anchors instead of using
  AppKit's default bottom-up document origin.
- **content-top-leading-anchored**: The document view MUST be pinned to the top
  and leading edges of the scroll view's `contentView`.
- **content-width-matches-viewport**: Content installed via `setContent(_:)`
  MUST have its width constrained equal to the scroll view's `contentView`
  width, so the content's own fitting width never drives the size of the panel
  or its containing window.
- **content-min-height-viewport**: Content installed via `setContent(_:)` MUST
  have its height constrained to be greater than or equal to the scroll view's
  `contentView` height, so short content fills the viewport and taller content
  triggers vertical scrolling.
- **content-fills-document-edges**: Content installed via `setContent(_:)` MUST
  be pinned to the top, leading, trailing, and bottom edges of the document
  view.
- **content-replacement-removes-previous**: `setContent(_:)` MUST remove every
  existing subview of the document view before installing the new content.
- **content-replacement-resets-scroll-position**: `setContent(_:)` SHOULD
  reset the scroll position to the top when it replaces the hosted content.
  Source calls no explicit scroll API; the reset follows only as a side
  effect of removing the previous content's constraints (which collapses the
  document view to zero size until the new content is installed and
  re-constrained).
- **vertical-scroller-enabled**: The scroll view MUST enable a vertical
  scroller (`hasVerticalScroller = true`).
- **horizontal-scroller-enabled**: The scroll view MAY enable a horizontal
  scroller (`hasHorizontalScroller = true`). Source sets it unconditionally in
  `init`, but content installed via `setContent(_:)` always matches the
  viewport width (see **content-width-matches-viewport**), so this scroller
  can never actually be triggered through the public API; ports need not
  mirror it.
- **scrollers-autohide**: The scroll view MUST autohide its scrollers
  (`autohidesScrollers = true`).
- **background-transparent**: The scroll view MUST NOT draw its own background
  (`drawsBackground = false`).
- **autoresizing-mask-disabled**: The scroll view and its document view MUST
  each disable translation of the autoresizing mask into constraints
  (`translatesAutoresizingMaskIntoConstraints = false`), so layout is driven
  entirely by the explicit Auto Layout constraints in source.
- **main-actor-isolated**: The component MUST be isolated to the main actor
  (`@MainActor`).
- **programmatic-instantiation-only**: The component MUST NOT support
  archive-based instantiation; `init(coder:)` is marked `@available(*,
  unavailable)`, so the compiler rejects any call at compile time before the
  method's `fatalError()` body could ever run.

## Appearance

- **Corner radius**: Not applicable — `PanelScrollView` draws no background or
  border chrome of its own (`drawsBackground = false`, no `borderType`
  override anywhere in source), so no corner radius applies.
- **Padding**: 0pt on all edges — every constraint in source (document to
  `contentView` in `init`, and installed content to the document view in
  `setContent`) omits an explicit `constant`, which defaults to `0`.
- **Font**: Not applicable — `PanelScrollView` renders no text of its own; any
  typography belongs to the content installed via `setContent`.
- **Background**: `drawsBackground = false` — the scroll view paints no
  background of its own, so whatever sits behind it shows through.
- **Foreground/Text**: Not applicable — the same reasoning as Font; the
  component has no text or tint of its own to color.
- **Border**: Not applicable — no `borderType`, border color, or border width
  is configured anywhere in `PanelScrollView.swift`; the view relies on
  `NSScrollView`'s inherited default and draws no background of its own.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `PanelScrollView.swift`.
- **Min/Max size**: Not applicable — `PanelScrollView` itself sets no minimum
  or maximum size constraint; only the *installed content's* height is
  constrained to be at least the viewport height (see
  content-min-height-viewport).

## Accessibility

- **Role/trait**: `PanelScrollView` is an `NSScrollView` subclass that defines
  no custom accessibility role, subrole, or `NSAccessibilityElement` override
  in source; it inherits AppKit's default scroll-area accessibility
  representation around whatever content `setContent` installs.
- **Label requirements**: Not applicable — `PanelScrollView` sets no
  `accessibilityLabel` anywhere in source; a label describing the panel's
  contents is the responsibility of the content installed via `setContent`,
  which has its own recipe.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading, disabled, or other transitional state of its own
  (see States); nothing in `PanelScrollView.swift` would need to announce a
  change.
- **Minimum tap target**: Not applicable — `PanelScrollView` is not an
  `NSControl` and defines no clickable or tappable target of its own;
  scrolling is performed through the system-provided `NSScroller`/trackpad
  gesture path, which source does not resize or override.
- **Keyboard / assistive technology navigation**: Source does not override
  `acceptsFirstResponder`, `keyDown`, or any keyboard-handling method;
  keyboard scrolling (e.g. Page Down/Up) and VoiceOver navigation are both
  provided by the inherited `NSScrollView`/`NSClipView` behavior, unmodified
  by this class.
- **Contrast**: Not applicable — `PanelScrollView` sets `drawsBackground =
  false` and no foreground or text color of its own; it renders no content
  that could fail a contrast check.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|

Not applicable: `PanelScrollView` exposes no configurable initializer
parameters or settable properties; its only public API besides `init()` is
`setContent(_:)`, which installs content rather than configuring the view
(see Behavioral Requirements).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call of any kind; there is no motion to substitute. |
| Increase Contrast | Not applicable: `PanelScrollView.swift` sets no custom `NSColor` or drawing of its own; it has no appearance to adjust for contrast. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; it has no colored indicator anywhere in source. |

## Privacy

- **Data collected**: Not applicable — the component collects no data; it
  only hosts and lays out a caller-supplied `NSView`.
- **Storage**: Not applicable — source performs no read or write to disk,
  `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its document view and
  whatever content the caller last passed to `setContent`, for its own
  lifetime; it persists nothing beyond that.

