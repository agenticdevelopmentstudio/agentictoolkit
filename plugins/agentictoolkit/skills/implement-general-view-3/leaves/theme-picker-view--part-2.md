<!-- leaf: implement-general-view-3/theme-picker-view--part-2 · source: theme-picker-view.md -->

# ThemePickerView — continued (part 2)

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
  vertical `NSStackView`, pinned to the view's edges through the shared
  `Self.pinToEdges` helper with no additional constant. `ThemePickerView`
  declares only `init(store:)` and the fatal-erroring `init?(coder:)`; because
  its `popup` stored property has no default value and `NSView`'s designated
  initializer is not overridden, Swift does not synthesize a usable
  `init(frame:)` for it, so `ThemePickerView(frame:)` fails to compile.
  Separately, it wires a `ThemePaletteObserver` whose `apply` closure repaints
  only the preview. There is no UIKit code path in source; a UIKit port would
  replace `NSPopUpButton`-backed selection with a `UIButton` presenting a
  `UIMenu` or a dedicated theme-list screen, but needs no separate
  scope-resolution walk of its own — `ThemeScopeResolution.swift` already
  extends `PlatformView` (`UIView` on non-macOS platforms) identically to
  `NSView`.
- **WinUI 3**: Build the row as a vertical
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

**Decision**: Refresh the preview only through `ThemePaletteObserver`'s
notification subscriptions, never by calling `preview.show` directly from
the popup's selection handler.
**Rationale**: `ThemePickerView.swift` contains no direct call from the
popup to the preview at all; the two are wired to the same app-wide
`UserSettings.activeThemeID` setting and `ThemeManager` notification
independently, which is what lets the preview also react to a theme
change made from somewhere else entirely (a different settings panel, a
synced change) without `ThemePickerView` needing to know about it.
**Approved**: pending

**Decision**: Keep `popup`, `preview`, and `observer` all `private`, unlike
sibling rows (`PopupMenuChoiceView`, `FontPickerView`) that expose their
constituent views publicly.
**Rationale**: `ThemePickerView.swift` declares all three with `private`
access and provides no public accessor for any of them; this recipe
documents that as the actual, current visibility rather than assuming
parity with its siblings.
**Approved**: pending

**Decision**: Default `store` to `ThemeStore()`, the `AgenticToolkit`-side
convenience initializer that persists through `UserSettingsThemeStorage`,
rather than requiring a caller to supply one.
**Rationale**: Per `UserSettingsThemeStorage.swift`'s own comment, "every
existing `ThemeStore()` call site keeps working, and keeps reading the
themes already on disk" — the default is the same persisted store every
other `ThemeStore()` call site in the app already uses.
**Approved**: pending
