<!-- leaf: implement-settings/panel-split-view-controller · source: settings-panel-split-view-controller.md -->

**Rules** (cite as `implement-settings/panel-split-view-controller#<slug>`):

- `exposes-descriptor` MUST
- `defaults-descriptor-when-omitted` MUST
- `titles-sidebar-from-descriptor` MUST
- `rejects-coder-initialization` MUST
- `acts-as-hostable-panel` MUST
- `returns-nil-help-content-by-default` MUST
- `falls-back-help-content-through-inner-selection` MUST
- `surfaces-empty-help-when-chain-exhausted` MUST
- `reports-no-additional-search-keywords` MUST
- `narrows-detail-minimum-thickness` MUST
- `fixes-content-sized-sidebar` MUST
- `runs-on-main-actor` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | `SettingsPanelDescriptor?` | `nil` (resolves to `SettingsPanelDescriptor()`, `title == ""`) | The panel's own sidebar-row metadata; also the source of `sidebarTitle` at initialization. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this file. |
| Increase Contrast | Not applicable: no color is set anywhere in this file. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator. |

## Privacy

- **Data collected**: None — this file holds only the `descriptor`
  reference it is constructed with or defaults to.
- **Storage**: Not applicable — no persistence code exists in this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this file.
- **Retention**: The `descriptor` reference is held in memory for this
  controller's own lifetime and is never persisted by this file.

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

