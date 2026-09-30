<!-- leaf: implement-foundation/concurrency--part-2 · source: foundation-concurrency.md -->

# BlockingWork, KeyedDebouncer & PendingTeardowns — continued (part 2)

**Rules** (cite as `implement-foundation/concurrency--part-2#<slug>`):

- `blocking-queue-hop` MUST
- `blocking-qos-default` MUST
- `blocking-throwing-resume` MUST
- `blocking-nonthrowing-resume` MUST
- `blocking-sendable-boundary` MUST
- `blocking-not-a-cancellation-point` MUST
- `blocking-calls-run-independently` MUST
- `debouncer-mainactor-isolation` MUST
- `debouncer-key-constraint` MUST
- `debounce-window-default` MUST
- `retry-ceiling-default-and-floor` MUST
- `schedule-coalesces-latest` MUST
- `schedule-during-run-defers-timer` MUST
- `one-run-per-key` MUST
- `cross-key-concurrency` MUST
- `success-retires-entry` MUST
- `failure-keeps-entry-and-rearms` MUST
- `failure-callback-invoked-even-if-canceled` MUST
- `superseded-run-resets-backoff` MUST
- `retry-backoff-exponential-capped` MUST
- `cancel-drops-entry-without-running` MUST
- `cancel-during-run-not-resurrected` MUST
- `cancel-all-keys` MUST
- `cancellation-is-cooperative-only` MUST
- `flush-runs-now` MUST
- `flush-awaits-in-flight-run` MUST
- `flush-all-sequential-reports-still-failing` MUST
- `pending-membership-reflects-any-state` MUST
- `teardowns-mainactor-isolation` MUST
- `teardown-nonthrowing-closure` MUST
- `add-returns-immediately` MUST
- `add-tracks-handle-per-token` MUST
- `entry-self-removes-on-completion` MUST
- `drain-awaits-all-in-flight` MUST
- `drain-awaits-teardowns-added-during-drain` MUST
- `drain-on-empty-returns-immediately` MUST
- `in-flight-count-internal-visibility` MUST

## Behavioral Requirements

- **blocking-queue-hop**: `BlockingWork.run` (both overloads) MUST execute `work` on a GCD global queue (`DispatchQueue.global(qos:)`), never on the Swift concurrency cooperative thread pool that ordinary `Task`/`Task.detached` work shares (`BlockingWork.swift`).
- **blocking-qos-default**: Both `run` overloads MUST default their `qos` parameter to `.userInitiated` when the caller omits it.
- **blocking-throwing-resume**: The throwing overload MUST resume the caller with whatever value `work` returned, or rethrow whatever error `work` threw, via `continuation.resume(with: Result { try work() })`.
- **blocking-nonthrowing-resume**: The non-throwing overload MUST resume the caller with exactly the value `work` returned, with no error path.
- **blocking-sendable-boundary**: On both overloads, the generic result type `T` and the `work` closure itself MUST both be constrained to `Sendable`, because the value crosses a thread boundary once into the closure's execution context and once back out through the continuation.
- **blocking-not-a-cancellation-point**: `BlockingWork.run` MUST NOT observe or react to cancellation of the calling `Task` once `work` has been dispatched — the continuation resumes only when the synchronous `work` closure itself returns or throws, per the doc comment "nothing here can interrupt a synchronous call that is already running"; a caller needing bounded execution MUST give `work` its own deadline, the way `CommandRunner` does.
- **blocking-calls-run-independently**: Two or more concurrent calls to `BlockingWork.run` MUST run independently of one another with no shared state and no coordination between them — `BlockingWork` is a case-less `enum` holding no instance or static mutable state, so any number of calls MAY execute in parallel, each on whatever thread GCD's global queue grows to serve it.
- **debouncer-mainactor-isolation**: `KeyedDebouncer` MUST be declared `@MainActor` (`KeyedDebouncer.swift`), so every one of its methods and computed properties (`schedule`, `cancel`, `cancelAll`, `flush`, `flushAll`, `pendingKeys`, `isPending`) MUST run on, and only be callable from, the main actor.
- **debouncer-key-constraint**: `KeyedDebouncer`'s generic parameter `Key` MUST conform to `Hashable & Sendable`.
- **debounce-window-default**: `init` MUST default `debounce` to `.seconds(1)` when the caller omits it.
- **retry-ceiling-default-and-floor**: `init` MUST default `maximumRetryInterval` to `.seconds(30)` and MUST clamp the stored ceiling to be at least `debounce`, via `max(debounce, maximumRetryInterval)` — a caller passing a `maximumRetryInterval` smaller than `debounce` MUST NOT be rejected; the smaller value is silently raised to `debounce` instead.
- **schedule-coalesces-latest**: `schedule(key:_:)` MUST replace whatever work was previously scheduled for `key` with the new closure and MUST restart the debounce window from the moment of the call — only the most recently scheduled closure for a key is ever run, never a queue of every call.
- **schedule-during-run-defers-timer**: Calling `schedule(key:_:)` while `key`'s work is already running MUST NOT cancel that run and MUST NOT start a second run for the same key; it MUST record the newer work by bumping the entry's `generation` and resetting its `failures` to zero, and MUST cancel any armed timer without re-arming it until the running work finishes.
- **one-run-per-key**: `KeyedDebouncer` MUST NOT run more than one instance of a given key's work concurrently — `beginRun(key:)` MUST return without effect when that key's `entry.run` is already non-nil.
- **cross-key-concurrency**: Work for two different keys, once each is timer-triggered via `beginRun`, MUST be allowed to run concurrently with each other — each key gets its own independently created `Task` with no lock shared across keys; only same-key runs are serialized (per `one-run-per-key`), and only `flushAll()` additionally serializes *across* keys (see `flush-all-sequential-reports-still-failing` below).
- **success-retires-entry**: An entry MUST be removed from the debouncer once its work completes without throwing and its generation has not been superseded by a newer `schedule` call made while it ran.
- **failure-keeps-entry-and-rearms**: If `work` throws, the entry MUST NOT be removed; its `failures` count MUST be incremented and a retry timer MUST be armed for it — per the type's own doc comment, an entry leaves the debouncer only "on exactly two events: its work completed *without throwing*, or a caller explicitly `cancel`led it".
- **failure-callback-invoked-even-if-canceled**: `onFailure` (when supplied) MUST be called exactly once per failed attempt, with the failing `key` and the thrown error — and this call happens unconditionally, before `finishRun` checks whether an entry for that key still exists. Consequently, if `cancel(key:)` removes the entry while a run is in flight and that run's `work` closure subsequently throws (e.g. because it observed the cancellation), `onFailure` MUST still fire for a key the caller already cancelled; nothing in the source suppresses the callback for a since-removed entry.
- **superseded-run-resets-backoff**: When a run finishes for a generation older than the entry's current generation (i.e. newer work arrived while it ran), the entry's `failures` MUST be reset to zero and a fresh debounce-length timer MUST be armed, regardless of whether that superseded run succeeded or threw — whether the old attempt succeeded says nothing about the newer work.
- **retry-backoff-exponential-capped**: `retryInterval(afterFailures:)` MUST compute `debounce * 2^shift` where `shift = min(max(failures - 1, 0), 20)`, and MUST cap the result at `maximumRetryInterval` — backoff grows exponentially from the debounce window and never exceeds the configured ceiling, and the exponent's own cap of 20 MUST be applied independently of the `Duration` cap so the multiplication cannot overflow for a key that keeps failing indefinitely.
- **cancel-drops-entry-without-running**: `cancel(key:)` MUST remove `key`'s entry, MUST cancel its armed timer `Task` and any run `Task` in flight, and MUST NOT run the pending work — this is, together with success, the only way an entry leaves the debouncer.
- **cancel-during-run-not-resurrected**: If `cancel(key:)` runs while `key`'s work is in flight, the entry MUST already be absent by the time that run's `finishRun` executes, and `finishRun` MUST NOT recreate or re-arm it — `guard var entry = entries[key] else { return }` returns immediately for a key with no entry.
- **cancel-all-keys**: `cancelAll()` MUST apply the exact effect of `cancel(key:)`, individually, to every key present in the debouncer at the moment of the call.
- **cancellation-is-cooperative-only**: `cancel(key:)`'s `entry.run?.cancel()` MUST mark that run's `Task` as cancelled cooperatively; it MUST NOT forcibly interrupt a `work` closure that does not itself check `Task.isCancelled` or call a cancellable suspension point — such a closure MUST be allowed to run to completion even after `cancel(key:)` has already removed its entry.
- **flush-runs-now**: `flush(key:)` MUST run `key`'s pending work immediately, without waiting for its debounce window to elapse, and MUST NOT return until that attempt has completed.
- **flush-awaits-in-flight-run**: If a run for `key` is already executing when `flush(key:)` is called, `flush` MUST await that same run rather than starting a second one, including re-checking for a run started during its own suspension.
- **flush-all-sequential-reports-still-failing**: `flushAll()` MUST flush every currently pending key one at a time, in sequence — MUST NOT run two keys' flushes concurrently with each other — and MUST return the keys still present (i.e. still failing and re-armed) once every flush has been attempted.
- **pending-membership-reflects-any-state**: `pendingKeys` and `isPending(key:)` MUST report a key as pending for as long as any entry exists for it, whether it is waiting out its debounce window, currently running, or waiting to retry after a failure.
- **teardowns-mainactor-isolation**: `PendingTeardowns` MUST be declared `@MainActor` (`PendingTeardowns.swift`).
- **teardown-nonthrowing-closure**: `PendingTeardowns.Teardown` MUST be a non-throwing `@MainActor () async -> Void` closure type — per the doc comment, "a teardown that fails still happened, and there is no caller left to hand an error to"; a teardown that needs to report its own failure MUST do so itself (e.g. by logging), since `PendingTeardowns` provides no failure channel of any kind.
- **add-returns-immediately**: `add(_:)` MUST start `teardown` and MUST return without waiting for it to complete.
- **add-tracks-handle-per-token**: `add(_:)` MUST retain a `Task<Void, Never>` handle for every teardown it starts, each keyed by a freshly incremented token, for as long as that teardown is running.
- **entry-self-removes-on-completion**: The `Task` that `add(_:)` creates MUST remove its own tracked entry once its `teardown` closure completes, regardless of whether `drain()` is ever called — a teardown that finishes before anyone drains MUST NOT leave a stale handle behind.
- **drain-awaits-all-in-flight**: `drain()` MUST await every teardown currently tracked before it returns.
- **drain-awaits-teardowns-added-during-drain**: If a teardown being awaited by `drain()` itself calls `add(_:)` before finishing, `drain()` MUST also wait for that newly added teardown before returning — it MUST loop, taking a fresh snapshot of `tasks` each pass, until the tracked collection is observed empty, rather than making a single pass over the entries present when it was called.
- **drain-on-empty-returns-immediately**: `drain()` MUST return without suspending when no teardown is currently tracked (`while !tasks.isEmpty`).
- **in-flight-count-internal-visibility**: `inFlightCount` MUST report the exact number of teardowns currently tracked, and MUST be declared without `public` (internal access only) — the doc comment states its purpose is to let a test distinguish "started and tracked" from "started and dropped", not for use outside the module.

