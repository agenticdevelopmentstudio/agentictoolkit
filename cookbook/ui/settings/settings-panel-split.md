---
id: ba8d9517-2528-4ae9-bc52-16046d68b126
title: Settings Panel Split
domain: agentictoolkit://cookbook/ui/settings/settings-panel-split
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings panel that is itself a nested topic/detail split, so a
  sub-hierarchy nests inside the outer settings window without a wrapper.
platforms:
- swift
- macos
tags:
- settings
- split-view
- view-controller
- nesting
depends-on:
- agentictoolkit://cookbook/ui/settings/settings-split-view
related:
- agentictoolkit://cookbook/ui/settings/settings-panel
- agentictoolkit://cookbook/ui/settings/settings-panel-list
references: []
approved-by: ''
approved-date: ''
---

# Settings Panel Split

## Overview

The Settings Panel Split is the base component for a settings panel that is
itself a nested topic/detail split — a sub-hierarchy (for example, a
"Theme" topic with several sub-panels) hosted in the outer settings
window's own detail pane. It builds on the settings split view (the
split-pane container: sidebar of panels plus a detail pane showing the
current selection) and satisfies the interface that lets a component be
hosted as a settings panel through that same inheritance, so an instance
can be added as a row/panel of an *enclosing* settings split while itself
hosting a second, independent sidebar and detail pane. This is what lets a
sub-hierarchy be expressed as one added panel rather than a second window
or sheet. This recipe documents only what this component itself declares
or overrides; the sidebar/detail mechanics it inherits (panel management,
navigation history, theming, the help drawer plumbing) belong to the
settings split view's own recipe, and the panel-list rendering it composes
belongs to the panel list's own recipe.

## Behavioral Requirements

- **exposes-descriptor**: The component MUST expose a descriptor property,
  satisfying the requirement that every hostable panel carry the metadata
  (title, icon, disabled state, section) its own sidebar row is built
  from.
- **defaults-descriptor-when-omitted**: When constructed with no
  descriptor argument (or an explicit absence of one), the component MUST
  use a default descriptor whose title is an empty string, rather than
  leaving its descriptor unset.
- **titles-sidebar-from-descriptor**: During initialization, the component
  MUST set its own inherited sidebar title to the descriptor's title, so
  its nested topic list's header defaults to this panel's own title.
- **acts-as-hostable-panel**: The component MUST satisfy the interface a
  hosting split requires of a panel, so an instance MAY be added as a
  panel inside an *enclosing* split's sidebar, nesting one topic/detail
  split inside another.
- **returns-nil-help-content-by-default**: The component's help content
  MUST return none unless a subclass overrides it.
- **falls-back-help-content-through-inner-selection**: The component's
  effective help content MUST return the currently selected inner panel's
  own effective help content when that value is non-empty, and MUST fall
  back to this panel's own help content when there is no inner selection
  or the inner selection's effective help content is empty.
- **surfaces-empty-help-when-chain-exhausted**: Composing
  **falls-back-help-content-through-inner-selection** with
  **returns-nil-help-content-by-default**, when there is no inner
  selection (or the inner selection's effective help content is empty)
  and no subclass overrides this panel's own help content, the
  component's effective help content MUST evaluate to none rather than to
  a placeholder value: a panel with nothing to add gets the drawer's own
  empty state rather than losing its help affordance.
- **reports-no-additional-search-keywords**: The component's search
  keywords MUST return an empty list; it contributes no keywords of its
  own beyond whatever its hosted inner panels supply to their own sidebar
  search.
- **narrows-detail-minimum-thickness**: The component MUST override its
  detail-pane minimum-thickness floor to return `200` points.
- **fixes-content-sized-sidebar**: The component MUST override its
  content-sized-sidebar flag to return true.

## Appearance

- **Corner radius**: Not applicable — this component draws no chrome of
  its own; any corner radius shown by hosted content belongs to that
  content's own recipe (e.g. a group view's card).
- **Padding**: Not applicable — no padding or inset constant is set in
  this component; the inherited settings split view owns the sidebar/
  detail layout this component does not override.
- **Font**: Not applicable — this component draws no text of its own.
- **Background**: Not applicable — no background is set in this
  component; the inherited settings split view's theme-application step
  paints the window/detail background, and this component does not
  override it.
- **Foreground/Text**: Not applicable — this component sets no color.
- **Border**: Not applicable — no border is configured in this component.
- **Shadow**: Not applicable — no shadow is configured in this component.
- **Min/Max size**: The detail-pane minimum-thickness floor is overridden
  to `200` points — a floor on the nested detail pane's width, not a
  maximum; no maximum size is set anywhere in this component. This floor
  deliberately stays below the inherited settings split view's default
  floor of `400` points, so it caps only the inner content rather than
  compounding the window's overall minimum width.

## States

| State | Appearance change |
|-------|------------------|
| Default | Newly initialized: the descriptor is the given value or a default (empty title); the sidebar title equals the descriptor's title; the detail-pane minimum-thickness floor is `200`; the content-sized-sidebar flag is true. |
| Inner panel selected, that panel offers help | Effective help content returns the selected inner panel's own effective help content (**falls-back-help-content-through-inner-selection**). |
| No inner selection, or the selected inner panel offers no help | Effective help content falls back to this panel's own help content (none unless a subclass overrides it). |
| Pressed | Not applicable — this component defines no pressable control of its own; it is a container, not a control. |
| Disabled | Not applicable in this component — the descriptor's disabled flag exists on the shared descriptor type but is never read anywhere in this component; whatever a disabled row does with it is the sidebar-row renderer's responsibility, outside this component. |
| Focused | Not applicable — this component adds no focus/first-responder handling of its own; the inherited settings split view's key-view loop and search field are unmodified by this component. |
| Loading | Not applicable — every member of this component is a synchronous initializer or computed property; there is no asynchronous operation. |

## Accessibility

- **Role/trait**: Not applicable — this component sets no accessibility
  role of its own; it is a plain container, and any role for rendered UI
  belongs to the inherited sidebar/detail views, each covered by its own
  recipe.
- **Keyboard/assistive technology navigation**: Not applicable in this
  component — no keyboard handling is added or overridden here; the
  inherited settings split view's search-field arrow-key handling and
  standard split-view tab order are unmodified by this component.
- **Label requirements**: Not applicable to this component — the sidebar
  title is set from the caller-supplied descriptor's title, but rendering
  that title (and whatever accessible label it produces) is the panel
  list's responsibility, a separate component with its own recipe; this
  component assigns no accessibility label of its own.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this component has no loading or disabled state to announce (see
  States).
- **Minimum tap target**: Not applicable — this component defines no
  interactive control of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-panel-split-view-controller-001 | exposes-descriptor | Construct with an explicit descriptor whose title is `"Theme"` | The descriptor's title is `"Theme"` |
| settings-panel-split-view-controller-002 | defaults-descriptor-when-omitted | Construct with no descriptor | The descriptor is a default descriptor whose title is `""` |
| settings-panel-split-view-controller-003 | titles-sidebar-from-descriptor | Construct with a descriptor whose title is `"Theme"` | The sidebar title is `"Theme"` |
| settings-panel-split-view-controller-005 | acts-as-hostable-panel | Construct an instance and add it as a panel of a separate, outer settings split | The outer split accepts it without a compile or runtime error; the instance appears in the outer split's panel list |
| settings-panel-split-view-controller-006 | returns-nil-help-content-by-default | Read the help content on a plain (non-subclassed) instance | Returns none |
| settings-panel-split-view-controller-007 | falls-back-help-content-through-inner-selection | Select an inner panel whose effective help content is non-empty | Effective help content on this instance returns that same value |
| settings-panel-split-view-controller-008 | falls-back-help-content-through-inner-selection | No inner panel selected, and a subclass overrides help content to a non-empty value | Effective help content returns that overridden help-content value |
| settings-panel-split-view-controller-009 | falls-back-help-content-through-inner-selection | An inner panel is selected, its effective help content is empty, and a subclass overrides this panel's own help content to a non-empty value | Effective help content falls through the inner selection's empty value and returns the subclass's overridden help content |
| settings-panel-split-view-controller-010 | surfaces-empty-help-when-chain-exhausted | No inner panel is selected (or the inner selection's effective help content is empty), and no subclass overrides help content | Effective help content evaluates to none |
| settings-panel-split-view-controller-011 | reports-no-additional-search-keywords | Read search keywords on a plain (non-subclassed) instance | Returns an empty list |
| settings-panel-split-view-controller-012 | narrows-detail-minimum-thickness | Read the detail-pane minimum-thickness floor | Returns `200` |
| settings-panel-split-view-controller-013 | fixes-content-sized-sidebar | Read the content-sized-sidebar flag | Returns true |

## Edge Cases

- **Null/empty input**: Constructing with no descriptor MUST use a
  default descriptor rather than leaving the descriptor unset or crashing
  (**defaults-descriptor-when-omitted**); that default descriptor's title
  is the empty string, so the sidebar title is set to `""` — this
  component performs no validation that a title is non-empty.
- **Boundary values**: The detail-pane minimum-thickness floor of `200`
  and the content-sized-sidebar flag of true are fixed override values,
  not caller-supplied inputs, so there is no boundary range to exercise on
  them directly; the only defined relationship is that `200` MUST stay
  below the inherited settings split view's default floor of `400` points
  (see Design Decisions).
- **Concurrent access**: Not applicable — the component's construction and
  every property access are confined to a single, serialized execution
  context (see Platform Notes), so there is no concurrent-access surface
  for this component to define behavior for.
- **Error states**: Not applicable — every member in this component (both
  construction paths and the four computed properties) is synchronous and
  non-throwing; no dependency, network call, or fallible operation exists
  in this component.
- **Offline/disconnected state**: Not applicable — this component performs
  no networking and has no dependency on connectivity.
- **Help chain resolves to no help at all**: When there is no inner
  selection and no subclass override of help content, effective help
  content evaluates to none (**surfaces-empty-help-when-chain-exhausted**,
  composing **falls-back-help-content-through-inner-selection**); this is
  a defined state — the outer split's help drawer shows its own empty
  state rather than hiding its help affordance.
- **The descriptor's disabled flag and section field go unused by this
  component**: The descriptor type carries both fields, but neither is
  read anywhere in this component; this is not a gap in this component —
  both are consumed by the sidebar-row renderer (the panel list) and by
  the settings split view's section-sort logic, outside this component.
  This component simply has no code path that reads either field.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | descriptor (optional) | none (resolves to a default descriptor, title `""`) | The panel's own sidebar-row metadata; also the source of the sidebar title at initialization. |

## Deep Linking

Not applicable: no URL scheme, route, or deep-link handling appears
anywhere in this component.

## Localization

Not applicable: this component contains no string literal of its own. The
sidebar title is set from the caller-supplied descriptor's title; whatever
localization applies to that string is decided at the call site that
constructs the descriptor, not in this component.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this component. |
| Increase Contrast | Not applicable: no color is set anywhere in this component. |
| Differentiate Without Color | Not applicable: this component has no color-only state indicator. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — this component holds only the descriptor
  reference it is constructed with or defaults to.
- **Storage**: Not applicable — no persistence code exists in this
  component.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component.
- **Retention**: The descriptor reference is held in memory for this
  component's own lifetime and is never persisted by this component.

## Logging

Not applicable: no logging call appears anywhere in this component.

## Platform Notes

- **SwiftUI**: Nest an inner `NavigationSplitView` as the detail content of
  an outer `NavigationSplitView`'s selected row. Give the inner split's
  sidebar column a fixed
  `.navigationSplitViewColumnWidth(min: w, ideal: w, max: w)` (min == ideal
  == max), the nearest SwiftUI analog to the content-sized-sidebar flag's
  non-draggable, content-sized sidebar, and title it from the same
  descriptor's title used for the outer row's own label. There is no
  direct SwiftUI equivalent of a per-split detail-pane minimum thickness;
  the nearest approximation is a `.frame(minWidth:)` on the inner split's
  detail content.
- **Compose**: Nest a two-pane `ListDetailPaneScaffold` (Material 3
  adaptive) or a `PermanentNavigationDrawer` inside an outer one of the
  same shape; size the inner pane with `Modifier.width(IntrinsicSize.Max)`
  rather than a draggable `Modifier.width` handle, mirroring the fixed
  sidebar. Reuse the same descriptor title for both the outer list row's
  label and the inner pane's own header.
- **React/Web**: A nested two-column layout (`display: grid;
  grid-template-columns: max-content 1fr`) inside an outer layout of the
  same shape, so the inner nav column sizes to its widest row with no
  resize handle — the web analog of the content-sized-sidebar flag. Reuse
  the same title string for the outer link and the inner column's
  heading.
- **AppKit / UIKit** (source platform): Source file
  `SettingsPanelSplitViewController.swift`, AppKit-only, no UIKit
  counterpart in this codebase (`ComposableSettingsWindow/` is entirely
  AppKit). It subclasses `ComposableSettings.SplitViewController`
  (`SplitViewController/SplitViewController.swift`), conforms to
  `ComposableSettingsPanel` (`ComposableSettingsPanel.swift`) through that
  inheritance, and stores a `ComposableSettings.SettingsPanelDescriptor`
  (`SettingsPanelDescriptor.swift`) — all three defined elsewhere in
  `AgenticToolkit` and not reimplemented here. The class is `@MainActor`,
  so construction and every property access are rejected off the main
  actor at compile time. It does not support construction via
  `init?(coder:)`: that initializer is overridden to call `fatalError()`,
  so a caller cannot construct one through that path. It also redeclares
  `helpContent`, `effectiveHelpContent`, and `searchKeywords` directly on
  the class rather than relying solely on `ComposableSettingsPanel`'s
  protocol-extension defaults — see Design Decisions for why.
- **WinUI 3**: Nest one `NavigationView`
  inside another's `Content`. Give the inner `NavigationView`
  `PaneDisplayMode="Left"` and `IsPaneToggleButtonVisible="False"`; its
  built-in pane has no draggable splitter (unlike `SplitView`), which
  matches the content-sized-sidebar flag without extra work. Bind the
  inner `NavigationView`'s `Header` to the panel's own title — the WinUI
  analog of setting the sidebar title from the descriptor's title — and
  set the *outer* `NavigationViewItem` that hosts this nested view's
  `Content` from that same title string. WinUI has no per-pane analog of
  a minimum-thickness floor; approximate the `200`pt floor with a fixed
  `MinWidth="200"` on the `Frame`/`ContentPresenter` hosting the inner
  `NavigationView`'s content region, deliberately smaller than the outer
  shell's own minimum width so it constrains only the nested region. For
  help, forward whichever inner `NavigationViewItem` is selected up to the
  outer shell's single help affordance (a `Button` + `Flyout`, or
  `AutomationProperties.HelpText`) and fall back to this nested view's own
  help text only when the inner selection offers none — mirroring the
  effective-help-content fallback chain.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelSplitViewController.swift` |

## Design Decisions

**Decision**: Override the detail-pane minimum-thickness floor to `200`
points rather than inheriting the settings split view's `400`pt default.
**Rationale**: "A modest floor so the nested detail (the sub-panel
content) can't be squeezed to a sliver. It stays below the outer detail's
own floor, so it caps the inner content rather than compounding the
window's minimum width."
**Approved**: pending

**Decision**: Override the content-sized-sidebar flag to true rather than
inheriting the settings split view's draggable, autosaved default.
**Rationale**: "Nested topic lists are content-sized and unified to one
width by the parent split, so switching between sibling panels never
shifts the inner divider and every title stays fully disclosed."
**Approved**: pending

**Decision**: Redeclare help content, effective help content, and search
keywords on this class rather than relying solely on the shared
protocol-extension defaults. (AppKit.)
**Rationale**: A protocol extension's default is bound at the point of
conformance; a subclass override reachable only through the extension
default would be invisible through the generic interface the enclosing
split holds. Redeclaring the properties on the class keeps subclass
overrides reachable.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |

Statuses rest on: this file overriding only the four properties that differ
from its base class and delegating every other behavior to
`SplitViewController` rather than reimplementing it
(separation-of-concerns); this file adding no keyboard handling of its own
that could remove a control from the tab order or block default activation,
while the actual keyboard path (search-field arrow keys, split-view tab
order) is inherited and evaluated by `SplitViewController`'s own recipe —
hence `partial` here rather than `passed` (keyboard-navigable); this file
introducing no accessibility role, label, or announcement of its own to
regress, while the rendered role/label surface is likewise
`SplitViewController`'s and `PanelListViewController`'s to evaluate — hence
`partial` here as well (screen-reader-support); and this file rendering no
custom-drawn chrome, composing only inherited AppKit split-view behavior
(native-controls-preference).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformat Design Decisions to the bold three-line form and cite the specific member behind each quoted claim; move two implicit MUSTs out of Edge Cases into a new named requirement and plain prose; add missing help-chain conformance vectors and drop the untestable main-actor compile-time vector; renumber test vector IDs sequentially; populate depends-on/related with the base class and sibling recipes; de-duplicate the `macos` tag; disambiguate the Overview's dangling class reference; remove editorializing from the WinUI 3 bullet; mark keyboard-navigable/screen-reader-support partial and point to SplitViewController's recipe; clean up Compliance rows to match the catalog |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/. |
