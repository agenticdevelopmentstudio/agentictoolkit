<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-inference-guard · source: ai-plugin-runtime-ai-plugin-kit-local-inference-guard.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-inference-guard#<slug>`):

- `guard-refusal-cases` MUST
- `guard-refusal-description` MUST
- `guard-refusal-non-transport` MUST
- `shared-default-instance` MUST
- `injectable-dependencies` MUST
- `actor-isolated-mutable-state` MUST
- `threshold-settings-override` MUST
- `threshold-fallback-on-missing-or-invalid` MUST
- `disk-size-lookup-delegation` MUST
- `unknown-size-fail-open` MUST
- `warn-tier-log-emission` MUST
- `warn-tier-log-scope` MUST
- `verdict-computation-delegation` MUST
- `verdict-independent-of-exclusive-lock` MUST
- `pressure-only-recheck` MUST
- `mutual-exclusion` MUST
- `fifo-admission-order` MUST
- `uncontended-fast-path` MUST
- `direct-handoff-without-busy-gap` MUST
- `post-acquire-cancellation-check` MUST
- `release-on-every-exit-path` MUST
- `parked-cancellation-throws` MUST
- `handoff-race-cancellation-noop` MUST
- `default-deadline-value` MUST
- `deadline-enforced-per-operation` MUST
- `deadline-clamped-to-nonnegative` MUST
- `deadline-cancellation-preserves-handoff` MUST
- `operation-result-propagation` MUST
- `sendable-operation-and-result` MUST
- `waiter-count-internal-visibility` MUST
- `no-reentrant-acquisition` SHOULD

# LocalInferenceGuard

## Overview

`LocalInferenceGuard` is the actor-isolated memory guard `AIPluginKit`'s
`DaemonAIChat` consults before dispatching a chat request to a loopback
("local") model server. Given a model name and base URL,
`verdict(model:baseURL:settings:)` asks `LocalModelCatalog` for the model's
on-disk size, asks the injected `SystemMemoryMonitoring` for the machine's
physical RAM and latched memory-pressure level, and returns a
`ModelFitPolicy.Verdict` (`.allow`, `.block(reason:)`, or
`.deferred(reason:)`). Independently of that verdict,
`runExclusive(deadline:_:)` serializes local inference process-wide behind a
single async mutex, so two host features that each trigger a local model load
(e.g. summaries and oversight) cannot do so at once; the mutex is a FIFO queue
of parked acquirers with direct-handoff release, and each exclusive run is
bounded by a wall-clock `deadline` (600s by default) after which the operation
is cancelled and the guard reports `AIGuardError.deferred`. `AIGuardError`
(`.blocked`/`.deferred`) is a distinct error type from `DaemonAIChat`'s own
`ChatError`: per the source's own comment, a guard refusal is "terminal for
this attempt" and must never be reinterpreted as a transport failure eligible
for the `claude -p` CLI fallback.

## Behavioral Requirements

- **guard-refusal-cases**: `AIGuardError` MUST provide exactly two cases,
  `.blocked(String)` and `.deferred(String)`, each carrying a human-readable
  reason string.
- **guard-refusal-description**: `AIGuardError.errorDescription` MUST return
  the associated reason string unchanged for both `.blocked` and `.deferred`.
- **guard-refusal-non-transport**: A guard refusal (`.blocked` or
  `.deferred`) MUST NOT be treated by a caller as a transport failure eligible
  for another provider path; per the doc comment, it is "Deliberately NOT a
  `DaemonAIChat.ChatError`... it must never cascade into the `claude -p`
  fallback."
- **shared-default-instance**: `LocalInferenceGuard.shared` MUST provide one
  process-wide default instance, constructed from the production dependencies
  `LocalModelCatalog.shared` and `SystemMemoryMonitor.shared`.
- **injectable-dependencies**: `init(catalog:memory:)` MUST accept a
  substitutable `LocalModelCatalog` and `any SystemMemoryMonitoring`, each
  defaulting to its production singleton, so a caller MAY construct a guard
  backed by fixed or fake behavior.
- **actor-isolated-mutable-state**: `LocalInferenceGuard` MUST be declared as
  an `actor`, so its mutable state (`busy`, `waiters`) is serialized by the
  actor's own executor rather than by a manual lock.
- **threshold-settings-override**: `verdict(model:baseURL:settings:)` MUST
  read the warn and block percentage thresholds from `settings` under
  `ModelFitPolicy.warnPctKey` and `ModelFitPolicy.blockPctKey` and MUST use
  the parsed integer when one is present.
- **threshold-fallback-on-missing-or-invalid**: `verdict` MUST fall back to
  `ModelFitPolicy.defaultWarnPct` (25) / `ModelFitPolicy.defaultBlockPct` (50)
  when `settings` returns `nil` for a threshold key, or returns a string that
  is not parseable as an `Int`.
- **disk-size-lookup-delegation**: `verdict` MUST obtain the candidate
  model's on-disk size by calling `catalog.sizeBytes(model:baseURL:)`, and
  MUST treat a `nil` result as "size unknown" rather than substituting a
  default size.
- **unknown-size-fail-open**: When the disk size is unknown (tier is `nil`),
  `verdict` MUST return `.allow` whenever the memory-pressure component alone
  would also allow — it MUST NOT block or defer solely because the size
  lookup failed.
- **warn-tier-log-emission**: When the computed tier is `.warn`, `verdict`
  MUST emit exactly one `notice`-level log via `Logger` (subsystem
  `com.agentic-cookbook.AIPluginKit`, category `LocalInferenceGuard`) naming
  the model and its estimated resident footprint, with `privacy: .public`.
- **warn-tier-log-scope**: `verdict` MUST NOT emit the warn-tier log for an
  `.ok` or `.block` tier, and MUST NOT emit it when the tier is `nil`
  (size unknown).
- **verdict-computation-delegation**: `verdict` MUST compute its returned
  `ModelFitPolicy.Verdict` by calling
  `ModelFitPolicy.verdict(model:diskBytes:physicalRAM:warnPct:blockPct:pressure:)`,
  passing the injected memory monitor's current `physicalRAM` and
  `pressureLevel` at the time of the call.
- **verdict-independent-of-exclusive-lock**: `verdict` MUST be callable, and
  MUST be able to complete, without acquiring or waiting on the
  `runExclusive` mutex — it reads and touches neither `busy` nor `waiters`.
- **pressure-only-recheck**: `pressureVerdict()` MUST return
  `ModelFitPolicy.pressureVerdict(memory.pressureLevel)`, evaluated fresh
  against the memory monitor's current pressure level rather than any value
  cached from a prior `verdict()` call, so it can be re-checked once inside a
  held lock's critical section.
- **mutual-exclusion**: `runExclusive(deadline:_:)` MUST guarantee that at
  most one `operation` closure is running at any instant across all
  concurrent callers of one `LocalInferenceGuard` instance.
- **fifo-admission-order**: Acquirers that begin waiting while the guard is
  busy MUST be granted ownership in the order they began waiting; a later
  arrival MUST NOT run its operation before an earlier, still-eligible
  waiter.
- **uncontended-fast-path**: A call to `runExclusive` made while no operation
  is running MUST proceed without parking — no continuation is created, and
  `busy` is set directly.
- **direct-handoff-without-busy-gap**: On completing an operation,
  `release()` MUST hand ownership directly to the head of the waiter queue
  when one exists, and `busy` MUST remain `true` throughout that handoff;
  `busy` MUST become `false` only when the waiter queue is empty at release
  time.
- **post-acquire-cancellation-check**: Immediately after `acquire()` returns
  and before `operation` is invoked, `runExclusive` MUST check the calling
  task's cancellation via `Task.checkCancellation()` and MUST throw
  `CancellationError` without ever invoking `operation` if the calling task
  was already cancelled.
- **release-on-every-exit-path**: `runExclusive` MUST call `release()`
  exactly once for every successful `acquire()`, whether `operation` returns
  normally, throws, the post-acquire cancellation check throws, or the
  deadline expires — via `defer`.
- **parked-cancellation-throws**: A waiter cancelled while still parked in
  the queue MUST be removed from the queue and MUST cause its `acquire()`
  call to throw `CancellationError`, without ever invoking `operation`.
- **handoff-race-cancellation-noop**: If a waiter's cancellation handler runs
  after `release()` has already removed that waiter from the queue and
  resumed it as the new owner, the cancellation handler MUST be a no-op; only
  that owner's own subsequent `Task.checkCancellation()` call MAY still throw
  and release the lock.
- **default-deadline-value**: `runExclusive` MUST apply
  `LocalInferenceGuard.defaultDeadline` (600 seconds) as the wall-clock bound
  on one operation when the caller supplies no `deadline` argument.
- **deadline-enforced-per-operation**: When `operation` has not completed
  before `deadline` elapses, `runExclusive` MUST cancel the operation's task
  and MUST throw `AIGuardError.deferred` naming the deadline in whole
  seconds, rather than continuing to wait or throwing a bare
  `CancellationError`.
- **deadline-clamped-to-nonnegative**: A `deadline` value less than or equal
  to zero MUST be treated as an immediate (zero-duration) timeout rather than
  producing a negative sleep duration.
- **deadline-cancellation-preserves-handoff**: When a deadline expiry cancels
  an operation, `release()` MUST still run afterward and hand the lock to the
  next waiter (if any), exactly as on a normal completion.
- **operation-result-propagation**: `runExclusive` MUST return `operation`'s
  value to the caller unchanged when it completes before the deadline, and
  MUST propagate any error `operation` throws unchanged (not wrapped) when it
  fails before the deadline.
- **sendable-operation-and-result**: `runExclusive<T: Sendable>` MUST require
  its `operation` closure to be `@Sendable` and its result type `T` to
  conform to `Sendable`, since `operation` runs inside a `Task` in a
  `withThrowingTaskGroup` racing concurrently against the deadline-timer
  task.
- **waiter-count-internal-visibility**: `waiterCount` MUST be visible only
  within the declaring module (no `public`/`private` modifier — Swift's
  default `internal`), so it functions as a test seam without becoming part
  of the type's public API.
- **no-reentrant-acquisition**: `runExclusive` SHOULD NOT be called again on
  the same `LocalInferenceGuard` instance from within an `operation` closure
  it is already running for, because the mutex provides no reentrancy
  detection and the nested call parks behind itself with no deadline covering
  the time spent waiting to acquire (only time spent running an already-
  granted `operation` is deadline-bound).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `catalog` (parameter to `init`) | `LocalModelCatalog` | `.shared` | Injectable model-size lookup; tests substitute a fixed or failing fetcher. |
| `memory` (parameter to `init`) | `any SystemMemoryMonitoring` | `SystemMemoryMonitor.shared` | Injectable RAM/pressure source; tests substitute a fixed value (e.g. `FixedMemory`). |
| `deadline` (parameter to `runExclusive`) | `TimeInterval` | `LocalInferenceGuard.defaultDeadline` (600) | Wall-clock bound on one exclusive operation's run. |
| `model`, `baseURL` (parameters to `verdict`) | `String`, `String` | none — required | Identify the candidate local model and its loopback server. |
| `settings` (parameter to `verdict`) | `ProviderSettingsReader` (`@Sendable (String) -> String?`) | none — required | Host-supplied reader for the `ai_guard_warn_pct` / `ai_guard_block_pct` override keys (declared on `ModelFitPolicy`, not this file). |
| `operation` (parameter to `runExclusive`) | `@escaping @Sendable () async throws -> T` | none — required | The local-inference work to run under the process-wide exclusive lock. |

`LocalInferenceGuard.swift` defines no environment variable of its own; the
two settings keys it reads (`ModelFitPolicy.warnPctKey`,
`ModelFitPolicy.blockPctKey`) are declared on the sibling `ModelFitPolicy`
type and reached only through the caller-supplied `settings` closure.

