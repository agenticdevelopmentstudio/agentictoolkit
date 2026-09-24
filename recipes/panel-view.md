---
id: 4b1a3eb0-0a8a-4059-b2ac-824013072bd5
title: PanelView
domain: agentictoolkit://recipes/panel-view
type: ingredient
version: 1.0.0
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
depends-on: []
related:
- agentictoolkit://recipes/group-view
- agentictoolkit://recipes/panel-heading-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
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

- **conforms-to-settings-view-protocol**: The component MUST conform to
  `SettingsViewProtocol`.
- **confines-to-main-actor**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **provides-zero-argument-convenience-initializer**: The `public convenience
  init()` MUST forward to `init(frame: .zero)` with no parameters of its own.
- **ignores-caller-supplied-frame**: The designated `public override
  init(frame frameRect: NSRect)` MUST NOT use the caller-supplied `frameRect`
  value for anything; it MUST call `super.init(frame: .zero)` unconditionally,
  regardless of what `frameRect` is.
- **disables-autoresizing-mask-on-self**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself at
  construction.
- **enables-layer-backing**: The component MUST set `wantsLayer = true` at
  construction.
- **stacks-groups-vertically-leading-aligned**: The component MUST construct
  an internal `NSStackView` (`stackView`) with `orientation == .vertical` and
  `alignment == .leading`.
- **spaces-groups-by-group-spacing**: The component MUST set `stackView`'s
  `spacing` to `SettingsLayout.default[.groupSpacing]` (20pt).
- **disables-autoresizing-mask-on-stack**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on `stackView`.
- **insets-stack-from-top-leading-trailing-by-panel-inset**: The component
  MUST pin `stackView`'s top, leading, and trailing anchors to its own
  corresponding anchors, each offset by `SettingsLayout.default[.panelInset]`
  (20pt) inward.
- **allows-stack-to-fall-short-of-bottom-inset**: The component MUST
  constrain `stackView`'s bottom anchor `lessThanOrEqualTo` its own bottom
  anchor, offset by `-SettingsLayout.default[.panelInset]` (20pt) — an
  inequality, not an equality constraint.
- **paints-background-from-theme-on-construction**: The component MUST set
  `layer?.backgroundColor` to the current theme's `.windowBackground` role
  (`palette.windowBackgroundColor.cgColor`), resolved through a
  `ThemePaletteObserver` constructed with `host: self`, immediately at
  construction.
- **repaints-background-on-theme-change**: The component MUST update
  `layer?.backgroundColor` to the new theme's `.windowBackground` role every
  time the active theme changes or the view's resolved `ThemeScope` changes,
  for the lifetime of the view (`ThemePaletteObserver`'s own notification
  subscriptions).
- **retains-theme-observer-for-view-lifetime**: The component MUST hold its
  `ThemePaletteObserver` in a stored property (`themeObserver`) for as long
  as the view exists, so the observer's Combine subscriptions are not
  deallocated early.
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST
  fatal-error with the message `not overridden`.
- **appends-group-as-arranged-subview**: `addGroup(_:)` MUST add the given
  `GroupView` as the next arranged subview of `stackView`, with no other
  transformation.
- **constructs-heading-from-title-and-caption**: `addHeading(_:caption:)`
  MUST construct a `PanelHeadingView(title:caption:)` from its own `title`
  and `caption` parameters.
- **defaults-heading-caption-to-nil**: `addHeading(_:caption:)` MUST default
  its `caption` parameter to `nil` when the caller omits it.
- **widens-gap-before-heading-when-stack-nonempty**: When `stackView` already
  has at least one arranged subview at the time `addHeading` is called, the
  component MUST set `stackView`'s custom spacing after that existing last
  arranged subview to `SettingsLayout.default[.groupSpacing] * 1.5` (30pt),
  before adding the new heading.
- **skips-spacing-adjustment-on-empty-stack**: When `stackView` has no
  arranged subviews at the time `addHeading` is called, the component MUST
  NOT attempt to set any custom spacing (there is no prior arranged subview
  to set it after).
- **appends-heading-as-arranged-subview**: `addHeading(_:caption:)` MUST add
  the constructed `PanelHeadingView` as the next arranged subview of
  `stackView`, after any spacing adjustment above has been made.
- **matches-heading-width-to-stack**: `addHeading(_:caption:)` MUST activate
  a constraint equating the constructed heading's `widthAnchor` to
  `stackView.widthAnchor`.
- **returns-constructed-heading**: `addHeading(_:caption:)` MUST return the
  constructed `PanelHeadingView` to its caller; the method is marked
  `@discardableResult`.

## Appearance

- **Corner radius**: Not applicable — `PanelView.swift` never sets
  `layer?.cornerRadius`; `wantsLayer = true` is set only so a background
  color can be painted on the layer.
- **Padding**: `stackView` is inset `SettingsLayout.default[.panelInset]` =
  20pt from the panel's top, leading, and trailing edges (equality
  constraints) and at most 20pt from the bottom edge (an inequality — see
  `allows-stack-to-fall-short-of-bottom-inset`). Between arranged subviews,
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
  inset, but — per `allows-stack-to-fall-short-of-bottom-inset` — the view
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
| panel-view-001 | conforms-to-settings-view-protocol | Construct `PanelView()` | `view is SettingsViewProtocol` is `true` |
| panel-view-002 | confines-to-main-actor | Attempt to construct or mutate a `PanelView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-view-003 | provides-zero-argument-convenience-initializer | Construct `PanelView()` | Succeeds and produces a fully initialized view with `stackView` and `themeObserver` set up |
| panel-view-004 | ignores-caller-supplied-frame | Construct `PanelView(frame: NSRect(x: 10, y: 10, width: 300, height: 300))` | The resulting view's frame is `.zero`, not the supplied rect |
| panel-view-005 | disables-autoresizing-mask-on-self | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-006 | enables-layer-backing | Construct the component | `view.wantsLayer == true` and `view.layer` is non-nil |
| panel-view-007 | stacks-groups-vertically-leading-aligned | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading` |
| panel-view-008 | spaces-groups-by-group-spacing | Construct the component | The internal stack's `spacing == 20.0` |
| panel-view-009 | disables-autoresizing-mask-on-stack | Construct the component | The internal stack's `translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-010 | insets-stack-from-top-leading-trailing-by-panel-inset | Construct the component | Active constraints pin the stack's top/leading/trailing anchors to the view's corresponding anchors, each with constant `20.0` inward |
| panel-view-011 | allows-stack-to-fall-short-of-bottom-inset | Inspect the component's active constraints | A `lessThanOrEqualTo` constraint relates the stack's bottom anchor to the view's bottom anchor with constant `-20.0`; no equality constraint exists between them |
| panel-view-012 | paints-background-from-theme-on-construction | Construct the component under a known theme | `layer?.backgroundColor` equals that theme's `windowBackgroundColor.cgColor` immediately after `init` returns |
| panel-view-013 | repaints-background-on-theme-change | Construct the component, then switch the active theme | `layer?.backgroundColor` updates to the new theme's `windowBackgroundColor.cgColor` |
| panel-view-014 | retains-theme-observer-for-view-lifetime | Construct the component, trigger a theme change some time later | The background still repaints (proving the observer was not deallocated between construction and the change) |
| panel-view-015 | rejects-coder-initializer | Construct via `PanelView(coder: someCoder)` | Execution traps via `fatalError` with message `not overridden` |
| panel-view-016 | appends-group-as-arranged-subview | `addGroup(someGroupView)` | `someGroupView` is an arranged subview of the internal stack, at the end |
| panel-view-017 | constructs-heading-from-title-and-caption | `addHeading("Section", caption: "Some blurb")` | A `PanelHeadingView` is created whose `titleLabel.stringValue == "Section"` and whose caption reflects `"Some blurb"` |
| panel-view-018 | defaults-heading-caption-to-nil | `addHeading("Section")` with no `caption` argument | The constructed `PanelHeadingView`'s `captionLabel == nil` |
| panel-view-019 | widens-gap-before-heading-when-stack-nonempty | `addGroup(someGroupView)` then `addHeading("Section")` | The stack's custom spacing after `someGroupView` is `30.0` |
| panel-view-020 | skips-spacing-adjustment-on-empty-stack | `addHeading("Section")` as the first call on a freshly constructed component | No custom spacing is set (the stack has no prior arranged subview); no crash occurs |
| panel-view-021 | appends-heading-as-arranged-subview | `addHeading("Section")` | The returned `PanelHeadingView` is an arranged subview of the internal stack, at the end |
| panel-view-022 | matches-heading-width-to-stack | `addHeading("Section")` | An active constraint equates the returned heading's `widthAnchor` to the internal stack's `widthAnchor` |
| panel-view-023 | returns-constructed-heading | `let heading = addHeading("Section")` | `heading` is the same `PanelHeadingView` instance added to the stack; the caller can ignore the return value with no compiler warning |

## Edge Cases

- **Null/empty input**: `group` (`GroupView`, `addGroup(_:)`) and `title`
  (`String`, `addHeading(_:caption:)`) are non-optional, typed parameters;
  Swift's type system rules out `nil` for either (MUST — no nil-handling
  path is needed). `caption` (`String?`) defaults to `nil`; an explicit empty
  string (`caption: ""`) is passed straight through to
  `PanelHeadingView(title:caption:)`, which — per that recipe — still
  constructs a caption view whose label renders empty.
- **Boundary values**: Not applicable in the numeric sense — `PanelView`
  exposes no caller-configurable numeric range of its own; its only numeric
  behavior comes from the fixed `SettingsLayout` constants (20pt panel
  inset, 20pt group spacing, the fixed `1.5×` heading-gap multiplier).
- **Concurrent access**: Not applicable — the class is `@MainActor` (see
  `confines-to-main-actor`), so `addGroup`, `addHeading`, and every
  constraint activation are serialized on the main actor.
- **Error states**: Not applicable — every operation in `PanelView.swift`
  (adding a group, adding a heading, repainting the background) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing API
  appears in source.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking of its own.
- **`addHeading` called on an empty panel**: Per
  `skips-spacing-adjustment-on-empty-stack`, the first heading in a panel
  sits with no extra gap above it, because `stackView.arrangedSubviews.last`
  is `nil` at that point and the `if let last = ...` guard simply does not
  run (MUST, source-traceable — no fallback spacing is applied in its
  place).
- **The view's own frame is unreachable by construction**: Per
  `ignores-caller-supplied-frame`, any `NSRect` passed to
  `PanelView(frame:)` — including a non-zero one supplied directly by a
  caller who bypasses the `init()` convenience initializer — is discarded;
  the view always begins at `.zero` regardless (MUST, source-traceable:
  `super.init(frame: .zero)` never references its own `frameRect`
  parameter).
- **Passing the same `GroupView` (or `PanelHeadingView`) instance to
  `addGroup`/two `addHeading`-constructed headings sharing an instance is not
  possible, but reusing a `GroupView` already added elsewhere is)**: AppKit's
  `addArrangedSubview` always detaches a view from its previous superview
  before adding it to a new one; adding the same `GroupView` instance to a
  second `PanelView` (or a second time to the same one) silently removes it
  from its first location. `PanelView.swift` contains no guard against this
  — the same source-traceable consequence the sibling `GroupView` recipe
  documents for `addSettingSubview` (MUST-level, per
  `appends-group-as-arranged-subview`).
- **A superview taller than the panel's content**: Because
  `allows-stack-to-fall-short-of-bottom-inset` constrains the stack's bottom
  with an inequality rather than an equality, a `PanelView` given more
  height than its groups require leaves visible, unpainted-by-content slack
  between the last arranged subview and the panel's bottom edge, rather than
  stretching `stackView` to fill it (MUST, source-traceable: no equality or
  centering constraint exists to distribute the extra space).

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
  `allows-stack-to-fall-short-of-bottom-inset`. Give the container a
  `.background` filled from the theme's window-background token, matching
  `paints-background-from-theme-on-construction`/
  `repaints-background-on-theme-change`, which SwiftUI's environment-driven
  color already repaints automatically on a theme change with no manual
  observer. Insert an extra `Spacer().frame(height: 10)` immediately before
  a heading view — 10pt plus the `VStack`'s own 20pt `spacing` totals the
  30pt of `widens-gap-before-heading-when-stack-nonempty` — but only when a
  view already precedes it, mirroring
  `skips-spacing-adjustment-on-empty-stack`.
- **Compose**: Use a `Column(verticalArrangement =
  Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.Start,
  modifier = Modifier.padding(start = 20.dp, end = 20.dp, top =
  20.dp).background(<windowBackground token>))`, letting the column wrap its
  content height rather than filling a fixed-height parent, the Compose
  analog of the inequality bottom constraint. Precede a heading composable
  with an extra `Spacer(Modifier.height(10.dp))` (10dp + the column's own
  20dp gap = 30dp) only when it is not the column's first child, mirroring
  `widens-gap-before-heading-when-stack-nonempty`/
  `skips-spacing-adjustment-on-empty-stack`.
- **React/Web**: A `<div>` styled `display: flex; flex-direction: column;
  align-items: flex-start; gap: 20px; padding: 20px 20px 0 20px;
  background: var(--window-background)`, sized to its content rather than a
  fixed height so it can fall short of a taller parent, mirroring
  `allows-stack-to-fall-short-of-bottom-inset`. Give a heading element
  `margin-top: 10px` in addition to the flex `gap` (10px + 20px = 30px
  total) only when a previous sibling exists (a `:not(:first-child)`
  selector), mirroring the conditional spacing rule; rely on the CSS custom
  property's own value updating on a theme class/attribute change for
  `repaints-background-on-theme-change`.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelView.swift`,
  with layout constants from `ViewLayout.swift` and `ThemePaletteObserver`/
  `ThemeScopeResolving` from the `agenticdevelopertoolkit` submodule's
  `SourcesUI/Shared/Theme/ThemeBinding.swift` and
  `ThemeScopeResolution.swift` (an `extension PlatformView:
  ThemeScopeResolving`, so every `NSView`/`UIView` already qualifies as a
  `host` with no extra conformance declaration needed). A macOS-only
  (`import AppKit`) `open`, `@MainActor` `NSView` subclass inside the
  `ComposableSettings` namespace, built on `NSStackView` and Auto Layout.
  There is no UIKit code path in source; because `ThemePaletteObserver`
  itself is already cross-platform (`SourcesUI/Shared`), a UIKit port would
  only need to replace `NSStackView` with `UIStackView` and the layer
  background assignment with the UIKit equivalent (`layer.backgroundColor`
  on a layer-backed `UIView`, which is layer-backed by default) — the theme
  observer and its notification-driven repaint carry over unchanged.
- **WinUI 3** (the reason this recipe exists): Build a `StackPanel`
  (`Orientation="Vertical"`, `Spacing="20"`, matching
  `spaces-groups-by-group-spacing`) inside a root whose
  `Background="{ThemeResource ApplicationPageBackgroundThemeBrush}"` (or the
  app's own window-background resource) repaints automatically through
  WinUI's `ThemeResource` re-resolution on a `RequestedTheme` change — the
  platform-native analog of
  `paints-background-from-theme-on-construction`/
  `repaints-background-on-theme-change`, needing no manual observer
  equivalent to `ThemePaletteObserver`. Give the root `Padding="20,20,20,0"`
  and leave the `StackPanel`'s `VerticalAlignment` at its default `Top`
  rather than `Stretch`, so it sizes to its content and leaves slack below
  rather than stretching to fill the container — the WinUI analog of
  `allows-stack-to-fall-short-of-bottom-inset`'s inequality constraint.
  Because `StackPanel.Spacing` cannot vary per-gap the way
  `NSStackView.setCustomSpacing(after:)` can, reproduce
  `widens-gap-before-heading-when-stack-nonempty`/
  `skips-spacing-adjustment-on-empty-stack` with an extra `<Border
  Height="10"/>` spacer element inserted immediately before a heading
  `TextBlock`/`StackPanel` — 10 plus the panel's own 20 `Spacing` totals the
  30 of `groupSpacing * 1.5` — but only when `Children.Count > 0` at the
  point of insertion.

## Design Decisions

- Decision: Constrain `stackView`'s bottom anchor with `lessThanOrEqualTo`
  rather than an equality constraint, unlike the top/leading/trailing edges.
  Rationale: not explained in source comments beyond the code itself. An
  inequality lets the stack's own Auto-Layout-computed height determine the
  panel's occupied region without forcing `stackView` to stretch and fill a
  taller frame the panel happens to be given, the same "size to content, not
  to container" outcome `GroupView`'s sibling recipe gets from having no
  height constraint of its own at all.
  Approved: pending
- Decision: Resolve the background color through `ThemePaletteObserver(host:
  self)` rather than reading `ThemePaletteObserver.currentPalette` (the
  unscoped, app-wide answer) once at construction.
  Rationale: per the source's own comment, this keeps the panel's ground the
  same as "the sidebar and the window," painted from `self`'s own resolved
  `ThemeScope` rather than a single global palette, and it stays live for
  the view's lifetime rather than being captured once.
  Approved: pending
- Decision: `addHeading` widens the gap above a heading to `groupSpacing *
  1.5` only when a prior arranged subview already exists, rather than always
  applying the wider spacing or applying it to the gap below the heading.
  Rationale: per the source's own doc comment, "the gap above a heading is
  wider than the gap between two cards, because that gap is what says the
  heading belongs to what comes *after* it — at the stack's own spacing it
  reads as a caption trailing the card above." A first heading with nothing
  above it needs no such signal, so no adjustment is made.
  Approved: pending
- Decision: `required init?(coder:)` fatal-errors with the message `not
  overridden`, a different string from the sibling `GroupView`'s and
  `PanelHeadingView`'s own coder-initializer message
  (`init(coder:) has not been implemented`).
  Rationale: documented as a source-traceable inconsistency between
  siblings, not smoothed over in either direction — this file's message is
  what is actually in source, even though it reads as though it were
  written for an overridable hook rather than an unsupported initializer.
  Approved: pending
- Decision: This recipe has fewer behavioral requirements than the sibling
  `GroupView` recipe (33) but more than the sibling `PanelHeadingView`
  recipe (16).
  Rationale: `PanelView` composes a stack, a theme observer, and two mutating
  methods with real conditional logic (the heading-gap rule), but owns none
  of `GroupView`'s per-row separator bookkeeping. The requirement count
  reflects that difference in scope, not a gap in authoring effort.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | ui-tokens |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | passed | i18n |

`main-actor-confined` passes because the class is declared `@MainActor` (see
`confines-to-main-actor`). `no-raw-hex` passes because the only color this
component sets comes from `palette.windowBackgroundColor`, a theme-resolved
semantic role, never a literal `NSColor` or hex value.
`native-controls-preference` passes because the component is built entirely
from `NSView`/`NSStackView`. `differentiate-without-color` passes because
the component conveys no state through color. `screen-reader-support`
passes because `PanelView` is a transparent layout container with no label
or control of its own for VoiceOver to need; each hosted child manages its
own accessibility per its own recipe. `localizable-strings` passes because
`PanelView.swift` owns no string literal of its own — `title`/`caption` are
entirely caller-supplied and forwarded unchanged.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `PanelView` (AppKit, macOS) source. |
