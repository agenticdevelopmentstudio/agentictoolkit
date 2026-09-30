<!-- leaf: implement-general-view-3/theme-picker-view--test-vectors · source: theme-picker-view.md -->

# ThemePickerView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-picker-view-001 | composes-theme-choice-popup | Construct `ThemePickerView(store: someStore)` | A `PopupMenuChoiceView<String>` is among the view's descendant views, built from a `ThemeChoiceViewModel(store: someStore)` |
| theme-picker-view-002 | composes-theme-preview | Construct `ThemePickerView` | A `ThemePreviewView` is among the view's descendant views |
| theme-picker-view-003 | stacks-popup-above-preview | Construct `ThemePickerView` | The popup and the preview are arranged, in that order, top-to-bottom, inside one leading-aligned vertical `NSStackView` with 10pt spacing |
| theme-picker-view-004 | pins-stack-to-view-edges | Construct `ThemePickerView` | The stack view's top/leading/trailing/bottom constraints equal `ThemePickerView`'s own edges with a 0pt constant |
| theme-picker-view-005 | derives-choices-from-injected-store | `store.allThemes == [ColorTheme(id: "a", name: "Alpha"), ColorTheme(id: "b", name: "Beta")]` | The popup's `viewModel.choices == [Choice(label: "Alpha", value: "a"), Choice(label: "Beta", value: "b")]` and `viewModel.title == "Theme"` |
| theme-picker-view-006 | defaults-to-the-persisted-theme-store | Construct `ThemePickerView()` with no `store` argument | The popup's choices equal `BuiltInThemes.all` followed by `UserSettings.customThemes.value` (in that order), each mapped to `Choice(label: $0.name, value: $0.id)` — the same composition `ThemeStore.allThemes` computes (`ThemeStore.swift`) |
| theme-picker-view-007 | renders-initial-preview-synchronously | Construct `ThemePickerView` | Immediately after `init` returns, the preview's subviews are already non-empty and reflect the current palette's theme — no further call is needed |
| theme-picker-view-008 | resyncs-preview-on-theme-change | Post `ThemeManager.didChangeNotification` after construction | The preview's `show(_:)` is invoked again with the newly current palette's theme |
| theme-picker-view-009 | resyncs-preview-on-matching-scope-change | Post `ThemeScope.didChangeNotification` with `object` set to the exact `ThemeScope` instance the view's own `resolvedThemeScope` returns | The preview's `show(_:)` is invoked again |
| theme-picker-view-010 | ignores-non-matching-scope-change | Post `ThemeScope.didChangeNotification` with `object` set to a `ThemeScope` instance other than the one `resolvedThemeScope` returns — a distinct `ObjectIdentifier`, since `ThemeScope` has no `Equatable` conformance and `ThemePaletteObserver` compares scopes by `ObjectIdentifier` identity (`ThemeBinding.swift`) | The preview's `show(_:)` is NOT invoked as a result of that notification |
| theme-picker-view-011 | commits-selection-through-the-active-theme-setting | Select a different item in the popup | `UserSettings.activeThemeID.value` equals the selected item's represented theme id |
| theme-picker-view-012 | decouples-preview-refresh-from-selection-commit | Select a different item in the popup | No call from the popup's selection handler invokes `preview.show` directly; the preview is refreshed only by a `ThemePaletteObserver` subscription firing |
| theme-picker-view-013 | keeps-constituent-views-private | Attempt to access `.popup`, `.preview`, or `.observer` from outside `ThemePickerView` | Compiler rejects each access; no public API exposes any of the three |
| theme-picker-view-014 | retains-the-palette-observer-for-its-lifetime | Construct `ThemePickerView`, retain it, then post `ThemeManager.didChangeNotification` | The preview still re-renders (the observer has not been deallocated while the view is retained) |
| theme-picker-view-015 | requires-designated-initializer | Attempt `ThemePickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| theme-picker-view-016 | omits-a-usable-frame-only-initializer | Attempt to write `ThemePickerView(frame: .zero)` | Compilation fails; no such initializer is available |
| theme-picker-view-017 | confines-to-main-actor | Attempt to construct or mutate a `ThemePickerView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
