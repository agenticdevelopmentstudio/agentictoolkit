<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--part-3 · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager.md -->

# AI Plugin Manager — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appName` (`init(appName:additionalSearchPaths:)`) | `String` | none — required | Names the `~/Library/Application Support/<appName>/Plugins` search location; not validated for emptiness (see the open question on empty-app-name-unvalidated) |
| `additionalSearchPaths` (`init(appName:additionalSearchPaths:)`) | `[URL]` | `[]` | Extra directories appended after the three default locations, in the order given |
| `searchPaths` (`init(searchPaths:appName:)`) | `[URL]` | none — required | Replaces all default-location derivation entirely; used by tests |
| `appName` (`init(searchPaths:appName:)`) | `String` | `"AgenticPlugins"` | Retained alongside explicit `searchPaths`, but not consulted to derive any path in this initializer |
| `Bundle.main.builtInPlugInsURL` (environment) | `URL?` | app-bundle-determined | `Contents/PlugIns` inside the running app bundle; included as a search path only when non-nil |
| `NSHomeDirectory()` (environment) | `String` (path) | current user's home | Base for the `~/.agenticplugins` search path |
| Application Support directory (environment, `FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)`) | `URL?` | `~/Library/Application Support` | Base for `<appName>/Plugins`; the whole search path is omitted when unavailable |

## Localization

No message in this file is externalized through a localization key (no `NSLocalizedString`/`String(localized:)`). Every user-facing string is a hardcoded English `String` literal interpolated into `AIPluginError.errorDescription`:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Plugin not found: <id>` | `AIPluginError.notFound.errorDescription` |
| (none — hardcoded) | `Failed to load plugin bundle: <id>` | `AIPluginError.loadFailed.errorDescription` |
| (none — hardcoded) | `Plugin '<id>' has no NSPrincipalClass` | `AIPluginError.noPrincipalClass.errorDescription` |
| (none — hardcoded) | `Plugin '<id>' principal class does not conform to AIPlugin` | `AIPluginError.principalClassNotPlugin.errorDescription` |

## Privacy

- **Data collected**: `AIPluginManager` reads plugin metadata only — `descriptor.json`'s `identifier`, `displayName`, `version`, `models`, `defaultModel`, `fields` (key/label/kind/placeholder shape, not values), and `templates`. It never reads, stores, or transmits a credential or configuration value; `AIPluginDescriptor.Field.kind == .secret` only labels which *field* a settings UI should mask and persist to the Keychain elsewhere in `AIPluginKit` (`SecretStoring`, `AIProviderConfigSync`) — this file never touches an actual secret value.
- **Storage**: Everything this type reads is kept only in the in-memory `records`, `loadedPlugins`, and `loadedBundles` collections (per `in-memory-state-only`); nothing is written to disk by this type.
- **Transmission**: This type performs no network communication.
- **Retention**: Discovered and loaded state lives only as long as the `AIPluginManager` instance; it is not persisted and does not survive process restart.

## Platform Notes

- **SwiftUI**: The source itself; `AIPluginManager` is a plain `@MainActor` Foundation/`os` type with no view-layer dependency, so a SwiftUI host observes it the same way an AppKit host does — typically by wrapping it in an `@Observable`/`ObservableObject` adapter that calls `discoverPlugins()` once and republishes `descriptors`/`availableTemplates` after mutating calls, since `AIPluginManager` itself is not observable.
- **Compose**: Kotlin has no `dlopen`/`NSPrincipalClass` equivalent for loading arbitrary on-disk bundles into a running process; the nearest analog is Android's `PackageManager`/`DexClassLoader` (loading code from an installed package or a `.dex`/`.jar` at a known path) — a much more restricted and permission-gated model than macOS's own-account file-system scan. `descriptor.json` decoding maps to `kotlinx.serialization` or `Moshi`; the discovery scan maps to `java.io.File.listFiles()`; the `@MainActor` confinement maps to a single-threaded `CoroutineDispatcher` (e.g. `Dispatchers.Main`) that every call is confined to.
- **React/Web**: There is no on-disk bundle-loading equivalent in a browser; the closest analog for "discover a descriptor cheaply, load code lazily" is dynamic `import()` (or a plugin registry fetched as JSON) gated behind a manifest file resembling `descriptor.json`, with the actual module fetched and evaluated only when first requested. `AIPluginError` maps to a small discriminated-union error type; the single-threaded JS event loop gives the same "no real concurrency" guarantee `@MainActor` gives here, without needing an explicit isolation keyword.
- **AppKit / UIKit**: Same note as SwiftUI — `AIPluginManager` has no AppKit/UIKit dependency at all (only `Foundation`, `os`/`OSLog`, and `AgenticToolkitCore` for `Loggable`). `.aiplugin` bundle loading via `Bundle`/`NSPrincipalClass` is macOS-only (UIKit/iOS sandboxes forbid loading arbitrary on-disk executable bundles), which is why this recipe's `platforms` list `macos` and not `ios`.
- **WinUI 3**: There is no direct `NSPrincipalClass`/`dlopen` counterpart on .NET; the nearest equivalent is `System.Reflection.Assembly.LoadFrom`/`AssemblyLoadContext` to load a plugin `.dll` on demand and `Activator.CreateInstance` (against an interface analogous to `AIPlugin`) to instantiate its principal type, with `System.IO.Directory.Exists`/`Directory.EnumerateFiles` for the discovery scan and `System.Text.Json` for decoding `descriptor.json`. Unlike `Bundle`, `AssemblyLoadContext` *can* be unloaded (a collectible `AssemblyLoadContext`), so a WinUI 3 port has a real choice `AIPluginManager` does not: whether `unloadPlugin` should actually unload the assembly rather than only dropping the cached instance (`unload-retains-bundle` is a macOS constraint, not a requirement to carry over literally). Exposing `descriptors`/`availableTemplates` to bound UI should go through an `ObservableCollection<T>` (or a view model implementing `INotifyPropertyChanged`) refreshed after `discoverPlugins()`/`loadPlugin`/`unloadPlugin`, since WinUI 3 has no built-in reactivity for a plain `List<T>`. The manager's `@MainActor` confinement maps to confining all calls to the UI thread (`DispatcherQueue.TryEnqueue` for any call originating off it).

## Design Decisions

**Decision**: `loadPlugin(identifier:)` caches one instance per identifier for the manager's lifetime instead of creating a fresh instance per call, even though `AIPlugin`'s own doc comment says "Instances are cheap and may be created per request."
**Rationale**: Caching avoids repeating `bundle.load()`/principal-class resolution on every request and keeps the `loadedBundles` bookkeeping simple (one `Bundle` reference per identifier); since macOS never truly unloads a loaded bundle's binary anyway (per `unload-retains-bundle`), there is no memory cost to keeping one instance alive alongside it.
**Approved**: pending

**Decision**: A duplicate `identifier` discovered from a later search path is dropped silently, with the earlier one always winning.
**Rationale**: The source's own comment on `init(appName:additionalSearchPaths:)` states the search-path order is deliberate — "the bundle's own copy wins, then the hand-filled dotfolder, then what an installer wrote" — so first-discovered-wins is how that stated precedence is implemented, not an oversight.
**Approved**: pending

**Decision**: `unloadPlugin(identifier:)` removes the cached `AIPlugin` instance but leaves the `Bundle` in `loadedBundles` forever.
**Rationale**: The source's own comment states "the bundle remains loaded in memory (macOS does not support unloading bundles)" — since the OS will not release the mapped binary regardless, removing the `Bundle` reference would only lose the manager's own bookkeeping for no memory benefit.
**Approved**: pending
