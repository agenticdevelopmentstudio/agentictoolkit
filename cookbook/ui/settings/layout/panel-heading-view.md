---
id: 9e21151e-dc58-49a2-be1e-4984529f4396
title: Panel Heading View
domain: agentictoolkit://cookbook/ui/settings/layout/panel-heading-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A view pairing a primary-styled heading label with an optional
  wrapping caption, used above a run of settings groups in a settings panel.
platforms:
- swift
- macos
tags:
- settings
- heading
depends-on:
- agentictoolkit://cookbook/ui/settings/layout/explanation-view
related:
- agentictoolkit://cookbook/ui/settings/layout/explanation-view
- agentictoolkit://cookbook/ui/settings/layout/header-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Panel Heading View

## Overview

The Panel Heading View renders a heading over a *run* of groups, one level
above a single group's own caption — distinct from the Group View's own
header, which captions a single list of rows rather than a run of groups.
It pairs a title label (styled as a primary-emphasis heading) with an
optional caption, which — when supplied — is wrapped in the Explanation
View rather than a label of its own, so it wraps by the one policy every
settings blurb in this system shares instead of a copy of it (see the
Explanation View recipe). Use it above a panel whose groups fall into more
than one kind that a reader needs to see distinguished up front — for
example, a Key Commands panel's per-window cards, split by whether a
window's commands fire only in that app or everywhere. The one call site
that constructs a Panel Heading View, a panel's own add-heading operation,
is not part of this recipe's source; its own spacing decision is recorded
in Design Decisions, not here.

## Behavioral Requirements

- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **exposes-title-label**: The component MUST expose its heading label as
  a public, immutable stored property.
- **exposes-caption-label**: The component MUST expose a public, read-only
  computed property that returns the caption view's own label when a
  caption view exists, and nothing when it does not.
- **styles-title-as-primary-heading**: The component MUST style its
  heading label with the primary-text color role and the heading text
  role.
- **sets-title-text-from-caller**: The component MUST initialize its
  heading label's displayed text to the caller-supplied title parameter,
  unmodified.
- **creates-caption-view-when-caption-given**: When the caller-supplied
  caption parameter is non-empty/present, the component MUST construct a
  caption view (see the Explanation View recipe) built from that string.
- **omits-caption-view-when-caption-nil**: When the caller-supplied
  caption parameter is absent, the component MUST NOT construct a caption
  view; the internal caption-view reference MUST be absent too.
- **stacks-title-and-caption-vertically-leading-aligned**: The component
  MUST arrange the title label, followed by the caption view when one
  exists, in that order, as the children of a vertical stack with
  leading alignment.
- **spaces-title-from-caption**: The component MUST set the stack's
  spacing to the standard caption-spacing value (6pt), regardless of
  whether a caption view is present.
- **matches-caption-width-to-stack**: When the caption view exists, the
  component MUST constrain its width equal to the stack's width. No
  equivalent width constraint is applied to the title label.
- **fills-bounds-with-zero-inset**: The component's content MUST fill the
  view's own bounds, with zero inset on every side. (See the Platform
  Notes for the source's constraint-based mechanism.)
- **requires-title-at-construction**: The component MUST NOT be usable
  without a title supplied at construction. A bare/default construction
  path with no title, and a deserializing/decoding-based construction
  path, MUST both fail rather than produce a usable instance with no
  title (see Platform Notes for the source's exact mechanism and
  messages).

## Appearance

- **Corner radius**: Not applicable — the component has no layer or shape
  of its own.
- **Padding**: 0 around the component's own bounds — the stack is pinned
  to all four edges with no additional constant
  (**fills-bounds-with-zero-inset**). Internally, the gap between the
  title label and the caption view (when present) is the standard
  caption-spacing value; treat the 6pt current value as illustrative, not
  the assertion — the underlying token is the source of truth.
- **Font**: The title label uses the theme's heading text role
  (illustratively 15pt semibold, system font family, scaled by the active
  theme's size scale unless overridden — the token, not the literal, is
  the assertion). The caption's font is the theme's caption text role,
  applied by the caption view — see the Explanation View recipe for that
  view's own font details; this recipe does not duplicate them.
- **Background**: None/transparent — the component sets no background
  color or layer of its own, and neither the title label nor the caption
  view draws one either.
- **Foreground/Text**: The title label's text color tracks the theme's
  primary-text role, undimmed unlike the secondary-text role. The
  caption's text color is the theme's secondary-text role, applied by the
  caption view — see that recipe for its derivation and the open question
  it raises about that role's contrast.
- **Border**: None — no border is drawn or configured anywhere in this
  component.
- **Shadow**: None — no shadow is drawn or configured anywhere in this
  component.
- **Min/Max size**: None declared by the component itself. The title
  label keeps its default single-line, clipped configuration (the
  component never reconfigures its wrap settings), so it sizes to one
  non-wrapping line. The caption view, when present, wraps across as many
  lines as its width (matched to the stack's width) requires, per its own
  configuration.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders the title label's text at the primary-text/heading style; whether a caption follows depends on the caption argument given at construction. |
| Caption present | The caption view is constructed and arranged below the title label, 6pt apart, its width matched to the stack; the caption-label accessor returns its label. |
| Caption absent | The caption view is absent and never constructed; only the title label is an arranged child; the caption-label accessor returns nothing. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — the component has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no enabled property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and the platform's own default (unable to become first responder) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: The source never sets an explicit accessibility role on
  the title label; the platform exposes it, as a non-editable text field,
  as ordinary static text, not as a heading. The component's stated
  purpose (per its own doc comment) is to caption a *run* of groups the
  way a section heading would, but the source establishes that
  relationship only visually (size and weight): it sets no accessibility
  heading role/trait on the title label, so screen-reader users have no
  way to jump between panel headings the way heading navigation would let
  them.
- **Label requirements**: Satisfied for the title — the title label's
  displayed text is always the exact, caller-supplied title argument
  (**sets-title-text-from-caller**), which is also its accessible name
  under the platform's default behavior for this kind of text field. The
  caption's own label requirements are covered by the Explanation View
  recipe, not duplicated here — this component only forwards that view's
  label as its own caption-label accessor.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component defines no loading or disabled state to announce (see
  States). Whether a caption exists is fixed at construction, not a
  runtime state change this component makes after the fact.
- **Minimum tap target**: Not applicable — the source defines no
  target/action, gesture recognizer, or click handling; this is a purely
  visual, non-interactive display element with no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-heading-view-001 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking, runtime-checked otherwise) |
| panel-heading-view-002 | exposes-title-label | Construct the component with title "Section" | Its title label is accessible from outside the component |
| panel-heading-view-003 | exposes-caption-label | Construct the component with title "Section" and caption "Some blurb" | Its caption-label accessor is present and equals the constructed caption view's own label |
| panel-heading-view-004 | exposes-caption-label | Construct the component with title "Section" (no caption argument) | Its caption-label accessor is absent |
| panel-heading-view-005 | styles-title-as-primary-heading | Construct the component with title "Section" | The title label's color role is primary-text and its text role is heading |
| panel-heading-view-006 | sets-title-text-from-caller | Construct the component with title "General" | The title label's displayed text is "General" |
| panel-heading-view-007 | creates-caption-view-when-caption-given | Construct the component with title "Section" and caption "Some blurb" | The stack's arranged children include a caption view whose label reads "Some blurb" |
| panel-heading-view-008 | omits-caption-view-when-caption-nil | Construct the component with title "Section" and caption defaulted/absent | The stack's arranged children contain no caption view; the caption-label accessor is absent |
| panel-heading-view-009 | stacks-title-and-caption-vertically-leading-aligned | Construct the component with title "Section" and caption "Some blurb" | The internal stack's orientation is vertical, its alignment is leading, and its arranged children are the title label followed by the caption view, in that order |
| panel-heading-view-010 | spaces-title-from-caption | Construct the component (with or without a caption) | The internal stack's spacing equals the standard caption-spacing value (currently 6.0) |
| panel-heading-view-011 | matches-caption-width-to-stack | Construct the component with title "Section" and caption "Some blurb" | An active constraint equates the caption view's width to the stack's width; no equivalent constraint exists for the title label |
| panel-heading-view-012 | fills-bounds-with-zero-inset | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom edges to the view's corresponding edges, each with zero constant |
| panel-heading-view-013 | requires-title-at-construction | Attempt to construct the component via a bare/default construction path that supplies no title | Construction fails rather than producing a usable instance (see Platform Notes for the source's exact mechanism and message) |
| panel-heading-view-014 | requires-title-at-construction | Attempt to construct the component via a deserializing/decoding-based construction path | Construction fails rather than producing a usable instance (see Platform Notes for the source's exact mechanism and message) |

Vectors 001, 013, and 014 are compile-time or trap checks, not conventional
runtime unit tests: 001 verifies rejection under the platform's UI-thread
isolation checking, and 013/014 verify an unconditional trap; run each as
the static or trap check it is.

## Edge Cases

- **Null/empty input**: title is a required, non-optional string
  parameter, so the type system rules out a missing value. An empty
  string renders an empty title label, with no guard against it in
  source — a consequence of **sets-title-text-from-caller**. caption is
  optional and defaults to absent; an explicit empty string is still
  present/non-absent, so it still constructs a caption view whose label
  renders empty, since **creates-caption-view-when-caption-given** does
  not special-case an empty but present string.
- **Boundary values**: Not applicable in the numeric sense — the
  component's only inputs are the two caller-supplied strings; it has no
  caller-configurable numeric range. A very long title is clipped, not
  wrapped, because the component never reconfigures the title label's
  wrap settings; a very long caption wraps across more lines instead,
  because its width is matched to the stack (**matches-caption-width-to-stack**)
  while the caption view itself is configured to wrap.
- **Concurrent access**: Not applicable — the component is confined to
  the UI thread; construction or mutation of the component, its title
  label, or its caption view from off that thread is rejected.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **Caption text reassigned after construction**: The component exposes
  its caption-label accessor, so a caller with a present caption can
  reassign that label's displayed text directly, reached through the
  forwarding accessor rather than any update/set-text method the
  component itself defines. This mirrors the pattern the Explanation View
  recipe's own `updates-text-via-label-property` requirement documents
  for that view (see
  `agentictoolkit://cookbook/ui/settings/layout/explanation-view#exposes-label-property`;
  also Design Decisions).
- **Constructed with no caption and later needing one**: The caption view
  is constructed once at construction time and never reassigned; the
  source provides no way to add a caption to a component instance that
  was built without one — a caller that needs a caption supplies it at
  construction. This is a source-traceable consequence of
  **omits-caption-view-when-caption-nil**: no method exists to set the
  caption view after construction returns.

## Configuration

The Panel Heading View:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | string | — (required) | The heading's displayed text, passed to the title label unmodified. |
| `caption` | string, optional | absent | Optional caption text. When present, wrapped in a caption view and arranged below the title. When absent, no caption view is created. |

## Deep Linking

Not applicable: the component is a display-only heading inside a
composable settings panel, not a navigable screen; no URL scheme, route,
or deep-link handler appears anywhere in its source.

## Localization

Not applicable: both `title` and `caption` are entirely caller-supplied
string parameters, not literals owned by this component. The source
defines no string literal of its own that would need translation;
producing localized text is the caller's responsibility before either
parameter reaches this component.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation or transition of any kind; construction is a synchronous sequence of view and layout setup. |
| Increase Contrast | Not applicable to this component directly — the source sets no custom color and reads no system contrast setting. The title label's color is the theme's primary-text role, applied unconditionally across this whole system, not something this component computes or could get wrong independently of the palette it draws from. The caption's secondary-text role carries the open question already tracked in the Explanation View recipe; it is not repeated here. |
| Differentiate Without Color | Not applicable — the component conveys no state through color at all; it renders the caller-supplied title (and optional caption) in two fixed, fixed-role colors, with no color-coded meaning to differentiate. |

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; the view renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the view holds only the title/caption
  strings passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component.
- **Retention**: Not applicable — the view retains only its title label
  and, if constructed, its caption view, for its own lifetime.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 6)` with a
  `Text(title)` styled from the app's `.heading` theme token (the SwiftUI
  analog of `ThemeTypography.defaultStyle(.heading)`, not the built-in
  `.headline` text style, which is a different size/weight on this platform)
  for the title, and — only when `caption` is non-`nil` — a `Text(caption)
  .font(.caption).foregroundStyle(.secondary)
  .fixedSize(horizontal: false, vertical: true)` beneath it, mirroring
  `stacks-title-and-caption-vertically-leading-aligned` and
  `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil`. Give the caption `Text` no fixed
  frame beyond the parent's own width so it wraps to it, the SwiftUI analog
  of `matches-caption-width-to-stack`; leave the title unconstrained in width
  to match the source's clipped, single-line title.
- **Compose**: Use a `Column(verticalArrangement = Arrangement
  .spacedBy(6.dp), horizontalAlignment = Alignment.Start)` with a
  `Text(title, style = MaterialTheme.typography.titleMedium)` for the
  heading, and conditionally (`if (caption != null)`) a
  `Text(caption, style = MaterialTheme.typography.bodySmall, color =
  MaterialTheme.colorScheme.onSurfaceVariant)` that wraps within the
  column's own width — Compose `Text` wraps by default, mirroring the
  caption's wrapping behavior without extra configuration.
- **React/Web**: A `<hgroup>` or `<div>` containing a heading element (e.g.
  `<h3>`) styled from the primary-text/heading tokens, followed — only when
  `caption` is provided — by a `<p>` styled from the
  secondary-text/caption tokens with `white-space: normal; overflow-wrap:
  break-word` and `width: 100%` so it wraps to the container, mirroring
  `matches-caption-width-to-stack`; use `gap: 6px` (flex or grid column) for
  the title-to-caption spacing, matching `spaces-title-from-caption`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, `final`, inside the `ComposableSettings` namespace,
  conforming to `SettingsViewProtocol` (a marker protocol with no
  requirements of its own that every settings-row view in this system
  adopts), composing one `ThemedLabel` (`titleLabel`, styled `role:
  .primaryText, textRole: .heading`) and, conditionally, one
  `ExplanationView` (`captionView`) inside an `NSStackView`.
  `confines-to-ui-thread` is enforced at compile time by the class's
  `@MainActor` declaration. `fills-bounds-with-zero-inset` is met by
  setting `translatesAutoresizingMaskIntoConstraints = false` on the view
  itself, the stack, and `titleLabel` (`captionView` opts itself in inside
  `ExplanationView`'s own initializer — this component does not set it a
  second time), then activating four `NSLayoutConstraint`s pinning the
  stack's top, leading, trailing, and bottom anchors to the matching
  anchors of the view itself, each with a zero constant.
  `requires-title-at-construction` is met by overriding `init(frame
  frameRect: NSRect)` to `fatalError("init(frame frameRect: NSRect)")`
  unconditionally, and `init?(coder: NSCoder)` to `fatalError("init(coder:)
  has not been implemented")`; the only supported construction path is
  `init(title:caption:)`, which requires `title`. There is no UIKit code
  path in source. A UIKit port would replace `NSStackView` with
  `UIStackView`, `ThemedLabel`(`NSTextField`) with a `UILabel` styled for
  the heading role, and the conditionally-constructed
  `ExplanationView`/`UILabel` pairing for the caption; it would have no
  `NSCoder`-vs-frame initializer split to fatal-error on the way the
  source does.
- **WinUI 3**: Build this as a vertical
  `StackPanel` with `Spacing="6"` (the analog of
  `SettingsLayout.default[.captionSpacing]` /
  `spaces-title-from-caption`) containing a `TextBlock` styled
  `Style="{StaticResource BodyStrongTextBlockStyle}"` (or a custom style
  matching the theme's `.heading` size/weight) bound to `title`, mirroring
  `styles-title-as-primary-heading`/`sets-title-text-from-caller`. Add a
  second `TextBlock` — constructed and added to the `StackPanel.Children`
  only when `caption` is non-null, not merely hidden via `Visibility`, to
  mirror `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil` and to keep the component's own
  caption-label accessor honest for a null caption — styled
  `Style="{StaticResource CaptionTextBlockStyle}"` with
  `TextWrapping="WrapWholeWords"` and `HorizontalAlignment="Stretch"` so it
  wraps to the `StackPanel`'s own width, mirroring
  `matches-caption-width-to-stack` (a `StackPanel`'s children stretch to its
  width by default when no narrower `Width` is set, unlike the title label,
  which should keep `TextWrapping="NoWrap"` and `TextTrimming="Clip"` to
  match the source's untouched, single-line default). There is no WinUI
  equivalent of the constraint-based edge pinning needed beyond placing the
  `StackPanel` alone in its parent cell with no `Margin`, reproducing
  `fills-bounds-with-zero-inset` directly.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift` |

## Design Decisions

- **Decision**: The caption, when supplied, is wrapped in the Explanation
  View rather than being built as a second label local to this component.
  **Rationale**: per the source's own comment on `captionView`, this is "so
  it wraps inside the panel by the one policy every settings blurb shares
  instead of a copy of it" — the wrapping, compression, and hugging behavior
  a multi-line settings caption needs is owned once, by the Explanation
  View, and reused here rather than re-implemented.
  **Approved**: pending
- **Decision**: The title label's width is never constrained to the
  stack's width, while the caption view's width is
  (**matches-caption-width-to-stack**).
  **Rationale**: not explained in source comments beyond the code itself.
  The title label keeps its default single-line, clipped configuration and
  needs no width constraint to wrap correctly; the caption view wraps by
  design (per the Explanation View's own configuration) and needs a known
  width to wrap *against* — without the constraint, a wrapping label
  reports its one-line intrinsic width instead of the width the panel
  actually gives it, the same reasoning the Explanation View recipe
  documents for that view's own horizontal-compression decision.
  **Approved**: pending
- **Decision** (AppKit/UIKit): The gap above a Panel Heading View inside a
  panel is widened to `1.5×` the panel's group spacing by the panel's own
  add-heading operation, not by this component itself.
  **Rationale**: the panel's own source comment on that operation states
  "the gap above a heading is wider than the gap between two cards, because
  that gap is what says the heading belongs to what comes *after* it — at
  the stack's own spacing it reads as a caption trailing the card above."
  This spacing decision is recorded here for context because it is the one
  call site that constructs this component, but that call site's own
  source is not part of this recipe's source, so it is not a requirement of
  this component itself.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |

`screen-reader-support` is partial because the title label's text is present
and reads via the platform's default accessible-name behavior for this kind
of text field, but nothing in source marks it with an accessibility heading
role, so screen-reader users cannot navigate panel headings the way heading
navigation would let them (see Accessibility above).
`no-hardcoded-strings` passes because `title` and `caption` are entirely
caller-supplied strings, with no user-visible string literal owned by this
component itself.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: cite spacing/typography tokens instead of literals; restate two AppKit-mechanics requirements as outcomes and move their mechanism into AppKit Platform Notes; trim duplicated theme/typography prose; move the internal cookbook reference from `references` to `related` and add `explanation-view` to `depends-on`; fix Design Decision approval-line format and remove two commentary (non-decision) entries; change `screen-reader-support` from the disallowed `needs-review` status to `partial` and rebuild the Compliance table against real catalog checks (`screen-reader-support`, `no-hardcoded-strings`); drop the unsupported WinUI "reason this recipe exists" claim and point the SwiftUI note at the theme heading token instead of `.headline`; remove RFC 2119 keywords from Edge Cases in favor of citing the named requirements they follow from; mark test vectors 001/015/016 as compile-time/trap checks; trim the Overview to component identity and usage. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `PanelHeadingView` (AppKit, macOS) source. |
