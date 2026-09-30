<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin.md -->

# AIPlugin

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--edge-cases#<slug>`):

- `empty-or-minimal-context` MUST — An AIChatContext whose messages is empty or whose config has no entries is not special-cased by this protocol; …
- `concurrent-access` MUST — Two tasks calling buildRequest(_:), buildValidationRequest(config:), or describeError(status:body:) on the same plugin …
- `error-states` MUST — buildRequest(_:) MUST throw rather than return a partially built AIRequestSpec when it cannot construct a valid request …
- `cancellation-and-timeouts` MUST — buildRequest(_:) and makeDecoder() are synchronous, non-async calls that return immediately once invoked; they MUST NOT …
- `missing-file-or-unreachable-server` MUST — buildRequest(_:) and makeDecoder() MUST NOT themselves open a file, socket, or process — a missing executable path or …

## Edge Cases

- **Empty or minimal context**: An `AIChatContext` whose `messages` is empty or whose `config` has no entries is not special-cased by this protocol; `buildRequest(_:)` MUST throw when it cannot proceed with what it was given, per the general "insufficient context" contract (`AIPlugin.swift`). Whether an empty `messages` array specifically counts as "insufficient" is left to each conforming type.
- **Boundary values**: Not applicable to `AIPlugin.swift` itself — numeric bounds such as `AIChatContext.maxTokens` and `AIRequestSpec.timeout` are owned by those sibling types, not by this protocol, which imposes no numeric constraint of its own.
- **Concurrent access**: Two tasks calling `buildRequest(_:)`, `buildValidationRequest(config:)`, or `describeError(status:body:)` on the same plugin instance concurrently MUST both complete correctly (MUST); `Sendable` conformance is the only concurrency guarantee this protocol supplies, and a conforming type's own internal mutable state is its own responsibility to protect.
- **Error states**: `buildRequest(_:)` MUST throw rather than return a partially built `AIRequestSpec` when it cannot construct a valid request (MUST). `describeError(status:body:)` MUST return `nil` rather than throw or crash when it cannot interpret the given `status`/`body` (MUST, per the never-throwing default extension).
- **Offline / disconnected state**: Not applicable in the direct sense — `buildRequest(_:)`, `makeDecoder()`, and `describeError(status:body:)` perform no I/O and so never observe connectivity themselves; an unreachable host or dropped connection surfaces later, to the host's transport layer, and reaches this protocol only indirectly as the `status`/`body` `describeError` is given after the attempt already failed.
- **Cancellation and timeouts**: `buildRequest(_:)` and `makeDecoder()` are synchronous, non-`async` calls that return immediately once invoked; they MUST NOT be treated as having a cancellation or timeout point of their own (SHOULD NOT be assumed cancellable mid-call). Cancelling or timing out the request the returned `AIRequestSpec` describes is the host's responsibility once the plugin has handed the spec back, per "the host owns the transport."
- **Missing file or unreachable server**: `buildRequest(_:)` and `makeDecoder()` MUST NOT themselves open a file, socket, or process — a missing executable path or an unreachable server is never observed inside this protocol's methods; those failures occur only later, when the host executes the `AIRequestSpec` the plugin produced.
