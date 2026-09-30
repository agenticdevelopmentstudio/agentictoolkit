<!-- leaf: implement-hub-domain-2/support--part-2 · source: hub-domain-support.md -->

# Hub Domain: Support — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/support--part-2#<slug>`):

- `unavailable-message-constant` MUST
- `form-builds-form-view-controller` MUST
- `notice-is-single-readonly-field` MUST
- `notice-delegates-to-form` MUST
- `formatters-built-once` MUST
- `parse-tries-fractional-then-whole` MUST
- `iso-formats-fixed-utc-string` MUST
- `display-uses-humane-formatter-or-fallback` MUST
- `value-maps-to-form-value` MUST
- `wrap-passes-hub-error-through` MUST
- `wrap-maps-other-errors-to-unexpected` MUST
- `wrap-closure-rethrows-mapped-error` MUST
- `wrap-preserves-caller-isolation` MUST
- `non-blank-trims-and-nils-blank` MUST
- `decode-precedence` MUST
- `encode-passes-through-case-value` MUST
- `pretty-text-sorted-with-null-fallback` MUST
- `parse-wraps-decoding-failure-as-validation` MUST
- `integral-number-equals-decoded-int` MUST
- `hash-matches-integral-number-equality` MUST
- `string-dictionary-requires-all-string-values` MUST
- `id-bounds-checked` MUST
- `last-returns-nil-for-empty-path` MUST
- `make-projects-to-lowercase-hyphenated` MUST
- `make-never-produces-leading-or-trailing-hyphen` MUST
- `make-returns-empty-for-no-valid-characters` MUST
- `is-valid-matches-pattern` MUST
- `slug-length-unbounded` MUST

## Behavioral Requirements

### FormDetails.swift — form/notice detail-pane factory

- **unavailable-message-constant**: `FormDetails.unavailableMessage` MUST
  be the static string `"Not available in this version"`.
- **form-builds-form-view-controller**: `FormDetails.form(id:title:spec:values:blockedReason:)`
  MUST return an `HTDVDetail` whose `id` and `title` are the given `id`
  and `title` arguments, and whose `make()` closure builds a `FormState`
  from the given `spec` and `values`, sets that `FormState`'s
  `blockedReason` to the given `blockedReason` (default `nil`), and
  returns a `FormViewController` constructed with that state and
  `HubModules.markdownEditing`.
- **notice-is-single-readonly-field**: `FormDetails.notice(id:title:message:)`
  MUST build a `FormSpec` with exactly one section containing exactly one
  `.readOnly(FormReadOnlyField(key: "notice", label: title))` field.
- **notice-delegates-to-form**: `FormDetails.notice(id:title:message:)`
  MUST call `FormDetails.form(id:title:spec:values:)` with that one-field
  spec and `values: ["notice": .string(message)]`, supplying no
  `blockedReason` argument, so it takes `form`'s default `nil`.

### HubDates.swift — ISO-8601 date parsing and formatting

- **formatters-built-once**: `HubDates` MUST build its `fractional`,
  `whole`, `output`, and `humane` formatters as `private static let`
  constants — constructed exactly once, never mutated afterward — per the
  source's own comment that building one per call "is expensive enough to
  show up when a rail formats a few hundred rows."
- **parse-tries-fractional-then-whole**: `HubDates.parse(_:)` MUST return
  `nil` when given `nil` or an empty string, and otherwise MUST attempt
  `fractional.parse(iso)` (ISO-8601 including fractional seconds) first,
  falling back to `whole.parse(iso)` (ISO-8601 without fractional seconds)
  when the first attempt fails, and MUST return `nil` when both fail.
- **iso-formats-fixed-utc-string**: `HubDates.iso(_:)` MUST format the
  given `Date` with the `output` formatter — `Calendar(identifier:
  .iso8601)`, `Locale(identifier: "en_US_POSIX")`,
  `TimeZone(secondsFromGMT: 0)`, and the fixed pattern
  `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` — regardless of the caller's current
  locale or time zone.
- **display-uses-humane-formatter-or-fallback**: `HubDates.display(_:fallback:)`
  MUST return the caller-supplied `fallback` (default `"—"`) when
  `HubDates.parse` of the given string returns `nil`, and otherwise MUST
  format the parsed `Date` with the `humane` formatter (`dateStyle:
  .medium`, `timeStyle: .short`), using that formatter's own default
  locale and time zone rather than the fixed UTC/POSIX pair `output`
  uses.
- **value-maps-to-form-value**: `HubDates.value(_:)` MUST return
  `FormValue.null` when `HubDates.parse` of the given string returns
  `nil`, and otherwise MUST return `FormValue.date` wrapping the parsed
  `Date`.

### HubError+Wrap.swift — error normalization

- **wrap-passes-hub-error-through**: `HubError.wrap(_:)` MUST return its
  argument unchanged, cast to `HubError`, when that argument already is a
  `HubError`.
- **wrap-maps-other-errors-to-unexpected**: `HubError.wrap(_:)` MUST
  return `.unexpected(String(describing: error))` for any argument that
  is not a `HubError`.
- **wrap-closure-rethrows-mapped-error**: The closure-taking
  `HubError.wrap(isolation:_:)` overload MUST return the value produced
  by calling its `body` closure when `body` does not throw, and MUST
  throw `HubError.wrap` of whatever error `body` threw when it does.
- **wrap-preserves-caller-isolation**: The closure-taking
  `HubError.wrap(isolation:_:)` overload MUST declare its `isolation`
  parameter as `isolated (any Actor)? = #isolation`, so a caller's `body`
  closure runs under the caller's own actor isolation — main actor, a
  specific actor, or nonisolated — instead of being forced `nonisolated`,
  per the source's own comment that this lets a `@MainActor` caller
  "capture `self`" and still compile under Swift 6 strict concurrency
  "without hoisting reads out or wrapping writes in `MainActor.run`."

### HubText.swift — blank-string normalization

- **non-blank-trims-and-nils-blank**: `HubText.nonBlank(_:)` MUST return
  `nil` when given `nil` or a string that is empty, or contains only
  whitespace and/or newline characters after trimming with
  `.whitespacesAndNewlines`, and otherwise MUST return the trimmed
  string.

### JSONValue.swift — JSON document value type

- **decode-precedence**: `JSONValue.init(from:)` MUST decode a
  single-value container by trying, in order, nil, `Bool`, `Int64`,
  `Double`, `String`, `[JSONValue]`, then `[String: JSONValue]`, taking
  the first that succeeds as `.null`, `.bool`, `.int`, `.number`,
  `.string`, `.array`, or `.object` respectively, and MUST throw
  `DecodingError.dataCorruptedError` when none of the seven succeeds.
- **encode-passes-through-case-value**: `JSONValue.encode(to:)` MUST
  encode each case's associated value directly into a single-value
  container — `.object` as its dictionary, `.array` as its array,
  `.string` as its string, `.int` as its `Int64`, `.number` as its
  `Double`, `.bool` as its bool, `.null` via `encodeNil()` — with no
  wrapper.
- **pretty-text-sorted-with-null-fallback**: `JSONValue.prettyText` MUST
  encode `self` with a `JSONEncoder` whose `outputFormatting` is
  `[.prettyPrinted, .sortedKeys]` and return the resulting UTF-8 string,
  falling back to the literal string `"null"` when encoding or the
  UTF-8-to-`String` conversion fails.
- **parse-wraps-decoding-failure-as-validation**: `JSONValue.parse(_:)`
  MUST decode the given string as UTF-8 JSON and, on failure, MUST throw
  `HubError.validation` with a message beginning `"Invalid JSON: "`
  followed by the thrown `DecodingError`'s `decodingDebugDescription`
  (its `Context.debugDescription`) when the underlying error is a
  `DecodingError`, or by `error.localizedDescription` for any other
  thrown error.
- **integral-number-equals-decoded-int**: `JSONValue.==` MUST treat
  `.int(n)` and `.number(d)` as equal whenever `Int64(exactly: d) == n`,
  in addition to the ordinary same-case equalities for `.object`,
  `.array`, `.string`, `.int`-`.int`, `.number`-`.number`, `.bool`, and
  `.null`; a `.number` that is not exactly representable as `Int64`, or
  whose exact `Int64` value differs from `n`, MUST compare unequal to
  `.int(n)`.
- **hash-matches-integral-number-equality**: `JSONValue.hash(into:)` MUST
  hash an integral `.number` (one exactly representable as `Int64`)
  identically to the `.int` holding that same value, and MUST hash a
  non-integral `.number` on a hash tag distinct from `.int`/integral
  `.number`, so that `==` and `hash(into:)` stay consistent with each
  other.
- **string-dictionary-requires-all-string-values**: `JSONValue.stringDictionary`
  MUST return `nil` when `self` is not `.object`, and MUST return `nil`
  when any value inside that object is not `.string`; only when `self` is
  `.object` and every value is `.string` MUST it return the
  `[String: String]` dictionary of the unwrapped strings.

### RailPath.swift — rail-path position lookups

- **id-bounds-checked**: `RailPath.id(at:in:)` MUST return `nil` when
  `index` is not a valid index of `path` (per
  `path.indices.contains(index)`), and otherwise MUST return
  `path[index].id`.
- **last-returns-nil-for-empty-path**: `RailPath.last(_:)` MUST return
  `path.last`, which is `nil` when `path` is empty.

### Slug.swift — slug rules

- **make-projects-to-lowercase-hyphenated**: `Slug.make(from:)` MUST
  lowercase the input, keep only the ASCII letters `a`-`z` and digits
  `0`-`9`, and collapse every run of one or more disallowed characters
  between two kept characters into a single hyphen — implemented with a
  `pendingHyphen` flag that is flushed (appending one `"-"`) only
  immediately before the next allowed character is appended, and only
  when the output built so far is non-empty.
- **make-never-produces-leading-or-trailing-hyphen**: `Slug.make(from:)`
  MUST NOT emit a leading or trailing hyphen in its non-empty output: a
  pending hyphen is never flushed while the output built so far is still
  empty, and a pending hyphen still outstanding at the end of the input
  is never flushed at all.
- **make-returns-empty-for-no-valid-characters**: `Slug.make(from:)` MUST
  return the empty string `""` when the input contains no ASCII letter or
  digit.
- **is-valid-matches-pattern**: `Slug.isValid(_:)` MUST return `true` if
  and only if the given string matches `Slug.pattern` as a whole-string
  regular expression: lowercase letters and digits only, with any
  interior hyphens single and never leading or trailing.
- **slug-length-unbounded**: `Slug.pattern` and `Slug.isValid(_:)` MUST
  NOT reject a slug for length alone; the given source defines no maximum
  length for either `Slug.pattern` or `Slug.make(from:)`'s output.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id`, `title`, `spec`, `values` (parameters to `FormDetails.form`) | `String`, `String`, `FormSpec`, `[String: FormValue]` | none — required | Caller-supplied identity, title, field layout, and initial values for the built `HTDVDetail`/`FormState`. |
| `blockedReason` (parameter to `FormDetails.form`) | `String?` | `nil` | Propagated verbatim onto the built `FormState`; not exercised further by any of these seven given sources. |
| `HubModules.markdownEditing` | `any MarkdownEditing` | `PlainTextMarkdownEditing()` | `@MainActor` injection point `FormDetails.form` reads (never writes) when constructing its `FormViewController`; the hosting app overwrites it once at launch with the real markdown module. |
| `fallback` (parameter to `HubDates.display`) | `String` | `"—"` | Caller-suppliable placeholder text shown when the given ISO string is missing or fails to parse. |
| `isolation` (parameter to the closure-taking `HubError.wrap`) | `isolated (any Actor)?` | `#isolation` (the caller's own isolation) | Not a value a caller ordinarily passes explicitly; documented here because it determines the actor isolation the `body` closure runs under. |

