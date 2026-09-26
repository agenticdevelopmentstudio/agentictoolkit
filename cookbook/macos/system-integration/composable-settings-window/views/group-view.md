---
id: 775f1761-f757-41d0-b51b-354a410a11f4
title: GroupView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/group-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit macOS card view drawing a captioned, rounded settings group whose
  rows are padded and hairline-divided, closing up automatically around a hidden row.
platforms:
- swift
- macos
tags:
- card
- settings
- layout
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/conditional-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/dismissible-hint-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- https://developer.apple.com/documentation/appkit/nsstackview
approved-by: ''
approved-date: ''
---

# GroupView

## Overview

`GroupView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/GroupView.swift`)
is a macOS `ComposableSettings` container: an `@MainActor` `NSView` subclass
conforming to `SettingsViewProtocol` that draws a settings group the way
System Settings draws one — a caption sitting outside and above a rounded
card, and inside the card one padded row per setting with a hairline between
them. The caption is a separate view (`HeaderView` by default, or any
caller-supplied `NSView`) positioned above `cardView`, a `ThemedBox` that
holds a vertical stack of rows. Each row added through `addSettingSubview(_:
style:)` is wrapped in a private `CardRow`, which owns the row's own padding
and the separator above it. A row whose content conforms to the file's own
`SelfHidingSettingsView` protocol (exposing `onVisibilityChange`) lets
`GroupView` collapse that row's padding and hairline when the content hides
itself, so a dismissed hint or a conditionally-hidden group member does not
leave a padded blank band or a stray divider behind — the same protocol the
sibling `ConditionalView` and `DismissibleHintView` recipes conform to for
that reason.

## Behavioral Requirements

- **card-surface**: Component MUST construct `cardView` as a `ThemedBox`
  filled with the `.elevatedSurface` role, `stroke: nil`, and corner radius
  `SettingsLayout.default[.cardCornerRadius]` (10pt, `ViewLayout.swift`).
- **card-view-access**: Component MUST expose `cardView` as a public,
  read-only property.
- **header-from-title**: The `init(withTitle:)` convenience initializer MUST
  construct a `HeaderView(title:)` from the caller-supplied string and
  forward it to `init(withHeaderView:)`.
- **arbitrary-header-view**: The designated `init(withHeaderView:)`
  initializer MUST accept any `NSView` as the group's caption, not only a
  `HeaderView`.
- **header-above-card**: Component MUST add the header view and then
  `cardView`, in that order, as arranged subviews of a vertical, leading-
  aligned `NSStackView` (`outerStack`).
- **header-card-spacing**: Component MUST set `outerStack.spacing` to
  `SettingsLayout.default[.captionSpacing]` (6pt).
- **outer-stack-edge-pinning**: Component MUST pin `outerStack`'s top,
  leading, trailing, and bottom anchors to its own corresponding edges with
  no additional constant (`pinToEdges`).
- **header-width-match**: Component MUST constrain the header view's width
  equal to `outerStack.widthAnchor`.
- **card-width-match**: Component MUST constrain `cardView`'s width equal to
  `outerStack.widthAnchor`.
- **row-area-edge-pinning**: Component MUST pin the internal `rowStack` to
  `cardView`'s top, leading, trailing, and bottom anchors with no additional
  constant (`pinToEdges`).
- **row-stacking**: Component MUST lay out rows in a vertical, leading-
  aligned stack with `0` spacing between adjacent rows.
- **autoresizing-mask-disabled**: Component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself, `outerStack`,
  `rowStack`, the header view, and `cardView`.
- **superview-width-match**: `viewDidMoveToSuperview` MUST activate a
  constraint equating `self.widthAnchor` to `parent.widthAnchor` whenever
  `self.superview` is non-nil after the move.
- **width-match-skip-without-superview**: `viewDidMoveToSuperview` MUST NOT
  activate any width constraint when `self.superview` is `nil` after the
  move.
- **row-append**: `addSettingSubview(_:style:)` MUST wrap `view` as the
  card's next row and add it to the end of the card's visible row order,
  growing the card's row count by one.
- **default-row-style**: `addSettingSubview(_:style:)` MUST default its
  `style` parameter to `.row` when the caller omits it.
- **added-row-width-match**: Component MUST constrain each newly added row's
  width equal to `rowStack.widthAnchor`.
- **self-hiding-content-wiring**: When `view` conforms to
  `SelfHidingSettingsView`, `addSettingSubview` MUST set that view's
  `onVisibilityChange` to a closure that calls the new row's
  `syncVisibility()` and then `self.updateSeparators()`.
- **separator-recompute-on-add**: `addSettingSubview` MUST recompute every
  row's separator visibility immediately after appending the new row.
- **separator-visibility**: `updateSeparators` MUST set each row's
  `showsSeparator` to `true` only when a strictly-earlier row in `rows` was
  not hidden (`hasVisiblePredecessor == true`) AND the current row's own
  `style` is `.row`; a `.continuation`-style row's `showsSeparator` MUST
  always be `false`.
- **first-row-headless**: The first row in `rows` MUST NOT show a separator
  regardless of its style, because `updateSeparators` starts
  `hasVisiblePredecessor` at `false`.
- **designated-initializer-requirement**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **main-actor-confinement**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **row-visibility-binding**: A row's own hidden state MUST always equal its
  wrapped content's hidden state.
- **row-visibility-at-construction**: A newly constructed row MUST already
  reflect its content's hidden state before construction returns.
- **separator-collapse**: When a row's separator visibility is turned off,
  its divider MUST become hidden and the space reserved for it MUST collapse
  to zero height.
- **separator-expansion**: When a row's separator visibility is turned on,
  its divider MUST become visible and the space reserved for it MUST expand
  to `SettingsLayout.default[.dividerThickness]` (1pt).
- **separator-write-idempotency**: Setting a row's separator visibility to
  its own current value MUST NOT change the divider's hidden state or the
  reserved space's height.
- **separator-inset**: A row's divider MUST be inset from the row's leading
  edge by `SettingsLayout.default[.cardHorizontalInset]` (14pt) and MUST
  reach flush to the row's trailing edge.
- **row-content-padding**: For a `.row`-style row, Component MUST inset the
  wrapped content's top edge below the divider band by
  `SettingsLayout.default[.cardVerticalInset]` (9pt), and inset the content's
  bottom edge from the row's own bottom edge by the same 9pt.
- **continuation-padding**: For a `.continuation`-style row, Component MUST
  inset the wrapped content's top edge from the divider band by `0`, while
  still applying the 9pt bottom inset.
- **row-content-horizontal-inset**: Component MUST inset the wrapped
  content's leading and trailing edges from the row's own corresponding
  edges by `SettingsLayout.default[.cardHorizontalInset]` (14pt) on each
  side.
- **row-designated-initializer-requirement**: A row MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.

## Appearance

- **Corner radius**: `cardView`'s corner radius is
  `SettingsLayout.default[.cardCornerRadius]` = 10pt, set once at
  construction (`ThemedBox(cornerRadius:)`, `ViewLayout.swift`). Neither
  `GroupView` itself nor the header/caption draws a shape of its own.
- **Padding**: The caption-to-card gap is
  `SettingsLayout.default[.captionSpacing]` = 6pt (`outerStack.spacing`).
  Inside the card, a `.row`-style row is padded
  `SettingsLayout.default[.cardVerticalInset]` = 9pt above and below its
  content and `SettingsLayout.default[.cardHorizontalInset]` = 14pt on each
  side; a `.continuation`-style row takes the same 9pt bottom and 14pt
  horizontal padding but 0pt of top padding, tucking it against the row
  above. `outerStack` and `rowStack` contribute 0pt of padding beyond their
  own content (`pinToEdges`).
- **Font**: The caption/header text tracks the active theme's `.caption` text
  role (`HeaderView` → `ThemedLabel(textRole: .caption)`); weight and size
  are not literal in `GroupView.swift` or `HeaderView.swift` — they come from
  the theme's `.caption` definition. `GroupView` sets no font of its own on
  row content; each row's typography belongs to its caller-supplied content.
- **Background**: `cardView`'s fill is the theme's `.elevatedSurface` role
  (`ThemedBox(fill: .elevatedSurface, ...)`). `GroupView` (the outer view)
  itself has no background color or layer.
- **Foreground/Text**: The caption/header text color is the theme's
  `.secondaryText` role (`HeaderView` → `ThemedLabel(role: .secondaryText)`).
  `GroupView` sets no foreground color of its own on row content.
- **Border**: `cardView` is constructed with `stroke: nil`, so it has no
  outline of its own. Between rows, a 1pt hairline
  (`ThemedSeparatorView(role: .divider)`) is drawn instead, inset
  `SettingsLayout.default[.cardHorizontalInset]` = 14pt from the leading
  edge and flush to the trailing edge, shown only where `updateSeparators`
  computes that a separator is due.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `GroupView.swift`.
- **Min/Max size**: Not applicable — `GroupView.swift` sets no explicit
  min/max width or height constraint. The only size constraint activated at
  runtime beyond internal layout is `GroupView`'s own width matching its
  superview's width (`viewDidMoveToSuperview`); height follows entirely from
  the header's and the accumulated rows' content.

## States

| State | Appearance change |
|-------|------------------|
| Default | The header and `cardView` are added to `outerStack`; `rowStack` starts empty until `addSettingSubview` is called — no rows, no separators. |
| Row added (`.row` style) | A `CardRow` is appended with 9pt padding above and below its content and 14pt padding on each side; whether it also shows a leading hairline is decided separately by `updateSeparators`. |
| Row added (`.continuation` style) | A `CardRow` is appended with 0pt top padding (tucked against the row above) and the same 9pt bottom / 14pt horizontal padding; it never shows a separator. |
| Separator shown | A `.row`-style row with a not-hidden predecessor: `line.isHidden == false`, separator band height = 1pt (`dividerThickness`), inset 14pt from the leading edge. |
| Separator collapsed | The first row in the card, any `.continuation`-style row, or a `.row`-style row with no not-hidden predecessor: `line.isHidden == true`, separator band height = 0pt. |
| Row content hidden | A row's own `isHidden` mirrors its content's `isHidden` (`syncVisibility`); `NSStackView` omits its space, and `updateSeparators` may then collapse the separator on the row that follows it. |
| Pressed | Not applicable: `GroupView`, `cardView`, and `CardRow` define no target/action and receive no press interaction of their own — any pressed styling belongs to a row's caller-supplied content. |
| Disabled | Not implemented in `GroupView.swift`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `GroupView`; any focus ring belongs to a row's own content, not to the container. |
| Loading | Not applicable: `GroupView` performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role/trait**: `GroupView`, `cardView` (a `ThemedBox`, itself an `NSView`
  subclass), and `rowStack` set no explicit accessibility role anywhere in
  `GroupView.swift`; each is exposed to assistive technology with `NSView`'s
  ordinary default, not as a distinguished "group" container. The header
  view's own accessibility behavior belongs to `HeaderView` (a
  `ThemedLabel`-based static-text label); `GroupView.swift` does not further
  style or role it.
- **Label requirements**: `GroupView.swift` never associates the
  header/caption text with `cardView` or `rowStack` through any
  accessibility API — no `setAccessibilityLabel`, no
  `accessibilityLabelledUIElements`, no `NSAccessibilityGroupRole` container
  — anywhere in source. A settings group's entire visual purpose is a named
  card of rows, so a VoiceOver user tabbing into the card's rows has no
  programmatic way to learn which caption group they belong to; only sighted
  proximity conveys that relationship.
- **Announce state changes**: Not applicable beyond AppKit's own default —
  hiding a row's content sets that `CardRow`'s own `isHidden` through
  `syncVisibility`, which removes it (and its content) from the
  accessibility tree automatically; `GroupView.swift` performs no explicit
  VoiceOver announcement of its own for a row appearing, disappearing, or a
  separator changing.
- **Minimum tap target**: Not applicable — `GroupView`, `cardView`, and
  `CardRow` are layout/presentation containers with no target/action or
  gesture recognizer of their own anywhere in `GroupView.swift`; whatever tap
  targets exist belong to each row's own caller-supplied content and that
  content's own recipe.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| group-view-001 | card-surface | Construct `GroupView(withTitle: "Example")` | `cardView` is a `ThemedBox` with `fillRole == .elevatedSurface`, `strokeRole == nil`, and a 10pt layer corner radius |
| group-view-002 | card-view-access | Construct the component, then read `.cardView` from outside the type | Returns the same `ThemedBox` instance the view displays |
| group-view-003 | header-from-title | `GroupView(withTitle: "Example")` | The constructed header is a `HeaderView` whose `titleLabel.stringValue == "Example"` |
| group-view-004 | arbitrary-header-view | `GroupView(withHeaderView: someCustomNSView)` | `someCustomNSView` is the arranged subview above `cardView` in `outerStack` |
| group-view-005 | header-above-card | Construct the component | `outerStack.arrangedSubviews == [header, cardView]`, in that order |
| group-view-006 | header-card-spacing | Construct the component | `outerStack.spacing == 6.0` |
| group-view-007 | outer-stack-edge-pinning | Construct the component | Active constraints pin `outerStack`'s top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| group-view-008 | header-width-match | Construct the component | An active constraint equates the header's width to `outerStack.widthAnchor` |
| group-view-009 | card-width-match | Construct the component | An active constraint equates `cardView`'s width to `outerStack.widthAnchor` |
| group-view-010 | row-area-edge-pinning | Construct the component | Active constraints pin the internal row stack's top/leading/trailing/bottom anchors to `cardView`'s corresponding anchors, each with constant `0` |
| group-view-011 | row-stacking | Construct the component | The internal row stack's `orientation == .vertical`, `alignment == .leading`, `spacing == 0` |
| group-view-012 | autoresizing-mask-disabled | Construct the component | `translatesAutoresizingMaskIntoConstraints == false` on the view, `outerStack`, the row stack, the header, and `cardView` |
| group-view-013 | superview-width-match | Add the constructed view as a subview of a parent `NSView` | An active constraint equates the view's width to the parent's width |
| group-view-014 | width-match-skip-without-superview | Construct the component and call `viewDidMoveToSuperview()` without adding it to any parent | No width constraint is activated; no crash occurs from a nil superview |
| group-view-015 | row-append | `addSettingSubview(someView)` | `someView` is wrapped in a row that becomes the last row in the card; the number of rows in the card grows by one |
| group-view-016 | default-row-style | `addSettingSubview(someView)` with no `style` argument | The added row's `style == .row` |
| group-view-017 | added-row-width-match | `addSettingSubview(someView)` | An active constraint equates the new row's width to the row stack's width |
| group-view-018 | self-hiding-content-wiring | `addSettingSubview(aSelfHidingView)` where `aSelfHidingView` conforms to `SelfHidingSettingsView`, then invoke `aSelfHidingView.onVisibilityChange?()` | The wrapping row's `isHidden` re-syncs to `aSelfHidingView.isHidden` and separators are recomputed (observable via a subsequent row's separator state changing) |
| group-view-019 | separator-recompute-on-add | `addSettingSubview(viewA)` then `addSettingSubview(viewB)` | Recomputation after each call is observable — whether `viewB`'s row shows a separator reflects `viewA`'s row's hidden state at the time `viewB` was added |
| group-view-020 | separator-visibility | Add three `.row`-style, not-hidden views in sequence | The second and third rows' `showsSeparator == true`; only the first is `false` |
| group-view-021 | first-row-headless | `addSettingSubview(firstView)` as the only row | `firstView`'s row `showsSeparator == false` |
| group-view-022 | designated-initializer-requirement | Static check: inspect `GroupView.init?(coder:)` | Its body consists solely of a call to `fatalError`, so no code path returns a decoded instance |
| group-view-023 | main-actor-confinement | Static check: attempt to construct or mutate a `GroupView` from a non-isolated context | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| group-view-024 | row-visibility-binding | Hide a row's wrapped content, then have the row resynchronize its visibility | The row's own hidden state becomes `true` |
| group-view-025 | row-visibility-at-construction | Construct a row whose wrapped content's hidden state is `true` | Immediately after construction returns, the row's own hidden state is `true` |
| group-view-026 | separator-collapse | Turn a row's separator visibility off (from on) | The row's divider becomes hidden; the space reserved for it becomes `0` |
| group-view-027 | separator-expansion | Turn a row's separator visibility on (from off) | The row's divider becomes visible; the space reserved for it becomes `1.0`pt |
| group-view-028 | separator-write-idempotency | Set a row's separator visibility to its own current value | Neither the divider's hidden state nor the reserved space's height changes as a result of this assignment |
| group-view-029 | separator-inset | Inspect a `.row`-style row's active constraints | The divider is inset 14pt from the row's leading edge; the divider reaches the row's trailing edge with no additional inset |
| group-view-030 | row-content-padding | Inspect a `.row`-style row's active constraints | The content's top edge is inset 9pt below the divider band; the content's bottom edge is inset 9pt from the row's bottom edge |
| group-view-031 | continuation-padding | Inspect a `.continuation`-style row's active constraints | The content's top edge has no inset from the divider band (`0`); the content's bottom edge is still inset 9pt from the row's bottom edge |
| group-view-032 | row-content-horizontal-inset | Inspect any row's active constraints | The content's leading edge is inset 14pt from the row's leading edge; the content's trailing edge is inset 14pt from the row's trailing edge |
| group-view-033 | row-designated-initializer-requirement | Static check: inspect the row type's `init?(coder:)` | Its body consists solely of a call to `fatalError`, so no code path returns a decoded instance |

## Edge Cases

- Null/empty input: `title` (`String`, `init(withTitle:)`) and `header`
  (`NSView`, `init(withHeaderView:)`) are non-optional, typed constructor
  parameters; Swift's type system rules out `nil` for either (MUST — the
  initializer needs no nil-handling path because neither parameter can be
  `nil`).
- Empty `title` string (`""`): `header-from-title` still runs
  unconditionally, constructing a `HeaderView` whose label renders empty; the
  caption band and its 6pt spacing from the card remain in layout regardless
  (MUST, per `header-from-title` and `header-card-spacing` — the source has
  no guard against an empty string).
- Boundary values: Not applicable — `GroupView`'s only numeric behavior comes
  from the fixed `SettingsLayout` constants (10pt corner radius, 6pt caption
  spacing, 14pt horizontal inset, 9pt vertical inset, 1pt divider
  thickness); it exposes no caller-configurable numeric range of its own.
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), so `addSettingSubview`, `updateSeparators`, and
  every constraint activation are serialized on the main actor.
- Error states: Not applicable — every operation in `GroupView.swift`
  (adding a row, updating separators, syncing visibility) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own.
- Zero rows added: `rowStack` is pinned to `cardView`'s edges with
  `pinToEdges`, so with no arranged subviews `cardView`'s size is exactly
  `rowStack`'s size; nothing in `GroupView.swift` enforces a nonzero row
  count or a minimum card height, so an unpopulated group renders as an
  empty rounded, elevated-surface strip beneath its caption (MUST, per
  `row-area-edge-pinning` — no minimum-height constraint exists anywhere in
  source).
- All rows hidden simultaneously: `NSStackView` omits layout space for
  hidden arranged subviews, and separator recomputation only ever toggles a
  row's own separator visibility on rows still present in `rows` — nothing
  in `GroupView.swift` ever sets `cardView.isHidden`. The card itself
  remains present, still painted with its elevated-surface fill and rounded
  corners (see `card-surface`), collapsed to near-zero height, rather than
  disappearing. Whether a fully collapsed card should hide itself is an open
  decision the source does not make — see Design Decisions.
- Passing the same content view instance to `addSettingSubview` twice:
  Precondition — callers MUST NOT add the same view instance to a
  `GroupView` more than once. AppKit's `addSubview(_:)` always detaches a
  view from its previous superview before adding it to a new one, so a
  second call wrapping the same instance in a new row silently removes it
  from the first row, leaving that row's own content constraints referencing
  a view no longer inside its subtree — Auto Layout then has no common
  ancestor left to satisfy them. `GroupView.swift` contains no guard against
  this; honoring the precondition is the caller's responsibility, not a
  behavior `row-append` is required to produce.
- Moving a `GroupView` between two different superviews: `superview-width-
  match` activates a fresh `self.widthAnchor == parent.widthAnchor`
  constraint on every call to `viewDidMoveToSuperview`, without deactivating
  any constraint created for a previous superview. Re-parenting the same
  `GroupView` instance leaves both width constraints active simultaneously,
  which conflicts if the two superviews' widths ever differ (MUST-level
  consequence of source; `GroupView.swift` never stores or deactivates a
  previously created width constraint — see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required, via `init(withTitle:)`) | The convenience initializer's caption text, forwarded into an internally-constructed `HeaderView`. |
| `header` | `NSView` | — (required, via `init(withHeaderView:)`) | The designated initializer's caption view, placed above `cardView`. `init(withTitle:)` supplies a `HeaderView` here. |
| `style` (per call to `addSettingSubview(_:style:)`) | `ComposableSettings.CardRowStyle` | `.row` | Whether the added view starts a new padded, divided row (`.row`) or continues the row above with no top padding and no divider (`.continuation`). |

## Deep Linking

Not applicable: `GroupView` is a layout container inside a composable
settings window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in `GroupView.swift`.

## Localization

Not applicable: `GroupView.swift` defines no string literals of its own.
`init(withTitle:)`'s `title` parameter has no default value — it is entirely
caller-supplied at every call site — so localizing it is the caller's
responsibility, the same treatment fully caller-supplied text gets in the
sibling `DismissibleHintView` recipe's `text` parameter.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `GroupView.swift` contains no animation, transition, or `NSAnimationContext` call; every layout change (adding a row, toggling `showsSeparator`, hiding a row) is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `GroupView.swift` reads no system contrast setting; `cardView`'s fill and the divider's color are theme-resolved semantic roles (`.elevatedSurface`, `.divider`) supplied by `ThemedBox`/`ThemedSeparatorView`, neither of which this file adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: `GroupView` conveys grouping and row separation through structure — padding and a hairline — not through color alone; whether a row shows a divider is driven by `showsSeparator`'s layout effect, never by a color-only cue. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `GroupView.swift`; the caption, the card, and every added row render
unconditionally.

## Analytics

Not applicable: `GroupView.swift` contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  header view/title, `cardView`, and the row views it is given.
- **Storage**: Not applicable — `GroupView.swift` performs no read/write to
  disk, `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `GroupView.swift`.
- **Retention**: Not applicable — the view retains only `cardView`, its two
  internal stacks, and its `rows` array for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: `GroupView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Use `Section` with a leading, `.caption`-styled header text
  above a `VStack` clipped to a `RoundedRectangle` (matching the 10pt
  `cardCornerRadius`) and filled with the elevated-surface color, mirroring
  `#requirements/card-surface`; insert `Divider()` between rows only where
  the source's own `#requirements/separator-visibility` rule would show one
  — SwiftUI's `Section` in a `List`/`Form` already renders this pattern
  close to natively on macOS/iOS, so a from-scratch `VStack` is only needed
  for a fully custom card. Give a `.continuation`-styled child no top
  padding and no `Divider()` above it, mirroring
  `#requirements/continuation-padding`. Drive a row's presence with
  structural conditional inclusion (`if !isHidden { row }`) rather than
  `.hidden()`, the same substitution the sibling
  `ConditionalView`/`DismissibleHintView` recipes make, so a hidden row's
  divider and padding close up the way `#requirements/row-visibility-
  binding` does here.
- **Compose**: Build a `Column` with a `.caption`-styled `Text` above a
  `Card`/`Surface` (`shape = RoundedCornerShape(10.dp)`,
  `colors = CardDefaults.cardColors(containerColor = <elevated-surface
  token>)`), and lay rows out in an inner `Column` inserting a thin
  `HorizontalDivider` between consecutive visible rows only — computed the
  same way the source walks its rows, tracking whether a not-hidden,
  non-continuation predecessor has been seen (see
  `#requirements/separator-visibility`). Apply `Modifier.padding` per row
  matching the 9dp/14dp vertical/horizontal insets, and `0.dp` top padding
  for a continuation row.
- **React/Web**: Render a `<fieldset>` or `<section role="group"
  aria-labelledby="...">` whose caption is a `<legend>`/heading with
  `id="..."` matching `aria-labelledby` — the explicit label association
  that `GroupView.swift`'s AppKit source never establishes (see Label
  requirements) — inside a `div` styled with `border-radius: 10px` and the
  elevated-surface background token. Give each `.row` child
  `padding: 9px 14px` and a `border-top: 1px solid var(--divider)` on every
  child except the first visible one, mirroring
  `#requirements/separator-visibility` / `#requirements/first-row-headless`;
  give a `.continuation` child `padding-top: 0` and no `border-top`. Toggle
  a row's presence with conditional rendering (removing the node), not
  `display: none` alone, so the surrounding gap actually closes, mirroring
  `#requirements/row-visibility-binding`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/GroupView.swift`,
  with layout constants from `ViewLayout.swift`, `ThemedBox`/
  `ThemedSeparatorView`/`ThemedLabel` from the `agenticdevelopertoolkit`
  submodule's `ThemedViews.swift`, and the caption view from
  `HeaderView.swift`. A macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, built entirely on
  `NSStackView` and Auto Layout. The rows live in a private `rowStack`, each
  wrapped in a private `CardRow` tracked in a private `rows` array; a row's
  divider is a private `line`/`separatorHeight` pair, and `showsSeparator`'s
  `didSet` short-circuits on an unchanged `oldValue` to skip redundant
  writes — the requirements above describe these mechanics only by their
  observable effect, since any of these names could change under a refactor
  without changing what the card looks like or does. There is no UIKit code
  path in source; a UIKit port would replace `NSStackView` with
  `UIStackView`, `NSView.isHidden` with `UIView.isHidden` (the same
  removal-from-layout semantics apply within a `UIStackView`), and would
  have no `NSCoder`-only initializer restriction to fatal-error on the way
  `#requirements/designated-initializer-requirement` and
  `#requirements/row-designated-initializer-requirement` do here.
- **WinUI 3** (the reason this recipe exists): Compose the group from a
  `TextBlock` caption (`Style="{StaticResource CaptionTextBlockStyle}"`)
  positioned above a rounded `Border` (`CornerRadius="10"`, matching
  `cardCornerRadius`, `Background="{ThemeResource
  CardBackgroundFillColorDefaultBrush}"`, `BorderThickness="0"`, matching
  `#requirements/card-surface`'s `stroke: nil`) containing a vertical
  `StackPanel` of row `Border`s. Reproduce `#requirements/separator-
  visibility` / `#requirements/first-row-headless` with a value converter,
  keyed on item index and visibility, that suppresses a row's top `Border`
  divider (`BorderThickness="0,1,0,0"`, `BorderBrush="{ThemeResource
  DividerStrokeColorDefaultBrush}"`) unless a prior, still-visible,
  non-continuation row exists. Bind each row `Border`'s own `Visibility` —
  not just its inner content's — to the wrapped content's visibility, since
  a `StackPanel` does not auto-collapse a row's own padding around a
  `Visibility="Collapsed"` child's slot the way an `NSStackView` collapses a
  hidden arranged `NSView`; this is the direct analog of
  `#requirements/row-visibility-binding` and is required for the
  divider-recompute analog above to see accurate "still-visible" state.
  Give each row `Padding="14,9,14,9"` (a continuation row
  `Padding="14,0,14,9"`), matching `#requirements/row-content-padding` /
  `#requirements/continuation-padding`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/GroupView.swift` |

## Design Decisions

**Decision**: Place the caption outside `cardView`, as a sibling in
`outerStack`, rather than as the card's own first row.
**Rationale**: per the source's own doc comment, "a title as the card's
first row reads as just another setting" — the caption sits outside the
card because that is what separates a group's name from its contents at a
glance.
**Approved**: pending

**Decision**: `addSettingSubview` takes an explicit `style: CardRowStyle`
parameter rather than inferring row style from the added view's type.
**Rationale**: per the source's own doc comment, inferring style from type
"was inferred from the view's type once — prose was assumed to annotate the
row above it — which turned a list of plugin load failures into an
unseparated run of jammed-together lines, and sliced one model description
into six divided rows." What a view means in a card is not knowable from
what class it is, so the caller states it.
**Approved**: pending

**Decision**: `viewDidMoveToSuperview` activates a width constraint
equating `GroupView` to its new superview, rather than giving `GroupView` an
intrinsic or fixed width.
**Rationale**: per the source's own comment, each group fills its parent
stack's width "so that any child that wants to span the full panel (sliders
with trailing captions, dividers, etc.) actually can," while items inside
the group still control their own horizontal layout via content-hugging
priorities.
**Approved**: pending

**Decision**: Drive `updateSeparators()` from `SelfHidingSettingsView`'s
`onVisibilityChange` callback, rather than observing `isHidden` via KVO or
polling it.
**Rationale**: per the source's own doc comment, `GroupView` "listens so the
card can close up around a row that has hidden itself — its padding and the
hairline above it go with it," because an `NSStackView` collapses a hidden
arranged subview but the row's own padding cell is not hidden just because
its content is; without the callback, a dismissed hint leaves an empty band
and a stray divider behind.
**Approved**: pending

**Decision**: `viewDidMoveToSuperview` neither stores nor deactivates a
width constraint from a previous superview before activating a new one.
**Rationale**: acceptable as shipped because every known call site adds a
`GroupView` to exactly one stable superview once and never re-parents it
afterward; documented here as the source-traceable technical debt that
surfaces specifically in the re-parenting scenario recorded under Edge
Cases, should a future caller move a `GroupView` between superviews.
**Approved**: pending

**Decision**: When every row in a `GroupView` is hidden, `cardView` is left
visible — collapsed to near-zero height — rather than being hidden or
removed along with its rows.
**Rationale**: `GroupView.swift` never sets `cardView.isHidden`;
`NSStackView` omits layout space for hidden arranged subviews, so the row
area's height collapses to zero, but no code path in source extends that
collapse to `cardView`'s own visibility. This is documented as undecided
behavior, not a chosen one — the source simply has no check either way, so
a caller sees an empty elevated-surface strip rather than nothing (see Edge
Cases).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |

Statuses rest on `GroupView.swift`: `native-controls-preference` reflects the
card being built from `NSStackView`/`ThemedBox` rather than a custom-drawn
control; `idempotent-operations` is `partial` because `viewDidMoveToSuperview`
activates a fresh width constraint on every attach without removing one from
a prior superview (see Design Decisions); and `screen-reader-support` is
`partial` because no accessibility grouping ties the header to
`cardView`/`rowStack` (see Accessibility).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names and restated the private-internal ones (rowStack/rows/CardRow/line/separatorHeight/oldValue) as observable outcomes; reformatted Design Decisions and added one for the all-rows-hidden open question; reframed the duplicate-add edge case as a caller precondition instead of a required behavior; converted the two fatal-error and one compile-time test vectors to static checks; moved the cookbook guideline URI out of references into related and added real external references; corrected Compliance statuses and category names and dropped invented checks; rewrote the WinUI 3 bullet around one concrete structure. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple GroupView (AppKit, macOS) source. |
