<!-- leaf: implement-general-view-3/theme-picker-view · source: theme-picker-view.md -->

**Rules** (cite as `implement-general-view-3/theme-picker-view#<slug>`):

- `composes-theme-choice-popup` MUST
- `composes-theme-preview` MUST
- `stacks-popup-above-preview` MUST
- `pins-stack-to-view-edges` MUST
- `derives-choices-from-injected-store` MUST
- `defaults-to-the-persisted-theme-store` MUST
- `renders-initial-preview-synchronously` MUST
- `resyncs-preview-on-theme-change` MUST
- `resyncs-preview-on-matching-scope-change` MUST
- `ignores-non-matching-scope-change` MUST
- `commits-selection-through-the-active-theme-setting` MUST
- `decouples-preview-refresh-from-selection-commit` MUST
- `keeps-constituent-views-private` MUST
- `retains-the-palette-observer-for-its-lifetime` MUST
- `requires-designated-initializer` MUST
- `omits-a-usable-frame-only-initializer` MUST
- `confines-to-main-actor` MUST

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
  top/leading/trailing/bottom edges directly to its own edges with no
  additional inset, so the stack fills the view exactly (see Platform Notes,
  AppKit / UIKit, for the helper used to pin it).
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
  `ThemeScope.didChangeNotification` is posted for the `ThemeScope` instance
  identical to the view's own `resolvedThemeScope` (resolved by walking the
  view's superview chain for the nearest `ThemeScopeProviding` ancestor, or
  `.app` if none exists), the component's observer MUST call
  `preview.show(palette.theme)` again.
- **ignores-non-matching-scope-change**: WHEN `ThemeScope.didChangeNotification`
  is posted for a `ThemeScope` instance other than the view's own resolved
  scope, the component MUST NOT call `preview.show`.
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
  subscriptions described above (see Edge Cases for the refresh timing that
  results).
- **keeps-constituent-views-private**: Component MUST expose no accessor —
  public property, method, or computed value — that lets an external caller
  read or mutate the composed popup, the composed preview, or the palette
  observer subscription.
- **retains-the-palette-observer-for-its-lifetime**: Component MUST store the
  constructed `ThemePaletteObserver` in its own `private var observer`
  property so the subscription (and the preview refresh it drives) lives
  exactly as long as the view does.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **omits-a-usable-frame-only-initializer**: Component MUST NOT provide or
  inherit a callable `init(frame:)`; source declares only `init(store:)` and
  the fatal-erroring `init?(coder:)`, so `ThemePickerView(frame:)` fails to
  compile rather than trapping at runtime (see Platform Notes, AppKit / UIKit,
  for why the initializer isn't inherited).
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
  cards enforce a `>= 280`pt width, `ThemePreviewView.swift`, reasserted
  for the terminal card at `ThemePreviewView.swift`) composed inside the
  vertical stack.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `ThemeStore` | `ThemeStore()` (persists through `UserSettings` via `UserSettingsThemeStorage`) | Supplies the popup's list of selectable themes (`store.allThemes`) and, through the `ThemeChoiceViewModel` it seeds, the underlying `UserSettings.activeThemeID` setting the popup reads and writes. |

## Localization

`ThemePickerView.swift` contains no user-facing string literal of its own —
it passes no `title` argument to `ThemeChoiceViewModel` at all, so it has no
call site of its own to localize. But the popup title it composes is not
inert: `ThemeChoiceViewModel.init`'s `title: String = "Theme"` default
(`ThemeChoiceViewModel.swift`) is a plain `String`, not routed through
`String(localized:)`/`NSLocalizedString`, and because `ThemePickerView`
supplies no title of its own, every `ThemePickerView` shows that unlocalized
`"Theme"` default; no localization key exists for the popup's title, and
`ThemeChoiceViewModel` has no recipe of its own to record the gap against.
Every other visible string (choice labels, preview sample text) is owned by
`ThemeChoiceViewModel.swift` and `ThemePreviewView.swift` respectively.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `ThemePickerView.swift` contains no animation, transition, or `NSAnimationContext` call; every preview refresh is an instantaneous call to `preview.show(_:)`, which itself redraws by removing and re-adding subviews rather than animating. |
| Increase Contrast | Not applicable: `ThemePickerView.swift` sets no custom `NSColor` of its own; all coloring belongs to the composed `popup` and `preview`, each of which tracks the active theme (and, transitively, system contrast) through its own file. |
| Differentiate Without Color | Not applicable: `ThemePickerView.swift` conveys no state through color; the only state it introduces (which theme is active) is communicated through the popup's selected item text and the preview's full rendered sample, not a color-only signal added by this file. |

