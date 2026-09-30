<!-- leaf: implement-panel/scroll-view--part-2 · source: panel-scroll-view.md -->

# PanelScrollView — continued (part 2)

**Rules** (cite as `implement-panel/scroll-view--part-2#<slug>`):

- `compose` SHOULD — Start from a Column inside Modifier.verticalScroll( rememberScrollState()), with the content given …

## Platform Notes

- **SwiftUI**: Start from `ScrollView(.vertical)` — content is pinned to the
  viewport width (mirroring content-width-matches-viewport), so horizontal
  scrolling can never trigger; adding `[.vertical, .horizontal]` only mirrors
  horizontal-scroller-enabled's incidental configuration and is optional.
  Wrap the content in a container pinned with `.frame(maxWidth: .infinity,
  alignment: .top)`. Read the
  viewport size with a `GeometryReader`/`.containerRelativeFrame` and apply
  `.frame(minHeight: viewportHeight)` to the content to mirror
  content-min-height-viewport — SwiftUI has no direct
  `greaterThanOrEqualTo`-style modifier the way Auto Layout does. SwiftUI's
  `ScrollView` is already top-down, so no flipped-coordinate trick (mirroring
  document-view-flipped) is needed. To mirror
  content-replacement-resets-scroll-position, wrap the content in a
  `ScrollViewReader` and call `scrollTo` the top anchor when the identity of
  the hosted content changes.
- **Compose**: Start from a `Column` inside `Modifier.verticalScroll(
  rememberScrollState())`, with the content given `Modifier.fillMaxWidth()`
  to mirror content-width-matches-viewport and `Modifier.heightIn(min = ...)`
  sized from a `BoxWithConstraints` to mirror content-min-height-viewport.
  Because content always fills the available width, adding
  `Modifier.horizontalScroll` can never trigger; it only mirrors
  horizontal-scroller-enabled's incidental configuration and is optional.
  Compose's scroll containers are already top-down, so no flipped-coordinate
  handling is needed. Reset scroll position on content replacement by calling
  `scrollState.scrollTo(0)` inside a `LaunchedEffect` keyed on the content's
  identity, mirroring content-replacement-resets-scroll-position (source
  itself only resets scroll position as a side effect of removing the
  previous content's constraints, so treat this as a SHOULD, not a hard
  guarantee, when porting).
- **React/Web**: Start from a plain `div` with `overflow-y: auto` on the
  outer element and `width: 100%; min-height: 100%; box-sizing: border-box`
  on the content, which map directly to content-width-matches-viewport and
  content-min-height-viewport. Because the content is always full width,
  adding `overflow-x: auto` (mirroring horizontal-scroller-enabled) can never
  trigger and is optional. The web's default coordinate system is already
  top-down, so no flipped-view
  equivalent of document-view-flipped is needed. Scroller autohide
  (scrollers-autohide) is an OS/browser display preference rather than
  something the component sets; reset scroll position on content replacement
  with `scrollTop = 0` in the same effect that swaps the content, mirroring
  content-replacement-resets-scroll-position.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelScrollView.swift`.
  A macOS-only (`import AppKit`) `NSScrollView` subclass, `@MainActor`,
  nested in the `ComposableSettings` namespace, wrapping a private
  `FlippedDocumentView` and exposing one method, `setContent(_:)`. A UIKit
  port would replace `NSScrollView`/`NSView` with `UIScrollView`/`UIView`,
  pinning the content to the scroll view's `contentLayoutGuide` with its
  width equal to the `frameLayoutGuide` width and its height greater than or
  equal to the `frameLayoutGuide` height; `UIScrollView`'s coordinate system
  is already top-down, so it needs no `FlippedDocumentView`-equivalent
  override (mirroring document-view-flipped is unnecessary on UIKit), and
  `showsVerticalScrollIndicator`/`showsHorizontalScrollIndicator` already
  autohide by default, so scrollers-autohide needs no extra configuration
  there either.
- **WinUI 3** (the reason this ingredient exists): Start from a
  `ScrollViewer` with `VerticalScrollBarVisibility="Auto"` (mirroring
  vertical-scroller-enabled and scrollers-autohide, since WinUI's `Auto`
  visibility shows a scrollbar only while scrolling and fades it otherwise).
  `HorizontalScrollBarVisibility="Auto"` mirrors horizontal-scroller-enabled
  but is optional: since `Content` is always stretched to the viewport width
  (below), horizontal scrolling can never trigger, so a vertical-only
  `ScrollViewer` is an equally faithful port. Give the `Content` element
  `HorizontalAlignment="Stretch"` to mirror content-width-matches-viewport.
  `ScrollViewer` has no declarative "at least the viewport height" constraint
  the way `NSLayoutConstraint.greaterThanOrEqualTo` does, so mirror
  content-min-height-viewport by binding the content's `MinHeight` to the
  `ScrollViewer`'s `ViewportHeight`, updated from the `ScrollViewer`'s
  `SizeChanged` event only (`ViewChanging` fires on scroll, not resize, so it
  cannot track viewport height changes; a value converter or code-behind
  handler is needed either way, since XAML bindings alone cannot express the
  inequality). WinUI is already top-down, so no flipped-coordinate handling
  is needed
  (mirroring document-view-flipped is a no-op there). To mirror
  content-replacement-removes-previous and
  content-replacement-resets-scroll-position, clear and reassign `Content`
  and then call `ChangeView(0, 0, 1, disableAnimation: true)`, since
  assigning a new `Content` does not by itself reset `ScrollViewer`'s scroll
  offset.

## Design Decisions

**Decision**: Pin installed content's width equal to the viewport's width,
and its height only greater-than-or-equal to the viewport's height, rather
than letting the content's own intrinsic size dictate the panel's size.
**Rationale**: Per the source's own doc comment, `SplitViewController` wraps
every non-self-scrolling panel in a `PanelScrollView`, and master/detail
pickers host their detail panes in one, specifically so that rebuilt content
can never tug a split view's divider; pinning width and floor-ing height
keeps the panel's own footprint stable regardless of what content is
installed.
**Approved**: pending

**Decision**: Enable both `hasVerticalScroller` and `hasHorizontalScroller`,
even though content-width-matches-viewport pins installed content's width
exactly to the viewport width, which means content added through
`setContent(_:)` alone can never actually trigger horizontal scrolling.
**Rationale**: Source sets `hasHorizontalScroller = true` unconditionally in
`init`, before any content exists; it is not gated on content width. Because
the document view (`document`) is private, callers have no path to add
subviews outside `setContent(_:)`, so the horizontal scroller is incidental
configuration rather than support for any caller-reachable overflow case.
**Approved**: pending

**Decision**: Use a private `FlippedDocumentView` with `isFlipped == true`
rather than the AppKit default (unflipped) document view.
**Rationale**: Per the source's own doc comment, settings content reads
top-to-bottom, and an unflipped `NSScrollView` document places its origin at
the bottom-left, which would anchor new content at the bottom of the
scrollable area instead of the top.
**Approved**: pending

**Decision**: Disable `init(coder:)` with `@available(*, unavailable)` and a
`fatalError`, leaving the parameterless `init()` as the only usable
initializer.
**Rationale**: `PanelScrollView` has no archive-restorable state — it is
configured entirely by `init()` and then by a caller's `setContent(_:)` call
— so the `NSCoding`-based initializer that Interface Builder/nib loading
would otherwise use is intentionally disabled. Because the initializer is
marked unavailable, any call is rejected by the compiler rather than
reaching the `fatalError()` at runtime.
**Approved**: pending
