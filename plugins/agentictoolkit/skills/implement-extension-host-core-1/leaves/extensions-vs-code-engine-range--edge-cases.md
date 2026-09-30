<!-- leaf: implement-extension-host-core-1/extensions-vs-code-engine-range--edge-cases · source: extension-host-core-extensions-vs-code-engine-range.md -->

# VSCodeEngineRange

**Rules** (cite as `implement-extension-host-core-1/extensions-vs-code-engine-range--edge-cases#<slug>`):

- `null-empty-input` MUST — an empty string, or a string that trims to empty, MUST fail to parse (init?(_:) returns nil); there is no default or …
- `boundary-values` MUST — a component exactly at SemanticVersion's plausibility bound (Int32.max) MUST parse and MUST be safe to compare in …
- `concurrent-access` MAY — VSCodeEngineRange and its private Requirement are immutable value types with no mutable shared state, so accepts(_:), …

## Edge Cases

- **Null/empty input**: an empty string, or a string that trims to empty,
  MUST fail to parse (`init?(_:)` returns `nil`); there is no default or
  fallback range (`unsupported-grammar-rejection`, `vcer-011`).
- **Boundary values**: a component exactly at `SemanticVersion`'s
  plausibility bound (`Int32.max`) MUST parse and MUST be safe to compare
  in `accepts(_:)`; a component one past that bound (for example
  `2147483648`) MUST fail to parse rather than overflow or trap
  (`component-bound`, `vcer-013`, `vcer-015`). The declared floor for `"*"`
  and for an all-`x` range is `0.0.0`, the lowest value `minimumVersion`
  can report (`vcer-006`).
- **Concurrent access**: `VSCodeEngineRange` and its private `Requirement`
  are immutable value types with no mutable shared state, so `accepts(_:)`,
  `minimumVersion`, `isUnconstrained`, and `description` MAY be called
  concurrently, from any isolation domain, against the same instance with
  no synchronization required (`concurrency-safety`, `vcer-022`).
- **Error states**: not applicable in the throwing sense — every operation
  in this component is a synchronous, non-throwing, pure computation with
  no I/O. The one failure signal this component defines is `init?(_:)`
  returning `nil`; deciding what that `nil` means to a caller (an
  unparseable engine string versus a well-formed but incompatible one) is
  the caller's responsibility, not this type's — `ExtensionRegistry`
  records `.engineRangeUnparsable`, `VSIXInstaller` throws
  `.engineRangeUnreadable`, and `OpenVSXCatalog` returns
  `.engineRangeUnreadable`, each only after `VSCodeEngineRange.init?(_:)`
  has already returned `nil`.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; it operates entirely on an
  in-memory string and an in-memory `SemanticVersion`.
- **Malformed grammar shapes**: whitespace inside the range, an operator
  this grammar does not define (`~`, `>`, `<`, `||`), a component count
  other than three, and a non-numeric non-`x` component all fail to parse
  the same way — `init?(_:)` returns `nil` — rather than being partially
  accepted or approximated (`inner-whitespace-rejection`,
  `unsupported-grammar-rejection`, `component-count`, `vcer-011`,
  `vcer-012`).
