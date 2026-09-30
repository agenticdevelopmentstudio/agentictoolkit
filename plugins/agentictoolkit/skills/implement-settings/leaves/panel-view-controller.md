<!-- leaf: implement-settings/panel-view-controller · source: settings-panel-view-controller.md -->

**Rules** (cite as `implement-settings/panel-view-controller#<slug>`):

- `class-declaration` MUST
- `main-actor-isolation` MUST
- `descriptor` MUST
- `default-descriptor` MUST
- `descriptor-retention` MUST
- `coder-initialization` MUST
- `root-view` MUST
- `add-group` MUST
- `help-content-default` MUST
- `effective-help-content` MUST
- `hosts-own-scroll-default` MUST
- `search-keywords-default` MUST
- `protocol-default-redeclaration` MUST
- `hosting-view-helper` MUST
- `hosting-view-sizing-options` MUST
- `hosting-view-autoresizing-mask` MUST

# SettingsPanelViewController

## Overview

`ComposableSettings.SettingsPanelViewController`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelViewController.swift`)
is the base `NSViewController` every `ComposableSettings` panel subclasses.
Per the source's own doc comment, one instance is hosted in the right-hand
detail pane of a `ComposableSettings.SplitViewController`, and the sidebar's
list-item metadata lives on the panel itself, via `descriptor` — "the panel
*is* the list item — no wrapper struct." Its `loadView()` sets `self.view` to
`settingsView`, a `PanelView` instance this class owns and constructs. It
conforms to `ComposableSettingsPanel`, redeclaring that protocol's
`helpContent`, `effectiveHelpContent`, `hostsOwnScroll`, and `searchKeywords`
defaults directly on the class (rather than inheriting them from the
protocol extension) so that a subclass override is actually reached through
the `any ComposableSettingsPanel` existential the hosting split holds. It
also exposes a convenience `addGroup(_:)`, forwarding to
`settingsView.addGroup(_:)`, and a `static func hostingView(for:)` helper
that lets a subclass host SwiftUI content as its own view without that
content's intrinsic size resizing the settings window it sits in.

## Behavioral Requirements

- **class-declaration**: Component MUST be declared as an `open class`
  subclassing `NSViewController` and conforming to `ComposableSettingsPanel`.
- **main-actor-isolation**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **descriptor**: Component MUST expose a public, immutable
  `descriptor: SettingsPanelDescriptor`, set once at construction, supplying
  the sidebar's title/icon/isDisabled/section metadata for this panel.
- **default-descriptor**: Component MUST construct a default
  `SettingsPanelDescriptor()` when `init(with:)` is called with `nil` (its
  default value) or no argument at all.
- **descriptor-retention**: Component MUST retain the exact descriptor
  instance passed to `init(with:)` — rather than constructing a new one —
  whenever a non-`nil` descriptor is supplied.
- **coder-initialization**: Component MUST NOT support construction via
  `init(coder:)`; the required `init?(coder:)` MUST trigger a fatal error.
- **root-view**: Component's `loadView()` MUST set `self.view` to
  `settingsView`, the `PanelView` instance this class owns.
- **add-group**: Component MUST expose a public `addGroup(_:)` method that
  forwards its `GroupView` argument, unchanged, to
  `settingsView.addGroup(_:)`.
- **help-content-default**: Component's `helpContent` MUST default to `nil`
  when not overridden by a subclass — a plain panel offers no reference
  prose, and the detail pane's help drawer shows its own empty state rather
  than losing its help button.
- **effective-help-content**: Component's
  `effectiveHelpContent` MUST return `helpContent` unless overridden — a
  plain panel holds no selection of its own, so the help it effectively
  shows is its own.
- **hosts-own-scroll-default**: Component's `hostsOwnScroll` MUST default to
  `false` unless overridden. (Consumed by
  `ComposableSettings.SplitViewController`'s detail-pane host, outside this
  file, to decide whether this panel's view is wrapped in a
  `PanelScrollView` or hosted directly.)
- **search-keywords-default**: Component's `searchKeywords` MUST default to
  an empty array unless overridden.
- **protocol-default-redeclaration**: Component MUST redeclare
  `helpContent`, `effectiveHelpContent`, `hostsOwnScroll`, and
  `searchKeywords` as `open` members on this class rather than relying on
  `ComposableSettingsPanel`'s protocol-extension defaults. Per the source's
  own comment, a protocol extension's default is bound at the point of
  conformance — this class — so a subclass property that merely shadows
  that default would be invisible through the `any ComposableSettingsPanel`
  existential the hosting split holds.
- **hosting-view-helper**: Component MUST expose a `static func
  hostingView(for content: some View) -> NSView` that wraps `content` in an
  `NSHostingView` for use as a panel's own view.
- **hosting-view-sizing-options**: The `NSHostingView` returned by
  `hostingView(for:)` MUST have its `sizingOptions` set to
  `[.intrinsicContentSize]` — not AppKit's `.standardBounds` default — so
  the hosted SwiftUI content contributes a sizing *preference* rather than
  required min/max size constraints to its superview. See
  **#design-decisions** for why.
- **hosting-view-autoresizing-mask**: The `NSHostingView` returned by
  `hostingView(for:)` MUST have `translatesAutoresizingMaskIntoConstraints`
  set to `false`.

## Appearance

- **Corner radius**: Not set by this file. `SettingsPanelViewController`
  draws nothing of its own; any corner radius on screen belongs to whatever
  `GroupView` cards a subclass adds via `addGroup(_:)`
  (`SettingsLayout.default[.cardCornerRadius]` = 10pt; see
  `agentictoolkit://recipes/group-view`).
- **Padding**: Not set by this file. The panel inset and inter-group
  spacing (`SettingsLayout.default[.panelInset]`,
  `SettingsLayout.default[.groupSpacing]`, both 20pt) belong to
  `settingsView`, the `PanelView` this class constructs and hosts unchanged;
  see `agentictoolkit://recipes/panel-view`.
- **Font**: Not applicable — this file sets no font of its own; any text
  rendered comes from the `GroupView`s a subclass composes via
  `addGroup(_:)`, or from SwiftUI content hosted through `hostingView(for:)`,
  whose fonts are the subclass's responsibility.
- **Background**: Not set by this file. `settingsView` paints the theme's
  `.windowBackground` role behind the group stack, reactively, through its
  own `ThemePaletteObserver`; see `agentictoolkit://recipes/panel-view`.
- **Foreground/Text**: Not applicable — this file renders no text of its
  own.
- **Border**: Not applicable — no border is set anywhere in
  `SettingsPanelViewController.swift`.
- **Shadow**: Not applicable — no shadow, `NSShadow`, or layer shadow
  property is set anywhere in this file.
- **Min/Max size**: `SettingsPanelViewController` sets no min/max size
  constraint on `self.view` itself. Its `hostingView(for:)` helper
  deliberately avoids installing one on the SwiftUI content it hosts — see
  **#design-decisions** for why `sizingOptions = [.intrinsicContentSize]` is
  used instead of `NSHostingView`'s `.standardBounds` default.

## Accessibility

- **Role/trait**: Not applicable beyond AppKit's own default —
  `SettingsPanelViewController` sets no explicit accessibility role
  anywhere in source; it is a transparent container whose view is
  `settingsView`, with no label, icon, or control of its own to expose. Each
  `GroupView` a subclass adds manages its own accessibility per its own
  recipe (`agentictoolkit://recipes/group-view`).
- **Label requirements**: Not applicable — this file sets no accessibility
  label on `settingsView`. `descriptor.title` becomes the sidebar row's
  accessible name only through the sidebar list controller
  (`PanelListViewController`/`TopicListViewController`, outside this file);
  any accessible label for the detail pane's *content* comes from whatever a
  subclass adds via `addGroup(_:)` or `hostingView(for:)`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this file has no loading or disabled transition of its own for an
  announcement to accompany (see States: Disabled, Loading above).
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSViewController` (no touch input path anywhere
  in this file), and `SettingsPanelViewController.swift` itself defines no
  button, checkbox, or other control with a hit target for the 44×44pt
  iOS/touch guidance to apply to.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | `SettingsPanelDescriptor?` | `nil` | Passed to `init(with:)`. When supplied, retained as-is (spvc-005); when `nil`, a default `SettingsPanelDescriptor()` (empty title) is constructed instead (spvc-004). |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file. |
| Increase Contrast | Not applicable: this file sets no literal `NSColor` or other color of its own to adjust for contrast. |
| Differentiate Without Color | Not applicable: this file conveys no state through color; it draws nothing itself. |

## Privacy

- **Data collected**: None of its own. The component holds only the
  caller-supplied or default-constructed `descriptor` (title/icon/
  isDisabled/section) and its own `settingsView`.
- **Storage**: Not applicable — this file performs no read/write to disk,
  `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Not applicable — `descriptor` is in-memory state retained
  only for the panel instance's own lifetime; this file persists nothing.

