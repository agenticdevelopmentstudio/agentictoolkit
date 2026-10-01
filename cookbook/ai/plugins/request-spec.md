---
id: 72829b3b-ce4a-4730-877f-da7b48e7b3dd
title: Request Specification
domain: agentictoolkit://cookbook/ai/plugins/request-spec
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The value type a plugin''s request-building operation returns: a
  fully-described HTTP or local-command request for one chat turn, plus a
  wall-clock timeout.'
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- transport
depends-on: []
related:
- agentictoolkit://cookbook/ai/plugins/ai-plugin
references: []
approved-by: ''
approved-date: ''
---

# Request Specification

## Overview

The request specification is the value type a plugin's request-building
operation returns: a fully-described request for one chat turn. It carries
only a description of how the host should reach the provider — over HTTP or
by running a local command — plus a wall-clock timeout; it performs no
networking or process work itself. The plugin contributes the description;
the plugin transport is the sole consumer that turns the description into an
actual HTTP request or a subprocess. The split between transport kinds lives
in this type's transport-kind field, not in the plugin's identity, so every
plugin has the same "describe a request, decode the bytes" shape.

## Behavioral Requirements

- **concurrent-share-safety**: The request specification type, its nested
  method kind, and its nested transport kind MUST all be safe to share
  across concurrent execution contexts without synchronization, so a value
  returned by the request-building operation MAY be handed from the
  plugin's own execution context to the host's transport logic without a
  data-race diagnostic.
- **value-type-semantics**: The request specification MUST have value
  semantics, not reference semantics, so assigning or passing an instance
  MUST copy it: mutating one binding's transport-kind or timeout MUST NOT
  affect any other binding holding a separately-assigned copy of the same
  instance.
- **mutable-fields**: The transport-kind and timeout fields MUST be mutable,
  so a caller MAY construct an instance and then reassign either field
  before handing the value to the host.
- **exactly-one-transport**: An instance MUST describe exactly one way to
  reach the provider, held in its single transport-kind field; the
  transport kind MUST have two mutually exclusive cases, so a single
  instance MUST NOT simultaneously describe an HTTP request and a subprocess
  command.
- **http-transport-fields**: The HTTP transport case MUST carry exactly a
  method, a URL, a headers map, and an optional body.
- **command-transport-fields**: The command transport case MUST carry
  exactly an executable location, an arguments list, an optional
  standard-input payload, and an environment map.
- **method-cases**: The method kind MUST expose exactly two cases: GET (wire
  value "GET") and POST (wire value "POST").
- **timeout-field**: An instance MUST carry a timeout representing the
  wall-clock budget for the whole request before the host cancels it.
- **designated-initializer**: Constructing an instance from a transport kind
  and a timeout MUST be the sole designated way to build one, MUST accept a
  required transport kind, MUST default the timeout to 120 when the caller
  omits it, and MUST be synchronous and non-failing.
- **http-convenience-constructor**: The HTTP convenience constructor MUST
  require only a URL and MUST default the method to POST, the headers to an
  empty map, the body to none, and the timeout to 120, returning an instance
  whose transport kind is HTTP with exactly the given (or defaulted) values.
- **command-convenience-constructor**: The command convenience constructor
  MUST require only an executable location and MUST default the arguments
  to an empty list, the standard-input payload to none, the environment to
  an empty map, and the timeout to 120, returning an instance whose
  transport kind is command with exactly the given (or defaulted) values.
- **non-throwing-construction**: No constructor this type defines MAY throw
  or fail; every path from valid argument values to an instance MUST succeed
  synchronously.
- **no-input-validation**: Neither the designated constructor nor either
  convenience constructor MUST validate its arguments; any timeout value
  (including zero, negative, not-a-number, or infinite), any URL, and any
  string map or byte payload the caller supplies MUST be accepted and stored
  unchanged. This is a deliberate design, not a gap: interpreting an
  out-of-range timeout is left entirely to the request's one consumer (see
  Design Decisions).
- **description-only-contract**: A value of this type MUST NOT itself
  perform networking, spawn a process, or produce any other side effect; the
  plugin contributes only the description, the host owns the transport.
  Constructing or holding a request specification MUST have no observable
  effect beyond the value itself.
- **no-persistence**: A request specification instance MUST NOT be cached,
  reused across chat turns, or written to any store by this type; the
  request-building operation is documented to build a fresh spec from the
  current chat request context for one chat turn, and this type defines no
  storage of its own.
- **host-http-consumption**: When the host executes an HTTP-transport
  instance, the method becomes the resulting request's HTTP method, each
  header entry is applied as one HTTP header field, and the body becomes the
  request body — this is observable only through the request's sole
  consumer, the plugin transport's HTTP path, which is cited here because it
  is the only place these fields' meaning is observable.
- **host-command-consumption**: When the host executes a command-transport
  instance, the executable location and arguments describe the child
  process, the standard-input payload (if given) is written to the child and
  then the child's input is closed to signal end-of-file, and the child's
  output is streamed to the plugin's decoder — this is observable only
  through the request's sole consumer, the plugin transport's command path.
- **environment-replace-semantics**: A non-empty environment on a
  command-transport instance MUST become the entire environment of the
  spawned child process, replacing rather than merging with the host
  process's own environment; an empty environment MUST leave the child
  inheriting the host's environment unchanged. This is non-obvious from the
  field's name alone, so a plugin that wants the host's search-path variable
  (or any other inherited variable) available to its child MUST include it
  explicitly, as one local-command plugin does by starting from the current
  process's environment before appending search paths.
- **dual-purpose-timeout**: For an HTTP-transport instance, the timeout MUST
  be used both as the wall-clock budget racing the whole request and,
  independently, as the underlying request's own idle-timeout value — a
  timeout that resets on every received byte rather than bounding the whole
  transfer. A single timeout value therefore governs two different timeout
  semantics in the one consumer that reads it.

## Appearance

Not applicable — this is a request-description value type, not a visual
component.

## States

Not applicable — this is a request-description value type, not a visual
component.

## Accessibility

Not applicable — this is a request-description value type, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-request-spec-001 | http-convenience-constructor, designated-initializer | Build an HTTP request specification giving only a URL. | The timeout defaults to 120; the transport kind is HTTP with method POST, the given URL, an empty headers map, and no body. |
| ai-request-spec-002 | command-convenience-constructor | Build a command request specification giving an executable location, arguments ["echo", "hi"], and a standard-input payload of "in". | The transport kind is command with the given executable location, arguments ["echo", "hi"], standard-input payload "in", and an empty environment map; the timeout defaults to 120. |
| ai-request-spec-003 | http-transport-fields, http-convenience-constructor | A plugin's request-building operation, given a chat request context whose configuration contains an API key of "secret" and a model of "test-model", builds an HTTP request specification with a URL, a header entry mapping a key-identifying header name to "secret", and a body containing "test-model". | The returned specification's transport kind is HTTP with method POST, the given URL, the given header entry, and the given body. |
| ai-request-spec-004 | value-type-semantics, mutable-fields | Build an HTTP request specification and assign it to one binding, assign a second binding from the first, then change the second binding's timeout to 5. | The first binding's timeout remains 120 (unchanged); the second binding's timeout is 5; the two bindings do not share mutable state. |
| ai-request-spec-005 | command-convenience-constructor, timeout-field | Build a command request specification giving an executable location and a timeout of 30 (overriding the default). | The specification's timeout is 30, overriding the constructor's own default of 120. |
| ai-request-spec-006 | method-cases | Read the wire value of the GET case and the POST case of the method kind. | "GET" and "POST" respectively. |
| ai-request-spec-007 | environment-replace-semantics | A local-command plugin's request-building operation builds its environment map by starting from the current process's environment, then overwrites only the search-path entry with a joined search-path string, and returns a command-transport specification carrying that environment map. | The returned specification's command transport case carries a non-empty environment map containing every key from the current process's environment plus a rewritten search-path entry; per environment-replace-semantics, the host uses this map as the child's entire environment rather than merging it with anything else. |
| ai-request-spec-008 | no-input-validation | Construct a request specification with timeout not-a-number, then construct another with timeout -5. | Both constructions succeed and return a value whose timeout is exactly not-a-number and -5 respectively; neither the designated constructor nor either convenience constructor throws, clamps, or otherwise rejects the value. |

## Edge Cases

- **Null/empty input**: An empty headers map, no body, an empty arguments
  list, no standard-input payload, and an empty environment map are each
  that field's own documented default and MUST be accepted as ordinary,
  valid values, not as an error condition. An empty environment MUST leave
  the child process inheriting the host's environment, per
  environment-replace-semantics.
- **Boundary values**: timeout accepts any numeric value, including 0, a
  negative value, not-a-number, and infinite; the request specification
  itself imposes no minimum, maximum, or validity constraint on timeout (per
  no-input-validation). What each of those boundary values means once the
  host consumes it is defined entirely outside this type, by the request's
  one consumer.
- **Concurrent access**: Because the request specification is safe to share
  across concurrent execution contexts, a single instance MAY be read or
  copied concurrently from multiple execution contexts without
  synchronization, since each concurrent holder either owns an independent
  copy or observes an immutable snapshot at the point it was captured.
  Concurrent mutation of one shared mutable binding to a request
  specification (e.g., a mutable field stored on a reference type
  elsewhere) is not a concern this type resolves; it is an ordinary
  shared-mutable-state hazard no different from any other value safe to
  share this way, and this type defines no such shared binding itself.
- **Error states**: No operation this type defines (its constructor or
  either convenience constructor) can fail. A failure to actually perform
  the described request (an unreachable host, a non-2xx HTTP status, a
  non-zero subprocess exit) is reported by the host's transport layer after
  this type has already handed back a value, never by the request
  specification itself.
- **Offline/disconnected state**: This type performs no I/O and so never
  observes network connectivity; connectivity loss during the request the
  instance describes is entirely the concern of the host transport that
  consumes the instance, not of this type.
- **Missing file or unreachable server**: An executable location that names
  a file that does not exist, or a URL whose host is unreachable, is
  accepted unchanged by every constructor this type defines; the resulting
  failure surfaces only when the host later attempts to launch the process
  or open the connection, since the host owns the transport. This mirrors
  the sibling plugin recipe's own contract that such failures are never
  observed inside the plugin's own operations.
- **Cancellation and timeout**: This type's constructors are synchronous and
  return immediately; they have no cancellation or timeout point of their
  own. The timeout value they carry is enforced, and any in-flight request
  is cancelled, only by the host's transport layer once it begins executing
  the described transport kind — never by this type.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Transport kind | transport-kind value | none — required | The HTTP or command description of how to reach the provider for this request. |
| Timeout | numeric duration | 120 | Wall-clock budget for the whole request before the host cancels it. |
| Method | method value | POST | HTTP method for an HTTP-transport request. |
| Headers | text-keyed map of text | empty | HTTP header fields applied to the request. |
| Body | optional byte payload | none | HTTP request body. |
| Executable location | location | none — required | Path to the executable the host spawns as a subprocess. |
| Arguments | list of text | empty | Command-line arguments passed to the subprocess. |
| Standard input | optional byte payload | none | Bytes written to the subprocess's standard input before it is closed. |
| Environment | text-keyed map of text | empty | Environment variables for the subprocess; a non-empty value replaces the host's own environment for the child (see environment-replace-semantics). |

This type defines no environment variable or settings key of its own; every
value above arrives as a caller-supplied constructor argument.

## Deep Linking

Not applicable: this type defines no URL scheme, route, or navigation
destination; the address it carries reaches an AI provider's HTTP endpoint,
not an app deep link.

## Localization

Not applicable: this type contains no string literal intended for display;
headers, body, arguments, standard input, and environment carry
caller-supplied, non-display data.

## Accessibility Options

Not applicable: this type presents no UI, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this type contains no feature-flag or settings-key reference
of its own.

## Analytics

Not applicable: this type contains no analytics or event-tracking call.

## Privacy

- **Data handled**: Headers, body, standard input, and environment MAY each
  carry a credential a plugin has embedded into the request description —
  for example one provider plugin places an API key into an HTTP header,
  and a local-command plugin places the full process environment (which MAY
  contain secrets a shell session has exported) into a command
  specification's environment. This type itself has no knowledge of which
  fields hold a secret; it stores whatever byte payload or map value it is
  given.
- **Storage**: This type defines no storage of its own and MUST NOT persist
  any field to disk or any other durable store; per no-persistence, an
  instance exists only as long as the plugin and host both hold a reference
  to it during one chat turn.
- **Transmission**: A request specification never transmits data itself;
  its fields describe what the host's transport will send over HTTP or
  write to a subprocess's standard input, per host-http-consumption and
  host-command-consumption.
- **Violation handling**: Out of scope for this type — detecting or
  reacting to a leaked or invalid credential is the responsibility of the
  plugin that built the spec and the host's transport and secret-storage
  layers; this type performs no inspection of its own field values.

## Logging

Not applicable: this type contains no logging call; it is a pure data type
with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIRequestSpec.swift`, consumed by `PluginTransport.swift` (same directory) and returned by every conforming `AIPlugin.buildRequest(_:)` implementation under `packages/apple/AIPlugins/*/`. Nothing here is SwiftUI-specific; a SwiftUI-based host reads and executes an `AIRequestSpec` exactly as an AppKit one does, through `PluginTransport`. Concretely, the type is `public struct AIRequestSpec: Sendable` with `public enum Method: String, Sendable` and `public enum Transport: Sendable` nested inside it — the concurrent-share-safety requirement above is this `Sendable` conformance, verified by the compiler at compile time rather than by any runtime check.
- **Compose**: Model the two-case `Transport` as a Kotlin `sealed interface AiTransport` with `data class Http(val method: AiMethod, val url: String, val headers: Map<String, String>, val body: ByteArray?)` and `data class Command(val executablePath: String, val arguments: List<String>, val stdin: ByteArray?, val environment: Map<String, String>)`, and wrap it in `data class AiRequestSpec(val transport: AiTransport, val timeoutMillis: Long = 120_000)`. `AiMethod` is a two-case `enum class` (`GET`, `POST`). Android has no first-class notion of spawning an arbitrary local executable the way `.command` does; a Compose/Android port would typically omit or stub the command case unless the host environment specifically supports subprocess execution.
- **React/Web**: Model `Transport` as a discriminated union — `{ kind: "http", method: "GET" | "POST", url: string, headers: Record<string, string>, body?: Uint8Array } | { kind: "command", executablePath: string, arguments: string[], stdin?: Uint8Array, environment: Record<string, string> }` — inside `interface AIRequestSpec { transport: Transport; timeout: number }` (milliseconds, defaulting to `120_000`). A browser host has no subprocess primitive at all; the `command` case only makes sense for a Node.js or Electron host, which would use `child_process.spawn` in place of `PluginTransport.runCommand`, writing `stdin` and calling `stdin.end()` for EOF, matching `host-command-consumption`. Use the `fetch` API's `AbortController`, tied to a `setTimeout(timeout)`, in place of Swift's wall-clock budget race.
- **AppKit / UIKit**: Identical to the SwiftUI note — this type is UI-framework-agnostic; only the host application embedding `AIPluginKit` differs, never this data shape.
- **WinUI 3**: Model the contract as an immutable-by-convention record on the .NET / Windows App SDK: `public sealed record AiRequestSpec(AiTransport Transport, TimeSpan Timeout = default)` where a `default` `TimeSpan` is treated by the host as "use the 120-second default" (since C# cannot default a record parameter to a non-constant `TimeSpan.FromSeconds(120)` inline, the host or a factory method substitutes it, mirroring the source). Represent `Transport` as an `abstract record AiTransport` with two derived records: `HttpTransport(HttpMethod Method, Uri Url, IReadOnlyDictionary<string, string> Headers, byte[]? Body) : AiTransport` — reusing `System.Net.Http.HttpMethod.Get`/`.Post` rather than a custom enum — and `CommandTransport(string ExecutablePath, IReadOnlyList<string> Arguments, byte[]? Stdin, IReadOnlyDictionary<string, string> Environment) : AiTransport`. A WinUI 3 host executes `HttpTransport` with `System.Net.Http.HttpClient.SendAsync` (streaming the response via `HttpCompletionOption.ResponseHeadersRead`) and `CommandTransport` with `System.Diagnostics.Process`/`ProcessStartInfo`: set `RedirectStandardInput`/`RedirectStandardOutput` to `true`, write `Stdin` to `StandardInput.BaseStream` then call `StandardInput.Close()` for the EOF signal `host-command-consumption` requires, and reproduce `environment-replace-semantics` by calling `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `Environment` (since `ProcessStartInfo.EnvironmentVariables` starts pre-populated with the parent process's variables, the opposite of the source's replace-when-non-empty default). Bound `Timeout` with a `CancellationTokenSource` (`CancelAfter(Timeout)`) passed to both `SendAsync` and the process wait, rather than porting the source's custom `withWallClockBudget` race, since .NET's cancellation tokens already provide an equivalent wall-clock bound; note that `HttpClient.Timeout` alone is not a substitute, because — like `URLRequest.timeoutInterval` in `dual-purpose-timeout` — it is a per-operation timeout that a `CancellationTokenSource` bounds independently of how much data has already streamed.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIRequestSpec.swift` |

## Design Decisions

**Decision**: `AIRequestSpec` validates none of its constructor arguments — an out-of-range `timeout`, a nonexistent `executableURL`, or an empty `headers`/`environment` dictionary are all accepted without complaint. (Apple platform implementation.)
**Rationale**: The type's entire job is to describe a request, not to judge one; validating `timeout` in particular would require this type to know how its one consumer (`withWallClockBudget`, called from `PluginTransport.run(spec:plugin:)`) interprets each boundary value (`NaN` → no budget, at/above roughly a year → no budget, at/below zero → immediate expiry — see `WallClockBudget.swift`'s documented policy), which is a decision that belongs to the consumer, not to the value it consumes.
**Approved**: pending

**Decision**: A `.command` transport's `environment` replaces the child process's entire environment when non-empty, rather than merging with the host process's own environment. (Apple platform implementation.)
**Rationale**: `PluginTransport.swift` states this explicitly (`environmentPolicy: .replace`) as matching prior `Process`-based behavior, and frames a plugin handing over a minimal environment as "isolating its child on purpose." A plugin that wants any host-inherited variable (most commonly `PATH`) available to its child, as `ClaudeLocalPlugin` does, MUST include it itself rather than relying on inheritance.
**Approved**: pending

**Decision**: `timeout` on an `.http`-transport instance simultaneously governs the request's overall wall-clock budget and `URLRequest`'s idle `timeoutInterval`. (Apple platform implementation.)
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
