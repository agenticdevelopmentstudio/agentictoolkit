<!-- leaf: implement-composable-tabs/settings-view-controller · source: composable-tabs-settings-view-controller.md -->

**Rules** (cite as `implement-composable-tabs/settings-view-controller#<slug>`):

- `constructs-topic-list-from-closures` MUST
- `rejects-coder-initialization` MUST
- `tags-window-background-role` MUST
- `identifies-sheet-root` MUST
- `embeds-topic-list-as-child` MUST
- `pins-panel-to-top-leading-trailing` MUST
- `renders-done-button` MUST
- `binds-return-key-to-done` MUST
- `identifies-done-button` MUST
- `lays-out-done-button-offsets` MUST
- `dismisses-on-done` MUST
- `applies-changes-live` MUST
- `sizes-preferred-content` MUST
- `titles-sidebar-project` MUST
- `widens-detail-pane` MUST
- `fixes-sidebar-width` MUST
- `presents-help-as-popover` MUST
- `registers-two-panels-in-order` MUST
- `rejects-coder-initialization-on-panels` MUST
- `lists-edges-in-reading-order` MUST
- `labels-tabs-descriptor` MUST
- `groups-edge-checkboxes` MUST
- `reflects-initial-edge-state` MUST
- `identifies-edge-checkboxes` MUST
- `themes-checkbox-title-color` MUST
- `commits-edge-toggle` MUST
- `reverts-checkbox-to-authoritative-state` MUST
- `guards-invalid-checkbox-tag` MUST
- `labels-spacing-descriptor` MUST
- `groups-frame-and-divider-controls` MUST
- `binds-frame-spacing-to-settings` MUST
- `binds-divider-spacing-to-settings` MUST
- `closes-tab-loop-between-spacing-controls` MUST

# ComposableTabsSettingsViewController

## Overview

`ComposableTabsSettingsViewController` is a macOS `NSViewController`
(`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsSettingsViewController.swift`)
that presents a project window's own settings as a sheet on its document
window. Per the source's own doc comment, it is deliberately the same shape
as the app's Settings window — a topic list on the left, a panel on the right
— reusing `ComposableSettings.SplitViewController` so that a second topic is a
subclass and an `addPanel` call rather than a second dialog. The file defines
four classes: the public `ComposableTabsSettingsViewController` (the sheet's
outer chrome and Done button), the private `ProjectSettingsSplitViewController`
(the topic list, subclassing `ComposableSettings.SplitViewController`), and two
private `ComposableSettings.SettingsPanelViewController` subclasses —
`ProjectTabsSettingsPanel` (four per-edge tab-bar checkboxes) and
`ProjectSpacingSettingsPanel` (two bound `SpacingControl` instances for frame
and divider spacing). Every change is applied as it is made — there is no
staged state, no commit, and no cancel.

## Behavioral Requirements

- **constructs-topic-list-from-closures**: Component MUST construct its
  topic list during its own initialization, passing through the
  `isEdgeEnabled` and `setEdgeEnabled` closures it was given.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init(coder:)`; that initializer MUST trigger a fatal error if
  invoked.
- **tags-window-background-role**: Component MUST set its root view to a
  `ThemedBackgroundView` constructed with role `.windowBackground`.
- **identifies-sheet-root**: Component MUST set the root view's accessibility
  identifier to `project-window.project-settings`.
- **embeds-topic-list-as-child**: Component MUST add the topic list as a
  child view controller and add its view as a subview of the root view.
- **pins-panel-to-top-leading-trailing**: Component MUST pin the topic list's
  view to the root view's top, leading, and trailing edges, and MUST NOT pin
  it to the root view's bottom edge (the Done button occupies the remaining
  space below it).
- **renders-done-button**: Component MUST render a button titled "Done" with
  `bezelStyle = .rounded` below the topic list.
- **binds-return-key-to-done**: Component MUST set the Done button's
  `keyEquivalent` to the Return character (`"\r"`).
- **identifies-done-button**: Component MUST set the Done button's
  accessibility identifier to `project-window.project-settings.done`.
- **lays-out-done-button-offsets**: Component MUST position the Done button
  12pt below the topic list's bottom edge, 20pt inside the root view's
  trailing edge, and 16pt above the root view's bottom edge.
- **dismisses-on-done**: Component MUST call `dismiss(self)` when the Done
  button's action fires.
- **applies-changes-live**: Component MUST apply every setting change
  immediately as the user makes it, with no separate commit or cancel
  action anywhere in source — every mutation (`setEdgeEnabled`, the bound
  `SpacingControl` writes) takes effect on the underlying state the moment
  it happens.
- **sizes-preferred-content**: Component MUST set `preferredContentSize` to
  760×520 points.
- **titles-sidebar-project**: The topic list MUST set its `sidebarTitle` to
  "Project".
- **widens-detail-pane**: The topic list MUST override
  `detailMinimumThickness` to return 420pt.
- **fixes-sidebar-width**: The topic list MUST override `contentSizedSidebar`
  to return `true`, sizing the sidebar to its content rather than a
  user-draggable width.
- **presents-help-as-popover**: The topic list MUST set its `helpPresenter`
  to a `ComposableSettings.HelpPopoverController` instance rather than a
  drawer-style presenter.
- **registers-two-panels-in-order**: The topic list MUST add the Tabs panel
  before the Spacing panel (`addPanel(tabsPanel)` then
  `addPanel(spacingPanel)`) and MUST select the panel at index 0 (Tabs) once
  both are added.
- **rejects-coder-initialization-on-panels**: The topic list, Tabs panel, and
  Spacing panel MUST NOT support construction via `init(coder:)`; each MUST
  trigger a fatal error if invoked.
- **lists-edges-in-reading-order**: The Tabs panel MUST present the window's
  four edges in the fixed order Top, Right, Bottom, Left.
- **labels-tabs-descriptor**: The Tabs panel MUST construct its descriptor
  with title "Tabs" and the SF Symbol `rectangle.3.group`.
- **groups-edge-checkboxes**: The Tabs panel MUST place all four edge
  checkboxes inside a single `GroupView` titled "Tab Bars".
- **reflects-initial-edge-state**: The Tabs panel MUST initialize each
  checkbox's state from `isEdgeEnabled(edge)`, setting `.on` when it returns
  `true` and `.off` when it returns `false`.
- **identifies-edge-checkboxes**: The Tabs panel MUST set each checkbox's
  accessibility identifier to `project-settings.tabs.` followed by the
  edge's raw value (`top`, `right`, `bottom`, or `left`).
- **themes-checkbox-title-color**: The Tabs panel MUST repaint each
  checkbox's attributed title using the active theme's `.primaryText` color
  and `.body` font whenever the theme changes, via `observeTheme`.
- **commits-edge-toggle**: The Tabs panel MUST call
  `setEdgeEnabled(edge, sender.state == .on)` whenever a checkbox's action
  fires and its tag maps to a valid edge index.
- **reverts-checkbox-to-authoritative-state**: The Tabs panel MUST, in the
  same action handler and immediately after calling `setEdgeEnabled`,
  re-read the toggled checkbox's displayed state from `isEdgeEnabled(edge)`
  and set the checkbox's `state` from that read — not from the click that
  triggered the handler. This is how a refused attempt to disable the
  window's last enabled edge becomes visible on screen: the window's own
  refusal (reported back through `isEdgeEnabled`) overrides the checkbox's
  own state.
- **guards-invalid-checkbox-tag**: The Tabs panel MUST NOT act on a
  checkbox action whose `tag` does not index into the four-edge array; the
  handler MUST return without calling `setEdgeEnabled` in that case.
- **labels-spacing-descriptor**: The Spacing panel MUST construct its
  descriptor with title "Spacing" and the SF Symbol
  `squareshape.split.2x2`.
- **groups-frame-and-divider-controls**: The Spacing panel MUST place the
  frame-spacing control inside a `GroupView` titled "Frame Spacing" and the
  divider-spacing control inside a separate `GroupView` titled "Pane Divider
  Spacing".
- **binds-frame-spacing-to-settings**: The Spacing panel MUST construct its
  frame-spacing control via
  `SpacingControl.boundToSettings(style: .frame, edges: PaneSpacing.edgeSettings)`.
- **binds-divider-spacing-to-settings**: The Spacing panel MUST construct
  its divider-spacing control via
  `SpacingControl.boundToSettings(style: .paneDividers, gutters: PaneSpacing.gutterSettings)`.
- **closes-tab-loop-between-spacing-controls**: The Spacing panel MUST set
  the frame-spacing control's `lastNumberField.nextKeyView` to the
  divider-spacing control's `firstNumberField`, and the divider-spacing
  control's `lastNumberField.nextKeyView` to the frame-spacing control's
  `firstNumberField`, so Tab cycles between the two controls without
  leaving the panel.

