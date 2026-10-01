---
id: 92d66361-a16d-4c35-a0d3-4c1c8bbd5f52
title: Composable Tabs Settings View
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/settings-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A project-specific settings sheet composing a split view with Tabs (per-edge
  toggles) and Spacing (frame/divider) panels; edits apply live.
platforms:
- swift
- macos
tags:
- composable-tabs
- settings
- split-view
- sheet
depends-on:
- agentictoolkit://cookbook/ui/settings/settings-split-view
- agentictoolkit://cookbook/ui/settings/layout/group-view
- agentictoolkit://cookbook/ui/controls/spacing-control
related: []
references: []
approved-by: ''
approved-date: ''
---

# Composable Tabs Settings View

## Overview

The settings view presents a project's own settings as a sheet on its parent
window. It is deliberately the same shape as the app's global settings
surface — a topic list on one side, a panel on the other — so that a second
topic is simply another panel added to the list rather than a second dialog.
The view is composed of four parts: the outer sheet chrome (the outer
container and its Done button), the topic list (a split view showing
available topics), and two settings panels — a Tabs panel (four per-edge
tab-bar toggles) and a Spacing panel (two bound spacing controls for frame
and divider spacing). Every change is applied as it is made — there is no
staged state, no commit, and no cancel.

## Behavioral Requirements

- **constructs-topic-list-from-closures**: Component MUST construct its
  topic list during its own initialization, passing through the
  `isEdgeEnabled` and `setEdgeEnabled` closures it was given.
- **tags-window-background-role**: Component MUST set its root view's
  background to the `.windowBackground` theme role.
- **identifies-sheet-root**: Component MUST set the root view's accessibility
  identifier to `project-window.project-settings`.
- **embeds-topic-list-as-child**: Component MUST add the topic list as a
  child element of the root view and MUST make its view a subview of the
  root view.
- **pins-panel-to-top-leading-trailing**: Component MUST pin the topic list's
  view to the root view's top, leading, and trailing edges, and MUST NOT pin
  it to the root view's bottom edge (the Done button occupies the remaining
  space below it).
- **renders-done-button**: Component MUST render a rounded-style button
  titled "Done" below the topic list.
- **binds-return-key-to-done**: Component MUST bind the Done button's
  activation shortcut to the Return key.
- **identifies-done-button**: Component MUST set the Done button's
  accessibility identifier to `project-window.project-settings.done`.
- **lays-out-done-button-offsets**: Component MUST position the Done button
  12pt below the topic list's bottom edge, 20pt inside the root view's
  trailing edge, and 16pt above the root view's bottom edge.
- **dismisses-on-done**: Component MUST dismiss the sheet when the Done
  button's action fires.
- **applies-changes-live**: Component MUST apply every setting change
  immediately as the user makes it, with no separate commit or cancel
  action anywhere in the component — every mutation (`setEdgeEnabled`, the
  bound spacing-control writes) takes effect on the underlying state the
  moment it happens.
- **sizes-preferred-content**: Component MUST size its preferred content area
  to 760×520 points.
- **titles-sidebar-project**: The topic list MUST title its sidebar
  "Project".
- **widens-detail-pane**: The topic list MUST enforce a minimum detail-pane
  width of 420pt.
- **fixes-sidebar-width**: The topic list MUST size its sidebar to its
  content rather than a user-draggable width.
- **presents-help-as-popover**: The topic list MUST present its help content
  in a popover rather than a drawer-style presentation.
- **registers-two-panels-in-order**: The topic list MUST register the Tabs
  panel before the Spacing panel and MUST select the Tabs panel once both
  are registered.
- **lists-edges-in-reading-order**: The Tabs panel MUST present the window's
  four edges in the fixed order Top, Right, Bottom, Left.
- **labels-tabs-descriptor**: The Tabs panel MUST label itself with the
  title "Tabs" and an icon representing a grid of tab bars.
- **groups-edge-checkboxes**: The Tabs panel MUST place all four edge
  toggles inside a single group titled "Tab Bars".
- **reflects-initial-edge-state**: The Tabs panel MUST initialize each
  toggle's state from `isEdgeEnabled(edge)`, setting it on when it returns
  `true` and off when it returns `false`.
- **identifies-edge-checkboxes**: The Tabs panel MUST set each toggle's
  accessibility identifier to `project-settings.tabs.` followed by the
  edge's raw value (`top`, `right`, `bottom`, or `left`).
- **themes-checkbox-title-color**: The Tabs panel MUST repaint each toggle's
  title using the active theme's primary-text color and body text style
  whenever the theme changes.
- **commits-edge-toggle**: The Tabs panel MUST call
  `setEdgeEnabled(edge, isOn)` whenever a toggle's action fires with a
  value mapping to a valid edge.
- **reverts-checkbox-to-authoritative-state**: The Tabs panel MUST, in the
  same action handler and immediately after calling `setEdgeEnabled`,
  re-read the toggled control's displayed state from `isEdgeEnabled(edge)`
  and set the control's state from that read — not from the click that
  triggered the handler. This is how a refused attempt to disable the
  window's last enabled edge becomes visible on screen: the window's own
  refusal (reported back through `isEdgeEnabled`) overrides the toggle's
  own state.
- **guards-invalid-checkbox-tag**: The Tabs panel MUST NOT act on a toggle
  action whose index does not map to one of the four edges; the handler
  MUST return without calling `setEdgeEnabled` in that case.
- **labels-spacing-descriptor**: The Spacing panel MUST label itself with
  the title "Spacing" and an icon representing a 2×2 grid of panes.
- **groups-frame-and-divider-controls**: The Spacing panel MUST place the
  frame-spacing control inside a group titled "Frame Spacing" and the
  divider-spacing control inside a separate group titled "Pane Divider
  Spacing".
- **binds-frame-spacing-to-settings**: The Spacing panel MUST construct its
  frame-spacing control bound live to the app-wide frame-spacing settings
  for every edge.
- **binds-divider-spacing-to-settings**: The Spacing panel MUST construct
  its divider-spacing control bound live to the app-wide pane-divider
  gutter settings.
- **closes-tab-loop-between-spacing-controls**: The Spacing panel MUST link
  keyboard focus so tabbing forward from the frame-spacing control's last
  field moves to the divider-spacing control's first field, and tabbing
  forward from the divider-spacing control's last field returns to the
  frame-spacing control's first field, so Tab cycles between the two
  controls without leaving the panel.

## Appearance

- **Corner radius**: The shared settings layout's card-corner-radius token,
  inherited by composing the group component's themed card — see
  agentictoolkit://cookbook/ui/settings/layout/group-view#appearance for the
  current value. This file sets no corner radius of its own.
- **Padding**: The sheet itself contributes 0pt of padding around the topic
  list (pinned flush to the root view's top/leading/trailing) and fixed
  offsets around the Done button: 12pt above it (from the topic list), 20pt
  to its trailing edge, 16pt below it. Inside each panel, the shared
  settings layout's panel-inset token (20pt) insets the group stack from
  the panel's top/leading/trailing (bottom is a "no more than" constraint,
  so it never forces extra height), and the shared settings layout's
  group-spacing token (20pt) separates the Spacing panel's two groups (the
  Tabs panel has only one group, so this spacing is never visually
  exercised there) — both are this component's own panel-level settings,
  not the group component's. Inside each card, the shared layout's
  card-horizontal-inset and card-vertical-inset tokens pad each row's
  content, and its caption-spacing token separates each group's caption
  from its card — see
  agentictoolkit://cookbook/ui/settings/layout/group-view#appearance for the
  current values, since the group component is what consumes them.
- **Font**: Each group's caption ("Tab Bars", "Frame Spacing", "Pane Divider
  Spacing") renders with a caption text role (the group component's own
  header, built internally). Each Tabs toggle's title is forced to the
  body text style by this component's own theme-observing logic. The
  Spacing panel's number/label fonts belong to the spacing control's own
  implementation, not to this component.
- **Background**: The sheet's root view paints the `.windowBackground`
  theme role. Each group's card paints the theme's `.elevatedSurface` role
  — see agentictoolkit://cookbook/ui/settings/layout/group-view#appearance
  for its exact construction. The topic list's own panel body additionally
  paints the window-background color behind the cards (composed by the
  panel component, not set directly by this component).
- **Foreground/Text**: Each Tabs toggle's title is forced to the
  `.primaryText` theme role by this component. Each group's caption
  resolves to the theme's `.secondaryText` role (the group header's own
  label). The Done button's title uses the platform's default system
  label color; this component sets no explicit color on it.
- **Border**: Each card has no border stroke of its own, and a hairline
  divider separates a card row from the row above it — both are the group
  component's construction, not this component's; see
  agentictoolkit://cookbook/ui/settings/layout/group-view#appearance for the
  current values (the shared layout's divider-thickness token, drawn as a
  themed divider).
- **Shadow**: Not applicable — no shadow property is set anywhere in this
  component, nor in the group/panel/card components it composes.
- **Min/Max size**: The preferred content area is fixed at 760×520pt; the
  topic list additionally floors the detail pane at 420pt. No maximum size
  is set anywhere in the component.

## States

| State | Appearance change |
|-------|------------------|
| Default | Sheet opens with the Tabs panel selected; each edge toggle reflects `isEdgeEnabled(edge)`; Done is enabled. |
| On (edge toggle) | Toggle is on, title drawn in the primary-text color and body text style; set on init when `isEdgeEnabled(edge)` is `true`, and after any toggle that `isEdgeEnabled` confirms as enabled. |
| Off (edge toggle) | Toggle is off; set on init when `isEdgeEnabled(edge)` is `false`, and after any toggle — including a refused attempt to disable the last enabled edge, which this component re-reads back to on rather than leaving it off (see **reverts-checkbox-to-authoritative-state**). |
| Pressed | Not applicable: this component sets no custom pressed-state styling; the toggles', Done button's, and Spacing controls' click/press feedback is the platform's own default control rendering. |
| Disabled | Not implemented in the component: enablement is never read or set on any control here — the Done button, the four toggles, and both spacing controls are always interactive whenever the sheet is on screen. |
| Focused | Not styled beyond the platform's native focus indication, except for the explicit focus loop this component stitches between the two Spacing controls (**closes-tab-loop-between-spacing-controls**); the Done button and the four toggles use the platform's default focus-order placement, which this component does not override. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this component. |

## Accessibility

- **Role/trait**: Not customized beyond the identifiers below — no explicit
  accessibility role assignment appears anywhere in this component. The
  four toggles use the platform's built-in checkbox role; the Done button
  uses a standard push-button role.
- **Label requirements**: Each toggle's visible title (the edge's display
  name — "Top", "Right", "Bottom", "Left") supplies its accessible name; the
  Done button's visible title ("Done") supplies its accessible name. The
  accessibility identifiers this component sets
  (`project-window.project-settings`,
  `project-window.project-settings.done`,
  `project-settings.tabs.<edge>`) are automation hooks, not accessible
  names, and are invisible to assistive technology's spoken output. This
  component sets no accessibility identifier or label on either spacing
  control or on the topic list's sidebar; whatever name each exposes is the
  spacing control's and the topic list's own responsibility, outside this
  component.
- **Announce state changes (e.g., loading, disabled)**: Not implemented in
  the component. When a toggle click is refused because it would disable
  the window's last enabled edge, this component changes the toggle's
  state a second time within the same action handler
  (**reverts-checkbox-to-authoritative-state**), but no explicit
  accessibility notification accompanies that correction anywhere in the
  component. A sighted user sees the toggle spring back to checked; this
  component itself emits no notification of the reversal to assistive
  technology, relying entirely on whatever announcement the platform's own
  automatic accessibility observation of the state change produces, if
  any.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition (no touch input path anywhere in this component); the
  44×44pt minimum is touch-platform guidance, not a pointer-interface
  requirement. This component sets no explicit control size on any button,
  so each keeps the platform's regular system click-target metrics.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| cts-settings-vc-001 | constructs-topic-list-from-closures | Construct with `isEdgeEnabled`/`setEdgeEnabled` closures | A topic-list child exists whose Tabs panel was constructed with the same two closures |
| cts-settings-vc-003 | tags-window-background-role | Load the component | The root view's background is the `.windowBackground` theme role |
| cts-settings-vc-004 | identifies-sheet-root | Load the component | The root view's accessibility identifier equals `"project-window.project-settings"` |
| cts-settings-vc-005 | embeds-topic-list-as-child | Load the component | The topic list appears among the component's child elements, and its view is a subview of the root view |
| cts-settings-vc-006 | pins-panel-to-top-leading-trailing | Load the component | Constraints exist pinning the topic list's view top/leading/trailing to the container; no constraint pins its bottom to the container |
| cts-settings-vc-007 | renders-done-button | Load the component | A subview exists titled "Done" with a rounded appearance |
| cts-settings-vc-008 | binds-return-key-to-done | Load the component | The Done button's activation shortcut is the Return key |
| cts-settings-vc-009 | identifies-done-button | Load the component | The Done button's accessibility identifier equals `"project-window.project-settings.done"` |
| cts-settings-vc-010 | lays-out-done-button-offsets | Load the component, resolve constraints | Done button's top is 12pt below the topic list's bottom; container's trailing is 20pt beyond Done's trailing; container's bottom is 16pt beyond Done's bottom |
| cts-settings-vc-011 | dismisses-on-done | Click the Done button | The sheet is dismissed (the sheet closes) |
| cts-settings-vc-012 | applies-changes-live | Toggle an edge, then inspect a `setEdgeEnabled` spy's call order relative to Done/dismiss | The `setEdgeEnabled` spy was already called at the moment of the toggle, before any Done-button click or dismissal occurs |
| cts-settings-vc-013 | sizes-preferred-content | Load the component | The preferred content area is 760×520pt |
| cts-settings-vc-014 | titles-sidebar-project | Construct the topic list | Its sidebar title equals "Project" |
| cts-settings-vc-015 | widens-detail-pane | Read the topic list's detail-pane minimum width | Returns `420` |
| cts-settings-vc-016 | fixes-sidebar-width | Read the topic list's content-sized-sidebar setting | Returns `true` |
| cts-settings-vc-017 | presents-help-as-popover | Construct the topic list, load its view | Help is presented through a popover-style presenter |
| cts-settings-vc-018 | registers-two-panels-in-order | Load the topic list | Panel at index 0 is the Tabs panel, index 1 is the Spacing panel, and the selected panel is index 0 |
| cts-settings-vc-020 | lists-edges-in-reading-order | Load the Tabs panel | Toggles appear in the group in the order Top, Right, Bottom, Left |
| cts-settings-vc-021 | labels-tabs-descriptor | Construct the Tabs panel | Its descriptor's title equals "Tabs", with an icon representing a grid of tab bars |
| cts-settings-vc-022 | groups-edge-checkboxes | Load the Tabs panel | All four toggles are rows of one group titled "Tab Bars"; no second group exists |
| cts-settings-vc-023 | reflects-initial-edge-state | Construct the Tabs panel with `isEdgeEnabled` returning `true` for `.top` and `false` for the rest | Only the Top toggle's initial state is on |
| cts-settings-vc-024 | identifies-edge-checkboxes | Load the Tabs panel | The Left toggle's accessibility identifier equals `"project-settings.tabs.left"` (and correspondingly for the other three edges) |
| cts-settings-vc-025 | themes-checkbox-title-color | Fire a theme change after loading | Each toggle's title is rebuilt with the primary-text color and body text style |
| cts-settings-vc-026 | commits-edge-toggle | Click the Right toggle to turn it on | `setEdgeEnabled(.right, true)` is called |
| cts-settings-vc-027 | reverts-checkbox-to-authoritative-state | Click the last enabled edge's toggle to turn it off, with `isEdgeEnabled` continuing to report `true` for that edge after the call | The toggle's state ends the handler on, not off |
| cts-settings-vc-028 | guards-invalid-checkbox-tag | Invoke the toggle handler with a sender whose index maps to no edge | `setEdgeEnabled` is not called; the handler returns with no effect |
| cts-settings-vc-029 | labels-spacing-descriptor | Construct the Spacing panel | Its descriptor's title equals "Spacing", with an icon representing a 2×2 grid of panes |
| cts-settings-vc-030 | groups-frame-and-divider-controls | Load the Spacing panel | Two groups exist, titled "Frame Spacing" and "Pane Divider Spacing" respectively, each containing exactly one spacing control |
| cts-settings-vc-031 | binds-frame-spacing-to-settings | Change the top frame-spacing setting externally after loading | The frame-spacing control's displayed top value updates to match |
| cts-settings-vc-032 | closes-tab-loop-between-spacing-controls | Focus the frame-spacing control's last number field, press Tab | Focus moves to the divider-spacing control's first number field (and Tab from its last field returns focus to the frame-spacing control's first field) |
| cts-settings-vc-033 | binds-divider-spacing-to-settings | Change the between-columns gutter setting externally after loading | The divider-spacing control's displayed value updates to match |

## Edge Cases

- Null/empty input: `isEdgeEnabled` and `setEdgeEnabled` are non-optional,
  escaping closure parameters; the type system rules out an absent value. A
  closure that always returns `false` from `isEdgeEnabled` is well-defined
  here: every toggle initializes off. No string or collection input in
  this component can be empty in a way that changes its behavior. The
  component provides, and needs, no nil-handling path for either closure
  parameter.
- Boundary values: The four toggles are two-valued (on/off); there is no
  numeric boundary in the Tabs panel. The Spacing panel's numeric range
  (`0...40`) is the default of the spacing control's binding — this
  component passes no explicit range to either binding, so both the frame
  and divider controls inherit `0...40` unmodified. Clamping behavior at 0
  or 40 is the spacing control's own responsibility, not decided in this
  component.
- Concurrent access: Every construction and mutation in this component is
  confined to a single thread, so this component itself has no concurrency
  hazard. Worth noting, though: the frame-spacing and gutter-spacing
  settings are shared, app-wide settings ("App-wide, deliberately... A
  window whose panes are spaced differently from the window beside it
  reads as a bug"), so opening this sheet on two project windows at once
  and editing spacing in one updates the bound control's displayed value
  in the other, since both bind live to the same settings.
- Error states: Not applicable — every call in this component (layout,
  dismissal, `setEdgeEnabled`, the spacing bindings) is synchronous and
  non-throwing; no failure-signaling API appears anywhere in the
  component.
- Offline/disconnected: Not applicable — this component performs no
  networking; every dependency it touches (settings, the injected
  closures, the theme palette) is in-process, local state.
- Last-edge-disable refusal: Per **reverts-checkbox-to-authoritative-state**,
  this component has no independent rule of its own that keeps at least
  one edge enabled; it only reflects whatever `isEdgeEnabled` reports after
  calling `setEdgeEnabled`. The actual "refuse to disable the last edge"
  logic — and its persistence — live entirely outside this component,
  behind the injected closures.
- Out-of-range toggle index: Per **guards-invalid-checkbox-tag**, the toggle
  handler guards the index against the valid edge range before indexing;
  this component's own construction path only ever assigns indices
  `0...3`, so the guard is dead code under normal use, but it is
  source-present, testable behavior: a toggle retagged to an out-of-range
  value externally (e.g., from test code) causes the action to silently
  no-op rather than trap.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `isEdgeEnabled` | Function: edge → Boolean | — (required) | Read once per toggle at panel construction, and again after every toggle, to decide each toggle's displayed state. Ownership of the underlying storage is external to this component. |
| `setEdgeEnabled` | Function: (edge, Boolean) → void | — (required) | Invoked with the toggled edge and the toggle's clicked value whenever a Tabs toggle's action fires. |
| Frame-spacing settings (top/leading/bottom/trailing) | Integer | `0` | App-wide frame-spacing inset per side, bound live to the frame-spacing control; persisted keys `pane_spacing_top`/`pane_spacing_leading`/`pane_spacing_bottom`/`pane_spacing_trailing`. |
| Gutter-spacing settings (between columns/rows) | Integer | `1` | App-wide pane-divider gutter width, bound live to the divider-spacing control; persisted keys `pane_spacing_between_columns`/`pane_spacing_between_rows`. |

## Deep Linking

Not applicable: the settings view is presented as a sheet on an existing
document window, not a navigable screen with its own route; no URL scheme,
route, or deep-link handler appears anywhere in this component.

## Localization

Every user-facing string in this component is a hardcoded English literal
with no localization lookup: the Done button's title ("Done"), the panel
titles ("Tabs", "Spacing"), the sidebar title ("Project"), the group titles
("Tab Bars", "Frame Spacing", "Pane Divider Spacing"), and every help-topic
title and body paragraph in both panels' help content. This component has
no mechanism to supply a translated string for any of them.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition appears anywhere in this component; any sheet presentation/dismissal animation is owned by the platform's own sheet-transition mechanism, outside this component. |
| Increase Contrast | Not applicable: this component sets no custom color outside theme-role lookups (`.primaryText`, `.secondaryText`, `.elevatedSurface`, `.windowBackground`, `.divider`); those resolve through the active theme palette, which is not overridden here. |
| Differentiate Without Color | Not applicable: each toggle's on/off state is communicated through the platform's own check-mark glyph and track position, not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component; the sheet, both panels, and every control in them are
always built once the component loads.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None of its own. The component reads and writes local
  application settings only: per-edge tab-bar enablement (via the injected
  closures) and frame/divider spacing integers (via the app-wide spacing
  settings).
- **Storage**: Frame and divider spacing persist through the app-wide
  frame- and gutter-spacing settings, whose default storage survives an app
  restart, lives on the local device only (not synced by default), and is
  shared across every project window, not scoped to one project. The
  storage for tab-bar edge-enabled state is NOT decided by this component:
  it is owned entirely by whatever backs the injected
  `isEdgeEnabled`/`setEdgeEnabled` closures. The Tabs panel's own help text
  states these edges "belong to this project... and are saved with the
  project," implying project-file persistence, but the write path itself is
  outside this component.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this component.
- **Retention**: Spacing settings are retained indefinitely until explicitly
  changed again or the settings store is reset; this component codes no
  expiry or automatic clearing. Retention of edge-enabled state is likewise
  outside this component's control.

## Logging

Not applicable: this component contains no logging call.

## Platform Notes

- **SwiftUI**: Rebuild the sheet as a `NavigationSplitView` (sidebar +
  detail) inside a `.sheet`, with a `List` of two `NavigationLink`-backed
  rows ("Tabs", "Spacing") in the sidebar. The Tabs panel becomes a
  `VStack` of four `Toggle` rows bound to a view model wrapping
  `isEdgeEnabled`/`setEdgeEnabled`; re-read the authoritative value from the
  view model inside the `Toggle`'s binding setter, after calling
  `setEdgeEnabled`, to mirror reverts-checkbox-to-authoritative-state (a
  plain `Binding` would otherwise trust the tap). The Spacing panel becomes
  two grouped `Stepper`/`TextField` pairs bound to `AppStorage` (SwiftUI's
  analog of the app-wide integer settings). Use
  `.toolbar { ToolbarItem { Button("Done") { dismiss() } } }` with
  `.keyboardShortcut(.defaultAction)` for the Return-bound Done button.
- **Compose**: Use a two-pane `Row` (`NavigationRail` or a simple `Row` with
  a fixed-width sidebar `Column`, matching the non-draggable sidebar) with a
  `Column` of `Checkbox` rows for Tabs and two `OutlinedTextField`/stepper
  groups for Spacing, persisted through `DataStore` (the Compose/Android
  analog of the app-wide integer settings). Re-read the source of truth
  after each `onCheckedChange` call before updating the `Checkbox`'s
  displayed `checked` state, mirroring reverts-checkbox-to-authoritative-state.
  Use `Modifier.focusRequester`/`FocusManager.moveFocus` to stitch the same
  closed Tab loop between the two spacing groups.
- **React/Web**: A two-column layout (`display: grid;
  grid-template-columns: auto 1fr`) with a `<nav>` list of two buttons
  ("Tabs", "Spacing") and a content pane holding four `<input
  type="checkbox">` rows for Tabs and two grouped `<input type="number">` +
  stepper pairs for Spacing, persisted via `localStorage` (the web analog of
  the app-wide integer settings). After each toggle's `onChange`, re-read
  the authoritative value from the store and reset `checked` from it rather
  than trusting the event, mirroring reverts-checkbox-to-authoritative-state.
  Use explicit `tabIndex` values (or DOM order) to close the Tab loop
  between the last field of one spacing group and the first field of the
  other.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsSettingsViewController.swift`.
  A macOS-only (`import AppKit`), `@MainActor` composition of one public
  `NSViewController` (`ComposableTabsSettingsViewController`) and three
  private classes: the topic list is the private
  `ProjectSettingsSplitViewController`, subclassing
  `ComposableSettings.SplitViewController` and added as a child view
  controller via `addChild`; the Tabs and Spacing panels are private
  `ComposableSettings.SettingsPanelViewController` subclasses
  (`ProjectTabsSettingsPanel`, `ProjectSpacingSettingsPanel`). All four
  classes are `final`, and all four mark `init(coder:)`
  `@available(*, unavailable)` to produce a fatal-error trap if invoked
  (`rejects-coder-initialization`/`rejects-coder-initialization-on-panels`
  in prior revisions of this recipe; this is a construction-time
  compiler/runtime rule of the platform, not an independently testable
  behavior of the component). The Done button is rendered with
  `bezelStyle = .rounded`; its activation shortcut is set via
  `keyEquivalent = "\r"`. This component composes
  `ComposableSettings.SplitViewController`, `SettingsPanelViewController`,
  `GroupView`, `HelpPopoverController`, and `SpacingControl` — all defined
  elsewhere in `AgenticToolkit` — rather than reimplementing any of their
  layout or persistence logic. The Tabs panel's icon is the SF Symbol
  `rectangle.3.group`; the Spacing panel's icon is `squareshape.split.2x2`.
  The frame-spacing control is constructed via
  `SpacingControl.boundToSettings(style: .frame, edges: PaneSpacing.edgeSettings)`,
  and the divider-spacing control via
  `SpacingControl.boundToSettings(style: .paneDividers, gutters: PaneSpacing.gutterSettings)`.
  The closed Tab loop is wired via `nextKeyView`. There is no UIKit code
  path in source; a UIKit port would need an entirely different navigation
  shell, since `NSSplitViewController`'s sidebar/detail model has no direct
  `UISplitViewController` equivalent at this content-sized-sidebar,
  non-draggable configuration.
- **WinUI 3** (the reason this recipe exists): Build the sheet as a
  `ContentDialog` (overriding the `ContentDialogMaxWidth` resource, since
  its default caps a dialog at roughly 548 effective pixels wide — well
  under the 760pt this sheet needs) or, more simply, a secondary `Window`
  sized 760×520 effective pixels, matching the preferred content size,
  hosting a `NavigationView` with
  `PaneDisplayMode="Left"`, `IsPaneOpen="True"`, and `IsSettingsVisible="False"`
  — `NavigationView`'s pane, unlike `SplitView`'s, has no user-draggable
  splitter by default, which is the WinUI analog of the fixed sidebar
  width. Populate it with two `NavigationViewItem`s ("Tabs",
  icon `Segoe Fluent Icons` glyph for a grid/tab-row shape; "Spacing", a
  layout-grid glyph), selecting the first on load
  (`SelectedItem = navView.MenuItems[0]`) to mirror selecting the Tabs
  panel by default. The Tabs content is a `StackPanel` of four
  `CheckBox` controls (`Content="Top"`, `"Right"`, `"Bottom"`, `"Left"`)
  whose `Checked`/`Unchecked` handlers call the injected setter and then
  explicitly set `IsChecked` back from the injected getter's current value
  — WinUI's two-way `x:Bind` would otherwise leave the box showing whatever
  the user clicked, so the handler-level re-read is required to reproduce
  reverts-checkbox-to-authoritative-state. Guard that re-read (a boolean
  flag, or comparing against the value already set) before writing
  `IsChecked`, since setting it from inside the `Checked`/`Unchecked`
  handler re-fires that same handler; alternatively, handle `Click` instead
  of `Checked`/`Unchecked` to sidestep the re-entrancy entirely. Set
  `AutomationProperties.Name` on each `CheckBox` from its content text
  (the WinUI analog of the visible label supplying the accessible name),
  and additionally mark the `CheckBox` with
  `AutomationProperties.LiveSetting="Assertive"` (or raise a
  `FrameworkElementAutomationPeer` structure-changed event) when the
  handler corrects a refused uncheck — UI Automation does not re-announce a
  value the app itself just wrote back, which is the same gap this recipe
  flags in Accessibility. The Spacing content is two `Grid`s, each with a
  `NumberBox` (built-in spin buttons, `SpinButtonPlacementMode="Inline"`)
  per side/gutter, bound `Value="{x:Bind ..., Mode=TwoWay}"` to properties
  backed by `ApplicationData.Current.LocalSettings` (the WinUI/UWP analog
  of the app-wide integer settings); give each `NumberBox` a `Minimum="0"`
  and `Maximum="40"` to mirror the `0...40` default range. Stitch the same
  closed Tab loop between the two `NumberBox` groups with explicit
  `TabIndex` values (or `XYFocusUp`/`XYFocusDown` on the boundary
  controls), since `NumberBox`es placed in separate `Grid`s otherwise tab
  in visual, not intended, order. Present help from a `Button` with a
  `Flyout` (WinUI's analog of the popover-based help presenter), since a
  `ContentDialog` has no free window edge for a docked help drawer either.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsSettingsViewController.swift` |

## Design Decisions

- Decision: Apply every setting change immediately, with no commit or
  cancel action anywhere in the sheet.
  Rationale: Per the source's own comment, "the edges toggle live behind
  the sheet — so there is nothing to commit and nothing to cancel"; the
  Done button only dismisses the sheet, it does not persist anything that
  was not already persisted.
  Approved: pending
- Decision: Re-read each checkbox's displayed state from `isEdgeEnabled`
  immediately after calling `setEdgeEnabled`, rather than trusting the
  click that triggered the handler.
  Rationale: Per the source's own comment, "the window refuses to turn off
  its last tab bar, so the checkbox is re-read rather than left showing a
  state the window does not have" — this file has no rule of its own about
  a minimum number of enabled edges; it only ever reflects what the
  injected closure reports.
  Approved: pending
- Decision: Override `contentSizedSidebar` to `true` instead of the base
  class's draggable default. (AppKit/UIKit.)
  Rationale: Per the source's own comment, "a sheet has no remembered
  geometry to restore, and a divider the user drags in a transient dialog
  is a setting they never asked to keep."
  Approved: pending
- Decision: Present help through a `HelpPopoverController` instead of the
  base class's drawer-style presenter. (AppKit/UIKit.)
  Rationale: Per the source's own comment, "a sheet has no free edge for a
  drawer to slide out of, so this split presents its help in a popover off
  the help button instead."
  Approved: pending
- Decision: Fix `detailMinimumThickness` at 420pt. (AppKit/UIKit.)
  Rationale: Per the source's own comment, this is "wide enough for the
  Spacing panel's diagram, which is the widest thing either topic puts in
  the detail pane" — the value is driven by the Spacing panel's content,
  not the Tabs panel's.
  Approved: pending
- Decision: Close the Tab key-view loop between the frame-spacing and
  divider-spacing controls onto themselves, rather than letting it trail
  into the Done button or the sidebar.
  Rationale: Per the source's own comment, the controls are "placed by
  frame, so left to itself Tab out of the bottom number went somewhere
  that looked like nowhere," and "the sheet holds nothing else to type in,
  so the loop closes on itself rather than trailing off into the sheet's
  buttons." The comment also notes this mirrors the key-view loop of "the
  Projects settings panel," so the same pair of controls owes the user a
  consistent Tab order wherever it appears.
  Approved: pending
- Decision: Scope tab-bar edge enablement to the current project (via the
  injected closures) while scoping frame/divider spacing to every window
  in the app (via the app-wide spacing settings).
  Rationale: Both panels' own help text states this split explicitly — the
  Tabs panel's: "these edges belong to this project, not to the app...
  Spacing... is the opposite: it belongs to every window"; the Spacing
  panel's: "Spacing belongs to the app, not to this project — every
  project window is spaced the same way." The two panels deliberately use
  two different persistence scopes side by side in the same sheet.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

`keyboard-navigable` and `screen-reader-support` are `partial` because the
Done button and the four checkboxes rely on AppKit's default key-view loop
and default accessibility roles, which this file never overrides or
verifies (see **Accessibility**); `string-externalization` is `failed`
because every user-facing string in this file is a hardcoded English
literal (see **Localization**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: populated depends-on with composed ingredients (split-view-controller, group-view, spacing-control); trimmed tags to five; decoupled three requirements from private implementation details (moved to Platform Notes); replaced restated GroupView metrics in Appearance with citations to its recipe; downgraded keyboard-navigable and screen-reader-support to partial and added a failed string-externalization check, with a sentence explaining both; renamed the AppKit platform-notes bullet to AppKit / UIKit; tightened three conformance test vectors (coder-init traps as compile-time checks, applies-changes-live as call-order assertion) and split/added divider-binding vectors; expanded WinUI 3 notes for ContentDialog width and checkbox re-entrancy; removed descriptive MUST usage from Edge Cases. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
