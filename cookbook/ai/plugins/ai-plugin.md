---
id: 47eb19ef-2c42-4a52-a60b-54b6f01c8791
title: AI Plugin
domain: agentictoolkit://cookbook/ai/plugins/ai-plugin
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The contract every AI provider plugin implements: describe one chat request
  and decode its response stream.'
platforms:
- swift
- macos
tags:
- ai-plugin-runtime
- protocol
depends-on:
- agentictoolkit://cookbook/ai/chat/chat-context
- agentictoolkit://cookbook/ai/plugins/request-spec
- agentictoolkit://cookbook/ai/plugins/stream-event
related:
- agentictoolkit://cookbook/ai/plugins/plugin-manager
- agentictoolkit://cookbook/ai/plugins/plugin-transport
- agentictoolkit://cookbook/ai/plugins/plugin-descriptor
references: []
approved-by: ''
approved-date: ''
---

# AI Plugin

## Overview

An AI plugin is the contract every AI provider plugin implements. A plugin
is the principal entry point of a plugin bundle: given one chat turn's
context, it describes the HTTP or subprocess request for that turn as a
request spec, and it creates a fresh stream decoder that turns the
provider's raw response bytes into stream events. A plugin never performs
networking, spawns a process, presents any UI, or stores a secret itself —
it only describes and decodes; the host performs the transport, builds the
settings UI from the bundle's descriptor schema, and owns secret storage.

## Behavioral Requirements

- **zero-argument-initialization**: A conforming plugin type MUST provide a
  synchronous, non-failing, zero-argument construction path, since the host
  constructs plugin instances by invoking it on a type obtained by
  resolving a bundle's principal class.
- **cheap-instantiation**: Constructing a conforming plugin SHOULD be
  inexpensive, because the contract documents instances as cheap and states
  a caller MAY create a new instance per request.
- **request-description**: Building a request MUST synchronously return a
  request spec that fully describes the HTTP or subprocess request for one
  chat turn, derived from the given chat context.
- **insufficient-context-error**: Building a request MUST fail with an
  error instead of returning a value when the given chat context does not
  contain what the plugin needs to build a request (e.g. a required config
  value is missing).
- **fresh-decoder-per-response**: Creating a decoder MUST return a newly
  created stream-decoder instance on every call, and that instance MUST own
  whatever mutable state it needs to parse exactly one response stream.
- **validation-request-default**: Building a validation request MUST
  return no result for a conforming plugin that does not override this
  behavior, via the contract's default implementation.
- **validation-request-cannot-validate**: An overriding validation-request
  implementation MUST return no result when it has no way to validate the
  given plugin configuration.
- **error-message-default**: Describing an error MUST return no result for
  a conforming plugin that does not override this behavior, via the
  contract's default implementation, signaling the host SHOULD fall back to
  a generic "HTTP `<status>`" message.
- **transport-non-ownership**: A conforming plugin MUST NOT perform
  networking or spawn a subprocess itself; building a request and building
  a validation request MUST only describe a request, never execute one —
  the plugin performs no networking, and the host owns the transport.
- **ui-non-ownership**: A conforming plugin MUST NOT present any user
  interface; the host builds the settings UI from the bundle's descriptor
  schema, and the plugin ships no UI of its own.
- **secret-non-ownership**: A conforming plugin MUST NOT implement its own
  secret storage; the host owns secret storage, and any credential the
  plugin needs arrives already resolved inside the chat context's
  configuration.
- **metadata-non-ownership**: A conforming plugin MUST NOT expose identity
  or presentation metadata (identifier, display name, supported models,
  capabilities, settings schema) through this contract; all identity and
  presentation metadata live as data in the bundle, not in the plugin's own
  code, so the host can list and configure a plugin without loading its
  binary.
- **shared-instance-concurrency-safety**: The contract MUST require every
  conforming plugin to be safe to invoke concurrently from multiple callers
  on one shared instance, and to be usable as a reference type so the host
  can hold and reuse one instance across calls — the plugin itself MUST be
  safe to capture and invoke from any concurrency domain.
- **concurrent-invocation-safety**: Because a conforming plugin must be
  safe to invoke concurrently, a conforming plugin MUST make any internal
  mutable state safe for concurrent invocation of building a request,
  building a validation request, and describing an error from multiple
  callers on one shared instance. The implementation's compiler MAY
  statically enforce this for ordinary stored state; an implementation that
  opts out of that static enforcement assumes the safety obligation
  manually.
- **decoder-isolation**: The stream decoder a decoder-creation call returns
  MUST be used to parse a single response only and MUST NOT be shared
  across concurrent responses, since it is not safe to share across
  concurrency domains and is documented to hold per-response parsing
  state.
- **foundation-only-dependency**: The module declaring this contract MUST
  depend only on the platform's base runtime library, with no UI framework
  or third-party dependency.
- **shared-framework-image**: A plugin bundle MUST link the module
  declaring this contract without embedding a separate copy of it, so a
  freshly loaded plugin type resolves against the host's single loaded
  copy of that module and can be recognized as conforming to the contract.

## Appearance

Not applicable — this is the contract for AI provider plugins, not a
visual component.

## States

Not applicable — this is the contract for AI provider plugins, not a
visual component.

## Accessibility

Not applicable — this is the contract for AI provider plugins, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-001 | zero-argument-initialization | Construct a conforming plugin type with no arguments. | Construction returns a usable instance without throwing or crashing. |
| ai-plugin-002 | request-description | Build a request for a chat context with one user message "hi", model "test-model", and configuration `{"apiKey": "secret"}`, using a plugin that describes an HTTP POST to `https://api.example.com/chat` with the API key as an `x-api-key` header and the model name as the body. | Returns a request spec whose transport is an HTTP POST to `https://api.example.com/chat` with headers `{"x-api-key": "secret"}` and body `"test-model"`. |
| ai-plugin-003 | insufficient-context-error | Build a request for a chat context with no `apiKey` present in its configuration, using a plugin that requires one. | Fails with an error identifying a missing API key, instead of returning a spec. |
| ai-plugin-004 | fresh-decoder-per-response, decoder-isolation | Create two decoders from the same plugin (decoder A and decoder B); feed only decoder A the bytes `"a\n"`, then finish both. | Decoder A's finish (after consuming) yields one text delta `"a"`; decoder B's finish yields nothing — the two instances hold independent state. |
| ai-plugin-005 | fresh-decoder-per-response | Feed one decoder the byte chunks `"he"`, then `"llo\nwor"`, then `"ld\n"`, then finish it. | Emits text deltas `"hello"` then `"world"`, in order, across the chunks plus the finish call. |
| ai-plugin-006 | validation-request-default | Build a validation request using a plugin that does not override this behavior, given configuration `{"apiKey": "x"}`. | Returns no result. |
| ai-plugin-007 | validation-request-cannot-validate | A plugin overrides validation-request building to return a validation request only when its configuration has an API key; call it with an empty configuration. | Returns no result because there is no key to validate. |
| ai-plugin-008 | error-message-default | Describe an error for status 500 with an empty body, using a plugin that does not override this behavior. | Returns no result, signaling the host should use its generic "HTTP 500" fallback. |
| ai-plugin-009 | transport-non-ownership, ui-non-ownership, secret-non-ownership, metadata-non-ownership | Enumerate the contract's required members. | Exactly construction, building a request, creating a decoder, building a validation request, and describing an error — no member performs I/O directly, presents a view, reads/writes a credential store, or returns an identifier/display name. |
| ai-plugin-010 | shared-instance-concurrency-safety | Declare a conforming plugin type with an internal mutable field that is not itself safe to share across concurrency domains, and no opt-out of the implementation's static enforcement. | The implementation is rejected at build time: an unprotected mutable field violates the required concurrency-safety guarantee. |
| ai-plugin-011 | concurrent-invocation-safety | A single, stateless plugin instance (as cached and reused by the host's plugin loader) has request-building invoked concurrently from two callers with two different chat contexts. | Both calls return correct, independent request specs; no data race occurs, because the plugin reads only its input parameter and holds no shared mutable field. |
| ai-plugin-012 | foundation-only-dependency, shared-framework-image | Inspect the module declaring this contract's dependencies and each plugin target's link configuration for that module. | The module depends only on the platform's base runtime library; every plugin target links that module without embedding a separate copy of it. |

`cheap-instantiation` (SHOULD) has no dedicated vector: constructor cost is a design guideline about how a plugin is expected to be written, not an automatable pass/fail assertion on the contract itself; the rationale for this omission is recorded here per the Completeness guideline.

## Edge Cases

- **Empty or minimal context**: A chat context whose messages list is empty or whose configuration has no entries is not special-cased by this contract; building a request MUST fail when it cannot proceed with what it was given, per the general "insufficient context" rule. Whether an empty messages list specifically counts as "insufficient" is left to each conforming plugin.
- **Boundary values**: Not applicable to this contract itself — numeric bounds such as a chat context's `maxTokens` and a request spec's `timeout` are owned by those sibling concepts, not by this contract, which imposes no numeric constraint of its own.
- **Concurrent access**: Two callers invoking building a request, building a validation request, or describing an error on the same plugin instance concurrently MUST both complete correctly (MUST); the required concurrency-safety guarantee is the only concurrency guarantee this contract supplies, and a conforming plugin's own internal mutable state is its own responsibility to protect.
- **Error states**: Building a request MUST fail with an error rather than return a partially built request spec when it cannot construct a valid request (MUST). Describing an error MUST return no result rather than fail or crash when it cannot interpret the given status/body (MUST, per the non-failing default behavior).
- **Offline / disconnected state**: Not applicable in the direct sense — building a request, creating a decoder, and describing an error perform no I/O and so never observe connectivity themselves; an unreachable host or dropped connection surfaces later, to the host's transport layer, and reaches this contract only indirectly, as the status/body that error-description is given after the attempt already failed.
- **Cancellation and timeouts**: Building a request and creating a decoder are synchronous calls that return immediately once invoked; they MUST NOT be treated as having a cancellation or timeout point of their own (SHOULD NOT be assumed cancellable mid-call). Cancelling or timing out the request the returned request spec describes is the host's responsibility once the plugin has handed the spec back, since the host owns the transport.
- **Missing file or unreachable server**: Building a request and creating a decoder MUST NOT themselves open a file, socket, or process — a missing executable path or an unreachable server is never observed inside this contract's own behaviors; those failures occur only later, when the host executes the request spec the plugin produced.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` (parameter to building a request) | chat context | none — required | Conversation messages, model, token budget, tool specs, and the resolved configuration the caller supplies for one chat turn. |
| `config` (parameter to building a validation request) | plugin configuration | none — required | Resolved settings plus any injected secret (e.g. `apiKey`) the host wants the plugin to check for validity. |
| `status`, `body` (parameters to describing an error) | integer, raw bytes | none — required | The HTTP-style status code and raw response body from a chat request or validation request that failed. |

This contract defines no environment variable or settings key of its own; every value it reads arrives as a parameter already resolved by the host from the plugin's bundled descriptor schema (see the plugin-descriptor and plugin-configuration sibling components).

## Deep Linking

Not applicable: this contract defines no URL scheme, route, or navigation destination — it describes an HTTP/subprocess request and decodes bytes, not app navigation.

## Localization

Not applicable: this contract contains no string literal intended for display; the only user-facing text this contract touches is the optional string a conforming plugin's own error-description behavior may produce, and that string's content and localization are that conforming plugin's concern, not this contract's.

## Accessibility Options

Not applicable: this contract presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this contract contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: this contract contains no analytics or event-tracking call.

## Privacy

- **Data handled**: Building a request receives the chat context's configuration, and building a validation request receives a configuration directly, either of which MAY carry a credential such as an API key — the host reads these from the plugin's settings schema and injects secrets (API keys) from secure storage just before calling request-building; the plugin never touches storage itself.
- **Storage**: This contract defines no storage of its own. Secret persistence (e.g. keychain-style secure storage) is the host's responsibility, implemented by a sibling secret-storage component, not by any conforming plugin.
- **Transmission**: A conforming plugin never transmits data itself; it only describes a request (the returned request spec's headers or body MAY embed a credential, e.g. as an `Authorization: Bearer <apiKey>` header) for the host's transport to send.
- **Violation handling**: Out of scope for this contract — detecting or reacting to a security violation (an invalid key, a revoked credential) is delegated entirely to the host's secret-storage and transport layers; this contract neither validates nor reports on credential legitimacy beyond the optional validation-request hook.

## Logging

Not applicable: this contract contains no logging call; it is a pure contract declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIPlugin.swift`, alongside `AIChatContext.swift`, `AIRequestSpec.swift`, and `AIStreamEvent.swift` (its parameter and return types). Nothing here is SwiftUI-specific — a SwiftUI-based host consumes an `AIPlugin` exactly as an AppKit one does, through `AIPluginManager`/`PluginTransport`. The protocol requires every conforming type to be `Sendable` and a class (`public protocol AIPlugin: AnyObject, Sendable`), so a single plugin instance may be captured and invoked from any concurrency domain — the doc comment states "The plugin itself is `Sendable`, so capturing it is safe" (quoted from `PluginTransport.swift`, which captures a plugin inside a `Task`). Swift's strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`) enforces this for ordinary stored state; a conforming type assumes the safety obligation manually when it opts out with `@unchecked Sendable`, as `OpenAIPlugin` does. The framework declaring this protocol (`AIPluginKit`) is a Foundation-only dynamic framework, with no dependency beyond it.
- **Compose**: Android has no analogue of `dlopen`-loading an arbitrary `.aiplugin` bundle's principal class at runtime. A Kotlin port would define the same contract as a plain `interface AIPlugin` and resolve implementations from a build-time registry or a `ServiceLoader`-style mechanism instead of loading foreign bundles from disk.
- **React/Web**: Model the contract as a plain TypeScript interface (`buildRequest`, `makeDecoder`, `buildValidationRequest`, `describeError`) with plugins as ES modules loaded via dynamic `import()` instead of `dlopen`. Use `fetch`/`ReadableStream` in place of `URLSession`/subprocess transport, and return `Promise`s from methods that are synchronous-but-throwing in Swift, since browser I/O is inherently asynchronous.
- **AppKit / UIKit**: Identical to the SwiftUI note — this protocol is UI-framework-agnostic; only the host application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model the contract as a C# interface on the .NET / Windows App SDK: `public interface IAiPlugin { AiRequestSpec BuildRequest(AiChatContext context); IAiStreamDecoder MakeDecoder(); AiRequestSpec? BuildValidationRequest(AiPluginConfig config); string? DescribeError(int status, byte[] body); }`, with a public parameterless constructor standing in for `init()`. Use `HttpClient` for the HTTP transport case `AIRequestSpec.Transport.http` describes and `System.Diagnostics.Process` for the `.command` case that `PluginTransport` drives. Represent `AIStreamEvent` as a discriminated record and expose decoding via `IAsyncEnumerable<AiStreamEvent>` rather than Swift's synchronous `Consume(byte[]) -> IReadOnlyList<AiStreamEvent>`, since .NET streaming favors `async`/`await` over buffering callbacks. `Windows.Storage`/Credential Locker is the analogue of the host's Keychain use — owned by the host, never by the plugin, matching the source. Dynamic loading of third-party plugin assemblies maps to `AssemblyLoadContext` rather than `dlopen` + `NSPrincipalClass`; because .NET assemblies are ordinarily loaded in full rather than resolved against one shared image, a WinUI 3 host MUST decide how it prevents duplicate type identity across plugin assemblies that each reference the interface assembly — the direct analogue of this source's "link, don't embed" rule.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIPlugin.swift` |

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

**Decision**: In the Apple/Swift implementation, `AIPluginKit` is linked, not embedded, by each plugin bundle, so it resolves to the host's single loaded image at `dlopen` time.
**Rationale**: The doc comment states this is what lets the host cast a freshly loaded principal class to `AIPlugin`; embedding a second copy of the framework would give the plugin's `AIPlugin` type a distinct identity from the host's, and the cast in `AIPluginManager.loadPlugin(identifier:)` (`principalClass as? any AIPlugin.Type`) would fail. This is confirmed in `packages/apple/AIPlugins/project.yml`, where every plugin target (`ClaudeAPI`, `ClaudeLocal`, `Google`, `OpenAI`, `OpenAICompatible`) declares its `AgenticToolkit/AIPluginKit` dependency with `embed: false`. Any platform that dynamically loads plugin modules against a shared type system faces the same "one copy, not two" concern under its own name — see the WinUI 3 note on `AssemblyLoadContext` above.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |

Notes: separation-of-concerns passes because the protocol's own requirements forbid a conforming type from owning transport, UI, secret storage, or presentation metadata (`transport-non-ownership`, `ui-non-ownership`, `secret-non-ownership`, `metadata-non-ownership`), so a plugin only describes and decodes while the host performs every other concern. unit-test-coverage passes because `AIPluginKitTests.swift` exercises `EchoPlugin` and `OpenAIPlugin` conformances directly — initialization, request description, decoder freshness, and the missing-API-key throw path. explicit-error-handling passes because `buildRequest(_:)` MUST throw an `Error` rather than return an invalid spec when the given context is insufficient, per `insufficient-context-error`. test-pyramid passes because `AIPluginKitTests.swift` exercises the protocol's contract entirely at the unit level, with no integration or UI test needed for a Foundation-only protocol.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
