<!-- leaf: implement-composable-tabs/settings-view-controller--part-3 · source: composable-tabs-settings-view-controller.md -->

# ComposableTabsSettingsViewController — continued (part 3)

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
