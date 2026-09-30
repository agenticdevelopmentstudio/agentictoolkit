<!-- leaf: implement-settings/panel-split-view-controller--states · source: settings-panel-split-view-controller.md -->

# SettingsPanelSplitViewController

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
