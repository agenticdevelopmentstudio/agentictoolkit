<!-- leaf: implement-general-1/deploy-engine--part-6 · source: deploy-engine.md -->

# Deploy Engine — continued (part 6)

**Rules** (cite as `implement-general-1/deploy-engine--part-6#<slug>`):

- `decision` MUST — listRailwayProjects returns null (couldn't enumerate) as distinct from [] (enumerated, genuinely empty); …

## Platform Notes

- **SwiftUI**: A port keeps the planners (`plan.ts`, `builder-match.ts`) as
  pure, synchronous Swift functions over `struct`/`enum` value types (the
  `AddPlan`/`BuilderSitePlan` unions map directly to Swift `enum`s with
  associated values); the cross-thread cooldown registry maps to an `actor`
  or a `Sendable` type wrapping `os_unfair_lock`/`ManagedAtomic` rather than
  `SharedArrayBuffer` + `Atomics`, since Swift has no JS-style shared-buffer
  primitive across threads in one process.
- **Compose**: Mirrors SwiftUI's structural mapping — pure Kotlin `data
  class`/`sealed interface` planners, coroutines for the injected-I/O
  runner, and `kotlinx.atomicfu` or a `Mutex`-guarded `IntArray` in place of
  the `SharedArrayBuffer` registry for cross-thread/cross-coroutine cooldown
  state.
- **React/Web**: This is the source platform; no translation is needed. A
  browser-hosted port (as opposed to this Node-hosted one) would need a
  substitute for `SharedArrayBuffer` cross-THREAD sharing (a `Worker` plus
  `postMessage`, since browser `SharedArrayBuffer` requires cross-origin
  isolation headers this component's server context does not need).
- **AppKit/UIKit**: Same mapping as SwiftUI's controller-level equivalents;
  `URLSession` with `URLSessionConfiguration.timeoutIntervalForRequest`
  provides the `withTimeout`/`AbortSignal.timeout` equivalent, and
  `NSCache` (with an explicit last-write timestamp, since `NSCache` has no
  built-in TTL) can back the single-flight cache's storage half provided a
  separate in-flight-promise/continuation dictionary still de-duplicates
  concurrent misses.
- **WinUI 3**: `HttpClient` (with a per-call `CancellationTokenSource`
  driving a timeout, replacing `AbortSignal`/`withTimeout`) issues the
  provider requests; `System.Text.Json` replaces the `JSON.parse`/`res
  .json()` calls throughout the provider adapters; no file lives under
  `Windows.Storage` since no given source persists anything to disk;
  `Task`/`async`-`await` replaces the `Promise`-based `applySequentially`/
  `mapLimit` orchestration, with `System.Threading.Channels` or a plain
  `SemaphoreSlim` bounding `mapLimit`'s concurrency; the cross-thread
  cooldown registry maps to a shared `long[]` (or a small
  `MemoryMappedFile`) mutated only through `Interlocked.Exchange`/
  `Interlocked.CompareExchange`, the .NET equivalent of the source's
  `Atomics.store`/`Atomics.load` discipline; a port has no
  `ObservableCollection`/`INotifyPropertyChanged` counterpart to add here,
  since none of the given sources expose an observable collection — every
  result is a plain returned value or array.

## Design Decisions

### SharedArrayBuffer for cross-thread cooldown state

**Decision**: The provider-cooldown registry stores its four provider slots
in a `BigInt64Array` backed by a `SharedArrayBuffer`, mutated only through
`Atomics.load`/`Atomics.store`, and hands that same buffer to a worker
thread via `cooldownState()`/`attachCooldownState()` rather than each thread
keeping its own registry.

**Rationale**: The monitor cycle runs on a worker thread while
`/deploy-projects` and `/integrations` enumerate on the API thread, and both
hit the same provider token; a per-thread registry left a 429 seen by one
thread invisible to the other, so the other kept hammering an
already-throttled account — the exact failure this module exists to
prevent. The reads sit on the fetchers' hot path, so they must stay
synchronous (no DB round trip), which a `SharedArrayBuffer` read satisfies
and an IPC-based alternative would not.

**Approved**: pending

### null vs. empty-array/false as provenance, not just a value

**Decision**: `listRailwayProjects` returns `null` (couldn't enumerate) as
distinct from `[]` (enumerated, genuinely empty); `fetchProjectDomains` and
`fetchProjectDomainList` return a `{ domains, live }` shape rather than a
bare array so a failed refresh is distinguishable from a genuinely
domain-less project; `EndpointLite.ignoreProjectWarning` is a REQUIRED
boolean (unlike `EndpointLike`'s optional field) precisely so an adapter
must name `false` explicitly rather than omit the field and have omission
silently misread as "not opted out."

**Rationale**: A caller that deletes a monitor for being unclaimed, or
treats an empty enumeration as "nothing exists," cannot make that decision
safely if "couldn't read" and "read, and there's nothing" produce the same
value. Each of these three shapes exists because a real regression shipped
from collapsing the distinction (documented in each file's own comments).

**Approved**: pending

### Creation is opt-in; matching is not

**Decision**: `runAutoConfigure` and `runBuilderAutoConfigure` both wire an
existing site/endpoint to a project unconditionally, but create a new
site/endpoint only when the caller supplies `opts.create` (a target group).

**Rationale**: The per-platform "Match" / "Match all" UI actions must never
graft a phantom site; only the global "Auto Configure" review flow, after
an operator has pruned the projects they don't want, passes `create`. Making
creation a separate, explicitly-supplied capability rather than a flag
on the same call keeps a match-only caller structurally incapable of
creating anything.

**Approved**: pending

### Stale-wiring repair is gated on a verified, per-platform live-project index

**Decision**: `planAddProject` re-points an endpoint's wiring away from a
project name only when the caller supplies a `LiveProjectIndex` whose
`platforms` set includes that endpoint's own canonical platform; absent
that verification, a name the platform "doesn't have" is treated as still
live and the endpoint is left alone (or reported as a `conflict`).

**Rationale**: Absence of a name from an enumeration is evidence only when
that enumeration is known to be a complete, authenticated read. A platform
whose listing failed, or that degraded to a configured fallback list, is
missing names that are perfectly alive; treating those as retired would
re-point live monitors onto whatever project happens to be added next — the
single most destructive failure mode this feature could have.

**Approved**: pending

### One `applySequentially` definition shared by both runners

**Decision**: `runAutoConfigure` (project axis) and `runBuilderAutoConfigure`
(builder axis) both call the same exported `applySequentially` from
`run.ts` rather than each implementing their own sequential-apply loop.

**Rationale**: Both runs need identical sequencing (strictly one item at a
time, because each apply may mutate shared working state a later apply must
see) and identical resilience (one item's failure recorded in `skipped`,
never fatal). Two independent implementations of that loop could drift —
one becoming parallel, or one dropping the try/catch — without any test
catching the divergence, since they are exercised by different test files.

**Approved**: pending

### `familyGroup` is immutable for the life of one run

**Decision**: `Working.familyGroup`, built once by `indexFamilyGroups` at
the start of `runAutoConfigure`, is never updated as sites are created or
rolled back during that same run; the next run rebuilds it from scratch.

**Rationale**: A site created mid-run is filed either with its domain
family's existing owning group or, for an unowned/split family, with the
operator's fallback group — and the map, as built at the run's start,
already answers both of those questions the same way a mid-run update
would. Maintaining it live would add mutation-ordering complexity (in
particular around the create/rollback path) for an answer that provably
cannot change within the run.

**Approved**: pending

### Requirement count reflects twelve bundled source files of pure logic

**Decision**: This ingredient recipe carries a substantially larger
Behavioral Requirements list than a typical UI ingredient.

**Rationale**: `deploy-engine` is not one class or view; it is twelve
source files — a canonicalization module, a cross-thread rate limiter, a
classification model, two pure planners, an I/O runner shared by two
callers, three provider adapters, a host-picker, and three single-purpose
utilities — each with its own public contract. Splitting this into several
smaller recipes would break the "one recipe, one component" convention the
brief assigns (`deploy-engine` is the named component), and would scatter
cross-file invariants (e.g. the sibling-matching key that both `plan.ts`
and `builder-match.ts` must agree on) across files that could then drift
independently.

**Approved**: pending
