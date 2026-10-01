---
id: 0a729d47-fc2d-427c-b474-26072dc8b336
title: Plugin Manager
domain: agentictoolkit://cookbook/ai/plugins/plugin-manager
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Discovers plugin bundles from disk, reads each one's descriptor without
  loading its code, and lazily loads and instantiates the plugin on demand.
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
- agentictoolkit://cookbook/ai/chat/chat-context
references: []
approved-by: ''
approved-date: ''
---

# Plugin Manager

## Overview

The plugin manager discovers, describes, and loads provider plugins shipped as
plugin bundles. A plugin bundle declares a principal type that conforms to the
plugin protocol. Discovery reads each bundle's descriptor — a plain JSON
resource describing the plugin's identity, models, settings fields, and
provider templates — without loading the plugin's code, so a settings UI can
list and configure a plugin from its descriptor alone. Loading a plugin
(mapping its code into the running process and instantiating its principal
type) only happens on demand, the first time a caller asks for that plugin's
instance, and the resulting instance is cached for the manager's lifetime. The
manager owns no networking, no UI, and no secret storage — those belong to the
loaded plugin, the settings UI built from the descriptor, and the
secret-storage component respectively.

## Behavioral Requirements

- **existing-search-paths-only**: Discovery MUST only scan a search-path entry that exists on disk, silently skipping any entry that does not exist.
- **aiplugin-extension-filter**: Discovery MUST only consider a directory entry whose file extension is exactly `aiplugin`.
- **no-binary-load-at-discovery**: Discovery MUST NOT load or otherwise map a candidate's executable code into memory; it MUST only open the candidate as a bundle and read its descriptor file from it.
- **unreadable-candidate-skip**: Discovery MUST skip a candidate — not add it to the manager's records — and log a warning naming the candidate's last path component when the candidate cannot be opened as a bundle, or when its descriptor file is missing, unreadable, or fails to decode as a descriptor.
- **schema-version-filter**: Discovery MUST skip a candidate — not add it to records — and log a warning naming the descriptor's display name and schema version when the descriptor's schema version falls outside the currently supported range (currently 2 through 3).
- **duplicate-identifier-first-wins**: Discovery MUST silently ignore (no log, not added to records) a candidate whose descriptor identifier already matches a previously recorded descriptor, so the search path that appears first in search-path order wins for a given identifier.
- **discovery-idempotent**: Running discovery more than once MUST leave the discovered descriptors unchanged for every identifier a previous run already discovered.
- **descriptor-log-on-success**: Discovery MUST log an info message naming the display name and identifier for every candidate it adds to records.
- **descriptors-list**: The discovered-descriptors list MUST return exactly one descriptor per discovered record, in the order the records were appended.
- **available-templates-list**: The available-templates list MUST return one entry per (record, template) pair drawn from each record's resolved templates, in descriptor order then template order, each paired with that descriptor's identifier.
- **template-lookup**: Looking up a template by plugin identifier and template id MUST return the first resolved template of that plugin's descriptor whose id matches, or nothing when the plugin is undiscovered or no template matches.
- **fields-resolution-known-plugin**: Resolving a template's fields MUST return the descriptor's fields for that template when the plugin is discovered.
- **fields-resolution-unknown-plugin**: Resolving a template's fields MUST return the template's own fields when the plugin is not discovered and the template declares fields, and MUST return an empty list when both are absent.
- **load-cache-hit**: Loading a plugin MUST return the existing cached instance for that identifier, without re-opening the bundle or constructing a new instance, when one is already cached.
- **loaded-plugin-identity-stable**: Two calls to load the same plugin identifier, with no intervening unload, MUST return the same object instance (reference identity), never two separate instances of the plugin type.
- **load-unknown-identifier**: Loading a plugin MUST fail with a not-found error naming the identifier when no record matches it.
- **load-bundle-construction-failure**: Loading a plugin MUST fail with a load-failed error naming the identifier when the candidate's bundle cannot be opened.
- **load-dlopen-failure**: Loading a plugin MUST fail with a load-failed error naming the identifier when the bundle is not already loaded and loading its code fails.
- **load-missing-principal-class**: Loading a plugin MUST fail with a no-principal-class error naming the identifier when the loaded bundle declares no principal type.
- **load-non-conforming-principal-class**: Loading a plugin MUST fail with a principal-class-not-plugin error naming the identifier when the principal type does not conform to the plugin protocol.
- **load-success-caching**: On success, loading a plugin MUST instantiate the plugin type's required initializer, cache the instance and its bundle by identifier, log an info message naming the descriptor's display name, and return the instance.
- **load-all-resilient**: Loading all plugins MUST attempt to load every discovered identifier, MUST continue attempting the remaining identifiers after any one load fails, MUST log an error naming the failing descriptor's display name, identifier, and the failure's message, and MUST return a result whose loaded list holds every succeeding instance and whose failures list holds one entry (identifier, display name, message) per failing identifier.
- **unload-removes-instance**: Unloading a plugin MUST remove that identifier's cached instance if present.
- **unload-always-logs**: Unloading a plugin MUST log an info message naming the identifier, whether or not a cached instance was present to remove.
- **unload-retains-bundle**: Unloading a plugin MUST NOT remove that identifier's cached bundle, and MUST NOT take any action to unload the bundle's code from memory.
- **descriptor-query-no-load**: Looking up a discovered descriptor MUST return the recorded descriptor for an identifier, or nothing if undiscovered, without loading any code.
- **plugin-query-no-load**: Looking up a loaded plugin MUST return the cached instance for an identifier, or nothing if not loaded, without triggering a load.
- **internal-record-hidden**: A discovered candidate's bundle location MUST NOT be exposed by any public interface; only the discovered descriptors, the available templates, and the query operations expose discovered state.
- **single-context-confinement**: Every property and operation of the manager MUST execute only within a single, designated execution context; a caller MUST reach it through that context (directly, or with an explicit hand-off), never through unsynchronized concurrent access.
- **load-result-context-confined**: A load result value MUST be treated as usable only within the execution context that produced it; it MUST NOT be passed to or read from a separate concurrent execution context, regardless of whether its members are individually safe to share.
- **testing-registration-debug-only**: Test registration MUST exist only in builds with testing support enabled, MUST append a record pairing the given descriptor with a fixed, non-existent bundle location, and a subsequent load for that identifier MUST still fail with a load-failed error since no real bundle exists there.
- **additional-search-paths-optional**: Creating a manager with an app name MAY receive additional search paths; when omitted (default: none), the manager MUST scan only the three default locations.
- **search-path-order-fixed**: Creating a manager with an app name MUST build the search paths in this order: the running app's own built-in plugins location (only when the platform resolves one), then the user's home dotfolder location, then the app's Application Support location (only when resolvable), then any additional search paths appended in the order given.
- **testing-initializer-explicit**: Creating a manager with explicit search paths MUST use exactly the given search paths, with no default-location derivation, defaulting the app name to `"AgenticPlugins"` when omitted.
- **in-memory-state-only**: The manager's records, loaded plugins, and loaded bundles MUST exist only in memory for the manager's lifetime; none of this state MUST be persisted to disk, and a newly created manager MUST report empty discovered descriptors, empty available templates, and no loaded plugins until discovery has run at least once.

- **search-path-enumeration-failure**: NEEDS REVIEW: Not implemented in source. Discovery swallows the error when a search-path entry exists but cannot be enumerated (e.g. a permissions failure, or a path that exists as a non-directory file) — that skip produces no log line and no way for a caller to distinguish "this path had nothing in it" from "this path could not be read." Every other skip branch in the same discovery pass (an unreadable descriptor, an incompatible schema) logs a warning; this one does not. What is missing: whether an enumeration failure should be logged, surfaced through a return value, or left silent as it is today. This could not be determined from the source alone because the asymmetry with the sibling skip branches gives no signal of intent. It can be resolved by whoever owns this manager's callers confirming whether silent operation here is acceptable or whether it should log like the other skip paths.
- **empty-app-name-unvalidated**: NEEDS REVIEW: Not implemented in source. Creating a manager with an app name never validates that the app name is non-empty before using it to build the Application Support search path. The helper this relies on documents that an empty app-name component "collapses the path onto the *shared* Application Support/<subdirectory> and silently widens the search to every app's content of that kind" — for this manager, the shared Plugins location. What is missing: whether an empty app name should be rejected (an assertion), defaulted, or is simply never expected to occur in practice. This could not be determined from the manager alone, since the risk is documented only in the helper it calls, not enforced at this call site. It can be resolved by whoever owns the manager's call sites confirming whether the app name can ever be empty before app metadata is configured.

## Appearance

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## States

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## Accessibility

Not applicable — this is a plugin discovery and loading manager, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-manager-001 | existing-search-paths-only, aiplugin-extension-filter, no-binary-load-at-discovery, descriptors-list, descriptor-log-on-success | One search path containing a single valid plugin bundle with a v3 descriptor, identifier `p1` | Discovery populates the discovered descriptors with exactly the `p1` descriptor; an info log "Discovered plugin: <name> (p1)" is emitted; the candidate's code is never loaded |
| ai-plugin-manager-002 | unreadable-candidate-skip | Same as above, but the descriptor file is malformed JSON | Discovery leaves the discovered descriptors empty; a warning log "Skipping plugin without a readable descriptor: <bundle filename>" is emitted; no error is thrown |
| ai-plugin-manager-003 | schema-version-filter | A plugin bundle whose descriptor has schema version 1 | Discovery leaves the discovered descriptors empty; a warning log naming schema `1` as not in `2...3` is emitted |
| ai-plugin-manager-004 | duplicate-identifier-first-wins, search-path-order-fixed | Two search paths, each with a plugin bundle whose identifier is `"dup"` but different display names, in search-path order `[pathA, pathB]` | Exactly one descriptor is discovered; its display name equals pathA's bundle's display name; no log is emitted for pathB's candidate |
| ai-plugin-manager-005 | discovery-idempotent | Discovery already run once against a path with plugin `p1` | Running discovery again with the same search paths leaves the discovered descriptors as just `p1`'s descriptor, with no duplicate entry |
| ai-plugin-manager-006 | available-templates-list | A descriptor with two entries in its templates | The available templates list has exactly two entries, each paired with that descriptor's identifier, in the same order as the descriptor's templates |
| ai-plugin-manager-007 | available-templates-list, template-lookup | A descriptor with no templates, models `["m1", "m2"]`, one field `F` | The available templates list contains one synthesized template with id `"default"` and models `["m1", "m2"]`; looking up that plugin's `"default"` template returns that same template |
| ai-plugin-manager-008 | fields-resolution-known-plugin | A discovered descriptor with fields `[F1]`; a template with no fields of its own | Resolving that template's fields returns `[F1]` |
| ai-plugin-manager-009 | fields-resolution-unknown-plugin | A plugin identifier not present in records; a template with fields `[F2]` | Resolving that template's fields returns `[F2]` |
| ai-plugin-manager-010 | fields-resolution-unknown-plugin | A plugin identifier not present in records; a template with no fields of its own | Resolving that template's fields returns an empty list |
| ai-plugin-manager-011 | load-unknown-identifier | An identifier not present in records | Loading that plugin fails with a not-found error; its message reads "Plugin not found: <identifier>" |
| ai-plugin-manager-012 | load-bundle-construction-failure, testing-registration-debug-only | A record whose bundle location is a fixed, non-existent path (as test registration produces) | Loading that plugin fails with a load-failed error |
| ai-plugin-manager-013 | load-success-caching, load-cache-hit, loaded-plugin-identity-stable | A real, loadable plugin bundle whose principal type conforms to the plugin protocol | The first load returns an instance and logs "Loaded plugin: <name>"; a second load for the same identifier returns the identical instance, with no second bundle open and no second log line |
| ai-plugin-manager-014 | load-missing-principal-class | A discoverable bundle whose principal type is unset | Loading that plugin fails with a no-principal-class error |
| ai-plugin-manager-015 | load-non-conforming-principal-class | A discoverable bundle whose principal type does not conform to the plugin protocol | Loading that plugin fails with a principal-class-not-plugin error |
| ai-plugin-manager-016 | load-all-resilient | Three discovered descriptors; the second's load fails with a no-principal-class error, the first and third succeed | Loading all plugins returns two loaded instances (first and third) and one failure entry naming the second's identifier/display name/message; an error log is emitted for the second; the third still loads |
| ai-plugin-manager-017 | unload-removes-instance, unload-always-logs | An identifier currently loaded | Unloading it makes a later lookup for that identifier return nothing afterward; the descriptor lookup is unchanged; an info log "Unloaded plugin: <identifier>" is emitted |
| ai-plugin-manager-018 | unload-retains-bundle | An identifier currently loaded, then unloaded | Manual/inspection check: the manager's cached bundle for that identifier is still present immediately after unloading; the code is never explicitly unloaded |
| ai-plugin-manager-019 | search-path-order-fixed, additional-search-paths-optional | Creating a manager with an app name and one additional search path, with one distinct, uniquely identified plugin placed at each of the built-in location, the home dotfolder location, the Application Support location, and the additional path | Discovery appends the discovered descriptors in exactly that order: built-in, dotfolder, Application Support, then the additional path |
| ai-plugin-manager-020 | testing-initializer-explicit | Creating a manager with explicit search paths limited to one directory under test control | Discovery discovers only that directory's plugins; the built-in, home dotfolder, and Application Support locations are never consulted |
| ai-plugin-manager-021 | in-memory-state-only | A freshly created manager before discovery has ever run | The discovered descriptors and available templates are both empty, and looking up any plugin returns nothing |
| ai-plugin-manager-022 | testing-registration-debug-only | Test registration called (in a build with testing support enabled) with a hand-built descriptor | The discovered descriptors contain the injected descriptor; loading it fails with a load-failed error |
| ai-plugin-manager-023 | single-context-confinement | Attempting to access the manager's state from outside its designated execution context, with no explicit hand-off | Rejected by the platform's concurrency enforcement (e.g. a compile-time diagnostic) rather than allowed to run concurrently |
| ai-plugin-manager-024 | load-result-context-confined | A load result value passed to or read from a separate concurrent execution context | Rejected by the platform's concurrency enforcement (e.g. a compile-time diagnostic), since a load result carries no cross-context sharing guarantee |

## Edge Cases

- Empty search paths (no locations to scan): discovery MUST leave the discovered descriptors and available templates empty; no error is raised.
- A search-path entry that does not exist on disk: MUST be skipped silently by `existing-search-paths-only`; no log, no error.
- A search-path entry that exists but cannot be enumerated (permissions failure, or a non-directory file at that path): silently skipped with no log — see the open question on `search-path-enumeration-failure`.
- A directory entry with the plugin extension that is not a valid bundle: caught by `unreadable-candidate-skip` (the bundle cannot be opened), logged and skipped, MUST NOT throw.
- The descriptor file absent, unreadable, or not valid JSON for the declared descriptor shape: caught by `unreadable-candidate-skip`, logged and skipped, MUST NOT throw. This is also how a pre-descriptor plugin (no descriptor file at all) is ignored, per the source's own documentation.
- The schema version below the minimum or above the current maximum: caught by `schema-version-filter`, logged and skipped, MUST NOT throw.
- The same identifier discovered from two or more search paths (including the same identifier appearing twice in one directory listing, which cannot occur since file names are unique): only the first-recorded one is kept, per `duplicate-identifier-first-wins`.
- Loading a plugin for an identifier never discovered: MUST fail with a not-found error, per `load-unknown-identifier`.
- Loading a plugin called concurrently is not a distinct case: the manager's single-context confinement (`single-context-confinement`) means two calls are always serialized, never truly concurrent; there is no data race to define behavior for.
- Unloading a plugin for an identifier that was never loaded: removing a non-existent cache entry is a no-op, but the info log fires anyway, per `unload-always-logs`.
- Cancellation: none of the manager's operations are asynchronous or accept a cancellation token; there is nothing to cancel. Not applicable.
- Timeouts: discovery and loading a plugin perform only synchronous local file-system and code-loading calls, with no network access and no timeout parameter. Not applicable.
- Test registration exists only in builds with testing support enabled; in a release/production build the operation does not exist at all, per `testing-registration-debug-only`.
- Offline/disconnected state: the manager makes no network requests of its own (that is the loaded plugin's and its transport's job); connectivity loss cannot affect discovery or loading. Not applicable.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| App name | text | none — required | Names the Application Support search location for this app; not validated for emptiness (see the open question on `empty-app-name-unvalidated`) |
| Additional search paths | list of locations | empty | Extra directories appended after the three default locations, in the order given |
| Explicit search paths | list of locations | none — required | Replaces all default-location derivation entirely; used by tests |
| App name (explicit-search-paths form) | text | `"AgenticPlugins"` | Retained alongside explicit search paths, but not consulted to derive any path in this form |
| Built-in plugins location (environment) | location, optional | platform-determined | The plugins directory inside the running app's own bundle; included as a search path only when the platform resolves one |
| Home dotfolder location (environment) | location | current user's home + `.agenticplugins` | Base for the user-level search path |
| Application Support location (environment) | location, optional | platform-determined user data directory | Base for `<app name>/Plugins`; the whole search path is omitted when unavailable |

## Deep Linking

Not applicable: this component defines no URL scheme handling, and nothing in it registers, parses, or responds to a deep link.

## Localization

No message in this component is externalized through a localization key. Every user-facing string is a hardcoded English string, interpolated into the corresponding error's message:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Plugin not found: <id>` | Not-found error's message |
| (none — hardcoded) | `Failed to load plugin bundle: <id>` | Load-failed error's message |
| (none — hardcoded) | `Plugin '<id>' has no NSPrincipalClass` | No-principal-class error's message |
| (none — hardcoded) | `Plugin '<id>' principal class does not conform to AIPlugin` | Principal-class-not-plugin error's message |

## Accessibility Options

Not applicable: this is a non-UI logic component with no visible surface, so it consults none of the system accessibility display options (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: this component reads no feature-flag key and gates none of its behavior behind one.

## Analytics

Not applicable: this component emits no analytics events; its only instrumentation is the logging calls documented under Logging.

## Privacy

- **Data collected**: The manager reads plugin metadata only — a descriptor's identifier, display name, version, models, default model, fields (key/label/kind/placeholder shape, not values), and templates. It never reads, stores, or transmits a credential or configuration value; a field's secret kind only labels which *field* a settings UI should mask and persist to secure storage elsewhere in the plugin system — this component never touches an actual secret value.
- **Storage**: Everything this component reads is kept only in the in-memory records, loaded-plugins, and loaded-bundles collections (per `in-memory-state-only`); nothing is written to disk by this component.
- **Transmission**: This component performs no network communication.
- **Retention**: Discovered and loaded state lives only as long as the manager instance; it is not persisted and does not survive process restart.

## Logging

Subsystem: the app's bundle identifier (falls back to a fixed placeholder if unset) | Category: the plugin manager's logging category

| Event | Level | Message |
|-------|-------|---------|
| A candidate bundle has no readable descriptor file (cannot be opened, or decode failure) | warning | `Skipping plugin without a readable descriptor: <bundle filename>` |
| A descriptor's schema version is outside the supported range | warning | `Skipping incompatible plugin '<displayName>': schema <n> not in 2...<currentSchemaVersion>` |
| A new, non-duplicate identifier is recorded | info | `Discovered plugin: <displayName> (<identifier>)` |
| Loading a plugin fails inside "load all plugins" | error | `Failed to load plugin '<displayName>' (<identifier>): <message>` |
| Loading a plugin succeeds | info | `Loaded plugin: <displayName>` |
| Unloading a plugin is called, loaded or not | info | `Unloaded plugin: <identifier>` |

## Platform Notes

- **SwiftUI**: The manager is a plain, main-actor-confined Foundation/`os` type with no view-layer dependency, so a SwiftUI host observes it the same way an AppKit host does — typically by wrapping it in an `@Observable`/`ObservableObject` adapter that calls discovery once and republishes the discovered descriptors/available templates after mutating calls, since the manager itself is not observable.
- **Compose**: Kotlin has no `dlopen`/principal-class equivalent for loading arbitrary on-disk bundles into a running process; the nearest analog is Android's `PackageManager`/`DexClassLoader` (loading code from an installed package or a `.dex`/`.jar` at a known path) — a much more restricted and permission-gated model than macOS's own-account file-system scan. Descriptor decoding maps to `kotlinx.serialization` or `Moshi`; the discovery scan maps to `java.io.File.listFiles()`; the single-context confinement maps to a single-threaded `CoroutineDispatcher` (e.g. `Dispatchers.Main`) that every call is confined to.
- **React/Web**: There is no on-disk bundle-loading equivalent in a browser; the closest analog for "discover a descriptor cheaply, load code lazily" is dynamic `import()` (or a plugin registry fetched as JSON) gated behind a manifest file resembling the descriptor, with the actual module fetched and evaluated only when first requested. The manager's error cases map to a small discriminated-union error type; the single-threaded JS event loop gives the same "no real concurrency" guarantee the single-context confinement gives here, without needing an explicit isolation keyword.
- **AppKit / UIKit**: `AIPluginManager.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift`) defines `AIPluginManager`, a `@MainActor` class — this is the source for `single-context-confinement` — with no AppKit/UIKit dependency at all (only `Foundation`, `os`/`OSLog`, and `AgenticToolkitCore` for `Loggable`). A plugin bundle's `NSPrincipalClass` conforms to `AIPluginKit.AIPlugin`. "Opening the candidate as a bundle" is `Bundle(url:)`; "loading its code" is `bundle.load()` (skipped when `bundle.isLoaded` is already `true`), which is macOS's `dlopen` underneath; the file-extension and existing-path checks use `pathExtension` and `FileManager.fileExists(atPath:)`; enumeration uses `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`. `PluginLoadResult` declares no `Sendable` conformance, which is the source of `load-result-context-confined` — the Swift compiler rejects sending a `PluginLoadResult` value across a `Sendable` boundary even though its members (`[any AIPlugin]`, `[PluginLoadFailure]`) are individually `Sendable`-eligible. Two initializers exist: `init(appName:additionalSearchPaths:)` builds the three default locations (`Bundle.main.builtInPlugInsURL`, `~/.agenticplugins` via `NSHomeDirectory()`, and `~/Library/Application Support/<appName>/Plugins` via `FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)`) and appends any additional paths; `init(searchPaths:appName:)` is a test-only escape hatch that skips default-location derivation entirely. Test registration is `registerForTesting(_:)`, compiled only under `#if DEBUG`. `.aiplugin` bundle loading via `Bundle`/`NSPrincipalClass` is macOS-only (UIKit/iOS sandboxes forbid loading arbitrary on-disk executable bundles), which is why this recipe's `platforms` list `macos` and not `ios`. The empty-app-name open question traces to `InstalledContentLocation.applicationSupport(appName:subdirectory:)` in `packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift`.
- **WinUI 3**: There is no direct principal-class/`dlopen` counterpart on .NET; the nearest equivalent is `System.Reflection.Assembly.LoadFrom`/`AssemblyLoadContext` to load a plugin `.dll` on demand and `Activator.CreateInstance` (against an interface analogous to the plugin protocol) to instantiate its principal type, with `System.IO.Directory.Exists`/`Directory.EnumerateFiles` for the discovery scan and `System.Text.Json` for decoding the descriptor. Unlike a macOS bundle, `AssemblyLoadContext` *can* be unloaded (a collectible `AssemblyLoadContext`), so a WinUI 3 port has a real choice this manager does not: whether unloading a plugin should actually unload the assembly rather than only dropping the cached instance (`unload-retains-bundle` is a macOS constraint, not a requirement to carry over literally). Exposing the discovered descriptors/available templates to bound UI should go through an `ObservableCollection<T>` (or a view model implementing `INotifyPropertyChanged`) refreshed after discovery/load/unload, since WinUI 3 has no built-in reactivity for a plain `List<T>`. The manager's single-context confinement maps to confining all calls to the UI thread (`DispatcherQueue.TryEnqueue` for any call originating off it).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift` |

## Design Decisions

**Decision**: Loading a plugin caches one instance per identifier for the manager's lifetime instead of creating a fresh instance per call, even though the plugin protocol's own doc comment says "Instances are cheap and may be created per request."
**Rationale**: Caching avoids repeating the bundle-load/principal-class resolution on every request and keeps the loaded-bundles bookkeeping simple (one bundle reference per identifier); since macOS never truly unloads a loaded bundle's binary anyway (per `unload-retains-bundle`), there is no memory cost to keeping one instance alive alongside it. (Apple platform implementation.)
**Approved**: pending

**Decision**: A duplicate identifier discovered from a later search path is dropped silently, with the earlier one always winning.
**Rationale**: The source's own comment on the app-name initializer states the search-path order is deliberate — "the bundle's own copy wins, then the hand-filled dotfolder, then what an installer wrote" — so first-discovered-wins is how that stated precedence is implemented, not an oversight.
**Approved**: pending

**Decision**: Unloading a plugin removes the cached instance but leaves its bundle cached forever.
**Rationale**: The source's own comment states "the bundle remains loaded in memory (macOS does not support unloading bundles)" — since the OS will not release the mapped binary regardless, removing the bundle reference would only lose the manager's own bookkeeping for no memory benefit. (Apple platform implementation.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy And Data |

Explicit-error-handling is `partial`: loading a plugin (individually or via "load all") reports every failure as a typed error, but discovery's directory-enumeration failure is swallowed with no log and no thrown error (see the open question on `search-path-enumeration-failure`). Fault-tolerance passes because "load all plugins" isolates each plugin's failure into its failures list and keeps loading the rest. No-hardcoded-strings fails because every error message is an unlocalized English literal (see Localization). No-pii-in-logs passes because every logged value is a plugin identifier, display name, schema number, or bundle filename — never a credential or user-content value.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
