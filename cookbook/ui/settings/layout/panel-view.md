---
id: 4b1a3eb0-0a8a-4059-b2ac-824013072bd5
title: Panel View
domain: agentictoolkit://cookbook/ui/settings/layout/panel-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A view that stacks group cards and panel headings inside a themed
  panel, matching a settings app's outer layout.
platforms:
- swift
- macos
tags:
- settings
- layout
depends-on:
- agentictoolkit://cookbook/ui/settings/layout/group-view
- agentictoolkit://cookbook/ui/settings/layout/panel-heading-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Panel View

## Overview

The Panel View is the root container for a settings panel: it hosts a
vertical stack of group-view cards, spaced apart inside the panel's
content area, per the source's own doc comment. It owns a single internal
vertical stack inset from its own edges by the panel's outer margin,
paints its own background from the active theme, and exposes exactly two
mutating operations: an add-group operation, which appends a group-view
card, and an add-heading operation, which appends a panel heading view
(constructed internally) ahead of the groups that follow it, widening the
gap above it so the heading reads as belonging to what comes after it
rather than as a caption trailing the card above — per the source's own
comment on that operation. Both the Group View and the Panel Heading View
are separate components with their own recipes; this recipe covers only
what this component itself does with them. The background color tracks
this component's own resolved theme scope rather than an app-wide default;
the source's own comment on that choice explains the color: "The same
ground as the sidebar and the window: the cards are what stand out here,
and a panel-shaped patch of a second near-identical colour behind them
only reads as a misprint."

## Behavioral Requirements

- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **vertical-leading-stack-alignment**: The component MUST construct an
  internal vertical stack with leading alignment.
- **group-spacing**: The component MUST set the internal stack's spacing
  to the standard group-spacing value (20pt).
- **top-leading-trailing-inset**: The component MUST pin the internal
  stack's top, leading, and trailing edges to its own corresponding edges,
  each offset by the standard panel-inset value (20pt) inward.
- **bottom-inset-inequality**: The component MUST constrain the internal
  stack's bottom edge to be no further than the standard panel-inset value
  (20pt) from its own bottom edge — an inequality, not an equality
  constraint.
- **construction-time-background-paint**: The component MUST set its
  background to the current theme's window-background role, resolved for
  the component's own theme scope, immediately at construction.
- **theme-change-background-repaint**: The component MUST update its
  background to the new theme's window-background role every time the
  active theme changes or the component's resolved theme scope changes,
  for the lifetime of the view.
- **rejects-deserializing-construction**: A deserializing/decoding-based
  construction path MUST trap or fail when invoked; the exact trap message
  is not part of this requirement (see Design Decisions).
- **group-arranged-subview-append**: The add-group operation MUST add the
  given group view as the next arranged child of the internal stack, with
  no other transformation.
- **heading-construction**: The add-heading operation MUST construct a
  panel heading view from its own title and caption parameters.
- **heading-caption-default**: The add-heading operation MUST default its
  caption parameter to absent when the caller omits it.
- **heading-gap**: When the internal stack already has at least one
  arranged child at the time the add-heading operation is called, the
  component MUST set the custom spacing after that existing last arranged
  child to 1.5x the standard group-spacing value (30pt), before adding the
  new heading.
- **empty-stack-spacing-skip**: When the internal stack has no arranged
  children at the time the add-heading operation is called, the component
  MUST NOT attempt to set any custom spacing (there is no prior arranged
  child to set it after).
- **heading-arranged-subview-append**: The add-heading operation MUST add
  the constructed panel heading view as the next arranged child of the
  internal stack, after any spacing adjustment above has been made.
- **heading-width-match**: The add-heading operation MUST activate a
  constraint equating the constructed heading's width to the internal
  stack's width.
- **heading-return**: The add-heading operation MUST return the
  constructed panel heading view to its caller.

## Appearance

- **Corner radius**: Not applicable — the source never sets a corner
  radius; the component is only made layer-backed (see Platform Notes) so
  a background color can be painted.
- **Padding**: The internal stack is inset the standard panel-inset value
  (20pt) from the panel's top, leading, and trailing edges (equality
  constraints) and at most 20pt from the bottom edge (an inequality — see
  **bottom-inset-inequality**). Between arranged children, the default gap
  is the standard group-spacing value (20pt); the gap immediately above a
  heading added by the add-heading operation is widened to 1.5x that value
  (30pt) whenever a prior arranged child already exists.
- **Font**: Not applicable — the component renders no text of its own.
  Group captions and heading text belong to the Group View and Panel
  Heading View recipes, each of which documents its own typography.
- **Background**: The theme's window-background role, matching the
  source's own comment that this is "the same ground as the sidebar and
  the window."
- **Foreground/Text**: Not applicable — the component draws no text or
  icon of its own.
- **Border**: None — no border is drawn or configured anywhere in the
  source.
- **Shadow**: None — no shadow is drawn or configured anywhere in the
  source.
- **Min/Max size**: None declared by the component itself. Its width is
  whatever its superview gives it (no self-width constraint is set here,
  unlike the Group View's own width-matching behavior); its height is
  bounded below by the internal stack's accumulated content plus the 20pt
  top inset, but — per **bottom-inset-inequality** — the view MAY be
  taller than that, leaving unused space below the last arranged child.

## States

| State | Appearance change |
|-------|------------------|
| Default | The internal stack is empty and pinned inside the panel; the background is already painted from the current theme at construction. |
| Group added | A group view is appended as the next arranged child, separated from the previous arranged child (if any) by the default 20pt group-spacing value. |
| Heading added, stack previously non-empty | A panel heading view is appended; the gap between it and the arranged child before it is widened to 30pt; its width is matched to the internal stack. |
| Heading added, stack previously empty | A panel heading view is appended as the first arranged child; no spacing adjustment is made because there is no predecessor. |
| Theme changed | The background is reassigned to the new theme's window-background role; no other visual property changes. |
| Pressed | Not applicable: the source defines no target/action or gesture recognizer of its own; it is a passive layout host. |
| Disabled | Not implemented in the source; an enabled/disabled state is never read or set anywhere in source. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable beyond the platform's own default — the
  component sets no explicit accessibility role anywhere in source; it is
  a transparent layout container with no label, icon, or control of its
  own to expose. Each hosted group view/panel heading view manages its
  own accessibility per its own recipe.
- **Label requirements**: Not applicable — the component itself carries no
  text or icon content; the add-group/add-heading operations forward the
  caller's views and strings unchanged, with no label of the component's
  own to satisfy.
- **Announce state changes**: Not applicable — there is no loading or
  disabled state to announce (see States); the background repaint on a
  theme change is a silent, instantaneous recolor with no screen-reader
  announcement anywhere in source.
- **Minimum tap target**: Not applicable — the source defines no
  target/action or gesture recognizer of its own; whatever tap targets
  exist belong to the group view/panel heading view content it hosts,
  covered by their own recipes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-view-002 | confines-to-ui-thread | (Static/compile-time check) Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking, runtime-checked otherwise) |
| panel-view-004 | see Design Decisions | Construct the component with an explicit non-zero frame, checked immediately after construction, before layout | The resulting view's frame is zero, not the supplied rect |
| panel-view-007 | vertical-leading-stack-alignment | Construct the component | The internal stack's orientation is vertical and its alignment is leading |
| panel-view-008 | group-spacing | Construct the component | The internal stack's spacing equals 20.0 |
| panel-view-010 | top-leading-trailing-inset | Construct the component | Active constraints pin the stack's top/leading/trailing edges to the view's corresponding edges, each with constant 20.0 inward |
| panel-view-011 | bottom-inset-inequality | Inspect the component's active constraints | An inequality constraint relates the stack's bottom edge to the view's bottom edge with constant −20.0; no equality constraint exists between them |
| panel-view-012 | construction-time-background-paint | Construct the component under a known theme | The background equals that theme's window-background color immediately after construction returns |
| panel-view-013 | theme-change-background-repaint | Construct the component, then switch the active theme | The background updates to the new theme's window-background color |
| panel-view-015 | rejects-deserializing-construction | Attempt to construct the component via a deserializing/decoding-based construction path | Execution traps or fails; the exact message text is not required by this requirement (see Design Decisions) |
| panel-view-016 | group-arranged-subview-append | Call the add-group operation with a group view | The group view is an arranged child of the internal stack, at the end |
| panel-view-017 | heading-construction | Call the add-heading operation with title "Section" and caption "Some blurb" | A panel heading view is constructed with those two values forwarded to it (see the Panel Heading View recipe for how these values render) |
| panel-view-018 | heading-caption-default | Call the add-heading operation with title "Section" and no caption argument | The constructed panel heading view receives an absent caption (see the Panel Heading View recipe for its own no-caption behavior) |
| panel-view-019 | heading-gap | Call the add-group operation with a group view, then the add-heading operation with title "Section" | The stack's custom spacing after that group view is 30.0 |
| panel-view-020 | empty-stack-spacing-skip | Call the add-heading operation with title "Section" as the first call on a freshly constructed component | No custom spacing is set (the stack has no prior arranged child); no crash occurs |
| panel-view-021 | heading-arranged-subview-append | Call the add-heading operation with title "Section" | The returned panel heading view is an arranged child of the internal stack, at the end |
| panel-view-022 | heading-width-match | Call the add-heading operation with title "Section" | An active constraint equates the returned heading's width to the internal stack's width |
| panel-view-023 | heading-return | Capture the return value of the add-heading operation called with title "Section" | The returned value is the same panel heading view instance added to the stack; the caller can ignore the return value with no compiler warning |

Three implementation-only construction-rule checks (a parameterless
construction path forwarding to a zero frame, disabling the legacy
autoresizing-mask/frame system on the component and its internal stack,
and making the component layer-backed so a background color can be
painted) and one memory-management-only check (retaining the internal
theme-change observer for the view's lifetime) are framework mechanics
rather than portable behavior; see Platform Notes for
how the source implements them. Likewise, the marker-protocol conformance
this component satisfies is covered there rather than as a normative
requirement.

## Edge Cases

- **Null/empty input**: the group parameter of the add-group operation
  and the title parameter of the add-heading operation are non-optional,
  typed parameters; the type system rules out a missing value for either,
  so no null-handling path is needed. The caption parameter defaults to
  absent; an explicit empty string is passed straight through to the
  constructed panel heading view, which — per that recipe — still
  constructs a caption view whose label renders empty.
- **Boundary values**: Not applicable in the numeric sense — the
  component exposes no caller-configurable numeric range of its own; its
  only numeric behavior comes from the fixed layout constants (20pt panel
  inset, 20pt group spacing, the fixed 1.5x heading-gap multiplier).
- **Concurrent access**: Not applicable — the component is confined to
  the UI thread (see **confines-to-ui-thread**), so the add-group
  operation, the add-heading operation, and every constraint activation
  are serialized to that thread.
- **Error states**: Not applicable — every operation in the source
  (adding a group, adding a heading, repainting the background) is a
  synchronous, non-throwing call; no fallible or error-producing API
  appears in source.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **The add-heading operation called on an empty panel**: Per
  **empty-stack-spacing-skip**, the first heading in a panel sits with no
  extra gap above it, because there is no prior arranged child at that
  point and the spacing-adjustment guard simply does not run — no
  fallback spacing is applied in its place.
- **The view's own frame is unreachable by construction**: Per the design
  decision on frame handling (see Design Decisions), any frame passed at
  construction — including a non-zero one supplied directly by a caller
  who bypasses the parameterless construction path — is discarded; the
  view always begins at zero regardless.
- **Re-adding an already-parented group view**: this platform's mechanism
  for arranging children typically detaches a view from its previous
  parent before adding it to a new one; adding the same group view
  instance to a second Panel View (or a second time to the same one)
  silently removes it from its first location. The source contains no
  guard against this — the same source-traceable consequence the sibling
  Group View recipe documents for its own add-row operation (see
  **group-arranged-subview-append**).
- **A superview taller than the panel's content**: Because
  **bottom-inset-inequality** constrains the internal stack's bottom with
  an inequality rather than an equality, a Panel View given more height
  than its groups require leaves visible, unpainted-by-content slack
  between the last arranged child and the panel's bottom edge, rather than
  stretching the stack to fill it: no equality or centering constraint
  exists to distribute the extra space.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Group (add-group operation) | group-view reference | — (required) | The card appended as the panel's next arranged child. |
| Title (add-heading operation) | string | — (required) | Heading text forwarded verbatim to the constructed panel heading view. |
| Caption (add-heading operation) | string, optional | absent | Optional caption text forwarded verbatim to the constructed panel heading view. |

## Deep Linking

Not applicable: the component is a layout container inside a composable
settings window, not a navigable screen; no URL scheme, route, or
deep-link handler appears anywhere in the source.

## Localization

Not applicable: the source defines no string literal of its own. The
add-heading operation's title and caption parameters are entirely
caller-supplied and forwarded verbatim to the constructed panel heading
view — localizing them is the caller's responsibility, the same treatment
the sibling Panel Heading View recipe documents for those same two
parameters one level down.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation or transition of any kind; adding a group, adding a heading, and repainting the background on a theme change are each a synchronous, instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting and sets no literal color; the background is a theme-resolved semantic role, which this file does not further adjust for contrast. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; its background is decorative ground behind the groups it hosts, not a status or selection indicator. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in the source; the background paints and every added
group/heading render unconditionally.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  group-view/panel-heading-view instances it is given, plus its own
  internal stack and theme-change observer.
- **Storage**: Not applicable — the source performs no read/write to disk
  or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in the source.
- **Retention**: Not applicable — the view retains its stack, its added
  arranged children, and its theme observer only for its own lifetime; it
  persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

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
- **AppKit / UIKit** (source platform): `ComposableSettings.PanelView`, at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelView.swift`,
  is a macOS-only (`import AppKit`), `open`, `@MainActor` `NSView` subclass
  conforming to `SettingsViewProtocol` (a marker protocol with no
  requirements of its own). Internally, the private stored properties
  `stackView` (`NSStackView`) and `themeObserver`
  (`ThemePaletteObserver?`) back the stack and theme-repaint behavior
  described under Behavioral Requirements; `themeObserver` is retained in
  a stored property for the view's whole lifetime so its Combine
  subscriptions are not deallocated early. `wantsLayer = true` is set at
  construction so `layer?.backgroundColor` can be painted
  (**construction-time-background-paint**), reading the current theme's
  `.windowBackground` role (`palette.windowBackgroundColor.cgColor`),
  resolved through a `ThemePaletteObserver` constructed with `host: self`
  (see Design Decisions) rather than the unscoped, app-wide palette; the
  observer repaints the layer on every subsequent notification
  (**theme-change-background-repaint**). The component and its internal
  stack view each set `translatesAutoresizingMaskIntoConstraints = false`
  at construction — a pure Auto Layout framework construction rule with no
  equivalent step needed on a platform that never had a legacy
  autoresizing-mask/frame layout system to opt out of. The public
  `convenience init()` forwards to `init(frame: .zero)` with no parameters
  of its own; `required init?(coder:)` traps via `fatalError`
  (**rejects-deserializing-construction**), with message text `not
  overridden` (see Design Decisions — the mismatch with the sibling
  `GroupView`/`PanelHeadingView` message is a known, unsmoothed
  inconsistency). The add-heading operation is `@discardableResult`, built
  on `NSStackView` and Auto Layout. There is no UIKit code path in source;
  because `ThemePaletteObserver` itself is already cross-platform
  (`SourcesUI/Shared`), a UIKit port would only need to replace
  `NSStackView` with `UIStackView` and the layer background assignment
  with the UIKit equivalent (`layer.backgroundColor` on a layer-backed
  `UIView`, which is layer-backed by default) — the theme observer and its
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelView.swift` |

## Design Decisions

- **Decision**: Constrain the internal stack's bottom edge with an
  inequality rather than an equality constraint, unlike the
  top/leading/trailing edges.
  **Rationale**: Not explained in source comments beyond the code itself.
  An inequality lets the stack's own computed height determine the
  panel's occupied region without forcing the stack to stretch and fill a
  taller frame the panel happens to be given, the same "size to content,
  not to container" outcome the Group View's sibling recipe gets from
  having no height constraint of its own at all.
  **Approved**: pending
- **Decision** (AppKit): The designated `init(frame:)` ignores the
  caller-supplied `frameRect` entirely and always forwards `.zero` to
  `super.init(frame:)`.
  **Rationale**: Not explained in source comments; the effect is that no
  caller can give the component a non-zero initial frame, even by
  bypassing the parameterless construction path. This is a known quirk
  rather than a deliberate API contract — kept as-is because it is what
  the source does (see the frame edge case above).
  **Approved**: pending
- **Decision** (AppKit): Resolve the background color through a
  `ThemePaletteObserver(host: self)` rather than reading the unscoped,
  app-wide palette once at construction.
  **Rationale**: Per the source's own comment, this keeps the panel's
  ground the same as "the sidebar and the window," painted from the
  component's own resolved theme scope rather than a single global
  palette, and it stays live for the view's lifetime rather than being
  captured once.
  **Approved**: pending
- **Decision**: The add-heading operation widens the gap above a heading
  to 1.5x the group-spacing value only when a prior arranged child already
  exists, rather than always applying the wider spacing or applying it to
  the gap below the heading.
  **Rationale**: Per the source's own doc comment, "the gap above a
  heading is wider than the gap between two cards, because that gap is
  what says the heading belongs to what comes *after* it — at the stack's
  own spacing it reads as a caption trailing the card above." A first
  heading with nothing above it needs no such signal, so no adjustment is
  made.
  **Approved**: pending
- **Decision** (AppKit): The deserializing-construction path traps via
  `fatalError`, and its current message text (`not overridden`) is left
  as-is rather than standardized to match the sibling Group
  View/Panel Heading View message (`init(coder:) has not been
  implemented`).
  **Rationale**: The message text is not part of the
  **rejects-deserializing-construction** requirement; the mismatch is a
  real, source-traceable inconsistency between siblings, not smoothed
  over in either direction.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |

`native-controls-preference` passes because the component is built
entirely from native platform views and stack containers. `screen-reader-support`
passes because the component is a transparent layout container with no
label or control of its own for a screen reader to need; each hosted
child manages its own accessibility per its own recipe.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `PanelView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformatted frontmatter (references moved to related, depends-on populated with GroupView/PanelHeadingView); renamed requirements to subject-noun form and updated every citation; moved the ignored-frame behavior and the coder-initializer message wording into Design Decisions; removed stray MUST labels and a garbled title from Edge Cases; marked test vector 002 as compile-time and fixed vector 004's timing and vectors 017/018 to assert PanelHeadingView's public inputs instead of its private labels; reformatted Design Decisions to the bold convention and dropped a non-decision entry; trimmed Platform Notes editorializing and moved private stack/observer identifiers there; cleaned the Compliance table to catalog-valid checks with Title Case categories. |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
