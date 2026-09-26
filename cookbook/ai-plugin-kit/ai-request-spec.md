---
id: 72829b3b-ce4a-4730-877f-da7b48e7b3dd
title: AIRequestSpec
domain: agentictoolkit://cookbook/ai-plugin-kit/ai-request-spec
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Sendable value type an AIPlugin.buildRequest(_:) returns: a fully-described
  HTTP or local-command request for one chat turn, plus a wall-clock timeout.'
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- sendable
- foundation
- transport
depends-on: []
related:
- agentictoolkit://cookbook/ai-plugin-kit/ai-plugin
references: []
approved-by: ''
approved-date: ''
---

# AIRequestSpec

## Overview

`AIRequestSpec` is the `Sendable` value type an `AIPlugin`'s `buildRequest(_:)` returns: a fully-described request for one chat turn. It carries only a description of how the host should reach the provider — over HTTP or by running a local command — plus a wall-clock `timeout`; it performs no networking or process work itself. The plugin contributes the description; `PluginTransport.run(spec:plugin:)` is the sole consumer that turns the description into an actual `URLSession` request or a subprocess. The split between transport kinds lives in this type's `Transport` case, not in the plugin's identity, so every plugin has the same "describe a request, decode the bytes" shape (`AIRequestSpec.swift`).

## Behavioral Requirements

- **sendable-conformance**: `AIRequestSpec`, its nested `Method` enum, and its nested `Transport` enum MUST all conform to `Sendable` (`public struct AIRequestSpec: Sendable`, `public enum Method: String, Sendable`, `public enum Transport: Sendable`), so a value returned by `buildRequest(_:)` MAY be handed across concurrency domains (from the plugin's isolation to the host's transport task) without a data-race diagnostic.
- **value-type-semantics**: `AIRequestSpec` MUST be a `struct`, not a class, so assigning or passing an instance MUST copy it: mutating one binding's `transport` or `timeout` MUST NOT affect any other binding holding a separately-assigned copy of the same instance.
- **mutable-fields**: `transport` and `timeout` MUST be mutable (`public var`, not `public let`), so a caller MAY construct an instance and then reassign either field before handing the value to the host.
- **exactly-one-transport**: An instance MUST describe exactly one way to reach the provider, held in its single `transport: Transport` property; `Transport` MUST be an `enum` whose two cases are mutually exclusive, so a single instance MUST NOT simultaneously describe an HTTP request and a subprocess command.
- **http-transport-fields**: The `.http` `Transport` case MUST carry exactly `method: Method`, `url: URL`, `headers: [String: String]`, and `body: Data?`.
- **command-transport-fields**: The `.command` `Transport` case MUST carry exactly `executableURL: URL`, `arguments: [String]`, `stdin: Data?`, and `environment: [String: String]`.
- **method-cases**: `Method` MUST expose exactly two cases, `.get` with raw value `"GET"` and `.post` with raw value `"POST"`.
- **timeout-field**: An instance MUST carry a `timeout: TimeInterval` representing the wall-clock budget for the whole request before the host cancels it, per its doc comment.
- **designated-initializer**: `init(transport:timeout:)` MUST be the sole designated initializer, MUST accept a required `transport: Transport`, MUST default `timeout` to `120` when the caller omits it, and MUST be synchronous and non-throwing.
- **http-convenience-constructor**: The static `http(method:url:headers:body:timeout:)` constructor MUST require only `url` and MUST default `method` to `.post`, `headers` to `[:]`, `body` to `nil`, and `timeout` to `120`, returning an `AIRequestSpec` whose `transport` is `.http` with exactly the given (or defaulted) values.
- **command-convenience-constructor**: The static `command(executableURL:arguments:stdin:environment:timeout:)` constructor MUST require only `executableURL` and MUST default `arguments` to `[]`, `stdin` to `nil`, `environment` to `[:]`, and `timeout` to `120`, returning an `AIRequestSpec` whose `transport` is `.command` with exactly the given (or defaulted) values.
- **non-throwing-construction**: No initializer or static constructor this type defines MAY throw or fail; every path from valid Swift argument values to an `AIRequestSpec` instance MUST succeed synchronously (54 — none is marked `throws`).
- **no-input-validation**: Neither the designated initializer nor either convenience constructor MUST validate its arguments; any `TimeInterval` (including zero, negative, `NaN`, or `.infinity`), any `URL`, and any string dictionary or byte `Data` the caller supplies MUST be accepted and stored unchanged. This is a deliberate design, not a gap: interpreting an out-of-range `timeout` is left entirely to the request's one consumer (see Design Decisions).
- **description-only-contract**: A value of this type MUST NOT itself perform networking, spawn a process, or produce any other side effect; per the doc comment, "the plugin contributes only the description; the host owns the transport". Constructing or holding an `AIRequestSpec` MUST have no observable effect beyond the value itself.
- **no-persistence**: An `AIRequestSpec` instance MUST NOT be cached, reused across chat turns, or written to any store by this type; `AIPlugin.buildRequest(_:)` is documented to build a fresh spec from the `AIChatContext` given to it for one chat turn, and `AIRequestSpec.swift` defines no storage of its own.
- **host-http-consumption**: When the host executes an `.http`-transport instance, `method.rawValue` becomes the resulting request's HTTP method, each `headers` entry is applied as one HTTP header field, and `body` becomes the request body — traced to the request's sole consumer, `PluginTransport.runHTTP(method:url:headers:body:timeout:plugin:into:)` (`PluginTransport.swift`), which is cited here because it is the only place these fields' meaning is observable.
- **host-command-consumption**: When the host executes a `.command`-transport instance, `executableURL` and `arguments` describe the child process, `stdin` (if non-`nil`) is written to the child and then the child's input is closed to signal EOF, and the child's stdout is streamed to the plugin's decoder — traced to `PluginTransport.runCommand(executableURL:arguments:stdin:environment:plugin:into:)` (`PluginTransport.swift`).
- **environment-replace-semantics**: A non-empty `environment` on a `.command`-transport instance MUST become the entire environment of the spawned child process, replacing rather than merging with the host process's own environment; an empty `environment` MUST leave the child inheriting the host's environment unchanged. This is traced to `PluginTransport.swift`'s explicit `environmentPolicy: .replace` and is non-obvious from the field's name alone, so a plugin that wants the host's `PATH` (or any other inherited variable) available to its child MUST include it explicitly, as `ClaudeLocalPlugin.buildRequest(_:)` does by starting from `ProcessInfo.processInfo.environment` before appending search paths (`ClaudeLocalPlugin.swift`).
- **dual-purpose-timeout**: For an `.http`-transport instance, `timeout` MUST be used both as the wall-clock budget racing the whole request (`withWallClockBudget(spec.timeout)`) and, independently, as `URLRequest`'s `timeoutInterval` — an idle timeout that resets on every received byte rather than bounding the whole transfer — traced to `PluginTransport.run(spec:plugin:)` and `runHTTP`. A single `timeout` value therefore governs two different timeout semantics in the one consumer that reads it.

## Appearance

Not applicable — this is a request-description value type, not a visual component.

## States

Not applicable — this is a request-description value type, not a visual component.

## Accessibility

Not applicable — this is a request-description value type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-request-spec-001 | http-convenience-constructor, designated-initializer | `AIRequestSpec.http(url: URL(string: "https://example.com/v1")!)` (`AIPluginKitTests.swift`, "AIRequestSpec.http applies sensible defaults"). | `spec.timeout == 120`; `spec.transport` is `.http(method: .post, url: <same url>, headers: [:], body: nil)`. |
| ai-request-spec-002 | command-convenience-constructor | `AIRequestSpec.command(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["echo", "hi"], stdin: Data("in".utf8))` (`AIPluginKitTests.swift`, "AIRequestSpec.command carries the subprocess description"). | `spec.transport` is `.command(executableURL: <exe>, arguments: ["echo", "hi"], stdin: Data("in".utf8), environment: [:])`; `spec.timeout == 120` by default. |
| ai-request-spec-003 | http-transport-fields, http-convenience-constructor | `EchoPlugin().buildRequest(context)` where `context.config.apiKey == "secret"` and `context.model == "test-model"`; `EchoPlugin.buildRequest` calls `.http(url: URL(string: "https://api.example.com/chat")!, headers: ["x-api-key": "secret"], body: Data("test-model".utf8))` (`AIPluginKitTests.swift`). | Returned `AIRequestSpec.transport` is `.http(method: .post, url: https://api.example.com/chat, headers: ["x-api-key": "secret"], body: Data("test-model".utf8))`. |
| ai-request-spec-004 | value-type-semantics, mutable-fields | Assign `var a = AIRequestSpec.http(url: someURL)`, then `var b = a`, then set `b.timeout = 5` (direct consequence of `AIRequestSpec` being declared `struct` with `var` stored properties — Swift value-type copy-on-write semantics). | `a.timeout == 120` (unchanged); `b.timeout == 5`; the two bindings do not share mutable state. |
| ai-request-spec-005 | command-convenience-constructor, timeout-field | `AIRequestSpec.command(executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"), timeout: 30)` (default-parameter override). | `spec.timeout == 30`, overriding the constructor's own default of `120`. |
| ai-request-spec-006 | method-cases | `AIRequestSpec.Method.get.rawValue` and `AIRequestSpec.Method.post.rawValue`. | `"GET"` and `"POST"` respectively. |
| ai-request-spec-007 | environment-replace-semantics | `ClaudeLocalPlugin.buildRequest(_:)` builds `environment` by starting from `ProcessInfo.processInfo.environment`, then overwrites only `environment["PATH"]` with a joined search-path string, and returns `.command(executableURL: <claude path>, arguments: ..., stdin: Data(prompt.utf8), environment: environment)` (`ClaudeLocalPlugin.swift`). | The returned spec's `.command` case carries a non-empty `environment` containing every key from the current process's environment plus a rewritten `PATH`; per `environment-replace-semantics`, the host uses this dictionary as the child's entire environment rather than merging it with anything else. |
| ai-request-spec-008 | no-input-validation | `AIRequestSpec(transport: .http(method: .post, url: someURL, headers: [:], body: nil), timeout: .nan)`, then `AIRequestSpec(transport: ..., timeout: -5)`. | Both constructions succeed and return a value whose `timeout` is exactly `.nan` and `-5` respectively; neither the initializer nor either static constructor throws, clamps, or otherwise rejects the value. |

## Edge Cases

- **Null/empty input**: `headers: [:]`, `body: nil`, `arguments: []`, `stdin: nil`, and `environment: [:]` are each that field's own documented default and MUST be accepted as ordinary, valid values, not as an error condition. An empty `environment` MUST leave the child process inheriting the host's environment, per `environment-replace-semantics`.
- **Boundary values**: `timeout` accepts any `TimeInterval`, including `0`, a negative value, `.nan`, and `.infinity`; `AIRequestSpec` itself imposes no minimum, maximum, or validity constraint on `timeout` (per `no-input-validation`). What each of those boundary values means once the host consumes it is defined entirely outside this type, by the request's one consumer.
- **Concurrent access**: Because `AIRequestSpec` is a `Sendable` value type, a single instance MAY be read or copied concurrently from multiple tasks without synchronization, since each concurrent holder either owns an independent copy or observes an immutable snapshot at the point it was captured. Concurrent *mutation* of one shared mutable binding to an `AIRequestSpec` (e.g., a `var` stored on a class) is not a concern this type resolves; it is an ordinary Swift shared-mutable-state hazard no different from any other `Sendable` struct stored that way, and `AIRequestSpec.swift` defines no such shared binding itself.
- **Error states**: No operation `AIRequestSpec.swift` defines (its initializer or either static constructor) can fail — none is `throws`. A failure to actually perform the described request (an unreachable host, a non-2xx HTTP status, a non-zero subprocess exit) is reported by the host's transport layer after this type has already handed back a value, never by `AIRequestSpec` itself.
- **Offline/disconnected state**: `AIRequestSpec.swift` performs no I/O and so never observes network connectivity; connectivity loss during the request the instance describes is entirely the concern of the host transport that consumes the instance, not of this type.
- **Missing file or unreachable server**: An `executableURL` that names a file that does not exist, or a `url` whose host is unreachable, is accepted unchanged by every initializer and constructor this type defines; the resulting failure surfaces only when the host later attempts to launch the process or open the connection, per the doc comment's "the host owns the transport". This mirrors the sibling `AIPlugin` protocol's own contract that such failures are "never observed inside" the plugin's methods.
- **Cancellation and timeout**: `AIRequestSpec`'s own initializer and constructors are synchronous and return immediately; they have no cancellation or timeout point of their own. The `timeout` value they carry is enforced, and any in-flight request is cancelled, only by the host's transport layer once it begins executing the described `Transport` — never by this type.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `transport` (`init(transport:timeout:)`) | `Transport` | none — required | The `.http` or `.command` description of how to reach the provider for this request. |
| `timeout` (`init`, `.http`, `.command`) | `TimeInterval` | `120` | Wall-clock budget for the whole request before the host cancels it. |
| `method` (`.http(...)`) | `Method` | `.post` | HTTP method for an HTTP-transport request. |
| `headers` (`.http(...)`) | `[String: String]` | `[:]` | HTTP header fields applied to the request. |
| `body` (`.http(...)`) | `Data?` | `nil` | HTTP request body. |
| `executableURL` (`.command(...)`) | `URL` | none — required | Path to the executable the host spawns as a subprocess. |
| `arguments` (`.command(...)`) | `[String]` | `[]` | Command-line arguments passed to the subprocess. |
| `stdin` (`.command(...)`) | `Data?` | `nil` | Bytes written to the subprocess's standard input before it is closed. |
| `environment` (`.command(...)`) | `[String: String]` | `[:]` | Environment variables for the subprocess; a non-empty value replaces the host's own environment for the child (see `environment-replace-semantics`). |

`AIRequestSpec.swift` defines no environment variable or settings key of its own; every value above arrives as a caller-supplied constructor argument.

## Deep Linking

Not applicable: `AIRequestSpec.swift` defines no URL scheme, route, or navigation destination; the `url` it carries addresses an AI provider's HTTP endpoint, not an app deep link.

## Localization

Not applicable: `AIRequestSpec.swift` contains no string literal intended for display; `headers`, `body`, `arguments`, `stdin`, and `environment` carry caller-supplied, non-display data.

## Accessibility Options

Not applicable: `AIRequestSpec.swift` presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `AIRequestSpec.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `AIRequestSpec.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: `headers`, `body`, `stdin`, and `environment` MAY each carry a credential a plugin has embedded into the request description — for example `OpenAIPlugin` places an API key into an HTTP header, and `ClaudeLocalPlugin` places the full process environment (which MAY contain secrets a shell session has exported) into a `.command` spec's `environment` (`ClaudeLocalPlugin.swift`). `AIRequestSpec.swift` itself has no knowledge of which fields hold a secret; it stores whatever `Data` or dictionary value it is given.
- **Storage**: `AIRequestSpec.swift` defines no storage of its own and MUST NOT persist any field to disk or any other durable store; per `no-persistence`, an instance exists only as long as the plugin and host both hold a reference to it during one chat turn.
- **Transmission**: `AIRequestSpec` never transmits data itself; its fields describe what the host's transport (`PluginTransport`) will send over HTTP or write to a subprocess's stdin, per `host-http-consumption` and `host-command-consumption`.
- **Violation handling**: Out of scope for this type — detecting or reacting to a leaked or invalid credential is the responsibility of the plugin that built the spec and the host's transport and secret-storage layers; `AIRequestSpec.swift` performs no inspection of its own field values.

## Logging

Not applicable: `AIRequestSpec.swift` contains no logging call; it is a pure data type with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIRequestSpec.swift`, consumed by `PluginTransport.swift` (same directory) and returned by every conforming `AIPlugin.buildRequest(_:)` implementation under `packages/apple/AIPlugins/*/`. Nothing here is SwiftUI-specific; a SwiftUI-based host reads and executes an `AIRequestSpec` exactly as an AppKit one does, through `PluginTransport`.
- **Compose**: Model the two-case `Transport` as a Kotlin `sealed interface AiTransport` with `data class Http(val method: AiMethod, val url: String, val headers: Map<String, String>, val body: ByteArray?)` and `data class Command(val executablePath: String, val arguments: List<String>, val stdin: ByteArray?, val environment: Map<String, String>)`, and wrap it in `data class AiRequestSpec(val transport: AiTransport, val timeoutMillis: Long = 120_000)`. `AiMethod` is a two-case `enum class` (`GET`, `POST`). Android has no first-class notion of spawning an arbitrary local executable the way `.command` does; a Compose/Android port would typically omit or stub the command case unless the host environment specifically supports subprocess execution.
- **React/Web**: Model `Transport` as a discriminated union — `{ kind: "http", method: "GET" | "POST", url: string, headers: Record<string, string>, body?: Uint8Array } | { kind: "command", executablePath: string, arguments: string[], stdin?: Uint8Array, environment: Record<string, string> }` — inside `interface AIRequestSpec { transport: Transport; timeout: number }` (milliseconds, defaulting to `120_000`). A browser host has no subprocess primitive at all; the `command` case only makes sense for a Node.js or Electron host, which would use `child_process.spawn` in place of `PluginTransport.runCommand`, writing `stdin` and calling `stdin.end()` for EOF, matching `host-command-consumption`. Use the `fetch` API's `AbortController`, tied to a `setTimeout(timeout)`, in place of Swift's wall-clock budget race.
- **AppKit / UIKit**: Identical to the SwiftUI note — this type is UI-framework-agnostic; only the host application embedding `AIPluginKit` differs, never this data shape.
- **WinUI 3**: Model the contract as an immutable-by-convention record on the .NET / Windows App SDK: `public sealed record AiRequestSpec(AiTransport Transport, TimeSpan Timeout = default)` where a `default` `TimeSpan` is treated by the host as "use the 120-second default" (since C# cannot default a record parameter to a non-constant `TimeSpan.FromSeconds(120)` inline, the host or a factory method substitutes it, mirroring the source). Represent `Transport` as an `abstract record AiTransport` with two derived records: `HttpTransport(HttpMethod Method, Uri Url, IReadOnlyDictionary<string, string> Headers, byte[]? Body) : AiTransport` — reusing `System.Net.Http.HttpMethod.Get`/`.Post` rather than a custom enum — and `CommandTransport(string ExecutablePath, IReadOnlyList<string> Arguments, byte[]? Stdin, IReadOnlyDictionary<string, string> Environment) : AiTransport`. A WinUI 3 host executes `HttpTransport` with `System.Net.Http.HttpClient.SendAsync` (streaming the response via `HttpCompletionOption.ResponseHeadersRead`) and `CommandTransport` with `System.Diagnostics.Process`/`ProcessStartInfo`: set `RedirectStandardInput`/`RedirectStandardOutput` to `true`, write `Stdin` to `StandardInput.BaseStream` then call `StandardInput.Close()` for the EOF signal `host-command-consumption` requires, and reproduce `environment-replace-semantics` by calling `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `Environment` (since `ProcessStartInfo.EnvironmentVariables` starts pre-populated with the parent process's variables, the opposite of the source's replace-when-non-empty default). Bound `Timeout` with a `CancellationTokenSource` (`CancelAfter(Timeout)`) passed to both `SendAsync` and the process wait, rather than porting the source's custom `withWallClockBudget` race, since .NET's cancellation tokens already provide an equivalent wall-clock bound; note that `HttpClient.Timeout` alone is not a substitute, because — like `URLRequest.timeoutInterval` in `dual-purpose-timeout` — it is a per-operation timeout that a `CancellationTokenSource` bounds independently of how much data has already streamed.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIRequestSpec.swift` |

## Design Decisions

**Decision**: `AIRequestSpec` validates none of its constructor arguments — an out-of-range `timeout`, a nonexistent `executableURL`, or an empty `headers`/`environment` dictionary are all accepted without complaint.
**Rationale**: The type's entire job is to describe a request, not to judge one; validating `timeout` in particular would require this type to know how its one consumer (`withWallClockBudget`, called from `PluginTransport.run(spec:plugin:)`) interprets each boundary value (`NaN` → no budget, at/above roughly a year → no budget, at/below zero → immediate expiry — see `WallClockBudget.swift`'s documented policy), which is a decision that belongs to the consumer, not to the value it consumes.
**Approved**: pending

**Decision**: A `.command` transport's `environment` replaces the child process's entire environment when non-empty, rather than merging with the host process's own environment.
**Rationale**: `PluginTransport.swift` states this explicitly (`environmentPolicy: .replace`) as matching prior `Process`-based behavior, and frames a plugin handing over a minimal environment as "isolating its child on purpose." A plugin that wants any host-inherited variable (most commonly `PATH`) available to its child, as `ClaudeLocalPlugin` does, MUST include it itself rather than relying on inheritance.
**Approved**: pending

**Decision**: `timeout` on an `.http`-transport instance simultaneously governs the request's overall wall-clock budget and `URLRequest`'s idle `timeoutInterval`.
**Rationale**: `PluginTransport.runHTTP` passes `spec.timeout` to `URLRequest(url:timeoutInterval:)` in addition to wrapping the whole call in `withWallClockBudget(spec.timeout)`, even though the two express different guarantees — one bounds total elapsed time, the other resets on every received byte. `AIRequestSpec` exposes only one `timeout` field for both, so a value chosen to satisfy one semantics also applies to the other; there is no way, from this type alone, to give the two different bounds.
**Approved**: pending

**Decision**: `Method` declares a `.get` case, but no plugin under `packages/apple/AIPlugins/` currently constructs an `AIRequestSpec` with `method: .get`.
**Rationale**: Every current provider plugin (`ClaudeAPI`, `Google`, `OpenAI`, `OpenAICompatible`) issues its chat request as an HTTP POST with a JSON body, so `.get` is present for completeness and for a future or third-party plugin whose provider expects a GET request, not because any shipped code exercises it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`separation-of-concerns` passes because the type carries only a description of a request and performs no networking or process work itself (`description-only-contract`). `test-pyramid` passes on unit-test coverage alone (`AIPluginKitTests.swift`) — appropriate for a pure value type with no integration surface of its own. `input-sanitization` is partial because, per `no-input-validation`, this type accepts an unconstrained `timeout` (including `NaN` and negative values) and an unconstrained `executableURL`/`environment` without any check at construction time; the open question of whether that should ever be validated here rather than downstream is recorded above under `no-input-validation` and in the first Design Decision.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
