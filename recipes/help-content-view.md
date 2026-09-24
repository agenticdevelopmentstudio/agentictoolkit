---
id: 93f50554-5ae3-4a43-b8db-539d4d804890
title: HelpContentView
domain: agentictoolkit://recipes/help-content-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A fixed "Help" heading over an independently scrolling list of HelpContent
  topics, in AppKit's ComposableSettings row style.
platforms:
- swift
- macos
tags:
- settings
- help
- macos
- appkit
depends-on:
- agentictoolkit://recipes/explanation-view
- agentictoolkit://recipes/group-view
- agentictoolkit://recipes/panel-scroll-view
- agentictoolkit://recipes/panel-view
related: []
references: []
approved-by: ''
approved-date: ''
---

# HelpContentView

## Overview

`HelpContentView`, at
`packages/apple/AgenticToolkit/macOS/UI/Help/HelpContentView.swift`, is the
content of a help drawer: a fixed "Help" heading over an independently
scrolling list of `HelpContent` topics. It is `@MainActor`-isolated and
subclasses `NSView`. Per the source's own doc comment, the topics are ordinary
`ComposableSettings.GroupView` + `ComposableSettings.ExplanationView` pairs —
the same two views the settings panels are built from — so help reads in the
same type and rhythm as the controls it describes. The source also notes this
is *only* the content: "the sliding, the edge it comes out of and the window
tracking belong to `WindowDrawer`" — this recipe covers none of that, only
the heading-over-scroll-area view itself and its `setHelp(_:)` content API.
In the toolkit's own composable settings window, `HelpContentView` is hosted
by `ComposableSettingsWindow`'s `HelpDrawerController`, which owns the drawer
chrome and feeds it the active panel's `HelpContent`.

## Behavioral Requirements

- **fixed-help-heading**: The view MUST display a label reading exactly
  `"Help"`, inset 20pt
  (`ComposableSettings.SettingsLayout.default[.panelInset]`) from the
  view's top and leading edges, and free to be narrower than the available
  width but never wider — its trailing edge never crosses the same inset
  from the view's trailing edge. See the AppKit Platform Notes bullet for
  the exact anchor equations.
- **independently-scrolling-content**: The view MUST host topic content in
  a `ComposableSettings.PanelScrollView`, positioned directly below the
  heading with no gap, and spanning the view's full leading/trailing/bottom
  edges with no inset, so the heading stays fixed on screen while the topic
  content beneath it scrolls independently. See the AppKit Platform Notes
  bullet for the exact anchor equations.
- **topic-groups**: For each `HelpContent.Topic` in
  `content.topics`, the view MUST add one `ComposableSettings.GroupView`
  titled with the topic's `title`, containing exactly one
  `ComposableSettings.ExplanationView` showing the topic's `body`, to the
  scrolled panel, in the same order the `topics` array provides.
- **empty-state**: When `setHelp(_:)` is called with
  `nil`, or with a `HelpContent` whose `topics` array is empty, the view
  MUST display exactly one group titled `"No Help Yet"` containing one
  `ExplanationView` with the fixed sentence "This panel doesn't have any
  help written for it. Its controls each carry their own explanation
  underneath." — instead of leaving the scroll area blank.
- **wholesale-replacement**: Each call to `setHelp(_:)`
  MUST discard every previously displayed `GroupView`/`ExplanationView` and
  build an entirely new `ComposableSettings.PanelView` from the given
  content, rather than diffing or mutating the views from a prior call.
- **scroll-reset**: Each call to `setHelp(_:)`
  MUST return the visible scroll position to the top of the content, because
  it installs the new panel through
  `PanelScrollView.setContent(_:)`, which removes the document view's prior
  subviews and re-pins the new one from the document's top edge.
- **theme-application**: The view MUST resolve and apply
  the current `SemanticPalette` immediately when constructed, and again on
  every subsequent theme change (via `ThemePaletteObserver`), updating: the
  view's own layer background color, the heading label's font, and the
  heading label's text color.
- **window-background**: The view's background layer color MUST be set to
  `palette.windowBackgroundColor` — the same ground as the window and
  drawer around it — per the source's own theming comment, so that the
  topic cards (`GroupView`'s elevated-surface fill) are what visibly stand
  out, rather than a heading-shaped band of a second, near-identical color
  above them.
- **coder-init-unavailable**: The view MUST NOT support
  construction via `init(coder:)`; that initializer is marked
  `@available(*, unavailable)` and MUST trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable to `HelpContentView` itself — it is a
  plain `NSView` with `wantsLayer = true` but no `cornerRadius` set on its
  own layer anywhere in source. (The rounded corners visible on each topic
  card belong to `GroupView`'s `cardView`, at
  `SettingsLayout.default[.cardCornerRadius]` — 10pt — which is `GroupView`'s
  concern, not this file's.)
- **Padding**: The heading label is inset 20pt
  (`SettingsLayout.default[.panelInset]`) from the view's top and leading
  edges, and constrained to stay at least 20pt from the trailing edge. The
  scroll view below it has zero inset on its leading, trailing, and bottom
  edges, and starts exactly at the heading label's bottom edge with no
  additional vertical gap constant of its own — any visible gap between
  "Help" and the first topic card comes from `PanelView`'s own 20pt top
  inset inside the scrolled content, not from a spacing value in
  `HelpContentView.swift` (see Design Decisions).
- **Font**: The heading label uses `palette.font(.heading)` — the theme's
  `.heading` text role, which defaults to 15pt semibold
  (`ThemeTypography.defaultStyle(.heading)`) and scales with the active
  theme's `sizeScale`. Topic titles and bodies are styled entirely by
  `GroupView`'s header (`.secondaryText`/`.caption`) and by
  `ExplanationView` (`.secondaryText`/`.caption`); `HelpContentView.swift`
  sets no font of its own for either.
- **Background**: The view's own layer background color is
  `palette.windowBackgroundColor`. `PanelScrollView` draws no background of
  its own (`drawsBackground = false`), so this color shows through the
  entire scroll area; `PanelView` separately paints its own layer with the
  same `windowBackgroundColor` via its own `ThemePaletteObserver`.
- **Foreground/Text**: The heading label's text color is
  `palette.primaryTextColor`.
- **Border**: None — no border is drawn or configured anywhere in
  `HelpContentView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `HelpContentView.swift`.
- **Min/Max size**: None declared on `HelpContentView` itself — no explicit
  width or height constraint appears in source. The view fills whatever
  frame its container (the drawer) gives it; topic content that exceeds
  that frame's height scrolls rather than being clipped or truncated
  (`independently-scrolling-content`).

## States

| State | Appearance change |
|-------|------------------|
| Default | Heading reads "Help"; scroll area shows whatever `setHelp(_:)` was last called with. |
| Empty (`setHelp(nil)` or empty `topics`) | Scroll area shows the single "No Help Yet" group — see **empty-state**. |
| Populated (one or more topics) | Scroll area shows one `GroupView` per topic, in array order — see **topic-groups**. |
| Pressed | Not applicable: `HelpContentView.swift` defines no target/action, gesture recognizer, or tracking area of its own; it is a non-interactive content view. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: `HelpContentView` never becomes key/first responder itself; the source overrides no responder-chain behavior, and any keyboard focus lands on the scroll view's own default targets, not on this view. |
| Loading | Not applicable: `setHelp(_:)` is synchronous; the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: Not customized beyond AppKit's defaults — no explicit
  accessibility role, trait, or heading designation appears anywhere in
  `HelpContentView.swift`. The heading label is `NSTextField(labelWithString:)`,
  which AppKit exposes to assistive technology as static text by default;
  `titleLabel` is never given `setAccessibilityRole(.staticText)` with a
  heading subrole, nor any other heading designation
  (`HelpContentView.swift`, `:31-32`), so AppKit's default static-text
  role does not by itself announce to VoiceOver's rotor that "Help" is a
  section heading over the topic list below it. The topic titles/bodies
  inherit whatever `GroupView`/`ExplanationView` expose on their own.
- **Label requirements**: Satisfied for the fixed heading — it always reads
  the literal string `"Help"` (**fixed-help-heading**). Per-topic
  labeling is `GroupView`'s and `ExplanationView`'s responsibility, not this
  file's; `ExplanationView`'s own recipe
  (`agentictoolkit://recipes/explanation-view`) covers its label behavior.
- **Announce state changes (e.g., loading, disabled)**: `setHelp(_:)` tears
  down and rebuilds the entire scrolled panel with no
  `NSAccessibility.post(element:notification:)` call and no explicit focus
  move to the new content anywhere in `HelpContentView.swift`,
  `PanelScrollView.swift`, or `PanelView.swift`, so nothing in source
  announces to a VoiceOver user that the drawer's content just changed
  (e.g., when the reader switches settings panels and the drawer refreshes
  behind them).
- **Minimum tap target**: Not applicable — `HelpContentView` defines no
  button, control, or click handler of its own; it is a non-interactive
  content view. (The scroll view it hosts uses `NSScrollView`'s standard
  hit-testing, which this file does not customize.)
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The heading label's color is `palette.primaryTextColor`, which `SemanticPalette` resolves as the theme's raw `foreground` color with no enforced minimum-contrast floor (unlike `.secondaryText`, which is explicitly dimmed toward the background with a `minContrast: 3.0` clamp); whether `primaryTextColor` reaches WCAG AA's 4.5:1 ratio against `windowBackgroundColor` for every theme this component ships with cannot be determined from `HelpContentView.swift` or `SemanticPalette.swift` alone — it depends on each theme's concrete foreground/background color pair and would be settled by auditing the computed contrast ratio per theme.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| help-content-view-001 | fixed-help-heading | Construct `HelpContentView()` | A subview with `stringValue == "Help"` exists, pinned 20pt from the view's top and leading edges, outside the scroll view's document |
| help-content-view-002 | independently-scrolling-content | Call `setHelp` with topics whose combined height exceeds the view's frame, then scroll the document | The heading label's frame is unchanged while the visible topic content scrolls |
| help-content-view-003 | topic-groups | `setHelp(HelpContent(topics: [Topic(title: "A", body: "a"), Topic(title: "B", body: "b")]))` | The panel contains exactly 2 `GroupView`s in order, titled "A" then "B", each with one `ExplanationView` whose text matches the topic's `body` |
| help-content-view-004 | empty-state | `setHelp(nil)` | The panel contains exactly 1 `GroupView` titled "No Help Yet" with one `ExplanationView` reading the fixed empty-state sentence |
| help-content-view-005 | empty-state | `setHelp(HelpContent(topics: []))` | Same result as help-content-view-004 |
| help-content-view-006 | wholesale-replacement | Call `setHelp` with topic set A, then call it again with topic set B | After the second call, none of topic set A's `GroupView`/`ExplanationView` instances remain in the panel; only topic set B's are present |
| help-content-view-007 | scroll-reset | Call `setHelp` with tall content, scroll to the bottom, then call `setHelp` again with new content | The scroll view's visible origin is back at the top immediately after the second call returns |
| help-content-view-008 | theme-application, window-background | Construct `HelpContentView()` while Theme A is active | `layer.backgroundColor == ThemeA.windowBackgroundColor.cgColor` (not a distinct or hardcoded color); `titleLabel.font == ThemeA.font(.heading)`; `titleLabel.textColor == ThemeA.primaryTextColor` |
| help-content-view-009 | theme-application | With the view constructed under Theme A, switch the active theme to Theme B | All three properties from help-content-view-008 update to Theme B's values without re-constructing the view |
| help-content-view-010 | coder-init-unavailable | Compile `HelpContentView(coder: someCoder)` at any call site | The line fails to compile — `init(coder:)` is marked `@available(*, unavailable)`. This is a compile-time/availability check, not a runtime trap, and is not automatable via a runtime test harness. |

## Edge Cases

- **Null/empty input**: `setHelp(nil)` and `setHelp(HelpContent(topics: []))`
  both MUST produce the identical single-group empty state (see
  **empty-state**; help-content-view-004,
  help-content-view-005) — `content?.topics ?? []` treats a `nil` content
  and an empty `topics` array as the same case.
- **Boundary values**: Not applicable in the numeric-input sense — the
  source enforces no minimum or maximum topic count. A `HelpContent` with
  one topic and one with a hundred topics both render every topic
  (**topic-groups**); the scroll view grows to fit any
  count rather than clipping it.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`content`
  from off the main actor, so there is no concurrent-access surface to
  define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `HelpContentView`
  performs no network operation of its own.
- **Rapid, repeated `setHelp(_:)` calls**: Each call independently tears
  down and rebuilds the panel (**wholesale-replacement**);
  the source contains no debouncing, coalescing, or in-flight guard, so N
  calls in quick succession perform N full rebuilds.
- **`setHelp(_:)` called with an unchanged, equal `HelpContent`**: The
  source performs no equality check against the previously stored
  `content` before rebuilding — even though `HelpContent` is `Equatable` —
  so passing back the same value still discards and rebuilds every group
  and explanation view (**wholesale-replacement**).
- **Very long single topic body**: `ExplanationView` wraps and grows
  vertically with no line limit (per its own recipe), so a very long body
  makes its `GroupView` taller and pushes later groups further down the
  scrollable content; nothing in `HelpContentView.swift` truncates or
  limits it.
- **Constructing via `init(frame:)`**: Not possible. `HelpContentView`
  declares its own designated initializer, `public init()`, and overrides
  none of `NSView`'s designated initializers, so under Swift's initializer
  inheritance rules it inherits neither `init(frame:)` nor `init(coder:)`;
  `HelpContentView(frame:)` does not compile. Unlike sibling
  `ComposableSettings` row views (e.g. `ExplanationView`,
  `DisclosureCardView`), it needs no fatal-error override to block that path —
  `init()` is the only way to build one, and it always installs the title
  label, scroll view, and theme observer.

## Configuration

`HelpContentView`
(`packages/apple/AgenticToolkit/macOS/UI/Help/HelpContentView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `content` | `HelpContent?` | — (required argument; `nil` is a valid, explicit value) | The topics to display, passed to `setHelp(_:)`. `nil` or an empty `topics` array both show the fixed empty state. |

```swift
public init()
public func setHelp(_ content: HelpContent?)
```

`HelpContent` (`packages/apple/AgenticToolkit/macOS/UI/Help/HelpContent.swift`)
is `Sendable`/`Equatable` and holds an ordered array of `Topic`, each a
`title`/`body` string pair.

## Deep Linking

Not applicable: `HelpContentView` is content hosted inside a drawer, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `HelpContentView.swift`. Presenting or dismissing the drawer
itself belongs to `WindowDrawer`/`HelpDrawerController`, outside this
recipe's source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | `Help` | Fixed heading label, set via `NSTextField(labelWithString:)` |
| — (hardcoded literal, no key) | `No Help Yet` | Empty-state group title, shown when `setHelp(_:)` receives `nil` or no topics |
| — (hardcoded literal, no key) | `This panel doesn't have any help written for it. Its controls each carry their own explanation underneath.` | Empty-state explanation body |
| — (caller-supplied, no key in this file) | n/a | `HelpContent.Topic.title` / `.body` for a non-empty topic list — every heading and prose string is supplied by the caller, not a literal in `HelpContentView.swift` |

`NSTextField(labelWithString:)` sets `stringValue` from a Swift string
literal directly; unlike a SwiftUI `Text` literal (a `LocalizedStringKey`),
an AppKit `stringValue` set this way is not itself localizable, and no
`NSLocalizedString` lookup or string-catalog reference appears anywhere in
`HelpContentView.swift` for the three literals above.

## Accessibility Options

- Reduce Motion: Not applicable — `HelpContentView.swift` contains no
  animation, transition, or `NSAnimationContext`/`CATransaction` call.
  Content replacement and theme recoloring are both synchronous property
  and layer-color assignments, not a motion effect.
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
gate; `HelpContentView` renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the view holds only the `HelpContent` struct
  (topic titles and bodies) passed to it by the caller; it originates no
  data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: The most recently set `content` is held in memory as a
  private stored property for the view's own lifetime, and is replaced (not
  appended to) on every subsequent `setHelp(_:)` call; nothing persists
  across app launches.

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in `HelpContentView.swift`).

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
  built from `GroupView`/`ExplanationView` rows. A UIKit port replaces
  `NSTextField` with a `UILabel`, `PanelScrollView`/`PanelView` with a
  `UIScrollView` hosting a `UIStackView` of card views, and
  `ThemePaletteObserver`'s AppKit-side theme-change notification with
  UIKit's own trait-collection/theme-change hook. The constraint equations
  behind **fixed-help-heading** and **independently-scrolling-content**:
  `titleLabel.topAnchor == self.topAnchor + inset`,
  `titleLabel.leadingAnchor == self.leadingAnchor + inset`,
  `titleLabel.trailingAnchor <= self.trailingAnchor - inset`,
  `scrollView.topAnchor == titleLabel.bottomAnchor`, and
  `scrollView`'s leading/trailing/bottom anchors each equal to `self`'s
  with no constant, where `inset` is
  `ComposableSettings.SettingsLayout.default[.panelInset]` (20pt).
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

## Design Decisions

- **Decision**: `HelpContentView` composes `GroupView` and `ExplanationView`
  — types that still live under the `ComposableSettings` namespace — for
  help content, not settings.
  **Rationale**: the source's own doc comment states this is "the same two
  views the settings panels are built from," so help reads in the same
  type and rhythm as the controls it describes, and states plainly that the
  `ComposableSettings` naming for these shared views "is a naming debt, not
  a layering one (it is all one framework), and paying it off is a larger
  change than this file should make."
  **Approved: pending**
- **Decision**: When `setHelp(_:)` is given `nil` or an empty topics list,
  the view shows a fixed "No Help Yet" group instead of closing the drawer
  or leaving the scroll area blank.
  **Rationale**: the source's own doc comment on `emptyTitle`/`emptyBody`
  explains that the drawer previously closed itself in this case, which
  "made it slam shut on the way to a panel with nothing to say and slide
  open again on the way out, an animation nobody asked for that reads as
  the window flinching," and concludes "an honest sentence beats an empty
  pane that reads as a rendering failure."
  **Approved: pending**
- **Decision**: The view's background layer is painted with
  `palette.windowBackgroundColor` — the same color as the window and drawer
  around it — rather than a distinct background.
  **Rationale**: the source's inline comment states this is deliberate so
  that "the cards are what should stand out" and a heading-shaped band of a
  second near-identical grey above them "only reads as a misprint."
  **Approved: pending**
- **Decision**: `setHelp(_:)` always tears down and rebuilds the entire
  panel from scratch, with no comparison against the previously stored
  `content`, even though `HelpContent` is `Equatable`.
  **Rationale**: not stated in source; inferred from the absence of any
  equality check or partial-update path. `setHelp(_:)` is called only when
  the panel/topic selection changes — `SplitViewController.show(_:)` and
  `refreshHelp()`, in
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift`,
  are the only call sites (reached through `PanelHostView` and
  `HelpDrawerController.setHelp(_:)`), and both fire from the reader
  changing which panel or topic is selected — not on a hot or
  performance-sensitive path, so a full rebuild is the simplest correct
  behavior rather than a documented optimization trade-off.
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
