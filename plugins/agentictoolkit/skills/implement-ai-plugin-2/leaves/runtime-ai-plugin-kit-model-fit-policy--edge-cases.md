<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-model-fit-policy.md -->

# ModelFitPolicy

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy--edge-cases#<slug>`):

- `null-and-empty-input` MUST — diskBytes == nil MUST short-circuit tier and fitInfo to nil and MUST make verdict fail open to .allow whenever pressure …
- `boundary-values` MUST — A pct exactly equal to warnPct MUST classify as .warn, not .ok, and a pct exactly equal to blockPct MUST classify as …
- `concurrent-access` MUST — Not applicable in the mutex/serialization sense — ModelFitPolicy declares no actor, lock, or shared mutable state of …

## Edge Cases

- **Null and empty input**: `diskBytes == nil` MUST short-circuit `tier` and
  `fitInfo` to `nil` and MUST make `verdict` fail open to `.allow` whenever
  pressure is `.normal` (MUST, see `tier-unknown-size`,
  `verdict-allow-non-block-tier`). An empty `model` string (`""`) is not
  validated or rejected anywhere in the source: `verdict` and `pickerLabel`
  MUST interpolate it verbatim into the reason string or label exactly as
  any other string, since neither function branches on it (MUST).
- **Boundary values**: A `pct` exactly equal to `warnPct` MUST classify as
  `.warn`, not `.ok`, and a `pct` exactly equal to `blockPct` MUST classify
  as `.block`, not `.warn`, because `tier` compares with `>=`, not `>` (MUST,
  see `tier-classification`). `physicalRAM == 0` MUST yield a
  `nil` tier (so `verdict` fails open) and MUST make `ramPct` return `0`,
  regardless of `diskBytes` (MUST, see `tier-zero-ram`, `ram-pct-zero-ram`).
  A negative `diskBytes`, or a negative or over-100 `warnPct`/`blockPct`, is
  not validated or rejected anywhere in `ModelFitPolicy.swift`;
  `estimatedBytes`, `tier`, and the percentage arithmetic all proceed
  unguarded, so a negative `diskBytes` necessarily produces a negative `pct`,
  which both `>=` comparisons read as `.ok` (fact, not a MUST — no
  validation branch exists in the source to enforce or violate).
- **Concurrent access**: Not applicable in the mutex/serialization sense —
  `ModelFitPolicy` declares no actor, lock, or shared mutable state of any
  kind (MUST, see `namespace-isolation`); every function reads
  only its parameters and returns a freshly computed value, so any number of
  concurrent callers on any number of threads or tasks are inherently
  race-free and require no synchronization.
- **Error states**: `ModelFitPolicy.swift` declares no `throws` on any
  function and raises no error of its own; it has no dependency (network,
  file system, database) to fail against. A caller's own failure to
  determine a model's size or the machine's RAM is communicated to
  `ModelFitPolicy` only as `diskBytes == nil`, already covered under Null and
  empty input above (fact — the source has no error path of its own to
  document).
- **Offline or disconnected state**: Not applicable — `ModelFitPolicy.swift`
  makes no network call and holds no notion of connectivity (traced to the
  single `import Foundation` and the absence of any networking API
  in the file). A caller's own unreachable local model server surfaces to
  `ModelFitPolicy` only as `diskBytes == nil`, identical to any other
  unknown-size case above.
