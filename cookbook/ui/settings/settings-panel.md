---
id: 432e8d4b-43c3-49fd-b481-036a759e7c55
title: Settings Panel
domain: agentictoolkit://cookbook/ui/settings/settings-panel
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The base component every settings panel is built from, combining
  descriptor metadata, a composed content view, and a helper for hosting
  differently-sized content without letting it resize the settings window.
platforms:
- swift
- macos
tags:
- settings
- panel-controller
- view-controller
depends-on:
- agentictoolkit://cookbook/ui/settings/layout/panel-view
related:
- agentictoolkit://cookbook/ui/settings/layout/group-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Settings Panel

## Overview

The Settings Panel is the base type every settings panel is built from. One
instance is hosted in the right-hand detail pane of a settings split view,
and the sidebar's list-item metadata lives on the panel itself, via its
descriptor — "the panel *is* the list item — no wrapper struct." Its content
view is a panel view instance this type owns and constructs, exposed as its
own view. It conforms to a settings-panel role, redeclaring that role's
help-content, effective-help-content, hosts-own-scroll, and search-keywords
defaults directly on the type (rather than inheriting them from a shared
default) so that a subclass override is actually reached through the
generic reference the hosting split holds. It also exposes a convenience
method for adding a group, forwarding to its own content view, and a helper
that lets a subclass host differently-sized UI content as its own view
without that content's intrinsic size resizing the settings window it sits
in.

## Behavioral Requirements

- **descriptor**: Component MUST expose a public, immutable descriptor,
  set once at construction, supplying the sidebar's title/icon/isDisabled/
  section metadata for this panel.
- **default-descriptor**: Component MUST construct a default descriptor
  when constructed with no descriptor supplied (or an explicit absence of
  one).
- **descriptor-retention**: Component MUST retain the exact descriptor
  instance supplied at construction — rather than constructing a new one —
  whenever one is supplied.
- **root-view**: Component MUST expose its own composed content view — a
  panel view instance this type owns — as its view.
- **add-group**: Component MUST expose a public method that forwards its
  group argument, unchanged, to its own content view.
- **help-content-default**: Component's help content MUST default to none
  when not overridden by a subclass — a plain panel offers no reference
  prose, and the detail pane's help drawer shows its own empty state rather
  than losing its help button.
- **effective-help-content**: Component's effective help content MUST
  return its own help content unless overridden — a plain panel holds no
  selection of its own, so the help it effectively shows is its own.
- **hosts-own-scroll-default**: Component's hosts-own-scroll flag MUST
  default to false unless overridden. (Consumed by the hosting split
  view's detail-pane host, outside this component, to decide whether this
  panel's view is wrapped in a scrolling container or hosted directly.)
- **search-keywords-default**: Component's search keywords MUST default to
  an empty list unless overridden.
- **subclass-default-override-visibility**: Component MUST ensure that a
  subclass's override of any of its help-content, effective-help-content,
  hosts-own-scroll, or search-keywords defaults is observable when the
  panel is referenced through the generic interface the hosting split
  uses to hold panels, not only through its own concrete type.
- **hosting-view-helper**: Component MUST expose a helper that wraps
  arbitrary content for use as a panel's own view.
- **hosting-view-sizing-options**: The wrapper returned by that helper
  MUST advertise the hosted content's size to its container as a sizing
  preference, not a required min/max size constraint. See Design
  Decisions for why.

## Appearance

- **Corner radius**: Not set by this component; it draws nothing of its
  own. Any corner radius on screen belongs to whatever group view cards a
  subclass adds (10pt corner radius by default; see
  `agentictoolkit://cookbook/ui/settings/layout/group-view`).
- **Padding**: Not set by this component. The panel inset and inter-group
  spacing (20pt each, by default) belong to its own content view, hosted
  unchanged; see
  `agentictoolkit://cookbook/ui/settings/layout/panel-view`.
- **Font**: Not applicable — this component sets no font of its own; any
  text rendered comes from the group views a subclass composes, or from
  content hosted through the hosting helper, whose fonts are the
  subclass's responsibility.
- **Background**: Not set by this component. Its content view paints the
  theme's window-background role behind the group stack, reactively,
  through its own theme-change subscription; see
  `agentictoolkit://cookbook/ui/settings/layout/panel-view`.
- **Foreground/Text**: Not applicable — this component renders no text of
  its own.
- **Border**: Not applicable — no border is set anywhere in this
  component.
- **Shadow**: Not applicable — no shadow or layer-shadow property is set
  anywhere in this component.
- **Min/Max size**: The component sets no min/max size constraint on its
  own view. Its hosting helper deliberately avoids installing one on the
  content it hosts — see Design Decisions for why a sizing preference is
  used instead of a hard size constraint.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: the component is a container, not a control; it registers no press handling and applies no pressed-state styling anywhere in source. |
| Disabled | Not applicable to this component's own view. The descriptor's disabled flag is read only by the sidebar row list (a different concept) to disable that row; this component never reads that flag itself and applies no disabled styling to its own view. |
| Focused | Not applicable: this component installs no key-view loop or focus-ring override of its own; whatever focus order exists belongs to the controls a subclass adds. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this component. |

## Accessibility

- **Role/trait**: Not applicable beyond the platform's own default — the
  component sets no explicit accessibility role anywhere in source; it is
  a transparent container whose view is its own content view, with no
  label, icon, or control of its own to expose. Each group view a
  subclass adds manages its own accessibility per its own recipe
  (`agentictoolkit://cookbook/ui/settings/layout/group-view`).
- **Label requirements**: Not applicable — this component sets no
  accessibility label on its own view. The descriptor's title becomes the
  sidebar row's accessible name only through the sidebar list component,
  outside this component; any accessible label for the detail pane's
  *content* comes from whatever a subclass adds via its group method or
  its hosting helper.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this component has no loading or disabled transition of its own for an
  announcement to accompany (see States: Disabled, Loading above).
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-
  driven composition (no touch input path anywhere in this component),
  and this component itself defines no button, checkbox, or other control
  with a hit target for the 44×44pt touch guidance to apply to.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| spvc-003 | descriptor | Attempt to assign a new descriptor to an existing instance after construction | Rejected — the descriptor is immutable after construction |
| spvc-004 | default-descriptor | Construct the component with no descriptor argument | Its descriptor is a freshly constructed default descriptor with an empty title |
| spvc-005 | descriptor-retention | Construct the component with a given descriptor | The component's descriptor is that exact same instance, not a copy |
| spvc-007 | root-view | Trigger the component's view-loading step | The component's view is its own content view, which is a panel view |
| spvc-008 | add-group | Call the component's add-group method with a given group | That group becomes the last item in the content view's stack |
| spvc-009 | help-content-default | Read the help content on a plain, non-overriding instance | Returns none |
| spvc-010 | effective-help-content | Read the effective help content on a plain, non-overriding instance whose help content is none | Returns none; on a subclass instance overriding help content to a non-empty value, returns that same value |
| spvc-011 | hosts-own-scroll-default | Read the hosts-own-scroll flag on a plain, non-overriding instance | Returns false |
| spvc-012 | search-keywords-default | Read the search keywords on a plain, non-overriding instance | Returns an empty list |
| spvc-013 | subclass-default-override-visibility | Subclass the component, override the hosts-own-scroll default to return true, then access the instance through the generic panel interface the hosting split holds | The generic reference's hosts-own-scroll reads true (the subclass override), not the shared default's false |
| spvc-014 | hosting-view-helper | Call the component's hosting helper with some content | Returns a wrapper view containing the given content |
| spvc-015 | hosting-view-sizing-options | Call the hosting helper with some content, inspect the returned wrapper's sizing behavior | The wrapper advertises the content's size as a preference, not a required min/max constraint |

## Edge Cases

- Null/empty input: see **default-descriptor** — when no descriptor is
  supplied at construction, the component MUST construct a default
  descriptor, which in turn defaults its title to an empty string. This
  is a well-defined path, not an unhandled gap.
- Boundary values: Not applicable — this component takes no numeric or
  range-constrained input; the descriptor is a reference type with no
  bounds.
- Concurrent access: see **main-actor-isolation** in Platform Notes — the
  component is confined to a single, serialized execution context, so
  every construction, read, and mutation is serialized; this component
  itself has no concurrency hazard.
- Error states: Not applicable — every operation in this component (view
  loading, both construction paths, the add-group method, the hosting
  helper) is synchronous and non-throwing; no error or completion-with-
  error path appears anywhere in source.
- Offline/disconnected: Not applicable — this component performs no
  networking; it touches only in-process UI state.
- Oversized hosted content: see Design Decisions for why the hosting
  helper preserves only a sizing preference on the wrapper it returns.
  Content taller than the detail pane is not clipped or resized by this
  component; the scrolling container that hosts a panel (outside this
  component) reads that preference to decide whether to scroll. This
  component's own guarantee is limited to advertising a sizing
  preference, not a hard constraint — it does not itself scroll or clip
  oversized content.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `descriptor` | Descriptor (optional) | none | Passed at construction. When supplied, retained as-is (spvc-005); when omitted, a default descriptor (empty title) is constructed instead (spvc-004). |

## Deep Linking

Not applicable: the component is a base type for a panel hosted in a
settings window's detail pane, not a directly routable screen — no URL
scheme or deep-link handler appears anywhere in this component.

## Localization

Not applicable: this component introduces no user-facing string literal of
its own. The descriptor's title defaults to an empty string in its own
default construction and is otherwise supplied entirely by the caller or
subclass; there is no literal string assignment anywhere in this component
for a translator to act on.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition appears anywhere in this component. |
| Increase Contrast | Not applicable: this component sets no literal color of its own to adjust for contrast. |
| Differentiate Without Color | Not applicable: this component conveys no state through color; it draws nothing itself. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component; view loading, both construction paths, the add-group
method, and the hosting helper all execute unconditionally.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None of its own. The component holds only the
  caller-supplied or default-constructed descriptor (title/icon/
  isDisabled/section) and its own content view.
- **Storage**: Not applicable — this component performs no read/write to
  disk or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component.
- **Retention**: Not applicable — the descriptor is in-memory state
  retained only for the panel instance's own lifetime; this component
  persists nothing.

## Logging

Not applicable: this component contains no logging call.

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
  `NSViewController` subclass conforming to `ComposableSettingsPanel`. The
  class declaration itself is the platform's contract: `@MainActor`
  confines every construction, read, and mutation of the class to the
  main actor under Swift's concurrency checking, and the class supports
  construction only through `init(with:)` — the required `init?(coder:)`
  is overridden to trigger a fatal error, so a caller cannot construct one
  through that path. It composes `PanelView`, `SettingsPanelDescriptor`,
  and `GroupView` — all defined elsewhere in `AgenticToolkit` — rather than
  reimplementing their layout. Its `loadView()` sets `self.view` to
  `settingsView`, the `PanelView` instance the class owns. The hosting
  helper's `NSHostingView` also sets
  `translatesAutoresizingMaskIntoConstraints = false`, opting the returned
  view out of AppKit's legacy autoresizing-mask-to-constraints translation
  so the Auto Layout constraints the caller applies are the only sizing
  authority. There is no UIKit code path anywhere in source;
  `ComposableSettings` is a macOS-only settings-window abstraction, so a
  UIKit port would need an entirely different navigation shell (e.g.
  `UISplitViewController`), not a line-for-line translation of this file.
- **WinUI 3**: Build the base class as an abstract `Page` (or
  `UserControl`), e.g. `SettingsPanelBase : Page`.
  - Descriptor: Expose a `Descriptor` object implementing
    `INotifyPropertyChanged` with `Title` (`string`), `Icon` (`IconSource?`),
    `IsDisabled` (`bool`, default `false`), and `Section` (`string?`) — the
    direct analog of `SettingsPanelDescriptor`'s `@Published` fields —
    constructed in the base class's constructor from an optional parameter,
    defaulting to a descriptor with an empty `Title` exactly as
    `init(with:)` does.
  - Virtual defaults: Give `HelpContent` (nullable), `EffectiveHelpContent`
    (defaulting to `HelpContent`), `HostsOwnScroll` (`bool`, default
    `false`), and `SearchKeywords` (`IReadOnlyList<string>`, default empty)
    each a `virtual` property with the base implementation supplying these
    defaults — WinUI's ordinary virtual-member dispatch through a base class
    reaches an overriding subclass correctly on its own, so the explicit
    redeclare-for-dispatch pattern this file needs (to defeat Swift's
    protocol-extension-default binding through an `any
    ComposableSettingsPanel` existential) has no WinUI counterpart to
    reproduce.
  - Scroll wrapping: The hosting `NavigationView`'s content presenter reads
    `HostsOwnScroll` to decide whether to wrap the panel's `Content` in a
    `ScrollViewer VerticalScrollBarVisibility="Auto"` or host it directly,
    mirroring `SplitViewController.show(_:)`'s `PanelScrollView`-wrapping
    branch.
  - Hosting-size analog: For the `hostingView(for:)` analog — hosting a
    differently-sized UI surface (a `WebView2`, or a control tree built by a
    different framework) inside a panel without letting its desired size
    drive the containing `Window`'s or `ContentDialog`'s size — note that
    WinUI 3's `Window` and `ContentDialog` have no `SizeToContent` property
    (that is a WPF API, not a WinUI 3 one). Instead, size the containing
    `Window` explicitly through `AppWindow.Resize` and give the hosted
    control `HorizontalAlignment="Stretch"` with `VerticalAlignment="Top"`
    inside a `ScrollViewer`, rather than letting the hosted control's
    `DesiredSize` drive the window's size. This reproduces `sizingOptions =
    [.intrinsicContentSize]`'s effect: the hosted content's size becomes a
    layout preference inside a `ScrollViewer`, never a hard constraint the
    containing window must satisfy.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelViewController.swift` |

## Design Decisions

**Decision**: Redeclare `helpContent`, `effectiveHelpContent`,
`hostsOwnScroll`, and `searchKeywords` directly on this class instead of
relying on `ComposableSettingsPanel`'s protocol-extension defaults.
(AppKit source.)
**Rationale**: Per the source's own comment, "a protocol extension's default
is bound at the point of conformance — this class — and a subclass property
that merely shadows it is invisible through the `any ComposableSettingsPanel`
the split holds." Redeclaring these as `open` members means an overriding
subclass's value is reached through class-based dynamic dispatch instead of
being silently skipped behind the existential.
**Approved**: pending

**Decision**: Give `hostingView(for:)`'s `NSHostingView` `sizingOptions =
[.intrinsicContentSize]` instead of AppKit's `.standardBounds` default.
(AppKit source.)
**Rationale**: Per the source's own comment, `.standardBounds` "installs
required min- and max-size constraints derived from the SwiftUI content's
own sizing," and because the detail pane pins a panel to its edges, those
constraints become the settings window's own — "a panel whose content is a
stack of cards has a finite ideal height, and selecting it collapsed the
window to that height and held it there." Restricting to
`.intrinsicContentSize` keeps that sizing a hugging-priority preference
(still read by `PanelScrollView`'s document, so oversized content scrolls)
rather than a hard limit, so "panel content never sizes this window; the
window sizes the panel." (See **hosting-view-sizing-options** and the
Appearance › Min/Max size and Edge Cases › Oversized hosted content
entries, which point back here rather than repeating this rationale.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |

Statuses rest on `SettingsPanelViewController.swift` itself: it composes
only native `NSViewController`/`NSHostingView` APIs, never reimplementing
their layout (`native-controls-preference`: passed), but it sets no
accessibility role or label of its own — that responsibility belongs to the
`GroupView`s and SwiftUI content a subclass hosts — so `screen-reader-support`
is only `partial` here, not exercised or violated by this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `SettingsPanelViewController` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case and updated every citation; reformatted Design Decisions to the bold form; corrected the WinUI 3 hosting-size note (no `SizeToContent` in WinUI 3) and split its bullet; marked screen-reader-support and differentiate-without-color partial instead of passed; deduplicated the `.standardBounds`/`.intrinsicContentSize` rationale into Design Decisions; made spvc-001/003 compile-time checks and gave spvc-008 a concrete expected result; rewrote bare Edge Cases MUSTs as requirement citations; moved the platform-design-languages reference into `related` and added `panel-view` to `depends-on`; removed template-residue text; title-cased Compliance categories; ran the compliance-catalog cleanup. |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/. |
