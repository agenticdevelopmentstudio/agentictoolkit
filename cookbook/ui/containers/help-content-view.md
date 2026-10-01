---
id: 93f50554-5ae3-4a43-b8db-539d4d804890
title: Help Content View
domain: agentictoolkit://cookbook/ui/containers/help-content-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A fixed "Help" heading over an independently scrolling list of help topics,
  styled in the same row style as the rest of the settings.
platforms:
- swift
- macos
tags:
- settings
- help
depends-on:
- agentictoolkit://cookbook/ui/settings/layout/explanation-view
- agentictoolkit://cookbook/ui/settings/layout/group-view
- agentictoolkit://cookbook/ui/settings/layout/panel-scroll-view
- agentictoolkit://cookbook/ui/settings/layout/panel-view
related: []
references: []
approved-by: ''
approved-date: ''
---

# Help Content View

## Overview

This is the content of a help drawer: a fixed "Help" heading over an
independently scrolling list of help topics. Per the concept's own
rationale, the topics are ordinary Group View + Explanation View pairs — the
same two views the settings panels are built from — so help reads in the
same type and rhythm as the controls it describes. This recipe covers only
the heading-over-scroll-area view itself and its content-setting operation;
the sliding, the edge it comes out of, and the window tracking belong to the
drawer that hosts it. In the toolkit's own composable settings window, this
content is hosted inside a drawer controller that owns the drawer chrome and
feeds it the active panel's help content.

## Behavioral Requirements

- **fixed-help-heading**: Component MUST display a label reading exactly
  `"Help"`, inset 20pt from the view's top and leading edges, and free to be
  narrower than the available width but never wider — its trailing edge
  never crosses the same inset from the view's trailing edge. See Platform Notes for the exact anchor equations and the
  literal inset constant's source.
- **independently-scrolling-content**: Component MUST host topic content in
  a scrollable panel, positioned directly below the heading with no gap,
  and spanning the view's full leading/trailing/bottom edges with no
  inset, so the heading stays fixed on screen while the topic content
  beneath it scrolls independently. See Platform Notes for the exact anchor equations.
- **topic-groups**: For each topic in the supplied content, Component MUST
  add one Group View titled with the topic's `title`, containing exactly
  one Explanation View showing the topic's `body`, to the scrolled panel,
  in the same order the topics array provides.
- **empty-state**: When the content-setting operation is called with no
  content, or with content whose topics array is empty, Component MUST
  display exactly one group titled `"No Help Yet"` containing one
  explanation row with the fixed sentence "This panel doesn't have any
  help written for it. Its controls each carry their own explanation
  underneath." — instead of leaving the scroll area blank.
- **wholesale-replacement**: Each call to the content-setting operation
  MUST discard every previously displayed group/explanation row and build
  an entirely new panel from the given content, rather than diffing or
  mutating the views from a prior call.
- **scroll-reset**: Each call to the content-setting operation MUST return
  the visible scroll position to the top of the content.
- **theme-application**: Component MUST resolve and apply the current
  `SemanticPalette` immediately when constructed, and again on every
  subsequent theme change, updating: the view's own background color, the
  heading label's font, and the heading label's text color.
- **window-background**: Component's background color MUST be set to the
  theme's `windowBackgroundColor` — the same ground as the window and
  drawer around it — so that the topic cards (a Group View's
  elevated-surface fill) are what visibly stand out, rather than a
  heading-shaped band of a second, near-identical color above them.
- **coder-init-unavailable**: See Platform Notes.

## Appearance

- **Corner radius**: Not applicable to this component itself — it has no
  corner radius set of its own anywhere in source. (The rounded corners
  visible on each topic card belong to a Group View's own card surface —
  10pt — which is that component's concern, not this file's.)
- **Padding**: The heading label is inset 20pt from the view's top and
  leading edges, and constrained to stay at least 20pt from the trailing
  edge. The scroll view below it has zero inset on its leading, trailing,
  and bottom edges, and starts exactly at the heading label's bottom edge
  with no additional vertical gap constant of its own — any visible gap
  between "Help" and the first topic card comes from the panel's own 20pt
  top inset inside the scrolled content, not from a spacing value in this
  component's own source (see Design Decisions).
- **Font**: The heading label uses the theme's `.heading` text role, which
  defaults to 15pt semibold and scales with the active theme's size scale.
  Topic titles and bodies are styled entirely by a Group View's own header
  (`.secondaryText`/`.caption`) and by an Explanation View
  (`.secondaryText`/`.caption`); this component sets no font of its own for
  either.
- **Background**: The view's own background color is the theme's
  `windowBackgroundColor`. The scroll panel draws no background of its
  own, so this color shows through the entire scroll area; the inner panel
  separately paints its own background with the same `windowBackgroundColor`,
  kept in sync by the same theme-change mechanism.
- **Foreground/Text**: The heading label's text color is
  `palette.primaryTextColor`.
- **Border**: None — no border is drawn or configured anywhere in this
  component's own source.
- **Shadow**: None — no shadow is drawn or configured anywhere in this
  component's own source.
- **Min/Max size**: None declared on this component itself — no explicit
  width or height constraint appears in source. The view fills whatever
  frame its container (the drawer) gives it; topic content that exceeds
  that frame's height scrolls rather than being clipped or truncated
  (`independently-scrolling-content`).

## States

| State | Appearance change |
|-------|------------------|
| Default | Heading reads "Help"; scroll area shows whatever the content-setting operation was last called with. |
| Empty (no content, or an empty topics list) | Scroll area shows the single "No Help Yet" group — see **empty-state**. |
| Populated (one or more topics) | Scroll area shows one group per topic, in array order — see **topic-groups**. |
| Pressed | Not applicable: this component defines no target/action, gesture recognizer, or tracking area of its own; it is a non-interactive content view. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: this component never becomes key/first responder itself; the source overrides no responder-chain behavior, and any keyboard focus lands on the scroll view's own default targets, not on this view. |
| Loading | Not applicable: the content-setting operation is synchronous; the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: Not customized beyond the platform's defaults — no
  explicit accessibility role, trait, or heading designation appears
  anywhere in this component's source. The heading label is a plain text
  label, which the platform exposes to assistive technology as static text
  by default; it is never given a heading-level accessibility designation,
  so the platform's default static-text role does not by itself announce
  to a screen reader's navigation that "Help" is a section heading over the
  topic list below it.
- **Label requirements**: Satisfied for the fixed heading — it always reads
  the literal string `"Help"` (**fixed-help-heading**). Per-topic labeling
  is a Group View's and an Explanation View's responsibility, not this
  file's; the Explanation View's own recipe
  (`agentictoolkit://cookbook/ui/settings/layout/explanation-view`) covers
  its label behavior.
- **Announce state changes (e.g., loading, disabled)**: The content-setting
  operation tears down and rebuilds the entire scrolled panel with no
  accessibility notification and no explicit focus move to the new content
  anywhere in source, so nothing announces to a screen reader user that the
  drawer's content just changed (e.g., when the reader switches settings
  panels and the drawer refreshes behind them).
- **Minimum tap target**: Not applicable — this component defines no
  button, control, or click handler of its own; it is a non-interactive
  content view. (The scroll view it hosts uses the platform's standard
  hit-testing, which this file does not customize.)
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The heading label's color is the theme's `primaryTextColor`, which `SemanticPalette` resolves as the theme's raw foreground color with no enforced minimum-contrast floor (unlike `.secondaryText`, which is explicitly dimmed toward the background with a `minContrast: 3.0` clamp); whether `primaryTextColor` reaches WCAG AA's 4.5:1 ratio against `windowBackgroundColor` for every theme this component ships with cannot be determined from source alone — it depends on each theme's concrete foreground/background color pair and would be settled by auditing the computed contrast ratio per theme.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| help-content-view-001 | fixed-help-heading | Construct the component | A label with text exactly "Help" exists, pinned 20pt from the view's top and leading edges, outside the scroll view's document |
| help-content-view-002 | independently-scrolling-content | Set help content whose combined height exceeds the view's frame, then scroll the document | The heading label's frame is unchanged while the visible topic content scrolls |
| help-content-view-003 | topic-groups | Set help content with topics [(title: "A", body: "a"), (title: "B", body: "b")] | The panel contains exactly 2 groups in order, titled "A" then "B", each with one explanation row whose text matches the topic's `body` |
| help-content-view-004 | empty-state | Set help content to no content | The panel contains exactly 1 group titled "No Help Yet" with one explanation row reading the fixed empty-state sentence |
| help-content-view-005 | empty-state | Set help content to content with an empty topics list | Same result as help-content-view-004 |
| help-content-view-006 | wholesale-replacement | Set help content to topic set A, then set it again to topic set B | After the second call, none of topic set A's groups/explanation rows remain in the panel; only topic set B's are present |
| help-content-view-007 | scroll-reset | Set help content to tall content, scroll to the bottom, then set help content again to new content | The scroll view's visible origin is back at the top immediately after the second call returns |
| help-content-view-008 | theme-application, window-background | Construct the component while Theme A is active | Background color equals Theme A's `windowBackgroundColor` (not a distinct or hardcoded color); heading font equals Theme A's `.heading` font; heading text color equals Theme A's `primaryTextColor` |
| help-content-view-009 | theme-application | With the component constructed under Theme A, switch the active theme to Theme B | All three properties from help-content-view-008 update to Theme B's values without re-constructing the view |

`coder-init-unavailable` has no test vector: see Platform Notes for how it is verified.

## Edge Cases

- **Null/empty input**: Setting help content to no content, and setting it
  to content with an empty topics list, both MUST produce the identical
  single-group empty state (see **empty-state**;
  help-content-view-004, help-content-view-005) — the two are
  treated as the same case.
- **Boundary values**: Not applicable in the numeric-input sense — the
  source enforces no minimum or maximum topic count. Content with one
  topic and content with a hundred topics both render every topic
  (**topic-groups**); the scroll view grows to fit any
  count rather than clipping it.
- **Concurrent access**: Not applicable — this component is confined to a
  single thread of execution for its entire lifetime, so there is no
  concurrent-access surface to define behavior for. See Platform Notes for how that confinement is enforced.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — this component performs
  no network operation of its own.
- **Rapid, repeated content-setting calls**: Each call independently tears
  down and rebuilds the panel (**wholesale-replacement**); the source
  contains no debouncing, coalescing, or in-flight guard, so N calls in
  quick succession perform N full rebuilds.
- **Content-setting called with an unchanged, equal content value**: The
  source performs no equality check against the previously stored content
  before rebuilding — even though the content type supports equality
  comparison — so passing back the same value still discards and rebuilds
  every group and explanation view (**wholesale-replacement**).
- **Very long single topic body**: An Explanation View wraps and grows
  vertically with no line limit (per its own recipe), so a very long body
  makes its group taller and pushes later groups further down the
  scrollable content; nothing in this component's own source truncates or
  limits it.
- **Constructing via a frame-only initializer**: Not possible. This
  component declares its own single way to construct it, with no supported
  frame-only construction path, and unlike some sibling row views it needs
  no fatal-error guard to block that path — its constructor is the only way
  to build one, and it always installs the title label, scroll view, and
  theme observer. See Platform Notes for why the
  language's own initializer-inheritance rules make this true without an
  explicit guard.

## Configuration

Construction options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `content` | `HelpContent?` | — (required argument; `nil` is a valid, explicit value) | The topics to display, passed to the content-setting operation. `nil` or an empty topics array both show the fixed empty state. |

Beyond construction with no arguments, the component exposes one operation:
setting (or clearing) its help content.

The content type holds an ordered array of topics, each a `title`/`body`
string pair, and supports equality comparison.

## Deep Linking

Not applicable: this component is content hosted inside a drawer, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in its source. Presenting or dismissing the drawer itself belongs
to the window drawer that hosts it, outside this recipe's source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | `Help` | Fixed heading label |
| — (hardcoded literal, no key) | `No Help Yet` | Empty-state group title, shown when the content-setting operation receives no content or no topics |
| — (hardcoded literal, no key) | `This panel doesn't have any help written for it. Its controls each carry their own explanation underneath.` | Empty-state explanation body |
| — (caller-supplied, no key in this file) | n/a | Each topic's `title`/`body` for a non-empty topic list — every heading and prose string is supplied by the caller, not a literal in this component's own source |

The heading label is set directly from a fixed string, not through any
localization lookup mechanism, and no localization-catalog reference
appears anywhere in source for the three literals above.

## Accessibility Options

- Reduce Motion: Not applicable — this component's source contains no
  animation or transition call. Content replacement and theme recoloring
  are both synchronous property and color assignments, not a motion
  effect.
- Increase Contrast: Not applicable in this file — every color comes from
  the active `SemanticPalette` (`windowBackgroundColor`, `primaryTextColor`);
  if Increase Contrast should raise these colors' contrast, that is the
  palette's responsibility, not this view's. The open question on
  minimum-contrast-ratio is tracked once, under Accessibility above.
- Differentiate Without Color: Not applicable — the view conveys no state
  through color; it renders a fixed heading and caller-supplied topic text,
  with no color-coded meaning to differentiate.

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; this component renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the view holds only the content struct (topic
  titles and bodies) passed to it by the caller; it originates no data of
  its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: The most recently set content is held in memory as a
  private stored property for the view's own lifetime, and is replaced (not
  appended to) on every subsequent content-setting call; nothing persists
  across app launches.

## Logging

Not applicable: no logging call appears anywhere in this component's own
source.

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 0)` with a
  fixed `Text("Help").font(.headline)` (or a themed heading style) as the
  first child, and a `ScrollView { LazyVStack(alignment: .leading) {
  ForEach(topics) { topic in ... } } }` below it — the `VStack`'s own
  layout keeps the heading outside the `ScrollView`'s scroll content the
  same way `titleLabel` sits outside `PanelScrollView` here. Render each
  topic as a card-styled `GroupBox` or custom container plus a wrapping
  `Text` for the body, mirroring `GroupView` + `ExplanationView`. Show the
  fixed "No Help Yet" card when the topics array is empty, and drive the
  whole scroll content from a single `@State`/bound `HelpContent?` so
  reassigning it fully replaces the `ForEach` content the way
  `setHelp(_:)` does.
- **Compose**: Use a `Column { Text("Help", style =
  MaterialTheme.typography.titleMedium); Column(Modifier.verticalScroll(...))
  { topics.forEach { ... } } }` (or `LazyColumn` for long lists) — the
  outer `Column`'s heading stays fixed above the scrollable inner content
  the same way the AppKit heading sits above `PanelScrollView`. Render each
  topic as an `ElevatedCard` containing a title `Text` and a wrapping body
  `Text`, Compose's analog of `GroupView`/`ExplanationView`; recomposing
  with a new topics list naturally replaces the scrolled content the way
  `setHelp(_:)` rebuilds the panel.
- **React/Web**: A flex column with a non-scrolling `<h2>Help</h2>` header
  and a sibling `<div style="overflow-y: auto; flex: 1">` beneath it
  holding one card component per topic (a heading plus wrapping prose),
  re-rendered from whatever list state backs `content`; render a single
  "No Help Yet" card when that list is empty, and reset
  `scrollTop = 0` on the scrollable container whenever the topic list
  changes, mirroring **scroll-reset**.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/UI/Help/HelpContentView.swift` (this
  recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, composing one `NSTextField` heading with a
  `ComposableSettings.PanelScrollView` hosting a `ComposableSettings.PanelView`
  built from `GroupView`/`ExplanationView` rows. The class fails with a
  fatal error if constructed via `init(coder:)`, marked
  `@available(*, unavailable)` (`coder-init-unavailable`). It declares its
  own designated initializer, `public init()`, and overrides none of
  `NSView`'s designated initializers, so under Swift's initializer
  inheritance rules it inherits neither `init(frame:)` nor `init(coder:)` —
  `HelpContentView(frame:)` does not compile, and (unlike sibling
  `ComposableSettings` row views such as `ExplanationView` or
  `DisclosureCardView`) it needs no fatal-error override to block that path,
  since `init()` is the only initializer Swift synthesizes access to. It is
  a plain `NSView` with `wantsLayer = true` but no `cornerRadius` set on its
  own layer; the topic card's own rounding is
  `SettingsLayout.default[.cardCornerRadius]` (10pt), and the heading/scroll
  inset is `SettingsLayout.default[.panelInset]` (20pt). The heading font is
  `palette.font(.heading)`, which defaults to
  `ThemeTypography.defaultStyle(.heading)` (15pt semibold) and scales with
  `sizeScale`. `PanelScrollView` draws no background of its own
  (`drawsBackground = false`); `PanelView` separately paints its own layer
  with `windowBackgroundColor` via its own `ThemePaletteObserver` instance —
  this view resolves and reapplies `SemanticPalette` the same way, on
  `ThemePaletteObserver`'s theme-change notification. The heading label is
  `NSTextField(labelWithString:)`, which AppKit exposes to assistive
  technology as static text by default; `titleLabel` is never given
  `setAccessibilityRole(.staticText)` with a heading subrole
  (`HelpContentView.swift`, `:31-32`). Content replacement calls
  `PanelScrollView.setContent(_:)`, which removes the document view's prior
  subviews and re-pins the new one from the document's top edge (producing
  `scroll-reset` as a side effect), and posts no
  `NSAccessibility.post(element:notification:)` call anywhere in
  `HelpContentView.swift`, `PanelScrollView.swift`, or `PanelView.swift`.
  `HelpContent` (`HelpContent.swift`) is `Sendable`/`Equatable` and holds an
  ordered array of `Topic`, each a `title`/`body` string pair.
  `NSTextField(labelWithString:)` sets `stringValue` from a Swift string
  literal directly; unlike a SwiftUI `Text` literal (a `LocalizedStringKey`),
  an AppKit `stringValue` set this way is not itself localizable, and no
  `NSLocalizedString` lookup or string-catalog reference appears anywhere in
  source. No `NSAnimationContext`/`CATransaction` call appears in source
  either. A UIKit port replaces `NSTextField` with a `UILabel`,
  `PanelScrollView`/`PanelView` with a `UIScrollView` hosting a
  `UIStackView` of card views, and `ThemePaletteObserver`'s AppKit-side
  theme-change notification with UIKit's own trait-collection/theme-change
  hook. The constraint equations behind **fixed-help-heading** and
  **independently-scrolling-content**:
  `titleLabel.topAnchor == self.topAnchor + inset`,
  `titleLabel.leadingAnchor == self.leadingAnchor + inset`,
  `titleLabel.trailingAnchor <= self.trailingAnchor - inset`,
  `scrollView.topAnchor == titleLabel.bottomAnchor`, and
  `scrollView`'s leading/trailing/bottom anchors each equal to `self`'s
  with no constant, where `inset` is
  `ComposableSettings.SettingsLayout.default[.panelInset]` (20pt). Public API
  surface:
  ```swift
  public init()
  public func setHelp(_ content: HelpContent?)
  ```
- **WinUI 3** (the reason this recipe exists): Build this as a two-row
  `Grid`: row 0, `Auto` height, holds a `TextBlock Text="Help"` styled with
  `SubtitleTextBlockStyle` (the Fluent 2 analog of the 15pt semibold
  heading font), inset from the grid's edges by a 20px `Margin` to match
  `panelInset`; row 1, `*` height, holds a `ScrollViewer` with
  `VerticalScrollBarVisibility="Auto"` containing an `ItemsRepeater` (or
  `ItemsControl`) bound to an `ObservableCollection<Topic>`. Template each
  topic as a `Border` styled with `CardBackgroundFillColorDefaultBrush` and
  `CornerRadius="10"` (matching `cardCornerRadius`), containing a
  `TextBlock` for the title (`BodyStrongTextBlockStyle`) and a wrapping
  `TextBlock` for the body (`BodyTextBlockStyle`,
  `TextWrapping="WrapWholeWords"`) — WinUI 3's analogs of `GroupView`'s
  header and `ExplanationView`. Swap the bound collection's contents (or
  reset it to a single "No Help Yet" item) on every call that plays the
  role of `setHelp(_:)`, and call
  `scrollViewer.ChangeView(null, 0, null, true)` immediately after, to
  reproduce **scroll-reset** — `ItemsRepeater`
  does not reset scroll position on its own the way `PanelScrollView`'s
  `setContent(_:)` does. Bind `Border.Background` (the topic card) to
  `{ThemeResource LayerFillColorDefaultBrush}` and `TextBlock.Foreground`
  to `{ThemeResource TextFillColorPrimaryBrush}`, but bind the outer
  `Grid`'s own `Background` to `{ThemeResource
  SolidBackgroundFillColorBaseBrush}` — the window's own ground, not a
  distinct layer color — to reproduce **window-background**: the cards
  read as elevated only because the grid behind them matches the window,
  the same way `windowBackgroundColor` does here. Bind all three through
  `{ThemeResource}` rather than a fixed color, so `RequestedTheme`/
  light-dark changes repaint automatically the way `ThemePaletteObserver`
  repaints this view on every theme change.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/Help/HelpContentView.swift` |

## Design Decisions

- **Decision**: This component composes a Group View and an Explanation
  View — types that still live under the `ComposableSettings` namespace —
  for help content, not settings.
  **Rationale**: the source's own doc comment states this is "the same two
  views the settings panels are built from," so help reads in the same
  type and rhythm as the controls it describes, and states plainly that the
  `ComposableSettings` naming for these shared views "is a naming debt, not
  a layering one (it is all one framework), and paying it off is a larger
  change than this file should make." (Applies to the AppKit implementation.)
  **Approved: pending**
- **Decision**: When the content-setting operation is given no content or
  an empty topics list, the view shows a fixed "No Help Yet" group instead
  of closing the drawer or leaving the scroll area blank.
  **Rationale**: the source's own doc comment on `emptyTitle`/`emptyBody`
  explains that the drawer previously closed itself in this case, which
  "made it slam shut on the way to a panel with nothing to say and slide
  open again on the way out, an animation nobody asked for that reads as
  the window flinching," and concludes "an honest sentence beats an empty
  pane that reads as a rendering failure." (Applies to the AppKit
  implementation.)
  **Approved: pending**
- **Decision**: The view's background is painted with
  `palette.windowBackgroundColor` — the same color as the window and drawer
  around it — rather than a distinct background.
  **Rationale**: the source's inline comment states this is deliberate so
  that "the cards are what should stand out" and a heading-shaped band of a
  second near-identical grey above them "only reads as a misprint."
  (Applies to the AppKit implementation.)
  **Approved: pending**
- **Decision**: The content-setting operation always tears down and
  rebuilds the entire panel from scratch, with no comparison against the
  previously stored content, even though the content type supports
  equality comparison.
  **Rationale**: not stated in source; inferred from the absence of any
  equality check or partial-update path. The content-setting operation is
  called only when the panel/topic selection changes — `SplitViewController.show(_:)` and
  `refreshHelp()`, in
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift`,
  are the only call sites (reached through `PanelHostView` and
  `HelpDrawerController.setHelp(_:)`), and both fire from the reader
  changing which panel or topic is selected — not on a hot or
  performance-sensitive path, so a full rebuild is the simplest correct
  behavior rather than a documented optimization trade-off. (Applies to the
  AppKit implementation.)
  **Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | internationalization |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | platform-compliance |

Statuses rest on: every color resolved from the active `SemanticPalette`
and re-applied on every theme change via `ThemePaletteObserver`, matching
the window's own ground rather than a fixed value (platform-theming);
`primaryTextColor` carrying no enforced minimum-contrast floor the way
`secondaryText` does, so its contrast against `windowBackgroundColor` is
unverified per-theme (contrast-ratio — see Accessibility); `setHelp(_:)`
rebuilding the panel with no accessibility notification or focus move to
announce the change (screen-reader-support — see Accessibility); the three
literal English strings ("Help", "No Help Yet", the empty-state sentence)
being set as AppKit `stringValue`s with no localization lookup anywhere in
source (no-hardcoded-strings, string-externalization — see Localization);
and every topic string being rendered as caller-supplied `NSTextField`/
`ExplanationView` text with no special-casing of its contents
(unicode-support).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `HelpContentView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case; strengthened window-background to MUST and merged its duplicate test vector into theme-application's; moved AppKit anchor equations out of requirements into the Platform Notes bullet; cited the SplitViewController call site for the wholesale-rebuild rationale instead of asserting it as fact; fixed the WinUI grid background to the window's own brush; rewrote the coder-init test vector as a compile-time/non-automatable check; corrected invalid `needs-review` compliance statuses to `partial`/`failed`; added group-view, panel-scroll-view, and panel-view to depends-on; flagged the missing heading accessibility role as an open gap; and remapped/removed Compliance rows that cited checks outside the compliance catalog. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/containers/. |
