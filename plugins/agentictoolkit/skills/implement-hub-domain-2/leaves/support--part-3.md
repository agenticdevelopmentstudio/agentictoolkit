<!-- leaf: implement-hub-domain-2/support--part-3 · source: hub-domain-support.md -->

# Hub Domain: Support — continued (part 3)

## Localization

None of the seven given sources route a string through a localization
table or resource key; every user-facing string below is a hardcoded
English literal:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Not available in this version` | `FormDetails.unavailableMessage`, the message every "not available" notice pane shows. |
| (none — literal, no key) | `Use lowercase letters, numbers and hyphens.` | `Slug.patternMessage`, shown when a typed slug fails `Slug.pattern`. |
| (none — literal, no key) | `Invalid JSON: ` | Prefix `JSONValue.parse` puts on the `HubError.validation` message it throws for malformed JSON, followed by the decoder's own description. |
| (none — literal, no key) | `—` | `HubDates.display`'s default `fallback` parameter value, shown for a missing or unparseable date unless the caller supplies its own. |

## Privacy

- **Data collected**: These sources handle whatever the caller passes
  through `FormDetails.form`'s `values`/`spec` (arbitrary form field
  values), `HubDates`'s date strings, and `JSONValue`'s arbitrary JSON
  payloads; none of the seven given sources itself classifies any of
  this content as sensitive — sensitivity depends entirely on what a
  specific feature stores in it.
- **Storage**: None of the seven given sources persist anything to disk,
  a database, or `UserDefaults`; every value exists only in memory for
  the duration of the call that produced it.
- **Transmission**: None of the seven given sources performs a network
  call. `HubError.wrap`'s closure form wraps whatever error a caller's
  own network call produces, but that network call and any data it
  transmits are outside these seven sources.
- **Retention**: Not applicable at this layer — nothing here defines a
  client-side expiry or cache; retention is a caller/server concern
  outside these seven sources.

## Platform Notes

- **SwiftUI**: `HubDates`, `HubError+Wrap`, `HubText`, `JSONValue`,
  `RailPath`, and `Slug` need no change — none depends on AppKit/UIKit.
  Only `FormDetails.form`'s `FormViewController` construction is
  AppKit/UIKit-specific; a SwiftUI host would replace it with a SwiftUI
  view driven by the same `FormState` (per the related HTDV Engine
  recipe's SwiftUI note), keeping `FormDetails.notice`'s one-field-spec
  logic unchanged.
- **Compose**: Model `JSONValue` as a Kotlin `sealed class` with the same
  seven cases and a hand-written `equals`/`hashCode` implementing the
  same integral-number cross-equality this file's own comment explains
  (Kotlin data-class equality would otherwise compare sealed subclasses
  first, the same bug this source works around). Model `HubDates` with
  `kotlinx-datetime`'s `Instant` and a fixed-format ISO string builder
  for `iso`. Reimplement `Slug.make` as the same lowercase-and-collapse
  character scan, and `HubError.wrap` as a function normalizing any
  `Throwable` into a sealed `HubError` type.
- **React/Web**: Model `JSONValue` as a TypeScript `JsonValue` union with
  a hand-written `deepEqual` that treats an integral `number` as equal to
  the same-valued `number` it decodes back as (JavaScript has only one
  numeric type, so the `.int`/`.number` split this source encodes may not
  need reproducing — note the platform difference rather than force it).
  Use `Date.prototype.toISOString()` in place of `HubDates.iso` and
  `Intl.DateTimeFormat` in place of the `humane` formatter. Reimplement
  `Slug.make`/`Slug.pattern` as the same character scan and regular
  expression, and `HubError.wrap` as a function normalizing any thrown
  value into a tagged `HubError` union.
- **AppKit / UIKit**: This is the source platform.
  `packages/apple/AgenticToolkit/Hub/Features/Support/HubDates.swift`,
  `HubError+Wrap.swift`, `HubText.swift`, `JSONValue.swift`,
  `RailPath.swift`, and `Slug.swift` import only `Foundation` (plus
  `AgenticToolkitHTDV` for `HubDates`/`RailPath`'s HTDV types) and hold no
  AppKit/UIKit import of their own; only `FormDetails.swift` reaches into
  a platform-specific view controller, and it does so through
  `FormViewController`, which exists in both an AppKit variant
  (`packages/apple/AgenticToolkit/HTDV/Views/macOS/FormViewController.swift`)
  and a UIKit variant
  (`packages/apple/AgenticToolkit/HTDV/Views/iOS/FormViewController+UIKit.swift`) —
  the other six files are shared unchanged between macOS and iOS.
- **WinUI 3**: Model `JSONValue` as a C# type with the same seven-case
  shape and an `IEquatable<JSONValue>` implementation giving the same
  `int`/`double` cross-equality, serialized with `System.Text.Json`.
  Model `HubDates` with `DateTimeOffset` and the fixed format string
  `"yyyy-MM-dd'T'HH:mm:ss.fff'Z'"` for the equivalent of `iso`, parsing
  with `DateTimeOffset.TryParse` under `DateTimeStyles.RoundtripKind` in
  place of the fractional/whole two-step `parse`. Reimplement
  `Slug.pattern` with `System.Text.RegularExpressions.Regex`, and model
  `HubError.wrap` as a static method that normalizes any `Exception` into
  a `HubError`-derived exception type, with the closure overload taking a
  `Func<Task<T>>` in place of the caller-isolation-preserving Swift
  overload (WinUI 3 has no actor-isolation analog to preserve).

## Design Decisions

**Decision**: `JSONValue` implements `==` and `hash(into:)` by hand
instead of relying on the compiler-synthesized, case-first conformance,
treating `.int(n)` and `.number(d)` as equal (and equally hashing) when
`d` represents `n` exactly.
**Rationale**: `JSONDecoder` always decodes a JSON integer literal as
`.int` and a value written with a decimal point as `.number`; a
synthesized, case-first `==` would call a re-decoded `.number(20)`
different from an original `.int(20)` baseline. The source's own comment
states this previously misfired a form's `isDirty` baseline comparison,
leaving Save enabled on an untouched form and producing spurious discard
prompts.
**Approved**: pending

**Decision**: `HubDates` builds its four ISO-8601 formatters as
`private static let` values instead of constructing one per call.
**Rationale**: The source's own comment states construction is expensive
enough to show up when a rail formats a few hundred rows; both
`Date.ISO8601FormatStyle` and `DateFormatter` are safe to share as
immutable singletons once built and never mutated afterward.
**Approved**: pending

**Decision**: The closure-taking `HubError.wrap` declares its `isolation`
parameter as `isolated (any Actor)? = #isolation` rather than leaving the
closure's isolation to Swift's default inference.
**Rationale**: Without this parameter, Swift 6 strict concurrency would
force the closure `nonisolated`, breaking a `@MainActor` caller whose
closure reads and writes main-actor state without an explicit
`MainActor.run` hop. The source's own doc comment states this specific
compile-time regression is what the parameter guards against, and three
of `SupportTests.swift`'s test methods exist solely to fail to build if
it regresses.
**Approved**: pending

**Decision**: `Slug.make` tracks a `pendingHyphen` flag and only flushes
it (appending one `"-"`) immediately before the next allowed character,
and only when the output built so far is non-empty — rather than
converting every disallowed character to a hyphen in place.
**Rationale**: This guarantees `Slug.make`'s non-empty output already
satisfies `Slug.pattern` (which forbids a leading or trailing hyphen and
any run of two or more hyphens) without a second validation pass. The
ordering this depends on — never flush while `out` is empty, never flush
a still-pending hyphen at end of input — is not obvious from a single
call site, which is why it is called out here rather than left implicit.
**Approved**: pending
