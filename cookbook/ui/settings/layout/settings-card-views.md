---
id: afa90dd0-0ee6-435b-8cac-f5c6065e7496
title: Settings Card Views
domain: agentictoolkit://cookbook/ui/settings/layout/settings-card-views
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A caption, card, row, divider, and native-search-field vocabulary
  composing a settings panel, sharing layout metrics with the sibling group
  view component.
platforms:
- swift
- macos
tags:
- card
- settings
- group
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/header-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Settings Card Views

## Overview

This settings-card vocabulary is the declarative-framework counterpart to
the same panel chrome a native-framework component vocabulary draws
elsewhere in this cookbook: a caption above a rounded, elevated card (the
group container), the rounded card itself, one row's padding inside the
card, the hairline between two rows, a live-filtering search field
wrapping a genuine native search control, and a panel-level padding
operation. All six read the same shared layout metrics the sibling group
view component uses, so a panel composed either way lands on the same
grid. Rows are composed by the caller rather than collected by the
container, so a card can hold a run of uniform rows, an action row, and an
empty state without the container needing to know which is which.

## Behavioral Requirements

- **group-caption**: The group container MUST render its title, styled
  with the caption text role and the secondary-text foreground color,
  above the card, when a title is given.
- **group-omits-caption-when-title-absent**: The group container MUST NOT
  render any caption when no title is given.
- **group-caption-spacing**: The group container MUST separate its
  caption, when rendered, from the card beneath it by the standard
  caption-spacing value (6pt).
- **group-stretches-full-width**: The group container MUST stretch to the
  full width offered by its container, leading-aligned.
- **group-title-not-auto-localized**: The group container MUST NOT
  localize its title automatically; it MUST render the title exactly as
  the caller supplied it, with no lookup against a string catalog.
- **card-fills-rounded-elevated-surface**: The card MUST paint its
  content's background with the elevated-surface theme color, clipped to
  a continuous corner radius of the standard card-corner-radius value
  (10pt).
- **card-stretches-full-width**: The card MUST stretch its content to the
  full width offered by its container, leading-aligned.
- **card-row-insets-content**: A card row MUST inset its content by the
  standard card-horizontal-inset value (14pt) horizontally and the
  standard card-vertical-inset value (9pt) vertically.
- **card-row-stretches-full-width**: A card row MUST stretch its content
  to the full width offered by its container, leading-aligned.
- **divider-renders-hairline**: The divider MUST render a horizontal
  hairline exactly the standard divider-thickness value (1pt) tall, filled
  with the divider theme color, filling the width offered by its
  container.
- **divider-insets-from-leading-edge**: The divider MUST inset its
  hairline from the leading edge by the standard card-horizontal-inset
  value (14pt), with no trailing inset.
- **panel-inset-pads-uniformly**: The panel-inset operation MUST apply the
  standard panel-inset value (20pt) of padding uniformly on all four edges
  of the view it is applied to.
- **search-field-wraps-native-control**: The search field MUST render its
  text-entry surface using a genuine native search-field control, not a
  custom-drawn substitute.
- **search-field-filters-live**: The search field MUST be configured so a
  keystroke triggers the search action immediately, rather than waiting
  for a submit action.
- **search-field-writes-through-binding**: The search field MUST write
  its current text to the caller-supplied text value whenever its search
  action fires.
- **search-field-avoids-cursor-jump**: The search field MUST reassign its
  underlying text only when it differs from the caller-supplied text
  value, so reassigning an unchanged value does not move the insertion
  point.
- **search-field-sizes-to-fitting-height**: The search field MUST report
  the wrapped native control's own natural height as its height, and the
  proposed width when one is offered, falling back to the control's own
  natural width otherwise.
- **search-field-placeholder-not-auto-localized**: The search field MUST
  render its placeholder text exactly as the caller supplied it, with no
  automatic localization applied.

## Appearance

- **Corner radius**: The card clips to the standard card-corner-radius
  value (10pt), using a continuous (squircle) corner style.
- **Padding**: A card row insets its content 14pt horizontal by 9pt
  vertical; the group container spaces its caption from its card by 6pt;
  the panel-inset operation pads a whole panel 20pt on all sides.
- **Font**: The group container's caption uses the caption text role — 11pt,
  regular weight, the platform's system font family, scaled by the active
  theme's size scale unless the theme overrides the caption style.
- **Background**: The card fills with the elevated-surface theme color.
  The default derivation is the theme's background blended 12% toward its
  foreground, unless the active theme supplies an explicit override for
  that role.
- **Foreground/Text**: The group container's caption text color tracks the
  secondary-text role — the theme's foreground dimmed 32% toward its
  background with a 3.0 minimum-contrast floor, unless overridden. The
  divider fills with the divider role — the background blended 10% toward
  the foreground, unless overridden.
- **Border**: None on any of the six pieces of this vocabulary; the card
  sets no stroke, and the divider is itself a filled hairline rather than
  a bordered shape.
- **Shadow**: None; no shadow appears anywhere in this vocabulary.
- **Min/Max size**: None fixed by the group container, card, card row, or
  divider — each sizes to its content plus the padding above. The search
  field reports its wrapped native control's own natural height as its
  height, and the proposed width (or the control's own natural width if
  none is offered) — "its own height, the width it is offered."

## States

| State | Appearance change |
|-------|------------------|
| Default | The group container, card, card row, and divider render exactly the static appearance described above; there is no other visual state for any of them. The search field shows the wrapped control's placeholder or current text. |
| Pressed | Not applicable: none of the six pieces wires a target/action, gesture recognizer, or tap handler of its own. The search field's clear button and magnifier icon are the native control's own chrome. |
| Disabled | Not applicable: an enabled/disabled state is never read or set on any of the six pieces. |
| Focused | Not applicable for the group container, card, card row, and divider, which accept no keyboard focus. For the search field, no custom focus styling is applied — wrapping a genuine native search control means the system supplies the native focus ring automatically, the explicit reason this vocabulary does not hand-roll the control (see Design Decisions). |
| Loading | Not applicable: none of the six pieces performs asynchronous work or defines a loading indicator. |

## Accessibility

- **Role/trait**: The group container's caption sets no explicit heading
  trait; it reuses the sibling header component's exact role assignment
  (secondary-text color, caption text role — see Design Decisions), and
  the same open question about exposing it as a heading is tracked in that
  component's own recipe rather than re-raised here. The card, card row,
  and divider set no accessibility role of their own; they are pure
  layout/paint containers, and the platform applies its own default
  container/decoration behavior. The search field wraps a genuine native
  search control, so the system's search-field accessibility role, rotor
  behavior, and clear-key behavior are native to that control rather than
  something this vocabulary adds — exactly the alternative to "a
  hand-drawn stand-in" its own rationale calls out.
- **Label requirements**: The group container's caption text is both the
  visible and accessible content of the caption, since the title is
  displayed verbatim with no separate accessibility label. The search
  field's placeholder becomes the wrapped control's own placeholder text,
  which the platform also exposes as part of that control's default
  accessibility description; no separate accessibility label is set.
- **Announce state changes**: Not applicable — none of the six pieces
  defines a state that changes (see States); there is nothing for a
  screen reader to announce beyond the wrapped search control's own native
  announcements of its text changing.
- **Minimum tap target**: Not applicable for the group container, card,
  card row, and divider, none of which is an interactive control. The
  search field's tappable target (text bezel, clear button) is entirely
  the wrapped native control's own sizing, not a size this vocabulary
  computes.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented. The divider
  fills with the divider role, derived as the background blended only 10%
  toward the foreground, with no check that blend against the 3:1
  non-text contrast ratio a meaningful UI boundary is expected to meet.
  What is missing is a minimum-contrast floor on the divider role (as the
  secondary-text role has) or a per-theme contrast measurement. Settling
  it needs the divider-to-elevated-surface ratio measured under every
  shipped theme, or a decision that the divider is decorative and exempt
  from that guidance.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-card-views-001 | group-caption | Construct a group container titled "Section" wrapping a single row | A caption showing "Section" in the caption font and secondary-text color appears above the card |
| settings-card-views-002 | group-omits-caption-when-title-absent | Construct a group container with no title, wrapping a single row | No caption is rendered; only the card appears |
| settings-card-views-003 | group-caption-spacing | Construct a titled group container and measure the rendered layout | The vertical gap between the caption's bottom edge and the card's top edge is 6pt |
| settings-card-views-004 | group-stretches-full-width | Place a group container in a container 400pt wide | The rendered group container occupies the full 400pt width, leading-aligned |
| settings-card-views-005 | group-title-not-auto-localized | Add a string-catalog entry mapping the literal string passed as the title to a different translation, then render the group container with that same text held in a variable | The caption displays the original untranslated string, not the localized entry |
| settings-card-views-006 | card-fills-rounded-elevated-surface | Render a card with solid content under a known theme | The card's background pixel color matches the theme's elevated-surface value, and its clip shape is a continuous-corner rounded rectangle with radius 10 (or matches a snapshot-test baseline for the rendered corner) |
| settings-card-views-007 | card-stretches-full-width | Place a card in a container 400pt wide | The rendered card occupies the full 400pt width, leading-aligned |
| settings-card-views-008 | card-row-insets-content | Render a card row wrapping a single label inside a card of known width | The label's frame is inset 14pt from each side edge and 9pt from top and bottom |
| settings-card-views-009 | card-row-stretches-full-width | Place a card row in a container 400pt wide | The rendered row occupies the full 400pt width, leading-aligned |
| settings-card-views-010 | divider-renders-hairline | Render a divider under a known theme | A horizontal bar exactly 1pt tall appears, filled with the theme's divider color |
| settings-card-views-011 | divider-insets-from-leading-edge | Render a divider inside a card 400pt wide | The hairline starts 14pt from the leading edge and extends to the trailing edge with no trailing inset |
| settings-card-views-012 | panel-inset-pads-uniformly | Apply the panel-inset operation to a 300×300pt view | The modified view's content is inset 20pt on all four sides |
| settings-card-views-013 | search-field-wraps-native-control | Instantiate a search field with a placeholder and a bound text value, and inspect the produced view hierarchy | The produced view is, or contains, a genuine native search-field control |
| settings-card-views-014 | search-field-filters-live | Inspect the native control the search field creates | The control is configured to send its search action on every keystroke rather than waiting for a submit action |
| settings-card-views-015 | search-field-writes-through-binding | Type a character into the live field so its search action fires | The bound text value updates to the field's new text |
| settings-card-views-016 | search-field-avoids-cursor-jump | Place the insertion point mid-string in the field, then update it with a text value equal to the field's current text | The field's text is not reassigned and the insertion point does not move |
| settings-card-views-018 | search-field-sizes-to-fitting-height | Ask the search field to size itself with a proposed width of 200 and no proposed height | The returned height equals the wrapped control's own natural height, and the returned width is 200 |
| settings-card-views-019 | search-field-placeholder-not-auto-localized | Add a string-catalog entry mapping the literal string passed as the placeholder to a different translation, then construct the search field with that same text held in a variable | The field's placeholder shows the original untranslated string |

One requirement from the source implementation — keeping a rebindable
write-back target in sync across repeated re-renders of the surrounding
declarative view — is a mechanic of bridging a native control into a
declarative UI framework rather than a portable behavior; see Platform Notes. Two further checks against restricting a type's visibility
to its own defining module are a language-level access-control concern
with no user-visible effect; see Design Decisions and Platform Notes.

## Edge Cases

- **Null/empty input**: The group container's title is optional; omitting
  it entirely skips the caption (settings-card-views-002), while an
  explicit empty string still renders an empty-but-present caption line —
  the source guards against an absent title only, not against an empty
  string, since an empty string is a valid, distinct value. The search
  field's text value starting empty is valid and shows the placeholder.
- **Boundary values**: The group container's caption sets no line limit
  or truncation mode, so a very long title wraps across multiple lines
  within the leading-aligned stack rather than clipping to one line the
  way the sibling header component's single-line label does — a real
  behavioral difference between the two rendering paths, not an
  idealization. The search field imposes no maximum length on its text.
- **Concurrent access**: Not applicable for the four pure layout pieces —
  each is confined to the UI thread by the declarative framework's own
  rendering model. The search field's write-back path is likewise
  serialized to the UI thread.
- **Error states**: Not applicable — none of the six pieces has a
  dependency on network, database, or file-system access; there is no
  error path of any kind.
- **Offline/disconnected state**: Not applicable — none of the six pieces
  performs networking.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Title | string, optional | absent | The group container's optional caption text, rendered above the card when given |
| Content | one or more child views | required | The rows the group container, card, and card row wrap and lay out |
| Placeholder | string | empty | The search field's placeholder text |
| Text | two-way-bound string | required | The search field's two-way-bound current search string |

## Deep Linking

Not applicable: the group container, card, card row, divider, search
field, and panel-inset operation are chrome and layout for whatever
content a caller places inside a settings panel — none of them has a
navigable identity, route, or resource of its own that a deep link could
target.

## Localization

Title (group container) and placeholder (search field) are the only
user-facing strings in this vocabulary, and both are opaque,
caller-supplied values with no fixed key or default of their own — there
is no string-catalog entry to list. Neither is localized automatically:
title is rendered verbatim rather than resolved against a localization
table, and placeholder is set at runtime the same way, never looked up
against a localization table. Producing an already-localized string
before it reaches either parameter is the caller's responsibility.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: none of the six pieces applies an animation, transition, or motion effect of its own — every one is built once from static layout, with no looping effect anywhere. |
| Increase Contrast | Applies, but is not handled here: the group container's caption reuses the secondary-text role (3.0 minimum-contrast floor) and 11pt caption size that the sibling header component's caption also uses — the open question about raising that floor for Increase Contrast is tracked in that component's own recipe and not re-raised here. The divider's own role (10% blend, no stated minimum-contrast floor) raises the same open question independently — see the open question on minimum-contrast-ratio. |
| Differentiate Without Color | Not applicable: none of the six pieces conveys state or meaning through color alone — each renders exactly one presentation, with no color-coded distinction for an alternate cue to replace. |

## Feature Flags

Not applicable: no feature-flag check gates any of the six pieces; all
six construct and lay out unconditionally.

## Analytics

Not applicable: this vocabulary emits no analytics, tracking, or
telemetry. The search field forwards keystrokes to its bound text value
only; it reports nothing about what the user typed or searched for.

## Privacy

- **Data collected**: The search field's text value holds whatever search
  string the user types; it exists only in memory for the lifetime of the
  view and the state it is bound to. Nothing else in this vocabulary
  collects data.
- **Storage**: Not applicable — nothing in this vocabulary persists title,
  text, or placeholder anywhere; any persistence is entirely the caller's
  concern.
- **Transmission**: Not applicable — no network or IPC call appears
  anywhere in this vocabulary.
- **Retention**: Not applicable — no data outlives the view instances that
  hold it in memory.

## Logging

Not applicable: this vocabulary contains no logging calls anywhere.

## Platform Notes

- **SwiftUI (source)**: `SettingsCardViews.swift` is macOS-only SwiftUI,
  built entirely from stock view modifiers (`VStack`, `.background`,
  `.clipShape`, `.padding`, `.frame`) plus one `NSViewRepresentable`
  (`SettingsSearchField`) bridging AppKit's `NSSearchField`. Every metric
  it draws with comes from the same `ComposableSettings.SettingsLayout.default`
  subscript the AppKit `GroupView`/`CardRow` pair reads, which is what
  keeps a SwiftUI-authored panel on the same grid as an AppKit-authored
  one. `SettingsGroup` renders its caption via `Text(title)` styled `.caption`
  with the `secondaryText` color; because `title` is a `String` value
  rather than a `LocalizedStringKey` literal, it resolves through `Text`'s
  un-localized initializer (**group-title-not-auto-localized**), and
  `SettingsSearchField`'s `placeholder` likewise reaches
  `ThemedSearchField.placeholderString` verbatim
  (**search-field-placeholder-not-auto-localized**). `SettingsCard` clips
  with `RoundedRectangle(cornerRadius: 10, style: .continuous)`.
  `SettingsSearchField`'s `NSViewRepresentable.Coordinator` re-captures the
  current `text` binding on every `updateNSView` call, so the field's
  action always writes through the binding the current SwiftUI body
  captured rather than a stale one from an earlier render — a mechanic of
  bridging a native `NSSearchField` into SwiftUI's declarative re-render
  model, with no equivalent needed on a platform with no such bridge.
  `sizeThatFits` reports `nsView.fittingSize.height` as its height and the
  proposed width when one is offered, falling back to
  `nsView.fittingSize.width` otherwise. `SettingsCard` and
  `SettingsSearchField` are declared with no access modifier (internal),
  restricting their use to code inside the defining module — a Swift
  access-control choice with no runtime behavior of its own (see Design
  Decisions).
- **Compose**: Build the card with a Material 3 `Surface` (`shape =
  RoundedCornerShape(10.dp)`, `color = MaterialTheme.colorScheme.surfaceContainerHigh`
  or an equivalent elevated-surface token, `tonalElevation` for the raised
  look) holding a `Column` of rows, each an inset `Row`/`Box` with
  `Modifier.padding(horizontal = 14.dp, vertical = 9.dp)`; use
  `HorizontalDivider(modifier = Modifier.padding(start = 14.dp))` for the
  hairline, matching the leading-only inset. For the search field,
  Material 3's `SearchBar`/`DockedSearchBar` composable is the closest
  native equivalent — it already provides live `onQueryChange` callbacks
  and built-in accessibility, mirroring what wrapping a real native search
  control buys over a hand-rolled text field.
- **React/Web**: A `<section>` for the group with a labelled `<span>`
  caption above it — matching the source, which gives its caption no
  heading trait (see the open question under Accessibility) — a `<div>`
  styled `border-radius: 10px` and a background CSS custom property for
  the card, `padding: 9px 14px` per row, and a 1px `<hr>`/bordered `<div>`
  inset `margin-left: 14px` for the divider. Use `<input type="search">`
  for the search field — its native type gives Escape-to-clear and a
  search accessibility role in supporting browsers, the same argument
  used here for wrapping a genuine native search control instead of a
  bare `<input type="text">`.
- **AppKit / UIKit**: The AppKit translation of this exact vocabulary
  already exists elsewhere in this cookbook as the group view (caption +
  card), the themed box (the card's fill and corner radius), the private
  card row (row insets and separator), the themed separator view (the
  hairline), and the themed search field (the search field) — this
  SwiftUI vocabulary exists specifically to mirror them. A UIKit port
  with no AppKit sibling to mirror would use `UIStackView` for
  composition, a `UIView` with `layer.cornerRadius = 10` and
  `layer.cornerCurve = .continuous` for the card (matching this
  vocabulary's continuous curve, unlike the AppKit sibling's default
  circular curve — see Design Decisions), and `UISearchTextField`/`UISearchBar`
  in place of `NSSearchField` for the live-filtering field. `SettingsCard`
  and `SettingsSearchField`'s internal-only visibility
  (**card-stays-internal**/**search-field-stays-internal**, moved out of
  normative here) is a Swift access-control decision with no UIKit-side
  behavioral consequence beyond restricting which module can reference the
  type by name.
- **WinUI 3**: Build the card as a `Border` with `CornerRadius="10"` and
  `Background` bound to a brush equivalent to the elevated-surface role
  (Fluent 2's `CardBackgroundFillColorDefaultBrush` is the closest stock
  token), containing a `StackPanel` of rows; give each row a
  `Grid`/`StackPanel` with `Padding="14,9,14,9"` to match the
  card-horizontal/vertical insets, and separate rows with a 1px-tall
  `Rectangle` (or a `MenuFlyoutSeparator`-style `Border`) whose
  `Margin="14,0,0,0"` reproduces the leading-only inset and whose `Fill`
  binds to a divider-equivalent brush. Put the caption above the `Border`
  as a `TextBlock` styled `Style="{StaticResource CaptionTextBlockStyle}"`
  (or a custom style matching the port's 11pt caption size) with
  `Margin="0,0,0,6"` for the caption-to-card gap, and foreground bound to
  a secondary-text brush (`TextFillColorSecondaryBrush` is Fluent 2's
  stock equivalent). For the live-filtering search field, use
  `AutoSuggestBox` with its `TextChanged` event (fires per keystroke, the
  WinUI analog of sending the search action immediately) rather than
  waiting for a submit action — or a plain `TextBox` with a
  magnifying-glass `FontIcon` prefix if `AutoSuggestBox`'s suggestion
  popup is not wanted. Apply the panel-level inset with `Padding="20"` on
  the panel's root container.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SettingsCardViews.swift` |

## Design Decisions

**Decision** (Swift): The card is declared with no access modifier
(internal), while the group container, card row, and divider are given
public access.
**Rationale**: The source's own doc comment states it directly:
"Internal: `SettingsGroup` is the way to draw one. A card without the
caption above it is half a group, and the two were published together
only because they were written together." The card is an implementation
detail of the group, not a sanctioned standalone entry point.
**Approved**: pending

**Decision** (SwiftUI / AppKit): The card clips its content with a
continuous ("squircle") corner curve, while the AppKit sibling's
equivalent card sets a layer corner radius using that framework's default
(circular) corner curve.
**Rationale**: Not explained in source comments. Both land on the same
10pt radius from the shared layout metrics, but the two curve styles are
not pixel-identical — a real, minor divergence between the two render
paths the file's own comment says exist "so a panel written either way
lands on the same grid."
**Approved**: pending

**Decision**: The group container's caption reuses the sibling header
component's exact role assignment (secondary-text color, caption text
role) rather than defining its own style.
**Rationale**: The source doc comment frames this vocabulary as the
declarative-framework half of the same panel vocabulary the sibling
native component draws, reading the same layout metrics so a panel lands
on the same grid regardless of which framework composed it. The
heading-trait accessibility question this raises is already tracked in
the sibling header component's recipe and is deliberately not re-raised
here (see Accessibility).
**Approved**: pending

**Decision**: Title and placeholder are passed straight through to their
respective rendered text with no automatic localization.
**Rationale**: Not explained in source comments. Producing an
already-localized string is the caller's responsibility before either
parameter is reached (see the SwiftUI Platform Note for how the source
avoids automatic-localization resolution).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |

`screen-reader-support` passes because `SettingsSearchField`'s only interactive control is a genuine `NSSearchField` (`ThemedSearchField`), which carries its own search-field accessibility role and description; the four pure layout views (`SettingsGroup`, `SettingsCard`, `SettingsCardRow`, `SettingsCardDivider`) render no interactive elements of their own. `keyboard-navigable` passes for the same reason — `NSSearchField`'s native focus, typing, and Escape-to-clear behavior come for free from wrapping the real control (see Focused in States). `dynamic-type-support` is partial because the caption's `.caption` style is scaled by the active theme's `sizeScale` (`ThemeTypography.defaultStyle(.caption)`), and whether that tracks the system's text-size preference depends on the active theme, which this file cannot determine on its own. `contrast-ratio` is partial because the `secondaryText` and `divider` roles each guarantee only a fixed minimum-contrast floor (3.0 and unstated, respectively) from their derivation formula, not a guarantee that any specific active theme clears WCAG's 4.5:1 (text) or 3:1 (non-text UI) thresholds — see the open question on minimum-contrast-ratio. `no-hardcoded-strings` passes because the file's only user-facing text, `title` and `placeholder`, are caller-supplied parameters with no literal string of this file's own baked in (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: move the platform-design-languages guideline reference from `references` to `related`; fix Design Decision approval-line formatting; rename requirements to subject-only names (`group-caption`, `group-caption-spacing`, `search-field-coordinator-binding`); split `card-and-search-field-stay-internal` into `card-stays-internal` and `search-field-stays-internal` (only the card's internal access has a Design Decision behind it) with a matching new test vector; drop layout literals duplicated between Behavioral Requirements and Appearance, keeping Appearance as the single source; make the corner-radius and coordinator-rebind test vectors assert checkable outcomes; pick a `<span>` for the React caption; fix the five-views-plus-one-modifier count and a frameworks' possessive typo; remove leftover template boilerplate from Accessibility Options; and correct the Compliance table to cite only real catalog checks. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
