---
id: 2e71f72e-88d7-417e-9969-a414e1ab1a10
title: JSONC Preprocessor
domain: agentictoolkit://cookbook/foundation/formats/jsonc-preprocessor
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Reads JSONC (comments, trailing commas, six candidate encodings) into strict
  JSON an ordinary decoder accepts.
platforms:
- swift
- macos
tags:
- jsonc
- json
- text-processing
- encoding-detection
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest-localization
- agentictoolkit://cookbook/workspace/extensions/registry/extension-registry
- agentictoolkit://cookbook/workspace/extensions/registry/vsix-installer
references: []
approved-by: ''
approved-date: ''
---

# JSONC Preprocessor

## Overview

The JSONC preprocessor turns JSONC — JSON with `//` and `/* … */` comments
and trailing commas, the dialect VS Code writes its own configuration files
in — into strict JSON that an ordinary JSON decoder accepts. It holds no
state and performs no I/O of its own: every call receives its input as a
parameter (text, or raw bytes in an unknown encoding) and returns a value or
throws. It was extracted from a color-theme importer's own private copy of
this logic once a second caller — a language-snippet file reader — needed
the same JSONC-reading behavior, because two readers of the same dialect
must not drift apart. In this repository it is also used by an
extension-manifest localization component, an extension registry, and an
extension-package installer to read extension manifests, their
localization tables, and VS Code color themes and snippet files — all files
a third party (an extension or theme author, or an editor on another
platform) authored and saved in whatever encoding and comment style VS Code
itself tolerates.

## Behavioral Requirements

- **namespace-shape**: The JSONC preprocessor MUST hold no instance state
  and no shared mutable state, and MUST expose its behavior only through
  operations callable without constructing or holding an instance of it.
- **no-side-effects**: None of the strip operation, the parse-to-object
  operation, or the normalize-to-strict-JSON operation MUST perform file,
  network, process, or notification I/O — each operates only on its
  parameter and returns a value or throws.
- **stateless-concurrency-safety**: The JSONC preprocessor MUST be safe to
  call concurrently from any thread with no synchronization required by the
  caller, because it holds nothing that one call could observe or mutate
  while another call is in progress.
- **strip-comment-removal**: The strip operation MUST remove every `//`
  line comment and every `/* … */` block comment from the input text before
  returning.
- **strip-trailing-comma-removal**: The strip operation MUST blank —
  overwrite with a single space, not delete — any comma that has only
  whitespace between it and the next `}` or `]`, and MUST run this pass
  only after comment removal, so a comma exposed by removing a comment is
  also caught.
- **strip-string-awareness**: Both the comment scanner and the
  trailing-comma scanner MUST track whether the current position is inside
  a double-quoted string, honoring a backslash escape immediately before a
  quote or another backslash, and MUST NOT treat `//`, `/*`, or `,` as
  syntactically significant while inside a string.
- **line-comment-stops-at-newline**: A `//` line comment MUST consume
  characters up to, but not including, the next newline character, so the
  newline itself MUST still appear in the output.
- **block-comment-unterminated-consumes-rest**: An unterminated `/* … */`
  block comment MUST consume every remaining character in the document,
  with no closing-delimiter recovery attempted.
- **jsonobject-tries-encodings-in-order**: The parse-to-object operation
  MUST attempt to decode the input bytes as text using, in this exact
  order, six candidate encodings — UTF-8, UTF-16, UTF-16 big-endian, UTF-16
  little-endian, UTF-32 big-endian, UTF-32 little-endian — skipping to the
  next candidate whenever decoding that candidate fails.
- **jsonobject-bom-stripped**: For each candidate encoding that decodes
  successfully, the parse-to-object operation MUST remove a leading U+FEFF
  byte-order-mark character from the decoded text before stripping
  comments and commas.
- **jsonobject-first-parseable-candidate-wins**: The parse-to-object
  operation MUST return the object graph produced by the first candidate
  encoding whose byte-order-mark-stripped, comment/comma-stripped text
  successfully parses as JSON, and MUST NOT attempt any further candidate
  once one has succeeded.
- **jsonobject-rejects-top-level-fragments**: The parse-to-object operation
  MUST reject a document whose root value is not a JSON object or array; a
  top-level scalar value is never accepted from any candidate, nor from the
  final fallback attempt.
- **jsonobject-fallback-on-raw-bytes**: When no candidate encoding yields
  text that both decodes and parses, the parse-to-object operation MUST
  attempt to parse the original, untransformed bytes directly as JSON, and
  MUST propagate whatever error that attempt throws to the caller
  unchanged.
- **jsondata-passthrough-when-already-strict**: The normalize-to-strict-JSON
  operation MUST return the input bytes unchanged, performing no
  transformation and no re-serialization, whenever those bytes already
  parse directly as JSON — including when the root value is a top-level
  scalar.
- **jsondata-reencodes-when-not-strict**: When that direct parse fails, the
  normalize-to-strict-JSON operation MUST run the parse-to-object operation
  on the input bytes and MUST re-serialize the resulting object graph as
  JSON, returning that re-serialized result.
- **jsondata-propagates-jsonobject-errors**: The normalize-to-strict-JSON
  operation MUST propagate, unmodified, whatever error the parse-to-object
  operation throws when the re-encode path is taken.
- **candidate-list-is-fixed**: The six-encoding list MUST be fixed and MUST
  NOT be configurable by a caller — neither the parse-to-object operation
  nor the normalize-to-strict-JSON operation accepts an encoding-list
  parameter.

## Appearance

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a
visual component.

## States

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a
visual component. It holds no runtime state of its own to place in a
visual-state table; each call is a single, complete, stateless
transformation, covered above under Behavioral Requirements.

## Accessibility

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-json-001 | strip-comment-removal, strip-string-awareness | `{ // the answer\n "a": 1 }` | Parses to `{"a": 1}` — the `//` comment is removed, the value survives. |
| foundation-json-002 | strip-comment-removal | A multi-line `/* … */` block comment plus an inline `/* and inline */` between two keys. | Parses to `{"a": 1, "b": 2}`. |
| foundation-json-003 | block-comment-unterminated-consumes-rest | `{"a": 1 /* oops }` | Throws — the open block comment swallows the rest of the document, leaving nothing left to parse. |
| foundation-json-004 | strip-string-awareness | `{"$schema": "https://example.com/schema.json"}` | Parses to `{"$schema": "https://example.com/schema.json"}` — the `//` inside the URL is not treated as a comment. |
| foundation-json-005 | strip-string-awareness | `{"a": "say \"hi\" // not a comment"}` | Parses to `{"a": "say \"hi\" // not a comment"}` — the escaped quotes keep the string open past them, and the `//` inside it is left alone. |
| foundation-json-006 | strip-string-awareness, strip-trailing-comma-removal | `{"a": "one, two", "b": 2}` | Parses to `{"a": "one, two", "b": 2}` — the comma inside the string value is not blanked. |
| foundation-json-007 | strip-string-awareness | `{"a": "back\\", "b": 2}` | Parses to `{"a": "back\\", "b": 2}` — the escaped backslash does not itself escape the closing quote. |
| foundation-json-008 | strip-trailing-comma-removal | `{ "a": 1, }` | Parses to `{"a": 1}`. |
| foundation-json-009 | strip-trailing-comma-removal | `{ "a": [1, 2, ] }` | Parses to `{"a": [1, 2]}`. |
| foundation-json-010 | strip-trailing-comma-removal, strip-comment-removal | `{ "a": [1, /* stale */] }` | Parses to `{"a": [1]}` — the comma is only trailing once the comment between it and `]` is gone, confirming comments are stripped before commas. |
| foundation-json-011 | line-comment-stops-at-newline | Perform the strip operation on `"// a\nb"`. | Returns `"\nb"` — the comment's own newline is preserved rather than consumed. |
| foundation-json-012 | jsonobject-tries-encodings-in-order, jsonobject-first-parseable-candidate-wins | A JSONC document with a `//` comment, encoded with UTF-16. | Parses to `{"a": 1}` — the UTF-8 candidate fails to decode or parse, and the UTF-16 candidate succeeds. |
| foundation-json-013 | jsonobject-bom-stripped | The three UTF-8 byte-order-mark bytes followed by `{"a": 1}`. | Parses to `{"a": 1}` — the byte-order mark is skipped rather than causing the document to be rejected. |
| foundation-json-014 | jsonobject-fallback-on-raw-bytes | `{"a": 1` (unterminated object). | Throws — nothing is repaired or invented; the caller learns the document is broken. |
| foundation-json-015 | jsonobject-fallback-on-raw-bytes, strip-comment-removal | `// nothing here\n` | Throws — every candidate encoding strips to an empty or comment-only document with nothing left to parse. |
| foundation-json-016 | jsonobject-rejects-top-level-fragments | Perform the parse-to-object operation on the bytes for `42` — a bare top-level number, already strict JSON. | Throws — a document whose root is a scalar is rejected even though the bytes are otherwise valid JSON. |
| foundation-json-017 | jsondata-passthrough-when-already-strict | Perform the normalize-to-strict-JSON operation on the bytes for `42`. | Returns those same bytes unchanged — the top-level scalar is accepted directly and the re-encode path never runs. |
| foundation-json-018 | jsondata-passthrough-when-already-strict | Perform the normalize-to-strict-JSON operation on the bytes for `{"a":1e3}`. | Returns the exact original bytes, byte-for-byte, including `1e3` — not a re-serialized `{"a":1000}` — because the passthrough check succeeds and no re-encode ever runs. |
| foundation-json-019 | jsondata-reencodes-when-not-strict | Perform the normalize-to-strict-JSON operation on the bytes for `{"a": 1, }` (a trailing comma, so not strict JSON). | Returns re-serialized bytes that parse to `{"a": 1}` — the bytes differ from the input because the trailing comma forced the parse-and-re-serialize path. |
| foundation-json-020 | jsondata-propagates-jsonobject-errors | Perform the normalize-to-strict-JSON operation on the bytes for `{"a": 1` (unterminated, and not strict). | Throws — the failure originates in the parse-to-object operation's fallback attempt and passes through unmodified. |
| foundation-json-021 | stateless-concurrency-safety | Issue fifty concurrent calls to the strip operation and the parse-to-object operation, each with a distinct input, from many threads at once. | Every call returns the result matching its own input, with no cross-talk between calls — there is no shared state for two calls to interleave through. |
| foundation-json-022 | no-side-effects | Call the parse-to-object and normalize-to-strict-JSON operations with valid JSONC bytes in a test with no filesystem, network, or notification observers configured. | The call succeeds or throws based only on the bytes given it; no file is created, no request is issued, no notification is posted. |
| foundation-json-023 | candidate-list-is-fixed | Attempt to write a call site passing an encoding list or a custom encoding to either operation. | Rejected before it can run — neither operation accepts such a parameter. |

## Edge Cases

- **Null / empty input**: The strip operation on empty input MUST return
  empty output — there is nothing for either scanner to act on. The
  parse-to-object operation on empty bytes MUST throw: the first candidate
  encoding decodes the empty bytes to empty text, which strips to empty
  text and fails to parse as JSON; every other candidate encoding either
  fails to decode zero bytes or produces the same empty, unparseable text,
  so every candidate is exhausted and the final fallback attempt on the
  empty bytes also throws, propagating to the caller — this is a MUST,
  since nothing in the design special-cases an empty payload.
- **Boundary values**: The scanners impose no maximum input length; the
  comment scanner and the trailing-comma scanner MUST each make one linear
  pass over every character of the input regardless of size, with no early
  exit and no configurable ceiling — a caller passing an arbitrarily large
  input MUST have every character considered by both scanners. A document
  consisting of a single unmatched `"` (an opened-but-never-closed string)
  MUST leave both scanners inside a string for the remainder of the text,
  meaning any `//`, `/*`, or trailing comma after that point MUST be
  preserved rather than treated as syntax, and the resulting document MUST
  then fail to parse (the mechanism is
  **block-comment-unterminated-consumes-rest**'s sibling case, not a
  separate one — an unterminated string and an unterminated comment both
  simply run to the end of the text).
- **Concurrent access**: Per **stateless-concurrency-safety**, the JSONC
  preprocessor MUST behave identically under any number of concurrent
  calls, since it holds no state of any kind — this is not a caveat but
  the direct consequence of exposing behavior with no shared state at all.
- **Error states**: A document that fails to decode under every candidate
  encoding, or that decodes but fails to parse under every candidate after
  stripping, MUST cause the parse-to-object operation to throw the same
  error the underlying JSON parser raises for the caller's original,
  unmodified bytes (**jsonobject-fallback-on-raw-bytes**) — nothing wraps,
  annotates, or replaces that error, and no partial or best-effort result
  is ever returned. The normalize-to-strict-JSON operation MUST propagate
  that same error unchanged when its re-encode path is taken
  (**jsondata-propagates-jsonobject-errors**).
- **Offline / disconnected state**: Not applicable — the JSONC preprocessor
  performs no network I/O of any kind (**no-side-effects**); it operates
  only on the text or bytes a caller already holds in memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| text (parameter to the strip operation) | string | none — required | The JSONC text to normalize into strict JSON text. |
| data (parameter to the parse-to-object and normalize-to-strict-JSON operations) | bytes | none — required | The raw bytes of a JSONC or strict-JSON document, in any of the six candidate encodings. |

Neither operation reads an environment variable or a settings key, and
neither accepts an injected dependency; every value the component operates
on arrives as a call parameter, and the six-item candidate-encoding list is
a fixed, non-configurable constant (**candidate-list-is-fixed**).

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination — it transforms text and bytes, it does not navigate anywhere.

## Localization

Not applicable: this component contains no user-facing string literal of
its own — it never constructs an error message or display string; every
error it surfaces is rethrown verbatim from the underlying JSON parser,
unannotated.

## Accessibility Options

Not applicable: this component presents no UI, so it responds to none of
reduced-motion, increased-contrast, or color-differentiation accessibility
settings.

## Feature Flags

Not applicable: this component contains no feature-flag or settings-key
reference of its own.

## Analytics

Not applicable: this component contains no analytics or event-tracking
call.

## Privacy

- **Data handled**: The JSONC preprocessor defines no data field of its
  own — every byte and character it touches is the caller's input, held
  only for the duration of one call. In this repository that data is a VS
  Code style configuration file: a color theme, a language snippet file, or
  an extension's manifest and localization tables — content an extension or
  theme author wrote, not a credential or access token.
- **Storage**: None — the component performs no read or write of its own;
  it returns a transformed value in memory and retains nothing once the
  call returns.
- **Transmission**: None — the component performs no network I/O of its
  own (**no-side-effects**).
- **Retention**: None — no state survives past the return of the call that
  produced it; there is no instance to hold anything between calls.

## Logging

Not applicable: this component calls no logging or diagnostic API of any
kind.

## Platform Notes

- **SwiftUI**: Source: `packages/apple/AgenticToolkit/Core/JSON/
  JSONCPreprocessor.swift`, part of the `AgenticToolkitCore` framework
  target, which `project.yml` declares `platform: macOS` only (no iOS
  target exists for it today). The file imports only `Foundation`; nothing
  in it is SwiftUI- or AppKit-specific, so a macOS or iOS host consumes it
  identically wherever it is built.
- **Compose**: There is no JSONC-aware parser in the Kotlin standard
  library or `kotlinx.serialization`. Port the comment- and
  trailing-comma-removal passes as hand-written scanner functions over a
  `CharSequence`, preserving the same in-string/escape tracking, then
  decode the result with `kotlinx.serialization.json.Json`. Port the
  six-candidate encoding loop with `Charsets.UTF_8`, `Charsets.UTF_16BE`,
  `Charsets.UTF_16LE`, and the UTF-32 equivalents obtained via
  `Charset.forName`, decoding with a `CharsetDecoder` configured
  `onMalformedInput(CodingErrorAction.REPORT)` so a bad candidate throws
  rather than silently substituting replacement characters — the behavior
  Swift's `String(data:encoding:)` gives for free by returning `nil`.
- **React/Web**: `jsonc-parser` — the library VS Code's own extension host
  uses — already implements this exact dialect; port by depending on its
  `parse`/`parseTree` functions rather than hand-rolling the scanner. There
  is no six-encoding ambiguity to resolve in a browser or Node environment:
  a `File`/`Blob`/`Buffer` decodes via an explicit or sniffed `TextDecoder`
  encoding, not tried six ways in sequence. The
  **jsonobject-rejects-top-level-fragments** /
  **jsondata-passthrough-when-already-strict** asymmetry has no natural
  analogue, since `JSON.parse` always accepts a top-level scalar; a port
  that wants to preserve the asymmetry must gate its two entry points
  deliberately rather than getting it from the underlying parser.
- **AppKit / UIKit**: This recipe is `JSONCPreprocessor`
  (`JSONCPreprocessor.swift`), declared as a caseless `enum` — a
  Foundation-only namespace holding no instance and no mutable state, with
  its only stored property (`candidateEncodings`) an immutable `static
  let`, and no actor isolation of any kind, which together give it
  **stateless-concurrency-safety** for free. Its three functions are
  `strip(_:)`, `jsonObject(from:)`, and `jsonData(from:)`; the comment and
  trailing-comma scanners (`removingComments`, `removingTrailingCommas`)
  operate on Swift `Character` (extended grapheme cluster) values, not raw
  code units, which is what keeps multi-byte and combined Unicode
  characters inside string literals from being misread as ASCII
  punctuation. `no-side-effects` holds because the source imports only
  `Foundation` and contains no `FileManager`, `URLSession`, `Process`, or
  `NotificationCenter` reference. `jsonObject(from:)` decodes candidates via
  `String(data:encoding:)` against `.utf8`, `.utf16`, `.utf16BigEndian`,
  `.utf16LittleEndian`, `.utf32BigEndian`, `.utf32LittleEndian` in that
  order, and both it and `jsonData(from:)`'s re-encode path call
  `JSONSerialization.jsonObject(with:)` — never passing `.fragmentsAllowed`
  — which is what makes **jsonobject-rejects-top-level-fragments** true;
  `jsonData(from:)`'s own initial strict-JSON check calls
  `JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])`
  directly against the original bytes, and its re-encode path serializes
  via `JSONSerialization.data(withJSONObject:options: [.fragmentsAllowed])`.
  Per its own doc comment, this type was lifted out of `VSCodeThemeImporter`
  's private copy when a second caller, `SnippetFile` in the
  `AgenticToolkitLanguage` framework target, needed the same JSONC-reading
  behavior; `ExtensionManifestLocalization`, `ExtensionRegistry`, and
  `VSIXInstaller` are its other callers in this repository, reading
  extension `package.json` manifests, `package.nls*.json` localization
  tables, and VS Code color themes and snippet files.
- **WinUI 3**: `System.Text.Json`'s `JsonDocumentOptions`/
  `JsonSerializerOptions` already expose `CommentHandling =
  JsonCommentHandling.Skip` and `AllowTrailingCommas = true` — a WinUI 3
  port SHOULD set those options on `JsonDocument.Parse`/
  `JsonSerializer.Deserialize` instead of reimplementing the comment and
  trailing-comma scanners by hand, since the built-in options already
  provide the same string-aware comment and trailing-comma tolerance. Only
  the six-candidate encoding fallback needs its own port: try
  `Encoding.UTF8`, `Encoding.Unicode` (UTF-16LE), `Encoding.BigEndianUnicode`
  (UTF-16BE), and `Encoding.UTF32` plus its big-endian counterpart via
  `Encoding.GetEncoding(...)`, decoding with `Encoding.GetString` configured
  with a `DecoderExceptionFallback` (so a candidate that cannot decode
  throws a `DecoderFallbackException` instead of silently substituting
  replacement characters) to reproduce Swift's nil-on-failure decode
  signal. `Windows.Storage`/`StorageFile` never enters this component at
  all — the byte source stays the caller's concern.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/JSON/JSONCPreprocessor.swift` |

## Design Decisions

**Decision**: The parse-to-object operation never accepts a top-level
scalar fragment from any of its parse attempts, but the
normalize-to-strict-JSON operation's own initial strict-JSON check does
accept one.
**Rationale** (Swift/Foundation implementation): This creates an asymmetry
a reader would not expect from the two operations' names alone: normalizing
the bytes for `42` returns those bytes unchanged (the initial check accepts
a bare top-level number), but parsing the bytes for `42` to an object throws,
and a JSONC document whose root is a scalar (e.g. `42 // comment`) fails
through the normalize operation too, because its fallback is the
parse-to-object operation, which never accepts a fragment. Nothing in the
source comments this choice; it follows mechanically from the normalize
operation's passthrough check being written to allow fragments and every
other call site omitting that option.
**Approved**: pending

**Decision**: Candidate encodings are tried strictly in a fixed order —
UTF-8, UTF-16, UTF-16 big-endian, UTF-16 little-endian, UTF-32 big-endian,
UTF-32 little-endian — and the winner is the first candidate whose decoded
text also *parses*, not merely decodes.
**Rationale**: Per the source's own comment, UTF-16 bytes for ASCII text
also decode as UTF-8 (the interleaved NULs are valid UTF-8), and UTF-16
accepts any even-length payload as big-endian, so a "first that decodes"
rule would let an earlier candidate silently swallow a later one's file and
turn a good document into a syntax error. Requiring a successful *parse*,
not just a successful *decode*, is what makes the fixed try-order safe.
**Approved**: pending

**Decision**: The normalize-to-strict-JSON operation returns bytes that are
already strict JSON completely unchanged, rather than always round-tripping
through the parse-to-object operation and re-serializing.
**Rationale**: Per the source's own comment, a re-serialized document is
not byte-identical to the one that came in — `1e3` comes back as `1000`,
and key order can change — so a decoder that never sees the rewritten form
cannot be surprised by it. Only a file the strict parser actually refuses
pays the transform cost.
**Approved**: pending

**Decision**: The trailing-comma scanner blanks a disqualified comma by
overwriting it with a space character rather than removing it from the
text.
**Rationale** (Swift/Foundation implementation): Per the source's own
comment, overwriting keeps every remaining character offset valid while the
single forward scan is still running; deleting the character would shift
every subsequent index and require either a second pass or index-adjustment
bookkeeping the current single-pass algorithm does not do.
**Approved**: pending

**Decision**: An unterminated `/* … */` block comment consumes the rest of
the document with no recovery attempt, producing a downstream parse failure
rather than a repaired document.
**Rationale**: The design makes no attempt to detect or recover from this
case; the test covering it states the intent directly: this is the honest
outcome for a file whose author left a comment open, not a defect to be
patched around.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |

Notes: `separation-of-concerns` passes because the JSONC preprocessor
addresses exactly one concern — turning JSONC bytes/text into strict JSON —
with no theme, snippet, extension-manifest, or presentation logic of its
own; it was extracted from a color-theme importer specifically to keep that
concern from being duplicated across readers. `unit-test-coverage` is
partial: the strip operation and the parse-to-object operation are
exercised directly and thoroughly (comments, string-awareness, trailing
commas, all encoding paths, byte-order-mark handling, pass-through, and
both failure cases), but the normalize-to-strict-JSON operation has no
dedicated test anywhere in the repository, even though production code
calls it. `explicit-error-handling` passes because every failure path
rethrows the underlying JSON-parsing error unchanged, with no
swallow-and-continue anywhere the final result is concerned — internal
attempts exist only to test a candidate before committing to it, and each
is followed by a final attempt that lets any real error surface.
`fault-tolerance` passes because the parse-to-object and
normalize-to-strict-JSON operations accept arbitrary caller-supplied
bytes — malformed JSON, a document that is only a comment, an unrecognized
encoding — and always resolve to either a valid result or a well-defined
thrown error, never a crash. `unicode-support` passes because the component
explicitly transcodes across six Unicode-capable encodings (UTF-8 and four
UTF-16/UTF-32 byte-order variants) before falling back to the caller's raw
bytes, and its character-level scanners operate on extended grapheme
cluster values, not raw code units, so multi-byte and combined Unicode
characters inside string literals are never misinterpreted as ASCII
punctuation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/formats/. |
