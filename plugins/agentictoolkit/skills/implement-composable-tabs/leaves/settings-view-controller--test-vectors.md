<!-- leaf: implement-composable-tabs/settings-view-controller--test-vectors · source: composable-tabs-settings-view-controller.md -->

# ComposableTabsSettingsViewController

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
