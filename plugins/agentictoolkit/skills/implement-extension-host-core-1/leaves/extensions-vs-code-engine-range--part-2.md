<!-- leaf: implement-extension-host-core-1/extensions-vs-code-engine-range--part-2 · source: extension-host-core-extensions-vs-code-engine-range.md -->

# VSCodeEngineRange — continued (part 2)

## Privacy

- **Data collected**: none beyond what the caller already supplied. The
  only data `VSCodeEngineRange` reads is the `engines.vscode` string from a
  caller-supplied manifest — third-party, extension-author-published text,
  never device- or user-identifying data.
- **Storage**: none. A `VSCodeEngineRange` value is held only in memory for
  the lifetime the caller keeps it; nothing is written to disk by this
  component.
- **Transmission**: none. This component performs no networking.
- **Retention**: for the lifetime of the `VSCodeEngineRange` value the
  caller holds; releasing the value releases the data with it.

## Platform Notes

- **SwiftUI**: the source (`VSCodeEngineRange.swift`, alongside
  `SemanticVersion.swift`, which it calls into for component bounds
  checking) is plain Foundation string parsing and value comparison with no
  dependency on SwiftUI or any view-layer framework. A port that keeps this
  component in Swift needs nothing beyond `Foundation`.
- **Compose**: model the private `Requirement` as a Kotlin `data class`
  carrying the same three base/must-equal-flag pairs plus `isMinimum`;
  parse with plain `String` splitting rather than a regular expression, and
  do not reach for a JVM semver library — none on the JVM model VS Code's
  specific "operator only clears flags, sub-1.0.0 has slack" grammar, which
  is not npm's caret rule. No Compose or Android SDK type is involved,
  since there is no UI surface to render.
- **React/Web**: model `Requirement` as a small immutable object with the
  six numeric/boolean fields plus `isMinimum`; parse with the same
  three-way `if`/`else if` operator check and manual `.`-splitting the
  source uses, and deliberately avoid npm's `semver` package for range
  evaluation — it implements exactly the caret/tilde/hyphen-range semantics
  this type's own doc comment says VS Code never implemented, so using it
  would silently reintroduce the wrong grammar. JavaScript's `number`
  covers the `Int32`-scale bound this type enforces via
  `SemanticVersion.maximumComponent` without a separate overflow check,
  though an explicit upper-bound comparison should still be ported alongside
  it rather than relied upon implicitly.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS host consumes the same
  `AgenticToolkitCore` type directly with no translation.
- **WinUI 3**: there is no existing .NET or Windows App SDK type that
  implements VS Code's `engines.vscode` grammar, so it needs a direct C#
  port rather than an existing library. Port `VSCodeEngineRange` and
  `SemanticVersion` as plain C# `readonly struct`s carrying the same
  three-base/must-equal-flag representation, mirroring the sibling
  `ActivationEventMatcher` recipe's own guidance for this pair of types.
  Resist NuGet's `Semver` or `NuGet.Versioning` packages for the same reason
  the React/Web note gives: both implement npm/NuGet-style semver ranges,
  the grammar this type's doc comment explicitly says VS Code is not.
  Guard each parsed component against `int.MaxValue` explicitly (mirroring
  `SemanticVersion.maximumComponent`), so a manifest with an absurd version
  component fails a `TryParse`-style construction instead of throwing an
  unhandled `OverflowException` deep inside a later comparison.
  `Task`/`async`, `HttpClient`, `System.Text.Json`, `Windows.Storage`,
  `ObservableCollection`, and `INotifyPropertyChanged` have no role here:
  every operation is a synchronous, side-effect-free struct computation
  with no I/O, no serialization, and no observable mutable state to notify
  on.

## Design Decisions

- **Decision**: A requirement is represented as three independent bases
  each paired with its own must-equal flag, and an operator's only effect
  is to clear flags — never to compute a ceiling.
  **Rationale**: the source's own doc comment states this is why `^1.74.0`
  admits `1.999.0` but not `2.0.0`, without a ceiling ever being computed;
  modeling a requirement as a floor-and-ceiling pair (the npm mental model)
  would require deriving and maintaining a ceiling this grammar's own rules
  never need.
  **Approved**: pending
- **Decision**: any sub-1.0.0 requirement that leaves slack in at least one
  component is treated as satisfied by every 1.x host version, while a
  fully pinned sub-1.0.0 requirement is not (`accepts-sub-one-compatibility-rewrite`,
  `accepts-sub-one-exact-refusal`).
  **Rationale**: this is upstream's own surprising rule — "anything below
  1.0.0 is compatible with 1.x, except exact matches" — and is deliberately
  not npm's caret semantics, which would cap `^0.10.5` at `0.11.0` and never
  run it on a 1.x host at all. The source's doc comment names this
  explicitly as the difference that matters for real Open VSX extensions.
  **Approved**: pending
- **Decision**: a pre-release suffix (the text after a `-`) is recognized
  by the grammar and does not cause a parse failure, but its text is
  discarded and plays no role in any comparison.
  **Rationale**: the source's doc comment on the (omitted) `notBefore`
  field explains that upstream only gives a `-YYYYMMDD` suffix meaning when
  comparing against a supplied product build date, and this host publishes
  no build date, so that comparison could never fire; the suffix is still
  parsed rather than rejected "because the grammar has a production for it
  and a manifest that uses one must load."
  **Approved**: pending
- **Decision**: an input outside this grammar — including every npm range
  shape VS Code's own validator never implemented (`~`, `>`, `<`, `||`, a
  hyphen range, a two-component version) — returns `nil` from `init?(_:)`
  rather than being approximated, and every production caller treats that
  `nil` as a load failure naming the raw string, never a silent pass or a
  silent reject.
  **Rationale**: the source's own doc comment frames this as the reason
  the port matters, not an academic distinction: an npm reading rejects 48
  of 198 surveyed Open VSX web extensions that VS Code itself runs, and a
  reading that approximated an unsupported shape instead of refusing it
  could just as easily accept something VS Code refuses — the wrong
  direction for a host strictly less capable than the one these manifests
  were written for.
  **Approved**: pending
- **Decision**: `minimumVersion` reports the requirement's declared floor
  (the parsed bases) rather than the lowest version `accepts(_:)` actually
  returns `true` for.
  **Rationale**: the source's doc comment on `minimumVersion` states the
  two differ for a sub-1.0.0 range, and its one caller,
  `ActivationEventMatcher`, needs the *declared* floor specifically —
  probing `accepts(_:)` at a candidate version would give the wrong answer
  for a range like `^1.73.5`, whose floor is below `1.74.0` yet which still
  rejects the literal version `1.73.0`.
  **Approved**: pending
- **Decision**: `isUnconstrained` is a distinct predicate rather than a
  check for `minimumVersion == 0.0.0`.
  **Rationale**: the source's doc comment states that `*` parses to a
  floor reading of `0.0.0`, indistinguishable by `minimumVersion` alone
  from a manifest that genuinely asked for `0.0.0`; only the must-equal
  flags — cleared by `*` and by an all-`x` range, set by a literal
  `"0.0.0"` — can tell "no version claim at all" apart from "a claim to
  the oldest possible version."
  **Approved**: pending
