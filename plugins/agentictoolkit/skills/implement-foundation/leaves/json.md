<!-- leaf: implement-foundation/json · source: foundation-json.md -->

**Rules** (cite as `implement-foundation/json#<slug>`):

- `namespace-shape` MUST
- `no-side-effects` MUST
- `stateless-concurrency-safety` MUST
- `strip-comment-removal` MUST
- `strip-trailing-comma-removal` MUST
- `strip-string-awareness` MUST
- `line-comment-stops-at-newline` MUST
- `block-comment-unterminated-consumes-rest` MUST
- `jsonobject-tries-encodings-in-order` MUST
- `jsonobject-bom-stripped` MUST
- `jsonobject-first-parseable-candidate-wins` MUST
- `jsonobject-rejects-top-level-fragments` MUST
- `jsonobject-fallback-on-raw-bytes` MUST
- `jsondata-passthrough-when-already-strict` MUST
- `jsondata-reencodes-when-not-strict` MUST
- `jsondata-propagates-jsonobject-errors` MUST
- `candidate-list-is-fixed` MUST
- `winui-3` SHOULD — System.Text.Json's JsonDocumentOptions/JsonSerializerOptions already expose CommentHandling = JsonCommentHandling.Skip …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` (parameter to `strip(_:)`) | `String` | none — required | The JSONC text to normalize into strict JSON text. |
| `data` (parameter to `jsonObject(from:)` and `jsonData(from:)`) | `Data` | none — required | The raw bytes of a JSONC or strict-JSON document, in any of the six candidate encodings. |

Neither public function reads an environment variable or a settings key, and neither accepts an injected dependency; every value the component operates on arrives as a call parameter, and the six-item `candidateEncodings` list is a fixed, non-configurable private constant (`candidate-list-is-fixed`).

## Privacy

- **Data handled**: `JSONCPreprocessor` defines no data field of its own — every byte and character it touches is the caller's `text`/`data` parameter, held only for the duration of one call. In this repository that data is a VS Code style configuration file: a color theme (`VSCodeThemeImporter`), a language snippet file (`SnippetFile`), or an extension's `package.json` manifest and `package.nls*.json` localization tables (`ExtensionManifestLocalization`, `ExtensionRegistry`, `VSIXInstaller`) — content an extension or theme author wrote, not a credential or access token.
- **Storage**: None — the component performs no read or write of its own; it returns a transformed value in memory and retains nothing once the call returns.
- **Transmission**: None — the component performs no network I/O of its own (`no-side-effects`).
- **Retention**: None — no state survives past the return of the call that produced it; there is no instance to hold anything between calls.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/JSON/JSONCPreprocessor.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). The file imports only `Foundation`; nothing in it is SwiftUI- or AppKit-specific, so a macOS or iOS host consumes it identically wherever it is built.
- **Compose**: There is no JSONC-aware parser in the Kotlin standard library or `kotlinx.serialization`. Port `removingComments`/`removingTrailingCommas` as hand-written scanner functions over a `CharSequence`, preserving the same in-string/escape tracking, then decode the result with `kotlinx.serialization.json.Json`. Port the six-candidate encoding loop with `Charsets.UTF_8`, `Charsets.UTF_16BE`, `Charsets.UTF_16LE`, and the UTF-32 equivalents obtained via `Charset.forName`, decoding with a `CharsetDecoder` configured `onMalformedInput(CodingErrorAction.REPORT)` so a bad candidate throws rather than silently substituting replacement characters — the behavior `String(data:encoding:)` gives for free by returning `nil`.
- **React/Web**: `jsonc-parser` — the library VS Code's own extension host uses — already implements this exact dialect; port by depending on its `parse`/`parseTree` functions rather than hand-rolling the scanner. There is no six-encoding ambiguity to resolve in a browser or Node environment: a `File`/`Blob`/`Buffer` decodes via an explicit or sniffed `TextDecoder` encoding, not tried six ways in sequence. The `jsonobject-rejects-top-level-fragments` / `jsondata-passthrough-when-already-strict` asymmetry has no natural analogue, since `JSON.parse` always accepts a top-level scalar; a port that wants to preserve the asymmetry must gate its two entry points deliberately rather than getting it from the underlying parser.
- **AppKit / UIKit**: Identical to the SwiftUI note — the source is UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract.
- **WinUI 3**: `System.Text.Json`'s `JsonDocumentOptions`/`JsonSerializerOptions` already expose `CommentHandling = JsonCommentHandling.Skip` and `AllowTrailingCommas = true` — a WinUI 3 port SHOULD set those options on `JsonDocument.Parse`/`JsonSerializer.Deserialize` instead of reimplementing `removingComments` and `removingTrailingCommas` as hand-written scanners, since the built-in options already provide the same string-aware comment and trailing-comma tolerance. Only the six-candidate encoding fallback needs its own port: try `Encoding.UTF8`, `Encoding.Unicode` (UTF-16LE), `Encoding.BigEndianUnicode` (UTF-16BE), and `Encoding.UTF32` plus its big-endian counterpart via `Encoding.GetEncoding(...)`, decoding with `Encoding.GetString` configured with a `DecoderExceptionFallback` (so a candidate that cannot decode throws a `DecoderFallbackException` instead of `Encoding.GetString`'s default silent substitution of replacement characters) to reproduce `String(data:encoding:)`'s nil-on-failure signal. `Windows.Storage`/`StorageFile` never enters this component at all — the byte source stays the caller's concern, exactly as it is in `JSONCPreprocessor` today.

