<!-- leaf: implement-foundation/concurrency · source: foundation-concurrency.md -->

# BlockingWork, KeyedDebouncer & PendingTeardowns

## Overview

Three Foundation-only types in `packages/apple/AgenticToolkit/Core/Concurrency/`, part of the `AgenticToolkitCore` framework target, that each solve one recurring structured-concurrency mistake found independently at two or more call sites in this codebase. `BlockingWork` (`BlockingWork.swift`, a stateless `enum` namespace) hops a synchronous, thread-blocking closure onto a GCD global queue and resumes the calling `Task` with its result, so that work sitting on a semaphore or a large synchronous file read never occupies one of the cooperative thread pool's core-count threads. `KeyedDebouncer<Key>` (`KeyedDebouncer.swift`, an `@MainActor` generic `final class`) coalesces repeated per-key work into one debounced run and guarantees that a run which throws is never dropped: the entry stays pending and re-arms with exponential backoff until it succeeds or is explicitly cancelled. `PendingTeardowns` (`PendingTeardowns.swift`, an `@MainActor` `final class`) holds the task handle for teardown work started without a waiter, so a later shutdown path can `drain()` and be certain nothing it started is still in flight. None of the three performs any I/O of its own; each only manages *where* or *when* a caller-supplied closure runs.

