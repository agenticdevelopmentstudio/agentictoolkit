<!-- leaf: implement-settings/storage · source: settings-storage.md -->

# Settings Storage

## Overview

`settings-storage` is the toolkit's typed key/value persistence layer for user preferences and secrets. A `StorableSetting<Value>` is a typed key: a stable `name`, a `defaultValue`, and an `isSecure` flag. A `SettingsStorageProvider` is the pluggable backend contract — `get`/`set`/`remove`/`contains` plus a `changes: AnyPublisher<String, Never>` that names which key changed, with `publisher(for:)` and `values(for:)` derived from it in a protocol extension. Six concrete backends implement the contract: `InMemorySettingsStorageProvider` and `InMemorySecureSettingsStorageProvider` (tests and previews), `UserDefaultsSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`, and `iCloudSettingsStorageProvider`. `SettingsStore` — and its process-wide subclass singleton `UserSettings` — routes each key to a secure or plain backend by `key.isSecure` and merges both backends' `changes` into one publisher. Call sites almost never touch a provider directly: they declare a `static var` `UserSetting<Value>` (an `ObservableObject` that mirrors the store's live value for that key, as `UserSettings+Editor.swift`, `+Git.swift`, and `+Theme.swift` do) and read/write it through the `StorableSetting.value` accessor, or wrap it in a `UserSettingObserver`/`ObservedSetting` for a plain callback outside SwiftUI. `ColorSetting` is a `UserSetting<RGBAColor>` type alias for stored color settings, reaching `RGBAColor` through `Core/Theme/ThemeReExports.swift`.

