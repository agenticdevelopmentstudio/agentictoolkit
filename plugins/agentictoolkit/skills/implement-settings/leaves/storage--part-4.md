<!-- leaf: implement-settings/storage--part-4 · source: settings-storage.md -->

# Settings Storage — continued (part 4)

## Platform Notes

- **SwiftUI**: `UserSetting` is already an `ObservableObject`, so a SwiftUI view binds directly to `currentValue` with `@ObservedObject`/`@StateObject` on an instance the view (or its model) holds. The retired `StoredSetting` property wrapper in `StoredSettingPropertyWrapper.swift` sketched a `@propertyWrapper`/`DynamicProperty` alternative, but the whole file is compiled out with `#if false` and is not the live surface.
- **Compose**: Translate `SettingsStorageProvider` to a small Kotlin interface backed by Jetpack `DataStore<Preferences>` for plain keys and `EncryptedSharedPreferences`/Android Keystore for secure keys; `changes: AnyPublisher<String, Never>` becomes a `SharedFlow<String>`; `UserSetting` becomes a `MutableStateFlow`-backed delegate collected with `collectAsState()`, mirroring the eager, read-on-construction behavior of `UserSetting.init`.
- **React/Web**: Translate `SettingsStorageProvider` to a small interface backed by `localStorage`/`IndexedDB` for plain keys and a platform credential store (or a server-side secret proxy) for secure keys; `changes` becomes an `EventTarget`, or an observable keyed by name; `UserSetting` becomes a hook built on `useSyncExternalStore` over the same store.
- **AppKit / UIKit**: This is the source's own consumer story. `AppearanceManager`, `LaunchAtLoginManager`, and the `ComposableSettingsWindow` view models (`ChoiceViewModel`, `ColorViewModel`, `FontViewModel`, `RangeViewModel`) all bind to `UserSetting`/`UserSettingObserver` rather than to any storage provider directly, and `UserSettingObserver` deliberately hops to `DispatchQueue.main` — not `RunLoop.main` — so it still fires while AppKit is running a mouse-tracking loop in `.eventTracking` mode.
- **WinUI 3**: `StorableSetting`/`SettingsStorageProvider` map to a small C# interface with `Get<T>`/`Set<T>`/`Remove<T>`/`Contains<T>` plus a `changes` event, backed by `Windows.Storage.ApplicationData.Current.LocalSettings` (an `ApplicationDataContainer`, natives stored directly and complex types JSON-encoded via `System.Text.Json`, mirroring the native/JSON split here) for plain keys and the Windows Credential Locker (`Windows.Security.Credentials.PasswordVault`) in place of the Keychain for secure keys. `SqliteStorageProvider`'s hand-rolled `sqlite3` calls map to `Microsoft.Data.Sqlite`. `changes` becomes a plain `event Action<string>` or `IObservable<string>`. `UserSetting<T>` becomes an `ObservableObject`/`INotifyPropertyChanged` wrapper exposing a `T Value` property, and `UserSettingObserver`'s main-queue hop becomes `DispatcherQueue.TryEnqueue` from the setting's change handler, so an update still lands on the UI thread while WinUI is inside a modal input loop — the same reason the source hops to a dispatch queue rather than a run loop.

## Design Decisions

**Decision**: Replace `UserSettings.shared` — if a host app needs a different provider configuration at all — only before constructing any `UserSetting`.
**Rationale**: `UserSetting.init` captures `UserSettings.shared` once, to read the initial value and subscribe to its `changes`; replacing `shared` afterward leaves that instance's subscription pinned to the old store while its `value` accessor and the subscription's own re-read both target whichever instance is current — an inconsistency the source leaves to the caller's setup order (see `usersettings-shared-reassignment` in Edge Cases).
**Approved**: pending

**Decision**: Construct at most one `KeychainSecureSettingsStorageProvider` per process with a non-default `service`/`accessGroup`, or construct every instance with the same override.
**Rationale**: `init` assigns its `service` and `accessGroup` arguments to the process-wide statics `KeychainHelper.service`/`KeychainHelper.accessGroup`, including assigning `nil` unconditionally, so a later default-argument instance silently clears an override an earlier instance made intentionally; this is documented inline in `init`'s own comment, and a second, differently-configured instance changes keychain routing for every existing instance too, not only the new one.
**Approved**: pending

**Decision**: `KeychainSecureSettingsStorageProvider` memoizes every read — a hit or a confirmed miss — for the life of the instance rather than reading through on every `get`.
**Rationale**: the type's own documentation traces this to a measured cost — a keychain miss walks the access-group query, the legacy no-group query, and every retired service before returning, and bulk-resolving many AI-provider settings on the main thread pinned the app above 100% CPU inside the keychain query call. The provider owns every write to the keys it serves, so the memo can be exact rather than time-based.
**Approved**: pending

**Decision**: `UserSettingObserver` defers `onChange` to the next `DispatchQueue.main` turn rather than calling it synchronously or scheduling through `RunLoop.main`.
**Rationale**: `@Published` publishes before the new value is assigned, so a synchronous observer would see the property's old value; and `RunLoop.main` schedules in the default run-loop mode only, which AppKit does not service while a mouse-down or a slider drag runs the run loop in its event-tracking mode. The main dispatch queue is drained in every run-loop mode, so this is the scheduling choice that keeps a live-dragging preview working, documented in source as the same fix an earlier observer needed for an identical failure.
**Approved**: pending

**Decision**: Treat `StoredSetting` and its `Observer`, in `StoredSettingPropertyWrapper.swift`, as excluded from this recipe's contract.
**Rationale**: the entire file is wrapped in a disabled compile-time condition and does not build into the product; the live property-observation surface for a `UserSetting` is `UserSettingObserver`/`ObservedSetting` in `UserSetting.swift`.
**Approved**: pending
