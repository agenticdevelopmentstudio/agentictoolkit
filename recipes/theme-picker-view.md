---
id: c68fd42e-52e5-4129-9a13-2574d13a7a0e
title: ThemePickerView
domain: agentictoolkit://recipes/theme-picker-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "A macOS ComposableSettings row pairing a theme-choice popup with a live ThemePreviewView, kept in sync through the app-wide ThemeManager notification rather than a direct call between the two."
platforms:
- swift
- macos
tags:
- settings
- form-control
- theme
- macos
- appkit
depends-on:
- agentictoolkit://recipes/popup-menu-choice-view
related: []
references: []
approved-by: ''
approved-date: ''
---

# ThemePickerView

## Overview

`ThemePickerView` (`ComposableSettings.ThemePickerView`) is a macOS `NSView`
from the ComposableSettingsWindow system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ThemePickerView.swift`)
that stacks a `PopupMenuChoiceView<String>` (bound to a `ThemeChoiceViewModel`)
above a `ThemePreviewView`, and conforms to `SettingsViewProtocol`. Per the
source's own doc comment, it is "a compact, reusable 'theme chooser + live
sample'" for dropping into any settings panel that wants a quick theme switch
without the full theme editor. The popup lists every theme (`store.allThemes`:
built-ins plus custom) and, on selection, writes the chosen theme's `id`
directly to the shared `UserSettings.activeThemeID` setting. The preview is
never told about that write directly; it is driven independently by a
`ThemePaletteObserver`, which re-renders it from the current
`SemanticPalette` immediately at construction and again every time
`ThemeManager` posts its theme-change notification or the view's own
`ThemeScope` changes.

## Behavioral Requirements

- **composes-theme-choice-popup**: Component MUST construct a private
  `PopupMenuChoiceView<String>` whose view model is
  `ThemeChoiceViewModel(store: store)`.
- **composes-theme-preview**: Component MUST construct a private
  `ThemePreviewView` using its parameterless initializer (no theme passed at
  construction).
- **stacks-popup-above-preview**: Component MUST arrange the popup and the
  preview, in that order, inside a vertical `NSStackView` with `alignment =
  .leading` and `spacing = 10`.
- **pins-stack-to-view-edges**: Component MUST pin that stack view's
  top/leading/trailing/bottom edges directly to its own edges via
  `Self.pinToEdges`, with no additional constant.
- **derives-choices-from-injected-store**: `ThemeChoiceViewModel(store:)` MUST
  set the popup's title to the literal `"Theme"` and its choices to
  `store.allThemes.map { .init(label: $0.name, value: $0.id) }` — one choice
  per built-in and custom theme, in `allThemes`'s order (built-ins first,
  then custom themes).
- **defaults-to-the-persisted-theme-store**: Component's `store` initializer
  parameter MUST default to `ThemeStore()`, which resolves (via
  `ThemeStore`'s `AgenticToolkit`-side convenience initializer) to
  `ThemeStore(storage: UserSettingsThemeStorage())` — custom themes and the
  active theme id read and written through `UserSettings.customThemes` and
  `UserSettings.activeThemeID` respectively.
- **renders-initial-preview-synchronously**: Component MUST render the
  preview's first sample synchronously during initialization: constructing
  the `ThemePaletteObserver(host: self) { … }` invokes its `apply` closure
  immediately, before `init` returns, calling `preview.show(palette.theme)`
  with the current palette.
- **resyncs-preview-on-theme-change**: WHEN `ThemeManager.didChangeNotification`
  is posted, the component's observer MUST call `preview.show(palette.theme)`
  again with the newly current palette.
- **resyncs-preview-on-matching-scope-change**: WHEN
  `ThemeScope.didChangeNotification` is posted for the `ThemeScope` that
  equals the view's own `resolvedThemeScope` (resolved by walking the
  view's superview chain for the nearest `ThemeScopeProviding` ancestor, or
  `.app` if none exists), the component's observer MUST call
  `preview.show(palette.theme)` again.
- **ignores-non-matching-scope-change**: WHEN `ThemeScope.didChangeNotification`
  is posted for a `ThemeScope` other than the view's own resolved scope, the
  component MUST NOT call `preview.show`.
- **commits-selection-through-the-active-theme-setting**: WHEN the user picks
  a different item in the popup, the resulting write (performed inside
  `PopupMenuChoiceView`, per `agentictoolkit://recipes/popup-menu-choice-view`)
  MUST land in `UserSettings.activeThemeID` — the same `UserSetting<String>`
  `ThemeChoiceViewModel` was constructed against — with no separate
  persistence step of `ThemePickerView`'s own.
- **decouples-preview-refresh-from-selection-commit**: Component MUST NOT
  call `preview.show` directly from the popup's selection path;
  `ThemePickerView.swift` contains no call from the popup to the preview at
  all — the preview refreshes only through the `ThemePaletteObserver`
  subscriptions described above, which in practice fire on the next
  main-queue turn after a selection (see Edge Cases).
- **keeps-constituent-views-private**: Component MUST NOT expose `popup`,
  `preview`, or `observer` as public properties; all three are declared
  `private` in source, so no external caller can read or mutate the popup,
  the preview, or the observer subscription directly.
- **retains-the-palette-observer-for-its-lifetime**: Component MUST store the
  constructed `ThemePaletteObserver` in its own `private var observer`
  property so the subscription (and the preview refresh it drives) lives
  exactly as long as the view does.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **omits-a-usable-frame-only-initializer**: Component MUST NOT provide or
  inherit a callable `init(frame:)`; source declares only `init(store:)` and
  the fatal-erroring `init?(coder:)`, and because `popup` is a stored
  property with no default value and `NSView`'s designated initializer is
  not overridden, `init(frame:)` is not inherited — `ThemePickerView(frame:)`
  fails to compile rather than trapping at runtime.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — `ThemePickerView.swift` sets no
  `wantsLayer` or `cornerRadius` of its own; any rounded corners belong to
  the composed `popup` (uncornered, per `popup-menu-choice-view`) or
  `preview`'s own internal cards, which are a separate file.
- **Padding**: The stack's `spacing = 10` is the only gap `ThemePickerView`
  itself introduces, between the popup and the preview. `Self.pinToEdges`
  pins the stack's four edges to `ThemePickerView`'s own edges with no
  additional constant, so the component contributes 0pt of outer padding
  beyond that internal 10pt gap.
- **Font**: Not applicable — no font is set anywhere in `ThemePickerView.swift`;
  the popup's label font and every sample font drawn inside the preview are
  each owned by their own files (`PopupMenuChoiceView.swift`,
  `ThemePreviewView.swift`).
- **Background**: None — `ThemePickerView.swift` sets
  `translatesAutoresizingMaskIntoConstraints = false` on itself and calls no
  `wantsLayer`/background-color API.
- **Foreground/Text**: Not applicable — `ThemePickerView` draws no text of
  its own; all visible text belongs to the composed `popup` and `preview`.
- **Border**: None — no border is drawn or configured anywhere in
  `ThemePickerView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `ThemePickerView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `ThemePickerView.swift`; sizing comes entirely from
  the popup's and preview's own intrinsic/explicit sizing (the preview's own
  cards enforce a `>= 280`pt width) composed inside the vertical stack.

## States

| State | Appearance change |
|-------|------------------|
| Default | Popup shows the choice matching the persisted active theme id (or whatever item `NSPopUpButton` selects by default if none matches, per `popup-menu-choice-view`); preview already shows that theme's full sample, rendered synchronously at construction. |
| Theme picked (popup) | The popup's own selection updates immediately; `UserSettings.activeThemeID` is written; the preview does not change yet — see **decouples-preview-refresh-from-selection-commit**. |
| Theme changed (notification) | On the next main-queue turn, `ThemeManager` posts `didChangeNotification` and the preview fully re-renders via `preview.show(palette.theme)`. |
| Scope changed (matching) | Same preview re-render, triggered by a `ThemeScope.didChangeNotification` for this view's resolved scope. |
| Pressed | Not applicable: `ThemePickerView` draws no button of its own; the popup's own bezel-less press appearance is `PopupMenuChoiceView`'s concern. |
| Disabled | NEEDS REVIEW: Not implemented in source. Behavior undefined. `ThemePickerView.swift` exposes no `isEnabled` property and no way to disable itself, and — unlike `PopupMenuChoiceView`, which at least exposes its `popUpButton` for a caller to disable directly — `ThemePickerView` keeps `popup` `private`, so a host embedding this row has no path at all to disable it. A settings row plausibly needs to be disabled (its sibling `FontPickerView` implements exactly this). What is missing: whether disabling is intentionally out of scope for this row or an omission. What would settle it: a design decision on whether to add an `isEnabled` property mirroring `FontPickerView`'s, or an explicit statement that this row is always interactive. |
| Focused | Not styled directly by `ThemePickerView.swift`; whichever child view receives keyboard focus (the popup's internal `NSPopUpButton`) follows its own file's focus rendering. |
| Loading | Not applicable: construction and every refresh in `ThemePickerView.swift` are synchronous; there is no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not applicable — `ThemePickerView.swift` sets no
  accessibility role of its own; it is a plain container view. The
  interactive control's own role (`NSPopUpButton`) is owned by
  `PopupMenuChoiceView`, which has its own recipe
  (`agentictoolkit://recipes/popup-menu-choice-view`).
- **Label requirements**: Not applicable to this file — linking the popup's
  accessible name to its own label happens inside `PopupMenuChoiceView.swift`
  itself (`setAccessibilityTitleUIElement`), out of `ThemePickerView.swift`'s
  scope; see `agentictoolkit://recipes/popup-menu-choice-view`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — no
  loading state exists in `ThemePickerView.swift`. For disabling, see the
  open question under States.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView` composition (no touch input path in source); the
  44×44pt minimum is iOS/touch guidance, not a macOS pointer-interface
  requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-picker-view-001 | composes-theme-choice-popup | Construct `ThemePickerView(store: someStore)` | A `PopupMenuChoiceView<String>` is among the view's descendant views, built from a `ThemeChoiceViewModel(store: someStore)` |
| theme-picker-view-002 | composes-theme-preview | Construct `ThemePickerView` | A `ThemePreviewView` is among the view's descendant views |
| theme-picker-view-003 | stacks-popup-above-preview | Construct `ThemePickerView` | The popup and the preview are arranged, in that order, top-to-bottom, inside one leading-aligned vertical `NSStackView` with 10pt spacing |
| theme-picker-view-004 | pins-stack-to-view-edges | Construct `ThemePickerView` | The stack view's top/leading/trailing/bottom constraints equal `ThemePickerView`'s own edges with a 0pt constant |
| theme-picker-view-005 | derives-choices-from-injected-store | `store.allThemes == [ColorTheme(id: "a", name: "Alpha"), ColorTheme(id: "b", name: "Beta")]` | The popup's `viewModel.choices == [Choice(label: "Alpha", value: "a"), Choice(label: "Beta", value: "b")]` and `viewModel.title == "Theme"` |
| theme-picker-view-006 | defaults-to-the-persisted-theme-store | Construct `ThemePickerView()` with no `store` argument | The popup's choices equal `ThemeStore().allThemes` mapped to label/value pairs, i.e. the same set `UserSettings.customThemes`/`BuiltInThemes.all` would produce |
| theme-picker-view-007 | renders-initial-preview-synchronously | Construct `ThemePickerView` | Immediately after `init` returns, the preview's subviews are already non-empty and reflect the current palette's theme — no further call is needed |
| theme-picker-view-008 | resyncs-preview-on-theme-change | Post `ThemeManager.didChangeNotification` after construction | The preview's `show(_:)` is invoked again with the newly current palette's theme |
| theme-picker-view-009 | resyncs-preview-on-matching-scope-change | Post `ThemeScope.didChangeNotification` with `object` equal to the view's own `resolvedThemeScope` | The preview's `show(_:)` is invoked again |
| theme-picker-view-010 | ignores-non-matching-scope-change | Post `ThemeScope.didChangeNotification` with `object` equal to a *different* `ThemeScope` instance | The preview's `show(_:)` is NOT invoked as a result of that notification |
| theme-picker-view-011 | commits-selection-through-the-active-theme-setting | Select a different item in the popup | `UserSettings.activeThemeID.value` equals the selected item's represented theme id |
| theme-picker-view-012 | decouples-preview-refresh-from-selection-commit | Select a different item in the popup, then inspect the preview before the next main-queue turn runs | The preview has not yet been re-rendered for the new theme at that point (it updates only once `ThemeManager.didChangeNotification` is posted on a later turn) |
| theme-picker-view-013 | keeps-constituent-views-private | Attempt to access `.popup`, `.preview`, or `.observer` from outside `ThemePickerView` | Compiler rejects each access; no public API exposes any of the three |
| theme-picker-view-014 | retains-the-palette-observer-for-its-lifetime | Construct `ThemePickerView`, retain it, then post `ThemeManager.didChangeNotification` | The preview still re-renders (the observer has not been deallocated while the view is retained) |
| theme-picker-view-015 | requires-designated-initializer | Attempt `ThemePickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| theme-picker-view-016 | omits-a-usable-frame-only-initializer | Attempt to write `ThemePickerView(frame: .zero)` | Compilation fails; no such initializer is available |
| theme-picker-view-017 | confines-to-main-actor | Attempt to construct or mutate a `ThemePickerView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- **Null/empty input**: `store` (`ThemeStore`) is a non-optional, defaulted
  constructor parameter; Swift's type system rules out `nil`. If
  `store.allThemes` were empty, `ThemeChoiceViewModel`'s `choices` would be
  empty and the composed `PopupMenuChoiceView` would construct with zero
  menu items and no selection (its own documented empty-choices behavior,
  per `agentictoolkit://recipes/popup-menu-choice-view`) — `ThemePickerView.swift`
  adds no additional guard of its own around this case.
- **Boundary values**: Not applicable — `ThemePickerView.swift` owns no
  numeric or length-bounded input of its own.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`,
  so Swift's concurrency checker serializes all construction and mutation to
  the main actor.
- **Error states**: Not applicable — every operation in `ThemePickerView.swift`
  (constructing the stack, pinning edges, constructing the observer) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing API
  appears in source.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to in-process
  `UserSettings` state and in-process notifications.
- **Observer torn down with the view**: The `ThemePaletteObserver`'s two
  `NotificationCenter` subscriptions each capture `self` weakly inside their
  `sink` closures, and `ThemePickerView` is the sole strong owner of the
  observer (`private var observer`). When `ThemePickerView` deallocates, its
  `observer` deallocates with it, its `cancellables` are released, and no
  further `preview.show` calls occur for that instance — a MUST-level,
  source-traceable consequence rather than an explicit teardown call.
- **Selection-to-preview lag spans one main-queue turn**: Selecting a popup
  item writes synchronously to `UserSettings.activeThemeID` (via
  `UserSetting.value`'s setter), but every downstream observer of that
  setting — including `UserSettingsThemeStorage`'s internal
  `UserSettingObserver`, which calls `ThemeManager.reload()` on external
  change — fires asynchronously, hopped to the next main-dispatch-queue turn
  (`UserSettingObserver`'s own `.receive(on: DispatchQueue.main)`, documented
  in `UserSetting.swift`). `ThemeManager.reload()` then posts
  `didChangeNotification` synchronously within that later turn, which is
  what finally triggers `preview.show`. This is a MUST, traceable across
  `ThemePickerView.swift`, `UserSetting.swift`, and `ThemeManager.swift`
  together: the preview is never more than one main-queue turn behind a
  selection, and `ThemePickerView` performs no additional debouncing of its
  own on top of that.
- **Reload no-ops when the theme id round-trips to the same theme**:
  `ThemeManager.reload()` guards with `guard theme != currentTheme else {
  return }` before rebuilding the palette or posting the notification, so
  selecting the item that is already active produces no preview re-render
  and no second notification — a MUST, traceable to `ThemeManager.swift`,
  which this recipe's **resyncs-preview-on-theme-change** requirement
  depends on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `ThemeStore` | `ThemeStore()` (persists through `UserSettings` via `UserSettingsThemeStorage`) | Supplies the popup's list of selectable themes (`store.allThemes`) and, through the `ThemeChoiceViewModel` it seeds, the underlying `UserSettings.activeThemeID` setting the popup reads and writes. |

## Deep Linking

Not applicable: `ThemePickerView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `ThemePickerView.swift`.

## Localization

Not applicable: `ThemePickerView.swift` contains no user-facing string
literal of its own. `ThemeChoiceViewModel`'s `title: String = "Theme"`
default parameter is a plain `String`, not a literal passed directly to a
SwiftUI text view, but it is set by `ThemeChoiceViewModel.swift`, not by
`ThemePickerView.swift` — this file passes no title argument at all, so it
has nothing of its own to localize. Every other visible string (choice
labels, preview sample text) is owned by `ThemeChoiceViewModel.swift` and
`ThemePreviewView.swift` respectively.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `ThemePickerView.swift` contains no animation, transition, or `NSAnimationContext` call; every preview refresh is an instantaneous call to `preview.show(_:)`, which itself redraws by removing and re-adding subviews rather than animating. |
| Increase Contrast | Not applicable: `ThemePickerView.swift` sets no custom `NSColor` of its own; all coloring belongs to the composed `popup` and `preview`, each of which tracks the active theme (and, transitively, system contrast) through its own file. |
| Differentiate Without Color | Not applicable: `ThemePickerView.swift` conveys no state through color; the only state it introduces (which theme is active) is communicated through the popup's selected item text and the preview's full rendered sample, not a color-only signal added by this file. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `ThemePickerView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `ThemePickerView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it displays the store's themes and reports the user's picked theme id
  through the standard `UserSettings.activeThemeID` write path.
- **Storage**: The default `store: ThemeStore()` persists custom themes and
  the active theme id through `UserSettings` (`UserSettingsThemeStorage`,
  keys `theme.custom_themes` and `theme.active_theme_id`); `ThemePickerView.swift`
  performs no storage access of its own beyond constructing that default and
  reading/writing through the popup and view model it wires up.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `ThemePickerView.swift`.
- **Retention**: The view retains only its own subviews (`popup`, `preview`)
  and its `observer` for its own lifetime; the theme selection it commits
  persists in `UserSettings` independent of the view's own lifetime (see
  Storage).

## Logging

Not applicable: `ThemePickerView.swift` contains no logging call (no
`print`, `os_log`, or logger reference). `ThemeManager.swift`'s own
`os_log` call on a theme change (`"Active theme: …"`) belongs to a different
file and is out of scope for this recipe.

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 10)` with a
  `Picker("Theme", selection: $activeThemeID)` built from `store.allThemes`
  (mirroring `agentictoolkit://recipes/popup-menu-choice-view`'s own SwiftUI
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
  `agentictoolkit://recipes/popup-menu-choice-view`) followed by a preview
  `Composable` that reads the current theme from a shared
  `CompositionLocal`/`ViewModel` `StateFlow` rather than being called
  directly from the dropdown's `onItemSelected` — collect the flow with
  `collectAsState()` in the preview so a selection and its preview refresh
  stay two independently observed steps, mirroring
  **decouples-preview-refresh-from-selection-commit**.
- **React/Web**: A flex column (`display: flex; flex-direction: column; gap:
  10px`) with a `<select>` of theme options (per
  `agentictoolkit://recipes/popup-menu-choice-view`'s web note) above a
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
  vertical `NSStackView`, and separately wires a `ThemePaletteObserver` whose
  `apply` closure repaints only the preview. There is no UIKit code path in
  source; a UIKit port would replace `NSPopUpButton`-backed selection with a
  `UIButton` presenting a `UIMenu` or a dedicated theme-list screen, and
  would need its own scope-resolution walk since `ThemeScopeResolution.swift`
  already extends both `NSView` and `UIView` (`PlatformView`) identically.
- **WinUI 3** (the reason this recipe exists): Build the row as a vertical
  `StackPanel` with `Spacing="10"`: a themed `ComboBox`/`Grid` row at the top
  matching `agentictoolkit://recipes/popup-menu-choice-view`'s own WinUI 3
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

## Design Decisions

- Decision: Refresh the preview only through `ThemePaletteObserver`'s
  notification subscriptions, never by calling `preview.show` directly from
  the popup's selection handler.
  Rationale: `ThemePickerView.swift` contains no direct call from the popup
  to the preview at all; the two are wired to the same app-wide
  `UserSettings.activeThemeID` setting and `ThemeManager` notification
  independently, which is what lets the preview also react to a theme
  change made from somewhere else entirely (a different settings panel, a
  synced change) without `ThemePickerView` needing to know about it.
  Approved: pending
- Decision: Keep `popup`, `preview`, and `observer` all `private`, unlike
  sibling rows (`PopupMenuChoiceView`, `FontPickerView`) that expose their
  constituent views publicly.
  Rationale: `ThemePickerView.swift` declares all three with `private`
  access and provides no public accessor for any of them; this recipe
  documents that as the actual, current visibility rather than assuming
  parity with its siblings.
  Approved: pending
- Decision: Default `store` to `ThemeStore()`, the `AgenticToolkit`-side
  convenience initializer that persists through `UserSettingsThemeStorage`,
  rather than requiring a caller to supply one.
  Rationale: Per `UserSettingsThemeStorage.swift`'s own comment, "every
  existing `ThemeStore()` call site keeps working, and keeps reading the
  themes already on disk" — the default is the same persisted store every
  other `ThemeStore()` call site in the app already uses.
  Approved: pending
- Decision: Provide no `isEnabled`/disabled path, unlike sibling
  `FontPickerView`.
  Rationale: Not resolved by source — see the open question under States
  (Disabled); recorded here as the open question this recipe defers to a
  maintainer decision rather than inventing a disabled path the source does
  not have.
  Approved: pending
- Decision: This recipe gives `ThemePickerView` 17 behavioral requirements,
  fewer than `FontPickerView`'s 18 and comparable to `PopupMenuChoiceView`'s
  19, despite composing two child views rather than one.
  Rationale: `ThemePickerView` delegates almost all of its own interactive
  behavior to its two already-reciped children
  (`PopupMenuChoiceView`/`ThemeChoiceViewModel` for selection,
  `ThemePreviewView` for rendering) and to the shared `ThemePaletteObserver`
  helper; its own file's genuinely novel behavior is the composition, the
  notification-mediated decoupling, and the initializer/actor constraints —
  a comparable amount of distinct, source-traceable behavior to its two
  single-child siblings, not less analysis.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [meaningful-labels](agenticdevelopercookbook://compliance/accessibility#meaningful-labels) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` pass because the
component defers entirely to `PopupMenuChoiceView`'s and `ThemePreviewView`'s
own native-control choices rather than introducing new UI of its own.
`keyboard-navigable` passes on the popup's own inherited `NSPopUpButton`
navigation (per `popup-menu-choice-view`). `meaningful-labels` passes because
the popup's accessible name is already linked to its own label inside
`PopupMenuChoiceView.swift`, which this component composes unchanged.
`idempotent-operations` passes because `ThemeManager.reload()`'s
`theme != currentTheme` guard makes repeated selections of the same theme a
no-op for the preview (see Edge Cases). `separation-of-concerns` passes
because the preview refresh path is fully decoupled from the selection
commit path (see Design Decisions).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ThemePickerView, covering the popup/preview composition, the notification-mediated decoupling between selection and preview refresh, the private constituent views, and one open question on a disabled state. |
