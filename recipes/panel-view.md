---
id: 4b1a3eb0-0a8a-4059-b2ac-824013072bd5
title: PanelView
domain: agentictoolkit://recipes/panel-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit macOS NSView that stacks GroupView cards and PanelHeadingView headings
  inside a themed panel, matching System Settings' outer layout.
platforms:
- swift
- macos
tags:
- settings
- layout
- macos
- appkit
depends-on:
- agentictoolkit://recipes/group-view
- agentictoolkit://recipes/panel-heading-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# PanelView

## Overview

`ComposableSettings.PanelView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelView.swift`,
is the root container for a `ComposableSettings` panel: an `open`, `@MainActor`
`NSView` subclass conforming to `SettingsViewProtocol` that hosts a vertical
stack of `GroupView` cards, spaced apart inside the panel's content area, per
the source's own doc comment. It owns a single internal `NSStackView` inset
from its own edges by the panel's outer margin, paints its own layer
background from the active theme, and exposes exactly two mutating calls:
`addGroup(_:)`, which appends a `GroupView` card, and `addHeading(_:
caption:)`, which appends a `PanelHeadingView` (constructed internally) ahead
of the groups that follow it, widening the gap above it so the heading reads
as belonging to what comes after it rather than as a caption trailing the
card above — per the source's own comment on `addHeading`. Both `GroupView`
and `PanelHeadingView` are separate components with their own recipes; this
recipe covers only what `PanelView.swift` itself does with them. The
background color is resolved through a `ThemePaletteObserver` (from the
`agenticdevelopertoolkit` submodule's `ThemeBinding.swift`), created with
`host: self` so the color tracks `PanelView`'s own resolved `ThemeScope`
rather than the app-wide default; the source's own comment on that call
explains the choice of color: "The same ground as the sidebar and the
window: the cards are what stand out here, and a panel-shaped patch of a
second near-identical colour behind them only reads as a misprint."

## Behavioral Requirements

- **settings-view-conformance**: The component MUST conform to
  `SettingsViewProtocol`.
- **main-actor-confinement**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **zero-argument-convenience-initializer**: The `public convenience
  init()` MUST forward to `init(frame: .zero)` with no parameters of its own.
- **self-autoresizing-mask**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself at
  construction.
- **layer-backing**: The component MUST set `wantsLayer = true` at
  construction.
- **vertical-leading-stack-alignment**: The component MUST construct an
  internal vertical stack view with `orientation == .vertical` and
  `alignment == .leading`.
- **group-spacing**: The component MUST set the internal stack view's
  `spacing` to `SettingsLayout.default[.groupSpacing]` (20pt).
- **stack-autoresizing-mask**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on the internal stack
  view.
- **top-leading-trailing-inset**: The component MUST pin the internal stack
  view's top, leading, and trailing anchors to its own corresponding
  anchors, each offset by `SettingsLayout.default[.panelInset]` (20pt)
  inward.
- **bottom-inset-inequality**: The component MUST constrain the internal
  stack view's bottom anchor `lessThanOrEqualTo` its own bottom anchor,
  offset by `-SettingsLayout.default[.panelInset]` (20pt) — an inequality,
  not an equality constraint.
- **construction-time-background-paint**: The component MUST set
  `layer?.backgroundColor` to the current theme's `.windowBackground` role
  (`palette.windowBackgroundColor.cgColor`), resolved through a
  `ThemePaletteObserver` constructed with `host: self`, immediately at
  construction.
- **theme-change-background-repaint**: The component MUST update
  `layer?.backgroundColor` to the new theme's `.windowBackground` role every
  time the active theme changes or the view's resolved `ThemeScope` changes,
  for the lifetime of the view (`ThemePaletteObserver`'s own notification
  subscriptions).
- **theme-observer-retention**: The component MUST hold its
  `ThemePaletteObserver` in a stored property for as long as the view
  exists, so the observer's Combine subscriptions are not deallocated
  early.
- **coder-initializer-rejection**: `required init?(coder: NSCoder)` MUST
  trap via `fatalError` when invoked; the exact message text is not part of
  this requirement (see Design Decisions).
- **group-arranged-subview-append**: `addGroup(_:)` MUST add the given
  `GroupView` as the next arranged subview of the internal stack view, with
  no other transformation.
- **heading-construction**: `addHeading(_:caption:)` MUST construct a
  `PanelHeadingView(title:caption:)` from its own `title` and `caption`
  parameters.
- **heading-caption-default**: `addHeading(_:caption:)` MUST default its
  `caption` parameter to `nil` when the caller omits it.
- **heading-gap**: When the internal stack view already has at least one
  arranged subview at the time `addHeading` is called, the component MUST
  set its custom spacing after that existing last arranged subview to
  `SettingsLayout.default[.groupSpacing] * 1.5` (30pt), before adding the
  new heading.
- **empty-stack-spacing-skip**: When the internal stack view has no
  arranged subviews at the time `addHeading` is called, the component MUST
  NOT attempt to set any custom spacing (there is no prior arranged subview
  to set it after).
- **heading-arranged-subview-append**: `addHeading(_:caption:)` MUST add
  the constructed `PanelHeadingView` as the next arranged subview of the
  internal stack view, after any spacing adjustment above has been made.
- **heading-width-match**: `addHeading(_:caption:)` MUST activate a
  constraint equating the constructed heading's `widthAnchor` to the
  internal stack view's `widthAnchor`.
- **heading-return**: `addHeading(_:caption:)` MUST return the constructed
  `PanelHeadingView` to its caller; the method is marked
  `@discardableResult`.

## Appearance

- **Corner radius**: Not applicable — `PanelView.swift` never sets
  `layer?.cornerRadius`; `wantsLayer = true` is set only so a background
  color can be painted on the layer.
- **Padding**: `stackView` is inset `SettingsLayout.default[.panelInset]` =
  20pt from the panel's top, leading, and trailing edges (equality
  constraints) and at most 20pt from the bottom edge (an inequality — see
  `bottom-inset-inequality`). Between arranged subviews,
  the default gap is `SettingsLayout.default[.groupSpacing]` = 20pt; the gap
  immediately above a heading added by `addHeading` is widened to
  `groupSpacing * 1.5` = 30pt whenever a prior arranged subview already
  exists.
- **Font**: Not applicable — `PanelView.swift` renders no text of its own.
  Group captions and heading text belong to the `GroupView` and
  `PanelHeadingView` recipes, each of which documents its own typography.
- **Background**: The theme's `.windowBackground` role
  (`palette.windowBackgroundColor`, resolved via `ThemePaletteObserver`),
  matching the source's own comment that this is "the same ground as the
  sidebar and the window."
- **Foreground/Text**: Not applicable — `PanelView` draws no text or icon of
  its own.
- **Border**: None — no border is drawn or configured anywhere in
  `PanelView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `PanelView.swift`.
- **Min/Max size**: None declared by `PanelView` itself. Its width is
  whatever its superview gives it (no self-width constraint is set here,
  unlike `GroupView`'s own `viewDidMoveToSuperview` width match); its height
  is bounded below by `stackView`'s accumulated content plus the 20pt top
  inset, but — per `bottom-inset-inequality` — the view
  MAY be taller than that, leaving unused space below the last arranged
  subview.

## States

| State | Appearance change |
|-------|------------------|
| Default | `stackView` is empty and pinned inside the panel; the background is already painted from the current theme at construction. |
| Group added | A `GroupView` is appended as the next arranged subview, separated from the previous arranged subview (if any) by the default 20pt `groupSpacing`. |
| Heading added, stack previously non-empty | A `PanelHeadingView` is appended; the gap between it and the arranged subview before it is widened to 30pt; its width is matched to `stackView`. |
| Heading added, stack previously empty | A `PanelHeadingView` is appended as the first arranged subview; no spacing adjustment is made because there is no predecessor. |
| Theme changed | `layer?.backgroundColor` is reassigned to the new theme's `.windowBackground` role; no other visual property changes. |
| Pressed | Not applicable: `PanelView.swift` defines no target/action or gesture recognizer of its own; it is a passive layout host. |
| Disabled | Not implemented in `PanelView.swift`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not applicable: the view never becomes key/first responder; `PanelView.swift` overrides no responder-chain behavior. |
| Loading | Not applicable: `PanelView.swift` performs no asynchronous operation and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable beyond AppKit's own default — `PanelView`
  sets no explicit accessibility role anywhere in `PanelView.swift`; it is a
  transparent layout container with no label, icon, or control of its own to
  expose. Each hosted `GroupView`/`PanelHeadingView` manages its own
  accessibility per its own recipe.
- **Label requirements**: Not applicable — `PanelView` itself carries no text
  or icon content; `addGroup`/`addHeading` forward the caller's views and
  strings unchanged, with no label of `PanelView`'s own to satisfy.
- **Announce state changes**: Not applicable — there is no loading or
  disabled state to announce (see States); the background repaint on a theme
  change is a silent, instantaneous recolor with no VoiceOver announcement
  anywhere in `PanelView.swift`.
- **Minimum tap target**: Not applicable — `PanelView.swift` defines no
  target/action or gesture recognizer of its own; whatever tap targets exist
  belong to the `GroupView`/`PanelHeadingView` content it hosts, covered by
  their own recipes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-view-001 | settings-view-conformance | Construct `PanelView()` | `view is SettingsViewProtocol` is `true` |
| panel-view-002 | main-actor-confinement | (Static/compile-time check) Attempt to construct or mutate a `PanelView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-view-003 | zero-argument-convenience-initializer | Construct `PanelView()` | Succeeds and produces a fully initialized view with its internal stack view and theme observer set up |
| panel-view-004 | see Design Decisions | Construct `PanelView(frame: NSRect(x: 10, y: 10, width: 300, height: 300))`, checked immediately after `init` returns, before layout | The resulting view's frame is `.zero`, not the supplied rect |
| panel-view-005 | self-autoresizing-mask | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-006 | layer-backing | Construct the component | `view.wantsLayer == true` and `view.layer` is non-nil |
| panel-view-007 | vertical-leading-stack-alignment | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading` |
| panel-view-008 | group-spacing | Construct the component | The internal stack's `spacing == 20.0` |
| panel-view-009 | stack-autoresizing-mask | Construct the component | The internal stack's `translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-010 | top-leading-trailing-inset | Construct the component | Active constraints pin the stack's top/leading/trailing anchors to the view's corresponding anchors, each with constant `20.0` inward |
| panel-view-011 | bottom-inset-inequality | Inspect the component's active constraints | A `lessThanOrEqualTo` constraint relates the stack's bottom anchor to the view's bottom anchor with constant `-20.0`; no equality constraint exists between them |
| panel-view-012 | construction-time-background-paint | Construct the component under a known theme | `layer?.backgroundColor` equals that theme's `windowBackgroundColor.cgColor` immediately after `init` returns |
| panel-view-013 | theme-change-background-repaint | Construct the component, then switch the active theme | `layer?.backgroundColor` updates to the new theme's `windowBackgroundColor.cgColor` |
| panel-view-014 | theme-observer-retention | Construct the component, trigger a theme change some time later | The background still repaints (proving the observer was not deallocated between construction and the change) |
| panel-view-015 | coder-initializer-rejection | Construct via `PanelView(coder: someCoder)` | Execution traps via `fatalError`; the source's current message text is `not overridden` (not required by this requirement — see Design Decisions) |
| panel-view-016 | group-arranged-subview-append | `addGroup(someGroupView)` | `someGroupView` is an arranged subview of the internal stack, at the end |
| panel-view-017 | heading-construction | `addHeading("Section", caption: "Some blurb")` | A `PanelHeadingView` is constructed with `title == "Section"` and `caption == "Some blurb"` forwarded to its initializer (see the panel-heading-view recipe for how these values render) |
| panel-view-018 | heading-caption-default | `addHeading("Section")` with no `caption` argument | The constructed `PanelHeadingView` receives `caption == nil` (see the panel-heading-view recipe for its own nil-caption behavior) |
| panel-view-019 | heading-gap | `addGroup(someGroupView)` then `addHeading("Section")` | The stack's custom spacing after `someGroupView` is `30.0` |
| panel-view-020 | empty-stack-spacing-skip | `addHeading("Section")` as the first call on a freshly constructed component | No custom spacing is set (the stack has no prior arranged subview); no crash occurs |
| panel-view-021 | heading-arranged-subview-append | `addHeading("Section")` | The returned `PanelHeadingView` is an arranged subview of the internal stack, at the end |
| panel-view-022 | heading-width-match | `addHeading("Section")` | An active constraint equates the returned heading's `widthAnchor` to the internal stack's `widthAnchor` |
| panel-view-023 | heading-return | `let heading = addHeading("Section")` | `heading` is the same `PanelHeadingView` instance added to the stack; the caller can ignore the return value with no compiler warning |

## Edge Cases

- **Null/empty input**: `group` (`GroupView`, `addGroup(_:)`) and `title`
  (`String`, `addHeading(_:caption:)`) are non-optional, typed parameters;
  Swift's type system rules out `nil` for either, so no nil-handling path is
  needed. `caption` (`String?`) defaults to `nil`; an explicit empty
  string (`caption: ""`) is passed straight through to
  `PanelHeadingView(title:caption:)`, which — per that recipe — still
  constructs a caption view whose label renders empty.
- **Boundary values**: Not applicable in the numeric sense — `PanelView`
  exposes no caller-configurable numeric range of its own; its only numeric
  behavior comes from the fixed `SettingsLayout` constants (20pt panel
  inset, 20pt group spacing, the fixed `1.5×` heading-gap multiplier).
- **Concurrent access**: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), so `addGroup`, `addHeading`, and every
  constraint activation are serialized on the main actor.
- **Error states**: Not applicable — every operation in `PanelView.swift`
  (adding a group, adding a heading, repainting the background) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing API
  appears in source.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking of its own.
- **`addHeading` called on an empty panel**: Per
  **empty-stack-spacing-skip**, the first heading in a panel sits with no
  extra gap above it, because there is no prior arranged subview at that
  point and the spacing-adjustment guard simply does not run — no fallback
  spacing is applied in its place.
- **The view's own frame is unreachable by construction**: Per the design
  decision on frame handling (see Design Decisions), any `NSRect` passed to
  `PanelView(frame:)` — including a non-zero one supplied directly by a
  caller who bypasses the `init()` convenience initializer — is discarded;
  the view always begins at `.zero` regardless: `super.init(frame: .zero)`
  never references its own `frameRect` parameter.
- **Re-adding an already-parented `GroupView`**: AppKit's
  `addArrangedSubview` always detaches a view from its previous superview
  before adding it to a new one; adding the same `GroupView` instance to a
  second `PanelView` (or a second time to the same one) silently removes it
  from its first location. `PanelView.swift` contains no guard against this
  — the same source-traceable consequence the sibling `GroupView` recipe
  documents for `addSettingSubview` (see **group-arranged-subview-append**).
- **A superview taller than the panel's content**: Because
  **bottom-inset-inequality** constrains the internal stack view's bottom
  with an inequality rather than an equality, a `PanelView` given more
  height than its groups require leaves visible, unpainted-by-content slack
  between the last arranged subview and the panel's bottom edge, rather than
  stretching the stack to fill it: no equality or centering constraint
  exists to distribute the extra space.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `group` (`addGroup(_:)`) | `GroupView` | — (required) | The card appended as the panel's next arranged subview. |
| `title` (`addHeading(_:caption:)`) | `String` | — (required) | Heading text forwarded verbatim to the constructed `PanelHeadingView`. |
| `caption` (`addHeading(_:caption:)`) | `String?` | `nil` | Optional caption text forwarded verbatim to the constructed `PanelHeadingView`. |

## Deep Linking

Not applicable: `PanelView` is a layout container inside a composable
settings window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in `PanelView.swift`.

## Localization

Not applicable: `PanelView.swift` defines no string literal of its own.
`addHeading(_:caption:)`'s `title` and `caption` parameters are entirely
caller-supplied and forwarded verbatim to `PanelHeadingView` — localizing
them is the caller's responsibility, the same treatment the sibling
`PanelHeadingView` recipe documents for those same two parameters one level
down.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `PanelView.swift` contains no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere in source; adding a group, adding a heading, and repainting the background on a theme change are each a synchronous, instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `PanelView.swift` reads no system contrast setting and sets no literal `NSColor`; the background is a theme-resolved semantic role (`.windowBackground`) supplied by `ThemePaletteObserver`, which this file does not further adjust for contrast. |
| Differentiate Without Color | Not applicable: `PanelView` conveys no state through color; its background is decorative ground behind the groups it hosts, not a status or selection indicator. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `PanelView.swift`; the background paints and every added group/heading
render unconditionally.

## Analytics

Not applicable: `PanelView.swift` contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  `GroupView`/`PanelHeadingView` instances it is given, plus its own
  `stackView` and `themeObserver`.
- **Storage**: Not applicable — `PanelView.swift` performs no read/write to
  disk, `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `PanelView.swift`.
- **Retention**: Not applicable — the view retains its stack, its added
  arranged subviews, and its theme observer only for its own lifetime; it
  persists nothing beyond that.

## Logging

Not applicable: `PanelView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 20)` inside a
  container padded `.padding(.top, 20).padding(.horizontal, 20)`, with the
  bottom left to the stack's own intrinsic height rather than a fixed
  `.padding(.bottom, 20)` pin — SwiftUI's default layout already lets
  content fall short of an oversized parent, mirroring
  **bottom-inset-inequality**. Give the container a `.background` filled
  from the theme's window-background token, matching
  **construction-time-background-paint**/**theme-change-background-repaint**,
  which SwiftUI's environment-driven color already repaints automatically
  on a theme change with no manual observer. Insert an extra
  `Spacer().frame(height: 10)` immediately before a heading view — 10pt
  plus the `VStack`'s own 20pt `spacing` totals the 30pt of **heading-gap**
  — but only when a view already precedes it, mirroring
  **empty-stack-spacing-skip**.
- **Compose**: Use a `Column(verticalArrangement =
  Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.Start,
  modifier = Modifier.padding(start = 20.dp, end = 20.dp, top =
  20.dp).background(<windowBackground token>))`, letting the column wrap its
  content height rather than filling a fixed-height parent, the Compose
  analog of the inequality bottom constraint. Precede a heading composable
  with an extra `Spacer(Modifier.height(10.dp))` (10dp + the column's own
  20dp gap = 30dp) only when it is not the column's first child, mirroring
  **heading-gap**/**empty-stack-spacing-skip**.
- **React/Web**: A `<div>` styled `display: flex; flex-direction: column;
  align-items: flex-start; gap: 20px; padding: 20px 20px 0 20px;
  background: var(--window-background)`, sized to its content rather than a
  fixed height so it can fall short of a taller parent, mirroring
  **bottom-inset-inequality**. Give a heading element `margin-top: 10px` in
  addition to the flex `gap` (10px + 20px = 30px total) only when a previous
  sibling exists (a `:not(:first-child)` selector), mirroring the
  conditional spacing rule; rely on the CSS custom property's own value
  updating on a theme class/attribute change for
  **theme-change-background-repaint**.
- **AppKit / UIKit** (source platform): A macOS-only (`import AppKit`)
  `open`, `@MainActor` `NSView` subclass inside the `ComposableSettings`
  namespace (see Overview for the source file and its layout/theme
  dependencies), built on `NSStackView` and Auto Layout. Internally, the
  private stored properties `stackView` (`NSStackView`) and `themeObserver`
  (`ThemePaletteObserver?`) back the stack and theme-repaint behavior
  described under Behavioral Requirements. There is no UIKit code path in
  source; because `ThemePaletteObserver` itself is already cross-platform
  (`SourcesUI/Shared`), a UIKit port would only need to replace
  `NSStackView` with `UIStackView` and the layer background assignment with
  the UIKit equivalent (`layer.backgroundColor` on a layer-backed `UIView`,
  which is layer-backed by default) — the theme observer and its
  notification-driven repaint carry over unchanged.
- **WinUI 3**: Build a `StackPanel` (`Orientation="Vertical"`,
  `Spacing="20"`, matching **group-spacing**) inside a root whose
  `Background="{ThemeResource ApplicationPageBackgroundThemeBrush}"` (or the
  app's own window-background resource) repaints automatically through
  WinUI's `ThemeResource` re-resolution on a `RequestedTheme` change — the
  platform-native analog of
  **construction-time-background-paint**/**theme-change-background-repaint**,
  needing no manual observer equivalent to `ThemePaletteObserver`. Give the
  root `Padding="20,20,20,0"` and leave the `StackPanel`'s
  `VerticalAlignment` at its default `Top` rather than `Stretch`, so it
  sizes to its content and leaves slack below rather than stretching to
  fill the container — the WinUI analog of **bottom-inset-inequality**.
  Because `StackPanel.Spacing` cannot vary per-gap the way
  `NSStackView.setCustomSpacing(after:)` can, reproduce
  **heading-gap**/**empty-stack-spacing-skip** with an extra `<Border
  Height="10"/>` spacer element inserted immediately before a heading
  `TextBlock`/`StackPanel` — 10 plus the panel's own 20 `Spacing` totals the
  30 of `groupSpacing * 1.5` — but only when `Children.Count > 0` at the
  point of insertion.

## Design Decisions

- **Decision**: Constrain the internal stack view's bottom anchor with
  `lessThanOrEqualTo` rather than an equality constraint, unlike the
  top/leading/trailing edges.
  **Rationale**: Not explained in source comments beyond the code itself.
  An inequality lets the stack's own Auto-Layout-computed height determine
  the panel's occupied region without forcing the stack to stretch and fill
  a taller frame the panel happens to be given, the same "size to content,
  not to container" outcome `GroupView`'s sibling recipe gets from having no
  height constraint of its own at all.
  **Approved**: pending
- **Decision**: The designated `init(frame:)` ignores the caller-supplied
  `frameRect` entirely and always forwards `.zero` to `super.init(frame:)`.
  **Rationale**: Not explained in source comments; the effect is that no
  caller can give a `PanelView` a non-zero initial frame, even by bypassing
  the `init()` convenience initializer. This is a known quirk rather than a
  deliberate API contract — kept as-is because it is what the source does
  (see **zero-argument-convenience-initializer** and the frame edge case
  above).
  **Approved**: pending
- **Decision**: Resolve the background color through `ThemePaletteObserver(
  host: self)` rather than reading `ThemePaletteObserver.currentPalette`
  (the unscoped, app-wide answer) once at construction.
  **Rationale**: Per the source's own comment, this keeps the panel's
  ground the same as "the sidebar and the window," painted from `self`'s
  own resolved `ThemeScope` rather than a single global palette, and it
  stays live for the view's lifetime rather than being captured once.
  **Approved**: pending
- **Decision**: `addHeading` widens the gap above a heading to
  `groupSpacing * 1.5` only when a prior arranged subview already exists,
  rather than always applying the wider spacing or applying it to the gap
  below the heading.
  **Rationale**: Per the source's own doc comment, "the gap above a heading
  is wider than the gap between two cards, because that gap is what says
  the heading belongs to what comes *after* it — at the stack's own spacing
  it reads as a caption trailing the card above." A first heading with
  nothing above it needs no such signal, so no adjustment is made.
  **Approved**: pending
- **Decision**: `required init?(coder:)` traps via `fatalError`, and its
  current message text (`not overridden`) is left as-is rather than
  standardized to match the sibling `GroupView`/`PanelHeadingView` message
  (`init(coder:) has not been implemented`).
  **Rationale**: The message text is not part of the
  **coder-initializer-rejection** requirement; the mismatch is a real,
  source-traceable inconsistency between siblings, not smoothed over in
  either direction.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |

`native-controls-preference` passes because the component is built entirely
from `NSView`/`NSStackView`. `screen-reader-support` passes because
`PanelView` is a transparent layout container with no label or control of
its own for VoiceOver to need; each hosted child manages its own
accessibility per its own recipe.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `PanelView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformatted frontmatter (references moved to related, depends-on populated with GroupView/PanelHeadingView); renamed requirements to subject-noun form and updated every citation; moved the ignored-frame behavior and the coder-initializer message wording into Design Decisions; removed stray MUST labels and a garbled title from Edge Cases; marked test vector 002 as compile-time and fixed vector 004's timing and vectors 017/018 to assert PanelHeadingView's public inputs instead of its private labels; reformatted Design Decisions to the bold convention and dropped a non-decision entry; trimmed Platform Notes editorializing and moved private stack/observer identifiers there; cleaned the Compliance table to catalog-valid checks with Title Case categories. |
