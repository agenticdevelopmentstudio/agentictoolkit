---
id: 0a729d47-fc2d-427c-b474-26072dc8b336
title: AI Plugin Manager
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Discovers .aiplugin bundles from disk, reads their descriptor.json without
  loading code, and lazily loads/instantiates the AIPlugin on demand.
platforms:
- swift
- macos
tags:
- ai-plugin
- plugin-manager
- discovery
- dynamic-loading
- bundle-loading
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
references: []
approved-by: ''
approved-date: ''
---

# AI Plugin Manager

## Overview

`AIPluginManager.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift`) defines `AIPluginManager`, a `@MainActor` class that discovers, describes, and loads LLM provider plugins shipped as macOS `.aiplugin` bundles. A plugin bundle's `NSPrincipalClass` conforms to `AIPluginKit.AIPlugin`. Discovery reads each bundle's `descriptor.json` — a plain JSON resource describing the plugin's identity, models, settings fields, and provider templates — without loading (`dlopen`-ing) the plugin's binary, so a settings UI can list and configure a plugin from its descriptor alone. Loading a plugin (`bundle.load()` plus instantiating the `NSPrincipalClass`) only happens on demand, the first time a caller asks for that plugin's instance, and the resulting instance is cached for the manager's lifetime. The manager owns no networking, no UI, and no secret storage — those belong to the loaded `AIPlugin`, the settings UI built from the descriptor, and `AIPluginKit`'s secret-storage types respectively.

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

NEEDS REVIEW: Not implemented in source. `discoverPlugins()` swallows the error from `try? fileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` for a search path that exists but cannot be enumerated (e.g. a permissions failure, or a path that exists as a non-directory file) — the `guard ... else { continue }` produces no log line and no way for a caller to distinguish "this path had nothing in it" from "this path could not be read." Every other skip branch in the same method (an unreadable descriptor, an incompatible schema) logs a warning; this one does not. What is missing: whether an enumeration failure should be logged, surfaced through a return value, or left silent as it is today. This could not be determined from the source alone because the asymmetry with the sibling skip branches gives no signal of intent. It can be resolved by whoever owns `AIPluginManager`'s callers confirming whether silent operation here is acceptable or whether it should log like the other skip paths.

NEEDS REVIEW: Not implemented in source. `init(appName:additionalSearchPaths:)` never validates that `appName` is non-empty before passing it to `InstalledContentLocation.applicationSupport(appName:subdirectory:)`. That helper's own documentation (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift`) states an empty `appName` component "collapses the path onto the *shared* `Application Support/<subdirectory>` and silently widens the search to every app's content of that kind" — for this manager, `Application Support/Plugins`. What is missing: whether an empty `appName` should be rejected (precondition/assertion), defaulted, or is simply never expected to occur in practice. This could not be determined from `AIPluginManager.swift` alone, since the risk is documented only in the helper it calls, not enforced at this call site. It can be resolved by whoever owns the manager's call sites confirming whether `appName` can ever be empty before app metadata is configured.

## Appearance

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## States

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## Accessibility

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-manager-001 | existing-search-paths-only, aiplugin-extension-filter, no-binary-load-at-discovery, descriptors-list, descriptor-log-on-success | One search path containing a single valid `.aiplugin` bundle with a v3 descriptor, identifier `p1` | `discoverPlugins()` populates `descriptors` with exactly the `p1` descriptor; an info log "Discovered plugin: <name> (p1)" is emitted; no `dlopen`/`bundle.load()` occurs |
| ai-plugin-manager-002 | unreadable-candidate-skip | Same as above, but `descriptor.json` is malformed JSON | `discoverPlugins()` leaves `descriptors` empty; a warning log "Skipping plugin without a readable descriptor: <bundle filename>" is emitted; no error is thrown |
| ai-plugin-manager-003 | schema-version-filter | A `.aiplugin` bundle whose descriptor has `schemaVersion: 1` | `discoverPlugins()` leaves `descriptors` empty; a warning log naming schema `1` as not in `2...3` is emitted |
| ai-plugin-manager-004 | duplicate-identifier-first-wins, search-path-order-fixed | Two search paths, each with a `.aiplugin` bundle whose `identifier` is `"dup"` but different `displayName`s, in `searchPaths` order `[pathA, pathB]` | `descriptors.count == 1`; `descriptor(for: "dup")!.displayName` equals `pathA`'s bundle's `displayName`; no log is emitted for `pathB`'s candidate |
| ai-plugin-manager-005 | discovery-idempotent | `discoverPlugins()` already called once against a path with plugin `p1` | Calling `discoverPlugins()` again with the same `searchPaths` leaves `descriptors == [descriptor(p1)]`, with no duplicate entry |
| ai-plugin-manager-006 | available-templates-list | A descriptor with two entries in `templates` | `availableTemplates` has exactly two `AvailableProviderTemplate` entries, each with `pluginIdentifier == descriptor.identifier`, in the same order as `descriptor.templates` |
| ai-plugin-manager-007 | available-templates-list, template-lookup | A descriptor with `templates == nil`, `models: ["m1", "m2"]`, `fields: [F]` | `availableTemplates` contains one synthesized template with `id == "default"`, `models == ["m1", "m2"]`; `template(pluginIdentifier:templateId: "default")` returns that same template |
| ai-plugin-manager-008 | fields-resolution-known-plugin | A discovered descriptor with `fields == [F1]`; a template with `fields == nil` | `fields(pluginIdentifier:template:)` returns `[F1]` |
| ai-plugin-manager-009 | fields-resolution-unknown-plugin | `pluginIdentifier` not present in records; a template with `fields == [F2]` | `fields(pluginIdentifier:template:)` returns `[F2]` |
| ai-plugin-manager-010 | fields-resolution-unknown-plugin | `pluginIdentifier` not present in records; a template with `fields == nil` | `fields(pluginIdentifier:template:)` returns `[]` |
| ai-plugin-manager-011 | load-unknown-identifier | `identifier` not present in records | `try loadPlugin(identifier:)` throws `AIPluginError.notFound(identifier)`; `errorDescription == "Plugin not found: <identifier>"` |
| ai-plugin-manager-012 | load-bundle-construction-failure, testing-registration-debug-only | A record whose `bundleURL` is `/dev/null` (as `registerForTesting` produces) | `try loadPlugin(identifier:)` throws `AIPluginError.loadFailed(identifier)` |
| ai-plugin-manager-013 | load-success-caching, load-cache-hit, loaded-plugin-identity-stable | A real, loadable `.aiplugin` bundle whose `NSPrincipalClass` conforms to `AIPlugin` | First `loadPlugin(identifier:)` call returns an instance and logs "Loaded plugin: <name>"; a second call for the same identifier returns the identical instance (`===`), with no second `Bundle` construction and no second log line |
| ai-plugin-manager-014 | load-missing-principal-class | A discoverable bundle whose `NSPrincipalClass` is unset | `try loadPlugin(identifier:)` throws `AIPluginError.noPrincipalClass(identifier)` |
| ai-plugin-manager-015 | load-non-conforming-principal-class | A discoverable bundle whose principal class does not conform to `AIPlugin` | `try loadPlugin(identifier:)` throws `AIPluginError.principalClassNotPlugin(identifier)` |
| ai-plugin-manager-016 | load-all-resilient | Three discovered descriptors; the second's `loadPlugin` throws `noPrincipalClass`, the first and third succeed | `loadAllPlugins()` returns `loaded.count == 2` (first and third instances) and `failures.count == 1` naming the second's identifier/displayName/message; an error log is emitted for the second; the third still loads |
| ai-plugin-manager-017 | unload-removes-instance, unload-always-logs | `identifier` currently loaded | `unloadPlugin(identifier:)` makes `plugin(for: identifier)` return `nil` afterward; `descriptor(for: identifier)` is unchanged; an info log "Unloaded plugin: <identifier>" is emitted |
| ai-plugin-manager-018 | unload-retains-bundle | `identifier` currently loaded, then `unloadPlugin(identifier:)` called | Manual/debugger check: the manager's private `loadedBundles[identifier]` still holds the same `Bundle` object immediately after `unloadPlugin` returns; the binary is never explicitly unloaded |
| ai-plugin-manager-019 | search-path-order-fixed, additional-search-paths-optional | `init(appName:additionalSearchPaths: [customURL])` with one distinct, uniquely identified plugin placed at each of the app bundle's `PlugIns`, `~/.agenticplugins`, Application Support, and `customURL` locations | `discoverPlugins()` appends `descriptors` in exactly that order: built-in, dotfolder, Application Support, then the custom path |
| ai-plugin-manager-020 | testing-initializer-explicit | `init(searchPaths: [dirX], appName: "Test")`, with `dirX` the only location under test control | `discoverPlugins()` discovers only `dirX`'s plugins; the app bundle, home dotfolder, and Application Support locations are never consulted |
| ai-plugin-manager-021 | in-memory-state-only | A freshly created `AIPluginManager` before `discoverPlugins()` is ever called | `descriptors == []`, `availableTemplates == []`, and `plugin(for: "anything") == nil` |
| ai-plugin-manager-022 | testing-registration-debug-only | `registerForTesting(descriptor)` called in a `DEBUG` build with a hand-built `AIPluginDescriptor` | `descriptors` contains the injected descriptor; `try loadPlugin(identifier:)` for it throws `AIPluginError.loadFailed` |
| ai-plugin-manager-023 | main-actor-confinement | Compile-time: code calling `manager.descriptors` (or any other member) from a `nonisolated` or `Task.detached` context with no `await` | Fails to compile with a main-actor-isolation diagnostic |
| ai-plugin-manager-024 | load-result-non-sendable | Compile-time: a `PluginLoadResult` value captured in a `@Sendable` closure or sent across a `Task.detached` boundary | Fails to compile (or requires an explicit unsafe opt-out) with a `Sendable`-conformance diagnostic, since `PluginLoadResult` declares no `Sendable` conformance |

## Edge Cases

- Empty `searchPaths` (e.g. `init(searchPaths: [], appName: "Test")`): `discoverPlugins()` MUST leave `descriptors` and `availableTemplates` empty; no error is raised.
- A `searchPaths` entry that does not exist on disk: MUST be skipped silently by `existing-search-paths-only`; no log, no error.
- A `searchPaths` entry that exists but cannot be enumerated (permissions failure, or a non-directory file at that path): silently skipped with no log — see the open question above about `existing-search-paths-only`.
- A directory entry with the `.aiplugin` extension that is not a valid bundle: caught by `unreadable-candidate-skip` (`Bundle(url:)` returns `nil`), logged and skipped, MUST NOT throw.
- `descriptor.json` absent, unreadable, or not valid JSON for the declared `AIPluginDescriptor` shape: caught by `unreadable-candidate-skip`, logged and skipped, MUST NOT throw. This is also how a pre-descriptor "v1" plugin (no `descriptor.json` at all) is ignored, per the source's own doc comment.
- `schemaVersion` below `2` or above `AIPluginDescriptor.currentSchemaVersion`: caught by `schema-version-filter`, logged and skipped, MUST NOT throw.
- The same `identifier` discovered from two or more search paths (including the same identifier appearing twice in one directory listing, which cannot occur since file names are unique): only the first-recorded one is kept, per `duplicate-identifier-first-wins`.
- `loadPlugin(identifier:)` for an `identifier` never discovered: MUST throw `AIPluginError.notFound`, per `load-unknown-identifier`.
- `loadPlugin(identifier:)` called concurrently is not a distinct case: the type's `@MainActor` isolation (`main-actor-confinement`) means two calls are always serialized on the main actor, never truly concurrent; there is no data race to define behavior for.
- `unloadPlugin(identifier:)` for an `identifier` that was never loaded: `loadedPlugins.removeValue(forKey:)` is a no-op, but the info log fires anyway, per `unload-always-logs`.
- Cancellation: none of the manager's methods are `async` or accept a `Task`; there is nothing to cancel. Not applicable.
- Timeouts: `discoverPlugins()` and `loadPlugin(identifier:)` perform only synchronous local file-system and dynamic-loading calls, with no network access and no timeout parameter. Not applicable.
- `registerForTesting(_:)` is compiled only under `#if DEBUG`; in a `RELEASE`/production build the method does not exist at all, per `testing-registration-debug-only`.
- Offline/disconnected state: the manager makes no network requests of its own (that is the loaded `AIPlugin`'s and `PluginTransport`'s job); connectivity loss cannot affect discovery or loading. Not applicable.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appName` (`init(appName:additionalSearchPaths:)`) | `String` | none — required | Names the `~/Library/Application Support/<appName>/Plugins` search location; not validated for emptiness (see the open question above) |
| `additionalSearchPaths` (`init(appName:additionalSearchPaths:)`) | `[URL]` | `[]` | Extra directories appended after the three default locations, in the order given |
| `searchPaths` (`init(searchPaths:appName:)`) | `[URL]` | none — required | Replaces all default-location derivation entirely; used by tests |
| `appName` (`init(searchPaths:appName:)`) | `String` | `"AgenticPlugins"` | Retained alongside explicit `searchPaths`, but not consulted to derive any path in this initializer |
| `Bundle.main.builtInPlugInsURL` (environment) | `URL?` | app-bundle-determined | `Contents/PlugIns` inside the running app bundle; included as a search path only when non-nil |
| `NSHomeDirectory()` (environment) | `String` (path) | current user's home | Base for the `~/.agenticplugins` search path |
| Application Support directory (environment, `FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)`) | `URL?` | `~/Library/Application Support` | Base for `<appName>/Plugins`; the whole search path is omitted when unavailable |

## Deep Linking

Not applicable: `AIPluginManager.swift` defines no URL scheme handling, and nothing in it registers, parses, or responds to a deep link.

## Localization

No message in this file is externalized through a localization key (no `NSLocalizedString`/`String(localized:)`). Every user-facing string is a hardcoded English `String` literal interpolated into `AIPluginError.errorDescription`:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Plugin not found: <id>` | `AIPluginError.notFound.errorDescription` |
| (none — hardcoded) | `Failed to load plugin bundle: <id>` | `AIPluginError.loadFailed.errorDescription` |
| (none — hardcoded) | `Plugin '<id>' has no NSPrincipalClass` | `AIPluginError.noPrincipalClass.errorDescription` |
| (none — hardcoded) | `Plugin '<id>' principal class does not conform to AIPlugin` | `AIPluginError.principalClassNotPlugin.errorDescription` |

## Accessibility Options

Not applicable: this is a non-UI logic component with no visible surface, so it consults none of the system accessibility display options (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: `AIPluginManager.swift` reads no feature-flag key and gates none of its behavior behind one.

## Analytics

Not applicable: `AIPluginManager.swift` emits no analytics events; its only instrumentation is the `OSLog`/`Logger` calls documented under Logging.

## Privacy

- **Data collected**: `AIPluginManager` reads plugin metadata only — `descriptor.json`'s `identifier`, `displayName`, `version`, `models`, `defaultModel`, `fields` (key/label/kind/placeholder shape, not values), and `templates`. It never reads, stores, or transmits a credential or configuration value; `AIPluginDescriptor.Field.kind == .secret` only labels which *field* a settings UI should mask and persist to the Keychain elsewhere in `AIPluginKit` (`SecretStoring`, `AIProviderConfigSync`) — this file never touches an actual secret value.
- **Storage**: Everything this type reads is kept only in the in-memory `records`, `loadedPlugins`, and `loadedBundles` collections (per `in-memory-state-only`); nothing is written to disk by this type.
- **Transmission**: This type performs no network communication.
- **Retention**: Discovered and loaded state lives only as long as the `AIPluginManager` instance; it is not persisted and does not survive process restart.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy And Data |

Explicit-error-handling is `partial`: `loadPlugin`/`loadAllPlugins` report every failure as a typed, thrown `AIPluginError`, but `discoverPlugins()`'s directory-enumeration failure is swallowed with no log and no thrown error (see the open question in Behavioral Requirements). Fault-tolerance passes because `loadAllPlugins()` isolates each plugin's failure into `PluginLoadResult.failures` and keeps loading the rest. No-hardcoded-strings fails because every `AIPluginError.errorDescription` is an unlocalized English literal (see Localization). No-pii-in-logs passes because every logged value is a plugin identifier, display name, schema number, or bundle filename — never a credential or user-content value.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
