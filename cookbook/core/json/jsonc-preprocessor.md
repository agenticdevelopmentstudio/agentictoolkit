---
id: 2e71f72e-88d7-417e-9969-a414e1ab1a10
title: JSONCPreprocessor
domain: agentictoolkit://cookbook/core/json/jsonc-preprocessor
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- foundation
- text-processing
- encoding-detection
depends-on: []
related:
- agentictoolkit://cookbook/core/extensions/extension-manifest-localization
- agentictoolkit://cookbook/core/extensions/extension-registry
- agentictoolkit://cookbook/core/extensions/vsix-installer
references: []
approved-by: ''
approved-date: ''
---

# JSONCPreprocessor

## Overview

`JSONCPreprocessor` is a caseless `enum` namespace in `packages/apple/AgenticToolkit/Core/JSON/JSONCPreprocessor.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares `platform: macOS` only. It reads JSONC — JSON with `//` and `/* … */` comments and trailing commas, the dialect VS Code writes its own configuration files in — and turns it into strict JSON that `JSONSerialization`/`JSONDecoder` accept. It holds no state and performs no I/O of its own: every call receives its input as a parameter (`text: String` or `data: Data`) and returns a value or throws. Per its own doc comment, it was lifted out of `VSCodeThemeImporter`'s private copy when a second caller (`SnippetFile`, in the `AgenticToolkitLanguage` framework target) needed the same JSONC-reading behavior, because "two readers of the same dialect must not drift apart." In this repository it is also used by `ExtensionManifestLocalization`, `ExtensionRegistry`, and `VSIXInstaller` to read extension `package.json` manifests, their `package.nls*.json` localization tables, and VS Code color themes and snippet files — all files a third party (an extension or theme author, or a Windows-based editor) authored and saved in whatever encoding and comment style VS Code itself tolerates.

## Behavioral Requirements

- **namespace-shape**: `JSONCPreprocessor` MUST be declared as a caseless `enum` holding no instance or static mutable state, exposing its behavior only through functions callable without creating an instance.
- **no-side-effects**: None of `strip(_:)`, `jsonObject(from:)`, or `jsonData(from:)` MUST perform file, network, process, or notification I/O — the source imports only `Foundation` and contains no `FileManager`, `URLSession`, `Process`, or `NotificationCenter` reference; each function operates only on its parameter and returns a value or throws.
- **stateless-concurrency-safety**: `JSONCPreprocessor` MUST be safe to call concurrently from any thread or actor with no synchronization required by the caller — it declares no actor isolation, and its only static storage, `candidateEncodings`, is an immutable `let`, so no call can observe or mutate state shared with another call.
- **strip-comment-removal**: `strip(_:)` MUST remove every `//` line comment and every `/* … */` block comment from `text` before returning (via `removingComments`).
- **strip-trailing-comma-removal**: `strip(_:)` MUST blank — overwrite with a single space, not delete — any comma that has only whitespace between it and the next `}` or `]` (via `removingTrailingCommas`), and MUST run this pass only after comment removal, so a comma exposed by removing a comment is also caught (doc comment; test `trailingCommaAfterComment`).
- **strip-string-awareness**: Both the comment scanner and the trailing-comma scanner MUST track whether the current position is inside a double-quoted string, honoring a backslash escape immediately before a quote or another backslash, and MUST NOT treat `//`, `/*`, or `,` as syntactically significant while inside a string (1091-1104; tests `slashesInsideStringSurvive`, `escapedQuoteInsideString`, `commaInsideString`, `escapedBackslashEndsTheString`).
- **line-comment-stops-at-newline**: A `//` line comment MUST consume characters up to, but not including, the next newline character, so the newline itself MUST still appear in the output.
- **block-comment-unterminated-consumes-rest**: An unterminated `/* … */` block comment MUST consume every remaining character in the document, with no closing-delimiter recovery attempted (test `unterminatedBlockComment` confirms the resulting document then fails to parse).
- **jsonobject-tries-encodings-in-order**: `jsonObject(from:)` MUST attempt `String(data:encoding:)` against `data` using, in this exact order, `.utf8`, `.utf16`, `.utf16BigEndian`, `.utf16LittleEndian`, `.utf32BigEndian`, `.utf32LittleEndian`, skipping to the next candidate whenever decoding that candidate fails.
- **jsonobject-bom-stripped**: For each candidate encoding that decodes successfully, `jsonObject(from:)` MUST remove a leading U+FEFF byte-order-mark character from the decoded text before stripping comments and commas.
- **jsonobject-first-parseable-candidate-wins**: `jsonObject(from:)` MUST return the object graph produced by the first candidate encoding whose BOM-stripped, comment/comma-stripped text `JSONSerialization.jsonObject(with:)` successfully parses, and MUST NOT attempt any further candidate once one has succeeded.
- **jsonobject-rejects-top-level-fragments**: `jsonObject(from:)` MUST reject a document whose root value is not a JSON object or array — neither its per-candidate parse call nor its final fallback call passes `.fragmentsAllowed` to `JSONSerialization.jsonObject(with:)`.
- **jsonobject-fallback-on-raw-bytes**: When no candidate encoding yields text that both decodes and parses, `jsonObject(from:)` MUST call `JSONSerialization.jsonObject(with: data)` on the original, untransformed `data` and MUST propagate whatever error that call throws to the caller unchanged.
- **jsondata-passthrough-when-already-strict**: `jsonData(from:)` MUST return `data` unchanged, performing no transformation and no re-serialization, whenever `JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])` succeeds directly on the original bytes — including when the root value is a top-level scalar fragment.
- **jsondata-reencodes-when-not-strict**: When that direct fragments-allowed parse fails, `jsonData(from:)` MUST call `jsonObject(from: data)` and MUST re-serialize the resulting object graph via `JSONSerialization.data(withJSONObject:options: [.fragmentsAllowed])`, returning that re-serialized `Data`.
- **jsondata-propagates-jsonobject-errors**: `jsonData(from:)` MUST propagate, unmodified, whatever error `jsonObject(from: data)` throws when the re-encode path is taken.
- **candidate-list-is-fixed**: The six-encoding list MUST be fixed and MUST NOT be configurable by a caller — neither `jsonObject(from:)` nor `jsonData(from:)` accepts an encoding-list parameter.

## Appearance

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a visual component.

## States

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a visual component. It holds no runtime state of its own to place in a visual-state table; each call is a single, complete, stateless transformation, covered above under Behavioral Requirements.

## Accessibility

Not applicable — this is a JSONC-to-strict-JSON text preprocessor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-json-001 | strip-comment-removal, strip-string-awareness | `JSONCPreprocessorTests.lineComment`: `{ // the answer\n "a": 1 }`. | Parses to `["a": 1]` — the `//` comment is removed, the value survives. |
| foundation-json-002 | strip-comment-removal | `JSONCPreprocessorTests.blockComment`: a multi-line `/* … */` block comment plus an inline `/* and inline */` between two keys. | Parses to `["a": 1, "b": 2]`. |
| foundation-json-003 | block-comment-unterminated-consumes-rest | `JSONCPreprocessorTests.unterminatedBlockComment`: `{"a": 1 /* oops }`. | Throws — the open block comment swallows the rest of the document, leaving nothing left to parse. |
| foundation-json-004 | strip-string-awareness | `JSONCPreprocessorTests.slashesInsideStringSurvive`: `{"$schema": "https://example.com/schema.json"}`. | Parses to `["$schema": "https://example.com/schema.json"]` — the `//` inside the URL is not treated as a comment. |
| foundation-json-005 | strip-string-awareness | `JSONCPreprocessorTests.escapedQuoteInsideString`: `{"a": "say \"hi\" // not a comment"}`. | Parses to `["a": "say \"hi\" // not a comment"]` — the escaped quotes keep the string open past them, and the `//` inside it is left alone. |
| foundation-json-006 | strip-string-awareness, strip-trailing-comma-removal | `JSONCPreprocessorTests.commaInsideString`: `{"a": "one, two", "b": 2}`. | Parses to `["a": "one, two", "b": 2]` — the comma inside the string value is not blanked. |
| foundation-json-007 | strip-string-awareness | `JSONCPreprocessorTests.escapedBackslashEndsTheString`: `{"a": "back\\", "b": 2}`. | Parses to `["a": "back\\", "b": 2]` — the escaped backslash does not itself escape the closing quote. |
| foundation-json-008 | strip-trailing-comma-removal | `JSONCPreprocessorTests.trailingCommaBeforeBrace`: `{ "a": 1, }`. | Parses to `["a": 1]`. |
| foundation-json-009 | strip-trailing-comma-removal | `JSONCPreprocessorTests.trailingCommaBeforeBracket`: `{ "a": [1, 2, ] }`. | Parses to `["a": [1, 2]]`. |
| foundation-json-010 | strip-trailing-comma-removal, strip-comment-removal | `JSONCPreprocessorTests.trailingCommaAfterComment`: `{ "a": [1, /* stale */] }`. | Parses to `["a": [1]]` — the comma is only trailing once the comment between it and `]` is gone, confirming comments are stripped before commas. |
| foundation-json-011 | line-comment-stops-at-newline | `JSONCPreprocessor.strip("// a\nb")`. | Returns `"\nb"` — the comment's own newline is preserved rather than consumed. |
| foundation-json-012 | jsonobject-tries-encodings-in-order, jsonobject-first-parseable-candidate-wins | `JSONCPreprocessorTests.utf16Payload`: a JSONC document with a `//` comment, encoded with `.utf16`. | Parses to `["a": 1]` — the UTF-8 candidate fails to decode or parse, and the `.utf16` candidate succeeds. |
| foundation-json-013 | jsonobject-bom-stripped | `JSONCPreprocessorTests.utf8BOM`: the three UTF-8 BOM bytes (`0xEF 0xBB 0xBF`) followed by `{"a": 1}`. | Parses to `["a": 1]` — the BOM is skipped rather than causing `JSONSerialization` to reject the document. |
| foundation-json-014 | jsonobject-fallback-on-raw-bytes | `JSONCPreprocessorTests.malformedThrows`: `{"a": 1` (unterminated object). | Throws — nothing is repaired or invented; the caller learns the document is broken. |
| foundation-json-015 | jsonobject-fallback-on-raw-bytes, strip-comment-removal | `JSONCPreprocessorTests.commentOnlyThrows`: `// nothing here\n`. | Throws — every candidate encoding strips to an empty or comment-only document with nothing left to parse. |
| foundation-json-016 | jsonobject-rejects-top-level-fragments | `try JSONCPreprocessor.jsonObject(from: Data("42".utf8))` — a bare top-level number, already strict JSON. | Throws — no call inside `jsonObject(from:)` passes `.fragmentsAllowed`, so a document whose root is a scalar is rejected even though the bytes are valid JSON by `JSON.parse`-style rules. |
| foundation-json-017 | jsondata-passthrough-when-already-strict | `try JSONCPreprocessor.jsonData(from: Data("42".utf8))`. | Returns `Data("42".utf8)` unchanged — the initial `.fragmentsAllowed` check accepts the top-level scalar and short-circuits before `jsonObject(from:)` would have rejected it. |
| foundation-json-018 | jsondata-passthrough-when-already-strict | `try JSONCPreprocessor.jsonData(from: Data(#"{"a":1e3}"#.utf8))`. | Returns the exact original bytes, byte-for-byte, including `1e3` — not a re-serialized `{"a":1000}` — because the passthrough check succeeds and no re-encode ever runs. |
| foundation-json-019 | jsondata-reencodes-when-not-strict | `try JSONCPreprocessor.jsonData(from: Data(#"{"a": 1, }"#.utf8))` (a trailing comma, so not strict JSON). | Returns re-serialized `Data` that `JSONSerialization.jsonObject(with:)` decodes to `["a": 1]` — the bytes differ from the input because the trailing comma forced the `jsonObject(from:)` + re-serialize path. |
| foundation-json-020 | jsondata-propagates-jsonobject-errors | `try JSONCPreprocessor.jsonData(from: Data(#"{"a": 1"#.utf8))` (unterminated, and not strict). | Throws — the failure originates in `jsonObject(from:)`'s fallback call and passes through `jsonData(from:)` unmodified. |
| foundation-json-021 | stateless-concurrency-safety | Issue fifty concurrent calls to `JSONCPreprocessor.strip` and `jsonObject(from:)`, each with a distinct input, from a `withTaskGroup` spanning multiple threads. | Every call returns the result matching its own input, with no cross-talk between calls — `candidateEncodings` is an immutable `let` and no other state exists to interleave. |
| foundation-json-022 | no-side-effects | Call `jsonObject(from:)` and `jsonData(from:)` with any valid JSONC `Data` in a test with no filesystem, network, or notification observers configured. | The call succeeds or throws based only on the bytes given it; no file is created, no request is issued, no notification is posted — confirmed by the source containing no `FileManager`, `URLSession`, `Process`, or `NotificationCenter` reference anywhere in its 118 lines. |
| foundation-json-023 | candidate-list-is-fixed | Attempt to write a call site passing an encoding list or a custom encoding to either public function. | Fails to compile — neither `jsonObject(from:)` nor `jsonData(from:)` declares a parameter for it. |

## Edge Cases

- **Null / empty input**: `strip("")` MUST return `""` — there is nothing for either scanner to act on. `jsonObject(from: Data())` MUST throw: the UTF-8 candidate decodes the empty bytes to `""`, which strips to `""` and fails to parse as JSON via `JSONSerialization`; every other candidate encoding either fails to decode zero bytes or produces the same empty, unparseable text, so the loop exhausts all six candidates and the final fallback call on the empty `Data` also throws, propagating to the caller — this is a MUST, since nothing in the source special-cases an empty payload.
- **Boundary values**: The scanners impose no maximum input length; `removingComments` and `removingTrailingCommas` each MUST make one linear pass over every character of `text` regardless of size, with no early exit and no configurable ceiling — a caller passing an arbitrarily large `Data` value MUST have every byte considered by both scanners. A document consisting of a single unmatched `"` (an opened-but-never-closed string) MUST leave both scanners in `inString == true` for the remainder of the text, meaning any `//`, `/*`, or trailing comma after that point MUST be preserved rather than treated as syntax, and the resulting document MUST then fail to parse (the mechanism is `block-comment-unterminated-consumes-rest`'s sibling case, not a separate one — the source draws no distinction between an unterminated string and an unterminated comment: both simply run to the end of the text).
- **Concurrent access**: Per `stateless-concurrency-safety`, `JSONCPreprocessor` MUST behave identically under any number of concurrent calls, since it holds no actor isolation and no mutable state of any kind — this is not a caveat but the direct consequence of being a caseless `enum` with one immutable `static let`.
- **Error states**: A document that fails to decode under every candidate encoding, or that decodes but fails to parse under every candidate after stripping, MUST cause `jsonObject(from:)` to throw the error `JSONSerialization.jsonObject(with: data)` raises for the caller's original, unmodified bytes (`jsonobject-fallback-on-raw-bytes`) — the source never wraps, annotates, or replaces that error with one of its own, and never returns a partial or best-effort result. `jsonData(from:)` MUST propagate that same error unchanged when its re-encode path is taken (`jsondata-propagates-jsonobject-errors`).
- **Offline / disconnected state**: Not applicable — `JSONCPreprocessor` performs no network I/O of any kind (`no-side-effects`); it operates only on the `text`/`data` parameter a caller already holds in memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` (parameter to `strip(_:)`) | `String` | none — required | The JSONC text to normalize into strict JSON text. |
| `data` (parameter to `jsonObject(from:)` and `jsonData(from:)`) | `Data` | none — required | The raw bytes of a JSONC or strict-JSON document, in any of the six candidate encodings. |

Neither public function reads an environment variable or a settings key, and neither accepts an injected dependency; every value the component operates on arrives as a call parameter, and the six-item `candidateEncodings` list is a fixed, non-configurable private constant (`candidate-list-is-fixed`).

## Deep Linking

Not applicable: `JSONCPreprocessor.swift` defines no URL scheme, route, or navigation destination — it transforms text and bytes, it does not navigate anywhere.

## Localization

Not applicable: `JSONCPreprocessor.swift` contains no user-facing string literal of its own — it never constructs an error message or display string; every error it surfaces is rethrown verbatim from `JSONSerialization`, unannotated.

## Accessibility Options

Not applicable: `JSONCPreprocessor.swift` presents no UI, so it responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: `JSONCPreprocessor.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `JSONCPreprocessor.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: `JSONCPreprocessor` defines no data field of its own — every byte and character it touches is the caller's `text`/`data` parameter, held only for the duration of one call. In this repository that data is a VS Code style configuration file: a color theme (`VSCodeThemeImporter`), a language snippet file (`SnippetFile`), or an extension's `package.json` manifest and `package.nls*.json` localization tables (`ExtensionManifestLocalization`, `ExtensionRegistry`, `VSIXInstaller`) — content an extension or theme author wrote, not a credential or access token.
- **Storage**: None — the component performs no read or write of its own; it returns a transformed value in memory and retains nothing once the call returns.
- **Transmission**: None — the component performs no network I/O of its own (`no-side-effects`).
- **Retention**: None — no state survives past the return of the call that produced it; there is no instance to hold anything between calls.

## Logging

Not applicable: `JSONCPreprocessor.swift` calls no `os_log`, `Logger`, `print`, or other logging API.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/JSON/JSONCPreprocessor.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). The file imports only `Foundation`; nothing in it is SwiftUI- or AppKit-specific, so a macOS or iOS host consumes it identically wherever it is built.
- **Compose**: There is no JSONC-aware parser in the Kotlin standard library or `kotlinx.serialization`. Port `removingComments`/`removingTrailingCommas` as hand-written scanner functions over a `CharSequence`, preserving the same in-string/escape tracking, then decode the result with `kotlinx.serialization.json.Json`. Port the six-candidate encoding loop with `Charsets.UTF_8`, `Charsets.UTF_16BE`, `Charsets.UTF_16LE`, and the UTF-32 equivalents obtained via `Charset.forName`, decoding with a `CharsetDecoder` configured `onMalformedInput(CodingErrorAction.REPORT)` so a bad candidate throws rather than silently substituting replacement characters — the behavior `String(data:encoding:)` gives for free by returning `nil`.
- **React/Web**: `jsonc-parser` — the library VS Code's own extension host uses — already implements this exact dialect; port by depending on its `parse`/`parseTree` functions rather than hand-rolling the scanner. There is no six-encoding ambiguity to resolve in a browser or Node environment: a `File`/`Blob`/`Buffer` decodes via an explicit or sniffed `TextDecoder` encoding, not tried six ways in sequence. The `jsonobject-rejects-top-level-fragments` / `jsondata-passthrough-when-already-strict` asymmetry has no natural analogue, since `JSON.parse` always accepts a top-level scalar; a port that wants to preserve the asymmetry must gate its two entry points deliberately rather than getting it from the underlying parser.
- **AppKit / UIKit**: Identical to the SwiftUI note — the source is UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract.
- **WinUI 3**: `System.Text.Json`'s `JsonDocumentOptions`/`JsonSerializerOptions` already expose `CommentHandling = JsonCommentHandling.Skip` and `AllowTrailingCommas = true` — a WinUI 3 port SHOULD set those options on `JsonDocument.Parse`/`JsonSerializer.Deserialize` instead of reimplementing `removingComments` and `removingTrailingCommas` as hand-written scanners, since the built-in options already provide the same string-aware comment and trailing-comma tolerance. Only the six-candidate encoding fallback needs its own port: try `Encoding.UTF8`, `Encoding.Unicode` (UTF-16LE), `Encoding.BigEndianUnicode` (UTF-16BE), and `Encoding.UTF32` plus its big-endian counterpart via `Encoding.GetEncoding(...)`, decoding with `Encoding.GetString` configured with a `DecoderExceptionFallback` (so a candidate that cannot decode throws a `DecoderFallbackException` instead of `Encoding.GetString`'s default silent substitution of replacement characters) to reproduce `String(data:encoding:)`'s nil-on-failure signal. `Windows.Storage`/`StorageFile` never enters this component at all — the byte source stays the caller's concern, exactly as it is in `JSONCPreprocessor` today.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/JSON/JSONCPreprocessor.swift` |

## Design Decisions

**Decision**: `jsonObject(from:)` never passes `.fragmentsAllowed` to any of its `JSONSerialization.jsonObject(with:)` calls, but `jsonData(from:)`'s own initial strict-JSON check does pass it.
**Rationale**: This creates an asymmetry a reader would not expect from the two functions' names alone: `jsonData(from: Data("42".utf8))` returns `Data("42".utf8)` unchanged (the fragments-allowed check accepts a bare top-level number), but `jsonObject(from: Data("42".utf8))` throws, and a JSONC document whose root is a scalar (e.g. `42 // comment`) fails through `jsonData(from:)` too, because its fallback is `jsonObject(from:)`, which never accepts a fragment. Nothing in the source comments this choice; it follows mechanically from `jsonData(from:)`'s passthrough check being written with `.fragmentsAllowed` and every other call site in the file omitting it.
**Approved**: pending

**Decision**: Candidate encodings are tried strictly in the order `.utf8`, `.utf16`, `.utf16BigEndian`, `.utf16LittleEndian`, `.utf32BigEndian`, `.utf32LittleEndian`, and the winner is the first candidate whose decoded text also *parses*, not merely decodes.
**Rationale**: Per the source's own comment, UTF-16 bytes for ASCII text also decode as UTF-8 (the interleaved NULs are valid UTF-8), and `.utf16` accepts any even-length payload as big-endian, so a "first that decodes" rule would let an earlier candidate silently swallow a later one's file and turn a good document into a syntax error. Requiring a successful *parse*, not just a successful *decode*, is what makes the fixed try-order safe.
**Approved**: pending

**Decision**: `jsonData(from:)` returns bytes that are already strict JSON completely unchanged, rather than always round-tripping through `jsonObject(from:)` and re-serializing.
**Rationale**: Per the source's own comment, a re-serialized document is not byte-identical to the one that came in — `1e3` comes back as `1000`, and key order can change — so a decoder that never sees the rewritten form cannot be surprised by it. Only a file the strict parser actually refuses pays the transform cost.
**Approved**: pending

**Decision**: `removingTrailingCommas` blanks a disqualified comma by overwriting it with a space character rather than removing it from the string.
**Rationale**: Per the source's own comment, overwriting keeps every remaining character offset valid while the single forward scan is still running; deleting the character would shift every subsequent index and require either a second pass or index-adjustment bookkeeping the current single-pass algorithm does not do.
**Approved**: pending

**Decision**: An unterminated `/* … */` block comment consumes the rest of the document with no recovery attempt, producing a downstream parse failure rather than a repaired document.
**Rationale**: The source makes no attempt to detect or recover from this case; `JSONCPreprocessorTests.unterminatedBlockComment`'s own test comment states the intent directly: "documenting the scanner's actual behaviour rather than wishing for recovery... that is the honest outcome for a file whose author left a comment open."
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |

Notes: `separation-of-concerns` passes because `JSONCPreprocessor` addresses exactly one concern — turning JSONC bytes/text into strict JSON — with no theme, snippet, extension-manifest, or presentation logic of its own; it was extracted from `VSCodeThemeImporter` specifically to keep that concern from being duplicated across readers. `unit-test-coverage` is partial: `JSONCPreprocessorTests.swift` exercises `strip(_:)` and `jsonObject(from:)` directly and thoroughly (comments, string-awareness, trailing commas, all encoding paths, BOM handling, pass-through, and both failure cases), but `jsonData(from:)` has no dedicated test anywhere in the repository — a repo-wide search of every `*Tests.swift` file finds no assertion that exercises it, direct or indirect, even though production code (`VSIXInstaller`) calls it. `explicit-error-handling` passes because every failure path rethrows the underlying `JSONSerialization` error unchanged, with no `try?`-and-swallow anywhere the final result is concerned — the internal `try?` calls exist only to test a candidate before committing to it, and each is followed by a final call that lets any real error surface. `fault-tolerance` passes because `jsonObject(from:)` and `jsonData(from:)` accept arbitrary caller-supplied bytes — malformed JSON, a document that is only a comment, an unrecognized encoding — and always resolve to either a valid result or a well-defined thrown error, never a crash. `unicode-support` passes because the component explicitly transcodes across six Unicode-capable encodings (UTF-8 and four UTF-16/UTF-32 byte-order variants) before falling back to the caller's raw bytes, and its character-level scanners (`removingComments`, `removingTrailingCommas`) operate on Swift `Character` (extended grapheme cluster) values, not raw code units, so multi-byte and combined Unicode characters inside string literals are never misinterpreted as ASCII punctuation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
