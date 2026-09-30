<!-- leaf: implement-settings/storage--logging · source: settings-storage.md -->

# Settings Storage

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to the literal string `nil` if absent) | Category: the conforming type's name (e.g. `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`)

| Event | Level | Message |
|-------|-------|---------|
| Keychain non-`String` encode failure | error | Failed to encode value for secure key, naming the key |
| SQLite encode failure | error | Failed to encode value for key, naming the key |
| SQLite `SELECT` prepare failure | error | prepare SELECT failed, with the SQLite error message |
| SQLite `UPSERT` prepare failure | error | prepare UPSERT failed, with the SQLite error message |
| SQLite blob bind failure | error | bind blob failed, with the SQLite error message |
| SQLite `UPSERT` step failure | error | UPSERT step failed, with the SQLite error message |

`InMemorySettingsStorageProvider`, `InMemorySecureSettingsStorageProvider`, `UserDefaultsSettingsStorageProvider`, and `iCloudSettingsStorageProvider` conform to no `Loggable` and emit no log lines in the given sources.
