<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager.md -->

# AI Plugin Manager — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--part-2#<slug>`):

- `existing-search-paths-only` MUST
- `aiplugin-extension-filter` MUST
- `no-binary-load-at-discovery` MUST
- `unreadable-candidate-skip` MUST
- `schema-version-filter` MUST
- `duplicate-identifier-first-wins` MUST
- `discovery-idempotent` MUST
- `descriptor-log-on-success` MUST
- `descriptors-list` MUST
- `available-templates-list` MUST
- `template-lookup` MUST
- `fields-resolution-known-plugin` MUST
- `fields-resolution-unknown-plugin` MUST
- `load-cache-hit` MUST
- `loaded-plugin-identity-stable` MUST
- `load-unknown-identifier` MUST
- `load-bundle-construction-failure` MUST
- `load-dlopen-failure` MUST
- `load-missing-principal-class` MUST
- `load-non-conforming-principal-class` MUST
- `load-success-caching` MUST
- `load-all-resilient` MUST
- `unload-removes-instance` MUST
- `unload-always-logs` MUST
- `unload-retains-bundle` MUST
- `descriptor-query-no-load` MUST
- `plugin-query-no-load` MUST
- `internal-record-hidden` MUST
- `main-actor-confinement` MUST
- `load-result-non-sendable` MUST
- `testing-registration-debug-only` MUST
- `additional-search-paths-optional` MUST
- `search-path-order-fixed` MUST
- `testing-initializer-explicit` MUST
- `in-memory-state-only` MUST

## Behavioral Requirements

- **existing-search-paths-only**: `discoverPlugins()` MUST only enumerate a `searchPaths` entry that exists on disk (`FileManager.fileExists(atPath:)`), silently skipping any entry that does not exist.
- **aiplugin-extension-filter**: `discoverPlugins()` MUST only consider a directory entry whose `pathExtension` is exactly `"aiplugin"`.
- **no-binary-load-at-discovery**: `discoverPlugins()` MUST NOT call `Bundle.load()` or otherwise map a candidate's binary into memory; it MUST only construct a `Bundle` from the candidate's URL and read `descriptor.json` from it.
- **unreadable-candidate-skip**: `discoverPlugins()` MUST skip a candidate — not add it to the manager's records — and log a warning naming the candidate's last path component when `Bundle(url:)` fails to initialize, or when `descriptor.json` is missing, unreadable, or fails to decode as `AIPluginDescriptor`.
- **schema-version-filter**: `discoverPlugins()` MUST skip a candidate — not add it to records — and log a warning naming the descriptor's `displayName` and `schemaVersion` when `schemaVersion` falls outside `2...AIPluginDescriptor.currentSchemaVersion` (currently `2...3`).
- **duplicate-identifier-first-wins**: `discoverPlugins()` MUST silently ignore (no log, not added to records) a candidate whose `descriptor.identifier` already matches a previously recorded descriptor, so the search path that appears first in `searchPaths` order wins for a given identifier.
- **discovery-idempotent**: Calling `discoverPlugins()` more than once MUST leave `descriptors` unchanged for every identifier a previous call already discovered.
- **descriptor-log-on-success**: `discoverPlugins()` MUST log an info message naming the `displayName` and `identifier` for every candidate it adds to records.
- **descriptors-list**: `descriptors` MUST return exactly one `AIPluginDescriptor` per discovered record, in the order the records were appended.
- **available-templates-list**: `availableTemplates` MUST return one `AvailableProviderTemplate` per (record, template) pair drawn from each record's `descriptor.resolvedTemplates`, in descriptor order then template order, each paired with that descriptor's `identifier`.
- **template-lookup**: `template(pluginIdentifier:templateId:)` MUST return the first entry of `descriptor(for: pluginIdentifier)?.resolvedTemplates` whose `id` equals `templateId`, or `nil` when the plugin is undiscovered or no template matches.
- **fields-resolution-known-plugin**: `fields(pluginIdentifier:template:)` MUST return `descriptor.fields(for: template)` when `descriptor(for: pluginIdentifier)` is non-nil.
- **fields-resolution-unknown-plugin**: `fields(pluginIdentifier:template:)` MUST return `template.fields` when `descriptor(for: pluginIdentifier)` is `nil` and `template.fields` is non-nil, and MUST return an empty array when both are absent.
- **load-cache-hit**: `loadPlugin(identifier:)` MUST return the existing entry in `loadedPlugins` for `identifier`, without constructing a new `Bundle` or a new instance, when one is already cached.
- **loaded-plugin-identity-stable**: Two calls to `loadPlugin(identifier:)` for the same `identifier`, with no intervening `unloadPlugin(identifier:)`, MUST return the same object instance (reference identity), never two separate instances of the plugin type.
- **load-unknown-identifier**: `loadPlugin(identifier:)` MUST throw `AIPluginError.notFound(identifier)` when no record matches `identifier`.
- **load-bundle-construction-failure**: `loadPlugin(identifier:)` MUST throw `AIPluginError.loadFailed(identifier)` when `Bundle(url: record.bundleURL)` returns `nil`.
- **load-dlopen-failure**: `loadPlugin(identifier:)` MUST throw `AIPluginError.loadFailed(identifier)` when the constructed bundle is not already loaded (`bundle.isLoaded == false`) and `bundle.load()` returns `false`.
- **load-missing-principal-class**: `loadPlugin(identifier:)` MUST throw `AIPluginError.noPrincipalClass(identifier)` when the loaded bundle's `principalClass` is `nil`.
- **load-non-conforming-principal-class**: `loadPlugin(identifier:)` MUST throw `AIPluginError.principalClassNotPlugin(identifier)` when `principalClass` cannot be cast to `any AIPlugin.Type`.
- **load-success-caching**: On success, `loadPlugin(identifier:)` MUST instantiate the plugin type's required `init()`, store the instance in `loadedPlugins[identifier]`, store the `Bundle` in `loadedBundles[identifier]`, log an info message naming the descriptor's `displayName`, and return the instance.
- **load-all-resilient**: `loadAllPlugins()` MUST call `loadPlugin(identifier:)` for every identifier in `descriptors`, MUST continue attempting the remaining identifiers after any one call throws, MUST log an error naming the failing descriptor's `displayName`, `identifier`, and the thrown error's localized message, and MUST return a `PluginLoadResult` whose `loaded` array holds every succeeding instance and whose `failures` array holds one `PluginLoadFailure` (`identifier`, `displayName`, `message`) per failing identifier.
- **unload-removes-instance**: `unloadPlugin(identifier:)` MUST remove `identifier`'s entry from `loadedPlugins` if present.
- **unload-always-logs**: `unloadPlugin(identifier:)` MUST log an info message naming `identifier`, whether or not an entry was present in `loadedPlugins` to remove.
- **unload-retains-bundle**: `unloadPlugin(identifier:)` MUST NOT remove `identifier`'s entry from `loadedBundles`, and MUST NOT take any action to unload the bundle's binary from memory.
- **descriptor-query-no-load**: `descriptor(for:)` MUST return the recorded `AIPluginDescriptor` for `identifier`, or `nil` if undiscovered, without loading any binary.
- **plugin-query-no-load**: `plugin(for:)` MUST return the cached instance for `identifier` from `loadedPlugins`, or `nil` if not loaded, without triggering `loadPlugin`.
- **internal-record-hidden**: A discovered candidate's bundle URL (`Record.bundleURL`) MUST NOT be exposed by any public API; only `descriptors`, `availableTemplates`, and the query methods expose discovered state.
- **main-actor-confinement**: Every property and method of the manager MUST execute only on the main actor, per the type's `@MainActor` declaration; a caller MUST reach it through the main actor (directly, or with an explicit `await` hop), never through unsynchronized concurrent access.
- **load-result-non-sendable**: `PluginLoadResult` MUST be treated as non-`Sendable` across actor or task boundaries because the type declares no `Sendable` conformance, regardless of its members (`[any AIPlugin]`, `[PluginLoadFailure]`) being individually `Sendable`-eligible.
- **testing-registration-debug-only**: `registerForTesting(_:)` MUST exist only in `DEBUG` builds, MUST append a record pairing the given descriptor with the fixed `bundleURL` `/dev/null`, and a subsequent `loadPlugin(identifier:)` for that identifier MUST still throw `AIPluginError.loadFailed` since no real bundle exists at that URL.
- **additional-search-paths-optional**: `init(appName:additionalSearchPaths:)` MAY receive `additionalSearchPaths`; when it is omitted (default `[]`), the manager MUST scan only the three default locations.
- **search-path-order-fixed**: `init(appName:additionalSearchPaths:)` MUST build `searchPaths` in this order: `Bundle.main.builtInPlugInsURL` (only when non-nil), then `~/.agenticplugins`, then `~/Library/Application Support/<appName>/Plugins` (only when resolvable), then `additionalSearchPaths` appended in the order given.
- **testing-initializer-explicit**: `init(searchPaths:appName:)` MUST use exactly the given `searchPaths`, with no default-location derivation, defaulting `appName` to `"AgenticPlugins"` when the argument is omitted.
- **in-memory-state-only**: `records`, `loadedPlugins`, and `loadedBundles` MUST exist only in memory for the lifetime of the `AIPluginManager` instance; none of this state MUST be persisted to disk, and a newly created instance MUST report empty `descriptors`, empty `availableTemplates`, and no loaded plugins until `discoverPlugins()` is called at least once.

- **search-path-enumeration-failure**: NEEDS REVIEW: Not implemented in source. `discoverPlugins()` swallows the error from `try? fileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` for a search path that exists but cannot be enumerated (e.g. a permissions failure, or a path that exists as a non-directory file) — the `guard ... else { continue }` produces no log line and no way for a caller to distinguish "this path had nothing in it" from "this path could not be read." Every other skip branch in the same method (an unreadable descriptor, an incompatible schema) logs a warning; this one does not. What is missing: whether an enumeration failure should be logged, surfaced through a return value, or left silent as it is today. This could not be determined from the source alone because the asymmetry with the sibling skip branches gives no signal of intent. It can be resolved by whoever owns `AIPluginManager`'s callers confirming whether silent operation here is acceptable or whether it should log like the other skip paths.
- **empty-app-name-unvalidated**: NEEDS REVIEW: Not implemented in source. `init(appName:additionalSearchPaths:)` never validates that `appName` is non-empty before passing it to `InstalledContentLocation.applicationSupport(appName:subdirectory:)`. That helper's own documentation (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift`) states an empty `appName` component "collapses the path onto the *shared* `Application Support/<subdirectory>` and silently widens the search to every app's content of that kind" — for this manager, `Application Support/Plugins`. What is missing: whether an empty `appName` should be rejected (precondition/assertion), defaulted, or is simply never expected to occur in practice. This could not be determined from `AIPluginManager.swift` alone, since the risk is documented only in the helper it calls, not enforced at this call site. It can be resolved by whoever owns the manager's call sites confirming whether `appName` can ever be empty before app metadata is configured.

