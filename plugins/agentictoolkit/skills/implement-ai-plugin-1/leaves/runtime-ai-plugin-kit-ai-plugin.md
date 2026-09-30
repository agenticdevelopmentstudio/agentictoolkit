<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin#<slug>`):

- `zero-argument-initialization` MUST
- `cheap-instantiation` SHOULD
- `request-description` MUST
- `insufficient-context-error` MUST
- `fresh-decoder-per-response` MUST
- `validation-request-default` MUST
- `validation-request-cannot-validate` MUST
- `error-message-default` MUST
- `transport-non-ownership` MUST
- `ui-non-ownership` MUST
- `secret-non-ownership` MUST
- `metadata-non-ownership` MUST
- `sendable-conformance` MUST
- `concurrent-invocation-safety` MUST
- `decoder-isolation` MUST
- `foundation-only-dependency` MUST
- `shared-framework-image` MUST
- `data-handled` MAY — buildRequest(_:) receives context.config, and buildValidationRequest(config:) receives config directly, either of which …
- `transmission` MAY — A conforming type never transmits data itself; it only describes a request (the returned AIRequestSpec's headers or …
- `winui-3` MUST — Model the contract as a C# interface on the .NET / Windows App SDK: public interface IAiPlugin { AiRequestSpec …

# AIPlugin

## Overview

`AIPlugin` is the Foundation-only Swift protocol every AI provider plugin implements. A plugin is the `NSPrincipalClass` of a macOS `.aiplugin` bundle: given one chat turn's `AIChatContext`, it describes the HTTP or subprocess request for that turn as an `AIRequestSpec`, and it creates a fresh `AIStreamDecoder` that turns the provider's raw response bytes into `AIStreamEvent`s. A plugin never performs networking, spawns a process, presents any UI, or stores a secret itself — it only describes and decodes; the host performs the transport, builds the settings UI from the bundle's `descriptor.json` schema, and owns secret storage.

## Behavioral Requirements

- **zero-argument-initialization**: A conforming type MUST provide a synchronous, non-throwing, zero-argument initializer (`init()`), since the host constructs plugin instances by calling `.init()` on a metatype obtained by casting a bundle's principal class (`pluginClass.init()` in `AIPluginManager.loadPlugin(identifier:)`).
- **cheap-instantiation**: A conforming type's `init()` SHOULD be inexpensive, because the protocol documents instances as cheap and states a caller MAY create a new instance per request (`AIPlugin.swift`: "Create the plugin. Instances are cheap and may be created per request.").
- **request-description**: `buildRequest(_:)` MUST synchronously return an `AIRequestSpec` that fully describes the HTTP or subprocess request for one chat turn, derived from the given `AIChatContext`.
- **insufficient-context-error**: `buildRequest(_:)` MUST throw an `Error` instead of returning a value when the given `AIChatContext` does not contain what the plugin needs to build a request (e.g. a required `config` value is missing), per its doc comment: "Throws if the context is insufficient (e.g. a required config value is missing)."
- **fresh-decoder-per-response**: `makeDecoder()` MUST return a newly created `AIStreamDecoder` instance on every call, and that instance MUST own whatever mutable state it needs to parse exactly one response stream, per its doc comment: "Create a fresh decoder for one response stream. The decoder owns any per-response parsing state."
- **validation-request-default**: `buildValidationRequest(config:)` MUST return `nil` for a conforming type that does not override it, via the protocol extension's default implementation.
- **validation-request-cannot-validate**: An overriding `buildValidationRequest(config:)` MUST return `nil` when it has no way to validate the given `AIPluginConfig`, per its doc comment: "Return nil if the plugin cannot validate."
- **error-message-default**: `describeError(status:body:)` MUST return `nil` for a conforming type that does not override it, via the protocol extension's default implementation, signaling the host SHOULD fall back to a generic "HTTP `<status>`" message.
- **transport-non-ownership**: A conforming type MUST NOT perform networking or spawn a subprocess itself; `buildRequest(_:)` and `buildValidationRequest(config:)` MUST only describe a request, never execute one — the doc comment states the plugin "performs no networking" and "the host owns the transport."
- **ui-non-ownership**: A conforming type MUST NOT present any user interface; per the doc comment, the host builds the settings UI "from the bundle's `descriptor.json` schema," and the plugin "ships no UI."
- **secret-non-ownership**: A conforming type MUST NOT implement its own secret storage; per the doc comment, the host "owns... secret storage," and any credential the plugin needs arrives already resolved inside `context.config` / `config`.
- **metadata-non-ownership**: A conforming type MUST NOT expose identity or presentation metadata (identifier, display name, supported models, capabilities, settings schema) through this protocol; per the doc comment, "All identity and presentation metadata... live as data in the bundle, not here, so the host can list and configure a plugin without loading its binary."
- **sendable-conformance**: The protocol MUST require every conforming type to be `Sendable` and a class (`public protocol AIPlugin: AnyObject, Sendable`), so a single plugin instance MAY be captured and invoked from any concurrency domain — per the doc comment, "The plugin itself is `Sendable`, so capturing it is safe" (quoted from `PluginTransport.swift`, the module that captures a plugin inside a `Task`).
- **concurrent-invocation-safety**: Because conformance requires `Sendable`, a conforming type MUST make any internal mutable state safe for concurrent invocation of `buildRequest(_:)`, `buildValidationRequest(config:)`, and `describeError(status:body:)` from multiple tasks on one shared instance; Swift's strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`) enforces this for ordinary stored state, and the author assumes the obligation when opting out with `@unchecked Sendable` (as `OpenAIPlugin` does).
- **decoder-isolation**: The `AIStreamDecoder` a `makeDecoder()` call returns MUST be used to parse a single response only and MUST NOT be shared across concurrent responses, since `AIStreamDecoder` declares no `Sendable` conformance and is documented to hold per-response parsing state.
- **foundation-only-dependency**: The framework declaring this protocol MUST depend only on Foundation, per the doc comment: "`AIPluginKit` is a Foundation-only dynamic framework."
- **shared-framework-image**: A plugin bundle MUST link this protocol's framework without embedding a copy of it, so a freshly loaded principal class resolves against the host's one loaded image and can be cast to `AIPlugin`, per the doc comment: "each plugin links [`AIPluginKit`] *without* embedding, so a plugin resolves to the host's one loaded image at `dlopen` time."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` (parameter to `buildRequest(_:)`) | `AIChatContext` | none — required | Conversation messages, model, token budget, tool specs, and the resolved `AIPluginConfig` the caller supplies for one chat turn. |
| `config` (parameter to `buildValidationRequest(config:)`) | `AIPluginConfig` | none — required | Resolved settings plus any injected secret (e.g. `apiKey`) the host wants the plugin to check for validity. |
| `status`, `body` (parameters to `describeError(status:body:)`) | `Int`, `Data` | none — required | The HTTP-style status code and raw response body from a chat request or validation request that failed. |

This protocol defines no environment variable or settings key of its own; every value it reads arrives as a parameter already resolved by the host from the plugin's bundled `descriptor.json` schema (see the `AIPluginDescriptor` and `AIPluginConfig` sibling components).

## Privacy

- **Data handled**: `buildRequest(_:)` receives `context.config`, and `buildValidationRequest(config:)` receives `config` directly, either of which MAY carry a credential such as an API key — per `AIChatContext.swift`'s own doc comment on `AIPluginConfig`: "the host reads these from the plugin's settings schema and injects secrets (API keys) from the Keychain just before calling `buildRequest`; the plugin never touches storage itself."
- **Storage**: `AIPlugin.swift` defines no storage of its own. Secret persistence (e.g. Keychain access) is the host's responsibility, implemented by the sibling `SecretStoring` component, not by any conforming `AIPlugin` type.
- **Transmission**: A conforming type never transmits data itself; it only describes a request (the returned `AIRequestSpec`'s headers or body MAY embed a credential, as `OpenAIPlugin.swift` does with `"Authorization": "Bearer \(apiKey)"`) for the host's transport (`PluginTransport`) to send.
- **Violation handling**: Out of scope for this protocol — detecting or reacting to a security violation (an invalid key, a revoked credential) is delegated entirely to the host's secret-storage and transport layers; `AIPlugin.swift` neither validates nor reports on credential legitimacy beyond the optional `buildValidationRequest(config:)` hook.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIPlugin.swift`, alongside `AIChatContext.swift`, `AIRequestSpec.swift`, and `AIStreamEvent.swift` (its parameter and return types). Nothing here is SwiftUI-specific — a SwiftUI-based host consumes an `AIPlugin` exactly as an AppKit one does, through `AIPluginManager`/`PluginTransport`.
- **Compose**: Android has no analogue of `dlopen`-loading an arbitrary `.aiplugin` bundle's principal class at runtime. A Kotlin port would define the same contract as a plain `interface AIPlugin` and resolve implementations from a build-time registry or a `ServiceLoader`-style mechanism instead of loading foreign bundles from disk.
- **React/Web**: Model the contract as a plain TypeScript interface (`buildRequest`, `makeDecoder`, `buildValidationRequest`, `describeError`) with plugins as ES modules loaded via dynamic `import()` instead of `dlopen`. Use `fetch`/`ReadableStream` in place of `URLSession`/subprocess transport, and return `Promise`s from methods that are synchronous-but-throwing in Swift, since browser I/O is inherently asynchronous.
- **AppKit / UIKit**: Identical to the SwiftUI note — this protocol is UI-framework-agnostic; only the host application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model the contract as a C# interface on the .NET / Windows App SDK: `public interface IAiPlugin { AiRequestSpec BuildRequest(AiChatContext context); IAiStreamDecoder MakeDecoder(); AiRequestSpec? BuildValidationRequest(AiPluginConfig config); string? DescribeError(int status, byte[] body); }`, with a public parameterless constructor standing in for `init()`. Use `HttpClient` for the HTTP transport case `AIRequestSpec.Transport.http` describes and `System.Diagnostics.Process` for the `.command` case that `PluginTransport` drives. Represent `AIStreamEvent` as a discriminated record and expose decoding via `IAsyncEnumerable<AiStreamEvent>` rather than Swift's synchronous `Consume(byte[]) -> IReadOnlyList<AiStreamEvent>`, since .NET streaming favors `async`/`await` over buffering callbacks. `Windows.Storage`/Credential Locker is the analogue of the host's Keychain use — owned by the host, never by the plugin, matching the source. Dynamic loading of third-party plugin assemblies maps to `AssemblyLoadContext` rather than `dlopen` + `NSPrincipalClass`; because .NET assemblies are ordinarily loaded in full rather than resolved against one shared image, a WinUI 3 host MUST decide how it prevents duplicate type identity across plugin assemblies that each reference the interface assembly — the direct analogue of this source's "link, don't embed" rule.

