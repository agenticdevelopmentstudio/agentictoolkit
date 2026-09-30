<!-- leaf: implement-extension-host-core-1/extensions-vs-code-engine-range--test-vectors · source: extension-host-core-extensions-vs-code-engine-range.md -->

# VSCodeEngineRange

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vcer-001 | caret-operator, accepts-minor-comparison, accepts-patch-comparison | `VSCodeEngineRange("^1.74.0")!.accepts(1.74.0)`, `.accepts(1.95.0)`, `.accepts(1.74.1)` | all `true` (`caretAccepts`) |
| vcer-002 | accepts-major-comparison | `VSCodeEngineRange("^1.74.0")!.accepts(1.73.9)`, `.accepts(2.0.0)` | both `false` (`caretRejects`) |
| vcer-003 | minimum-operator, accepts-minimum-comparison | `VSCodeEngineRange(">=1.74.0")!.accepts(2.0.0)` | `true` (`atLeastAccepts`) |
| vcer-004 | exact-operator | `VSCodeEngineRange("1.74.0")!.accepts(1.74.0)` is `true`; `.accepts(1.74.1)` is `false` | (`exactAcceptsOnlyItself`) |
| vcer-005 | wildcard-recognition | `VSCodeEngineRange("*")!.accepts(1.138.0)`, `.accepts(0.0.1)`, `.accepts(42.0.0)` | all `true` (`starAcceptsEverything`) |
| vcer-006 | wildcard-recognition, minimum-version-floor | `VSCodeEngineRange("*")!.minimumVersion` | `== 0.0.0` (`starFloorsAtZero`) |
| vcer-007 | x-wildcard-component | `VSCodeEngineRange("1.x.x")!.accepts(1.138.0)` true, `VSCodeEngineRange("2.x.x")!.accepts(1.138.0)` false, `VSCodeEngineRange("1.139.x")!.accepts(1.138.0)` false | (`wildcardComponents`) |
| vcer-008 | prerelease-suffix-tolerance | `VSCodeEngineRange("^1.89.0-insider")!.accepts(1.138.0)`, `VSCodeEngineRange("^1.89.0-20240101")!.accepts(1.138.0)` | both `true` (`preReleaseSuffixIsAccepted`) |
| vcer-009 | accepts-sub-one-compatibility-rewrite | `VSCodeEngineRange("^0.10.5")!.accepts(1.138.0)`, `VSCodeEngineRange("^0.10.x")!.accepts(1.138.0)`, `VSCodeEngineRange("^0.0.1")!.accepts(1.138.0)` | all `true` (`subOneRequirementsWithSlackAccept1x`) |
| vcer-010 | accepts-sub-one-exact-refusal | `VSCodeEngineRange("0.10.0")!.accepts(1.138.0)` is `false`; `.accepts(0.10.0)` is `true` | (`exactSubOneRequirementRejects1x`) |
| vcer-011 | component-count, unsupported-grammar-rejection | `VSCodeEngineRange(input)` for each of `"~1.74.0"`, `">1.74.0"`, `"<2.0.0"`, `"1.74.0 || 2.0.0"`, `"1.74"`, `"1"`, `""`, `"latest"`, `"^"` | every result is `nil` (`rejectsUnsupportedGrammar`) |
| vcer-012 | whitespace-trimming, inner-whitespace-rejection | `VSCodeEngineRange("  ^1.74.0  ")!.accepts(1.74.0)` is `true`; `VSCodeEngineRange(">= 1.74.0")` is `nil`; `VSCodeEngineRange("^ 1.74.0")` is `nil` | (`whitespaceIsTrimmedNotTolerated`) |
| vcer-013 | component-bound | `VSCodeEngineRange(input)` for `"^\(Int.max).0.0"`, `">=\(Int.max).0.0"`, `"\(Int.max).0.0"`, `"^2147483648.0.0"`, `"1.\(Int.max).0"`, `"1.0.\(Int.max)"` | every result is `nil` (`rejectsOversizedComponents`) |
| vcer-014 | minimum-version-floor | `VSCodeEngineRange("^1.74.0")!.minimumVersion == 1.74.0`; `VSCodeEngineRange(">=1.80.2")!.minimumVersion == 1.80.2`; `VSCodeEngineRange("1.74.0")!.minimumVersion == 1.74.0` | (`minimumVersionIsTheFloor`) |
| vcer-015 | component-bound, accepts-major-comparison | `VSCodeEngineRange("^2147483647.0.0")!.accepts(SemanticVersion(major: 2147483647, minor: 9, patch: 9))` is `true`; `.accepts(1.95.0)` is `false` | (`acceptsTheLargestPermittedMajor`) |
| vcer-016 | is-unconstrained-predicate | `VSCodeEngineRange("*")!.isUnconstrained` is `true`; `VSCodeEngineRange(r)!.isUnconstrained` for each of `"^1.74.0"`, `">=1.80.2"`, `"1.74.0"`, `"^0.9.0"`, `"^0.0.1"` is `false` | (`onlyTheWildcardIsUnconstrained`) |
| vcer-017 | value-semantics, rawvalue-preservation | `VSCodeEngineRange("^1.74.0")!.description` | `== "^1.74.0"` — source: `description` returns `rawValue` |
| vcer-018 | rawvalue-preservation | `VSCodeEngineRange("  ^1.74.0  ")!.rawValue` | `== "  ^1.74.0  "` (untrimmed, exactly as passed) — source: `init?` |
| vcer-019 | accepts-minimum-comparison | `VSCodeEngineRange(">=1.74.0")!.accepts(1.73.9)` | `false` — source: `accepts(_:)`'s `isMinimum` branch, no dedicated test |
| vcer-020 | caret-operator, accepts-patch-comparison | `VSCodeEngineRange("^0.10.5")!.accepts(SemanticVersion(major: 0, minor: 10, patch: 6))` | `true` (major `0` clears only the patch flag) — source: `parse(_:)`'s caret branch, no dedicated test |
| vcer-021 | caret-operator, accepts-minor-comparison | `VSCodeEngineRange("^0.10.5")!.accepts(SemanticVersion(major: 0, minor: 11, patch: 0))` | `false` (minor flag stays set when major base is `0`) — source: `parse(_:)`'s caret branch, no dedicated test |
| vcer-022 | concurrency-safety | one shared `VSCodeEngineRange` value queried by `accepts(_:)` from many concurrent tasks | every call returns the same result a sequential call would, with no crash or data race — traced to `Sendable`/immutable-storage declaration, no dedicated test |
