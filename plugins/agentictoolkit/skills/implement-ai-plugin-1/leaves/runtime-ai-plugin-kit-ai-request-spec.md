<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-request-spec · source: ai-plugin-runtime-ai-plugin-kit-ai-request-spec.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-request-spec#<slug>`):

- `sendable-conformance` MUST
- `value-type-semantics` MUST
- `mutable-fields` MUST
- `exactly-one-transport` MUST
- `http-transport-fields` MUST
- `command-transport-fields` MUST
- `method-cases` MUST
- `timeout-field` MUST
- `designated-initializer` MUST
- `http-convenience-constructor` MUST
- `command-convenience-constructor` MUST
- `non-throwing-construction` MUST
- `no-input-validation` MUST
- `description-only-contract` MUST
- `no-persistence` MUST
- `environment-replace-semantics` MUST
- `dual-purpose-timeout` MUST
- `data-handled` MAY — headers, body, stdin, and environment MAY each carry a credential a plugin has embedded into the request description — …
- `storage` MUST — AIRequestSpec.swift defines no storage of its own and MUST NOT persist any field to disk or any other durable store; …

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

## Privacy

- **Data handled**: `headers`, `body`, `stdin`, and `environment` MAY each carry a credential a plugin has embedded into the request description — for example `OpenAIPlugin` places an API key into an HTTP header, and `ClaudeLocalPlugin` places the full process environment (which MAY contain secrets a shell session has exported) into a `.command` spec's `environment` (`ClaudeLocalPlugin.swift`). `AIRequestSpec.swift` itself has no knowledge of which fields hold a secret; it stores whatever `Data` or dictionary value it is given.
- **Storage**: `AIRequestSpec.swift` defines no storage of its own and MUST NOT persist any field to disk or any other durable store; per `no-persistence`, an instance exists only as long as the plugin and host both hold a reference to it during one chat turn.
- **Transmission**: `AIRequestSpec` never transmits data itself; its fields describe what the host's transport (`PluginTransport`) will send over HTTP or write to a subprocess's stdin, per `host-http-consumption` and `host-command-consumption`.
- **Violation handling**: Out of scope for this type — detecting or reacting to a leaked or invalid credential is the responsibility of the plugin that built the spec and the host's transport and secret-storage layers; `AIRequestSpec.swift` performs no inspection of its own field values.

