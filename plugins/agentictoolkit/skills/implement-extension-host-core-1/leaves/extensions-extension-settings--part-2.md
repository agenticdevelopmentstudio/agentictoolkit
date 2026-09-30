<!-- leaf: implement-extension-host-core-1/extensions-extension-settings--part-2 · source: extension-host-core-extensions-extension-settings.md -->

# ExtensionSettings — continued (part 2)

## Platform Notes

- **SwiftUI**: not the source, and not a dependency of it. A SwiftUI consumer reads and writes `UserSettings.disabledExtensionIdentifiers.value` exactly like any other caller, or wraps it in the `@ObservedSetting` property wrapper (`Core/SettingStorage/UserSetting.swift`) to bind a view to `currentValue`'s changes; nothing about the declaration is AppKit- or SwiftUI-specific.
- **AppKit / UIKit**: this is the source. `ExtensionSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift`) is part of the macOS-only `AgenticToolkitCore` framework target (`project.yml` declares `platform: macOS` for `AgenticToolkitCore`; no iOS target exists in this repository today, the same scoping the `ContributedSettings` sibling recipe records). The file imports only `Foundation` — no AppKit or UIKit type appears in it, so it would compile unchanged behind a UIKit consumer if the target were extended to iOS.
- **Compose**: model the declaration as a Kotlin `object` property backed by Jetpack `DataStore<Preferences>`, using a `stringSetPreferencesKey("extensions.disabledIdentifiers")` with an empty-set default; mirror `UserSetting`'s get/set/remove/exists surface with `DataStore`'s `Flow`-based read and `edit { }` write, and use `Flow.collect` in place of the Combine `changes` publisher this file's `UserSetting` subscribes to.
- **React/Web**: model it as a small typed wrapper over `localStorage`, storing a JSON-serialized array under the key `"extensions.disabledIdentifiers"` and converting to and from a JavaScript `Set` of strings at the read/write boundary, since `localStorage` has no native set type; use a small pub-sub, or the browser's `storage` event for cross-tab notification, in place of the synchronous Combine update this file's `currentValue` gets.
- **WinUI 3**: the reason this recipe exists. Model the property as a static member on a settings class backed by `Windows.Storage.ApplicationData.Current.LocalSettings.Values`, keyed `"extensions.disabledIdentifiers"`. `ApplicationDataContainer.Values` stores primitives and `String` natively but not a `HashSet<string>` directly, so serialize with `System.Text.Json.JsonSerializer.Serialize` and `Deserialize` into a stored `string` value — the same fallback-to-encoded-payload shape this file's dependency, `UserDefaultsSettingsStorageProvider`, uses for `Data`. Expose the mirrored, observable value through a property that raises `INotifyPropertyChanged`, in place of `UserSetting`'s `@Published currentValue`, and raise that notification synchronously from the setter, on the UI thread, to match this property's synchronous, main-actor-confined update rather than posting to a dispatcher queue. C# has no direct equivalent to `@MainActor`; document the type as UI-thread-affine by convention, or assert `DispatcherQueue.HasThreadAccess` at each entry point, since the compiler enforces nothing here the way Swift's actor isolation does.

## Design Decisions

**Decision**: The setting tracks *disabled* identifiers rather than *enabled* ones.
**Rationale**: the source's own doc comment states this directly — disabled-rather-than-enabled means a freshly installed extension is on by default and needs no migration when a new extension is added (`ExtensionSettings.swift`). The inverse representation would require seeding every new extension's identifier into an "enabled" set at install time, and anyone who never relaunched after that seeding step would see the new extension as disabled.
**Approved**: pending

**Decision**: The storage key `"extensions.disabledIdentifiers"` is a literal string, declared once, never derived or namespaced further at this layer.
**Rationale**: the source's own doc comment calls the key "load-bearing" and states that changing it orphans every user's existing choices and needs a migration — the same contract `theme.custom_themes` carries (`ExtensionSettings.swift`; `UserSettings+Theme.swift`).
**Approved**: pending

**Decision**: `UserSetting<Set<String>>` is constructed with no `isSecure` argument, so the identifiers persist through `UserDefaults`, not the Keychain.
**Rationale**: an extension identifier is a public, non-sensitive string with nothing to gain from Keychain's confidentiality or access-control guarantees; the call site simply omits the argument and takes `UserSetting.init`'s `false` default (`ExtensionSettings.swift`; `UserSetting.swift`).
**Approved**: pending

**Decision**: `UserSetting.currentValue` updates synchronously, in the same call that writes `.value`, rather than on a redispatched queue turn.
**Rationale**: `UserSetting.init`'s subscription to the store's `changes` publisher applies no scheduling operator, unlike `UserSettingObserver`'s explicit `.receive(on: DispatchQueue.main)` hop (`UserSetting.swift`). Recorded here so a port does not assume the observer's dispatched-callback delay also applies to the mirrored `currentValue` itself, which this property exposes directly.
**Approved**: pending
