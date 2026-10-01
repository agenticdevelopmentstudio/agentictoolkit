---
id: 9bec9953-29fb-4184-8bf6-a6c27187c99d
title: Support
domain: agentictoolkit://cookbook/adh/hub/support
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/ui/navigation/htdv
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

# Support

## Overview

The Support group is seven small, independent pieces of non-UI logic that every
feature module in this domain builds on:

- a **form/notice detail-pane factory** — builds the two detail panes every
  feature uses: an editable form and a read-only notice.
- **date parsing and formatting** — ISO-8601 string ↔ date conversion at the
  three edges a feature touches dates: forms, labels, and request bodies.
- an **error normalizer** — the universal error boundary: a feature's rail
  only ever shows the shared named error type, which normalizes whatever a
  data source throws.
- a **blank-string helper** — one operation that turns a form's `""` into an
  absent value, so optional fields encode as absent, not empty.
- a **JSON document value type** — for backend fields typed as free-form JSON
  (bag values, metadata, template vars).
- **rail-path position lookups** — two helpers for the path array a module
  receives when resolving a child.
- **slug rules** — the identifier rules shared by every feature that lets a
  user pick a slug (personas, products, buckets, users).

None of the seven pieces depends on any of the others. A detail-pane
descriptor, a path item, a form specification, a form section, a read-only
field descriptor, a form value wrapper, a form's mutable state object, and a
form-hosting view are types these pieces build on or return but are not among
this recipe's seven given pieces — see the related HTDV Engine recipe. A
shared injection point for the markdown-editing module, and the domain's own
shared error type (whose categories include validation, not-found, and
conflict) are likewise domain-wide concepts referenced here, but not
redescribed beyond what the form/notice factory and the error
normalizer/JSON parser do with them.

## Behavioral Requirements

### Form/notice detail-pane factory

- **unavailable-message-constant**: A shared "not available" message
  constant MUST be the static string `"Not available in this version"`.
- **form-builds-editable-detail-pane**: Building a form detail (given an id,
  title, field specification, initial values, and an optional blocked
  reason) MUST return a detail-pane descriptor whose id and title are the
  given id and title arguments, and whose content-builder produces a form's
  mutable state from the given field specification and initial values, sets
  that state's blocked reason to the given value (default absent), and
  returns a form-hosting view constructed with that state and the shared
  markdown-editing injection point.
- **notice-is-single-readonly-field**: Building a read-only notice (given an
  id, title, and message) MUST build a field specification with exactly one
  section containing exactly one read-only field keyed `"notice"` and
  labeled with the given title.
- **notice-delegates-to-form**: Building a read-only notice MUST delegate to
  building an editable form with that one-field specification and the
  initial value `{"notice": message}`, supplying no blocked-reason argument,
  so it takes the form-builder's default absent value.

### Date parsing and formatting

- **formatters-built-once**: The date-parsing/formatting helper MUST build
  its four formatters (for fractional-second ISO-8601, whole-second
  ISO-8601, wire output, and human-readable display) as constants —
  constructed exactly once, never mutated afterward — per the source's own
  comment that building one per call "is expensive enough to show up when a
  rail formats a few hundred rows."
- **parse-tries-fractional-then-whole**: Parsing an ISO-8601 string MUST
  return absent when given an absent value or an empty string, and
  otherwise MUST attempt to parse it as ISO-8601 including fractional
  seconds first, falling back to parsing it as ISO-8601 without fractional
  seconds when the first attempt fails, and MUST return absent when both
  fail.
- **iso-formats-fixed-utc-string**: Formatting a date to its ISO-8601 wire
  representation MUST use a fixed calendar/locale/time-zone combination —
  the ISO-8601 calendar, the POSIX-invariant locale, and UTC (zero offset) —
  and the fixed pattern `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, regardless of the
  caller's current locale or time zone.
- **display-uses-humane-formatter-or-fallback**: Formatting a date for
  display MUST return the caller-supplied fallback (default `"—"`) when
  parsing the given string fails, and otherwise MUST format the parsed date
  with a medium-date/short-time human-readable formatter, using that
  formatter's own default locale and time zone rather than the fixed
  UTC/invariant pair the wire formatter uses.
- **value-maps-to-form-value**: Mapping an ISO-8601 string to a form value
  MUST return a null form value when parsing the given string fails, and
  otherwise MUST return a date-typed form value wrapping the parsed date.

### Error normalization

- **wrap-passes-hub-error-through**: Normalizing an error MUST return its
  argument unchanged when that argument already is the shared named error
  type.
- **wrap-maps-other-errors-to-unexpected**: Normalizing an error MUST return
  an "unexpected" case carrying the argument's string description for any
  argument that is not already the shared named error type.
- **wrap-closure-rethrows-mapped-error**: The closure-taking form of error
  normalization MUST return the value produced by calling its body when the
  body does not throw, and MUST throw the normalized form of whatever error
  the body threw when it does.

### Blank-string normalization

- **non-blank-trims-and-nils-blank**: Trimming a string to a non-blank
  value MUST return absent when given an absent value or a string that is
  empty, or contains only whitespace and/or newline characters after
  trimming, and otherwise MUST return the trimmed string.

### JSON document value type

- **decode-precedence**: Decoding a JSON document value from a
  single-value container MUST try, in order, null, boolean, 64-bit integer,
  floating-point number, string, array-of-values, then object-of-values,
  taking the first that succeeds as the matching case, and MUST fail with a
  data-corrupted decoding error when none of the seven succeeds.
- **encode-passes-through-case-value**: Encoding a JSON document value MUST
  encode each case's associated value directly into a single-value
  container — an object as its dictionary, an array as its array, a string
  as its string, an integer as a 64-bit integer, a number as a
  floating-point value, a boolean as its bool, and null via the encoder's
  own null-encoding call — with no wrapper.
- **pretty-text-sorted-with-null-fallback**: Producing a pretty-printed text
  form of a JSON document value MUST encode it with pretty-printing and
  sorted keys enabled and return the resulting UTF-8 string, falling back to
  the literal string `"null"` when encoding or the UTF-8-to-text conversion
  fails.
- **parse-wraps-decoding-failure-as-validation**: Parsing a string as a
  JSON document value MUST decode it as UTF-8 JSON and, on failure, MUST
  throw a validation error with a message beginning `"Invalid JSON: "`
  followed by the underlying decoding error's debug description when the
  underlying error is a decoding error, or by that error's own localized
  description for any other thrown error.
- **integral-number-equals-decoded-int**: Equality between two JSON
  document values MUST treat an integer case and a number case as equal
  whenever the number is exactly representable as that same 64-bit integer
  value, in addition to the ordinary same-case equalities for object,
  array, string, integer-integer, number-number, boolean, and null; a
  number that is not exactly representable as a 64-bit integer, or whose
  exact integer value differs, MUST compare unequal to the integer case.
- **hash-matches-integral-number-equality**: Hashing a JSON document value
  MUST hash an integral number (one exactly representable as a 64-bit
  integer) identically to the integer case holding that same value, and
  MUST hash a non-integral number on a hash tag distinct from the
  integer/integral-number case, so that equality and hashing stay
  consistent with each other.
- **string-dictionary-requires-all-string-values**: Converting a JSON
  document value to a string-to-string dictionary MUST return absent when
  the value is not an object, and MUST return absent when any value inside
  that object is not a string; only when the value is an object and every
  value is a string MUST it return the dictionary of the unwrapped strings.

### Rail-path position lookups

- **id-bounds-checked**: Looking up the id at a position in a path array
  MUST return absent when the given index is not a valid index of the
  array, and otherwise MUST return that position's id.
- **last-returns-nil-for-empty-path**: Looking up the last item of a path
  array MUST return the array's last element, which is absent when the
  array is empty.

### Slug rules

- **make-projects-to-lowercase-hyphenated**: Projecting an input string to a
  slug MUST lowercase the input, keep only the ASCII letters `a`-`z` and
  digits `0`-`9`, and collapse every run of one or more disallowed
  characters between two kept characters into a single hyphen — implemented
  with a pending-hyphen flag that is flushed (appending one `"-"`) only
  immediately before the next allowed character is appended, and only when
  the output built so far is non-empty.
- **make-never-produces-leading-or-trailing-hyphen**: Projecting an input
  string to a slug MUST NOT emit a leading or trailing hyphen in its
  non-empty output: a pending hyphen is never flushed while the output
  built so far is still empty, and a pending hyphen still outstanding at the
  end of the input is never flushed at all.
- **make-returns-empty-for-no-valid-characters**: Projecting an input
  string to a slug MUST return the empty string `""` when the input
  contains no ASCII letter or digit.
- **is-valid-matches-pattern**: Validating a slug MUST return `true` if and
  only if the given string matches the shared slug pattern as a
  whole-string match: lowercase letters and digits only, with any interior
  hyphens single and never leading or trailing.
- **slug-length-unbounded**: The shared slug pattern and slug validation
  MUST NOT reject a slug for length alone; the given source defines no
  maximum length for either the pattern or the slug-projection output.

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
| hub-domain-support-001 | unavailable-message-constant | Reading the shared "not available" message constant. | Equals `"Not available in this version"` — verified by an existing test in the source. |
| hub-domain-support-002 | form-builds-editable-detail-pane | Building a form detail with id `"d"`, title `"Edit"`, a specification with one text field keyed `"name"`, initial values `{"name": "Ada"}`, and blocked reason `"read only"`; then invoking its content-builder. | The built detail's id is `"d"` and title is `"Edit"`; the built content is a form-hosting view; that view's state has `"name"` equal to `"Ada"` and a blocked reason of `"read only"` — verified by an existing test in the source. |
| hub-domain-support-003 | notice-is-single-readonly-field, notice-delegates-to-form | Building a read-only notice with id `"n"`, title `"Memory"`, and message equal to the shared "not available" constant; then invoking its content-builder. | The built form's field specification has exactly one field, that field is read-only, its value equals `"Not available in this version"`, and the specification defines no save action — verified by an existing test in the source. |
| hub-domain-support-004 | parse-tries-fractional-then-whole | Parsing `"2026-09-04T10:00:00.000Z"`, `"2026-09-04T10:00:00Z"`, `"yesterday"`, and an absent value. | The first two are non-absent; the last two are absent — verified by an existing test in the source. |
| hub-domain-support-005 | iso-formats-fixed-utc-string | Formatting the instant 1,800,000,000 seconds after the epoch to its wire representation. | `"2027-01-15T08:00:00.000Z"` — verified by an existing test in the source. |
| hub-domain-support-006 | iso-formats-fixed-utc-string, parse-tries-fractional-then-whole | Parsing the wire representation just produced from the instant 1,800,000,000 seconds after the epoch. | Equals that same instant — a value round-trips unchanged through formatting then parsing — verified by an existing test in the source. |
| hub-domain-support-007 | display-uses-humane-formatter-or-fallback | Formatting an absent value for display with fallback `"never"`; formatting an empty string for display with fallback `"never"`; formatting `"2026-09-04T10:00:00.000Z"` for display with the default fallback. | The first two both equal `"never"`; the third is non-empty (uses the default `"—"` fallback path only on parse failure, which this input does not hit) — verified by an existing test in the source. |
| hub-domain-support-008 | value-maps-to-form-value | Mapping an absent value to a form value; mapping `"2027-01-15T08:00:00.000Z"` to a form value. | The first is the null form value; the second is a date-typed form value wrapping the instant 1,800,000,000 seconds after the epoch — verified by an existing test in the source. |
| hub-domain-support-009 | wrap-passes-hub-error-through | Normalizing an already-normalized "not found" error. | Returns the same "not found" error, unchanged — verified by an existing test in the source. |
| hub-domain-support-010 | wrap-maps-other-errors-to-unexpected | Normalizing a foreign error value whose description is `"Boom()"`. | An "unexpected" case carrying the description `"Boom()"` — verified by an existing test in the source. |
| hub-domain-support-011 | wrap-closure-rethrows-mapped-error | Calling the closure-taking normalizer with a body that throws the same foreign error, then with a body that returns `7`. | The first throws the "unexpected" case carrying `"Boom()"`; the second returns `7` — verified by an existing test in the source. |
| hub-domain-support-013 | non-blank-trims-and-nils-blank | Trimming an absent value, an empty string, a whitespace-only string, and `"  Bob  "` to non-blank. | The first three are absent; the fourth is `"Bob"` — verified by an existing test in the source. |
| hub-domain-support-014 | decode-precedence, encode-passes-through-case-value | Parsing the JSON text `{"b":1,"a":[true,null,"x"]}` as a JSON document value, then producing its pretty-printed text. | Decodes to an object with `b` equal to the integer `1` and `a` equal to the array `[true, null, "x"]`; the pretty-printed text is `"{\n  \"a\" : [\n    true,\n    null,\n    \"x\"\n  ],\n  \"b\" : 1\n}"` (keys sorted, `a` before `b`) — verified by an existing test in the source. |
| hub-domain-support-015 | parse-wraps-decoding-failure-as-validation | Parsing the malformed JSON text `{nope`. | Throws a validation error whose message has the prefix `"Invalid JSON"` — verified by an existing test in the source. |
| hub-domain-support-016 | decode-precedence, encode-passes-through-case-value | Encoding the integer value 9,007,199,254,740,993 (2^53 + 1, the smallest integer a floating-point number cannot represent exactly), then decoding the result. | Encodes to the exact text `"9007199254740993"`; decodes back to the same integer value unchanged — the integer case is tried before the number case specifically so this round-trips exactly — verified by an existing test in the source. |
| hub-domain-support-017 | integral-number-equals-decoded-int, hash-matches-integral-number-equality | Comparing the number value `20` to the integer value `20`; hashing both; counting the size of a set containing both; comparing the number value `20.5` to the integer value `20`; comparing the integer value 9,007,199,254,740,993 to the number value 9,007,199,254,740,992. | The first two equalities hold; the set's size is `1`; the last two inequalities hold — a fractional number and a floating-point value that cannot hold the same 64-bit integer exactly are both correctly unequal — verified by an existing test in the source. |
| hub-domain-support-018 | string-dictionary-requires-all-string-values | Converting an object `{"a": "1"}` to a string dictionary; converting an object `{"a": 1}` to a string dictionary; converting an empty array to a string dictionary. | The first is `{"a": "1"}`; the second and third are both absent — verified by an existing test in the source. |
| hub-domain-support-019 | id-bounds-checked, last-returns-nil-for-empty-path | Looking up the id at positions 0, 1, and 2 in a two-item path (`"one"`, `"two"`); looking up the last item of that path; looking up the last item of an empty path. | Looking up by position returns `"one"`, `"two"`, and absent respectively; the last item of the two-item path has id `"two"`; the last item of the empty path is absent — verified by an existing test in the source. |
| hub-domain-support-020 | make-projects-to-lowercase-hyphenated, make-never-produces-leading-or-trailing-hyphen, make-returns-empty-for-no-valid-characters | Projecting `"  Research Agent  "`, `"Hello, World!"`, `"--a--b--"`, and `""` to slugs. | `"research-agent"`; `"hello-world"`; `"a-b"`; `""` — verified by an existing test in the source. |
| hub-domain-support-021 | is-valid-matches-pattern | Validating the slugs `"ci-sync"`, `"a"`, `"-lead"`, `"Trail-"`, and `"has space"`. | The first two are true; the last three are false (leading hyphen, trailing hyphen, embedded space) — verified by an existing test in the source. |
| hub-domain-support-022 | slug-length-unbounded | Validating a 300-character string of the repeated letter `"a"`. | `true` — derived directly from the shared slug pattern's definition, which imposes no length ceiling; no existing test exercises this specific boundary. |
| hub-domain-support-023 | pretty-text-sorted-with-null-fallback | Producing the pretty-printed text of a number value holding not-a-number. | `"null"` — derived directly from the pretty-text operation's own fallback: the encoder throws when asked to encode a non-finite floating-point value, so this branch is reachable, but no existing test exercises it. |

## Edge Cases

- **Null and empty input**: Parsing an absent value and parsing an empty
  string MUST both return absent (MUST, `parse-tries-fractional-then-whole`).
  Trimming an absent value and trimming an empty string to non-blank MUST
  both return absent (MUST, `non-blank-trims-and-nils-blank`). Projecting an
  empty string to a slug MUST return `""` (MUST,
  `make-returns-empty-for-no-valid-characters`). Looking up the last item of
  an empty path array MUST return absent (MUST,
  `last-returns-nil-for-empty-path`). Parsing an empty string as a JSON
  document value (empty string, not valid JSON) MUST throw a validation
  error via `parse-wraps-decoding-failure-as-validation`, since an empty
  string decodes as none of the seven cases.
- **Boundary values**: Looking up an id by position MUST return absent
  exactly at and beyond the array's length (and for any negative index),
  never trap (MUST, `id-bounds-checked`). The shared slug pattern and slug
  validation impose no maximum length, so a 300-character
  all-lowercase-letter string MUST still validate (MUST,
  `slug-length-unbounded`). The integer case of a JSON document value MUST
  round-trip a value as large as 2^53 + 1 exactly, the smallest integer a
  floating-point number cannot represent exactly, because 64-bit integer
  decoding is tried before floating-point decoding (MUST,
  `decode-precedence`, see Conformance Test Vector 016).
- **Concurrent access**: All seven pieces are stateless value types or
  static namespaces over immutable data (the date helper's four formatters
  are built once and never mutated, per `formatters-built-once`), except
  the shared markdown-editing injection point, which is confined to a
  single execution context and thus serialized rather than raced — none of
  these seven pieces themselves introduce a shared mutable variable a
  second call could observe mid-mutation. The closure-taking error
  normalizer MUST run its body under the caller's own execution context
  rather than a fixed one (see Platform Notes), so two concurrent callers on
  different execution contexts each run fully isolated within their own
  context; nothing in this piece coordinates between them, since
  coordinating unrelated callers is not this helper's job.
- **Error states**: Normalizing an error MUST convert any non-normalized
  error into an "unexpected" case carrying its string description, so no
  error this boundary sees is ever dropped silently (MUST,
  `wrap-maps-other-errors-to-unexpected`). Parsing a JSON document value
  MUST convert any decoding failure into a validation error carrying a
  human-readable message rather than letting the raw decoding error escape
  (MUST, `parse-wraps-decoding-failure-as-validation`). A cancellation
  signal thrown into the closure-taking error normalizer is not
  special-cased: it is wrapped into an "unexpected" case exactly like any
  other non-normalized error, per `wrap-maps-other-errors-to-unexpected` —
  the source draws no distinction between cancellation and any other thrown
  error.
- **Offline or disconnected state**: None of the seven given pieces make a
  network call, define a timeout, or define retry/backoff behavior of
  their own; the error normalizer normalizes whatever error a caller's own
  network call produces, but the network call itself, and any
  offline/connectivity handling around it, is outside these seven pieces
  (fact, not a gap — a thrown error is reported via normalization, not
  lost, just with no time bound or automatic retry defined at this layer).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| id, title, spec, values (parameters to building a form) | identifier string, title string, a field specification, a map of field values | none — required | Caller-supplied identity, title, field layout, and initial values for the built detail/state. |
| blockedReason (parameter to building a form) | optional string | absent | Propagated verbatim onto the built form state; not exercised further by any of these seven given pieces. |
| Markdown-editing injection point | an injectable markdown-editing collaborator | a plain-text implementation | Confined to a single execution context; read (never written) when constructing the built form's hosting view; the hosting app overwrites it once at launch with the real markdown module. |
| fallback (parameter to formatting a date for display) | string | `"—"` | Caller-suppliable placeholder text shown when the given ISO string is missing or fails to parse. |
| isolation (parameter to the closure-taking error normalizer) | an execution-context reference | the caller's own execution context | Not a value a caller ordinarily passes explicitly; documented here because it determines the execution context the body closure runs under — see Platform Notes. |

## Deep Linking

Not applicable: none of the seven given pieces define a URL scheme, route,
or app-level navigation destination. Building a form or notice detail
builds an in-memory descriptor consumed by a separate navigation state
machine (documented in the related HTDV Engine recipe), not a
deep-linkable URL.

## Localization

None of the seven given pieces route a string through a localization table
or resource key; every user-facing string below is a hardcoded English
literal:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Not available in this version` | The shared "not available" message constant, the message every "not available" notice pane shows. |
| (none — literal, no key) | `Use lowercase letters, numbers and hyphens.` | The shared slug pattern's message, shown when a typed slug fails validation. |
| (none — literal, no key) | `Invalid JSON: ` | Prefix the JSON-parsing operation puts on the validation error it throws for malformed JSON, followed by the decoder's own description. |
| (none — literal, no key) | `—` | The display-formatting operation's default fallback value, shown for a missing or unparseable date unless the caller supplies its own. |

## Accessibility Options

Not applicable: none of the seven given pieces present any UI of their own,
so none responds to a reduced-motion, increased-contrast, or
color-differentiation setting; any such handling belongs to the
presentation layer (the form-hosting view) that renders the values these
pieces build.

## Feature Flags

Not applicable: none of the seven given pieces read a feature-flag or an
on/off settings key. Every behavior described above is unconditional given
its inputs, with no flag gating any of it.

## Analytics

Not applicable: none of the seven given pieces contain an analytics or
event-tracking call.

## Privacy

- **Data collected**: These pieces handle whatever the caller passes
  through the form-builder's values/specification (arbitrary form field
  values), the date helper's date strings, and the JSON value type's
  arbitrary JSON payloads; none of the seven given pieces itself classifies
  any of this content as sensitive — sensitivity depends entirely on what a
  specific feature stores in it.
- **Storage**: None of the seven given pieces persist anything to disk, a
  database, or a settings store; every value exists only in memory for the
  duration of the call that produced it.
- **Transmission**: None of the seven given pieces performs a network
  call. The closure-taking error normalizer wraps whatever error a
  caller's own network call produces, but that network call and any data
  it transmits are outside these seven pieces.
- **Retention**: Not applicable at this layer — nothing here defines a
  client-side expiry or cache; retention is a caller/server concern outside
  these seven pieces.

## Logging

Not applicable: none of the seven given pieces make a logging call (no
log-framework import, no logger instance, no console-print call appears in
any of them). A failure surfaces only as a returned or thrown normalized
error, as described under Behavioral Requirements and Edge Cases.

## Platform Notes

- **SwiftUI**: The date, error-normalization, blank-string, JSON-value,
  rail-path, and slug pieces need no change — none depends on AppKit/UIKit.
  Only the form/notice factory's form-hosting-view construction is
  AppKit/UIKit-specific; a SwiftUI host would replace it with a SwiftUI
  view driven by the same form state (per the related HTDV Engine recipe's
  SwiftUI note), keeping the notice factory's one-field-spec logic
  unchanged.
- **Compose**: Model the JSON document value type as a Kotlin `sealed
  class` with the same seven cases and a hand-written `equals`/`hashCode`
  implementing the same integral-number cross-equality this file's own
  comment explains (Kotlin data-class equality would otherwise compare
  sealed subclasses first, the same bug this source works around). Model
  the date helper with `kotlinx-datetime`'s `Instant` and a fixed-format
  ISO string builder for the wire-formatting operation. Reimplement the
  slug-projection operation as the same lowercase-and-collapse character
  scan, and the error normalizer as a function normalizing any `Throwable`
  into a sealed error type.
- **React/Web**: Model the JSON document value type as a TypeScript
  `JsonValue` union with a hand-written `deepEqual` that treats an integral
  `number` as equal to the same-valued `number` it decodes back as
  (JavaScript has only one numeric type, so the integer/number split this
  source encodes may not need reproducing — note the platform difference
  rather than force it). Use `Date.prototype.toISOString()` in place of the
  wire-formatting operation and `Intl.DateTimeFormat` in place of the
  human-readable formatter. Reimplement the slug-projection operation and
  pattern as the same character scan and regular expression, and the error
  normalizer as a function normalizing any thrown value into a tagged
  error union.
- **AppKit / UIKit**: This is the source platform.
  `packages/apple/AgenticToolkit/Hub/Features/Support/HubDates.swift`,
  `HubError+Wrap.swift`, `HubText.swift`, `JSONValue.swift`,
  `RailPath.swift`, and `Slug.swift` import only `Foundation` (plus
  `AgenticToolkitHTDV` for the date helper's/rail-path's HTDV types) and
  hold no AppKit/UIKit import of their own; only `FormDetails.swift` reaches
  into a platform-specific view controller, and it does so through
  `FormViewController`, which exists in both an AppKit variant
  (`packages/apple/AgenticToolkit/HTDV/Views/macOS/FormViewController.swift`)
  and a UIKit variant
  (`packages/apple/AgenticToolkit/HTDV/Views/iOS/FormViewController+UIKit.swift`) —
  the other six files are shared unchanged between macOS and iOS. The
  closure-taking form of `HubError.wrap` (`HubError.wrap(isolation:_:)`)
  declares its `isolation` parameter as `isolated (any Actor)? =
  #isolation`, so a caller's `body` closure runs under the caller's own
  actor isolation — main actor, a specific actor, or nonisolated — instead
  of being forced `nonisolated`, per the source's own comment that this
  lets a `@MainActor` caller "capture `self`" and still compile under Swift
  6 strict concurrency "without hoisting reads out or wrapping writes in
  `MainActor.run`." This is a compile-time-only guarantee — no runtime
  assertion is possible for it — which is why `SupportTests.swift` carries
  three test methods that exist solely to fail to build if this isolation
  parameter regresses, and why the corresponding Conformance Test Vector
  was removed from the normative table above rather than translated into a
  neutral input/expected pair.
- **WinUI 3**: Model the JSON document value type as a C# type with the
  same seven-case shape and an `IEquatable<JSONValue>` implementation giving
  the same `int`/`double` cross-equality, serialized with
  `System.Text.Json`. Model the date helper with `DateTimeOffset` and the
  fixed format string `"yyyy-MM-dd'T'HH:mm:ss.fff'Z'"` for the equivalent
  of the wire-formatting operation, parsing with `DateTimeOffset.TryParse`
  under `DateTimeStyles.RoundtripKind` in place of the fractional/whole
  two-step parse. Reimplement the slug pattern with
  `System.Text.RegularExpressions.Regex`, and model the error normalizer as
  a static method that normalizes any `Exception` into a domain-error-
  derived exception type, with the closure overload taking a
  `Func<Task<T>>` in place of the caller-isolation-preserving Swift
  overload (WinUI 3 has no actor-isolation analog to preserve).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Support/` |

## Design Decisions

**Decision**: The JSON document value type implements equality and hashing
by hand instead of relying on compiler-synthesized, case-first conformance,
treating an integer case and a number case as equal (and equally hashing)
when the number represents that same integer exactly.
**Rationale**: A JSON decoder always decodes a JSON integer literal as the
integer case and a value written with a decimal point as the number case;
a synthesized, case-first equality would treat a re-decoded number
differently from an original integer baseline. The source's own comment
states this previously misfired a form's dirty-state baseline comparison,
leaving Save enabled on an untouched form and producing spurious discard
prompts.
**Approved**: pending

**Decision**: The date helper builds its four ISO-8601 formatters as
constants instead of constructing one per call.
**Platform**: Swift/Apple platforms — `private static let` values
(`Date.ISO8601FormatStyle`/`DateFormatter`); any port should use the
equivalent shared-immutable-instance idiom for its own platform's date
formatter type.
**Rationale**: The source's own comment states construction is expensive
enough to show up when a rail formats a few hundred rows; both formatter
types are safe to share as immutable singletons once built and never
mutated afterward.
**Approved**: pending

**Decision**: The closure-taking error normalizer declares an isolation
parameter (`isolated (any Actor)? = #isolation`) rather than leaving the
closure's isolation to the language's default inference.
**Platform**: Swift/Apple platforms — actor isolation is a Swift
concurrency concept with no direct analog on this recipe's other platforms
(see the WinUI 3 Platform Note).
**Rationale**: Without this parameter, Swift 6 strict concurrency would
force the closure `nonisolated`, breaking a `@MainActor` caller whose
closure reads and writes main-actor state without an explicit
`MainActor.run` hop. The source's own doc comment states this specific
compile-time regression is what the parameter guards against, and three of
`SupportTests.swift`'s test methods exist solely to fail to build if it
regresses.
**Approved**: pending

**Decision**: The slug-projection operation tracks a pending-hyphen flag
and only flushes it (appending one `"-"`) immediately before the next
allowed character, and only when the output built so far is non-empty —
rather than converting every disallowed character to a hyphen in place.
**Rationale**: This guarantees the slug-projection operation's non-empty
output already satisfies the slug pattern (which forbids a leading or
trailing hyphen and any run of two or more hyphens) without a second
validation pass. The ordering this depends on — never flush while the
output is empty, never flush a still-pending hyphen at end of input — is
not obvious from a single call site, which is why it is called out here
rather than left implicit.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
