<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-inference-guard--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-local-inference-guard.md -->

# LocalInferenceGuard

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-inference-guard--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty model or baseURL string is not special-cased by verdict; it is forwarded to catalog.sizeBytes(model:baseURL:), …
- `boundary-values` MUST — A deadline of exactly 0 or negative MUST be clamped to a zero-duration timer rather than crash (MUST, see …
- `concurrent-access` MUST — Concurrent runExclusive callers on one instance MUST be serialized to at most one running operation at a time, in FIFO …
- `error-states` MUST — If catalog.sizeBytes cannot determine a size (an unreachable or non-ollama local server), verdict treats that …
- `cancellation-and-timeouts` MUST — A waiter cancelled while parked MUST throw CancellationError from acquire() without ever running operation (MUST, see …

## Edge Cases

- **Null and empty input**: An empty `model` or `baseURL` string is not
  special-cased by `verdict`; it is forwarded to
  `catalog.sizeBytes(model:baseURL:)`, which is expected to yield `nil`
  (unknown size), so `verdict` MUST fall through to the unknown-size,
  fail-open path exactly as for any other unrecognized model (MUST). A
  `settings` closure that returns `nil` for both threshold keys MUST fall
  back to the documented 25%/50% defaults (MUST, see
  `threshold-fallback-on-missing-or-invalid`).
- **Boundary values**: A `deadline` of exactly `0` or negative MUST be
  clamped to a zero-duration timer rather than crash (MUST, see
  `deadline-clamped-to-nonnegative`). Because the deferred-reason message is
  built with `Int(deadline)` (truncation toward zero), any `deadline` under
  one second (e.g. the test's `0.1`) reads as `"...its 0s deadline..."` in
  the thrown reason string — a direct, undocumented-elsewhere consequence of
  `Int(Double)` truncation that this recipe records rather than idealizes.
  `warnPct`/`blockPct` values read from `settings` are forwarded to
  `ModelFitPolicy.verdict` unclamped; `LocalInferenceGuard.swift` itself
  performs no range validation (e.g. rejecting a negative or >100 percentage)
  on these values.
- **Concurrent access**: Concurrent `runExclusive` callers on one instance
  MUST be serialized to at most one running operation at a time, in FIFO
  admission order (MUST, see `mutual-exclusion`, `fifo-admission-order`).
  `verdict` and `pressureVerdict` are ordinary actor methods that do not
  touch `busy`/`waiters`, so they MUST remain callable, and MUST be able to
  complete, at any time — including while another call holds the exclusive
  lock (MUST, see `verdict-independent-of-exclusive-lock`). Calling
  `runExclusive` reentrantly on the same instance from within an operation it
  is already running for is not detected and deadlocks with no time bound,
  since the deadline only covers time spent running a granted `operation`,
  never time spent waiting inside `acquire()` (SHOULD NOT, see
  `no-reentrant-acquisition`).
- **Error states**: If `catalog.sizeBytes` cannot determine a size (an
  unreachable or non-ollama local server), `verdict` treats that identically
  to a model it has never seen — `nil` diskBytes, fail-open under normal
  pressure (MUST, see `unknown-size-fail-open`). If `operation` inside
  `runExclusive` throws before its deadline elapses, that exact error MUST
  propagate to the caller and the deadline timer MUST be cancelled without
  effect (MUST, see `operation-result-propagation`).
- **Offline or disconnected state**: `LocalInferenceGuard.swift` makes no
  network call of its own; an unreachable local model server is observed
  only indirectly, as `catalog.sizeBytes` returning `nil`, and is handled
  identically to any other unknown-size case above. `verdict` itself declares
  no `throws` and is never cancellation-checked, so if the calling task is
  cancelled while `verdict` awaits `catalog.sizeBytes`, `verdict` still
  completes and returns an ordinary `ModelFitPolicy.Verdict` (typically
  `.allow`) rather than raising `CancellationError` — this is a direct
  consequence of `verdict`'s non-throwing signature, not a bug.
- **Cancellation and timeouts**: A waiter cancelled while parked MUST throw
  `CancellationError` from `acquire()` without ever running `operation`
  (MUST, see `parked-cancellation-throws`). An operation that exceeds its
  `deadline` MUST be cancelled and reported as `AIGuardError.deferred`, and
  the lock MUST still be handed off to the next waiter afterward (MUST, see
  `deadline-enforced-per-operation`, `deadline-cancellation-preserves-
  handoff`). A caller's own task cancellation, checked once immediately after
  `acquire()` succeeds, MUST prevent `operation` from ever running for that
  call (MUST, see `post-acquire-cancellation-check`).
- **Missing file or unreachable server**: Not directly observable inside
  `LocalInferenceGuard.swift` — a missing local model file or an unreachable
  server surfaces only as `catalog.sizeBytes` returning `nil`, handled as
  described under Error states and Offline/disconnected state above.
