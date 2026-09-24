---
id: ba8d9517-2528-4ae9-bc52-16046d68b126
title: SettingsPanelSplitViewController
domain: agentictoolkit://recipes/settings-panel-split-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit base class letting a settings panel itself be a nested topic/detail
  split, so a sub-hierarchy nests inside the outer settings window without a wrapper.
platforms:
- swift
- macos
tags:
- settings
- split-view
- view-controller
- nesting
- appkit
depends-on:
- agentictoolkit://recipes/split-view-controller
related:
- agentictoolkit://recipes/settings-panel-view-controller
- agentictoolkit://recipes/settings-panel-list-view-controller
references: []
approved-by: ''
approved-date: ''
---

# SettingsPanelSplitViewController

## Overview

`ComposableSettings.SettingsPanelSplitViewController`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelSplitViewController.swift`,
is the base class for a settings panel that is itself a nested topic/detail
split — a sub-hierarchy (for example, a "Theme" topic with several
sub-panels) hosted in the outer settings window's own detail pane. It
subclasses `ComposableSettings.SplitViewController` (the split-pane
container: sidebar of panels plus a detail pane showing the current
selection) and conforms to `ComposableSettingsPanel` through that
inheritance, so an instance can be added as a row/panel of an *enclosing*
`SplitViewController` while itself hosting a second, independent sidebar and
detail pane. Per the source's own doc comments, this is what lets a
sub-hierarchy be a subclass and an `addPanel` call rather than a second
window or sheet. This recipe documents only what this class itself declares
or overrides; the sidebar/detail mechanics it inherits (panel management,
navigation history, theming, the help drawer plumbing) belong to
`SplitViewController`'s own recipe, and the panel-list rendering it composes
belongs to `PanelListViewController`'s own recipe.

## Behavioral Requirements

- **exposes-descriptor**: The component MUST expose a
  `descriptor: SettingsPanelDescriptor` property, satisfying
  `ComposableSettingsPanel`'s requirement that every hostable panel carry
  the metadata (title, icon, disabled state, section) its own sidebar row
  is built from.
- **defaults-descriptor-when-omitted**: When constructed via
  `init(with:)` with no descriptor argument (or an explicit `nil`), the
  component MUST use `SettingsPanelDescriptor()` — an empty descriptor
  whose `title` is `""` — rather than leaving `descriptor` unset.
- **titles-sidebar-from-descriptor**: During initialization, the
  component MUST set its own inherited `sidebarTitle` to `descriptor.title`,
  so its nested topic list's header defaults to this panel's own title.
- **rejects-coder-initialization**: The component MUST NOT support
  construction via `init(coder:)`; that initializer MUST call
  `fatalError()`.
- **acts-as-hostable-panel**: The component MUST conform to
  `ComposableSettingsPanel` (via subclassing `SplitViewController`), so an
  instance MAY be added as a panel inside an *enclosing*
  `SplitViewController`'s sidebar, nesting one topic/detail split inside
  another.
- **returns-nil-help-content-by-default**: The component's `helpContent`
  MUST return `nil` unless a subclass overrides it.
- **falls-back-help-content-through-inner-selection**: The component's
  `effectiveHelpContent` MUST return the inherited `effectiveHelp` (the
  currently selected inner panel's own `effectiveHelpContent`) when that
  value is non-`nil`, and MUST fall back to this panel's own `helpContent`
  when there is no inner selection or the inner selection's
  `effectiveHelpContent` is `nil`.
- **surfaces-empty-help-when-chain-exhausted**: Composing
  **falls-back-help-content-through-inner-selection** with
  **returns-nil-help-content-by-default**, when there is no inner selection
  (or the inner selection's `effectiveHelpContent` is `nil`) and no subclass
  overrides this panel's own `helpContent`, the component's
  `effectiveHelpContent` MUST evaluate to `nil` rather than to a placeholder
  value, per `ComposableSettingsPanel.helpContent`'s own doc comment: a
  panel with nothing to add gets the drawer's own empty state rather than
  losing its help affordance.
- **reports-no-additional-search-keywords**: The component's
  `searchKeywords` MUST return an empty array; it contributes no keywords
  of its own beyond whatever its hosted inner panels supply to their own
  sidebar search.
- **narrows-detail-minimum-thickness**: The component MUST override
  `detailMinimumThickness` to return `200` points.
- **fixes-content-sized-sidebar**: The component MUST override
  `contentSizedSidebar` to return `true`.
- **runs-on-main-actor**: The component MUST be `@MainActor`-isolated;
  construction and every property access MUST occur on the main actor.

## Appearance

- **Corner radius**: Not applicable — this file draws no chrome of its
  own; any corner radius shown by hosted content belongs to that content's
  own recipe (e.g. `GroupView`'s card).
- **Padding**: Not applicable — no padding or inset constant is set in
  this file; the inherited `SplitViewController` owns the sidebar/detail
  layout this class does not override.
- **Font**: Not applicable — this file draws no text of its own.
- **Background**: Not applicable — no background is set in this file; the
  inherited `SplitViewController.applyTheme` paints the window/detail
  background, and this subclass does not override it.
- **Foreground/Text**: Not applicable — this file sets no color.
- **Border**: Not applicable — no border is configured in this file.
- **Shadow**: Not applicable — no shadow is configured in this file.
- **Min/Max size**: `detailMinimumThickness` is overridden to `200`
  points — a floor on the nested detail pane's width, not a maximum; no
  maximum size is set anywhere in this file. Per the doc comment on this
  override, the floor deliberately stays below the inherited
  `SplitViewController.detailMinimumThickness` default of `400` points, so
  it caps only the inner content rather than compounding the window's
  overall minimum width.

## States

| State | Appearance change |
|-------|------------------|
| Default | Newly initialized: `descriptor` is the given value or `SettingsPanelDescriptor()`; `sidebarTitle == descriptor.title`; `detailMinimumThickness == 200`; `contentSizedSidebar == true`. |
| Inner panel selected, that panel offers help | `effectiveHelpContent` returns the selected inner panel's own `effectiveHelpContent` (**falls-back-help-content-through-inner-selection**). |
| No inner selection, or the selected inner panel offers no help | `effectiveHelpContent` falls back to this panel's own `helpContent` (`nil` unless a subclass overrides it). |
| Pressed | Not applicable — this file defines no pressable control of its own; it is a container view controller, not an `NSControl`. |
| Disabled | Not applicable in this file — `SettingsPanelDescriptor.isDisabled` exists on the shared descriptor type but is never read anywhere in `SettingsPanelSplitViewController.swift`; whatever a disabled row does with it is the sidebar-row renderer's responsibility, outside this file. |
| Focused | Not applicable — this file adds no focus/first-responder handling of its own; the inherited `SplitViewController`'s key-view loop and search field are unmodified by this subclass. |
| Loading | Not applicable — every member of this file is a synchronous initializer or computed property; there is no asynchronous operation. |

## Accessibility

- **Role/trait**: Not applicable — this file sets no accessibility role of
  its own; it is a plain `NSViewController`/`SplitViewController` subclass,
  and any role for rendered UI belongs to the inherited sidebar/detail
  views, each covered by its own recipe.
- **Keyboard/assistive technology navigation**: Not applicable in this
  file — no keyboard handling is added or overridden here; the inherited
  `SplitViewController`'s search-field arrow-key handling and standard
  `NSSplitViewController` tab order are unmodified by this subclass.
- **Label requirements**: Not applicable to this file — `sidebarTitle` is
  set from the caller-supplied `descriptor.title`, but rendering that
  title (and whatever accessible label it produces) is
  `PanelListViewController`'s responsibility, a separate component with
  its own recipe; this file assigns no accessibility label of its own.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this file has no loading or disabled state to announce (see States).
- **Minimum tap target**: Not applicable — this file defines no
  interactive control of its own on macOS.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-panel-split-view-controller-001 | exposes-descriptor | Construct with an explicit `SettingsPanelDescriptor(title: "Theme")` | `descriptor.title == "Theme"` |
| settings-panel-split-view-controller-002 | defaults-descriptor-when-omitted | Construct via `init(with: nil)` | `descriptor` is a `SettingsPanelDescriptor` whose `title == ""` |
| settings-panel-split-view-controller-003 | titles-sidebar-from-descriptor | Construct with `SettingsPanelDescriptor(title: "Theme")` | `sidebarTitle == "Theme"` |
| settings-panel-split-view-controller-004 | rejects-coder-initialization | Attempt `init?(coder:)` | The call traps with a fatal error; no instance is returned |
| settings-panel-split-view-controller-005 | acts-as-hostable-panel | Construct an instance and call `enclosingSplit.addPanel(instance)` on a separate, outer `SplitViewController` | The outer split accepts it without a compile or runtime error; the instance appears in the outer split's `panels` |
| settings-panel-split-view-controller-006 | returns-nil-help-content-by-default | Read `helpContent` on a plain (non-subclassed) instance | Returns `nil` |
| settings-panel-split-view-controller-007 | falls-back-help-content-through-inner-selection | Select an inner panel whose `effectiveHelpContent` is non-`nil` | `effectiveHelpContent` on this instance returns that same value |
| settings-panel-split-view-controller-008 | falls-back-help-content-through-inner-selection | No inner panel selected, and a subclass overrides `helpContent` to a non-`nil` value | `effectiveHelpContent` returns that overridden `helpContent` value |
| settings-panel-split-view-controller-009 | falls-back-help-content-through-inner-selection | An inner panel is selected, its `effectiveHelpContent` is `nil`, and a subclass overrides this panel's own `helpContent` to a non-`nil` value | `effectiveHelpContent` falls through the inner selection's `nil` and returns the subclass's overridden `helpContent` value |
| settings-panel-split-view-controller-010 | surfaces-empty-help-when-chain-exhausted | No inner panel is selected (or the inner selection's `effectiveHelpContent` is `nil`), and no subclass overrides `helpContent` | `effectiveHelpContent` evaluates `nil ?? nil` and returns `nil` |
| settings-panel-split-view-controller-011 | reports-no-additional-search-keywords | Read `searchKeywords` on a plain (non-subclassed) instance | Returns `[]` |
| settings-panel-split-view-controller-012 | narrows-detail-minimum-thickness | Read `detailMinimumThickness` | Returns `200` |
| settings-panel-split-view-controller-013 | fixes-content-sized-sidebar | Read `contentSizedSidebar` | Returns `true` |

**runs-on-main-actor** has no conformance vector: Swift's actor isolation
checking rejects construction or mutation from off the main actor at
compile time, so there is no runtime behavior left to assert — the
requirement stands on the compiler's own enforcement.

## Edge Cases

- **Null/empty input**: `init(with: nil)` MUST use `SettingsPanelDescriptor()`
  rather than leaving `descriptor` unset or crashing
  (**defaults-descriptor-when-omitted**); that default descriptor's `title`
  is the empty string, so `sidebarTitle` is set to `""` — this file
  performs no validation that a title is non-empty.
- **Boundary values**: `detailMinimumThickness`'s `200` and
  `contentSizedSidebar`'s `true` are fixed override values, not
  caller-supplied inputs, so there is no boundary range to exercise on
  them directly; the only defined relationship is that `200` MUST stay
  below `SplitViewController.detailMinimumThickness`'s inherited `400`pt
  default (see Design Decisions).
- **Concurrent access**: Not applicable — the class is `@MainActor`, so
  the Swift compiler rejects construction or mutation from off the main
  actor; there is no concurrent-access surface for this file to define
  behavior for.
- **Error states**: Not applicable — every member in this file (the two
  initializers and the four computed properties) is synchronous and
  non-throwing; no dependency, network call, or fallible operation exists
  in this file.
- **Offline/disconnected state**: Not applicable — this file performs no
  networking and has no dependency on connectivity.
- **Help chain resolves to no help at all**: When there is no inner
  selection and no subclass override of `helpContent`,
  `effectiveHelpContent` evaluates `nil ?? nil` and returns `nil`
  (**surfaces-empty-help-when-chain-exhausted**, composing
  **falls-back-help-content-through-inner-selection**); per
  `ComposableSettingsPanel`'s own doc comment, this is a defined state —
  the outer split's help drawer shows its own empty state rather than
  hiding its help affordance.
- **`descriptor.isDisabled` and `descriptor.section` go unused by this
  file**: `SettingsPanelDescriptor` carries both fields, but neither is
  read anywhere in `SettingsPanelSplitViewController.swift`; this is not a
  gap in this file — both are consumed by the sidebar-row renderer
  (`PanelListViewController`) and by `SplitViewController.ordered(_:)`'s
  sort-by-section logic, outside this file. This file simply has no code
  path that reads either field.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | `SettingsPanelDescriptor?` | `nil` (resolves to `SettingsPanelDescriptor()`, `title == ""`) | The panel's own sidebar-row metadata; also the source of `sidebarTitle` at initialization. |

## Deep Linking

Not applicable: no URL scheme, route, or `NSUserActivity` handling appears
anywhere in `SettingsPanelSplitViewController.swift`.

## Localization

Not applicable: this file contains no string literal of its own.
`sidebarTitle` is set from the caller-supplied `descriptor.title`; whatever
localization applies to that string is decided at the call site that
constructs the descriptor, not in this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this file. |
| Increase Contrast | Not applicable: no color is set anywhere in this file. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this file.

## Analytics

Not applicable: this file contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — this file holds only the `descriptor`
  reference it is constructed with or defaults to.
- **Storage**: Not applicable — no persistence code exists in this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this file.
- **Retention**: The `descriptor` reference is held in memory for this
  controller's own lifetime and is never persisted by this file.

## Logging

Not applicable: no logging call (`print`, `os_log`, or logger reference)
appears anywhere in `SettingsPanelSplitViewController.swift`.

## Platform Notes

- **SwiftUI**: Nest an inner `NavigationSplitView` as the detail content of
  an outer `NavigationSplitView`'s selected row. Give the inner split's
  sidebar column a fixed
  `.navigationSplitViewColumnWidth(min: w, ideal: w, max: w)` (min == ideal
  == max), the nearest SwiftUI analog to `contentSizedSidebar == true`'s
  non-draggable, content-sized sidebar, and title it from the same
  descriptor's `title` used for the outer row's own label. There is no
  direct SwiftUI equivalent of a per-split `detailMinimumThickness`; the
  nearest approximation is a `.frame(minWidth:)` on the inner split's
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
  resize handle — the web analog of `contentSizedSidebar`. Reuse the same
  title string for the outer link and the inner column's heading.
- **AppKit / UIKit** (source platform): Source file
  `SettingsPanelSplitViewController.swift`, AppKit-only, no UIKit
  counterpart in this codebase (`ComposableSettingsWindow/` is entirely
  AppKit). It subclasses `ComposableSettings.SplitViewController`
  (`SplitViewController/SplitViewController.swift`), conforms to
  `ComposableSettingsPanel` (`ComposableSettingsPanel.swift`) through that
  inheritance, and stores a `ComposableSettings.SettingsPanelDescriptor`
  (`SettingsPanelDescriptor.swift`) — all three defined elsewhere in
  `AgenticToolkit` and not reimplemented here.
- **WinUI 3**: Nest one `NavigationView`
  inside another's `Content`. Give the inner `NavigationView`
  `PaneDisplayMode="Left"` and `IsPaneToggleButtonVisible="False"`; its
  built-in pane has no draggable splitter (unlike `SplitView`), which
  matches `contentSizedSidebar == true` without extra work. Bind the inner
  `NavigationView`'s `Header` to the panel's own title — the WinUI analog
  of `sidebarTitle = descriptor.title` — and set the *outer*
  `NavigationViewItem` that hosts this nested view's `Content` from that
  same title string. WinUI has no per-pane analog of
  `NSSplitViewItem.minimumThickness`; approximate
  `detailMinimumThickness`'s `200`pt floor with a fixed `MinWidth="200"` on
  the `Frame`/`ContentPresenter` hosting the inner `NavigationView`'s
  content region, deliberately smaller than the outer shell's own minimum
  width so it constrains only the nested region. For help, forward
  whichever inner `NavigationViewItem` is selected up to the outer shell's
  single help affordance (a `Button` + `Flyout`, or `AutomationProperties.HelpText`)
  and fall back to this nested view's own help text only when the inner
  selection offers none — mirroring `effectiveHelpContent`'s
  `effectiveHelp ?? helpContent` chain.

## Design Decisions

**Decision**: Override `detailMinimumThickness` to `200` points rather than
inheriting `SplitViewController`'s `400`pt default.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.detailMinimumThickness`, "a modest floor
so the nested detail (the sub-panel content) can't be squeezed to a
sliver. It stays below the outer detail's own floor, so it caps the inner
content rather than compounding the window's minimum width."
**Approved**: pending

**Decision**: Override `contentSizedSidebar` to `true` rather than
inheriting `SplitViewController`'s draggable, autosaved default.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.contentSizedSidebar`, "nested topic lists
are content-sized and unified to one width by the parent split, so
switching between sibling panels never shifts the inner divider and every
title stays fully disclosed."
**Approved**: pending

**Decision**: Redeclare `helpContent`, `effectiveHelpContent`, and
`searchKeywords` on this class rather than relying solely on
`ComposableSettingsPanel`'s protocol-extension defaults.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.helpContent` (citing the same reasoning
documented on the sibling `SettingsPanelViewController.helpContent`), a
protocol extension's default is bound at the point of conformance; a
subclass override reachable only through the extension default would be
invisible through the `any ComposableSettingsPanel` existential the
enclosing split holds. Redeclaring the properties on the class keeps
subclass overrides reachable.
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
