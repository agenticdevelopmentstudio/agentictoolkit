---
id: 775f1761-f757-41d0-b51b-354a410a11f4
title: Group View
domain: agentictoolkit://cookbook/ui/settings/layout/group-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A card view drawing a captioned, rounded settings group whose rows are
  padded and hairline-divided, closing up automatically around a hidden row.
platforms:
- swift
- macos
tags:
- card
- settings
- layout
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/conditional-view
- agentictoolkit://cookbook/ui/settings/layout/dismissible-hint-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- https://developer.apple.com/documentation/appkit/nsstackview
approved-by: ''
approved-date: ''
---

# Group View

## Overview

The Group View is a settings-layout container that draws a settings group
the way a system settings app draws one — a caption sitting outside and
above a rounded card, and inside the card one padded row per setting with a
hairline between them. The caption is a separate view (a Header View by
default, or any caller-supplied view) positioned above the card, which holds
a vertical stack of rows. Each row added to the group is wrapped in an
internal row wrapper that owns the row's own padding and the separator
above it. A row whose content can report when it hides itself lets the
Group View collapse that row's padding and hairline when the content hides
itself, so a dismissed hint or a conditionally-hidden group member does not
leave a padded blank band or a stray divider behind — the same self-hiding-
content contract the sibling Conditional View and Dismissible Hint View
recipes fulfill for that reason.

## Behavioral Requirements

- **card-surface**: Component MUST construct its card surface filled with
  the `.elevatedSurface` role, no stroke, and a corner radius of 10pt.
- **card-view-access**: Component MUST expose its card surface as a public,
  read-only property.
- **header-from-title**: Constructing the component from a title string
  MUST build a header view from that string and use it as the group's
  caption.
- **arbitrary-header-view**: Component MUST accept any view as the group's
  caption, not only its own default header view.
- **header-above-card**: Component MUST place the header view above the
  card, in that order, in a vertical, leading-aligned stack.
- **header-card-spacing**: Component MUST set the spacing between the
  header and the card to 6pt.
- **outer-stack-edge-pinning**: Component MUST make the header-and-card
  stack fill its own bounds edge-to-edge, with no additional inset.
- **header-width-match**: Component MUST constrain the header view's width
  to match the header-and-card stack's width.
- **card-width-match**: Component MUST constrain the card's width to match
  the header-and-card stack's width.
- **row-area-edge-pinning**: Component MUST make the row area fill the
  card's bounds edge-to-edge, with no additional inset.
- **row-stacking**: Component MUST lay out rows in a vertical, leading-
  aligned stack with `0` spacing between adjacent rows.
- **superview-width-match**: When the component is added to a parent, it
  MUST size itself to match that parent's width.
- **width-match-skip-without-superview**: The component MUST NOT attempt to
  match a parent's width when it has no parent to match yet.
- **row-append**: Adding a row to the group MUST wrap it as the card's next
  row and add it to the end of the card's visible row order, growing the
  card's row count by one.
- **default-row-style**: Adding a row with no style specified MUST default
  to the standard row style.
- **added-row-width-match**: Component MUST constrain each newly added
  row's width to match the row area's width.
- **self-hiding-content-wiring**: When a row's content can report when it
  hides itself, adding that row MUST subscribe to that report so that the
  content hiding re-syncs the row's own visibility and then recomputes
  every row's separators.
- **separator-recompute-on-add**: Adding a row MUST recompute every row's
  separator visibility immediately after the row is appended.
- **separator-visibility**: Component MUST show a divider above a row only
  when a strictly-earlier row in the card's row order is not hidden AND the
  current row's own style is the standard row style; a continuation-style
  row's divider MUST always be hidden.
- **first-row-headless**: The first row in the card's row order MUST NOT
  show a divider regardless of its style, because no earlier row exists for
  it to follow.
- **row-visibility-binding**: A row's own hidden state MUST always equal its
  wrapped content's hidden state.
- **row-visibility-at-construction**: A newly constructed row MUST already
  reflect its content's hidden state before construction returns.
- **separator-collapse**: When a row's separator visibility is turned off,
  its divider MUST become hidden and the space reserved for it MUST collapse
  to zero height.
- **separator-expansion**: When a row's separator visibility is turned on,
  its divider MUST become visible and the space reserved for it MUST expand
  to the standard 1pt divider thickness.
- **separator-write-idempotency**: Setting a row's separator visibility to
  its own current value MUST NOT change the divider's hidden state or the
  reserved space's height.
- **separator-inset**: A row's divider MUST be inset from the row's leading
  edge by 14pt and MUST reach flush to the row's trailing edge.
- **row-content-padding**: For a standard-style row, Component MUST inset
  the wrapped content's top edge below the divider band by 9pt, and inset
  the content's bottom edge from the row's own bottom edge by the same 9pt.
- **continuation-padding**: For a continuation-style row, Component MUST
  inset the wrapped content's top edge from the divider band by `0`, while
  still applying the 9pt bottom inset.
- **row-content-horizontal-inset**: Component MUST inset the wrapped
  content's leading and trailing edges from the row's own corresponding
  edges by 14pt on each side.
- **ui-thread-confinement**: Component MUST be usable only from the UI
  thread.

## Appearance

- **Corner radius**: The card's corner radius is 10pt, set once at
  construction. Neither the component itself nor the header/caption draws a
  shape of its own.
- **Padding**: The caption-to-card gap is 6pt. Inside the card, a
  standard-style row is padded 9pt above and below its content and 14pt on
  each side; a continuation-style row takes the same 9pt bottom and 14pt
  horizontal padding but 0pt of top padding, tucking it against the row
  above. The outer stack and the row area contribute 0pt of padding beyond
  their own content.
- **Font**: The caption/header text tracks the active theme's `.caption`
  text role; weight and size are not literal in this component — they come
  from the theme's `.caption` definition. The component sets no font of its
  own on row content; each row's typography belongs to its caller-supplied
  content.
- **Background**: The card's fill is the theme's `.elevatedSurface` role.
  The component (the outer view) itself has no background color or layer.
- **Foreground/Text**: The caption/header text color is the theme's
  `.secondaryText` role. The component sets no foreground color of its own
  on row content.
- **Border**: The card has no outline of its own (no stroke). Between rows,
  a 1pt hairline divider is drawn instead, inset 14pt from the leading edge
  and flush to the trailing edge, shown only where the separator-visibility
  rule computes that one is due.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set. The only size constraint activated at runtime beyond
  internal layout is the component's own width matching its parent's width;
  height follows entirely from the header's and the accumulated rows'
  content.

## States

| State | Appearance change |
|-------|------------------|
| Default | The header and the card are added to the outer stack; the row area starts empty until a row is added — no rows, no separators. |
| Row added (standard style) | A row is appended with 9pt padding above and below its content and 14pt padding on each side; whether it also shows a leading hairline is decided separately by the separator-visibility rule. |
| Row added (continuation style) | A row is appended with 0pt top padding (tucked against the row above) and the same 9pt bottom / 14pt horizontal padding; it never shows a separator. |
| Separator shown | A standard-style row with a not-hidden predecessor: the divider is visible, separator band height = 1pt, inset 14pt from the leading edge. |
| Separator collapsed | The first row in the card, any continuation-style row, or a standard-style row with no not-hidden predecessor: the divider is hidden, separator band height = 0pt. |
| Row content hidden | A row's own hidden state mirrors its content's hidden state; the layout omits its space, and the separator-visibility rule may then collapse the separator on the row that follows it. |
| Pressed | Not applicable: the component, the card, and each row define no target/action and receive no press interaction of their own — any pressed styling belongs to a row's caller-supplied content. |
| Disabled | Not implemented in this component; an enabled/disabled state is never read or set anywhere. |
| Focused | Not styled by this component; any focus ring belongs to a row's own content, not to the container. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator. |

## Accessibility

- **Role/trait**: The component, the card, and the row area set no explicit
  accessibility role; each is exposed to assistive technology with the
  platform's ordinary default, not as a distinguished "group" container. The
  header view's own accessibility behavior belongs to that view (a static-
  text label); this component does not further style or role it.
- **Label requirements**: The component never associates the header/caption
  text with the card or the row area through any accessibility API — no
  explicit accessible label, no labelled-by relationship, no accessible
  group role. A settings group's entire visual purpose is a named card of
  rows, so a screen-reader user tabbing into the card's rows has no
  programmatic way to learn which caption group they belong to; only
  sighted proximity conveys that relationship.
- **Announce state changes**: Not applicable beyond the platform's own
  default — hiding a row's content sets that row's own hidden state, which
  removes it (and its content) from the accessibility tree automatically;
  the component performs no explicit screen-reader announcement of its own
  for a row appearing, disappearing, or a separator changing.
- **Minimum tap target**: Not applicable — the component, the card, and each
  row are layout/presentation containers with no target/action or gesture
  recognizer of their own; whatever tap targets exist belong to each row's
  own caller-supplied content and that content's own recipe.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| group-view-001 | card-surface | Construct the component with title "Example" | The card is filled with the `.elevatedSurface` role, has no stroke, and has a 10pt corner radius |
| group-view-002 | card-view-access | Construct the component, then read its card property from outside the type | Returns the same card instance the component displays |
| group-view-003 | header-from-title | Construct the component from title "Example" | The constructed header's displayed title is "Example" |
| group-view-004 | arbitrary-header-view | Construct the component with a custom view as its header | That custom view is the arranged element above the card |
| group-view-005 | header-above-card | Construct the component | The outer stack's arranged order is [header, card] |
| group-view-006 | header-card-spacing | Construct the component | The spacing between the header and the card is 6.0 |
| group-view-007 | outer-stack-edge-pinning | Construct the component | The header-and-card stack fills the component's own bounds edge-to-edge, with zero inset on all four edges |
| group-view-008 | header-width-match | Construct the component | The header's width matches the header-and-card stack's width |
| group-view-009 | card-width-match | Construct the component | The card's width matches the header-and-card stack's width |
| group-view-010 | row-area-edge-pinning | Construct the component | The internal row area fills the card's bounds edge-to-edge, with zero inset on all four edges |
| group-view-011 | row-stacking | Construct the component | The internal row area is vertical, leading-aligned, with `0` spacing between rows |
| group-view-013 | superview-width-match | Add the constructed component as a child of a parent container | The component's width matches the parent's width |
| group-view-014 | width-match-skip-without-superview | Construct the component and let it settle with no parent | No width match is attempted; no crash occurs from a missing parent |
| group-view-015 | row-append | Add a row to the group | The added view is wrapped in a row that becomes the last row in the card; the number of rows in the card grows by one |
| group-view-016 | default-row-style | Add a row with no style specified | The added row's style is the standard row style |
| group-view-017 | added-row-width-match | Add a row to the group | The new row's width matches the row area's width |
| group-view-018 | self-hiding-content-wiring | Add a row whose content can report when it hides itself, then have that content report hiding | The wrapping row's hidden state re-syncs to the content's hidden state and separators are recomputed (observable via a subsequent row's separator state changing) |
| group-view-019 | separator-recompute-on-add | Add row A, then add row B | Recomputation after each addition is observable — whether row B's row shows a separator reflects row A's row's hidden state at the time row B was added |
| group-view-020 | separator-visibility | Add three standard-style, not-hidden rows in sequence | The second and third rows show a separator; only the first does not |
| group-view-021 | first-row-headless | Add a single row as the only row | That row's divider is hidden |
| group-view-023 | ui-thread-confinement | Attempt to construct or mutate the component from off the UI thread | The call is rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking, runtime-checked otherwise) |
| group-view-024 | row-visibility-binding | Hide a row's wrapped content, then have the row resynchronize its visibility | The row's own hidden state becomes `true` |
| group-view-025 | row-visibility-at-construction | Construct a row whose wrapped content's hidden state is `true` | Immediately after construction returns, the row's own hidden state is `true` |
| group-view-026 | separator-collapse | Turn a row's separator visibility off (from on) | The row's divider becomes hidden; the space reserved for it becomes `0` |
| group-view-027 | separator-expansion | Turn a row's separator visibility on (from off) | The row's divider becomes visible; the space reserved for it becomes `1.0`pt |
| group-view-028 | separator-write-idempotency | Set a row's separator visibility to its own current value | Neither the divider's hidden state nor the reserved space's height changes as a result of this assignment |
| group-view-029 | separator-inset | Inspect a standard-style row's layout | The divider is inset 14pt from the row's leading edge; the divider reaches the row's trailing edge with no additional inset |
| group-view-030 | row-content-padding | Inspect a standard-style row's layout | The content's top edge is inset 9pt below the divider band; the content's bottom edge is inset 9pt from the row's bottom edge |
| group-view-031 | continuation-padding | Inspect a continuation-style row's layout | The content's top edge has no inset from the divider band (`0`); the content's bottom edge is still inset 9pt from the row's bottom edge |
| group-view-032 | row-content-horizontal-inset | Inspect any row's layout | The content's leading edge is inset 14pt from the row's leading edge; the content's trailing edge is inset 14pt from the row's trailing edge |

Two implementation-only construction-rule checks (autoresizing-mask
disabling and the rejection of a coder-based/decoding constructor on the
component and on a row) are platform mechanics rather than portable
behavior; see Platform Notes for how the source verifies
them there.

## Edge Cases

- Null/empty input: `title` (string, for title-based construction) and
  `header` (view, for header-view-based construction) are required,
  non-optional constructor parameters; the type system rules out a missing
  value for either (MUST — the initializer needs no nil-handling path
  because neither parameter can be absent).
- Empty `title` string (`""`): `header-from-title` still runs
  unconditionally, constructing a header whose label renders empty; the
  caption band and its 6pt spacing from the card remain in layout regardless
  (MUST, per `header-from-title` and `header-card-spacing` — there is no
  guard against an empty string).
- Boundary values: Not applicable — the component's only numeric behavior
  comes from its own fixed layout constants (10pt corner radius, 6pt
  caption spacing, 14pt horizontal inset, 9pt vertical inset, 1pt divider
  thickness); it exposes no caller-configurable numeric range of its own.
- Concurrent access: Not applicable — the component is confined to the UI
  thread (see `ui-thread-confinement`), so adding a row, updating
  separators, and every layout change are serialized on that thread.
- Error states: Not applicable — every operation in this component (adding
  a row, updating separators, syncing visibility) is a synchronous,
  non-failing call; no error-producing path exists.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own.
- Zero rows added: the row area is pinned to the card's edges, so with no
  rows the card's size is exactly the row area's size; nothing in this
  component enforces a nonzero row count or a minimum card height, so an
  unpopulated group renders as an empty rounded, elevated-surface strip
  beneath its caption (MUST, per `row-area-edge-pinning` — no
  minimum-height constraint exists anywhere in this component).
- All rows hidden simultaneously: the layout omits space for hidden rows,
  and separator recomputation only ever toggles a row's own separator
  visibility on rows still present — nothing in this component ever hides
  the card itself. The card remains present, still painted with its
  elevated-surface fill and rounded corners (see `card-surface`), collapsed
  to near-zero height, rather than disappearing. Whether a fully collapsed
  card should hide itself is an open decision this component does not
  make — see Design Decisions.
- Passing the same content view instance to the row-add operation twice:
  Precondition — callers MUST NOT add the same view instance to the group
  more than once. Adding a view to a new parent typically detaches it from
  its previous parent first, so a second call wrapping the same instance in
  a new row silently removes it from the first row, leaving that row's own
  content constraints referencing a view no longer inside its subtree — the
  layout system then has no common ancestor left to satisfy them. This
  component contains no guard against this; honoring the precondition is
  the caller's responsibility, not a behavior `row-append` is required to
  produce.
- Moving the component between two different parents: `superview-width-
  match` activates a fresh width-match constraint on every attach to a
  parent, without deactivating any constraint created for a previous
  parent. Re-parenting the same component instance leaves both width
  constraints active simultaneously, which conflicts if the two parents'
  widths ever differ (MUST-level consequence of source; this component
  never stores or deactivates a previously created width constraint — see
  Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | string | — (required, for title-based construction) | The caption text, used to build a header view placed above the card. |
| `header` | view | — (required, for header-view-based construction) | The caption view, placed above the card. Title-based construction supplies its own header view here. |
| `style` (per added row) | row style (standard or continuation) | standard | Whether the added view starts a new padded, divided row (standard) or continues the row above with no top padding and no divider (continuation). |

## Deep Linking

Not applicable: the component is a layout container inside a composable
settings layout, not a navigable screen; no URL scheme, route, or deep-link
handler applies to it.

## Localization

Not applicable: the component defines no string literals of its own.
The `title` value has no default — it is entirely caller-supplied at every
call site — so localizing it is the caller's responsibility, the same
treatment fully caller-supplied text gets in the sibling Dismissible Hint
View recipe's `text` parameter.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component contains no animation or transition; every layout change (adding a row, toggling separator visibility, hiding a row) is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: it reads no system contrast setting; the card's fill and the divider's color are theme-resolved semantic roles (`.elevatedSurface`, `.divider`), neither of which this component adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: the component conveys grouping and row separation through structure — padding and a hairline — not through color alone; whether a row shows a divider is driven by its layout effect, never by a color-only cue. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component; the caption, the card, and every added row render
unconditionally.

## Analytics

Not applicable: the component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  header view/title, its card, and the row views it is given.
- **Storage**: Not applicable — the component performs no read/write to
  disk or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this component.
- **Retention**: Not applicable — the component retains only its card, its
  two internal stacks, and its row list for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: the component contains no logging call.

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
  that the source's AppKit implementation never establishes (see Label
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
  with layout constants from `ViewLayout.swift` (`SettingsLayout.default`,
  keyed `.cardCornerRadius` = 10pt, `.captionSpacing` = 6pt,
  `.cardHorizontalInset` = 14pt, `.cardVerticalInset` = 9pt,
  `.dividerThickness` = 1pt — the source of every fixed number in this
  recipe), `ThemedBox`/`ThemedSeparatorView`/`ThemedLabel` from the
  `agenticdevelopertoolkit` submodule's `ThemedViews.swift` (`card-surface`
  is a `ThemedBox` filled with `.elevatedSurface`, `stroke: nil`), and the
  caption view from `HeaderView.swift`. A macOS-only (`import AppKit`)
  `NSView` subclass, `@MainActor`, inside the `ComposableSettings`
  namespace, built entirely on `NSStackView` and Auto Layout. The rows live
  in a private `rowStack`, each wrapped in a private `CardRow` tracked in a
  private `rows` array; a row's divider is a private `line`/
  `separatorHeight` pair, and `showsSeparator`'s `didSet` short-circuits on
  an unchanged `oldValue` to skip redundant writes — the requirements above
  describe these mechanics only by their observable effect, since any of
  these names could change under a refactor without changing what the card
  looks like or does. `ui-thread-confinement` is enforced at compile time
  by the class's `@MainActor` declaration: the Swift compiler rejects
  construction or mutation of a `GroupView` from a non-isolated context.
  `translatesAutoresizingMaskIntoConstraints` is set to `false` on the view
  itself, `outerStack`, `rowStack`, the header view, and `cardView` — an
  Auto Layout construction rule with no portable analog, required only so
  the constraint-based requirements above (`outer-stack-edge-pinning`,
  `header-width-match`, `card-width-match`, `row-area-edge-pinning`, and the
  rest) can take effect at all. Neither `GroupView` nor its row type
  supports construction via a decoding-based (`init?(coder:)`) initializer:
  both call `fatalError` instead of returning a usable instance, so no code
  path returns a decoded instance for either type. There is no UIKit code
  path in source; a UIKit port would replace `NSStackView` with
  `UIStackView`, `NSView.isHidden` with `UIView.isHidden` (the same
  removal-from-layout semantics apply within a `UIStackView`), and would
  have no `NSCoder`-only initializer restriction to fatal-error on the way
  the decoding-rejection behavior above does here.
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

**Decision** (AppKit/UIKit): Place the caption outside `cardView`, as a
sibling in `outerStack`, rather than as the card's own first row.
**Rationale**: per the source's own doc comment, "a title as the card's
first row reads as just another setting" — the caption sits outside the
card because that is what separates a group's name from its contents at a
glance.
**Approved**: pending

**Decision** (AppKit/UIKit): `addSettingSubview` takes an explicit
`style: CardRowStyle` parameter rather than inferring row style from the
added view's type.
**Rationale**: per the source's own doc comment, inferring style from type
"was inferred from the view's type once — prose was assumed to annotate the
row above it — which turned a list of plugin load failures into an
unseparated run of jammed-together lines, and sliced one model description
into six divided rows." What a view means in a card is not knowable from
what class it is, so the caller states it.
**Approved**: pending

**Decision** (AppKit/UIKit): `viewDidMoveToSuperview` activates a width
constraint equating `GroupView` to its new superview, rather than giving
`GroupView` an intrinsic or fixed width.
**Rationale**: per the source's own comment, each group fills its parent
stack's width "so that any child that wants to span the full panel (sliders
with trailing captions, dividers, etc.) actually can," while items inside
the group still control their own horizontal layout via content-hugging
priorities.
**Approved**: pending

**Decision** (AppKit/UIKit): Drive `updateSeparators()` from
`SelfHidingSettingsView`'s `onVisibilityChange` callback, rather than
observing `isHidden` via KVO or polling it.
**Rationale**: per the source's own doc comment, `GroupView` "listens so the
card can close up around a row that has hidden itself — its padding and the
hairline above it go with it," because an `NSStackView` collapses a hidden
arranged subview but the row's own padding cell is not hidden just because
its content is; without the callback, a dismissed hint leaves an empty band
and a stray divider behind.
**Approved**: pending

**Decision** (AppKit/UIKit): `viewDidMoveToSuperview` neither stores nor
deactivates a width constraint from a previous superview before activating
a new one.
**Rationale**: acceptable as shipped because every known call site adds a
`GroupView` to exactly one stable superview once and never re-parents it
afterward; documented here as the source-traceable technical debt that
surfaces specifically in the re-parenting scenario recorded under Edge
Cases, should a future caller move a `GroupView` between superviews.
**Approved**: pending

**Decision** (AppKit/UIKit): When every row in a `GroupView` is hidden,
`cardView` is left visible — collapsed to near-zero height — rather than
being hidden or removed along with its rows.
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names and restated the private-internal ones (rowStack/rows/CardRow/line/separatorHeight/oldValue) as observable outcomes; reformatted Design Decisions and added one for the all-rows-hidden open question; reframed the duplicate-add edge case as a caller precondition instead of a required behavior; converted the two fatal-error and one compile-time test vectors to static checks; moved the cookbook guideline URI out of references into related and added real external references; corrected Compliance statuses and category names and dropped invented checks; rewrote the WinUI 3 bullet around one concrete structure. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple GroupView (AppKit, macOS) source. |
