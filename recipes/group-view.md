---
id: 775f1761-f757-41d0-b51b-354a410a11f4
title: GroupView
domain: agentictoolkit://recipes/group-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
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
- agentictoolkit://recipes/conditional-view
- agentictoolkit://recipes/dismissible-hint-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
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

- **creates-card-as-elevated-surface-with-no-stroke**: Component MUST
  construct `cardView` as a `ThemedBox` filled with the `.elevatedSurface`
  role, `stroke: nil`, and corner radius
  `SettingsLayout.default[.cardCornerRadius]` (10pt, `ViewLayout.swift`).
- **exposes-card-view-property**: Component MUST expose `cardView` as a
  public, read-only property.
- **builds-header-from-title-string**: The `init(withTitle:)` convenience
  initializer MUST construct a `HeaderView(title:)` from the caller-supplied
  string and forward it to `init(withHeaderView:)`.
- **accepts-arbitrary-header-view**: The designated `init(withHeaderView:)`
  initializer MUST accept any `NSView` as the group's caption, not only a
  `HeaderView`.
- **arranges-header-above-card**: Component MUST add the header view and then
  `cardView`, in that order, as arranged subviews of a vertical, leading-
  aligned `NSStackView` (`outerStack`).
- **spaces-header-from-card**: Component MUST set `outerStack.spacing` to
  `SettingsLayout.default[.captionSpacing]` (6pt).
- **pins-outer-stack-to-own-edges**: Component MUST pin `outerStack`'s top,
  leading, trailing, and bottom anchors to its own corresponding edges with
  no additional constant (`pinToEdges`).
- **matches-header-width-to-outer-stack**: Component MUST constrain the
  header view's width equal to `outerStack.widthAnchor`.
- **matches-card-width-to-outer-stack**: Component MUST constrain
  `cardView`'s width equal to `outerStack.widthAnchor`.
- **pins-row-stack-to-card-edges**: Component MUST pin the internal
  `rowStack` to `cardView`'s top, leading, trailing, and bottom anchors with
  no additional constant (`pinToEdges`).
- **stacks-rows-vertically-with-no-gap**: Component MUST set `rowStack`'s
  orientation to `.vertical`, alignment to `.leading`, and `spacing` to `0`.
- **disables-autoresizing-mask-throughout**: Component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself, `outerStack`,
  `rowStack`, the header view, and `cardView`.
- **matches-width-to-superview-on-attach**: `viewDidMoveToSuperview` MUST
  activate a constraint equating `self.widthAnchor` to `parent.widthAnchor`
  whenever `self.superview` is non-nil after the move.
- **skips-width-match-with-no-superview**: `viewDidMoveToSuperview` MUST NOT
  activate any width constraint when `self.superview` is `nil` after the
  move.
- **appends-row-per-added-view**: `addSettingSubview(_:style:)` MUST wrap
  `view` in a new `CardRow(content:style:)`, append it to the internal `rows`
  array, and add it as the next arranged subview of `rowStack`.
- **defaults-row-style-to-row**: `addSettingSubview(_:style:)` MUST default
  its `style` parameter to `.row` when the caller omits it.
- **matches-added-row-width-to-row-stack**: Component MUST constrain each
  newly added row's width equal to `rowStack.widthAnchor`.
- **wires-self-hiding-content-to-separator-updates**: When `view` conforms to
  `SelfHidingSettingsView`, `addSettingSubview` MUST set that view's
  `onVisibilityChange` to a closure that calls the new row's
  `syncVisibility()` and then `self.updateSeparators()`.
- **recomputes-separators-after-each-add**: `addSettingSubview` MUST call
  `updateSeparators()` after appending the new row.
- **shows-separator-only-after-visible-row-style-predecessor**:
  `updateSeparators` MUST set each row's `showsSeparator` to `true` only when
  a strictly-earlier row in `rows` was not hidden (`hasVisiblePredecessor ==
  true`) AND the current row's own `style` is `.row`; a `.continuation`-style
  row's `showsSeparator` MUST always be `false`.
- **treats-first-row-as-headless**: The first row in `rows` MUST NOT show a
  separator regardless of its style, because `updateSeparators` starts
  `hasVisiblePredecessor` at `false`.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **ties-row-hidden-state-to-content-hidden-state**: The internal `CardRow`
  MUST set its own `isHidden` equal to its wrapped `content.isHidden`
  (`syncVisibility`).
- **syncs-row-visibility-at-construction**: `CardRow.init` MUST call
  `syncVisibility()` before returning.
- **collapses-separator-band-when-hidden**: When `CardRow.showsSeparator` is
  set to `false`, the row MUST set `line.isHidden = true` and
  `separatorHeight.constant = 0`.
- **expands-separator-band-when-shown**: When `CardRow.showsSeparator` is set
  to `true`, the row MUST set `line.isHidden = false` and
  `separatorHeight.constant` to `SettingsLayout.default[.dividerThickness]`
  (1pt).
- **skips-redundant-separator-writes**: `CardRow.showsSeparator`'s `didSet`
  MUST return without touching `line.isHidden` or `separatorHeight` when the
  newly assigned value equals `oldValue`.
- **insets-separator-from-leading-edge**: `CardRow` MUST inset the hairline's
  leading anchor from its separator band's leading anchor by
  `SettingsLayout.default[.cardHorizontalInset]` (14pt) and pin its trailing
  anchor flush to the separator band's trailing anchor.
- **pads-row-style-content-on-both-sides**: For a `.row`-style `CardRow`,
  Component MUST inset `content`'s top anchor from the separator band's
  bottom anchor by `SettingsLayout.default[.cardVerticalInset]` (9pt), and
  inset `content`'s bottom anchor from the row's own bottom anchor by the
  same 9pt.
- **omits-top-padding-for-continuation-style**: For a `.continuation`-style
  `CardRow`, Component MUST inset `content`'s top anchor from the separator
  band's bottom anchor by `0`, while still applying the 9pt bottom inset.
- **insets-row-content-horizontally**: `CardRow` MUST inset `content`'s
  leading and trailing anchors from its own corresponding edges by
  `SettingsLayout.default[.cardHorizontalInset]` (14pt) on each side.
- **requires-designated-initializer-for-card-row**: `CardRow` MUST NOT
  support construction via `init(coder:)`; that initializer MUST trigger a
  fatal error.

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
- **Label requirements**: NEEDS REVIEW: `GroupView.swift` never associates
  the header/caption text with `cardView` or `rowStack` through any
  accessibility API — no `setAccessibilityLabel`, no
  `accessibilityLabelledUIElements`, no `NSAccessibilityGroupRole` container
  — anywhere in source. A settings group's entire visual purpose is a named
  card of rows, so a VoiceOver user tabbing into the card's rows has no
  programmatic way to learn which caption group they belong to; only sighted
  proximity conveys that relationship. What is missing: an explicit
  accessibility grouping/labelling relationship between the header and
  `cardView`/`rowStack`. What would settle it: confirmation from the
  accessibility/HIG owner on whether `GroupView` should wrap `cardView` in
  `NSAccessibilityGroupRole` with `accessibilityLabel`/
  `accessibilityLabelledUIElements` pointing at the header, since the source
  as written establishes only a visual relationship.
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
| group-view-001 | creates-card-as-elevated-surface-with-no-stroke | Construct `GroupView(withTitle: "Example")` | `cardView` is a `ThemedBox` with `fillRole == .elevatedSurface`, `strokeRole == nil`, and a 10pt layer corner radius |
| group-view-002 | exposes-card-view-property | Construct the component, then read `.cardView` from outside the type | Returns the same `ThemedBox` instance the view displays |
| group-view-003 | builds-header-from-title-string | `GroupView(withTitle: "Example")` | The constructed header is a `HeaderView` whose `titleLabel.stringValue == "Example"` |
| group-view-004 | accepts-arbitrary-header-view | `GroupView(withHeaderView: someCustomNSView)` | `someCustomNSView` is the arranged subview above `cardView` in `outerStack` |
| group-view-005 | arranges-header-above-card | Construct the component | `outerStack.arrangedSubviews == [header, cardView]`, in that order |
| group-view-006 | spaces-header-from-card | Construct the component | `outerStack.spacing == 6.0` |
| group-view-007 | pins-outer-stack-to-own-edges | Construct the component | Active constraints pin `outerStack`'s top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| group-view-008 | matches-header-width-to-outer-stack | Construct the component | An active constraint equates the header's width to `outerStack.widthAnchor` |
| group-view-009 | matches-card-width-to-outer-stack | Construct the component | An active constraint equates `cardView`'s width to `outerStack.widthAnchor` |
| group-view-010 | pins-row-stack-to-card-edges | Construct the component | Active constraints pin the internal row stack's top/leading/trailing/bottom anchors to `cardView`'s corresponding anchors, each with constant `0` |
| group-view-011 | stacks-rows-vertically-with-no-gap | Construct the component | The internal row stack's `orientation == .vertical`, `alignment == .leading`, `spacing == 0` |
| group-view-012 | disables-autoresizing-mask-throughout | Construct the component | `translatesAutoresizingMaskIntoConstraints == false` on the view, `outerStack`, the row stack, the header, and `cardView` |
| group-view-013 | matches-width-to-superview-on-attach | Add the constructed view as a subview of a parent `NSView` | An active constraint equates the view's width to the parent's width |
| group-view-014 | skips-width-match-with-no-superview | Construct the component and call `viewDidMoveToSuperview()` without adding it to any parent | No width constraint is activated; no crash occurs from a nil superview |
| group-view-015 | appends-row-per-added-view | `addSettingSubview(someView)` | `someView` is wrapped in a row that is an arranged subview of the row stack; the internal `rows` array grows by one |
| group-view-016 | defaults-row-style-to-row | `addSettingSubview(someView)` with no `style` argument | The added row's `style == .row` |
| group-view-017 | matches-added-row-width-to-row-stack | `addSettingSubview(someView)` | An active constraint equates the new row's width to the row stack's width |
| group-view-018 | wires-self-hiding-content-to-separator-updates | `addSettingSubview(aSelfHidingView)` where `aSelfHidingView` conforms to `SelfHidingSettingsView`, then invoke `aSelfHidingView.onVisibilityChange?()` | The wrapping row's `isHidden` re-syncs to `aSelfHidingView.isHidden` and `updateSeparators()` runs (observable via a subsequent row's `showsSeparator` changing) |
| group-view-019 | recomputes-separators-after-each-add | `addSettingSubview(viewA)` then `addSettingSubview(viewB)` | `updateSeparators()`'s effect is observable after each call — `viewB`'s row's `showsSeparator` reflects `viewA`'s row's hidden state at the time `viewB` was added |
| group-view-020 | shows-separator-only-after-visible-row-style-predecessor | Add three `.row`-style, not-hidden views in sequence | The second and third rows' `showsSeparator == true`; only the first is `false` |
| group-view-021 | treats-first-row-as-headless | `addSettingSubview(firstView)` as the only row | `firstView`'s row `showsSeparator == false` |
| group-view-022 | requires-designated-initializer | Attempt `GroupView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| group-view-023 | confines-to-main-actor | Attempt to construct or mutate a `GroupView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| group-view-024 | ties-row-hidden-state-to-content-hidden-state | Set `content.isHidden = true` on a row's wrapped content, then call the row's `syncVisibility()` | The row's own `isHidden == true` |
| group-view-025 | syncs-row-visibility-at-construction | Construct a `CardRow` whose `content.isHidden == true` | Immediately after `init` returns, the row's own `isHidden == true` |
| group-view-026 | collapses-separator-band-when-hidden | Set a row's `showsSeparator = false` (from `true`) | `line.isHidden == true`; `separatorHeight.constant == 0` |
| group-view-027 | expands-separator-band-when-shown | Set a row's `showsSeparator = true` (from `false`) | `line.isHidden == false`; `separatorHeight.constant == 1.0` |
| group-view-028 | skips-redundant-separator-writes | Set a row's `showsSeparator` to its own current value | Neither `line.isHidden` nor `separatorHeight.constant` changes as a result of this assignment |
| group-view-029 | insets-separator-from-leading-edge | Inspect a `.row`-style row's active constraints | `line.leadingAnchor` is inset 14pt from the separator band's leading anchor; `line.trailingAnchor` equals the separator band's trailing anchor with constant `0` |
| group-view-030 | pads-row-style-content-on-both-sides | Inspect a `.row`-style row's active constraints | `content.topAnchor` is inset 9pt from the separator band's bottom anchor; `content.bottomAnchor` is inset 9pt from the row's bottom anchor |
| group-view-031 | omits-top-padding-for-continuation-style | Inspect a `.continuation`-style row's active constraints | `content.topAnchor` equals the separator band's bottom anchor with constant `0`; `content.bottomAnchor` is still inset 9pt from the row's bottom anchor |
| group-view-032 | insets-row-content-horizontally | Inspect any row's active constraints | `content.leadingAnchor` is inset 14pt from the row's leading anchor; `content.trailingAnchor` is inset 14pt from the row's trailing anchor |
| group-view-033 | requires-designated-initializer-for-card-row | Attempt to construct a `CardRow` via `init(coder:)` | The call traps with a fatal error; no instance is returned |

## Edge Cases

- Null/empty input: `title` (`String`, `init(withTitle:)`) and `header`
  (`NSView`, `init(withHeaderView:)`) are non-optional, typed constructor
  parameters; Swift's type system rules out `nil` for either (MUST — the
  initializer needs no nil-handling path because neither parameter can be
  `nil`).
- Empty `title` string (`""`): `builds-header-from-title-string` still runs
  unconditionally, constructing a `HeaderView` whose label renders empty; the
  caption band and its 6pt spacing from the card remain in layout regardless
  (MUST, per `builds-header-from-title-string` and `spaces-header-from-card`
  — the source has no guard against an empty string).
- Boundary values: Not applicable — `GroupView`'s only numeric behavior comes
  from the fixed `SettingsLayout` constants (10pt corner radius, 6pt caption
  spacing, 14pt horizontal inset, 9pt vertical inset, 1pt divider
  thickness); it exposes no caller-configurable numeric range of its own.
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `confines-to-main-actor`), so `addSettingSubview`, `updateSeparators`, and
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
  `pins-row-stack-to-card-edges` — no minimum-height constraint exists
  anywhere in source).
- All rows hidden simultaneously: `NSStackView` omits layout space for
  hidden arranged subviews, and `updateSeparators` only ever toggles
  `showsSeparator` on rows still present in `rows` — nothing in
  `GroupView.swift` ever sets `cardView.isHidden`. The card itself remains
  present, still painted with its elevated-surface fill and rounded corners,
  collapsed to near-zero height, rather than disappearing (MUST, per
  `creates-card-as-elevated-surface-with-no-stroke` — no code path hides
  `cardView`).
- Passing the same content view instance to `addSettingSubview` twice:
  AppKit's `addSubview(_:)` always detaches a view from its previous
  superview before adding it to a new one. A second call wrapping the same
  `NSView` instance in a new `CardRow` and calling `addSubview(content)`
  silently removes that view from the first `CardRow`, leaving the first
  row's own `content` constraints referencing a view no longer inside that
  row's subtree — Auto Layout has no common ancestor left to satisfy them.
  `GroupView.swift` contains no guard against adding the same view instance
  more than once (MUST-level, source-traceable consequence of
  `appends-row-per-added-view`, not a genuine gap in the recipe: AppKit's own
  view-reparenting rule determines the outcome).
- Moving a `GroupView` between two different superviews:
  `matches-width-to-superview-on-attach` activates a fresh
  `self.widthAnchor == parent.widthAnchor` constraint on every call to
  `viewDidMoveToSuperview`, without deactivating any constraint created for a
  previous superview. Re-parenting the same `GroupView` instance leaves both
  width constraints active simultaneously, which conflicts if the two
  superviews' widths ever differ (MUST-level consequence of source;
  `GroupView.swift` never stores or deactivates a previously created width
  constraint — see Design Decisions).

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
  `creates-card-as-elevated-surface-with-no-stroke`; insert `Divider()`
  between rows only where the source's own `shows-separator-only-after-
  visible-row-style-predecessor` rule would show one — SwiftUI's `Section`
  in a `List`/`Form` already renders this pattern close to natively on
  macOS/iOS, so a from-scratch `VStack` is only needed for a fully custom
  card. Give a `.continuation`-styled child no top padding and no `Divider()`
  above it, mirroring `omits-top-padding-for-continuation-style`. Drive a
  row's presence with structural conditional inclusion (`if !isHidden { row
  }`) rather than `.hidden()`, the same substitution the sibling
  `ConditionalView`/`DismissibleHintView` recipes make, so a hidden row's
  divider and padding close up the way `ties-row-hidden-state-to-content-
  hidden-state` does here.
- **Compose**: Build a `Column` with a `.caption`-styled `Text` above a
  `Card`/`Surface` (`shape = RoundedCornerShape(10.dp)`,
  `colors = CardDefaults.cardColors(containerColor = <elevated-surface
  token>)`), and lay rows out in an inner `Column` inserting a thin
  `HorizontalDivider` between consecutive visible rows only — computed the
  same way `updateSeparators` walks `rows`, tracking whether a not-hidden,
  non-continuation predecessor has been seen. Apply `Modifier.padding` per
  row matching the 9dp/14dp vertical/horizontal insets, and `0.dp` top
  padding for a continuation row.
- **React/Web**: Render a `<fieldset>` or `<section role="group"
  aria-labelledby="...">` whose caption is a `<legend>`/heading with
  `id="..."` matching `aria-labelledby` — the explicit label association
  that is the open question the Accessibility section raises about the
  AppKit source — inside a `div` styled with `border-radius: 10px` and the
  elevated-surface background token. Give each `.row` child
  `padding: 9px 14px` and a `border-top: 1px solid var(--divider)` on every
  child except the first visible one, mirroring `shows-separator-only-after-
  visible-row-style-predecessor`/`treats-first-row-as-headless`; give a
  `.continuation` child `padding-top: 0` and no `border-top`. Toggle a row's
  presence with conditional rendering (removing the node), not `display:
  none` alone, so the surrounding gap actually closes, mirroring `ties-row-
  hidden-state-to-content-hidden-state`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/GroupView.swift`,
  with layout constants from `ViewLayout.swift`, `ThemedBox`/
  `ThemedSeparatorView`/`ThemedLabel` from the `agenticdevelopertoolkit`
  submodule's `ThemedViews.swift`, and the caption view from
  `HeaderView.swift`. A macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, built entirely on
  `NSStackView` and Auto Layout. There is no UIKit code path in source; a
  UIKit port would replace `NSStackView` with `UIStackView`, `NSView.isHidden`
  with `UIView.isHidden` (the same removal-from-layout semantics apply
  within a `UIStackView`), and would have no `NSCoder`-only initializer
  restriction to fatal-error on the way `requires-designated-initializer`
  and `requires-designated-initializer-for-card-row` do here.
- **WinUI 3** (the reason this recipe exists): Compose the group from an
  `Expander`-free pairing of a `TextBlock` captioned with
  `Style="{StaticResource CaptionTextBlockStyle}"` positioned above a
  rounded `Border` (`CornerRadius="10"`, matching `cardCornerRadius`,
  `Background="{ThemeResource CardBackgroundFillColorDefaultBrush}"`,
  `BorderThickness="0"`, matching `creates-card-as-elevated-surface-with-no-
  stroke`'s `stroke: nil`) containing a vertical `ItemsControl` or
  `StackPanel` of rows. Reproduce `shows-separator-only-after-visible-row-
  style-predecessor`/`treats-first-row-as-headless` with an
  `ItemsControl.ItemContainerStyle` (or a value converter keyed on item
  index and visibility) that suppresses a row's top `Border` divider
  (`BorderThickness="0,1,0,0"`, `BorderBrush="{ThemeResource
  DividerStrokeColorDefaultBrush}"`) unless a prior, still-visible,
  non-continuation row exists. Bind each row wrapper's own `Visibility` —
  not just its inner content's — to the wrapped content's visibility, since
  `ItemsControl`/`StackPanel` does not auto-collapse a container's own
  padding around a `Visibility="Collapsed"` child's slot the way an
  `NSStackView` collapses a hidden arranged `NSView`; this is the direct
  analog of `ties-row-hidden-state-to-content-hidden-state` and is required
  for the divider-recompute analog above to see accurate "still-visible"
  state. Give each row `Padding="14,9,14,9"` (a continuation row
  `Padding="14,0,14,9"`), matching `pads-row-style-content-on-both-sides`/
  `omits-top-padding-for-continuation-style`.

## Design Decisions

- Decision: Place the caption outside `cardView`, as a sibling in
  `outerStack`, rather than as the card's own first row.
  Rationale: per the source's own doc comment, "a title as the card's first
  row reads as just another setting" — the caption sits outside the card
  because that is what separates a group's name from its contents at a
  glance.
  Approved: pending
- Decision: `addSettingSubview` takes an explicit `style: CardRowStyle`
  parameter rather than inferring row style from the added view's type.
  Rationale: per the source's own doc comment, inferring style from type
  "was inferred from the view's type once — prose was assumed to annotate
  the row above it — which turned a list of plugin load failures into an
  unseparated run of jammed-together lines, and sliced one model description
  into six divided rows." What a view means in a card is not knowable from
  what class it is, so the caller states it.
  Approved: pending
- Decision: `viewDidMoveToSuperview` activates a width constraint equating
  `GroupView` to its new superview, rather than giving `GroupView` an
  intrinsic or fixed width.
  Rationale: per the source's own comment, each group fills its parent
  stack's width "so that any child that wants to span the full panel
  (sliders with trailing captions, dividers, etc.) actually can," while
  items inside the group still control their own horizontal layout via
  content-hugging priorities.
  Approved: pending
- Decision: Drive `updateSeparators()` from `SelfHidingSettingsView`'s
  `onVisibilityChange` callback, rather than observing `isHidden` via KVO or
  polling it.
  Rationale: per the source's own doc comment, `GroupView` "listens so the
  card can close up around a row that has hidden itself — its padding and
  the hairline above it go with it," because an `NSStackView` collapses a
  hidden arranged subview but the row's own padding cell is not hidden just
  because its content is; without the callback, a dismissed hint leaves an
  empty band and a stray divider behind.
  Approved: pending
- Decision: `viewDidMoveToSuperview` neither stores nor deactivates a
  width constraint from a previous superview before activating a new one.
  Rationale: acceptable as shipped because every known call site adds a
  `GroupView` to exactly one stable superview once and never re-parents it
  afterward; documented here as the source-traceable technical debt that
  surfaces specifically in the re-parenting scenario recorded under Edge
  Cases, should a future caller move a `GroupView` between superviews.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [theme-driven-typography](agenticdevelopercookbook://compliance/ui-tokens#theme-driven-typography) | passed | ui-tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | needs-review | accessibility |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | passed | i18n |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple GroupView (AppKit, macOS) source. |
