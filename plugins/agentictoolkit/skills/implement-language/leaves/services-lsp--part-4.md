<!-- leaf: implement-language/services-lsp--part-4 · source: language-services-lsp.md -->

# Language Services LSP — continued (part 4)

**Rules** (cite as `implement-language/services-lsp--part-4#<slug>`):

- `platform-i18n-layer-decide-design-choice-outside` MUST — Every string above is hardcoded English with no lookup table, ICU message, or locale parameter anywhere in these eight …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `LanguageServerConfiguration.command` | `String` | none (caller-supplied) | Absolute path to the server executable, e.g. `/usr/bin/sourcekit-lsp` |
| `LanguageServerConfiguration.languageIds` | `[String]` | none (caller-supplied) | LSP language ids this server serves, e.g. `["swift"]` |
| `LanguageServerConfiguration.arguments` | `[String]` | `[]` | Process arguments passed to `command` |
| `LanguageServerConfiguration.environment` | `[String: String]` | `[:]` | Non-secret environment overrides merged over the parent environment |
| `LanguageServerConfiguration.rootMarkers` | `[String]` | `[".git"]` | File/directory names, most specific first, that mark a workspace root; supports glob-suffix markers like `*.xcodeproj` |
| `LanguageServerConfiguration.isEnabled` | `Bool` | `true` | Whether the registry starts/keeps a session for this configuration |
| `UserSettings.languageServerConfigurations` | `[LanguageServerConfiguration]` (regular provider) | `[]` | Persisted key `languageServer.serverConfigurations` |
| `UserSettings.languageServerSecrets` | `LanguageServerSecrets` (`isSecure: true`, Keychain) | `[:]` | Persisted key `languageServer.serverSecrets`, keyed by `id.uuidString` then env-var name |
| `LanguageServerSession.Configuration.initializeBudgetSeconds` | `TimeInterval` | `30` | Wall-clock budget for the `initialize` handshake |
| `LanguageServerSession.Configuration.shutdownBudgetSeconds` | `TimeInterval` | `2` | Wall-clock budget for the graceful `shutdown`/`exit` round trip |
| `LanguageServerSession.Configuration.abandonedStartBudgetSeconds` | `TimeInterval` | `1` | Wall-clock budget teardown waits for an in-flight start to abandon |
| `LanguageServerSession.Configuration.outstandingRequestBudgetSeconds` | `TimeInterval` | `2` | Wall-clock budget teardown waits for outstanding requests to finish |
| `LanguageServerSession.Configuration.exitStatusBudgetSeconds` | `TimeInterval` | `1` | Wall-clock budget teardown waits for the process exit status |
| `LanguageServerRegistry.builtInConfigurations` | static `[LanguageServerConfiguration]` | one entry (SourceKit-LSP, fixed UUID `1CE31A0E-0000-4000-A000-5357494654FF`) | Ships regardless of user configuration; overridden per-language by a matching user configuration |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `LanguageServerSessionError.serverExited` | The language server exited with status {status}. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |
| `LanguageServerSessionError.sessionHasBeenStopped` | The language server session has been stopped. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |
| `LanguageServerSessionError.notRunning` | The language server is not running. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in these eight files — this is a plain fact
about the source, not a gap: these are `LocalizedError` descriptions
surfaced in developer-facing logs/failure states, and a port to a platform
with an i18n layer MUST decide, as a design choice outside this contract,
whether and how to route them through it.

## Feature Flags

- **per-server-enablement**: `LanguageServerConfiguration.isEnabled` is a
  genuine per-server, user-controlled flag: the registry starts a session
  for a configuration only while it is `true`, and tears it down the moment
  it flips to `false` (`LanguageServerRegistry.swift`).

## Privacy

- **Data collected**: Per-server secret environment values (e.g. API keys a
  language server needs), stored under `UserSettings.languageServerSecrets`,
  keyed by `configuration.id.uuidString` then environment-variable name
  (secrets-keyed-by-id-then-env-var). Non-secret configuration (command,
  arguments, non-secret environment, root markers) is not sensitive and is
  stored via the regular settings provider.
- **Storage**: Secrets are routed through `isSecure: true`, i.e. the
  Keychain, never the plain settings file
  (secrets-stored-in-keychain-not-plain-settings). Diagnostics held by
  `DiagnosticStore` are in-memory only, keyed by document URI, and are never
  persisted to disk by this component.
- **Transmission**: A server's secret environment values are merged into
  its subprocess environment only at session start; this component never
  transmits them over the JSON-RPC channel itself — only the spawned
  process sees them, as environment variables
  (secrets-merged-into-environment-only-at-session-start).
- **Retention**: Diagnostics for a document are retained until the document
  is closed by its last editor (document-diagnostics-pruned-on-close) or
  until `DiagnosticStore.clear(uri:)`/`shutdown()` is called; secrets persist
  in the Keychain until the user removes the configuration or changes the
  secret value.

## Platform Notes

- **SwiftUI/AppKit/UIKit**: This is the reference implementation.
  `Foundation.Process` (via `SubprocessChannel`) launches the server;
  `JSONRPC`/`LanguageServerProtocol`/`LanguageClient` frame and type the
  protocol; Swift `actor`s (`LanguageServerSession`, `DocumentSyncPipeline`)
  and `@MainActor` `ObservableObject`s (`DiagnosticStore`,
  `LanguageServerRegistry`, `LanguageServerDocumentSync`) provide isolation;
  `AsyncStream` carries `publishedDiagnostics`/`stateChanges`; the Keychain
  (via `isSecure: true` settings) stores secrets.
- **Compose/Android**: `ProcessBuilder`/`Runtime.exec` replaces
  `Foundation.Process`; a hand-rolled or third-party JSON-RPC/LSP client
  library replaces `JSONRPC`/`LanguageServerProtocol`; Kotlin coroutines with
  a `Mutex`-guarded class replace an `actor`; `StateFlow`/`SharedFlow`
  replace `AsyncStream`; the Android Keystore (via `EncryptedSharedPreferences`
  or Jetpack Security) replaces the Keychain for secrets.
- **React/Web**: There is no direct browser analog for spawning a local
  subprocess; a web-hosted port would need a companion native/host process
  (e.g. a desktop shell's IPC bridge) to launch the language server, with
  `postMessage`/WebSocket framing standing in for the JSON-RPC channel;
  secrets would need to live in the host's secure storage, never in web
  `localStorage`.
- **WinUI 3**: `System.Diagnostics.Process` replaces `Foundation.Process`
  for spawning the server; `System.IO.Pipes` or the process's redirected
  standard streams carry the JSON-RPC frames, with `System.Text.Json`
  replacing `Foundation.JSONDecoder`/`JSONEncoder` for every LSP message.
  `Task`/`async`-`await` with a `SemaphoreSlim`-guarded class is the
  idiomatic equivalent of an `actor` for `LanguageServerSession` and
  `DocumentSyncPipeline`; an `ObservableCollection`/`INotifyPropertyChanged`-backed
  class, or a C# `event`, replaces the `@Published` properties on
  `LanguageServerRegistry`/`DiagnosticStore`; a `System.Threading.Channels.Channel<T>`
  replaces `AsyncStream` for `publishedDiagnostics`/`stateChanges`.
  `Windows.Security.Credentials.PasswordVault` replaces the Keychain for
  routing per-server secret environment values.

## Design Decisions

**Decision**: `PublishDiagnosticsParams` with a `nil` or stale `version` is
never dropped by `DiagnosticStore` — the store always keeps the most
recently published diagnostics for a URI regardless of version.
**Rationale**: Many language servers omit `version` on published
diagnostics or publish out of band with the document's own edit stream;
treating an unversioned or older-versioned publish as untrustworthy would
mean silently losing diagnostics for those servers rather than showing
something. Overwriting on send order, not version order, keeps the store
simple and matches what LSP servers actually send in practice.
**Approved**: pending

**Decision**: `DocumentSyncPipeline.forward(_:sync:)` gates `.changed` and
`.closed` events on `openURIs.contains(uri)` but deliberately does not gate
`.saved` the same way.
**Rationale**: The source's own comment asks that this asymmetry not be
"fixed" — a `.saved` event for a document the pipeline does not believe is
open is forwarded anyway, because some server integrations rely on
receiving `didSave` even across an open-tracking edge case that would
otherwise suppress it; unifying the gating would silently drop those saves.
**Approved**: pending

**Decision**: A user configuration for a language id replaces the built-in
configuration for that id wholesale in `effectiveConfigurations`, rather
than merging fields (e.g. keeping the built-in's `rootMarkers` while taking
the user's `command`).
**Rationale**: Partial merging would require a field-by-field precedence
rule that has no natural default (should a user's `arguments` merge with or
replace the built-in's?); replacing wholesale is unambiguous and matches
the mental model of "I am supplying my own server for this language,"
consistent with how `MCPServerConfiguration` in this codebase makes the
same choice.
**Approved**: pending

**Decision**: `LanguageServerSession.stop()` preserves a `.failed` state
rather than overwriting it with `.stopped`, and skips the graceful-shutdown
budget entirely when the server has already died on its own.
**Rationale**: Once a server has died, there is nothing left to negotiate a
graceful `shutdown`/`exit` with, so waiting out that budget would only delay
`stop()` for no benefit; and reporting `.stopped` over a genuine `.failed`
would hide from callers (and from `sessionStates` observers) that the
process died unexpectedly rather than being asked to stop.
**Approved**: pending
