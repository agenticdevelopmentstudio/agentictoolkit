<!-- leaf: implement-general-controller/split-view-controller · source: split-view-controller.md -->

**Rules** (cite as `implement-general-controller/split-view-controller#<slug>`):

- `hosted-panel-itself-splitviewcontroller-see-settingspanelsplitviewcontroller` MAY — A hosted panel MAY itself be a SplitViewController (see SettingsPanelSplitViewController's own recipe), in which case …

# SplitViewController

## Overview

`ComposableSettings.SplitViewController`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift`,
is the base class for a topic/detail split-pane container used throughout the
settings window: a non-collapsible sidebar of panels on the left, driven by a
`PanelListViewController`, and a themed detail pane on the right that shows
whichever panel is currently selected, hosted inside a `PanelHostView`. It
subclasses `ThemedSplitViewController` (an `AgenticDeveloperToolkit` base
that supplies theme-aware split-view chrome and a divider-hiding safety fix)
and conforms to `NSSearchFieldDelegate` solely to redirect the sidebar
search field's arrow keys to sidebar-row navigation. Per the source's own
doc comments, a client subclasses `SplitViewController` and populates it in
`viewDidLoad` by calling `addPanel(_:)`.

A hosted panel MAY itself be a `SplitViewController` (see
`SettingsPanelSplitViewController`'s own recipe), in which case this class
treats it as a nested split: it unifies every nested sibling's sidebar to
one content width and raises its own detail floor so the nested content is
never squeezed.

**Owns:**
- Panel storage and ordering, including optional alphabetical sorting
- An in-place back/forward navigation trail (`SettingsNavigationHistory`)
- Sidebar sizing — draggable-and-autosaved, or content-sized and pinned
- An optional sidebar search field and its arrow-key-to-selection redirect
- Repainting the window/detail backgrounds from the active theme
- Forwarding help state to a `PanelHostView`

**Delegates to:**
- `PanelListViewController` — sidebar row rendering and search matching
  (its own recipe)
- `PanelHostView` — the detail pane's help-button chrome (its own recipe)
- `PanelScrollView` — the scroll wrapper around non-self-scrolling panel
  content (its own recipe)
- `SettingsWindow` — the window-level toolbar that drives this class's
  `goBack()`/`goForward()`/`helpPresenter` (its own recipe)

This recipe documents only what this file itself declares.

