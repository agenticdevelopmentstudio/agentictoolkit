<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat--part-3 · source: ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat.md -->

# DaemonAIChat — continued (part 3)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat--part-3#<slug>`):

- `cache-main-actor-isolated` MUST
- `cache-reuse-by-search-paths` MUST
- `cache-unknown-identifier` MUST
- `cache-instance-reuse` MUST
- `cli-foreign-error-passthrough` MUST
- `transmission` MAY — resolved values, including a secret, are packaged into AIPluginConfig.values → AIChatContext.config → …

- **cache-main-actor-isolated**: `LivePluginCache` MUST be a `@MainActor`-isolated private enum whose mutable static state (`manager`, `managerPaths`, `loaded`) is safe to mutate without a separate lock, because the main actor serializes all access to it.
- **cache-reuse-by-search-paths**: `LivePluginCache.load` MUST reuse the cached `AIPluginManager` when the given `searchPaths` equals the previously cached `managerPaths`; otherwise it MUST construct a new `AIPluginManager`, call `discoverPlugins()`, replace the cached manager and paths, and clear every previously loaded plugin instance.
- **cache-unknown-identifier**: `LivePluginCache.load` MUST throw `ChatError.providerError("AI plugin not installed: \(identifier)")` when `mgr.descriptor(for: identifier)` is `nil`.
- **cache-instance-reuse**: `LivePluginCache.load` MUST return an already-cached plugin instance for `identifier` without calling `mgr.loadPlugin(identifier:)` again; otherwise it MUST call `loadPlugin`, cache the result, and return it.
- **cli-foreign-error-passthrough**: An error other than `ClaudeCLI.CLIError` thrown by an injected `cliRunner` MUST propagate out of `completeViaCLI` and `complete` unchanged, not wrapped as a `ChatError`; unlike `completeViaPlugin`, whose generic `catch` clauses wrap every failure as `ChatError.providerError`, the CLI path catches only `ClaudeCLI.CLIError`. `CLIRunner`'s doc comment names `ClaudeCLI.CLIError` as the only error a runner throws.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `systemPrompt` | `String` | none — required | System prompt text for this one-shot turn |
| `userPrompt` | `String` | none — required | The single user message's text |
| `maxTokens` | `Int` | none — required | Forwarded unvalidated into `AIChatContext.maxTokens` on the plugin path; unused on the CLI path |
| `cliModel` | `String` | `"haiku"` | Model name for the CLI path only; an empty string is also treated as `"haiku"` by `completeViaCLI` |
| `timeout` | `TimeInterval` | `defaultTimeout` (`60`) | Governs only `completeViaCLI`'s subprocess wait; ignored on the plugin path |
| `settings` | `ProviderSettingsReader` (`@escaping (String) -> String?`) | none — required | Reads the host's synced provider-registry values, keyed by `AIProviderConfigKeys` |
| `runtime` | `PluginRuntime` | `.live` | Injectable plugin-load/run seam |
| `cliRunner` | `CLIRunner` | `liveCLIRunner` | Injectable CLI-subprocess seam |
| `secretStore` | `any SecretStoring` | `KeychainSecretStore()` | Source of a template's secret field values |
| `inferenceGuard` | `LocalInferenceGuard?` | `.shared` | The local-inference RAM guard; `nil` disables both checkpoints |

`AIProviderConfigKeys`-namespaced settings keys `complete` (via `DaemonProviderResolver` and `completeViaPlugin`) reads through `settings`: the configurations registry, the selected-configuration id, a configuration's stored model, its non-secret fields ledger, and each ledger field's stored value.

## Localization

No message in this file is externalized through a localization key (no `NSLocalizedString`/`String(localized:)`). Every user-facing string this file itself authors is a hardcoded English literal:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Claude CLI not found (install Claude Code or check PATH)` | `ChatError.claudeNotFound.errorDescription` |
| (none — hardcoded) | `Empty reply from the model` | `ChatError.emptyReply.errorDescription` |
| (none — hardcoded) | `Failed to launch claude: <message>` | `completeViaCLI`'s `.launchFailed` mapping |
| (none — hardcoded) | `claude -p failed: <stderr or "exit <code>", truncated to 200 chars>` | `completeViaCLI`'s `.nonZeroExit` mapping |
| (none — hardcoded) | `Failed to load AI plugin '<id>': <underlying message>` | `completeViaPlugin`'s plugin-load error wrap |
| (none — hardcoded) | `Plugin could not build the request: <underlying message>` | `completeViaPlugin`'s `buildRequest` error wrap |
| (none — hardcoded) | `AI plugin not installed: <identifier>` | `LivePluginCache.load`'s unknown-identifier error |

`ChatError.providerError`'s remaining call site (the stream-consumption wrap) carries a plugin/transport-supplied `error.localizedDescription` through verbatim rather than authoring new text — that upstream string's own localization is out of this file's control.

## Privacy

- **Data handled**: `completeViaPlugin` reads the host's non-secret settings ledger and, for the configuration's own resolved template, its declared secret fields (e.g. `apiKey`) via the injected `secretStore`. `DaemonAIChat.swift` does not decide what is sensitive — it forwards exactly what the ledger and secret store report, scoped by `AIProviderConfigKeys` and `secret-scope-by-template`.
- **Storage**: `DaemonAIChat.swift` stores nothing itself. It reads through `settings` (a plain key/value reader) and `secretStore.get(forKey:)` (Keychain-backed by default, via `KeychainSecretStore`) and writes nothing back; the prompt text and the accumulated reply exist only as local variables for the duration of one `complete` call, with no persistence of either.
- **Transmission**: resolved values, including a secret, are packaged into `AIPluginConfig.values` → `AIChatContext.config` → `plugin.buildRequest(_:)`, which MAY embed a secret (e.g. as an `Authorization` header) into the returned `AIRequestSpec`; the actual wire transmission happens inside `PluginTransport.run`, not in this file. On the CLI path, `systemPrompt`/`userPrompt` are passed to `ClaudeCLI.run`, which spawns a local subprocess — no network call originates directly in `DaemonAIChat.swift` for that path, though `claude -p` may itself reach a remote API.
- **Retention**: `DaemonAIChat.swift` defines no retention, expiry, rotation, or revocation policy for any credential; whatever `secretStore.get(forKey:)` returns reflects the caller-supplied store's own retention. This file has no violation-detection logic of its own — a plugin-level authentication failure (e.g. an HTTP 401) surfaces only generically, as a `ChatError.providerError` carrying whatever message the plugin's `describeError` or `PluginTransport`'s own generic HTTP-status message supplies, with no distinct handling for a credential problem versus any other provider error.

## Platform Notes

- **SwiftUI**: The source, `packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift`, has no view-layer dependency at all — `complete` is a plain `static func` a SwiftUI (or any other) host calls from a `Task`, typically wrapping the call in a view model that publishes the in-flight/succeeded/failed state, since `DaemonAIChat` itself is not observable and returns only a final `String` (no partial-progress callback).
- **Compose**: model the two-path dispatch as a `suspend fun complete(...)` in a plain Kotlin object, with `PluginRuntime` and `CLIRunner` as constructor-injected function types (or a small interface each) for the same hermetic-testing seam. Android has no `dlopen`/`NSPrincipalClass` equivalent for the plugin path itself (see the `ai-plugin-manager` recipe's Compose note); the guard's actor-based mutual exclusion maps to a `Mutex` (kotlinx.coroutines) guarding the local-inference critical section, and the FIFO recheck-after-acquire pattern (`guard-recheck-in-lock`) carries over directly since `Mutex.withLock` also has to reconsider state that may have changed while suspended waiting for the lock.
- **React/Web**: model `complete` as an `async function` returning `Promise<string>`, with `runtime`/`cliRunner`/`settings`/`secretStore` as injected parameters or closures for the same test seams. There is no local subprocess (`claude -p`) equivalent in a browser; a web port's "zero-config default" would more plausibly be a server-side proxy endpoint than an in-process CLI fallback. The local-inference guard's process-wide mutual exclusion has no direct browser analogue (there is one JS execution context per tab); a multi-tab web host would need a `BroadcastChannel`- or server-mediated equivalent of `LocalInferenceGuard.runExclusive` to serialize local-model calls across tabs.
- **AppKit / UIKit**: same note as SwiftUI — `DaemonAIChat.swift` has no AppKit/UIKit dependency; only the host embedding it differs. The `.aiplugin` bundle-loading path this file drives is macOS-only (see the `ai-plugin-manager` and `ai-plugin` recipes), which is why this recipe's `platforms` list `macos` and not `ios`; an iOS host could still use the CLI-independent plugin path if a plugin bundle-loading mechanism were ported, but never the `claude -p` subprocess fallback, since iOS sandboxes forbid spawning arbitrary subprocesses.
- **WinUI 3**: model `complete` as an `async Task<string>` on a static class, with `PluginRuntime` (a record of two delegates) and `CLIRunner` as injected dependencies. `ClaudeCLI`'s subprocess fallback maps to `System.Diagnostics.Process`; `AssemblyLoadContext` is the nearest analogue for the plugin-loading half of the plugin path (see the `ai-plugin-manager` recipe's WinUI 3 note for the caching tradeoff this implies). The two-checkpoint local-inference guard maps to a `SemaphoreSlim`(1) guarding the critical section, with the same "re-check pressure after acquiring" pattern; `Windows.Storage`/Credential Locker stands in for the Keychain-backed `SecretStoring` this file reads through. Because `System.Diagnostics.Process` and `HttpClient` calls are both naturally `async`/awaitable on .NET, a WinUI 3 port has no equivalent of Swift's `AsyncThrowingStream`-based event consumption for `PluginRuntime.run`; `IAsyncEnumerable<AiStreamEvent>` is the direct substitute, with the `.end`/`.toolUse`/`.textDelta` switch in `completeViaPlugin` carrying over as a `switch` over an enum/discriminated union inside an `await foreach`.

