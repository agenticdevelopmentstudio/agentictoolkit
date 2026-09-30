<!-- leaf: implement-general-2/theme-engine--part-4 · source: theme-engine.md -->

# Theme Engine — continued (part 4)

**Rules** (cite as `implement-general-2/theme-engine--part-4#<slug>`):

- `storage-custom-themes-key` MUST
- `storage-active-key` MUST
- `storage-legacy-compatible` MUST
- `storage-nil-write` MUST
- `storage-read-non-nil` MUST
- `storage-observers-lazy` MUST
- `storage-observers-rebuilt` MUST
- `storage-change-any-writer` MUST
- `storage-change-deferred` MUST
- `storage-change-no-initial` MUST
- `storage-weak-owner` MUST
- `store-default-init` MUST
- `manager-default-init` MUST
- `manager-default-reads-disk` MUST

### UserSettings-backed storage

- **storage-custom-themes-key**: `UserSettingsThemeStorage.customThemes` MUST read and write `UserSettings.customThemes` — key `theme.custom_themes`, a JSON-encoded `[ColorTheme]`, default `[]` — in whichever provider `UserSettings.shared` holds (see Settings Storage).
- **storage-active-key**: `UserSettingsThemeStorage.activeThemeID` MUST read and write `UserSettings.activeThemeID` — key `theme.active_theme_id`, a plain `String`, default `BuiltInThemes.defaultID`.
- **storage-legacy-compatible**: The keys and encodings MUST NOT change; a value written by an earlier build under either key MUST read back unchanged, and a write MUST land under the historical key as a plain string for the active id.
- **storage-nil-write**: Assigning `nil` to `activeThemeID` MUST store `BuiltInThemes.defaultID`, never `nil`.
- **storage-read-non-nil**: Reading `activeThemeID` MUST return the stored string or `BuiltInThemes.defaultID`; it never returns `nil` despite the optional type.
- **storage-observers-lazy**: `UserSettingsThemeStorage` MUST NOT observe either setting until `onExternalChange` is set to a non-nil closure, and MUST release both observers when it is set back to `nil`.
- **storage-observers-rebuilt**: Each assignment of a non-nil `onExternalChange` MUST replace both observers with fresh ones.
- **storage-change-any-writer**: Once hooked, `onExternalChange` MUST fire on every change to either setting — including a write made through this storage itself — not only on writes from outside the `ThemeStorage` seam.
- **storage-change-deferred**: `onExternalChange` MUST be delivered on the main dispatch queue after the new value has landed, not synchronously inside the write.
- **storage-change-no-initial**: Hooking `onExternalChange` MUST NOT invoke it for the values already stored.
- **storage-weak-owner**: The observers MUST hold the storage weakly, so a deallocated storage delivers no further callbacks.

### Convenience initialisers

- **store-default-init**: `ThemeStore()` MUST be equivalent to `ThemeStore(storage: UserSettingsThemeStorage())`.
- **manager-default-init**: On macOS, `ThemeManager()` MUST be equivalent to `ThemeManager(storage: UserSettingsThemeStorage(), appearanceDriver: AppKitAppearanceDriver(autoAppearance:))`, with an `autoAppearance` closure that returns `UserSettings.appearanceMode.currentValue.nsAppearance`, read each time the closure is called.
- **manager-default-reads-disk**: A theme id stored under `theme.active_theme_id` by an earlier build MUST be the `currentTheme` of a freshly created `ThemeManager()`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` | `Data` | — | Raw theme bytes for `parse(_:label:uiTheme:)`; JSONC, UTF-8/UTF-16, optional BOM. |
| `url` | `URL` | — | Theme file for `parse(contentsOf:…)` and `importVSCodeTheme`; the caller vouches for it (not containment-checked). |
| `label` | `String` | — | The manifest entry's `label`; becomes `ColorTheme.name`. |
| `uiTheme` | `String` | — | The manifest entry's `uiTheme` (`vs`, `vs-dark`, `hc-light`, `hc-black`); decides appearance. |
| `containedIn` | `URL?` | `nil` (the theme file's directory) | Root every `include` must stay inside; the themes contribution point passes the extension's folder. |
| `maximumIncludeDepth` | `Int` (private constant) | `8` | Include hops followed before `includeChainTooDeep`. |
| `theme.custom_themes` | `UserSettings` key, `[ColorTheme]` as JSON | `[]` | Where `UserSettingsThemeStorage` keeps custom and imported themes. |
| `theme.active_theme_id` | `UserSettings` key, `String` | `BuiltInThemes.defaultID` | The selected theme's id. |
| `UserSettings.appearanceMode` | `UserSetting` | host-defined | Read by `ThemeManager()`'s `autoAppearance` closure for `.auto` themes. |
| `onExternalChange` | `(() -> Void)?` | `nil` | Callback `ThemeManager` installs; setting it allocates the two setting observers. |
| `UserSettings.shared` provider | injected `SettingsStorageProvider` | host-configured | Backend both keys are persisted in. |

## Platform Notes

- **SwiftUI**: The source is Swift and platform-neutral except `ThemeManager+UserSettings.swift`. `SyntaxRoleOverrides.swift` and `VSCodeThemeImporter.swift` are Foundation-only; `UserSettingsThemeStorage.swift` depends on ATK's `UserSettings` (`UserSettings+Theme.swift` declares the two keys) and `UserSettingObserver`, which delivers on `DispatchQueue.main` after `dropFirst()`. A SwiftUI host holds a `ThemeManager` and observes `ThemeManager.didChangeNotification`; nothing here is SwiftUI-specific.
- **Compose**: Port `SyntaxRole` as a Kotlin `enum class` with the same lowercase names and `SyntaxStyle` as a `data class`. Parse with `kotlinx.serialization.json.Json { isLenient = true; allowTrailingComma = true; allowComments = true }` into a `JsonObject` and read by key, as the source does, rather than a strict `@Serializable` model. Resolve includes with `java.nio.file.Path.resolve(...).toRealPath()` plus a `startsWith(root)` check. Back `ThemeStorage` with Jetpack `DataStore<Preferences>` under the same two keys; `onExternalChange` becomes collecting the DataStore `Flow` with `drop(1)`, dispatched on `Dispatchers.Main`.
- **React/Web**: Port the importer as a pure TypeScript module over `JSON.parse` after a JSONC strip (`jsonc-parser`'s `parse` with `allowTrailingComma`); `Map` iteration order is insertion order, but keep the lexicographic tie-break so the result does not depend on it. File access and include containment only exist in Node/Electron (`fs.readFileSync`, `path.resolve` + `fs.realpathSync` + a prefix check); a browser port accepts bytes only, like `parse(_:label:uiTheme:)`. Persist with `localStorage` under the same keys; the cross-tab `storage` event is the `onExternalChange` equivalent, and it does not fire in the writing tab — unlike the source, which fires for its own writes too.
- **AppKit / UIKit**: This is the source's own platform. `ThemeManager()` (macOS target) installs `AppKitAppearanceDriver` with `autoAppearance` reading `UserSettings.appearanceMode.currentValue.nsAppearance`; a UIKit port swaps in a driver that sets `overrideUserInterfaceStyle` on the window scene. `ThemeContributionPoint.swift` is the production caller of `parse(contentsOf:…containedIn:)`, and `ThemeSettingsPanelViewController` is where users duplicate an imported theme to edit it.
- **WinUI 3**: Port the model as C# `record` types (`SyntaxStyle(Color, bool Bold, bool Italic)`) and `SyntaxRole` as an `enum` with a lowercase-name mapping. Parse with `System.Text.Json.JsonDocument.Parse(bytes, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })` and walk `JsonElement`s by key (`TryGetProperty`, `ValueKind`) to keep the source's "read by key, absent on wrong type" rule; detect UTF-16 with `StreamReader`'s BOM detection before parsing. Read files with `Windows.Storage.StorageFile.GetFileFromPathAsync` + `FileIO.ReadBufferAsync`, or `System.IO.File.ReadAllBytes` in an unpackaged app; do include containment with `Path.GetFullPath` plus a case-insensitive `StartsWith(root)` check, resolving reparse points with `FileSystemInfo.ResolveLinkTarget(true)`. Where the source is synchronous, expose `Task<ColorTheme> ParseAsync(...)` so the UI thread is not blocked. Back `ThemeStorage` with `Windows.Storage.ApplicationData.Current.LocalSettings.Values["theme.active_theme_id"]` (a string) and a JSON string (or a `LocalFolder` file, since a settings value is capped at 8 KB) for `theme.custom_themes`; implement change notification with `INotifyPropertyChanged` on a storage class and dispatch the callback through `DispatcherQueue.TryEnqueue` to match the source's deferred main-queue delivery. Expose the catalog as an `ObservableCollection<ColorTheme>` for a `ListView` theme picker.

