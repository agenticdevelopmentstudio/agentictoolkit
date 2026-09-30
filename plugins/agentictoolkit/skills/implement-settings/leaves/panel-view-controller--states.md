<!-- leaf: implement-settings/panel-view-controller--states · source: settings-panel-view-controller.md -->

# SettingsPanelViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: `SettingsPanelViewController` is a container view controller, not a control; it registers no target/action and applies no pressed-state styling anywhere in source. |
| Disabled | Not applicable to this file's own view. `descriptor.isDisabled` is declared on `SettingsPanelDescriptor` and is read only by the sidebar row list (`PanelListViewController.buildSections`, a different file) to disable that row; `SettingsPanelViewController.swift` never reads `descriptor.isDisabled` and applies no disabled styling to `settingsView`. |
| Focused | Not applicable: this file installs no key-view loop, focus ring override, or `NSResponder` focus handling of its own; whatever key-view order exists belongs to the controls a subclass adds. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this file. |
