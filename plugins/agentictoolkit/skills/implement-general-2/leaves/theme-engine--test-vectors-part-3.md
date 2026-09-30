<!-- leaf: implement-general-2/theme-engine--test-vectors-part-3 · source: theme-engine.md -->

# Theme Engine — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-engine-048 | include-containment, import-file-default-root (test) | `themes/variant.json` includes `../outside/secret.json`, no `containedIn` | Throws `ExtensionResourcePathError` |
| theme-engine-049 | include-resolve (test) | Same files, `containedIn:` the parent directory | Parses; foreground `#D8DEE9FF` |
| theme-engine-050 | include-detect, import-file-entry (test) | Minimal theme on disk with no `include` | Same palette as `parse(_:label:uiTheme:)` of the same bytes |
| theme-engine-051 | include-merge-other, include-consumed | Base `{"x": 1, ...}`, variant `{"include": "./base.json", "x": 2}` | Merged document has `x == 2` and no `include` key |
| theme-engine-052 | import-file-errors | `parse(contentsOf:)` on a path that does not exist | Throws the file-read error; nothing parsed |
| theme-engine-053 | store-import, store-import-locked (test) | `ThemeStore(storage: InMemoryThemeStorage())`, minimal theme file, `importVSCodeTheme(label: "Acme Dark", uiTheme: "vs-dark")` | Returned `name == "Acme Dark"`, `isImported`, `isLocked`, `!isEditable`; `customThemes.map(\.id) == [imported.id]`; `allThemes` contains it |
| theme-engine-054 | store-import-failure | `importVSCodeTheme` on a file whose `colors` is missing | Throws `missingColors`; `customThemes` unchanged |
| theme-engine-055 | store-import-no-rename | Import the same file twice with the same label | Two custom themes, both named the label, with different ids |
| theme-engine-056 | storage-active-key, storage-legacy-compatible (test) | Defaults hold `theme.active_theme_id` = Dracula's id written the pre-seam way | `UserSettingsThemeStorage().activeThemeID == BuiltInThemes.dracula.id` |
| theme-engine-057 | storage-legacy-compatible (test) | `storage.activeThemeID = BuiltInThemes.nord.id` | `defaults.string(forKey: "theme.active_theme_id") == nord.id` |
| theme-engine-058 | storage-nil-write, storage-read-non-nil | `storage.activeThemeID = nil`, then read | Reads `BuiltInThemes.defaultID` |
| theme-engine-059 | storage-custom-themes-key | `storage.customThemes = [t]`, then read `UserSettings.customThemes.value` | `[t]` |
| theme-engine-060 | storage-change-any-writer, storage-change-deferred (test) | `ThemeManager` over this storage; write `UserSettings.activeThemeID.value = dracula.id` directly | After the main queue drains, `didChangeNotification` fired and `currentTheme.id == dracula.id` |
| theme-engine-061 | storage-change-any-writer (test) | Rewrite `UserSettings.customThemes` with the active custom theme renamed | Notification fired; `currentTheme.name` is the new name |
| theme-engine-062 | storage-change-any-writer (test) | `manager.selectTheme(id: dracula.id)` | Exactly one `didChangeNotification` (the storage callback fires, `ThemeManager.reload()` de-duplicates) |
| theme-engine-063 | storage-observers-lazy, storage-change-no-initial | Set `onExternalChange` to a counter, drain the main queue, then set it to `nil` and write both settings | Counter stays 0 |
| theme-engine-064 | store-default-init, manager-default-init, manager-default-reads-disk (test) | Defaults hold `theme.active_theme_id` = Gruvbox Dark's id; create `ThemeManager()` | `currentTheme.id == BuiltInThemes.gruvboxDark.id` |
