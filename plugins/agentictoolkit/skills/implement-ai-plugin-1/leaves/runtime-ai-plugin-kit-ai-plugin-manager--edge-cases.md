<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager.md -->

# AI Plugin Manager

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager--edge-cases#<slug>`):

- `appname-test-discoverplugins-leave-descriptors-availabletemplates-empty` MUST — Empty searchPaths (e.g. init(searchPaths: [], appName: "Test")): discoverPlugins() MUST leave descriptors and …
- `does-exist-disk-skipped-silently-existing-search` MUST — A searchPaths entry that does not exist on disk: MUST be skipped silently by existing-search-paths-only; no log, no …
- `nil-logged-skipped-not-throw` MUST — A directory entry with the .aiplugin extension that is not a valid bundle: caught by unreadable-candidate-skip …
- `skip-logged-skipped-not-throw-also-how-pre` MUST — descriptor.json absent, unreadable, or not valid JSON for the declared AIPluginDescriptor shape: caught by …
- `filter-logged-skipped-not-throw` MUST — schemaVersion below 2 or above AIPluginDescriptor.currentSchemaVersion: caught by schema-version-filter, logged and …
- `identifier-never-discovered-throw-aipluginerror-notfound-per` MUST — loadPlugin(identifier:) for an identifier never discovered: MUST throw AIPluginError.notFound, per …

## Edge Cases

- Empty `searchPaths` (e.g. `init(searchPaths: [], appName: "Test")`): `discoverPlugins()` MUST leave `descriptors` and `availableTemplates` empty; no error is raised.
- A `searchPaths` entry that does not exist on disk: MUST be skipped silently by `existing-search-paths-only`; no log, no error.
- A `searchPaths` entry that exists but cannot be enumerated (permissions failure, or a non-directory file at that path): silently skipped with no log — see the open question on search-path-enumeration-failure.
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
