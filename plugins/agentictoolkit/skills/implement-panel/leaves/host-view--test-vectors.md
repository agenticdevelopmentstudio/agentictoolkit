<!-- leaf: implement-panel/host-view--test-vectors · source: panel-host-view.md -->

# PanelHostView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-host-view-001 | replaces-content-on-set | Call `setContent(viewA)`, then `setContent(viewB)` | After the second call, `viewA` is no longer a subview of the content container; only `viewB` is |
| panel-host-view-002 | clears-content-on-nil | Call `setContent(viewA)`, then `setContent(nil)` | The content container has zero subviews after the second call |
| panel-host-view-003 | content-pinned-to-container-edges | Call `setContent(viewA)` | `viewA`'s top/leading/trailing/bottom anchors are each constrained equal to the content container's corresponding anchor with 0 constant |
| panel-host-view-004 | content-container-pinned-to-view-edges | Construct `PanelHostView()` | The content container's top/leading/trailing/bottom anchors are each constrained equal to `PanelHostView`'s corresponding anchor with 0 constant |
| panel-host-view-005 | help-button-inset-from-content-container | Construct `PanelHostView()` | The help button's top anchor equals the content container's top anchor + 12; its trailing anchor equals the content container's trailing anchor − 12 |
| panel-host-view-006 | help-button-above-content | Construct `PanelHostView()`, then call `setContent(viewA)` | The help button remains a subview of `PanelHostView` (not of the content container) both before and after the call, and is not removed or reordered by it |
| panel-host-view-007 | help-button-visibility | Set `showsHelpButton = false` with `helpPresenter` non-`nil` | `helpButton.isHidden == true` |
| panel-host-view-008 | help-button-visibility | Set `helpPresenter = nil` with `showsHelpButton == true` | `helpButton.isHidden == true` |
| panel-host-view-009 | help-button-visibility | Set `showsHelpButton = true` and assign a non-`nil` `helpPresenter` | `helpButton.isHidden == false` |
| panel-host-view-010 | help-button-icon-reflects-visibility | Set `helpPresenter` to a presenter stub whose `isHelpVisible` returns `true` | The help button's image is `questionmark.circle.fill` |
| panel-host-view-011 | help-button-icon-reflects-visibility | Assign a presenter whose `isHelpVisible == false` | The help button's image is `questionmark.circle` |
| panel-host-view-012 | help-button-symbol-configuration | Construct `PanelHostView()` | The image's symbol configuration reports point size 15 and weight `.regular` |
| panel-host-view-013 | help-button-tint-reflects-visibility | Presenter reports `isHelpVisible == true` while the active theme is "Solarized Dark" | `helpButton.contentTintColor` equals Solarized Dark's `SemanticPalette.accentColor` |
| panel-host-view-014 | help-button-tint-reflects-visibility | Presenter reports `isHelpVisible == false` while the active theme is "Solarized Dark" | `helpButton.contentTintColor` equals Solarized Dark's `SemanticPalette.secondaryTextColor` |
| panel-host-view-015 | help-button-tooltip-reflects-visibility | Presenter reports `isHelpVisible == true` | `helpButton.toolTip == "Hide Help"` |
| panel-host-view-016 | help-button-tooltip-reflects-visibility | Presenter reports `isHelpVisible == false` | `helpButton.toolTip == "Show Help"` |
| panel-host-view-017 | help-button-accessibility-label-fixed | Toggle help visible, then hidden | `helpButton`'s accessibility label reads `"Help"` in both states |
| panel-host-view-018 | help-button-borderless-image-only | Construct `PanelHostView()` | `helpButton.isBordered == false`; `helpButton.imagePosition == .imageOnly` |
| panel-host-view-019 | help-button-momentary-type | Construct `PanelHostView()` | `helpButton`'s button type is `.momentaryChange` |
| panel-host-view-020 | toggle-help-delegates-to-presenter | Assign a presenter, then call `toggleHelp()` | The presenter's `toggleHelp()` is invoked exactly once |
| panel-host-view-021 | toggle-help-delegates-to-presenter | With `helpPresenter == nil`, call `toggleHelp()` | No presenter method is invoked and no error occurs |
| panel-host-view-022 | help-anchor-claimed-when-button-shown | With `showsHelpButton == true`, assign a presenter | `presenter.helpAnchorView === helpButton` |
| panel-host-view-023 | help-anchor-untouched-when-button-hidden | With `showsHelpButton == false`, assign a presenter whose `helpAnchorView` was previously set to some other view | `presenter.helpAnchorView` is unchanged by the assignment |
| panel-host-view-024 | help-visibility-change-refreshes-button | With a presenter assigned, invoke the presenter's stored `onVisibilityChange` closure | The help button's icon/tint/tooltip are re-evaluated against the presenter's current `isHelpVisible` |
| panel-host-view-025 | help-visibility-change-notifies-external-observer | With `onHelpVisibilityChange` set, invoke the presenter's `onVisibilityChange` closure | `onHelpVisibilityChange` is invoked exactly once, after the button refresh |
| panel-host-view-026 | presenter-reassignment | Call `setHelp(contentA)`, then assign a new `helpPresenter` | The new presenter receives `setHelp(contentA)`, its `helpAnchorView` is claimed (if shown), and its `onVisibilityChange` is this view's closure |
| panel-host-view-027 | set-help-forwards-to-presenter | With a presenter assigned, call `setHelp(nil)` | The presenter receives `setHelp(nil)` and the help button is refreshed |
| panel-host-view-028 | is-help-visible-reflects-presenter-or-false | Query `isHelpVisible` with `helpPresenter == nil` | Returns `false` |
| panel-host-view-029 | is-help-visible-reflects-presenter-or-false | Query `isHelpVisible` with a presenter whose `isHelpVisible == true` | Returns `true` |
| panel-host-view-030 | shows-help-button-toggle | Toggle `showsHelpButton` from `false` to `true` with a presenter assigned | The presenter's `helpAnchorView` is claimed and the help button's hidden/icon/tint state is refreshed |
| panel-host-view-031 | theme-change-refreshes-button-tint | With help visible while the active theme is "Solarized Dark", call `ThemeManager.selectTheme(id:)` with Solarized Light's id | `helpButton.contentTintColor` updates to Solarized Light's `SemanticPalette.accentColor` without reconstructing the view |
| panel-host-view-032 | rejects-coder-initialization | Attempt `PanelHostView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| panel-host-view-033 | constraint-based-layout-only | Inspect `PanelHostView`, its content container, and its help button after construction | `translatesAutoresizingMaskIntoConstraints == false` for all three |
| panel-host-view-034 | help-button-keyboard-focusable | Construct `PanelHostView()`, Tab focus to the visible help button, then press Space | The help button receives key-view focus via Tab/Shift-Tab and its action fires on Space/Return, using `NSButton`'s unmodified default first-responder and key-equivalent handling |
