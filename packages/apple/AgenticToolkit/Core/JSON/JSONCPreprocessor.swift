//
//  JSONCPreprocessor.swift
//  AgenticToolkit
//

import Foundation

/// Reads JSONC — JSON with `//` and `/* … */` comments and trailing commas —
/// the dialect VS Code writes its own configuration files in.
///
/// A caseless namespace rather than a type: it holds no state, and both of its
/// callers want one function call, not an object. Lifted out of
/// `VSCodeThemeImporter`, whose private copy this was, when a second caller
/// appeared in another framework (`SnippetFile`, `AgenticToolkitLanguage`) —
/// two readers of the same dialect must not drift apart, and this is the
/// lowest tier that can hold a Foundation-only text transform with no theme,
/// snippet or extension concept in it.
public enum JSONCPreprocessor {

    // MARK: - Public API

    /// JSONC text with comments removed and trailing commas before `}` or `]`
    /// dropped — strict JSON, ready for `JSONSerialization`.
    ///
    /// Exposed alongside `jsonObject(from:)` because a caller that already has
    /// text should not have to re-encode it to bytes to get it stripped.
    public static func strip(_ text: String) -> String {
        removingTrailingCommas(removingComments(text))
    }

    /// The JSON object graph in `data`, decoded through the candidate
    /// encodings and the JSONC preprocessor.
    ///
    /// - Throws: whatever `JSONSerialization` throws for the *raw* bytes when
    ///   no candidate encoding yields a parseable document.
    public static func jsonObject(from data: Data) throws -> Any {
        // VS Code reads these files as JSONC; `JSONSerialization` does not, and the
        // preprocessor that closes that gap needs *text*. Transcoding is what keeps
        // JSONC support from depending on the file's encoding: handing raw UTF-16/32
        // bytes to `JSONSerialization` parses them, but only if they are strict JSON,
        // so a commented file would fail purely for not having been saved as UTF-8.
        //
        // First candidate that yields a parseable document wins, rather than first
        // that merely decodes: UTF-16 bytes for ASCII text also decode as UTF-8 (the
        // interleaved NULs are valid UTF-8), and `.utf16` accepts any even-length
        // payload as big-endian, so "decodes" alone would let an earlier candidate
        // swallow a later one's file and turn a good document into a syntax error.
        for encoding in candidateEncodings {
            guard var text = String(data: data, encoding: encoding) else { continue }
            // A BOM can survive decoding as U+FEFF, and `JSONSerialization` rejects
            // the document over it; VS Code's parser skips it.
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let stripped = strip(text)
            if let object = try? JSONSerialization.jsonObject(with: Data(stripped.utf8)) {
                return object
            }
        }
        // Nothing decoded into a parseable document. The raw bytes go to
        // `JSONSerialization` so the error describes the caller's actual file rather
        // than one of the transcodings attempted above.
        return try JSONSerialization.jsonObject(with: data)
    }

    /// The bytes in `data` as strict JSON a `JSONDecoder` will accept, with
    /// comments, trailing commas, a BOM and a non-UTF-8 encoding all taken
    /// out of the way first.
    ///
    /// The sibling of `jsonObject(from:)`, for the callers that want a
    /// `Decodable` rather than an object graph. Without it every such caller
    /// re-spells the round-trip — `jsonObject(from:)`, then
    /// `JSONSerialization.data(withJSONObject:)` — and the ones that do not
    /// bother stay on the strict decoder and reject files VS Code accepts.
    ///
    /// Bytes that are already strict JSON are handed back **unchanged** rather
    /// than round-tripped. That is not only a saved allocation: a re-serialised
    /// document is not byte-identical to the one that came in — `1e3` comes
    /// back as `1000`, key order changes — and a decoder that never has to see
    /// the rewritten form cannot be surprised by it. Only a file the strict
    /// parser refuses pays the transform.
    ///
    /// - Throws: whatever `JSONSerialization` throws for the raw bytes when no
    ///   candidate encoding yields a parseable document.
    public static func jsonData(from data: Data) throws -> Data {
        if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return data
        }
        let object = try jsonObject(from: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
    }

    // MARK: - Encodings

    /// The encodings a JSONC file can legally arrive in, in the order they are
    /// tried. UTF-8 is what every real file uses; the rest are legal JSON and
    /// cost one decode attempt each.
    private static let candidateEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16BigEndian,
        .utf16LittleEndian,
        .utf32BigEndian,
        .utf32LittleEndian
    ]

    // MARK: - Scanners

    /// Removes `//` and `/* … */` comments, leaving anything inside a string
    /// literal alone.
    ///
    /// String-awareness is the whole difficulty: a `$schema` value is an
    /// `https://…` URL, so a scanner that does not track quoting and backslash
    /// escapes truncates the document at the first one and reports a syntax
    /// error pointing nowhere near the problem.
    private static func removingComments(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" {
                    // Stop *at* the newline rather than past it, so the outer
                    // loop still emits it and line numbers survive.
                    index = next
                    while index < text.endIndex, !text[index].isNewline {
                        index = text.index(after: index)
                    }
                    continue
                }
                if next < text.endIndex, text[next] == "*" {
                    index = text.index(after: next)
                    while index < text.endIndex {
                        let closing = text.index(after: index)
                        if text[index] == "*", closing < text.endIndex, text[closing] == "/" {
                            index = text.index(after: closing)
                            break
                        }
                        index = text.index(after: index)
                    }
                    continue
                }
            }

            output.append(character)
            index = text.index(after: index)
        }

        return output
    }

    /// Blanks a comma that has nothing but whitespace between it and its closing
    /// `}` or `]`. Runs *after* comment removal, so `[1, /* stale */]` is caught
    /// too. Overwriting with a space rather than deleting keeps every remaining
    /// offset valid while the scan is still running.
    private static func removingTrailingCommas(_ text: String) -> String {
        var characters = Array(text)
        var inString = false
        var escaped = false
        var pendingComma: Int?

        for offset in characters.indices {
            let character = characters[offset]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                pendingComma = nil
            } else if character == "," {
                pendingComma = offset
            } else if character == "}" || character == "]" {
                if let comma = pendingComma { characters[comma] = " " }
                pendingComma = nil
            } else if !character.isWhitespace {
                pendingComma = nil
            }
        }

        return String(characters)
    }
}
