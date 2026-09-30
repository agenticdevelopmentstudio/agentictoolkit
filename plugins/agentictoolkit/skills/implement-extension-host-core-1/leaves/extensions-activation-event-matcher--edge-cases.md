<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher--edge-cases · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher

**Rules** (cite as `implement-extension-host-core-1/extensions-activation-event-matcher--edge-cases#<slug>`):

- `concurrent-access` MAY — ActivationEvent, ActivationTrigger, WorkspaceScan, and ActivationEventMatcher are declared Sendable value types with no …

## Edge Cases

- **Null/empty input**: an empty `activationEvents` array, or one containing
  only entries that fail to parse, yields an empty `events` array,
  `activatesEagerly == false`, and (per `empty-manifest-no-match`) no
  trigger matches. An entry that trims to the empty string, or a prefixed
  entry with an empty payload, is rejected rather than treated as a
  wildcard or an empty-string match (`empty-entry-rejection`,
  `empty-payload-rejection`).
- **Malformed glob syntax**: a `workspaceContains:` glob using a
  square-bracket character class or a leading exclamation-mark negation is
  rejected at parse time and recorded in `unsupportedPatterns`; it never
  matches, and it never causes `ActivationEventMatcher.init(manifest:)` to
  fail or throw (`glob-syntax-unsupported`, `glob-triage`).
- **Malformed engine range**: an `engines.vscode` string this component
  cannot parse (anything outside `*`, an optional `^`/`>=` prefix, and
  three numeric-or-`x` components) yields an empty
  `implicitlyActivatingCommands`, never a crash or a `nil` matcher
  (`implicit-activation-unparseable-engine`).
- **Boundary values — implicit-activation floor**: an engine of exactly
  `"1.74.0"` or `"^1.74.0"` grants implicit activation; an engine one patch
  below the floor (`"^1.73.0"`, or any range whose `minimumVersion` is less
  than 1.74.0) does not; an unconstrained engine (`"*"`) grants it, because
  the source explicitly treats "no version claim" as distinct from "a
  claim to predate 1.74" (`implicit-activation-floor`).
- **Boundary values — glob anchoring**: a pattern must consume the entire
  path at both ends; a pattern that matches a prefix or suffix of a path
  but not the whole of it does not match (`glob-anchoring`).
- **Concurrent access**: `ActivationEvent`, `ActivationTrigger`,
  `WorkspaceScan`, and `ActivationEventMatcher` are declared `Sendable`
  value types with no mutable stored state reachable after
  construction, and `GlobPattern.matches(_:)` builds its memoization
  tables as local variables scoped to that one call rather than shared
  mutable state on the pattern — so `matches(_:)` MAY be called
  concurrently, from any isolation domain, against the same matcher or the
  same `GlobPattern`, with no synchronization required.
- **Error states**: not applicable — every operation in this component is a
  synchronous, non-throwing, pure computation over already-in-memory
  values; there is no I/O, so there is no error channel to define.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; `WorkspaceScan`'s paths are
  supplied by the caller, who is responsible for the directory walk that
  produced them.
- **Unbounded input size**: `matches(.workspaceScanned(_:))` and
  `GlobPattern.matches(_:)` define no timeout, cancellation, or size limit;
  matching runs synchronously to completion regardless of how many paths a
  `WorkspaceScan` carries or how many backtracking tokens a pattern
  contains (mitigated for cost, not bounded for time, by
  `backtracking-memoization`).
