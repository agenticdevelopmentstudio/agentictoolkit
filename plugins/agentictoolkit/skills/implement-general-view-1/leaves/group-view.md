<!-- leaf: implement-general-view-1/group-view · source: group-view.md -->

**Rules** (cite as `implement-general-view-1/group-view#<slug>`):

- `card-surface` MUST
- `card-view-access` MUST
- `header-from-title` MUST
- `arbitrary-header-view` MUST
- `header-above-card` MUST
- `header-card-spacing` MUST
- `outer-stack-edge-pinning` MUST
- `header-width-match` MUST
- `card-width-match` MUST
- `row-area-edge-pinning` MUST
- `row-stacking` MUST
- `autoresizing-mask-disabled` MUST
- `superview-width-match` MUST
- `width-match-skip-without-superview` MUST
- `row-append` MUST
- `default-row-style` MUST
- `added-row-width-match` MUST
- `self-hiding-content-wiring` MUST
- `separator-recompute-on-add` MUST
- `separator-visibility` MUST
- `first-row-headless` MUST
- `designated-initializer-requirement` MUST
- `main-actor-confinement` MUST
- `row-visibility-binding` MUST
- `row-visibility-at-construction` MUST
- `separator-collapse` MUST
- `separator-expansion` MUST
- `separator-write-idempotency` MUST
- `separator-inset` MUST
- `row-content-padding` MUST
- `continuation-padding` MUST
- `row-content-horizontal-inset` MUST
- `row-designated-initializer-requirement` MUST

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

