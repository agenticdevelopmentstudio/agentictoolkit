<!-- leaf: implement-general-view-3/theme-picker-view--edge-cases · source: theme-picker-view.md -->

# ThemePickerView

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
  further `preview.show` calls occur for that instance — an inherent,
  source-traceable consequence of that ownership shape rather than an
  explicit teardown call.
- **Selection-to-preview lag spans one main-queue turn**: Selecting a popup
  item writes synchronously to `UserSettings.activeThemeID` (via
  `UserSetting.value`'s setter), but every downstream observer of that
  setting — including `UserSettingsThemeStorage`'s internal
  `UserSettingObserver` (`UserSettingsThemeStorage.swift`), which calls
  `ThemeManager.reload()` on external change (`ThemeManager.swift`) —
  fires asynchronously, hopped to the next main-dispatch-queue turn
  (`UserSettingObserver`'s own `.receive(on: DispatchQueue.main)`,
  `UserSetting.swift`). `ThemeManager.reload()` then posts
  `didChangeNotification` synchronously within that later turn, which is
  what finally triggers `preview.show`. This is current, source-traceable
  behavior across `ThemePickerView.swift`, `UserSetting.swift`,
  `UserSettingsThemeStorage.swift`, and `ThemeManager.swift` together: the
  preview is never more than one main-queue turn behind a selection, and
  `ThemePickerView` performs no additional debouncing of its own on top of
  that.
- **Reload no-ops when the theme id round-trips to the same theme**:
  `ThemeManager.reload()` guards with `guard theme != currentTheme else {
  return }` (`ThemeManager.swift`) before rebuilding the palette or
  posting the notification, so selecting the item that is already active
  produces no preview re-render
  and no second notification — current, source-traceable behavior in
  `ThemeManager.swift`, which this recipe's
  **resyncs-preview-on-theme-change** requirement depends on.
