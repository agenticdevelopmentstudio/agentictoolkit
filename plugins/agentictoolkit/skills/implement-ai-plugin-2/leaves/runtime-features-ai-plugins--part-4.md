<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--part-4 · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins) — continued (part 4)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appName` | `String` | — (required) | Passed to `AIPluginsCoordinator.init` / `AIPluginManager.init`; used to derive the per-app plugins search path under Application Support. |
| `additionalSearchPaths` | `[URL]` | `[]` | Passed to `AIPluginsCoordinator.init`; extra directories `AIPluginManager` scans for `.aiplugin` bundles. |
| `resolvePlugin` | `@Sendable () async -> (any AIPlugin)?` | — (required) | Injected into `LocalChatSession.init`; resolves which plugin instance serves the next turn. |
| `makeContext` | `@Sendable ([AIChatMessage]) async -> AIChatContext` | — (required) | Injected into `LocalChatSession.init`; builds the per-turn `AIChatContext` from the current history snapshot. |
| `eventStreamFactory` | `LocalChatSession.EventStreamFactory` | `{ PluginTransport.run(spec: $0, plugin: $1) }` | Injected into `LocalChatSession.init`; the seam tests use to fake a plugin's response stream. |
| `toolSource` | `(any ChatToolSource)?` | `nil` | Injected into `LocalChatSession.init`; when `nil`, the tool loop never runs even if the plugin emits `.toolUse` events. |
| `registry` | `MCPServerRegistry` | — (required) | Passed to `MCPChatToolSource.init`; the source of active MCP servers and their tools. |
| `activeServerIds` | `Set<UUID>` | — (required) | Passed to `MCPChatToolSource.init`; a fixed snapshot of which servers' tools are exposed to the model. |
| `"aiplugin.configurations"` | `[AIProviderConfiguration]` (settings key) | `[]` | `UserSettings.aiProviderConfigurations` — the ordered list of configured providers. |
| `"aiplugin.selectedConfigurationId"` | `String` (settings key) | `""` | `UserSettings.selectedAIProviderConfigurationId` — empty means the daemon's zero-config Default path. |
| `"aiplugin.migratedToConfigurations"` | `Bool` (settings key) | `false` | `UserSettings.aiProvidersMigrated` — one-time migration guard. |
| `"aiplugin.defaultConfigSeeded"` | `Bool` (settings key) | `false` | `UserSettings.aiDefaultConfigSeeded` — one-time default-seeding guard. |
| `"aiplugin.config.<uuid>.field.<key>"` | `String` (settings key, secret-routed per field) | `""` | Per-configuration field value, via `AIProviderConfigKeys.fieldKey` / `AIProviderConfigStore.fieldSetting`. |
| `"aiplugin.config.<uuid>.model"` | `String` (settings key) | template's `resolvedDefaultModel` | Per-configuration selected model, via `AIProviderConfigKeys.modelKey`. |
| `"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, `"aiplugin.selectedPlugin"` | `String` (legacy settings keys) | `""` | Read (never written) by `AIProviderMigration.runIfNeeded` via `PluginConfigStore`; superseded by the per-configuration keys above. |

## Localization

None of the given sources route their user-facing strings through
`NSLocalizedString` or `String(localized:)`; they are hardcoded English
literals, listed here as facts rather than as a marker per source fidelity:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `No AI provider is configured.` | `LocalChatSession.runTurn`'s `ChatError.message` when `resolvePlugin()` returns `nil` |
| (none — hardcoded literal) | `Unknown tool: <name>` | `MCPChatToolSource.callTool`'s error text when no pair matches the namespaced tool name |
| (none — hardcoded literal) | `Tool error: <error.localizedDescription>` | `MCPChatToolSource.callTool`'s error text when the underlying MCP call throws |

## Privacy

- **Data collected**: Provider credentials and connection settings the user
  enters for a configuration — secret fields (e.g. an `apiKey`, kind
  `.secret`) and plain fields (e.g. a `baseURL`, kind `.text`), plus the
  chosen `model` — are the sensitive data this component stores and
  resolves. `ChatConfigProvider.pluginConfigValues` is explicitly documented
  as "secrets included."
- **Storage**: A field's `isSecret` (`AIPluginDescriptor.Field.Kind.secret`)
  routes its `UserSetting<String>` to construct with `isSecure: true`
  (`AIProviderConfigStore.fieldSetting`, `PluginConfigStore.fieldSetting`),
  which persists it to the Keychain rather than plain user defaults; a
  `.text` field is persisted to the plain (non-Keychain) settings store.
  Setting a secret field's value to `""` (via `clearStoredValues`) removes
  it from the Keychain.
- **Transmission**: This component never performs network I/O itself. It
  assembles the resolved value bag into an `AIPluginConfig` inside an
  `AIChatContext` and hands that to the selected plugin's `buildRequest(_:)`;
  the plugin (outside this component's given sources) decides which of
  those values, including any secret, become part of the outgoing request
  that `PluginTransport` then performs.
- **Retention**: Stored field/model values persist indefinitely (Keychain
  for secrets, plain settings for the rest) until `clearStoredValues` is
  called for that configuration — there is no expiry, rotation, or
  time-based invalidation logic anywhere in this component; a stored value
  is valid until explicitly overwritten or cleared.

## Platform Notes

- **SwiftUI** (source): This is a plain Foundation/AppKit runtime layer, not
  a SwiftUI component. `AIPluginsCoordinator.swift` imports `AppKit` to
  compose menu/status-item contributions as an `AppFeature`; the actual chat
  UI (outside this component) binds to `AIChatViewModel`'s
  `@Published`/`ObservableObject` surface fed by `ChatBackendSession` or
  `LocalChatSession`'s `events()` `AsyncStream`. State that would be
  `@Observable`/`ObservableObject` elsewhere is here plain `NSLock`- or
  `Synchronization.Mutex`-guarded mutable state on `@unchecked Sendable`
  classes, and persistence goes through `UserSetting<T>` (Combine-backed,
  Keychain-routed when `isSecure`).
- **Compose** (Android/Kotlin): `kotlinx.coroutines.flow.Flow`/`SharedFlow`
  replaces the `AsyncStream`/`AsyncThrowingStream` event pipelines;
  `kotlinx.coroutines.sync.Mutex` replaces `NSLock`/`Synchronization.Mutex`
  for the busy-guard and subscriber registry; the Keychain-routed secret
  fields become `EncryptedSharedPreferences` or an Android
  Keystore-backed store, and the plain fields become ordinary
  `SharedPreferences`/`DataStore`; the `.aiplugin` bundle + `dlopen` +
  `NSPrincipalClass` discovery model has no direct Android analogue — a
  static `ServiceLoader`-style registry or a signed dynamic-feature module
  would replace it, since arbitrary native code loading is far more
  restricted.
- **React/Web**: Async generators or an RxJS `Observable` replace
  `AsyncStream`; because JS is single-threaded, the `NSLock`/`Mutex` guards
  collapse to a plain boolean busy flag (no actual lock needed); the
  Keychain-routed secret store becomes a server-side vault or, client-side,
  a WebCrypto-wrapped value in `IndexedDB` (never plain `localStorage` for a
  secret); dynamic `import()` of a plugin module, driven by a fetched
  `descriptor.json`-equivalent manifest, replaces `Bundle` + `dlopen`
  discovery.
- **AppKit / UIKit**: The given sources already target AppKit; a UIKit
  (iOS) port would replace `AIPluginsCoordinator`'s `AppFeature`/menu-bar
  lifecycle hooks with `UIApplicationDelegate` equivalents, and would need
  to drop the `dlopen`-based `.aiplugin` bundle loading entirely — dynamic
  loading of unsigned code is not permitted under App Store code-signing —
  in favor of statically linked or App Extension–hosted plugins. The
  Foundation-level pieces (`NSLock`, `UserDefaults`, Keychain Services)
  need no change.
- **WinUI 3**: `System.Net.Http.HttpClient` performs the HTTP half of what
  `PluginTransport` drives (the given sources hand it an `AIRequestSpec`,
  never touch `HttpClient` directly), and `System.Diagnostics.Process` /
  `ProcessStartInfo` covers the subprocess (`.command`) transport case;
  `System.Text.Json` replaces `Foundation.JSONEncoder`/`JSONDecoder` for
  `descriptor.json` decoding and for `MCPChatToolSource`'s tool-schema and
  tool-argument JSON; `Windows.Storage.ApplicationData.Current.LocalSettings`
  replaces the plain (`isSecure: false`) `UserSetting` keys, and
  `Windows.Security.Credentials.PasswordVault` replaces the Keychain for
  secret fields; `System.Threading.SemaphoreSlim` or a plain `lock` object
  replaces `NSLock`/`Synchronization.Mutex` for `LocalChatSession`'s busy
  guard and `AIPluginChatBackend`'s subscriber registry;
  `System.Threading.Channels.Channel<T>` or `IAsyncEnumerable<T>` replaces
  `AsyncStream`/`AsyncThrowingStream` for `events()` and the plugin-transport
  event streams; `ObservableCollection<T>` + `INotifyPropertyChanged`
  replaces `@Published`/`ObservableObject` for the settings-backed
  configuration list and view models; and the Managed Extensibility
  Framework (`System.ComponentModel.Composition`) or a plain
  `Assembly.LoadFrom` call is the .NET analogue of `Bundle` + `dlopen` +
  `NSPrincipalClass` discovery — read a manifest first, load the assembly
  only on first use.

