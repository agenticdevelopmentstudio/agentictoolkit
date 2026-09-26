---
id: 9bec9953-29fb-4184-8bf6-a6c27187c99d
title: 'Hub Domain: Support'
domain: agentictoolkit://cookbook/hub/features/support
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Hub''s Support utilities: a form/notice detail-pane factory, ISO-8601
  date parsing, error normalization, blank-string trimming, a JSON value type, rail-path
  lookups, and slug rules shared by every Hub feature module.'
platforms:
- swift
- macos
- ios
tags:
- hub
- support
- forms
- json
- slug
- dates
- error-handling
depends-on: []
related:
- agentictoolkit://cookbook/htdv
references:
- packages/apple/AgenticToolkit/Hub/Features/Support/FormDetails.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubDates.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubError+Wrap.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubText.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/JSONValue.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/RailPath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/Slug.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/SupportTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Support

## Overview

The Support group is seven small, independent pieces of non-UI logic that
every Hub feature module builds on:

- **`FormDetails`** (`FormDetails.swift`) — factories for the two detail
  panes every feature uses: an editable form (`form`) and a read-only
  notice (`notice`).
- **`HubDates`** (`HubDates.swift`) — ISO-8601 string ↔ `Date` conversion
  at the three edges a feature touches dates: forms (`value`), labels
  (`display`), and request bodies (`iso`).
- **`HubError.wrap`** (`HubError+Wrap.swift`) — the universal error
  boundary: "the rail only ever shows `HubError`," normalizing whatever a
  data source throws.
- **`HubText`** (`HubText.swift`) — one helper, `nonBlank`, that turns a
  form's `""` into `nil` so optional fields encode as absent, not empty.
- **`JSONValue`** (`JSONValue.swift`) — a `Codable` JSON-document value
  type for backend fields typed as free-form JSON (bag values, metadata,
  template vars).
- **`RailPath`** (`RailPath.swift`) — two position helpers for the
  `[HTDVItem]` path a module receives in `child(for:)`.
- **`Slug`** (`Slug.swift`) — the identifier rules shared by every feature
  that lets a user pick a slug (personas, products, buckets, users).

None of the seven files depends on any of the others. `HTDVDetail`,
`HTDVItem`, `FormSpec`, `FormSection`, `FormReadOnlyField`, `FormValue`,
`FormState`, and `FormViewController` are HTDV Engine types these files
build on or return but are not among this recipe's seven given
sources — see the related HTDV Engine recipe. `HubModules` (the
`@MainActor` injection-point enum) and the base `HubError` enum (its
cases, such as `.validation`, `.notFound`, `.conflict`) are likewise
Hub-wide types referenced here, but not redescribed beyond what
`FormDetails.form` and `HubError.wrap`/`JSONValue.parse` do with them.

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

## Appearance

Not applicable — this is Hub's Support utilities (a form/notice factory,
date parsing, error normalization, blank-string handling, a JSON value
type, rail-path lookups, and slug rules), not a visual component.

## States

Not applicable — this is Hub's Support utilities (a form/notice factory,
date parsing, error normalization, blank-string handling, a JSON value
type, rail-path lookups, and slug rules), not a visual component.

## Accessibility

Not applicable — this is Hub's Support utilities (a form/notice factory,
date parsing, error normalization, blank-string handling, a JSON value
type, rail-path lookups, and slug rules), not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-support-001 | unavailable-message-constant | `FormDetails.unavailableMessage`. | `"Not available in this version"`. |
| hub-domain-support-002 | form-builds-form-view-controller | `FormDetails.form(id: "d", title: "Edit", spec: spec, values: ["name": .string("Ada")], blockedReason: "read only")` where `spec` has one text field keyed `"name"`; call `.make()` and cast to `FormViewController` (`testFormDetailBuildsFormViewControllerWithValuesAndBlockedReason`). | `detail.id == "d"`; `detail.title == "Edit"`; the cast succeeds; `form.state.value(for: "name") == .string("Ada")`; `form.state.blockedReason == "read only"`. |
| hub-domain-support-003 | notice-is-single-readonly-field, notice-delegates-to-form | `FormDetails.notice(id: "n", title: "Memory", message: FormDetails.unavailableMessage)`; call `.make()` and cast to `FormViewController` (`testNoticeIsReadOnlySingleField`). | `form.state.spec.fields.count == 1`; `form.state.spec.fields.first?.isEditable == false`; `form.state.value(for: "notice") == .string("Not available in this version")`; `form.state.spec.actions.save == nil`. |
| hub-domain-support-004 | parse-tries-fractional-then-whole | `HubDates.parse("2026-09-04T10:00:00.000Z")`, `HubDates.parse("2026-09-04T10:00:00Z")`, `HubDates.parse("yesterday")`, `HubDates.parse(nil)` (`testParseAcceptsFractionalAndWholeSeconds`). | First two are non-`nil`; last two are `nil`. |
| hub-domain-support-005 | iso-formats-fixed-utc-string | `HubDates.iso(Date(timeIntervalSince1970: 1_800_000_000))` (`testIsoRoundTrips`). | `"2027-01-15T08:00:00.000Z"`. |
| hub-domain-support-006 | iso-formats-fixed-utc-string, parse-tries-fractional-then-whole | `HubDates.parse(HubDates.iso(Date(timeIntervalSince1970: 1_800_000_000)))` (`testIsoRoundTrips`). | Equals `Date(timeIntervalSince1970: 1_800_000_000)` — a value round-trips unchanged through `iso` then `parse`. |
| hub-domain-support-007 | display-uses-humane-formatter-or-fallback | `HubDates.display(nil, fallback: "never")`; `HubDates.display("", fallback: "never")`; `HubDates.display("2026-09-04T10:00:00.000Z")` (`testDisplayFallsBackWhenMissing`). | First two both equal `"never"`; third is non-empty (uses the default `"—"` fallback path only on parse failure, which this input does not hit). |
| hub-domain-support-008 | value-maps-to-form-value | `HubDates.value(nil)`; `HubDates.value("2027-01-15T08:00:00.000Z")` (`testValueMapsToFormValue`). | First is `.null`; second is `.date(Date(timeIntervalSince1970: 1_800_000_000))`. |
| hub-domain-support-009 | wrap-passes-hub-error-through | `HubError.wrap(HubError.notFound)` (`testWrapPassesHubErrorThrough`). | `.notFound`, unchanged. |
| hub-domain-support-010 | wrap-maps-other-errors-to-unexpected | `HubError.wrap(Boom())` for a local `struct Boom: Error {}` (`testWrapMapsOtherErrorsToUnexpected`). | `.unexpected("Boom()")`. |
| hub-domain-support-011 | wrap-closure-rethrows-mapped-error | `try await HubError.wrap { () async throws -> Int in throw Boom() }`, then `try await HubError.wrap { () async throws -> Int in 7 }` (`testWrapClosureRethrowsAsHubError`). | First throws `.unexpected("Boom()")`; second returns `7`. |
| hub-domain-support-012 | wrap-preserves-caller-isolation | Call the closure-taking `wrap` from a `@MainActor` method whose closure reads and writes `@MainActor` state, from an `actor`'s method whose closure mutates the actor's own state, and from a `nonisolated` function (`testWrapCompilesForMainActorCallerReadingAndWritingState`, `testWrapCompilesForActorCaller`, `testWrapCompilesForNonisolatedCaller`). | All three compile under Swift 6 strict concurrency and return the expected incremented/literal values (`1`, `1`, `42`) — the value of this vector is that the module fails to build if `wrap`'s isolation parameter regresses. |
| hub-domain-support-013 | non-blank-trims-and-nils-blank | `HubText.nonBlank(nil)`; `HubText.nonBlank("")`; `HubText.nonBlank("   ")`; `HubText.nonBlank("  Bob  ")` (`testNonBlankReturnsNilForNilOrBlank`, `testNonBlankTrimsWhitespace`). | First three are `nil`; fourth is `"Bob"`. |
| hub-domain-support-014 | decode-precedence, encode-passes-through-case-value | `JSONValue.parse(#"{"b":1,"a":[true,null,"x"]}"#)`, then `.prettyText` (`testJSONValueParseAndPretty`). | Decodes to `.object(["b": .int(1), "a": .array([.bool(true), .null, .string("x")])])`; `.prettyText == "{\n  \"a\" : [\n    true,\n    null,\n    \"x\"\n  ],\n  \"b\" : 1\n}"` (keys sorted, `a` before `b`). |
| hub-domain-support-015 | parse-wraps-decoding-failure-as-validation | `JSONValue.parse("{nope")` (`testJSONValueParseFailureIsValidation`). | Throws `HubError.validation` whose message has the prefix `"Invalid JSON"`. |
| hub-domain-support-016 | decode-precedence, encode-passes-through-case-value | Encode `JSONValue.int(9_007_199_254_740_993)` (2^53 + 1, the smallest integer a `Double` cannot represent exactly), then decode the result (`testJSONValueLargeIntegerRoundTripsExactly`). | Encodes to the exact text `"9007199254740993"`; decodes back to `.int(9_007_199_254_740_993)` unchanged — `.int` is tried before `.number` in `init(from:)` specifically so this round-trips exactly. |
| hub-domain-support-017 | integral-number-equals-decoded-int, hash-matches-integral-number-equality | `JSONValue.number(20) == .int(20)`; `JSONValue.int(20).hashValue == JSONValue.number(20).hashValue`; `Set([JSONValue.int(20), .number(20)]).count`; `JSONValue.number(20.5) != .int(20)`; `JSONValue.int(9_007_199_254_740_993) != .number(9_007_199_254_740_992)` (`testIntegralNumberEqualsTheIntItDecodesBackAs`). | First two equalities hold; the `Set` count is `1`; the last two inequalities hold — a fractional number and a `Double` that cannot hold the `Int64` exactly are both correctly unequal. |
| hub-domain-support-018 | string-dictionary-requires-all-string-values | `JSONValue.object(["a": .string("1")]).stringDictionary`; `JSONValue.object(["a": .number(1)]).stringDictionary`; `JSONValue.array([]).stringDictionary` (`testStringDictionary`). | First is `["a": "1"]`; second and third are both `nil`. |
| hub-domain-support-019 | id-bounds-checked, last-returns-nil-for-empty-path | `RailPath.id(at: 0/1/2, in: [HTDVItem(id: "one", ...), HTDVItem(id: "two", ...)])`; `RailPath.last(path)`; `RailPath.last([])` (`testRailPath`). | `id(at:)` returns `"one"`, `"two"`, `nil` respectively; `last(path)?.id == "two"`; `last([]) == nil`. |
| hub-domain-support-020 | make-projects-to-lowercase-hyphenated, make-never-produces-leading-or-trailing-hyphen, make-returns-empty-for-no-valid-characters | `Slug.make(from: "  Research Agent  ")`; `Slug.make(from: "Hello, World!")`; `Slug.make(from: "--a--b--")`; `Slug.make(from: "")` (`testSlugMake`). | `"research-agent"`; `"hello-world"`; `"a-b"`; `""`. |
| hub-domain-support-021 | is-valid-matches-pattern | `Slug.isValid("ci-sync")`; `Slug.isValid("a")`; `Slug.isValid("-lead")`; `Slug.isValid("Trail-")`; `Slug.isValid("has space")` (`testSlugPattern`). | First two `true`; last three `false` (leading hyphen, trailing hyphen, embedded space). |
| hub-domain-support-022 | slug-length-unbounded | `Slug.isValid(String(repeating: "a", count: 300))`. | `true` — derived directly from `Slug.pattern`'s definition, which imposes no length ceiling; no test in `SupportTests.swift` exercises this specific boundary. |
| hub-domain-support-023 | pretty-text-sorted-with-null-fallback | `JSONValue.number(Double.nan).prettyText`. | `"null"` — derived directly from `prettyText`'s `guard let ... else return "null"`: `JSONEncoder` throws when asked to encode a non-finite `Double`, so this branch is reachable, but no test in `SupportTests.swift` exercises it. |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id`, `title`, `spec`, `values` (parameters to `FormDetails.form`) | `String`, `String`, `FormSpec`, `[String: FormValue]` | none — required | Caller-supplied identity, title, field layout, and initial values for the built `HTDVDetail`/`FormState`. |
| `blockedReason` (parameter to `FormDetails.form`) | `String?` | `nil` | Propagated verbatim onto the built `FormState`; not exercised further by any of these seven given sources. |
| `HubModules.markdownEditing` | `any MarkdownEditing` | `PlainTextMarkdownEditing()` | `@MainActor` injection point `FormDetails.form` reads (never writes) when constructing its `FormViewController`; the hosting app overwrites it once at launch with the real markdown module. |
| `fallback` (parameter to `HubDates.display`) | `String` | `"—"` | Caller-suppliable placeholder text shown when the given ISO string is missing or fails to parse. |
| `isolation` (parameter to the closure-taking `HubError.wrap`) | `isolated (any Actor)?` | `#isolation` (the caller's own isolation) | Not a value a caller ordinarily passes explicitly; documented here because it determines the actor isolation the `body` closure runs under. |

## Deep Linking

Not applicable: none of the seven given sources define a URL scheme,
route, or app-level navigation destination. `FormDetails.form`/`notice`
build an in-memory `HTDVDetail` consumed by the HTDV navigation state
machine (documented in the related HTDV Engine recipe), not a
deep-linkable URL.

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

## Accessibility Options

Not applicable: none of the seven given sources present any UI of their
own, so none responds to Reduce Motion, Increase Contrast, or
Differentiate Without Color; any such handling belongs to the
presentation layer (`FormViewController`) that renders the values these
sources build.

## Feature Flags

Not applicable: none of the seven given sources read a feature-flag or an
on/off settings key. Every behavior described above is unconditional
given its inputs, with no flag gating any of it.

## Analytics

Not applicable: none of the seven given sources contain an analytics or
event-tracking call.

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

## Logging

Not applicable: none of the seven given sources make a logging call (no
`import os`, no `Logger`, no `print` appears in any of them). A failure
surfaces only as a returned or thrown `HubError`, as described under
Behavioral Requirements and Edge Cases.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Support/` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: unit-test-coverage passes because `SupportTests.swift` carries
meaningful, behavior-specific assertions for every public operation
across all seven files — every requirement above traces to a named test
method, with only the two boundary cases noted in Conformance Test
Vectors 022 and 023 derived from source inspection rather than an
existing test. separation-of-concerns passes because each of the seven
files is a single, independent concern (dates, error normalization,
blank-string handling, JSON values, rail-path lookups, slug rules, or the
form/notice factory), none imports another, and none holds an AppKit/
UIKit dependency beyond `FormDetails`'s single `FormViewController` call.
explicit-error-handling passes because every failure path in these seven
sources — `HubError.wrap`'s two forms and `JSONValue.parse`'s decoding
catch — converts its input into a named `HubError` case rather than
dropping it or letting a foreign error type escape, per Edge Cases' Error
states. data-integrity passes because `JSONValue`'s hand-written equality
and hashing keep an integral `.number` and the `.int` it decodes back as
provably indistinguishable, closing the exact `isDirty`-baseline
corruption the source's own comment describes, and because `Slug.make`'s
hyphen-flushing order provably keeps its non-empty output within
`Slug.pattern`. no-hardcoded-strings fails because every user-facing
string these sources produce — `FormDetails.unavailableMessage`,
`Slug.patternMessage`, `JSONValue.parse`'s `"Invalid JSON: "` prefix, and
`HubDates.display`'s default `"—"` fallback — is a hardcoded English
literal with no localization key, per Localization above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
