<!-- leaf: implement-general-view-3/theme-picker-view--states · source: theme-picker-view.md -->

# ThemePickerView

## States

| State | Appearance change |
|-------|------------------|
| Default | Popup shows the choice matching the persisted active theme id (or whatever item `NSPopUpButton` selects by default if none matches, per `popup-menu-choice-view`); preview already shows that theme's full sample, rendered synchronously at construction. |
| Theme picked (popup) | The popup's own selection updates immediately; `UserSettings.activeThemeID` is written; the preview does not change yet — see **decouples-preview-refresh-from-selection-commit**. |
| Theme changed (notification) | On the next main-queue turn, `ThemeManager` posts `didChangeNotification` and the preview fully re-renders via `preview.show(palette.theme)`. |
| Scope changed (matching) | Same preview re-render, triggered by a `ThemeScope.didChangeNotification` for this view's resolved scope. |
| Pressed | Not applicable: `ThemePickerView` draws no button of its own; the popup's own bezel-less press appearance is `PopupMenuChoiceView`'s concern. |
| Disabled | Not supported: `ThemePickerView` exposes no `isEnabled` property and keeps its popup private, so neither it nor a host can disable the row (unlike `PopupMenuChoiceView`, which exposes its `popUpButton`). |
| Focused | Not styled directly by `ThemePickerView.swift`; whichever child view receives keyboard focus (the popup's internal `NSPopUpButton`) follows its own file's focus rendering. |
| Loading | Not applicable: construction and every refresh in `ThemePickerView.swift` are synchronous; there is no asynchronous operation and no loading indicator in source. |
