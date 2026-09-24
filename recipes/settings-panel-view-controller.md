---
id: 432e8d4b-43c3-49fd-b481-036a759e7c55
title: SettingsPanelViewController
domain: agentictoolkit://recipes/settings-panel-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit base class for ComposableSettings panels: descriptor metadata, PanelView
  hosting, and a window-safe SwiftUI hosting helper.'
platforms:
- swift
- macos
tags:
- settings
- panel-controller
- view-controller
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/panel-view
- agentictoolkit://recipes/group-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

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

- **subclasses-view-controller-conforming-to-panel-protocol**: Component
  MUST be declared as an `open class` subclassing `NSViewController` and
  conforming to `ComposableSettingsPanel`.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **exposes-immutable-descriptor**: Component MUST expose a public,
  immutable `descriptor: SettingsPanelDescriptor`, set once at construction,
  supplying the sidebar's title/icon/isDisabled/section metadata for this
  panel.
- **constructs-default-descriptor-when-omitted**: Component MUST construct a
  default `SettingsPanelDescriptor()` when `init(with:)` is called with
  `nil` (its default value) or no argument at all.
- **retains-supplied-descriptor**: Component MUST retain the exact
  descriptor instance passed to `init(with:)` — rather than constructing a
  new one — whenever a non-`nil` descriptor is supplied.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init(coder:)`; the required `init?(coder:)` MUST trigger a fatal
  error.
- **hosts-panel-view-as-root-view**: Component's `loadView()` MUST set
  `self.view` to `settingsView`, the `PanelView` instance this class owns.
- **exposes-add-group**: Component MUST expose a public `addGroup(_:)`
  method that forwards its `GroupView` argument, unchanged, to
  `settingsView.addGroup(_:)`.
- **defaults-help-content-to-nil**: Component's `helpContent` MUST default
  to `nil` when not overridden by a subclass — a plain panel offers no
  reference prose, and the detail pane's help drawer shows its own empty
  state rather than losing its help button.
- **mirrors-effective-help-content-to-help-content**: Component's
  `effectiveHelpContent` MUST return `helpContent` unless overridden — a
  plain panel holds no selection of its own, so the help it effectively
  shows is its own.
- **defaults-hosts-own-scroll-to-false**: Component's `hostsOwnScroll` MUST
  default to `false` unless overridden. (Consumed by
  `ComposableSettings.SplitViewController`'s detail-pane host, outside this
  file, to decide whether this panel's view is wrapped in a
  `PanelScrollView` or hosted directly.)
- **defaults-search-keywords-to-empty**: Component's `searchKeywords` MUST
  default to an empty array unless overridden.
- **redeclares-protocol-defaults-for-subclass-dispatch**: Component MUST
  redeclare `helpContent`, `effectiveHelpContent`, `hostsOwnScroll`, and
  `searchKeywords` as `open` members on this class rather than relying on
  `ComposableSettingsPanel`'s protocol-extension defaults. Per the source's
  own comment, a protocol extension's default is bound at the point of
  conformance — this class — so a subclass property that merely shadows
  that default would be invisible through the `any ComposableSettingsPanel`
  existential the hosting split holds.
- **provides-swiftui-hosting-helper**: Component MUST expose a `static func
  hostingView(for content: some View) -> NSView` that wraps `content` in an
  `NSHostingView` for use as a panel's own view.
- **constrains-hosting-view-to-intrinsic-sizing**: The `NSHostingView`
  returned by `hostingView(for:)` MUST have its `sizingOptions` set to
  `[.intrinsicContentSize]` — not AppKit's `.standardBounds` default — so
  the hosted SwiftUI content contributes a sizing *preference* rather than
  required min/max size constraints to its superview.
- **disables-autoresizing-mask-on-hosting-view**: The `NSHostingView`
  returned by `hostingView(for:)` MUST have
  `translatesAutoresizingMaskIntoConstraints` set to `false`.

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
  deliberately avoids installing one on the SwiftUI content it hosts: an
  `NSHostingView` defaults to `.standardBounds`, which derives *required*
  min- and max-size constraints from the SwiftUI content's own sizing — and
  because the detail pane pins a panel's view to its edges, those
  constraints become the settings window's own, so a panel whose content is
  a finite stack of cards would collapse the window to that height and hold
  it there. `hostingView(for:)` sets `sizingOptions = [.intrinsicContentSize]`
  instead, so the hosted content's size is only a hugging-priority
  preference (still read by `PanelScrollView`'s document, so content taller
  than the pane scrolls rather than being clipped) — panel content never
  sizes the window; the window sizes the panel.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: `SettingsPanelViewController` is a container view controller, not a control; it registers no target/action and applies no pressed-state styling anywhere in source. |
| Disabled | Not applicable to this file's own view. `descriptor.isDisabled` is declared on `SettingsPanelDescriptor` and is read only by the sidebar row list (`PanelListViewController.buildSections`, a different file) to disable that row; `SettingsPanelViewController.swift` never reads `descriptor.isDisabled` and applies no disabled styling to `settingsView`. |
| Focused | Not applicable: this file installs no key-view loop, focus ring override, or `NSResponder` focus handling of its own; whatever key-view order exists belongs to the controls a subclass adds. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this file. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| spvc-001 | subclasses-view-controller-conforming-to-panel-protocol | Inspect the class declaration | `SettingsPanelViewController` is an `open class` inheriting `NSViewController` and conforming to `ComposableSettingsPanel` |
| spvc-002 | confines-to-main-actor | Attempt to construct or mutate an instance from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
| spvc-003 | exposes-immutable-descriptor | Construct `SettingsPanelViewController(with: myDescriptor)` | `instance.descriptor` is a public, non-optional, immutable `SettingsPanelDescriptor` |
| spvc-004 | constructs-default-descriptor-when-omitted | Construct `SettingsPanelViewController()` (no argument) | `instance.descriptor` is a freshly constructed `SettingsPanelDescriptor` with `title == ""` |
| spvc-005 | retains-supplied-descriptor | Construct `SettingsPanelViewController(with: myDescriptor)` | `instance.descriptor === myDescriptor` (the same instance, not a copy) |
| spvc-006 | rejects-coder-initialization | Attempt `SettingsPanelViewController(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| spvc-007 | hosts-panel-view-as-root-view | Trigger `loadView()` | `instance.view === instance.settingsView`, and `instance.settingsView` is a `PanelView` |
| spvc-008 | exposes-add-group | Call `instance.addGroup(myGroup)` | `myGroup` becomes an arranged subview of `instance.settingsView`'s internal stack, in the same call as `settingsView.addGroup(myGroup)` would produce |
| spvc-009 | defaults-help-content-to-nil | Read `instance.helpContent` on a plain, non-overriding instance | Returns `nil` |
| spvc-010 | mirrors-effective-help-content-to-help-content | Read `instance.effectiveHelpContent` on a plain, non-overriding instance whose `helpContent` is `nil` | Returns `nil`; on a subclass instance overriding `helpContent` to a non-nil value, returns that same value |
| spvc-011 | defaults-hosts-own-scroll-to-false | Read `instance.hostsOwnScroll` on a plain, non-overriding instance | Returns `false` |
| spvc-012 | defaults-search-keywords-to-empty | Read `instance.searchKeywords` on a plain, non-overriding instance | Returns `[]` |
| spvc-013 | redeclares-protocol-defaults-for-subclass-dispatch | Subclass `SettingsPanelViewController`, override `hostsOwnScroll` to return `true`, then access the instance through an `any ComposableSettingsPanel` existential | The existential's `hostsOwnScroll` reads `true` (the subclass override), not the protocol extension's `false` |
| spvc-014 | provides-swiftui-hosting-helper | Call `SettingsPanelViewController.hostingView(for: Text("Hi"))` | Returns an `NSView` that is an `NSHostingView` wrapping the given SwiftUI content |
| spvc-015 | constrains-hosting-view-to-intrinsic-sizing | Call `SettingsPanelViewController.hostingView(for: someView)`, inspect the returned `NSHostingView` | `sizingOptions == [.intrinsicContentSize]` |
| spvc-016 | disables-autoresizing-mask-on-hosting-view | Call `SettingsPanelViewController.hostingView(for: someView)`, inspect the returned view | `translatesAutoresizingMaskIntoConstraints == false` |

## Edge Cases

- Null/empty input: MUST — `init(with:)`'s `descriptor` parameter is
  `SettingsPanelDescriptor?`. When `nil` (its default) or omitted, a default
  `SettingsPanelDescriptor()` is constructed, which in turn defaults
  `title` to `""` (`SettingsPanelDescriptor`'s own `convenience init()`).
  This is a well-defined path, not an unhandled gap.
- Boundary values: Not applicable — this file takes no numeric or
  range-constrained input; `descriptor` is a reference type with no bounds.
- Concurrent access: MUST — the class and every member on it are
  `@MainActor`-confined, so the Swift compiler serializes every
  construction, read, and mutation to the main actor; this file itself has
  no concurrency hazard.
- Error states: Not applicable — every call in this file (`loadView()`,
  both initializers, `addGroup(_:)`, `hostingView(for:)`) is synchronous and
  non-throwing; no `try`, `Result`, or completion-with-error API appears
  anywhere in source.
- Offline/disconnected: Not applicable — this file performs no networking;
  it touches only in-process AppKit/SwiftUI state.
- Oversized hosted SwiftUI content: MUST — per `hostingView(for:)`'s own
  doc comment, content taller than the detail pane is not clipped or
  resized by this file; only `.intrinsicContentSize` is preserved on the
  returned `NSHostingView`, which `PanelScrollView`'s document (outside
  this file) reads to decide whether to scroll. This file's own guarantee
  is limited to advertising a sizing preference, not a hard constraint —
  it does not itself scroll or clip oversized content.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | `SettingsPanelDescriptor?` | `nil` | Passed to `init(with:)`. When supplied, retained as-is (spvc-005); when `nil`, a default `SettingsPanelDescriptor()` (empty title) is constructed instead (spvc-004). |

## Deep Linking

Not applicable: `SettingsPanelViewController` is a base class for a panel
hosted in a settings window's detail pane, not a directly routable screen —
no URL scheme, `NSUserActivity`, or deep-link handler appears anywhere in
this file.

## Localization

Not applicable: `SettingsPanelViewController.swift` introduces no
user-facing string literal of its own. `descriptor.title` defaults to the
empty string `""` in `SettingsPanelDescriptor`'s own `convenience init()`
and is otherwise supplied entirely by the caller or subclass; there is no
`Text`, `NSLocalizedString`, or literal `stringValue`/`title` assignment
anywhere in this file for a translator to act on.

## Accessibility Options

Document which accessibility display options (Rule 15) this component
responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file. |
| Increase Contrast | Not applicable: this file sets no literal `NSColor` or other color of its own to adjust for contrast. |
| Differentiate Without Color | Not applicable: this file conveys no state through color; it draws nothing itself. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this file; `loadView()`, both initializers, `addGroup(_:)`, and
`hostingView(for:)` all execute unconditionally.

## Analytics

Not applicable: this file contains no analytics or telemetry call.

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

## Logging

Not applicable: this file contains no logging call (no `print`, `os_log`,
or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: There is no `NSHostingView` bridging concern to solve — a
  SwiftUI settings panel is itself a `View`. Model the base class as a
  protocol (e.g. `SettingsPanel: Identifiable, View`) with associated
  `descriptor` (title/icon/isDisabled/section, mirroring
  `SettingsPanelDescriptor`'s published fields as `@Published` on an
  `ObservableObject` or as plain properties on a `struct`), plus
  `helpContent`/`effectiveHelpContent`/`searchKeywords` given default
  implementations in a protocol extension — Swift's normal protocol-witness
  dispatch resolves these correctly for a `View`-conforming type, so the
  redeclare-for-dispatch workaround this file needs for an `any
  ComposableSettingsPanel` existential does not apply. Compose panel
  content from a `ScrollView { LazyVStack { ... } }` unless the panel
  declares it hosts its own scrolling, mirroring `hostsOwnScroll`.
- **Compose**: Define an interface (e.g. `SettingsPanel`) exposing a
  `descriptor` data class (`title: String`, `icon: Painter?`,
  `isDisabled: Boolean`, `section: String?`), a `@Composable fun Content()`,
  and `helpContent`/`effectiveHelpContent`/`searchKeywords` with default
  (empty/null) implementations via a Kotlin interface default method or an
  abstract base class. The hosting `NavigationDrawer`/two-pane `Scaffold`
  wraps `Content()` in a `Column(Modifier.verticalScroll(rememberScrollState()))`
  unless the panel's `hostsOwnScroll` is `true`, mirroring
  `SplitViewController`'s `PanelScrollView`-wrapping branch.
- **React/Web**: Define a component contract (a TypeScript interface or an
  abstract base class) with a `descriptor` object (`title`, `icon`,
  `isDisabled`, `section`) and a `render()`/functional component for
  content, plus `helpContent`/`effectiveHelpContent`/`searchKeywords`
  defaulting to `null`/`null`/`[]`. The hosting layout wraps rendered
  content in a `<div style="overflow-y: auto">` unless the panel opts out
  via a `hostsOwnScroll` flag, mirroring the `PanelScrollView` wrap/no-wrap
  branch. There is no direct analog to `hostingView(for:)`'s min/max-size
  workaround, since a React component never carries AppKit-style required
  size constraints into its parent.
- **AppKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelViewController.swift`.
  A macOS-only (`import AppKit`, `import SwiftUI`), `@MainActor`, `open`
  `NSViewController` subclass conforming to `ComposableSettingsPanel`. It
  composes `PanelView`, `SettingsPanelDescriptor`, and `GroupView` — all
  defined elsewhere in `AgenticToolkit` — rather than reimplementing their
  layout. There is no UIKit code path anywhere in source; `ComposableSettings`
  is a macOS-only settings-window abstraction, so a UIKit port would need an
  entirely different navigation shell (e.g. `UISplitViewController`), not a
  line-for-line translation of this file.
- **WinUI 3** (the reason this recipe exists): Build the base class as an
  abstract `Page` (or `UserControl`), e.g. `SettingsPanelBase : Page`.
  Expose a `Descriptor` object implementing `INotifyPropertyChanged` with
  `Title` (`string`), `Icon` (`IconSource?`), `IsDisabled` (`bool`, default
  `false`), and `Section` (`string?`) — the direct analog of
  `SettingsPanelDescriptor`'s `@Published` fields — constructed in the base
  class's constructor from an optional parameter, defaulting to a
  descriptor with an empty `Title` exactly as `init(with:)` does. Give
  `HelpContent` (nullable), `EffectiveHelpContent` (defaulting to
  `HelpContent`), `HostsOwnScroll` (`bool`, default `false`), and
  `SearchKeywords` (`IReadOnlyList<string>`, default empty) each a `virtual`
  property with the base implementation supplying these defaults — WinUI's
  ordinary virtual-member dispatch through a base class reaches an
  overriding subclass correctly on its own, so the explicit
  redeclare-for-dispatch pattern this file needs (to defeat Swift's
  protocol-extension-default binding through an `any ComposableSettingsPanel`
  existential) has no WinUI counterpart to reproduce. The hosting
  `NavigationView`'s content presenter reads `HostsOwnScroll` to decide
  whether to wrap the panel's `Content` in a `ScrollViewer
  VerticalScrollBarVisibility="Auto"` or host it directly, mirroring
  `SplitViewController.show(_:)`'s `PanelScrollView`-wrapping branch. For
  the `hostingView(for:)` analog — hosting a differently-sized UI surface
  (a `WebView2`, or a control tree built by a different framework) inside a
  panel without letting its desired size drive the containing `Window`'s or
  `ContentDialog`'s size — set the containing window's `SizeToContent` to
  `Manual` and give the hosted control `HorizontalAlignment="Stretch"` with
  `VerticalAlignment="Top"` rather than binding the window's size to the
  hosted control's `DesiredSize`, reproducing `sizingOptions =
  [.intrinsicContentSize]`'s effect: the hosted content's size becomes a
  layout preference inside a `ScrollViewer`, never a hard constraint the
  containing window must satisfy.

## Design Decisions

- Decision: Redeclare `helpContent`, `effectiveHelpContent`,
  `hostsOwnScroll`, and `searchKeywords` directly on this class instead of
  relying on `ComposableSettingsPanel`'s protocol-extension defaults.
  Rationale: Per the source's own comment, "a protocol extension's default
  is bound at the point of conformance — this class — and a subclass
  property that merely shadows it is invisible through the `any
  ComposableSettingsPanel` the split holds." Redeclaring these as `open`
  members means an overriding subclass's value is reached through
  class-based dynamic dispatch instead of being silently skipped behind the
  existential.
  Approved: pending
- Decision: Give `hostingView(for:)`'s `NSHostingView` `sizingOptions =
  [.intrinsicContentSize]` instead of AppKit's `.standardBounds` default.
  Rationale: Per the source's own comment, `.standardBounds` "installs
  required min- and max-size constraints derived from the SwiftUI content's
  own sizing," and because the detail pane pins a panel to its edges, those
  constraints become the settings window's own — "a panel whose content is
  a stack of cards has a finite ideal height, and selecting it collapsed
  the window to that height and held it there." Restricting to
  `.intrinsicContentSize` keeps that sizing a hugging-priority preference
  (still read by `PanelScrollView`'s document, so oversized content
  scrolls) rather than a hard limit, so "panel content never sizes this
  window; the window sizes the panel."
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `SettingsPanelViewController` (AppKit, macOS) source. |
