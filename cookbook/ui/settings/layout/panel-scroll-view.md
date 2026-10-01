---
id: 45b6d470-4e58-4035-b1c7-e65dbe7716b9
title: Panel Scroll View
domain: agentictoolkit://cookbook/ui/settings/layout/panel-scroll-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings scroll host that top-anchors panel content, pins it to
  the viewport width, and grows or scrolls to fit its height.
platforms:
- swift
- macos
tags:
- settings
- layout
- scroll-view
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Panel Scroll View

## Overview

The Panel Scroll View is the canonical scroll host for panel content
inside a composable settings system. It wraps a private, top-down document
view so hosted content top-anchors (settings read top-to-bottom) instead
of using the platform's default bottom-up document origin. Content
installed through the component's set-content operation has its width
pinned to exactly the scroll view's viewport width and its height
constrained to at least the viewport height, so the content's own fitting
size never drives the size of the panel or its containing window. Per the
source's own doc comment, the owning split view controller wraps every
non-self-scrolling panel in one, and master/detail pickers host their
detail panes in one, so rebuilt content can never tug a split view's
divider.

## Behavioral Requirements

- **document-view-flipped**: The document view MUST use a top-down
  coordinate system, so hosted content top-anchors instead of using a
  bottom-up document origin (see Platform Notes for the source's exact
  mechanism).
- **content-top-leading-anchored**: The document view MUST be pinned to
  the top and leading edges of the scroll view's own visible content area
  (viewport).
- **content-width-matches-viewport**: Content installed via the
  set-content operation MUST have its width constrained equal to the
  scroll view's viewport width, so the content's own fitting width never
  drives the size of the panel or its containing window.
- **content-min-height-viewport**: Content installed via the set-content
  operation MUST have its height constrained to be greater than or equal
  to the scroll view's viewport height, so short content fills the
  viewport and taller content triggers vertical scrolling.
- **content-fills-document-edges**: Content installed via the set-content
  operation MUST be pinned to the top, leading, trailing, and bottom edges
  of the document view.
- **content-replacement-removes-previous**: The set-content operation
  MUST remove every existing child of the document view before installing
  the new content.
- **content-replacement-resets-scroll-position**: The set-content
  operation SHOULD reset the scroll position to the top when it replaces
  the hosted content. Source calls no explicit scroll API; the reset
  follows only as a side effect of removing the previous content's
  constraints (which collapses the document view to zero size until the
  new content is installed and re-constrained).
- **vertical-scroller-enabled**: The scroll view MUST enable a vertical
  scroll indicator.
- **horizontal-scroller-enabled**: The scroll view MAY enable a horizontal
  scroll indicator. Source enables it unconditionally at construction, but
  content installed via the set-content operation always matches the
  viewport width (see **content-width-matches-viewport**), so this
  indicator can never actually be triggered through the public API; ports
  need not mirror it.
- **scrollers-autohide**: The scroll view MUST autohide its scroll
  indicators.
- **background-transparent**: The scroll view MUST NOT draw its own
  background.
- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **programmatic-instantiation-only**: The component MUST NOT support
  construction through a deserializing/decoding-based construction path;
  any such call MUST be rejected (compile-time on platforms with static
  availability annotations, a runtime trap otherwise — see Platform Notes
  for the source's exact mechanism).

## Appearance

- **Corner radius**: Not applicable — the component draws no background
  or border chrome of its own, so no corner radius applies.
- **Padding**: 0pt on all edges — every constraint in source (document to
  viewport at construction, and installed content to the document view in
  the set-content operation) omits an explicit constant, which defaults
  to 0.
- **Font**: Not applicable — the component renders no text of its own;
  any typography belongs to the content installed via the set-content
  operation.
- **Background**: Transparent — the scroll view paints no background of
  its own, so whatever sits behind it shows through.
- **Foreground/Text**: Not applicable — the same reasoning as Font; the
  component has no text or tint of its own to color.
- **Border**: Not applicable — no border color, width, or style is
  configured anywhere in the source; the view relies on the platform's
  inherited default and draws no background of its own.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in the source.
- **Min/Max size**: Not applicable — the component itself sets no minimum
  or maximum size constraint; only the *installed content's* height is
  constrained to be at least the viewport height (see
  **content-min-height-viewport**).

## States

| State | Appearance change |
|-------|------------------|
| Default | Scroll view is active; scroll indicators autohide until scrolling or hovering (**scrollers-autohide**). |
| Pressed | Not applicable |
| Disabled | Not applicable |
| Focused | Not applicable |
| Loading | Not applicable |

Not applicable (Pressed/Disabled/Focused/Loading): the component is not
an interactive control, so it has no pressed or enabled/disabled state in
source; construction does not override the platform's default
first-responder behavior, so focus belongs to whatever content is
installed via the set-content operation, not to the panel itself; and the
component has no loading or progress state anywhere in source.

## Accessibility

- **Role/trait**: The component is a scroll-container view that defines
  no custom accessibility role, subrole, or override in source; it
  inherits the platform's default scroll-area accessibility
  representation around whatever content the set-content operation
  installs.
- **Label requirements**: Not applicable — the component sets no
  accessibility label anywhere in source; a label describing the panel's
  contents is the responsibility of the content installed via the
  set-content operation, which has its own recipe.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading, disabled, or other transitional state of
  its own (see States); nothing in the source would need to announce a
  change.
- **Minimum tap target**: Not applicable — the component is not an
  interactive control and defines no clickable or tappable target of its
  own; scrolling is performed through the system-provided scroll
  indicator/trackpad gesture path, which source does not resize or
  override.
- **Keyboard / assistive technology navigation**: Source does not
  override the platform's default keyboard-handling behavior; keyboard
  scrolling (e.g. Page Down/Up) and screen-reader navigation are both
  provided by the inherited scroll-container behavior, unmodified by this
  component.
- **Contrast**: Not applicable — the component draws no background and
  sets no foreground or text color of its own; it renders no content that
  could fail a contrast check.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-scroll-view-001 | document-view-flipped | Inspect the document view's coordinate system on a newly constructed component | It reports a top-down coordinate system |
| panel-scroll-view-002 | content-top-leading-anchored | Inspect the document view's active constraints against the scroll view's viewport on a newly constructed component | The document view's top and leading edges are each constrained equal, constant 0, to the viewport's top and leading edges |
| panel-scroll-view-003 | content-width-matches-viewport | Install content whose intrinsic content width is wider than the current viewport, then resize the scroll view's frame | The content's width always equals the viewport's width; it never exceeds or falls short of the viewport width regardless of the content's intrinsic width |
| panel-scroll-view-004 | content-min-height-viewport | Install content whose intrinsic content height is smaller than the viewport height | The content's height is at least the viewport's height, filling the viewport with no gap below |
| panel-scroll-view-005 | content-fills-document-edges | Install content, then inspect the edge constraints between it and the document view | The content's top, leading, trailing, and bottom edges are each constrained equal, constant 0, to the document view's corresponding edges |
| panel-scroll-view-006 | content-replacement-removes-previous | Install content A, then install content B | After the second call, content A is no longer a child of the document view; only content B remains |
| panel-scroll-view-007 | content-replacement-resets-scroll-position | Scroll to the bottom of content A, then install content B | The scroll position returns to the top (origin) once content B is installed, as a side effect of removing content A's constraints rather than an explicit scroll reset |
| panel-scroll-view-008 | vertical-scroller-enabled | Inspect a newly constructed component | Its vertical scroll indicator is enabled |
| panel-scroll-view-009 | horizontal-scroller-enabled | Inspect a newly constructed component | Its horizontal scroll indicator is enabled |
| panel-scroll-view-010 | scrollers-autohide | Inspect a newly constructed component | Its scroll indicators autohide |
| panel-scroll-view-011 | background-transparent | Inspect a newly constructed component | It draws no background of its own |
| panel-scroll-view-013 | confines-to-ui-thread | Attempt to construct or call the set-content operation on the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking, runtime-checked otherwise) |
| panel-scroll-view-014 | programmatic-instantiation-only | Attempt to construct the component via a deserializing/decoding-based construction path | Rejected (compile-time when the construction path is marked unavailable; otherwise a trap); no instance is produced |
| panel-scroll-view-015 | content-width-matches-viewport | Host the component as one pane of a split view, record the split view's divider position, then install content whose intrinsic width is wider than the pane | The divider's position is unchanged after installation; the content's width still equals the viewport's width, never exceeding the pane's allotted width |

Test vector for the disabled-legacy-frame-system requirement
(**autoresizing-mask-disabled** in the source's own construction) moved to
Platform Notes, since it is a framework
construction rule with no equivalent on platforms that never had an
autoresizing-mask/frame-based layout system to disable in the first place.

## Edge Cases

- Null/empty input: the set-content operation takes a non-optional view;
  the type system rules out a missing value, so source contains no
  null-check path. When an empty (zero-intrinsic-size) view is installed,
  the width-equal/height-at-least constraints applied by the set-content
  operation still stretch it to the viewport's width and to at least its
  height (see **content-width-matches-viewport** and
  **content-min-height-viewport**), so the visible area is always filled.
- Boundary values (no content installed): before the set-content
  operation is ever called, the document view carries only the
  top/leading constraints activated at construction; it has no width or
  height constraint of its own, so its size resolves to zero in this
  state, since nothing else constrains it.
- Boundary values (re-installing the same instance): calling the
  set-content operation a second time with the same view instance that is
  already installed MUST first remove that instance and then re-add and
  re-constrain it, per the unconditional child-removal step in source.
- Concurrent access: Not applicable — the component is confined to the
  UI thread (see **confines-to-ui-thread**), so every read and write of
  its state, including calls to the set-content operation, is serialized
  to that thread; source provides no additional synchronization because
  none is needed.
- Error states: the set-content operation has no error return path and
  performs no validation of the given view. If that view already carries
  constraints or a parent relationship that conflicts with the four edge
  constraints the set-content operation activates, constraint activation
  does not throw (the underlying API is non-throwing); any conflict
  surfaces only as a layout-engine console diagnostic at runtime, since
  source contains no conflict detection or recovery.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; its behavior does not depend on connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|

Not applicable: the component exposes no configurable initializer
parameters or settable properties; its only public API besides
construction is the set-content operation, which installs content rather
than configuring the view (see Behavioral Requirements).

## Deep Linking

Not applicable: the component is a reusable scroll-hosting container, not
a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in the source.

## Localization

Not applicable: the source contains no string literal of any kind — so
there is nothing of its own to localize. Any localizable text belongs to
the content installed via the set-content operation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation or transition of any kind; there is no motion to substitute. |
| Increase Contrast | Not applicable: the component sets no custom color or drawing of its own; it has no appearance to adjust for contrast. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; it has no colored indicator anywhere in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in the source.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data; it
  only hosts and lays out a caller-supplied view.
- **Storage**: Not applicable — source performs no read or write to disk
  or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its document view
  and whatever content the caller last passed to the set-content
  operation, for its own lifetime; it persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

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
  `FlippedDocumentView` (satisfying `document-view-flipped` via
  `isFlipped == true`) and exposing one method, `setContent(_:)`. The
  scroll view and its document view each disable translation of the
  autoresizing mask into constraints
  (`translatesAutoresizingMaskIntoConstraints = false`), so layout is
  driven entirely by the explicit Auto Layout constraints in source; this
  is a pure framework construction rule with no equivalent step needed on
  a platform that never had a legacy autoresizing-mask/frame layout system
  to opt out of. `programmatic-instantiation-only` is met by marking
  `init(coder:)` `@available(*, unavailable)`, so the compiler rejects any
  call at compile time before the method's `fatalError()` body could ever
  run. A UIKit port would replace `NSScrollView`/`NSView` with
  `UIScrollView`/`UIView`, pinning the content to the scroll view's
  `contentLayoutGuide` with its width equal to the `frameLayoutGuide` width
  and its height greater than or equal to the `frameLayoutGuide` height;
  `UIScrollView`'s coordinate system is already top-down, so it needs no
  `FlippedDocumentView`-equivalent override (mirroring
  document-view-flipped is unnecessary on UIKit), and
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelScrollView.swift` |

## Design Decisions

**Decision**: Pin installed content's width equal to the viewport's width,
and its height only greater-than-or-equal to the viewport's height, rather
than letting the content's own intrinsic size dictate the panel's size.
**Rationale**: Per the source's own doc comment, the owning split view
controller wraps every non-self-scrolling panel in a Panel Scroll View,
and master/detail pickers host their detail panes in one, specifically so
that rebuilt content can never tug a split view's divider; pinning width
and floor-ing height keeps the panel's own footprint stable regardless of
what content is installed.
**Approved**: pending

**Decision**: Enable both the vertical and horizontal scroll indicators,
even though content-width-matches-viewport pins installed content's width
exactly to the viewport width, which means content added through the
set-content operation alone can never actually trigger horizontal
scrolling.
**Rationale** (AppKit): Source sets `hasHorizontalScroller = true`
unconditionally in `init`, before any content exists; it is not gated on
content width. Because the document view is private, callers have no path
to add subviews outside `setContent(_:)`, so the horizontal scroller is
incidental configuration rather than support for any caller-reachable
overflow case.
**Approved**: pending

**Decision** (AppKit): Use a private `FlippedDocumentView` with
`isFlipped == true` rather than the platform's default (unflipped)
document view.
**Rationale**: Per the source's own doc comment, settings content reads
top-to-bottom, and an unflipped document view places its origin at the
bottom-left, which would anchor new content at the bottom of the
scrollable area instead of the top.
**Approved**: pending

**Decision** (AppKit): Disable `init(coder:)` with
`@available(*, unavailable)` and a `fatalError`, leaving the parameterless
`init()` as the only usable initializer.
**Rationale**: The component has no archive-restorable state — it is
configured entirely by construction and then by a caller's set-content
call — so the decoding-based initializer that archive/nib loading would
otherwise use is intentionally disabled. Because the initializer is marked
unavailable, any call is rejected by the compiler rather than reaching the
`fatalError()` at runtime.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |

`keyboard-navigable` passes because the component overrides no
keyboard-handling behavior of the platform's default; keyboard scrolling
and screen-reader navigation are both provided, unmodified, by the
inherited scroll-container behavior (see Accessibility).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: downgrade content-replacement-resets-scroll-position and horizontal-scroller-enabled from MUST to SHOULD/MAY with corrected rationale; move the internal `agenticdevelopercookbook://` link from `references` to `related`; strip RFC 2119 keywords from non-requirement Edge Cases prose; fix "recipe"/"ingredient" wording in the WinUI 3 note; correct programmatic-instantiation-only and its test vector to describe compile-time rejection instead of a runtime trap; add an integration test vector for split-view divider stability; fix the WinUI 3 MinHeight binding to `SizeChanged` only; reformat Design Decisions to the canonical three-line form; replace invented Compliance citations with a real catalog check |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
