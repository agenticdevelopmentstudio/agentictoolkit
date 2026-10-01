---
id: c68fd42e-52e5-4129-9a13-2574d13a7a0e
title: Theme Picker View
domain: agentictoolkit://cookbook/ui/settings/rows/theme-picker-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a theme picker with a live preview, kept in
  sync through the app's theme-change notifications.
platforms:
- swift
- macos
tags:
- settings
- form-control
- theme
depends-on:
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
- agentictoolkit://cookbook/ui/settings/rows/theme-preview-view
related:
- agentictoolkit://cookbook/ui/settings/rows/font-picker-view
references: []
approved-by: ''
approved-date: ''
---

# Theme Picker View

## Overview

The Theme Picker View is a settings row that stacks a theme-choice control
(bound to a theme-choice view model) above a theme preview. Per its own
description, it is a compact, reusable "theme chooser + live sample" for
dropping into any settings panel that wants a quick theme switch without the
full theme editor. The choice control lists every theme (built-ins plus
custom) and, on selection, writes the chosen theme's id directly to the
shared active-theme setting. The preview is never told about that write
directly; it is driven independently by a palette-observing subscription,
which re-renders it from the current semantic palette immediately at
construction and again every time the theme manager posts its theme-change
notification or the view's own theme scope changes.

## Behavioral Requirements

- **composes-theme-choice-popup**: Component MUST construct a private
  choice control whose view model is derived from the injected theme
  store.
- **composes-theme-preview**: Component MUST construct a private theme
  preview using its default, no-argument construction (no theme passed at
  construction time).
- **stacks-popup-above-preview**: Component MUST arrange the choice control
  and the preview, in that order, inside a single leading-aligned vertical
  stack with 10pt of spacing between them.
- **pins-stack-to-view-edges**: Component MUST pin that stack's
  top/leading/trailing/bottom edges directly to its own edges with no
  additional inset, so the stack fills the component exactly (see Platform
  Notes for the mechanism used to pin it).
- **derives-choices-from-injected-store**: The theme-choice view model MUST
  set the control's title to the literal "Theme" and its choices to one
  entry per built-in and custom theme in the store, each mapping a theme to
  a label/value pair of its name and its id, in the store's own theme
  ordering (built-ins first, then custom themes).
- **defaults-to-the-persisted-theme-store**: Component's theme-store
  parameter MUST default to the app's persisted theme store — the one that
  reads and writes custom themes and the active theme id through the
  shared settings store.
- **renders-initial-preview-synchronously**: Component MUST render the
  preview's first sample synchronously during initialization: the
  palette-observing subscription's apply step MUST run before
  initialization completes, showing the current palette's theme
  immediately.
- **resyncs-preview-on-theme-change**: WHEN the theme manager posts its
  theme-change notification, the component's subscription MUST show the
  newly current palette's theme in the preview again.
- **resyncs-preview-on-matching-scope-change**: WHEN a theme-scope change
  notification is posted for the theme scope identical to the view's own
  resolved scope (resolved by walking the view's ancestor chain for the
  nearest scope-providing ancestor, or the app-wide scope if none exists),
  the component's subscription MUST show the palette's theme in the preview
  again.
- **ignores-non-matching-scope-change**: WHEN a theme-scope change
  notification is posted for a theme scope other than the view's own
  resolved scope, the component MUST NOT refresh the preview.
- **commits-selection-through-the-active-theme-setting**: WHEN the user
  picks a different item in the choice control, the resulting write
  (performed inside the choice control itself) MUST land in the shared
  active-theme setting — the same setting the theme-choice view model was
  constructed against — with no separate persistence step of the
  component's own.
- **decouples-preview-refresh-from-selection-commit**: Component MUST NOT
  refresh the preview directly from the choice control's selection path;
  no call from the control to the preview exists at all — the preview
  refreshes only through the palette-observing subscriptions described
  above (see Edge Cases for the refresh timing that results).
- **keeps-constituent-views-private**: Component MUST expose no accessor —
  public property, method, or computed value — that lets an external
  caller read or mutate the composed choice control, the composed preview,
  or the palette-observer subscription.
- **retains-the-palette-observer-for-its-lifetime**: Component MUST retain
  the constructed palette-observing subscription for its own lifetime, so
  the subscription (and the preview refresh it drives) lives exactly as
  long as the view does.

## Appearance

- **Corner radius**: Not applicable — the component sets no custom layer
  or corner radius of its own; any rounded corners belong to the composed
  choice control (uncornered, per its own recipe) or the preview's own
  internal cards, which are a separate concept.
- **Padding**: The stack's 10pt spacing is the only gap the component
  itself introduces, between the choice control and the preview. The
  stack's edges are pinned to the component's own edges with no additional
  constant, so the component contributes 0pt of outer padding beyond that
  internal 10pt gap.
- **Font**: Not applicable — no font is set by this component; the choice
  control's label font and every sample font drawn inside the preview are
  each owned by their own concept.
- **Background**: None — the component sets no background color or layer
  of its own.
- **Foreground/Text**: Not applicable — the component draws no text of
  its own; all visible text belongs to the composed choice control and
  preview.
- **Border**: None — no border is drawn or configured by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured by this
  component.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set by this component; sizing comes entirely from the
  choice control's and preview's own intrinsic/explicit sizing (the
  preview's own cards enforce a minimum width of 280pt, reasserted for the
  terminal card) composed inside the vertical stack.

## States

| State | Appearance change |
|-------|------------------|
| Default | The choice control shows the item matching the persisted active theme id (or whatever item the control selects by default if none matches, per its own recipe); the preview already shows that theme's full sample, rendered synchronously at construction. |
| Theme picked (choice control) | The choice control's own selection updates immediately; the active-theme setting is written; the preview does not change yet — see **decouples-preview-refresh-from-selection-commit**. |
| Theme changed (notification) | On the next processing turn, the theme manager posts its change notification and the preview fully re-renders. |
| Scope changed (matching) | Same preview re-render, triggered by a theme-scope change notification for this view's resolved scope. |
| Pressed | Not applicable: the component draws no button of its own; the choice control's own press appearance is its own concern. |
| Disabled | Not supported: the component exposes no enabled/disabled property and keeps its choice control private, so neither it nor a host can disable the row (unlike the choice control itself, which exposes that control publicly). |
| Focused | Not styled directly by this component; whichever child view receives keyboard focus (the choice control's own interactive element) follows its own concept's focus rendering. |
| Loading | Not applicable: construction and every refresh are synchronous; there is no asynchronous operation and no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — the component sets no accessibility
  role of its own; it is a plain container. The interactive control's own
  role is owned by the choice control, which has its own recipe
  (`agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`).
- **Label requirements**: Not applicable to this component — linking the
  control's accessible name to its own label happens inside the choice
  control's own concept, out of this component's scope; see
  `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  no loading state exists here. For disabling, see the open question under
  States.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-
  driven composition (no touch input path); the 44×44pt minimum is
  touch-interface guidance, not a pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-picker-view-001 | composes-theme-choice-popup | Construct the component with a given theme store | A choice control is among the component's descendant views, built from a theme-choice view model derived from that store |
| theme-picker-view-002 | composes-theme-preview | Construct the component | A theme preview is among the component's descendant views |
| theme-picker-view-003 | stacks-popup-above-preview | Construct the component | The choice control and the preview are arranged, in that order, top-to-bottom, inside one leading-aligned vertical stack with 10pt spacing |
| theme-picker-view-004 | pins-stack-to-view-edges | Construct the component | The stack's top/leading/trailing/bottom edges equal the component's own edges with a 0pt constant |
| theme-picker-view-005 | derives-choices-from-injected-store | Store's themes are `[{id: "a", name: "Alpha"}, {id: "b", name: "Beta"}]` | The control's choices are `[{label: "Alpha", value: "a"}, {label: "Beta", value: "b"}]` and its title is "Theme" |
| theme-picker-view-006 | defaults-to-the-persisted-theme-store | Construct the component with no theme-store argument | The control's choices equal the built-in themes followed by the persisted custom themes (in that order), each mapped to a label/value pair — the same composition the default theme store computes |
| theme-picker-view-007 | renders-initial-preview-synchronously | Construct the component | Immediately after construction, the preview's contents are already non-empty and reflect the current palette's theme — no further call is needed |
| theme-picker-view-008 | resyncs-preview-on-theme-change | Post the theme-change notification after construction | The preview is shown again with the newly current palette's theme |
| theme-picker-view-009 | resyncs-preview-on-matching-scope-change | Post a theme-scope change notification for the exact scope instance the view's own resolved scope returns | The preview is shown again |
| theme-picker-view-010 | ignores-non-matching-scope-change | Post a theme-scope change notification for a scope instance other than the one the view's resolved scope returns | The preview is NOT shown again as a result of that notification |
| theme-picker-view-011 | commits-selection-through-the-active-theme-setting | Select a different item in the choice control | The active-theme setting's value equals the selected item's represented theme id |
| theme-picker-view-012 | decouples-preview-refresh-from-selection-commit | Select a different item in the choice control | No call from the control's selection handler shows anything in the preview directly; the preview is refreshed only by a palette-observing subscription firing |
| theme-picker-view-013 | keeps-constituent-views-private | Attempt to access the choice control, the preview, or the observer from outside the component | Each access is rejected; no public API exposes any of the three |
| theme-picker-view-014 | retains-the-palette-observer-for-its-lifetime | Construct the component, retain it, then post the theme-change notification | The preview still re-renders (the subscription has not been released while the view is retained) |

## Edge Cases

- **Null/empty input**: The theme store is a non-optional, defaulted
  construction parameter; there is no null case to handle. If the store's
  themes were empty, the theme-choice view model's choices would be empty
  and the composed choice control would construct with zero items and no
  selection (its own documented empty-choices behavior, per
  `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`) —
  this component adds no additional guard of its own around that case.
- **Boundary values**: Not applicable — the component owns no numeric or
  length-bounded input of its own.
- **Concurrent access**: Not applicable — the component is confined to
  construction and mutation from a single, serialized execution context
  (see Platform Notes).
- **Error states**: Not applicable — every operation (constructing the
  stack, pinning edges, constructing the subscription) is a synchronous,
  non-throwing call; no error-producing path appears.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to in-process
  settings state and in-process notifications.
- **Observer torn down with the view**: The palette-observing subscription's
  two notification subscriptions each capture the component weakly inside
  their callbacks, and the component is the sole strong owner of the
  subscription. When the component is released, its subscription is
  released with it, and no further preview refreshes occur for that
  instance — an inherent consequence of that ownership shape rather than an
  explicit teardown call.
- **Selection-to-preview lag spans one processing turn**: Selecting an item
  writes synchronously to the active-theme setting, but every downstream
  observer of that setting — including the persisted store's own internal
  observer, which reloads the theme manager on an external change — fires
  asynchronously, hopped to the next main-queue turn. The theme manager
  then posts its change notification synchronously within that later
  turn, which is what finally triggers the preview refresh. This is
  current, source-traceable behavior across the component and its
  supporting settings/theme-manager machinery together: the preview is
  never more than one processing turn behind a selection, and the
  component performs no additional debouncing of its own on top of that.
- **Reload no-ops when the theme id round-trips to the same theme**: The
  theme manager's reload guards against reprocessing an unchanged theme
  before rebuilding the palette or posting the notification, so selecting
  the item that is already active produces no preview re-render and no
  second notification — current, source-traceable behavior that this
  recipe's **resyncs-preview-on-theme-change** requirement depends on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | Theme store | The app's default persisted theme store | Supplies the control's list of selectable themes and, through the theme-choice view model it seeds, the underlying active-theme setting the control reads and writes. |

## Deep Linking

Not applicable: the component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

The component contains no user-facing string literal of its own — it
passes no title argument to the theme-choice view model at all, so it has
no call site of its own to localize. But the choice control's title it
composes is not inert: the theme-choice view model's own default title
("Theme") is a plain string, not routed through a localization mechanism,
and because the component supplies no title of its own, every instance
shows that unlocalized "Theme" default; no localization key exists for the
control's title, and the theme-choice view model has no recipe of its own
to record the gap against. Every other visible string (choice labels,
preview sample text) is owned by its own respective concept.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component contains no animation or transition of its own; every preview refresh is an instantaneous call, which itself redraws by removing and re-adding its contents rather than animating. |
| Increase Contrast | Not applicable: the component sets no custom color of its own; all coloring belongs to the composed choice control and preview, each of which tracks the active theme (and, transitively, system contrast) through its own concept. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; the only state it introduces (which theme is active) is communicated through the control's selected item text and the preview's full rendered sample, not a color-only signal added by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears in this
component; the row always renders once constructed.

## Analytics

Not applicable: the component contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it displays the store's themes and reports the user's picked
  theme id through the standard active-theme write path.
- **Storage**: The default theme store persists custom themes and the
  active theme id through the shared settings store (persisted keys for
  custom themes and the active theme id); the component performs no
  storage access of its own beyond constructing that default and
  reading/writing through the control and view model it wires up.
- **Transmission**: Not applicable — no networking call appears in this
  component.
- **Retention**: The view retains only its own subviews (the control, the
  preview) and its subscription for its own lifetime; the theme selection
  it commits persists in the shared settings store independent of the
  view's own lifetime (see Storage).

## Logging

Not applicable: the component contains no logging call. The theme
manager's own log call on a theme change belongs to a different concept
and is out of scope for this recipe.

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 10)` with a
  `Picker("Theme", selection: $activeThemeID)` built from `store.allThemes`
  (mirroring `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`'s own SwiftUI
  note) above a theme-preview view driven by the same `SemanticPalette`
  environment value or `@Observable` theme manager the rest of the app uses.
  Do not wire the picker's `Binding` directly to the preview's input;
  instead let both read from the same published "current theme" source (an
  `@Observable` theme manager, or `.onChange(of: activeThemeID)` reacting
  only after the setting itself has changed) so the SwiftUI port keeps the
  same decoupled-refresh shape as
  **decouples-preview-refresh-from-selection-commit**.
- **Compose**: A `Column` with an `ExposedDropdownMenuBox`/`DropdownMenu`
  listing available themes (the Compose analog described in
  `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`) followed by a preview
  `Composable` that reads the current theme from a shared
  `CompositionLocal`/`ViewModel` `StateFlow` rather than being called
  directly from the dropdown's `onItemSelected` — collect the flow with
  `collectAsState()` in the preview so a selection and its preview refresh
  stay two independently observed steps, mirroring
  **decouples-preview-refresh-from-selection-commit**.
- **React/Web**: A flex column (`display: flex; flex-direction: column; gap:
  10px`) with a `<select>` of theme options (per
  `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`'s web note) above a
  preview component. Commit the selected value to global theme state (a
  context provider, a store dispatch) on `onChange`, and have the preview
  subscribe to that same global state independently (a context consumer, a
  store selector) rather than receiving the new theme as a prop passed
  straight from the `<select>`'s handler, preserving the
  notification-mediated decoupling the source uses.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePickerView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes a `PopupMenuChoiceView<String>` and a `ThemePreviewView` into a
  vertical `NSStackView`, pinned to the view's edges through the shared
  `Self.pinToEdges` helper with no additional constant. The component is
  constructed only via `init(store:)`: the fatal-erroring `init?(coder:)`
  traps at runtime, so a caller cannot construct one through that path.
  Separately, because its `popup` stored property has no default value and
  `NSView`'s designated initializer is not overridden, Swift does not
  synthesize a usable `init(frame:)` for it, so `ThemePickerView(frame:)`
  fails to compile rather than trapping at runtime. `@MainActor` confines
  construction and mutation to the main actor under Swift's concurrency
  checking. Separately, it wires a `ThemePaletteObserver` whose `apply`
  closure repaints only the preview. There is no UIKit code path in
  source; a UIKit port would replace `NSPopUpButton`-backed selection with
  a `UIButton` presenting a `UIMenu` or a dedicated theme-list screen, but
  needs no separate scope-resolution walk of its own —
  `ThemeScopeResolution.swift` already extends `PlatformView` (`UIView` on
  non-macOS platforms) identically to `NSView`.
- **WinUI 3**: Build the row as a vertical
  `StackPanel` with `Spacing="10"`: a themed `ComboBox`/`Grid` row at the top
  matching `agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`'s own WinUI 3
  note (bound to the available themes, writing the picked theme id through a
  settings service), and a preview `UserControl` beneath it. Do not update
  the preview `UserControl` directly from the `ComboBox`'s
  `SelectionChanged` handler; instead have the settings service raise its
  own `INotifyPropertyChanged`/event (the WinUI analog of
  `ThemeManager.didChangeNotification`) that both the `ComboBox`'s bound
  property and the preview's bound theme property observe independently,
  matching **decouples-preview-refresh-from-selection-commit** and
  **resyncs-preview-on-theme-change**. If the app supports multiple
  independently-themed windows (the WinUI analog of `ThemeScope`), scope
  that event per `Window`/`XamlRoot` rather than firing it
  application-wide, mirroring **resyncs-preview-on-matching-scope-change**
  and **ignores-non-matching-scope-change**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePickerView.swift` |

## Design Decisions

**Decision**: Refresh the preview only through the palette-observing
subscription's notification callbacks, never by calling into the preview
directly from the choice control's selection handler. (AppKit source.)
**Rationale**: source contains no direct call from the control to the
preview at all; the two are wired to the same app-wide active-theme
setting and theme-manager notification independently, which is what lets
the preview also react to a theme change made from somewhere else
entirely (a different settings panel, a synced change) without this
component needing to know about it.
**Approved**: pending

**Decision**: Keep the choice control, the preview, and the observer all
`private` (AppKit: Swift access control), unlike sibling rows
(`PopupMenuChoiceView`, `FontPickerView`) that expose their constituent
views publicly. (AppKit source.)
**Rationale**: source declares all three with `private` access and
provides no public accessor for any of them; this recipe documents that
as the actual, current visibility rather than assuming parity with its
siblings.
**Approved**: pending

**Decision**: Default the theme store to the app's persisted store — the
convenience initializer that persists through the shared settings store —
rather than requiring a caller to supply one. (AppKit source.)
**Rationale**: per the persisted store's own comment, "every existing
default-store call site keeps working, and keeps reading the themes
already on disk" — the default is the same persisted store every other
default call site in the app already uses.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

`native-controls-preference` and `platform-design-language` pass because the
component defers entirely to `PopupMenuChoiceView`'s and `ThemePreviewView`'s
own native-control choices rather than introducing new UI of its own.
`keyboard-navigable` and `screen-reader-support` are `partial`: this file
adds no keyboard or screen-reader behavior of its own, inheriting the
popup's own inherited `NSPopUpButton` navigation and its already-linked
accessible name from `PopupMenuChoiceView.swift` (see
`agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view`), but the popup's visible
title is the unlocalized `"Theme"` default this file cannot override (see
Localization) and the row itself offers no disable path (see States,
Disabled), so this file's own compliance can't be called a full pass.
`idempotent-operations` is `partial` for the same reason: it holds only
because `ThemeManager.reload()`'s `theme != currentTheme` guard
(`ThemeManager.swift`) makes repeated selections of the same theme a
no-op for the preview (see Edge Cases) — a property of `ThemeManager`, not
of anything `ThemePickerView.swift` itself guarantees. `separation-of-concerns`
passes because the preview refresh path is fully decoupled from the
selection commit path (see Design Decisions).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ThemePickerView, covering the popup/preview composition, the notification-mediated decoupling between selection and preview refresh, the private constituent views, and one open question on a disabled state. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated three implementation-detail requirements as observable contracts and moved their mechanics into Platform Notes; pinned three previously undated claims to source lines; replaced the suppressed Localization "Not applicable" with an open question on the unlocalized popup title; disambiguated ThemeScope identity in two requirements and test vectors 009/010, and gave test 006 a concrete expected value; dropped the incidental timing assertion from test 012; reworded three Edge Cases MUSTs to plain description; reformatted Design Decisions to the bold three-line form and removed two non-decision entries; shortened the summary; added related/depends-on domains for composed and sibling recipes; fixed a self-contradicting UIKit note and dropped WinUI aside noise; and marked three Compliance checks partial with the inherited-result explained. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
