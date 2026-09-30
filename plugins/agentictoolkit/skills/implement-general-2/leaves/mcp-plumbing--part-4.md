<!-- leaf: implement-general-2/mcp-plumbing--part-4 · source: mcp-plumbing.md -->

# MCP Plumbing — continued (part 4)

**Rules** (cite as `implement-general-2/mcp-plumbing--part-4#<slug>`):

- `data-handled` MAY — MCPServerConfiguration's stdio environment and MCPServerSecrets' per-server secret dictionary MAY each carry …
- `storage` MUST — Non-secret server descriptions are stored by SettingsStore under "mcp.serverConfigurations" in the regular settings …

## Localization

`MCPClientError` and `MCPServerRegistry` produce hardcoded, unlocalized English strings with no string-catalog key, and `HostMCPServer`'s tool descriptions and tool-call bodies are likewise hardcoded English:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The MCP server was disabled or removed before its connection finished starting; nothing was launched." | `MCPClientError.clientHasBeenDisconnected.errorDescription` |
| (none — literal, no catalog key) | "Failed to connect MCP server %@: %@" (interpolated with `configuration.name` and `error.localizedDescription`) | `MCPServerRegistry.reconcile`'s failure log line |
| (none — literal, no catalog key) | "Return the host application's name, version, and configured AI plugins." | `host_app_info`'s tool `description` |
| (none — literal, no catalog key) | "Open a new AI chat window in the host application." | `host_open_chat_window`'s tool `description` |
| (none — literal, no catalog key) | "Host: %@\nVersion: %@\nPlugins: %@" | `host_app_info`'s success body |
| (none — literal, no catalog key) | "Opened a new chat window." | `host_open_chat_window`'s success body |
| (none — literal, no catalog key) | "Unknown tool: %@" | `CallTool`'s default-case body for an unrecognized tool name |

## Privacy

- **Data handled**: `MCPServerConfiguration`'s stdio `environment` and `MCPServerSecrets`' per-server secret dictionary MAY each carry credentials (e.g. `"GITHUB_TOKEN"`) that a user supplies when configuring a server; `MCPClient` forwards the merged environment to the spawned subprocess (`secrets-override-environment`) or, for an HTTP server, whatever `MCPServerConfiguration.Transport.http`'s `endpoint` and the SDK's `HTTPClientTransport` send, with no inspection of its own beyond the merge itself.
- **Storage**: Non-secret server descriptions are stored by `SettingsStore` under `"mcp.serverConfigurations"` in the regular settings provider; secret environment values are stored under `"mcp.serverSecrets"`, routed to the secure provider (Keychain in production) via `isSecure: true`, per `secrets-setting-routing` — secrets MUST NOT reach the regular settings file.
- **Transmission**: For a `.stdio` server, secrets are transmitted only as environment variables to a locally spawned child process, never over the network by this component itself; for a `.http` server, whatever headers or body the SDK's `HTTPClientTransport` sends travel to `endpoint` over HTTPS or HTTP as that URL specifies. `MCPServerRegistry`'s failure log (`registry-connect-failure-is-logged-not-thrown`) interpolates only `configuration.name` and `error.localizedDescription`, never a secret or environment value.
- **Retention**: Secrets persist in the secure provider until the user edits or removes the corresponding server configuration; the source defines no expiry, rotation, or automatic revocation for a stored secret.
- **Token lifecycle**: the component implements no expiry, rotation, or revocation for a stored server secret; a secret stays valid in the secure provider until the user edits or removes the server configuration.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/MCP/*.swift` (built into the `AgenticToolkitCore` framework target, macOS-only) and `packages/apple/AgenticToolkit/macOS/Features/MCP/HostMCPServer.swift` (built into the `AgenticToolkitMacOS` target). `MCPServerRegistry`'s `@Published clients` and `MCPClient`'s `state`/`cachedTools` are consumed reactively by SwiftUI views (e.g. the sibling `MCPChipsBarView` recipe) via `ObservableObject`, but nothing in these six files imports `SwiftUI` itself — the layer is UI-framework-agnostic.
- **Compose**: Model `MCPClient` as a class wrapping a `Mutex`-guarded `MutableStateFlow<MCPClientState>` and `MutableStateFlow<List<Tool>>` in place of the actor's isolated `state`/`cachedTools`, with `connect`/`disconnect`/`refreshTools`/`callTool` as `suspend` functions; reproduce `teardown-sequence`'s ordering with `withTimeoutOrNull(1_000L) { connectJob?.join() }` in place of the wall-clock budget, and `connectJob?.cancel()` in place of `connectTask?.cancel()`. Model `MCPServerRegistry` as a class exposing `StateFlow<Map<UUID, MCPClientProtocol>>`, driven by `combine` over two settings `Flow`s in place of Combine's `combineLatest`. Model `SubprocessTransport` with `ProcessBuilder`, reading stdout line-by-line on a background dispatcher to reproduce `.newlineDelimited` framing, and filtering blank lines the same way `subprocess-blank-line-filtering` does. Route secrets through Android's `EncryptedSharedPreferences` in place of Keychain.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive and no OS keychain), model `MCPClient` as an `EventEmitter`-based class or an async class exposing `state`/`cachedTools` getters, with `connect`/`disconnect` as `async` methods; reproduce `teardown-sequence`'s bounded wait with `Promise.race([connectPromise, delay(1000)])` in place of the wall-clock budget. Model `MCPServerRegistry` as a class holding a `Map<string, MCPClientProtocol>` and re-running its reconcile logic on every settings-store change event. Model `SubprocessTransport` with `child_process.spawn`, reading `.stdout` through `readline.createInterface` (or manual `\n`-splitting) for `.newlineDelimited` framing, and filtering blank lines per `subprocess-blank-line-filtering`; route secrets through an OS-keychain wrapper (e.g. `keytar`) in place of Keychain, and support only the `.http` transport in an Electron renderer sandbox that cannot spawn arbitrary executables.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AgenticToolkitCore`/`AgenticToolkitMacOS` differs, never this contract.
- **WinUI 3**: Model the `.http` path of `MCPClient`/`SubprocessTransport` with `System.Net.Http.HttpClient`, and the `.stdio` path with `System.Diagnostics.Process`/`ProcessStartInfo` (`RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` all `true`), reading stdout via a `StreamReader.ReadLineAsync()` loop to reproduce `.newlineDelimited` framing and `subprocess-blank-line-filtering`'s blank-line skip. Reproduce `teardown-sequence`'s bounded wait for an abandoned connect with a `CancellationTokenSource` whose `CancelAfter(TimeSpan.FromSeconds(1))` gates a `Task.WhenAny(connectTask, Task.Delay(Timeout.Infinite, token))`, in place of `withWallClockBudget`. Represent `MCPServerRegistry.clients` as an `ObservableCollection<KeyValuePair<Guid, IMcpClient>>` or a `Dictionary` behind a type implementing `INotifyPropertyChanged`/`INotifyCollectionChanged`, raised from the `reconcile` equivalent the same way `@Published` raises `objectWillChange`. Store `mcp.serverConfigurations` via `Windows.Storage.ApplicationData.LocalSettings` (serialized with `System.Text.Json`) and route `mcp.serverSecrets` through `Windows.Security.Credentials.PasswordVault` in place of Keychain, since `Windows.Storage`'s settings containers are not encrypted at rest the way `mcp.serverSecrets` requires.

## Design Decisions

**Decision**: `teardown()` disconnects the transport and the underlying `MCP.Client` twice each (steps 2+5 and 3+6), rather than once.
**Rationale**: Per `MCPClient.swift`'s own doc comment on `teardown()`, the first pair (steps 2-3) closes the window `MCP.Client.send`'s unstructured registration opens for a request that is mid-flight when a disconnect lands, while the second pair (steps 5-6) reaps a connect that resumes *after* steps 1-3 have already run out of things to catch — a connect suspended between publishing `self.transport` and calling `MCP.Client.connect(transport:)`. Both `SubprocessTransport.disconnect()` and `MCP.Client.disconnect()` are documented no-ops when already idle, so the repeated calls cost nothing in every ordering except the one each pair exists for.
**Approved**: pending

**Decision**: `teardown()`'s wait for an abandoned `connectTask` (step 4) is bounded to `abandonedConnectBudgetSeconds` (1.0 second) and both the operation's own error and a `WallClockBudgetExceeded` are discarded with `try?`.
**Rationale**: Per the source's own measurements cited in its doc comment, an unbounded wait here never returns for a connect wedged on the MCP SDK's bare `initialize` continuation, because nothing but step 6's `client.disconnect()` can resume it — and step 6 only runs after this wait ends. A bounded wait trades a fixed, small delay (measured at roughly 1.01-1.03 seconds end to end) for guaranteeing steps 5 and 6 run; propagating either the operation's error or the budget's own timeout error would serve no caller, since `teardown()`'s job is releasing resources, not reporting the abandoned connect's outcome.
**Approved**: pending

**Decision**: `SubprocessTransport` tracks `idle`/`connecting`/`connected` as a three-case enum rather than a `Bool`.
**Rationale**: Per the type's own doc comment, a `Bool` set only after `connect()`'s suspension at `channel.launch()` would let a `disconnect()` landing in that window observe "not yet connected" and become a no-op while a live child exists — stranding it for the life of the app. The `connecting` case exists precisely to make `disconnect()` treat that window the same as a fully connected one.
**Approved**: pending

**Decision**: `HostMCPServer` is self-contained, with no integration into `MCPServerRegistry` and no new case added to `MCPServerConfiguration.Transport` for an in-process server.
**Rationale**: Per the type's own doc comment, this keeps the sample from expanding the `Transport` enum with an in-process variant; a host application that wants `HostMCPServer`'s tools available to its own chat surface is expected to build an `MCP.Client` directly against `clientTransport` and wire that in wherever it already routes tool calls, rather than this component doing so on the host's behalf.
**Approved**: pending
