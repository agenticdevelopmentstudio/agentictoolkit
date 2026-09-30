<!-- leaf: implement-general-view-1/help-content-view · source: help-content-view.md -->

**Rules** (cite as `implement-general-view-1/help-content-view#<slug>`):

- `fixed-help-heading` MUST
- `independently-scrolling-content` MUST
- `topic-groups` MUST
- `empty-state` MUST
- `wholesale-replacement` MUST
- `scroll-reset` MUST
- `theme-application` MUST
- `window-background` MUST
- `coder-init-unavailable` MUST

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

