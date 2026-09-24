---
id: 92d66361-a16d-4c35-a0d3-4c1c8bbd5f52
title: ComposableTabsSettingsViewController
domain: agentictoolkit://recipes/composable-tabs-settings-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS project-settings sheet composing SplitViewController with Tabs (per-edge
  toggles) and Spacing (frame/divider) panels; edits apply live.
platforms:
- swift
- macos
tags:
- composable-tabs
- settings
- split-view
- sheet
- macos
depends-on:
- agentictoolkit://recipes/split-view-controller
- agentictoolkit://recipes/group-view
- agentictoolkit://recipes/spacing-control
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

- **Corner radius**: `SettingsLayout.default[.cardCornerRadius]` on every
  group's card, inherited by composing `ComposableSettings.GroupView`'s
  `ThemedBox` — see agentictoolkit://recipes/group-view#appearance for the
  current value. This file sets no corner radius of its own.
- **Padding**: The sheet itself contributes 0pt of padding around the topic
  list (pinned flush to the root view's top/leading/trailing) and fixed
  offsets around the Done button: 12pt above it (from the topic list), 20pt
  to its trailing edge, 16pt below it. Inside each panel,
  `SettingsLayout.default[.panelInset]` = 20pt insets the group stack from
  the panel's top/leading/trailing (bottom is `lessThanOrEqualTo`, so it
  never forces extra height), and
  `SettingsLayout.default[.groupSpacing]` = 20pt separates the Spacing
  panel's two groups (the Tabs panel has only one group, so this spacing is
  never visually exercised there) — both are this file's own panel-level
  settings, not `GroupView`'s. Inside each card,
  `SettingsLayout.default[.cardHorizontalInset]` and
  `SettingsLayout.default[.cardVerticalInset]` pad each row's content, and
  `SettingsLayout.default[.captionSpacing]` separates each group's caption
  from its card — see agentictoolkit://recipes/group-view#appearance for the
  current values, since `GroupView` is what consumes them.
- **Font**: Each group's caption ("Tab Bars", "Frame Spacing", "Pane Divider
  Spacing") renders as a `ThemedLabel` with `textRole: .caption`
  (`ComposableSettings.HeaderView`, which `GroupView` builds internally).
  Each Tabs checkbox's title is forced to `palette.font(.body)` by this
  file's own `observeTheme` closure. The Spacing panel's number/label fonts
  belong to `SpacingControl`'s own implementation, not to this file.
- **Background**: The sheet's root view paints `palette.nsColor(.windowBackground)`
  (`ThemedBackgroundView(role: .windowBackground)`). Each group's card
  paints the theme's `.elevatedSurface` role via a `ThemedBox` inside
  `GroupView` — see agentictoolkit://recipes/group-view#appearance for its
  exact construction. The topic list's own panel body additionally paints
  `palette.windowBackgroundColor` behind the cards (`PanelView`, composed by
  `SettingsPanelViewController`, not set directly by this file).
- **Foreground/Text**: Each Tabs checkbox's title is forced to
  `palette.nsColor(.primaryText)` by this file. Each group's caption
  resolves to the theme's `.secondaryText` role (`HeaderView`'s
  `ThemedLabel(role: .secondaryText, ...)`). The Done button's title uses
  `NSButton`'s own default system label color; this file sets no explicit
  color on it.
- **Border**: Each card's `ThemedBox` has no border stroke of its own, and a
  hairline divider separates a card row from the row above it — both are
  `GroupView`'s construction, not this file's; see
  agentictoolkit://recipes/group-view#appearance for the current values
  (`SettingsLayout.default[.dividerThickness]`, drawn by
  `ThemedSeparatorView(role: .divider)`).
- **Shadow**: Not applicable — no shadow, `NSShadow`, or layer shadow
  property is set anywhere in this file, nor in the `GroupView`/`PanelView`/
  `ThemedBox` types it composes.
- **Min/Max size**: `preferredContentSize` is fixed at 760×520pt; the topic
  list additionally floors the detail pane at 420pt
  (`detailMinimumThickness`). No maximum size is set anywhere in source.

## States

| State | Appearance change |
|-------|------------------|
| Default | Sheet opens with the Tabs panel selected (`selectPanel(at: 0)`); each edge checkbox reflects `isEdgeEnabled(edge)`; Done is enabled. |
| On (edge checkbox) | `checkbox.state == .on`, attributed title drawn in `.primaryText`/`.body`; set on init when `isEdgeEnabled(edge)` is `true`, and after any toggle that `isEdgeEnabled` confirms as enabled. |
| Off (edge checkbox) | `checkbox.state == .off`; set on init when `isEdgeEnabled(edge)` is `false`, and after any toggle — including a refused attempt to disable the last enabled edge, which this file re-reads back to `.on` rather than leaving it `.off` (see **reverts-checkbox-to-authoritative-state**). |
| Pressed | Not applicable: this file sets no custom pressed-state styling; the checkboxes', Done button's, and Spacing controls' click/press feedback is AppKit's own default `NSControl`/`NSButton` rendering. |
| Disabled | Not implemented in source: `isEnabled` is never read or set on any control in this file — the Done button, the four checkboxes, and both `SpacingControl` instances are always interactive whenever the sheet is on screen. |
| Focused | Not styled beyond AppKit's native focus ring, except for the explicit key-view loop this file stitches between the two Spacing controls (**closes-tab-loop-between-spacing-controls**); the Done button and the four checkboxes use AppKit's default key-view-loop placement, which this file does not override. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this file. |

## Accessibility

- **Role/trait**: Not customized beyond the identifiers below — no
  `setAccessibilityRole` call appears anywhere in this file. The four
  checkboxes use `NSButton(checkboxWithTitle:)`'s built-in AppKit checkbox
  role; the Done button uses stock `NSButton` push-button role.
- **Label requirements**: Each checkbox's visible title (`edge.displayName`
  — "Top", "Right", "Bottom", "Left") supplies its accessible name; the Done
  button's visible title ("Done") supplies its accessible name. The
  accessibility identifiers this file sets (`project-window.project-settings`,
  `project-window.project-settings.done`,
  `project-settings.tabs.<edge.rawValue>`, via `accessibilityID`, a wrapper
  over `setAccessibilityIdentifier`) are automation hooks, not accessible
  names, and are invisible to VoiceOver. This file sets no accessibility
  identifier or label on either `SpacingControl` instance or on the topic
  list's sidebar; whatever name each exposes is `SpacingControl`'s and
  `ComposableSettings.SplitViewController`'s own responsibility, outside
  this file.
- **Announce state changes (e.g., loading, disabled)**: NEEDS REVIEW: Not
  implemented in source. Behavior undefined. When a checkbox click is
  refused because it would disable the window's last enabled edge, this
  file changes the checkbox's `state` a second time within the same action
  handler (**reverts-checkbox-to-authoritative-state**), but no
  `NSAccessibility.post(element:notification:)` call, or any other explicit
  accessibility notification, accompanies that correction anywhere in
  source. A sighted user sees the checkbox spring back to checked; nothing
  in this file confirms whether VoiceOver announces the reversal the same
  way, since AppKit does not guarantee a fresh announcement for a
  same-handler state write the way it does for a user-initiated toggle.
  What would settle this: a VoiceOver-attached run of `toggleEdge(_:)` on
  the last enabled edge, checked for whether the corrected value is
  announced.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven composition of `NSButton`/`NSViewController` (no touch
  input path anywhere in this file); the 44×44pt minimum is iOS/touch
  guidance, not a macOS pointer-interface requirement. This file sets no
  `controlSize` on any button, so each keeps AppKit's regular system
  click-target metrics.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| cts-settings-vc-001 | constructs-topic-list-from-closures | Construct with `isEdgeEnabled`/`setEdgeEnabled` closures | A `ProjectSettingsSplitViewController` child exists whose Tabs panel was constructed with the same two closures |
| cts-settings-vc-002 | rejects-coder-initialization | Compile a call site invoking `ComposableTabsSettingsViewController(coder:)` | Compilation fails: `init(coder:)` is unavailable |
| cts-settings-vc-003 | tags-window-background-role | Trigger `loadView()` | `self.view` is a `ThemedBackgroundView` constructed with role `.windowBackground` |
| cts-settings-vc-004 | identifies-sheet-root | Trigger `loadView()` | `self.view.accessibilityIdentifier() == "project-window.project-settings"` |
| cts-settings-vc-005 | embeds-topic-list-as-child | Trigger `loadView()` | `panels` appears in `self.children`, and `panels.view` is a subview of `self.view` |
| cts-settings-vc-006 | pins-panel-to-top-leading-trailing | Trigger `loadView()` | Constraints exist pinning `panels.view`'s top/leading/trailing to the container; no constraint pins its bottom to the container |
| cts-settings-vc-007 | renders-done-button | Trigger `loadView()` | A subview exists titled "Done" with `bezelStyle == .rounded` |
| cts-settings-vc-008 | binds-return-key-to-done | Trigger `loadView()` | The Done button's `keyEquivalent == "\r"` |
| cts-settings-vc-009 | identifies-done-button | Trigger `loadView()` | The Done button's `accessibilityIdentifier() == "project-window.project-settings.done"` |
| cts-settings-vc-010 | lays-out-done-button-offsets | Trigger `loadView()`, resolve constraints | Done button's top is 12pt below `panelsView.bottom`; container's trailing is 20pt beyond Done's trailing; container's bottom is 16pt beyond Done's bottom |
| cts-settings-vc-011 | dismisses-on-done | Click the Done button | `dismiss(self)` is invoked (the sheet closes) |
| cts-settings-vc-012 | applies-changes-live | Toggle an edge checkbox, then inspect a `setEdgeEnabled` spy's call order relative to Done/dismiss | The `setEdgeEnabled` spy was already called at the moment of the toggle, before any Done-button click or `dismiss(self)` call occurs |
| cts-settings-vc-013 | sizes-preferred-content | Trigger `loadView()` | `preferredContentSize == NSSize(width: 760, height: 520)` |
| cts-settings-vc-014 | titles-sidebar-project | Construct the topic list | `sidebarTitle == "Project"` |
| cts-settings-vc-015 | widens-detail-pane | Read the topic list's `detailMinimumThickness` | Returns `420` |
| cts-settings-vc-016 | fixes-sidebar-width | Read the topic list's `contentSizedSidebar` | Returns `true` |
| cts-settings-vc-017 | presents-help-as-popover | Construct the topic list, trigger `viewDidLoad()` | `helpPresenter` is a `ComposableSettings.HelpPopoverController` instance |
| cts-settings-vc-018 | registers-two-panels-in-order | Trigger `viewDidLoad()` on the topic list | Panel at index 0 is the Tabs panel, index 1 is the Spacing panel, and the selected panel is index 0 |
| cts-settings-vc-019 | rejects-coder-initialization-on-panels | Compile a call site invoking `init(coder:)` on the topic list, the Tabs panel, and the Spacing panel | Compilation fails for each: `init(coder:)` is unavailable on all three types |
| cts-settings-vc-020 | lists-edges-in-reading-order | Trigger `viewDidLoad()` on the Tabs panel | Checkboxes appear in the group in the order Top, Right, Bottom, Left |
| cts-settings-vc-021 | labels-tabs-descriptor | Construct the Tabs panel | Its descriptor's `title == "Tabs"`, icon is the `rectangle.3.group` symbol |
| cts-settings-vc-022 | groups-edge-checkboxes | Trigger `viewDidLoad()` on the Tabs panel | All four checkboxes are rows of one `GroupView` titled "Tab Bars"; no second group exists |
| cts-settings-vc-023 | reflects-initial-edge-state | Construct the Tabs panel with `isEdgeEnabled` returning `true` for `.top` and `false` for the rest | Only the Top checkbox's initial `state == .on` |
| cts-settings-vc-024 | identifies-edge-checkboxes | Trigger `viewDidLoad()` on the Tabs panel | The Left checkbox's `accessibilityIdentifier() == "project-settings.tabs.left"` (and correspondingly for the other three edges) |
| cts-settings-vc-025 | themes-checkbox-title-color | Fire a theme change after `viewDidLoad()` | Each checkbox's `attributedTitle` is rebuilt with `.foregroundColor` from `.primaryText` and `.font` from `.body` |
| cts-settings-vc-026 | commits-edge-toggle | Click the Right checkbox to turn it on | `setEdgeEnabled(.right, true)` is called |
| cts-settings-vc-027 | reverts-checkbox-to-authoritative-state | Click the last enabled edge's checkbox to turn it off, with `isEdgeEnabled` continuing to report `true` for that edge after the call | The checkbox's `state` ends the handler as `.on`, not `.off` |
| cts-settings-vc-028 | guards-invalid-checkbox-tag | Invoke `toggleEdge(_:)` with a sender whose `tag == 99` | `setEdgeEnabled` is not called; the handler returns with no effect |
| cts-settings-vc-029 | labels-spacing-descriptor | Construct the Spacing panel | Its descriptor's `title == "Spacing"`, icon is the `squareshape.split.2x2` symbol |
| cts-settings-vc-030 | groups-frame-and-divider-controls | Trigger `viewDidLoad()` on the Spacing panel | Two `GroupView`s exist, titled "Frame Spacing" and "Pane Divider Spacing" respectively, each containing exactly one `SpacingControl` |
| cts-settings-vc-031 | binds-frame-spacing-to-settings | Change `PaneSpacing.edgeSettings[.top]`'s value externally after `viewDidLoad()` | The frame-spacing control's displayed top value updates to match |
| cts-settings-vc-032 | closes-tab-loop-between-spacing-controls | Focus the frame-spacing control's last number field, press Tab | Focus moves to the divider-spacing control's first number field (and Tab from its last field returns focus to the frame-spacing control's first field) |
| cts-settings-vc-033 | binds-divider-spacing-to-settings | Change `PaneSpacing.gutterSettings[.betweenColumns]`'s value externally after `viewDidLoad()` | The divider-spacing control's displayed value updates to match |

## Edge Cases

- Null/empty input: `isEdgeEnabled` and `setEdgeEnabled` are non-optional,
  escaping closure parameters; Swift's type system rules out `nil`. A
  closure that always returns `false` from `isEdgeEnabled` is well-defined
  here: every checkbox initializes `.off`. No string or collection input
  in this file can be empty in a way that changes its behavior. The
  component provides, and needs, no nil-handling path for either closure
  parameter.
- Boundary values: The four checkboxes are two-valued (on/off); there is no
  numeric boundary in the Tabs panel. The Spacing panel's numeric range
  (`0...40`) is the default of `SpacingControl.boundToSettings`'s `range`
  parameter — this file passes no explicit `range:` argument to either
  `boundToSettings` call, so both the frame and divider controls inherit
  `0...40` unmodified. Clamping behavior at 0 or 40 is `SpacingControl`'s
  own responsibility, not decided in this file.
- Concurrent access: All four classes in this file are `@MainActor`, so the
  Swift compiler serializes every construction and mutation to the main
  actor — this file itself has no concurrency hazard. Worth noting, though:
  `PaneSpacing.edgeSettings`/`gutterSettings` are shared, app-wide
  `UserSetting<Int>` instances (per `PaneSpacing`'s own doc comment:
  "App-wide, deliberately... A window whose panes are spaced differently
  from the window beside it reads as a bug"), so opening this sheet on two
  project windows at once and editing spacing in one updates the bound
  control's displayed value in the other, since both bind live to the same
  setting objects.
- Error states: Not applicable — every call in this file (layout,
  `dismiss(self)`, `setEdgeEnabled`, `SpacingControl.boundToSettings`) is
  synchronous and non-throwing; no `try`, `Result`, or completion-with-error
  API appears anywhere in source.
- Offline/disconnected: Not applicable — this file performs no networking;
  every dependency it touches (`UserSetting`, the injected closures, the
  theme palette) is in-process, local state.
- Last-edge-disable refusal: Per **reverts-checkbox-to-authoritative-state**,
  this file has no independent rule of its own that keeps at least one edge
  enabled; it only reflects whatever `isEdgeEnabled` reports after calling
  `setEdgeEnabled`. The actual "refuse to disable the last edge" logic — and
  its persistence — live entirely outside this file, behind the injected
  closures.
- Out-of-range checkbox tag: Per **guards-invalid-checkbox-tag**,
  `toggleEdge(_:)` guards `Self.edges.indices.contains(sender.tag)` before
  indexing; this file's own construction path only ever assigns tags
  `0...3`, so the guard is dead code under normal use, but it is
  source-present, testable behavior: a checkbox retagged to an
  out-of-range value externally (e.g., from test code) causes the action to
  silently no-op rather than trap.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `isEdgeEnabled` | `(Edge) -> Bool` | — (required) | Read once per checkbox at panel construction, and again after every toggle, to decide each checkbox's displayed state. Ownership of the underlying storage is external to this file. |
| `setEdgeEnabled` | `(Edge, Bool) -> Void` | — (required) | Invoked with the toggled edge and the checkbox's clicked value whenever a Tabs checkbox's action fires. |
| `PaneSpacing.edgeSettings[.top/.leading/.bottom/.trailing]` | `UserSetting<Int>` | `0` | App-wide frame-spacing inset per side, bound live to the frame-spacing control; persisted keys `pane_spacing_top`/`pane_spacing_leading`/`pane_spacing_bottom`/`pane_spacing_trailing`. |
| `PaneSpacing.gutterSettings[.betweenColumns/.betweenRows]` | `UserSetting<Int>` | `1` | App-wide pane-divider gutter width, bound live to the divider-spacing control; persisted keys `pane_spacing_between_columns`/`pane_spacing_between_rows`. |

## Deep Linking

Not applicable: `ComposableTabsSettingsViewController` is presented as a
sheet on an existing document window, not a navigable screen with its own
route; no URL scheme, route, or deep-link handler appears anywhere in this
file.

## Localization

NEEDS REVIEW: Not implemented in source. Behavior undefined. Every
user-facing string in this file is a hardcoded English literal with no
`NSLocalizedString` call or String Catalog lookup: the Done button's title
("Done"), the panel titles ("Tabs", "Spacing"), the sidebar title
("Project"), the group titles ("Tab Bars", "Frame Spacing", "Pane Divider
Spacing"), and every help-topic title and body paragraph in both panels'
`helpContent`. Localization plainly applies to a user-facing settings sheet,
and the source has no mechanism to supply a translated string for any of
them. What would settle this: confirmation from the app's localization
owner on whether this sheet is in scope for translation, and if so, a pass
that moves each literal into a String Catalog key.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file; any sheet presentation/dismissal animation is owned by AppKit's own sheet-transition mechanism, outside this file. |
| Increase Contrast | Not applicable: this file sets no custom `NSColor` outside theme-role lookups (`.primaryText`, `.secondaryText`, `.elevatedSurface`, `.windowBackground`, `.divider`); those resolve through the active `SemanticPalette`, which is not overridden here. |
| Differentiate Without Color | Not applicable: each checkbox's on/off state is communicated through `NSButton`'s own check-mark glyph and track position, not through a color-only signal introduced by this file. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this file; the sheet, both panels, and every control in them are always
built once the view controller loads.

## Analytics

Not applicable: this file contains no analytics or telemetry call.

## Privacy

- **Data collected**: None of its own. The component reads and writes local
  application settings only: per-edge tab-bar enablement (via the injected
  closures) and frame/divider spacing integers (via `PaneSpacing`'s
  `UserSetting<Int>` values).
- **Storage**: Frame and divider spacing persist through
  `PaneSpacing.edgeSettings`/`gutterSettings`, backed by `UserSetting<Int>`,
  whose default storage provider is `UserDefaultsSettingsStorageProvider`
  (`UserDefaults.standard`, per `SettingsStore`'s default parameter) — these
  values survive an app restart, live on the local Mac only (not
  iCloud-synced by default), and are shared across every project window, not
  scoped to one project. The storage for tab-bar edge-enabled state is NOT
  decided by this file: it is owned entirely by whatever backs the injected
  `isEdgeEnabled`/`setEdgeEnabled` closures. The Tabs panel's own help text
  states these edges "belong to this project... and are saved with the
  project," implying project-file persistence, but the write path itself is
  outside `ComposableTabsSettingsViewController.swift`.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Spacing settings are retained indefinitely in
  `UserDefaults` until explicitly changed again or the defaults domain is
  reset; this file codes no expiry or automatic clearing. Retention of
  edge-enabled state is likewise outside this file's control.

## Logging

Not applicable: this file contains no logging call (no `print`, `os_log`, or
logger reference anywhere in source).

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
  analog of the app-wide `UserSetting<Int>` persistence). Use
  `.toolbar { ToolbarItem { Button("Done") { dismiss() } } }` with
  `.keyboardShortcut(.defaultAction)` for the Return-bound Done button.
- **Compose**: Use a two-pane `Row` (`NavigationRail` or a simple `Row` with
  a fixed-width sidebar `Column`, matching `contentSizedSidebar`'s
  non-draggable sidebar) with a `Column` of `Checkbox` rows for Tabs and two
  `OutlinedTextField`/stepper groups for Spacing, persisted through
  `DataStore` (the Compose/Android analog of `UserDefaults`-backed
  `UserSetting<Int>`). Re-read the source of truth after each
  `onCheckedChange` call before updating the `Checkbox`'s displayed
  `checked` state, mirroring reverts-checkbox-to-authoritative-state. Use
  `Modifier.focusRequester`/`FocusManager.moveFocus` to stitch the same
  closed Tab loop between the two spacing groups.
- **React/Web**: A two-column layout (`display: grid;
  grid-template-columns: auto 1fr`) with a `<nav>` list of two buttons
  ("Tabs", "Spacing") and a content pane holding four `<input
  type="checkbox">` rows for Tabs and two grouped `<input type="number">` +
  stepper pairs for Spacing, persisted via `localStorage` (the web analog of
  `UserDefaults`). After each checkbox's `onChange`, re-read the
  authoritative value from the store and reset `checked` from it rather
  than trusting the event, mirroring reverts-checkbox-to-authoritative-state.
  Use explicit `tabIndex` values (or DOM order) to close the Tab loop
  between the last field of one spacing group and the first field of the
  other.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsSettingsViewController.swift`.
  A macOS-only (`import AppKit`), `@MainActor` composition of one public
  `NSViewController` and three private classes, all final, none
  `Codable`/`NSCoding`-constructible. The topic list is the private
  `ProjectSettingsSplitViewController` subclass, added as a child view
  controller via `addChild`; it and both panel subclasses mark
  `init(coder:)` `@available(*, unavailable)` to produce the required
  fatal-error trap. It composes `ComposableSettings.SplitViewController`,
  `SettingsPanelViewController`, `GroupView`, `HelpPopoverController`, and
  `SpacingControl` — all defined elsewhere in `AgenticToolkit` — rather than
  reimplementing any of their layout or persistence logic. There is no
  UIKit code path in source; a UIKit port would need an entirely different
  navigation shell, since `NSSplitViewController`'s sidebar/detail model has
  no direct `UISplitViewController` equivalent at this content-sized-sidebar,
  non-draggable configuration.
- **WinUI 3** (the reason this recipe exists): Build the sheet as a
  `ContentDialog` (overriding the `ContentDialogMaxWidth` resource, since
  its default caps a dialog at roughly 548 effective pixels wide — well
  under the 760pt this sheet needs) or, more simply, a secondary `Window`
  sized 760×520 effective pixels, matching `preferredContentSize`, hosting a
  `NavigationView` with
  `PaneDisplayMode="Left"`, `IsPaneOpen="True"`, and `IsSettingsVisible="False"`
  — `NavigationView`'s pane, unlike `SplitView`'s, has no user-draggable
  splitter by default, which is the WinUI analog of `contentSizedSidebar`
  returning `true`. Populate it with two `NavigationViewItem`s ("Tabs",
  icon `Segoe Fluent Icons` glyph for a grid/tab-row shape; "Spacing", a
  layout-grid glyph), selecting the first on load
  (`SelectedItem = navView.MenuItems[0]`) to mirror
  `selectPanel(at: 0)`. The Tabs content is a `StackPanel` of four
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
  of the app-wide `UserDefaults`-backed `UserSetting<Int>` values); give
  each `NumberBox` a `Minimum="0"` and `Maximum="40"` to mirror the
  `0...40` default range. Stitch the same closed Tab loop between the two
  `NumberBox` groups with explicit `TabIndex` values (or
  `XYFocusUp`/`XYFocusDown` on the boundary controls), since `NumberBox`es
  placed in separate `Grid`s otherwise tab in visual, not intended, order.
  Present help from a `Button` with a `Flyout` (WinUI's analog of
  `HelpPopoverController`'s `NSPopover`), since a `ContentDialog` has no
  free window edge for a docked help drawer either.

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
  class's draggable default.
  Rationale: Per the source's own comment, "a sheet has no remembered
  geometry to restore, and a divider the user drags in a transient dialog
  is a setting they never asked to keep."
  Approved: pending
- Decision: Present help through a `HelpPopoverController` instead of the
  base class's drawer-style presenter.
  Rationale: Per the source's own comment, "a sheet has no free edge for a
  drawer to slide out of, so this split presents its help in a popover off
  the help button instead."
  Approved: pending
- Decision: Fix `detailMinimumThickness` at 420pt.
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
  in the app (via `PaneSpacing`'s app-wide `UserSetting<Int>` values).
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
