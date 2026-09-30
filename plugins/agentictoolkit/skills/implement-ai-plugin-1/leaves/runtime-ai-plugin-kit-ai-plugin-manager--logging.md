<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--logging · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager.md -->

# AI Plugin Manager

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `AIPluginManager`

| Event | Level | Message |
|-------|-------|---------|
| A candidate bundle has no readable `descriptor.json` (`Bundle(url:)` or decode failure) | warning | `Skipping plugin without a readable descriptor: <bundle filename>` |
| A descriptor's `schemaVersion` is outside `2...currentSchemaVersion` | warning | `Skipping incompatible plugin '<displayName>': schema <n> not in 2...<currentSchemaVersion>` |
| A new, non-duplicate identifier is recorded | info | `Discovered plugin: <displayName> (<identifier>)` |
| `loadPlugin(identifier:)` throws inside `loadAllPlugins()` | error | `Failed to load plugin '<displayName>' (<identifier>): <message>` |
| `loadPlugin(identifier:)` succeeds | info | `Loaded plugin: <displayName>` |
| `unloadPlugin(identifier:)` is called, loaded or not | info | `Unloaded plugin: <identifier>` |
