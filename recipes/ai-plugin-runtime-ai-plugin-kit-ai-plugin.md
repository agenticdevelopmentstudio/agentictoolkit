---
id: 47eb19ef-2c42-4a52-a60b-54b6f01c8791
title: AIPlugin
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Foundation-only protocol contract every AI provider plugin implements: describe
  one chat request and decode its response stream.'
platforms:
- swift
- macos
tags:
- ai-plugin-runtime
- protocol
depends-on:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-request-spec
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-stream-event
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-plugin-transport
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a Foundation-only protocol contract for AI provider plugins, not a visual component.

## States

Not applicable — this is a Foundation-only protocol contract for AI provider plugins, not a visual component.

## Accessibility

Not applicable — this is a Foundation-only protocol contract for AI provider plugins, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-001 | zero-argument-initialization | Construct a conforming type with no arguments, e.g. `EchoPlugin()` (`AIPluginKitTests.swift`). | The initializer returns a usable instance without throwing or crashing. |
| ai-plugin-002 | request-description | `EchoPlugin().buildRequest(AIChatContext(messages: [AIChatMessage(role: .user, content: "hi")], model: "test-model", config: AIPluginConfig(["apiKey": "secret"])))` (`AIPluginKitTests.swift`, lines 47-65). | Returns an `AIRequestSpec` whose `.transport` is `.http(method: .post, url: https://api.example.com/chat, headers: ["x-api-key": "secret"], body: Data("test-model".utf8))`. |
| ai-plugin-003 | insufficient-context-error | `OpenAIPlugin().buildRequest(AIChatContext(messages: [...], model: "gpt-4.1-nano", config: AIPluginConfig([:])))` — no `apiKey` present (`OpenAIPlugin.swift`, lines 12-15). | Throws `OpenAIPlugin.PluginError.missingAPIKey` instead of returning a spec. |
| ai-plugin-004 | fresh-decoder-per-response, decoder-isolation | Call `EchoPlugin().makeDecoder()` twice to get decoder A and decoder B; feed only decoder A the bytes `Data("a\n".utf8)`, then call `finish()` on both. | Decoder A's `finish()` (after `consume`) yields `[.textDelta("a")]`; decoder B's `finish()` yields `[]` — the two instances hold independent state. |
| ai-plugin-005 | fresh-decoder-per-response | `decoder.consume(Data("he".utf8))`, then `consume(Data("llo\nwor".utf8))`, then `consume(Data("ld\n".utf8))`, then `finish()`, on one `LineDecoder` from `EchoPlugin().makeDecoder()` (`AIPluginKitTests.swift`, lines 67-81). | Emits `[.textDelta("hello"), .textDelta("world")]`, in order, across the three `consume` calls plus `finish()`. |
| ai-plugin-006 | validation-request-default | `EchoPlugin().buildValidationRequest(config: AIPluginConfig(["apiKey": "x"]))` — `EchoPlugin` does not override the method. | Returns `nil`. |
| ai-plugin-007 | validation-request-cannot-validate | A stub conformer overrides `buildValidationRequest(config:)` to return `.http(url: validationURL)` when `config.apiKey != nil`, else `nil`; call it with `AIPluginConfig([:])`. | Returns `nil` because the stub has no key to validate. |
| ai-plugin-008 | error-message-default | `EchoPlugin().describeError(status: 500, body: Data())` — `EchoPlugin` does not override the method. | Returns `nil`, signaling the host should use its generic "HTTP 500" fallback. |
| ai-plugin-009 | transport-non-ownership, ui-non-ownership, secret-non-ownership, metadata-non-ownership | Enumerate `AIPlugin`'s protocol requirements (`AIPlugin.swift`, lines 921-942). | Exactly `init()`, `buildRequest(_:)`, `makeDecoder()`, `buildValidationRequest(config:)`, `describeError(status:body:)` — no member performs I/O directly, presents a view, reads/writes a credential store, or returns an identifier/display name. |
| ai-plugin-010 | sendable-conformance | Declare `final class BadPlugin: AIPlugin { var box = NSMutableString() }` with no `@unchecked Sendable` escape hatch, under `SWIFT_STRICT_CONCURRENCY: complete`. | Fails to compile: the non-`Sendable` stored property violates the `Sendable` conformance `AIPlugin: AnyObject, Sendable` requires. |
| ai-plugin-011 | concurrent-invocation-safety | A single, stateless `EchoPlugin` instance (as cached and reused by `AIPluginManager.loadPlugin(identifier:)`, `AIPluginManager.swift` lines 205-236) has `buildRequest(_:)` invoked concurrently from two `Task`s with two different `AIChatContext` values. | Both calls return correct, independent `AIRequestSpec` values; no data race occurs, because `EchoPlugin` reads only its `context` parameter and holds no shared mutable field. |
| ai-plugin-012 | foundation-only-dependency, shared-framework-image | Inspect `AIPlugin.swift`'s imports and `packages/apple/AIPlugins/project.yml`'s `OpenAI` target dependency on `AgenticToolkit/AIPluginKit`. | `AIPlugin.swift` imports only `Foundation`; the `OpenAI` (and every sibling plugin) target declares `dependencies: [{target: AgenticToolkit/AIPluginKit, embed: false}]` — linked, not embedded. |

`cheap-instantiation` (SHOULD) has no dedicated vector: constructor cost is a design guideline about how a plugin is expected to be written, not an automatable pass/fail assertion on the protocol itself; the rationale for this omission is recorded here per the Completeness guideline.

## Edge Cases

- **Empty or minimal context**: An `AIChatContext` whose `messages` is empty or whose `config` has no entries is not special-cased by this protocol; `buildRequest(_:)` MUST throw when it cannot proceed with what it was given, per the general "insufficient context" contract (`AIPlugin.swift`, line 927). Whether an empty `messages` array specifically counts as "insufficient" is left to each conforming type.
- **Boundary values**: Not applicable to `AIPlugin.swift` itself — numeric bounds such as `AIChatContext.maxTokens` and `AIRequestSpec.timeout` are owned by those sibling types, not by this protocol, which imposes no numeric constraint of its own.
- **Concurrent access**: Two tasks calling `buildRequest(_:)`, `buildValidationRequest(config:)`, or `describeError(status:body:)` on the same plugin instance concurrently MUST both complete correctly (MUST); `Sendable` conformance is the only concurrency guarantee this protocol supplies, and a conforming type's own internal mutable state is its own responsibility to protect.
- **Error states**: `buildRequest(_:)` MUST throw rather than return a partially built `AIRequestSpec` when it cannot construct a valid request (MUST, line 927). `describeError(status:body:)` MUST return `nil` rather than throw or crash when it cannot interpret the given `status`/`body` (MUST, per the never-throwing default extension at line 948).
- **Offline / disconnected state**: Not applicable in the direct sense — `buildRequest(_:)`, `makeDecoder()`, and `describeError(status:body:)` perform no I/O and so never observe connectivity themselves; an unreachable host or dropped connection surfaces later, to the host's transport layer, and reaches this protocol only indirectly as the `status`/`body` `describeError` is given after the attempt already failed.
- **Cancellation and timeouts**: `buildRequest(_:)` and `makeDecoder()` are synchronous, non-`async` calls that return immediately once invoked; they MUST NOT be treated as having a cancellation or timeout point of their own (SHOULD NOT be assumed cancellable mid-call). Cancelling or timing out the request the returned `AIRequestSpec` describes is the host's responsibility once the plugin has handed the spec back, per "the host owns the transport."
- **Missing file or unreachable server**: `buildRequest(_:)` and `makeDecoder()` MUST NOT themselves open a file, socket, or process — a missing executable path or an unreachable server is never observed inside this protocol's methods; those failures occur only later, when the host executes the `AIRequestSpec` the plugin produced.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` (parameter to `buildRequest(_:)`) | `AIChatContext` | none — required | Conversation messages, model, token budget, tool specs, and the resolved `AIPluginConfig` the caller supplies for one chat turn. |
| `config` (parameter to `buildValidationRequest(config:)`) | `AIPluginConfig` | none — required | Resolved settings plus any injected secret (e.g. `apiKey`) the host wants the plugin to check for validity. |
| `status`, `body` (parameters to `describeError(status:body:)`) | `Int`, `Data` | none — required | The HTTP-style status code and raw response body from a chat request or validation request that failed. |

This protocol defines no environment variable or settings key of its own; every value it reads arrives as a parameter already resolved by the host from the plugin's bundled `descriptor.json` schema (see the `AIPluginDescriptor` and `AIPluginConfig` sibling components).

## Deep Linking

Not applicable: `AIPlugin.swift` defines no URL scheme, route, or navigation destination — it describes an HTTP/subprocess request and decodes bytes, not app navigation.

## Localization

Not applicable: `AIPlugin.swift` contains no string literal intended for display; the only user-facing text this protocol touches is the `String?` a conforming type's own `describeError(status:body:)` may produce, and that string's content and localization are that conforming type's concern, not this file's.

## Accessibility Options

Not applicable: `AIPlugin.swift` presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `AIPlugin.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `AIPlugin.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: `buildRequest(_:)` receives `context.config`, and `buildValidationRequest(config:)` receives `config` directly, either of which MAY carry a credential such as an API key — per `AIChatContext.swift`'s own doc comment on `AIPluginConfig`: "the host reads these from the plugin's settings schema and injects secrets (API keys) from the Keychain just before calling `buildRequest`; the plugin never touches storage itself."
- **Storage**: `AIPlugin.swift` defines no storage of its own. Secret persistence (e.g. Keychain access) is the host's responsibility, implemented by the sibling `SecretStoring` component, not by any conforming `AIPlugin` type.
- **Transmission**: A conforming type never transmits data itself; it only describes a request (the returned `AIRequestSpec`'s headers or body MAY embed a credential, as `OpenAIPlugin.swift` does with `"Authorization": "Bearer \(apiKey)"`) for the host's transport (`PluginTransport`) to send.
- **Violation handling**: Out of scope for this protocol — detecting or reacting to a security violation (an invalid key, a revoked credential) is delegated entirely to the host's secret-storage and transport layers; `AIPlugin.swift` neither validates nor reports on credential legitimacy beyond the optional `buildValidationRequest(config:)` hook.

## Logging

Not applicable: `AIPlugin.swift` contains no logging call; it is a pure protocol declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIPlugin.swift`, alongside `AIChatContext.swift`, `AIRequestSpec.swift`, and `AIStreamEvent.swift` (its parameter and return types). Nothing here is SwiftUI-specific — a SwiftUI-based host consumes an `AIPlugin` exactly as an AppKit one does, through `AIPluginManager`/`PluginTransport`.
- **Compose**: Android has no analogue of `dlopen`-loading an arbitrary `.aiplugin` bundle's principal class at runtime. A Kotlin port would define the same contract as a plain `interface AIPlugin` and resolve implementations from a build-time registry or a `ServiceLoader`-style mechanism instead of loading foreign bundles from disk.
- **React/Web**: Model the contract as a plain TypeScript interface (`buildRequest`, `makeDecoder`, `buildValidationRequest`, `describeError`) with plugins as ES modules loaded via dynamic `import()` instead of `dlopen`. Use `fetch`/`ReadableStream` in place of `URLSession`/subprocess transport, and return `Promise`s from methods that are synchronous-but-throwing in Swift, since browser I/O is inherently asynchronous.
- **AppKit / UIKit**: Identical to the SwiftUI note — this protocol is UI-framework-agnostic; only the host application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model the contract as a C# interface on the .NET / Windows App SDK: `public interface IAiPlugin { AiRequestSpec BuildRequest(AiChatContext context); IAiStreamDecoder MakeDecoder(); AiRequestSpec? BuildValidationRequest(AiPluginConfig config); string? DescribeError(int status, byte[] body); }`, with a public parameterless constructor standing in for `init()`. Use `HttpClient` for the HTTP transport case `AIRequestSpec.Transport.http` describes and `System.Diagnostics.Process` for the `.command` case that `PluginTransport` drives. Represent `AIStreamEvent` as a discriminated record and expose decoding via `IAsyncEnumerable<AiStreamEvent>` rather than Swift's synchronous `Consume(byte[]) -> IReadOnlyList<AiStreamEvent>`, since .NET streaming favors `async`/`await` over buffering callbacks. `Windows.Storage`/Credential Locker is the analogue of the host's Keychain use — owned by the host, never by the plugin, matching the source. Dynamic loading of third-party plugin assemblies maps to `AssemblyLoadContext` rather than `dlopen` + `NSPrincipalClass`; because .NET assemblies are ordinarily loaded in full rather than resolved against one shared image, a WinUI 3 host MUST decide how it prevents duplicate type identity across plugin assemblies that each reference the interface assembly — the direct analogue of this source's "link, don't embed" rule.

## Design Decisions

**Decision**: `buildRequest(_:)` signals a bad `AIChatContext` by throwing, while `buildValidationRequest(config:)` signals "cannot validate" by returning `nil` rather than throwing.
**Rationale**: A `buildRequest(_:)` failure is exceptional — the chat turn cannot proceed at all — while returning `nil` from `buildValidationRequest(config:)` is a normal, expected outcome for a plugin with no lightweight way to check credentials; an optional return avoids forcing every plugin to define and throw a "not supported" error for what is a routine case.
**Approved**: pending

**Decision**: Instances are documented as cheap and MAY be constructed per request rather than pooled or reused.
**Rationale**: This keeps whatever a plugin closes over isolated per call without requiring conforming types to implement reset logic, and combined with the `Sendable` requirement it lets the host construct a plugin from any concurrency domain per call. In practice, the current host (`AIPluginManager.loadPlugin(identifier:)`) caches one instance per identifier and reuses it across every request for that identifier rather than constructing fresh instances — a documented quirk that makes the `concurrent-invocation-safety` requirement above load-bearing in the actual running system, even though the protocol's own doc comment permits either approach.
**Approved**: pending

**Decision**: `describeError(status:body:)` shares one signature for both a failed chat request and a failed credential-validation request.
**Rationale**: The doc comment states this explicitly ("Used for both failed chat requests and credential validation"); both call sites only need a human-readable message derived from a status code and a response body, so a second parameter distinguishing the call site was not needed for that purpose.
**Approved**: pending

**Decision**: `AIPluginKit` is linked, not embedded, by each plugin bundle, so it resolves to the host's single loaded image at `dlopen` time.
**Rationale**: The doc comment states this is what lets the host cast a freshly loaded principal class to `AIPlugin`; embedding a second copy of the framework would give the plugin's `AIPlugin` type a distinct identity from the host's, and the cast in `AIPluginManager.loadPlugin(identifier:)` (`principalClass as? any AIPlugin.Type`) would fail. This is confirmed in `packages/apple/AIPlugins/project.yml`, where every plugin target (`ClaudeAPI`, `ClaudeLocal`, `Google`, `OpenAI`, `OpenAICompatible`) declares its `AgenticToolkit/AIPluginKit` dependency with `embed: false`.
**Approved**: pending

## Compliance

Not applicable: no automated compliance check exists yet for this component in the cookbook's check registry.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
