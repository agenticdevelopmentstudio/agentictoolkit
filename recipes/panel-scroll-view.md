---
id: 45b6d470-4e58-4035-b1c7-e65dbe7716b9
title: PanelScrollView
domain: agentictoolkit://recipes/panel-scroll-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings scroll host that top-anchors panel content, pins
  it to the viewport width, and grows or scrolls to fit its height.
platforms:
- swift
- macos
tags:
- settings
- layout
- scroll-view
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

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
- **content-replacement-resets-scroll-position**: `setContent(_:)` MUST reset
  the scroll position to the top when it replaces the hosted content.
- **vertical-scroller-enabled**: The scroll view MUST enable a vertical
  scroller (`hasVerticalScroller = true`).
- **horizontal-scroller-enabled**: The scroll view MUST enable a horizontal
  scroller (`hasHorizontalScroller = true`).
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
  archive-based instantiation; `init(coder:)` MUST terminate the process with a
  fatal error.

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Scroll view is active; scrollers autohide until scrolling or hovering (`autohidesScrollers = true`). |
| Pressed | Not applicable |
| Disabled | Not applicable |
| Focused | Not applicable |
| Loading | Not applicable |

Not applicable (Pressed/Disabled/Focused/Loading): `NSScrollView` is not an
`NSControl`, so `PanelScrollView` has no pressed or enabled/disabled state in
source; `init` does not override `acceptsFirstResponder`, so focus belongs to
whatever content is installed via `setContent`, not to the panel itself; and
the component has no loading or progress state anywhere in
`PanelScrollView.swift`.

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-scroll-view-001 | document-view-flipped | Inspect `documentView.isFlipped` on a newly constructed `PanelScrollView` | `isFlipped` returns `true` |
| panel-scroll-view-002 | content-top-leading-anchored | Inspect the document view's active constraints against `contentView` on a newly constructed `PanelScrollView` | Document view's top and leading anchors are each constrained equal, constant `0`, to `contentView`'s top and leading anchors |
| panel-scroll-view-003 | content-width-matches-viewport | Call `setContent(view)` with `view` whose intrinsic content width is wider than the current viewport, then resize the scroll view's frame | `view`'s width always equals `contentView.frame.width`; it never exceeds or falls short of the viewport width regardless of `view`'s intrinsic width |
| panel-scroll-view-004 | content-min-height-viewport | Call `setContent(view)` with `view` whose intrinsic content height is smaller than the viewport height | `view`'s height is at least `contentView.frame.height`, filling the viewport with no gap below |
| panel-scroll-view-005 | content-fills-document-edges | Call `setContent(view)`, then inspect the edge constraints between `view` and the document view | `view`'s top, leading, trailing, and bottom anchors are each constrained equal, constant `0`, to the document view's corresponding anchors |
| panel-scroll-view-006 | content-replacement-removes-previous | Call `setContent(viewA)`, then call `setContent(viewB)` | After the second call, `viewA` is no longer a subview of the document view; only `viewB` remains |
| panel-scroll-view-007 | content-replacement-resets-scroll-position | Scroll to the bottom of `viewA`'s content, then call `setContent(viewB)` | The scroll position returns to the top (origin) once `setContent` installs `viewB` |
| panel-scroll-view-008 | vertical-scroller-enabled | Inspect a newly constructed `PanelScrollView` | `hasVerticalScroller == true` |
| panel-scroll-view-009 | horizontal-scroller-enabled | Inspect a newly constructed `PanelScrollView` | `hasHorizontalScroller == true` |
| panel-scroll-view-010 | scrollers-autohide | Inspect a newly constructed `PanelScrollView` | `autohidesScrollers == true` |
| panel-scroll-view-011 | background-transparent | Inspect a newly constructed `PanelScrollView` | `drawsBackground == false` |
| panel-scroll-view-012 | autoresizing-mask-disabled | Inspect a newly constructed `PanelScrollView` and its document view | `translatesAutoresizingMaskIntoConstraints == false` on both the scroll view and the document view |
| panel-scroll-view-013 | main-actor-isolated | Attempt to construct or call `setContent` on a `PanelScrollView` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-scroll-view-014 | programmatic-instantiation-only | Attempt `PanelScrollView(coder: someCoder)` | The call traps with a fatal error; no instance is produced |

## Edge Cases

- Null/empty input: `setContent(_:)` takes a non-optional `NSView`; Swift's
  type system rules out `nil` for `view`, so source contains no null-check
  path. This is a MUST: when an empty (zero-intrinsic-size) view is installed,
  the `equalTo`/`greaterThanOrEqualTo` constraints in `setContent` still
  stretch it to `contentView`'s width and to at least its height, so the
  visible area is always filled.
- Boundary values (no content installed): before `setContent` is ever called,
  the document view carries only the top/leading constraints activated in
  `init`; it has no width or height constraint of its own. This is a MUST:
  the document view's size resolves to zero in this state, since nothing else
  constrains it.
- Boundary values (re-installing the same instance): calling `setContent(_:)`
  a second time with the same view instance that is already installed MUST
  first remove that instance via `removeFromSuperview()` and then re-add and
  re-constrain it, per the unconditional `document.subviews.forEach {
  $0.removeFromSuperview() }` in source.
- Concurrent access: Not applicable — `PanelScrollView` is `@MainActor`-
  isolated (see main-actor-isolated), so every read and write of its state,
  including calls to `setContent`, is serialized on the main actor; source
  provides no additional synchronization because none is needed.
- Error states: `setContent(_:)` has no error return path and performs no
  validation of `view`. This is a MUST: if `view` already carries constraints
  or a superview relationship that conflicts with the four edge constraints
  `setContent` activates, `NSLayoutConstraint.activate` does not throw (the
  API is non-throwing); any conflict SHOULD surface only as an Auto Layout
  console diagnostic at runtime, since source contains no conflict detection
  or recovery.
- Offline/disconnected: Not applicable — `PanelScrollView` performs no
  networking of its own; its behavior does not depend on connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|

Not applicable: `PanelScrollView` exposes no configurable initializer
parameters or settable properties; its only public API besides `init()` is
`setContent(_:)`, which installs content rather than configuring the view
(see Behavioral Requirements).

## Deep Linking

Not applicable: `PanelScrollView` is a reusable scroll-hosting container, not
a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `PanelScrollView.swift`.

## Localization

Not applicable: `PanelScrollView.swift` contains no string literal of any
kind — no `Text`, `Label`, `title`, or `stringValue` — so there is nothing of
its own to localize. Any localizable text belongs to the content installed
via `setContent`.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call of any kind; there is no motion to substitute. |
| Increase Contrast | Not applicable: `PanelScrollView.swift` sets no custom `NSColor` or drawing of its own; it has no appearance to adjust for contrast. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; it has no colored indicator anywhere in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `PanelScrollView.swift`.

## Analytics

Not applicable: `PanelScrollView.swift` contains no analytics or telemetry
call.

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

## Logging

Not applicable: `PanelScrollView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Start from `ScrollView(.vertical)` (or `[.vertical,
  .horizontal]` to mirror both scrollers) wrapping the content in a container
  pinned with `.frame(maxWidth: .infinity, alignment: .top)`. Read the
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
  rememberScrollState())` combined with `Modifier.horizontalScroll(
  rememberScrollState())`, with the content given `Modifier.fillMaxWidth()`
  to mirror content-width-matches-viewport and `Modifier.heightIn(min = ...)`
  sized from a `BoxWithConstraints` to mirror content-min-height-viewport.
  Compose's scroll containers are already top-down, so no flipped-coordinate
  handling is needed. Reset scroll position on content replacement by calling
  `scrollState.scrollTo(0)` inside a `LaunchedEffect` keyed on the content's
  identity, mirroring content-replacement-resets-scroll-position.
- **React/Web**: Start from a plain `div` with `overflow-y: auto;
  overflow-x: auto` on the outer element and `width: 100%; min-height: 100%;
  box-sizing: border-box` on the content, which map directly to
  content-width-matches-viewport and content-min-height-viewport. The web's
  default coordinate system is already top-down, so no flipped-view
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
- **WinUI 3** (the reason this recipe exists): Start from a `ScrollViewer`
  with `VerticalScrollBarVisibility="Auto"` and
  `HorizontalScrollBarVisibility="Auto"` (mirroring
  vertical-scroller-enabled/horizontal-scroller-enabled and
  scrollers-autohide, since WinUI's `Auto` visibility shows a scrollbar only
  while scrolling and fades it otherwise). Give the `Content` element
  `HorizontalAlignment="Stretch"` to mirror content-width-matches-viewport.
  `ScrollViewer` has no declarative "at least the viewport height" constraint
  the way `NSLayoutConstraint.greaterThanOrEqualTo` does, so mirror
  content-min-height-viewport by binding the content's `MinHeight` to the
  `ScrollViewer`'s `ViewportHeight`, updated from the `ScrollViewer`'s
  `SizeChanged`/`ViewChanging` event (a value converter or code-behind
  handler, since XAML bindings alone cannot express the inequality). WinUI
  is already top-down, so no flipped-coordinate handling is needed
  (mirroring document-view-flipped is a no-op there). To mirror
  content-replacement-removes-previous and
  content-replacement-resets-scroll-position, clear and reassign `Content`
  and then call `ChangeView(0, 0, 1, disableAnimation: true)`, since
  assigning a new `Content` does not by itself reset `ScrollViewer`'s scroll
  offset.

## Design Decisions

- Decision: Pin installed content's width equal to the viewport's width, and
  its height only greater-than-or-equal to the viewport's height, rather than
  letting the content's own intrinsic size dictate the panel's size.
  Rationale: per the source's own doc comment, `SplitViewController` wraps
  every non-self-scrolling panel in a `PanelScrollView`, and master/detail
  pickers host their detail panes in one, specifically so that rebuilt
  content can never tug a split view's divider; pinning width and floor-ing
  height keeps the panel's own footprint stable regardless of what content is
  installed.
  Approved: pending
- Decision: Enable both `hasVerticalScroller` and `hasHorizontalScroller`,
  even though content-width-matches-viewport pins installed content's width
  exactly to the viewport width, which means content added through
  `setContent(_:)` alone can never actually trigger horizontal scrolling.
  Rationale: source does not gate `hasHorizontalScroller` behind whether
  content is wider than the viewport; it is set unconditionally in `init`,
  before any content exists, so the scroll view is prepared for horizontal
  overflow from any subview a caller might add to the document view outside
  the sanctioned `setContent(_:)` path.
  Approved: pending
- Decision: Use a private `FlippedDocumentView` with `isFlipped == true`
  rather than the AppKit default (unflipped) document view.
  Rationale: per the source's own doc comment, settings content reads
  top-to-bottom, and an unflipped `NSScrollView` document places its origin
  at the bottom-left, which would anchor new content at the bottom of the
  scrollable area instead of the top.
  Approved: pending
- Decision: Disable `init(coder:)` with `@available(*, unavailable)` and a
  `fatalError`, leaving the parameterless `init()` as the only usable
  initializer.
  Rationale: `PanelScrollView` has no archive-restorable state — it is
  configured entirely by `init()` and then by a caller's `setContent(_:)`
  call — so the `NSCoding`-based initializer that Interface Builder/nib
  loading would otherwise use is intentionally disabled rather than left to
  produce a half-configured scroll view.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | Architecture |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | Accessibility |

`main-actor-confined` passes because the class is declared `@MainActor` (see **main-actor-isolated**). `differentiate-without-color` passes because `PanelScrollView` sets no color of its own and conveys no state through color — it only hosts and positions caller-supplied content.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
