---
id: fea35fb1-9eeb-4647-b185-902c1d1cb988
title: VSCodeEngineRange
domain: agentictoolkit://recipes/extension-host-core-extensions-vs-code-engine-range
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Parses and evaluates a VS Code extension manifest''s engines.vscode range:
  VS Code''s own non-npm version grammar, not an npm semver range.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-compatibility
- semantic-versioning
- version-range
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-activation-event-matcher
references:
- packages/apple/AgenticToolkit/Core/Extensions/VSCodeEngineRange.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SemanticVersion.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/VSCodeEngineRangeTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ActivationEventMatcher.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionRegistry.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VSCodeEngineRange

## Overview

`VSCodeEngineRange` is `AgenticToolkitCore`'s parser and evaluator for a VS
Code extension manifest's `engines.vscode` field. Per its own doc comment it
is a deliberate port — not an interpretation — of VS Code's own
`extensionValidator.ts` (`isValidVersionStr`, `parseVersion`,
`normalizeVersion`, `isValidVersion`), pinned at the commit recorded in
`docs/planning/vsc-extensions-upstream-pin-manifest.md`, because
`engines.vscode` *looks* like an npm semver range and is not one: an npm
reading rejects 48 of the 198 web extensions among the 600 most-downloaded on
Open VSX (per `Scripts/openvsx_engine_survey.py`) that VS Code itself runs.
The grammar it implements is exactly `(^|>=)?(digit-run or x).(digit-run or
x).(digit-run or x)` optionally followed by a `-` pre-release suffix, plus
the bare `*`; every other npm shape (`~`, `>`, `<`, `||`, a hyphen range, a
two-component version) is outside the grammar and fails to parse. A
requirement is represented as three bases — `majorBase`, `minorBase`,
`patchBase` — each paired with its own must-equal flag, plus an `isMinimum`
flag for a `>=` range; an operator's only job is to clear must-equal flags,
never to compute a ceiling, and a version below 1.0.0 that has any flag
cleared is treated as compatible with every 1.x version, while a fully
pinned sub-1.0.0 version is not. `minimumVersion` reports the requirement's
declared floor and `isUnconstrained` reports whether the range makes no
version claim at all (`*`, or an all-`x` range) — a distinction
`minimumVersion` alone cannot draw, because both `*` and a literal `0.0.0`
read as a floor of 0.0.0.

Four production call sites consume it today, all in
`AgenticToolkitCore`: `ActivationEventMatcher.init(manifest:)` reads
`minimumVersion` and `isUnconstrained` to decide whether a manifest's engine
grants VS Code 1.74's implicit-activation-from-`contributes.commands` rule;
`ExtensionRegistry.load(from:)` (`ExtensionRegistry.swift:544`) and
`VSIXInstaller`'s install path (`VSIXInstaller.swift:218`) each parse the
manifest's declared engine and call `accepts(_:)` against
`ExtensionRegistry.declaredVSCodeVersion` (1.138.0) to decide whether the
extension may load at all, reporting `.engineRangeUnparsable`/
`.engineRangeUnreadable` when the string does not parse and
`.engineIncompatible` when it parses but is not accepted; and
`OpenVSXCatalog.OpenVSXExtensionVersion.installability(forHostVersion:)`
runs the same two checks before a registry entry's `.vsix` is downloaded, so
that an incompatible or unparseable engine is refused before any network
transfer.

## Behavioral Requirements

- **rawvalue-preservation**: `VSCodeEngineRange.rawValue` MUST hold the
  string exactly as passed to `init?(_:)`, including any leading or
  trailing whitespace, even though recognition of the string's shape
  operates on a separately trimmed copy.
- **whitespace-trimming**: `init?(_:)` MUST trim leading and trailing
  whitespace (Foundation's `.whitespaces` character set) from the input
  before attempting to recognize its shape.
- **inner-whitespace-rejection**: `init?(_:)` MUST NOT accept whitespace
  anywhere inside the trimmed string; a string such as `">= 1.74.0"` or
  `"^ 1.74.0"` MUST fail to parse.
- **wildcard-recognition**: an input that trims to exactly `"*"` MUST parse
  to a requirement whose three bases are all `0`, whose three must-equal
  flags are all `false`, and whose `isMinimum` is `false`.
- **caret-operator**: a trimmed input beginning with `"^"` MUST always
  clear the patch component's must-equal flag, and MUST also clear the
  minor component's must-equal flag unless the parsed major base is `0`.
- **minimum-operator**: a trimmed input beginning with `">="` (and not with
  `"^"`) MUST set `isMinimum` to `true` and leave all three must-equal
  flags exactly as parsed from the three components.
- **exact-operator**: a trimmed input beginning with neither `"^"` nor
  `">="` MUST leave every component's must-equal flag exactly as parsed
  from that component (a numeric component's flag `true`, an `"x"`
  component's flag `false`) and MUST leave `isMinimum` `false`.
- **x-wildcard-component**: a component written as the single character
  `"x"` MUST parse to a base of `0` with that component's own must-equal
  flag `false`, independent of the other two components' values.
- **numeric-component**: a component consisting only of ASCII digit
  characters MUST parse to that integer value with the component's
  must-equal flag `true`, before any operator-driven clearing is applied.
- **component-count**: after the operator prefix is removed and any
  pre-release suffix is dropped, the remaining body MUST split into exactly
  three `.`-separated components (using
  `split(separator:omittingEmptySubsequences:false)`, so an empty component
  from a doubled or trailing `.` counts as a component); a body that does
  not split into exactly three components MUST cause `init?(_:)` to return
  `nil`.
- **prerelease-suffix-tolerance**: when the body contains a `-` character,
  `init?(_:)` MUST discard that character and everything after it before
  splitting into components, and the presence of such a suffix (for
  example `"-insider"` or `"-20240101"`) MUST NOT by itself cause
  `init?(_:)` to return `nil`; the discarded suffix text plays no further
  role in `accepts(_:)`, `minimumVersion`, or `isUnconstrained`.
- **component-bound**: the three parsed integer components MUST be
  validated by constructing `SemanticVersion("<major>.<minor>.<patch>")`
  from them; a component that is empty, contains a non-ASCII-digit
  character, or exceeds `SemanticVersion`'s own plausibility bound
  (`Int32.max`) MUST cause `init?(_:)` to return `nil` rather than
  overflowing or trapping.
- **unsupported-grammar-rejection**: a trimmed input that is not the bare
  `"*"` and does not fit `(^|>=)?` followed by exactly three
  numeric-or-`x` `.`-separated components (with an optional `-` suffix)
  MUST cause `init?(_:)` to return `nil`; this includes any npm-style
  shape VS Code's own grammar never implements — a `"~"`, `">"`, `"<"`, or
  `"||"` operator, a hyphen version range, a two-component version such as
  `"1.74"`, a bare single component such as `"1"`, the literal string
  `"latest"`, a lone `"^"` with no version, and the empty string.
- **accepts-minimum-comparison**: when `isMinimum` is `true`,
  `accepts(_:)` MUST return `true` if and only if the tested version's
  `(major, minor, patch)` tuple is greater than or equal to the
  requirement's `(majorBase, minorBase, patchBase)` tuple under
  lexicographic (major, then minor, then patch) ordering.
- **accepts-sub-one-compatibility-rewrite**: when `isMinimum` is `false`,
  the tested version's `major` equals `1`, the requirement's `majorBase`
  equals `0`, and at least one of the requirement's three must-equal flags
  is `false`, `accepts(_:)` MUST evaluate the tested version against a
  rewritten requirement of `majorBase: 1` (must-equal `true`), `minorBase:
  0` (must-equal `false`), `patchBase: 0` (must-equal `false`) instead of
  the requirement as parsed — i.e. any sub-1.0.0 requirement that leaves
  slack anywhere MUST be satisfied by every version whose major is `1`.
- **accepts-sub-one-exact-refusal**: when the requirement's `majorBase`
  equals `0` and all three of its must-equal flags are `true` (a fully
  pinned sub-1.0.0 version such as `"0.10.0"`), the rewrite in
  `accepts-sub-one-compatibility-rewrite` MUST NOT apply, and `accepts(_:)`
  MUST reject every tested version whose `major` is not exactly `0`.
- **accepts-major-comparison**: after any rewrite, `accepts(_:)` MUST
  return `false` when the tested version's `major` is less than the
  (possibly rewritten) `majorBase`, MUST return the negation of the
  (possibly rewritten) major must-equal flag when the tested version's
  `major` is greater than `majorBase`, and MUST proceed to compare minor
  components only when the two majors are equal.
- **accepts-minor-comparison**: once majors are equal, `accepts(_:)` MUST
  return `false` when the tested version's `minor` is less than
  `minorBase`, MUST return the negation of the minor must-equal flag when
  the tested version's `minor` is greater than `minorBase`, and MUST
  proceed to compare patch components only when the two minors are equal.
- **accepts-patch-comparison**: once minors are equal, `accepts(_:)` MUST
  return `false` when the tested version's `patch` is less than
  `patchBase`, MUST return the negation of the patch must-equal flag when
  the tested version's `patch` is greater than `patchBase`, and MUST
  return `true` when major, minor, and patch are all equal to their
  respective bases.
- **minimum-version-floor**: `minimumVersion` MUST equal
  `SemanticVersion(major: majorBase, minor: minorBase, patch: patchBase)`
  taken directly from the parsed requirement; it MUST NOT reflect the
  sub-1.0.0 rewrite that `accepts(_:)` applies at comparison time, so for a
  requirement such as `"^0.10.5"` it reports `0.10.5`, not `1.0.0`.
- **is-unconstrained-predicate**: `isUnconstrained` MUST be `true` if and
  only if `isMinimum` is `false` and all three bases are `0` and all three
  must-equal flags are `false`; this is `true` for `"*"` and for an all-`x`
  range such as `"x.x.x"`, and `false` for every other range, including a
  literal `"0.0.0"` and a `">=0.0.0"` minimum.
- **value-semantics**: `VSCodeEngineRange` MUST conform to `Sendable`,
  `Hashable`, and `CustomStringConvertible`, with its `description`
  returning `rawValue` exactly.
- **concurrency-safety**: `VSCodeEngineRange` instances MUST be safe to
  construct and to query (`accepts(_:)`, `minimumVersion`,
  `isUnconstrained`, `description`) concurrently, from any isolation
  domain, without external synchronization, because every stored property
  on `VSCodeEngineRange` and on the private `Requirement` it wraps is a
  `let` and neither type declares any mutable shared state.

## Appearance

Not applicable — this is a manifest version-range parser and evaluator,
not a visual component.

## States

Not applicable — this is a manifest version-range parser and evaluator,
not a visual component.

## Accessibility

Not applicable — this is a manifest version-range parser and evaluator,
not a visual component.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| the string passed to `init?(_:)` | `String` | none (required) | The raw `engines.vscode` value read from a manifest's `package.json`; the sole input this component accepts. |
| `version` passed to `accepts(_:)` | `SemanticVersion` | none (required) | The host (or candidate) version the range is evaluated against; every production caller passes `ExtensionRegistry.declaredVSCodeVersion` (`1.138.0`). |

There are no environment variables, settings keys, or injected
dependencies: `VSCodeEngineRange` takes every input as a plain initializer
or method argument and reads no ambient state.

## Deep Linking

Not applicable: `VSCodeEngineRange.swift` parses and evaluates manifest
strings in memory; it defines no URL scheme, route, or navigable
destination.

## Localization

Not applicable: `VSCodeEngineRange.swift` produces no user-facing string.
It carries `rawValue` verbatim for a caller to report, but formats,
translates, or displays none of it itself.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `VSCodeEngineRange.swift` defines no feature flag, build
configuration check, or remote-config lookup; its behavior is fixed by the
grammar it implements and the string it is constructed with.

## Analytics

Not applicable: this component emits no analytics events; it returns
values to its caller and performs no telemetry of its own.

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

## Logging

Not applicable: `VSCodeEngineRange.swift` contains no logging call. A
string it cannot parse is surfaced only as a `nil` return; a caller decides
for itself whether and how to log or report that (see Edge Cases — Error
states).

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`separation-of-concerns` passes because the type splits parsing
(`parse(_:)`, producing a private `Requirement`) from evaluation
(`accepts(_:)`), from floor reporting (`minimumVersion`), from the
no-claim predicate (`isUnconstrained`), each a single-purpose entry point
over one immutable `Requirement` value (`Overview`, `caret-operator`,
`minimum-version-floor`, `is-unconstrained-predicate`).
`input-sanitization` passes because every string handed to `init?(_:)` is
third-party, extension-author-supplied manifest text that is validated
against a fixed grammar rather than trusted: any shape outside it —
whitespace inside the range, an unsupported operator, a wrong component
count, a non-numeric or oversized component — is rejected via `nil`
(`unsupported-grammar-rejection`, `component-bound`, `vcer-011`,
`vcer-013`).
`explicit-error-handling` passes because an unparseable string always
yields `nil` from `init?(_:)` — never a partial or best-guess
`Requirement`, never a thrown error a caller might fail to catch, and
never a crash, since `component-bound` guards the one arithmetic hazard
(`Int` overflow) through `SemanticVersion`'s own plausibility bound before
any comparison runs.
`unit-test-coverage` passes: `VSCodeEngineRangeTests.swift` exercises every
operator (caret, minimum, exact, wildcard), the `x` wildcard component,
pre-release suffixes, the sub-1.0.0 compatibility rewrite and its
exact-match carve-out, every unsupported grammar shape, whitespace
handling, oversized components, `minimumVersion`, `isUnconstrained`, and a
registry-realism check (`declaredVersionAdmitsRealRanges`) against the
distinct `engines.vscode` ranges real Open VSX web extensions publish.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
