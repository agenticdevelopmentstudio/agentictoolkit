<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-request-spec--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-request-spec.md -->

# AIRequestSpec

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-request-spec--edge-cases#<slug>`):

- `null-empty-input` MUST — headers: [:], body: nil, arguments: [], stdin: nil, and environment: [:] are each that field's own documented default …
- `concurrent-access` MAY — Because AIRequestSpec is a Sendable value type, a single instance MAY be read or copied concurrently from multiple …

## Edge Cases

- **Null/empty input**: `headers: [:]`, `body: nil`, `arguments: []`, `stdin: nil`, and `environment: [:]` are each that field's own documented default and MUST be accepted as ordinary, valid values, not as an error condition. An empty `environment` MUST leave the child process inheriting the host's environment, per `environment-replace-semantics`.
- **Boundary values**: `timeout` accepts any `TimeInterval`, including `0`, a negative value, `.nan`, and `.infinity`; `AIRequestSpec` itself imposes no minimum, maximum, or validity constraint on `timeout` (per `no-input-validation`). What each of those boundary values means once the host consumes it is defined entirely outside this type, by the request's one consumer.
- **Concurrent access**: Because `AIRequestSpec` is a `Sendable` value type, a single instance MAY be read or copied concurrently from multiple tasks without synchronization, since each concurrent holder either owns an independent copy or observes an immutable snapshot at the point it was captured. Concurrent *mutation* of one shared mutable binding to an `AIRequestSpec` (e.g., a `var` stored on a class) is not a concern this type resolves; it is an ordinary Swift shared-mutable-state hazard no different from any other `Sendable` struct stored that way, and `AIRequestSpec.swift` defines no such shared binding itself.
- **Error states**: No operation `AIRequestSpec.swift` defines (its initializer or either static constructor) can fail — none is `throws`. A failure to actually perform the described request (an unreachable host, a non-2xx HTTP status, a non-zero subprocess exit) is reported by the host's transport layer after this type has already handed back a value, never by `AIRequestSpec` itself.
- **Offline/disconnected state**: `AIRequestSpec.swift` performs no I/O and so never observes network connectivity; connectivity loss during the request the instance describes is entirely the concern of the host transport that consumes the instance, not of this type.
- **Missing file or unreachable server**: An `executableURL` that names a file that does not exist, or a `url` whose host is unreachable, is accepted unchanged by every initializer and constructor this type defines; the resulting failure surfaces only when the host later attempts to launch the process or open the connection, per the doc comment's "the host owns the transport". This mirrors the sibling `AIPlugin` protocol's own contract that such failures are "never observed inside" the plugin's methods.
- **Cancellation and timeout**: `AIRequestSpec`'s own initializer and constructors are synchronous and return immediately; they have no cancellation or timeout point of their own. The `timeout` value they carry is enforced, and any in-flight request is cancelled, only by the host's transport layer once it begins executing the described `Transport` — never by this type.
