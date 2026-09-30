<!-- leaf: implement-hub-domain-2/support--edge-cases · source: hub-domain-support.md -->

# Hub Domain: Support

**Rules** (cite as `implement-hub-domain-2/support--edge-cases#<slug>`):

- `null-and-empty-input` MUST — HubDates.parse(nil) and HubDates.parse("") MUST both return nil (MUST, parse-tries-fractional-then-whole). …
- `boundary-values` MUST — RailPath.id(at:in:) MUST return nil exactly at and beyond path.count (and for any negative index), never trap (MUST, …
- `concurrent-access` MUST — All seven files are stateless value types or static namespaces over immutable data (HubDates's four formatters are …
- `error-states` MUST — HubError.wrap(_:) MUST convert any non-HubError into .unexpected(String(describing: error)), so no error this boundary …

## Edge Cases

- **Null and empty input**: `HubDates.parse(nil)` and `HubDates.parse("")`
  MUST both return `nil` (MUST, `parse-tries-fractional-then-whole`).
  `HubText.nonBlank(nil)` and `HubText.nonBlank("")` MUST both return
  `nil` (MUST, `non-blank-trims-and-nils-blank`). `Slug.make(from: "")`
  MUST return `""` (MUST, `make-returns-empty-for-no-valid-characters`).
  `RailPath.last([])` MUST return `nil` (MUST,
  `last-returns-nil-for-empty-path`). `JSONValue.parse("")` (empty
  string, not valid JSON) MUST throw `HubError.validation` via
  `parse-wraps-decoding-failure-as-validation`, since an empty string
  decodes as none of the seven cases.
- **Boundary values**: `RailPath.id(at:in:)` MUST return `nil` exactly at
  and beyond `path.count` (and for any negative index), never trap (MUST,
  `id-bounds-checked`). `Slug.pattern`/`Slug.isValid(_:)` impose no
  maximum length, so a 300-character all-lowercase-letter string MUST
  still validate (MUST, `slug-length-unbounded`). `JSONValue.int` MUST
  round-trip a value as large as 2^53 + 1 exactly, the smallest integer a
  `Double` cannot represent exactly, because `Int64` decoding is tried
  before `Double` decoding (MUST, `decode-precedence`, see Conformance
  Test Vector 016).
- **Concurrent access**: All seven files are stateless value types or
  static namespaces over immutable data (`HubDates`'s four formatters are
  built once and never mutated, per `formatters-built-once`), except
  `HubModules.markdownEditing`, which is `@MainActor`-isolated and thus
  serialized by the main actor rather than raced — none of these seven
  sources themselves introduce a shared mutable variable a second call
  could observe mid-mutation. `HubError.wrap(isolation:_:)`'s closure
  form MUST run its `body` under the caller's own actor isolation rather
  than a fixed one (MUST, `wrap-preserves-caller-isolation`), so two
  concurrent callers on different actors each run fully isolated within
  their own actor; nothing in this file coordinates between them, since
  coordinating unrelated callers is not this helper's job.
- **Error states**: `HubError.wrap(_:)` MUST convert any non-`HubError`
  into `.unexpected(String(describing: error))`, so no error this
  boundary sees is ever dropped silently (MUST,
  `wrap-maps-other-errors-to-unexpected`). `JSONValue.parse(_:)` MUST
  convert any decoding failure into a `HubError.validation` carrying a
  human-readable message rather than letting the raw `DecodingError`
  escape (MUST, `parse-wraps-decoding-failure-as-validation`). A
  `CancellationError` thrown into the closure-taking `HubError.wrap` is
  not special-cased: it is wrapped into
  `.unexpected("CancellationError()")` exactly like any other
  non-`HubError`, per `wrap-maps-other-errors-to-unexpected` — the source
  draws no distinction between cancellation and any other thrown error.
- **Offline or disconnected state**: None of the seven given sources
  make a network call, define a timeout, or define retry/backoff
  behavior of their own; `HubError.wrap` normalizes whatever error a
  caller's own network call produces, but the network call itself, and
  any offline/connectivity handling around it, is outside these seven
  sources (fact, not a gap — a thrown error is reported via `wrap`, not
  lost, just with no time bound or automatic retry defined at this
  layer).
